"""Groups and budgets (see docs/home-assistant-integration.md, Limits).

A budget is set on a group (a pool) of apps and titles. An app is in one pool at most besides All screen time, so the
pools' minutes and "other" (apps in no pool) add up to All's: where an adult moved it, else the pool whose list an adult
put it in, else a built-in starter list, else its Android category. Settings keep each app in one pool's list
(one_pool_per_app). Budgets (weekday and weekend) and today's bonus are kept with Home Assistant's storage helper; the
bonus and the "reached" marks start again each local day.

The built-in Video pool is retired (it held YouTube and the streaming apps alike, so their minutes counted twice):
retire_video moves an older household's options once, and logs what it did.
"""

from __future__ import annotations

from collections.abc import Callable
from dataclasses import dataclass, field
from datetime import date
import logging
import re
from typing import Any

from homeassistant.core import HomeAssistant
from homeassistant.helpers.storage import Store

from .const import CONF_GROUP_APPS, CONF_GROUPS
from .counting import ALL

_LOGGER = logging.getLogger(__name__)

# The retired built-in Video pool's id: an older household that budgeted it keeps a pool of its own by this id
VIDEO = "video"
GAMES = "games"
SOCIAL = "social"
MESSAGING = "messaging"
# Built-in groups outside All screen time unless an adult puts them in (options "inside_all"): chatting isn't screen
# time by default
DEFAULT_OUTSIDE_ALL = frozenset({MESSAGING})
# Options: {package: group id or "other"}: where an adult moved an app; beats every list and category
CONF_APP_GROUPS = "app_groups"
CONF_INSIDE_ALL = "inside_all"
CONF_OUTSIDE_ALL = "outside_all"
OTHER = "other"

STARTER_SOCIAL_APPS = frozenset(
    {
        "com.instagram.android",
        "com.instagram.barcelona",
        "com.zhiliaoapp.musically",
        "com.ss.android.ugc.trill",
        "com.snapchat.android",
        "com.facebook.katana",
        "com.facebook.lite",
        "com.reddit.frontpage",
        "com.pinterest",
        "com.twitter.android",
        "com.bereal.ft",
        "com.tumblr",
        "tv.twitch.android.app",
    }
)
STARTER_MESSAGING_APPS = frozenset(
    {
        "com.whatsapp",
        "com.facebook.orca",
        "org.telegram.messenger",
        "org.thoughtcrime.securesms",
        "com.discord",
        "com.google.android.apps.messaging",
        "com.samsung.android.messaging",
        "com.google.android.apps.dynamite",
        "com.microsoft.teams",
        "jp.naver.line.android",
        "com.viber.voip",
        "kik.android",
    }
)

# The retired Video pool's starter list (retire_video): video apps Android doesn't mark as video, or that TVs and phones
# commonly have
STARTER_VIDEO_APPS = frozenset(
    {
        "com.thesiegs.hearthtube",
        "com.thesiegs.hearthtube.mobile",
        "com.google.android.youtube",
        "com.google.android.youtube.tv",
        "com.google.android.apps.youtube.kids",
        "com.netflix.ninja",
        "com.netflix.mediaclient",
        "com.disney.disneyplus",
        "com.wbd.stream",
        "com.hulu.livingroomplus",
        "com.hulu.plus",
        "com.amazon.amazonvideo.livingroom",
        "com.amazon.avod.thirdpartyclient",
        "com.cbs.ott",
        "com.cbs.app",
        "com.peacocktv.peacockandroid",
        "com.apple.atve.androidtv.appletv",
        "com.apple.atve.amazon.appletv",
        "com.tubitv",
        "tv.pluto.android",
    }
)

# The two budgets: on school days ("weekday", its stored name from before school days) and on other days ("weekend")
DAY_TYPES = ("weekday", "weekend")
SCHOOL_DAY = "weekday"
OTHER_DAY = "weekend"


@dataclass(frozen=True)
class Group:
    id: str
    name: str
    apps: frozenset[str] = frozenset()
    # Apps whose Android category is this are in it too ("video", "game")
    category: str | None = None
    builtin: bool = False
    # Its time counts in All screen time, and its apps are held when that runs out (off: music, say)
    in_all: bool = True
    # Of [apps], the ones from a built-in starter list (the rest an adult put there): an adult's list wins over these
    starter: frozenset[str] = frozenset()


BUILTIN_GROUPS = (
    Group(ALL, "All screen time", builtin=True),
    Group(GAMES, "Games", frozenset(), "game", builtin=True),
    Group(SOCIAL, "Social", STARTER_SOCIAL_APPS, "social", builtin=True),
    Group(MESSAGING, "Messaging", STARTER_MESSAGING_APPS, "messaging", builtin=True),
)


def slug(name: str) -> str:
    return re.sub(r"[^a-z0-9]+", "_", name.lower()).strip("_")[:32] or "group"


def groups_from_options(options: dict[str, Any]) -> list[Group]:
    """The built-in groups (with apps an adult added to them) and the adult's own groups."""
    added: dict[str, list[str]] = options.get("group_apps", {})
    outside = (set(options.get("outside_all", [])) | (DEFAULT_OUTSIDE_ALL - set(options.get(CONF_INSIDE_ALL, [])))) - {ALL}
    groups = [
        Group(g.id, g.name, g.apps | frozenset(added.get(g.id, [])), g.category, True, g.id not in outside, g.apps)
        for g in BUILTIN_GROUPS
    ]
    for custom in options.get("groups", []):
        groups.append(
            Group(
                custom["id"],
                custom["name"],
                frozenset(custom.get("apps", [])),
                # Only the pool retire_video kept has one: the apps Android marks as video, as the old Video pool had
                custom.get("category"),
                in_all=custom["id"] not in outside,
            )
        )
    return groups


def groups_of(
    groups: list[Group],
    categories: dict[str, str],
    moved: dict[str, str] | None = None,
    **resolver: Any,
):
    """The function counting needs: an app's groups, All and at most one pool (placer's answer)."""
    place = placer(groups, categories, moved, **resolver)

    def of(item: str) -> set[str]:
        pool = place(item).pool
        return {ALL, pool} if pool else {ALL}

    return of


# Options: {catalog value: pool id or "other"}: an adult's own map from what the shared catalog (or the device) says an
# app is to a pool; the rest come from pool_map's defaults
CONF_CATALOG_POOLS = "catalog_pools"
# The values a pool map knows: the shared catalog's finer values (`detail`) and the ten categories
DETAIL_VALUES = ("youtube", "streaming", "education", "companion", "system")
CATEGORY_VALUES = ("game", "video", "audio", "image", "social", "messaging", "news", "maps", "productivity", "accessibility")
# The category each finer value sits under (glint.catalog/1)
DETAIL_CATEGORY = {"youtube": "video", "streaming": "video", "education": "productivity", "companion": "productivity",
                   "system": "productivity"}
# Pools of an adult's own, found by name, for the finer values' defaults
_DEFAULT_NAMES = {
    "youtube": ("youtube",),
    "streaming": ("streaming", "tv", "shows"),
    "audio": ("music", "audio"),
    "education": ("homework", "school", "education", "learning"),
}


def pool_map(groups: list[Group], adult: dict[str, str] | None = None) -> dict[str, str]:
    """What each value the shared catalog or a device says an app is goes to in this household: a pool id, or "other"
    (no pool). Hearth's defaults: a game to Games, social to Social, messaging to Messaging, a value a pool claims by its
    category (the Video pool retire_video kept) to it, YouTube, streaming, music and education to a pool of the
    household's own of that name (YouTube; Streaming or TV; Music; Homework or School) when there is one, companion apps
    (a platform's hub or store) and system apps never to a pool; an adult's own map ([adult]) beats them. A value
    missing from the map goes to no pool."""
    ids = {g.id for g in groups if g.id != ALL}
    out: dict[str, str] = {}
    for g in groups:
        if g.id != ALL and g.category is not None:
            out.setdefault(g.category, g.id)
    for value, pool in (("game", GAMES), ("social", SOCIAL), ("messaging", MESSAGING)):
        if pool in ids:
            out.setdefault(value, pool)
    own = {**{slug(g.name): g.id for g in groups if not g.builtin}, **{g.id: g.id for g in groups if not g.builtin}}
    for value, names in _DEFAULT_NAMES.items():
        found = next((own[n] for n in names if n in own), None)
        if found is not None:
            out.setdefault(value, found)
    out.setdefault("education", OTHER)
    out.setdefault("companion", OTHER)
    out.setdefault("system", OTHER)
    for value, pool in (adult or {}).items():
        if pool == OTHER or pool in ids:
            out[value] = pool
    return out


def catalog_value(pools: dict[str, str], pool: str) -> dict[str, str] | None:
    """What an adult's move to [pool] says the app is, in the catalog's terms ({category, detail?}), for sharing a
    correction: the first value the household's map sends there; None for Other or a pool no value goes to."""
    if pool == OTHER:
        return None
    for value in (*DETAIL_VALUES, *CATEGORY_VALUES):
        if pools.get(value) == pool:
            if value in DETAIL_CATEGORY:
                return {"category": DETAIL_CATEGORY[value], "detail": value}
            return {"category": value}
    return None


@dataclass(frozen=True)
class Placement:
    """Where an item counts, and why."""

    # A pool's id, or None: Other (All screen time only)
    pool: str | None
    # moved (an adult's move), list (a list an adult keeps), starter (Hearth's curated lists), catalog (the shared
    # catalog, confirmed), declared (the device's own category, or a Glint phone's copy of the catalog), suggested (the
    # shared catalog, suggested), hint (where its time came from: a Switch's are games), other
    why: str
    # What the catalog or the device says it is (a detail or a category)
    value: str | None = None
    # The catalog's confirmed answer and the device's disagree on whether it's a game
    disagree: bool = False
    declared: str | None = None


def placer(
    groups: list[Group],
    categories: dict[str, str],
    moved: dict[str, str] | None = None,
    *,
    catalog: Callable[[str], Any] | None = None,
    pools: dict[str, str] | None = None,
    hints: dict[str, set[str]] | None = None,
) -> Callable[[str], Placement]:
    """Where an item counts: the first of these that answers, each in the groups' order.

    1. Where an adult moved it ([moved]: item -> pool or "other").
    2. A list an adult keeps it in.
    3. Hearth's curated (starter) lists.
    4. The shared catalog's confirmed answer ([catalog]: item -> catalog.Hit or None), by the household's map
       ([pools], pool_map's); a confirmed value the map sends to no pool is Other, and stops here.
    5. The device's own category ([categories]; a Glint phone's copy of the catalog is below the device's).
    6. The shared catalog's suggested answer, only when it goes to a pool (a guess never takes an app out of one).
    7. Where its time came from ([hints]: a Switch's or an Xbox's titles are games).
    8. Other.
    """
    ids = {g.id for g in groups}
    pools_list = [g for g in groups if g.id != ALL]
    order = [g.id for g in pools_list]
    value_pools = pools if pools is not None else pool_map(groups)

    def to_pool(value: str | None) -> str | None:
        pool = value_pools.get(value) if value else None
        return pool if pool in ids and pool != ALL else None

    def of(item: str) -> Placement:
        if moved and item in moved:
            target = moved[item]
            return Placement(target if target in ids and target != ALL else None, "moved")
        found = next((g for g in pools_list if item in g.apps and item not in g.starter), None)
        if found:
            return Placement(found.id, "list")
        found = next((g for g in pools_list if item in g.starter), None)
        if found:
            return Placement(found.id, "starter")
        declared = categories.get(item)
        hit = catalog(item) if catalog is not None else None
        if hit is not None and hit.confirmed:
            # Read the finer value first, then the category
            value = hit.detail if hit.detail in value_pools else hit.category
            disagree = declared is not None and (declared == "game") != (hit.category == "game")
            return Placement(to_pool(value), "catalog", hit.value, disagree, declared)
        if (pool := to_pool(declared)) is not None:
            return Placement(pool, "declared", declared, declared=declared)
        if hit is not None:
            value = hit.detail if hit.detail in value_pools else hit.category
            if (pool := to_pool(value)) is not None:
                return Placement(pool, "suggested", hit.value, declared=declared)
        hinted = sorted((hints or {}).get(item, set()) & set(order), key=order.index)
        if hinted:
            return Placement(hinted[0], "hint")
        return Placement(None, "other")

    return of


def pool_lists(options: dict[str, Any]) -> list[tuple[str, list[str]]]:
    """Every list an adult keeps apps in, as (pool id, packages): the built-in pools' additions, then their own pools."""
    return [(gid, list(apps or [])) for gid, apps in (options.get(CONF_GROUP_APPS) or {}).items()] + [
        (g["id"], list(g.get("apps") or [])) for g in options.get(CONF_GROUPS) or []
    ]


def one_pool_per_app(before: dict[str, Any], after: dict[str, Any]) -> dict[str, Any]:
    """[after] (options an adult just saved) with each app in one pool's list: the list it was just put in wins (else
    the first list holding it) and it leaves the others; where an adult had moved it ("app_groups") follows its new
    list. [before] is the options as they were."""
    had = {(gid, app) for gid, apps in pool_lists(before) for app in apps}
    holders: dict[str, list[str]] = {}
    for gid, apps in pool_lists(after):
        for app in apps:
            if gid not in holders.setdefault(app, []):
                holders[app].append(gid)
    winner = {app: ([g for g in gids if (g, app) not in had] or gids)[0] for app, gids in holders.items()}
    out = dict(after)
    if CONF_GROUP_APPS in after:
        out[CONF_GROUP_APPS] = {
            gid: [a for a in apps or [] if winner.get(a) == gid] for gid, apps in (after[CONF_GROUP_APPS] or {}).items()
        }
    if CONF_GROUPS in after:
        out[CONF_GROUPS] = [
            {**g, "apps": [a for a in g.get("apps") or [] if winner.get(a) == g["id"]]} for g in after[CONF_GROUPS] or []
        ]
    moved = dict(after.get(CONF_APP_GROUPS) or {})
    newly = {app for app, gid in winner.items() if (gid, app) not in had}
    if any(moved.get(app, winner[app]) != winner[app] for app in newly):
        out[CONF_APP_GROUPS] = {a: g for a, g in moved.items() if a not in newly or g == winner[a]}
    return out


def without_app(options: dict[str, Any], package: str, keep: str | None = None) -> dict[str, Any]:
    """[options] with [package] out of every pool's list but [keep]'s (an adult moved it there)."""
    if not any(package in apps for gid, apps in pool_lists(options) if gid != keep):
        return dict(options)
    out = dict(options)
    if CONF_GROUP_APPS in options:
        out[CONF_GROUP_APPS] = {
            gid: [a for a in apps or [] if a != package or gid == keep]
            for gid, apps in (options[CONF_GROUP_APPS] or {}).items()
        }
    if CONF_GROUPS in options:
        out[CONF_GROUPS] = [
            {**g, "apps": [a for a in g.get("apps") or [] if a != package or g["id"] == keep]}
            for g in options[CONF_GROUPS] or []
        ]
    return out


# Options: 2 once the pools are one per app and the built-in Video pool is gone (retire_video)
CONF_POOLS = "pools"
POOLS_VERSION = 2


def retire_video(options: dict[str, Any], budgets: dict[str, dict[str, dict[str, int | None]]]) -> dict[str, Any] | None:
    """The options without the built-in Video pool, once (None: done already). A household that budgeted Video for
    someone, or moved an app to it, keeps a pool of its own by the same id and name, so its budgets, bonuses, pauses and
    history stay: it holds the starter list and the apps an adult added, less any app another pool of theirs lists (one
    pool per app), and the apps Android marks as video. Otherwise Video goes, with the apps an adult added to it: they
    count in All screen time only until put in a pool. Logged either way; the lists are made one pool per app too."""
    if options.get(CONF_POOLS, 1) >= POOLS_VERSION:
        return None
    added = {gid: list(apps or []) for gid, apps in (options.get(CONF_GROUP_APPS) or {}).items()}
    video_added = added.pop(VIDEO, [])
    customs = [dict(g) for g in options.get(CONF_GROUPS) or []]
    moved = dict(options.get(CONF_APP_GROUPS) or {})
    out = {**options, CONF_POOLS: POOLS_VERSION}
    if CONF_GROUP_APPS in options:
        out[CONF_GROUP_APPS] = added
    budgeted = sorted(
        person for person, groups in budgets.items() if any(m is not None for m in (groups.get(VIDEO) or {}).values())
    )
    moved_here = sorted(a for a, g in moved.items() if g == VIDEO)
    if any(g.get("id") == VIDEO for g in customs):
        # A pool of their own by that id already: it stays as it is
        _LOGGER.info("Hearth: the built-in Video pool is retired; the pool of your own called %r stays", VIDEO)
    elif budgeted or moved_here:
        others = (
            {a for g in customs for a in g.get("apps") or []}
            | {a for apps in added.values() for a in apps}
            | {a for a, g in moved.items() if g != VIDEO}
        )
        wanted = STARTER_VIDEO_APPS | set(video_added)
        apps = sorted(wanted - others)
        out[CONF_GROUPS] = [*customs, {"id": VIDEO, "name": "Video", "apps": apps, "category": "video"}]
        _LOGGER.warning(
            "Hearth: the built-in Video pool is retired (each app now counts in one pool). %s, so it stays as a pool of "
            "your own, \"Video\", with %d apps and the apps Android marks as video; %d apps another pool lists stay "
            "there. Remove it in Hearth's settings once YouTube and streaming have pools of their own",
            f"Video had a budget for {', '.join(budgeted)}" if budgeted else "Apps were moved to Video",
            len(apps),
            len(wanted & others),
        )
    else:
        _LOGGER.info(
            "Hearth: the built-in Video pool is retired (each app now counts in one pool); nobody had a Video budget%s",
            f", and the apps added to it ({', '.join(sorted(video_added))}) count in All screen time until put in a pool"
            if video_added
            else "",
        )
        if VIDEO in (options.get(CONF_OUTSIDE_ALL) or []):
            out[CONF_OUTSIDE_ALL] = [g for g in options[CONF_OUTSIDE_ALL] if g != VIDEO]
        if CONF_INSIDE_ALL in options:
            out[CONF_INSIDE_ALL] = [g for g in options[CONF_INSIDE_ALL] if g != VIDEO]
    # Lists that held an app twice keep it in the first (nothing is "just put" in a list here)
    return one_pool_per_app(out, out)


def day_type(day: date) -> str:
    return "weekend" if day.weekday() >= 5 else "weekday"


@dataclass
class GroupState:
    counted_min: float
    budget_min: int | None
    # Today's bonus: an adult's (set_bonus) and chores' together
    bonus_min: int
    # Of which chores earned today (todos.py)
    bonus_chores: int = 0

    @property
    def minutes_left(self) -> int | None:
        if self.budget_min is None:
            return None
        return max(0, int(self.budget_min + self.bonus_min - self.counted_min))


MAX_BONUS = 24 * 60


@dataclass
class LimitsData:
    # person -> group -> {"weekday": minutes | None, "weekend": minutes | None}
    budgets: dict[str, dict[str, dict[str, int | None]]] = field(default_factory=dict)
    # Today's: the day they're for, person -> group -> minutes
    day: str | None = None
    bonus: dict[str, dict[str, int]] = field(default_factory=dict)
    reached: dict[str, list[str]] = field(default_factory=dict)
    # A TV's own rules taken (or passed over) once per "device_id:profile_id" (Household.import_local_rules)
    imported: list[str] = field(default_factory=list)


# A TV's own rules name their groups all, games and youtube (ScreenTimeRules on the TV)
TV_GROUP_ALIASES: dict[str, tuple[str, ...]] = {"youtube": ("youtube", "video")}


class Limits:
    """The household's budgets and today's bonuses, kept across restarts."""

    def __init__(self, hass: HomeAssistant, entry_id: str) -> None:
        self._store: Store[dict[str, Any]] = Store(hass, 1, f"hearth.limits.{entry_id}")
        self.data = LimitsData()
        # (person, group) -> the minutes chores earned today (todos.ChoreBook.minutes_today), folded into the bonus
        self.chore_minutes: Callable[[str, str], int] | None = None

    async def async_load(self) -> None:
        stored = await self._store.async_load() or {}
        self.data = LimitsData(
            budgets=stored.get("budgets", {}),
            day=stored.get("day"),
            bonus=stored.get("bonus", {}),
            reached=stored.get("reached", {}),
            imported=stored.get("imported", []),
        )

    def _save(self) -> None:
        self._store.async_delay_save(
            lambda: {
                "budgets": self.data.budgets,
                "day": self.data.day,
                "bonus": self.data.bonus,
                "reached": self.data.reached,
                "imported": self.data.imported,
            },
            5,
        )

    async def async_flush(self) -> None:
        await self._store.async_save(
            {
                "budgets": self.data.budgets,
                "day": self.data.day,
                "bonus": self.data.bonus,
                "reached": self.data.reached,
                "imported": self.data.imported,
            }
        )

    def new_day(self, today: date) -> bool:
        """Starts today's bonus and marks afresh when the day changed; says whether it did."""
        if self.data.day == today.isoformat():
            return False
        self.data.day = today.isoformat()
        self.data.bonus = {}
        self.data.reached = {}
        self._save()
        return True

    def budget(self, person: str, group: str, kind: str) -> int | None:
        return self.data.budgets.get(person, {}).get(group, {}).get(kind)

    def set_budget(self, person: str, group: str, kind: str, minutes: int | None) -> None:
        self.data.budgets.setdefault(person, {}).setdefault(group, {})[kind] = minutes
        self._save()

    def take_rules(self, key: str, person: str, budgets: dict[str, dict[str, int]], groups: set[str]) -> bool:
        """A TV's own rules for one of its profiles ([key]: "device_id:profile_id"), mapped to [person]: they become
        the person's budgets when the person has none yet, once per key. The TV's YouTube group goes to Home Assistant's
        YouTube group, else Video; a group Home Assistant has nothing like is left out. Says whether any budget was set."""
        if key in self.data.imported:
            return False
        self.data.imported.append(key)
        taken = False
        if not any(m is not None for g in self.data.budgets.get(person, {}).values() for m in g.values()):
            for tv_group, kinds in budgets.items():
                # The TV's YouTube group is Home Assistant's own YouTube group when it has one, else Video (which
                # holds YouTube and HearthTube); other groups match by id
                group = next((g for g in TV_GROUP_ALIASES.get(tv_group, (tv_group,)) if g in groups), None)
                if group is None or group in self.data.budgets.get(person, {}):
                    continue
                for kind, minutes in kinds.items():
                    if kind in DAY_TYPES:
                        self.data.budgets.setdefault(person, {}).setdefault(group, {})[kind] = minutes
                        taken = True
        self._save()
        return taken

    def bonus(self, person: str, group: str) -> int:
        return self.data.bonus.get(person, {}).get(group, 0)

    def set_bonus(self, person: str, group: str, minutes: int) -> None:
        # Negative takes time away today (down to none left; minutes_left never goes below 0)
        self.data.bonus.setdefault(person, {})[group] = max(-MAX_BONUS, min(MAX_BONUS, minutes))
        self._save()

    def mark_reached(self, person: str, group: str) -> bool:
        """Notes that the person's group reached 0 today; False if it was noted already."""
        marks = self.data.reached.setdefault(person, [])
        if group in marks:
            return False
        marks.append(group)
        self._save()
        return True

    def clear_reached(self, person: str, group: str) -> None:
        """A bonus reopened the group: reaching 0 again fires again."""
        marks = self.data.reached.get(person, [])
        if group in marks:
            marks.remove(group)
            self._save()

    def state(self, person: str, group: str, counted_min: float, kind: str) -> GroupState:
        """The group's state today, with the budget for [kind] of day (SCHOOL_DAY or OTHER_DAY)."""
        chores = max(0, self.chore_minutes(person, group)) if self.chore_minutes else 0
        bonus = max(-MAX_BONUS, min(MAX_BONUS, self.bonus(person, group) + chores))
        return GroupState(counted_min, self.budget(person, group, kind), bonus, chores)
