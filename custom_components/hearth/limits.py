"""Groups and budgets (see docs/home-assistant-integration.md, Limits).

A budget is set on a group of apps and titles; a minute counts toward every group its app is in. Budgets (weekday and
weekend) and today's bonus are kept with Home Assistant's storage helper; the bonus and the "reached" marks start again
each local day.
"""

from __future__ import annotations

from dataclasses import dataclass, field
from datetime import date
import re
from typing import Any

from homeassistant.core import HomeAssistant
from homeassistant.helpers.storage import Store

from .counting import ALL

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

# Video apps Android doesn't mark as video, or that TVs and phones commonly have; an adult adds the rest
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


BUILTIN_GROUPS = (
    Group(ALL, "All screen time", builtin=True),
    Group(VIDEO, "Video", STARTER_VIDEO_APPS, "video", builtin=True),
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
        Group(g.id, g.name, g.apps | frozenset(added.get(g.id, [])), g.category, True, g.id not in outside)
        for g in BUILTIN_GROUPS
    ]
    for custom in options.get("groups", []):
        groups.append(
            Group(custom["id"], custom["name"], frozenset(custom.get("apps", [])), in_all=custom["id"] not in outside)
        )
    return groups


def groups_of(groups: list[Group], categories: dict[str, str], moved: dict[str, str] | None = None):
    """The function counting needs: an app's groups, from the lists and its category; where an adult moved it
    ([moved]: package -> group or "other") beats both."""
    ids = {g.id for g in groups}

    def of(item: str) -> set[str]:
        if moved and item in moved:
            return {ALL} | ({moved[item]} if moved[item] in ids and moved[item] != ALL else set())
        found = {ALL}
        category = categories.get(item)
        for group in groups:
            if item in group.apps or (group.category is not None and category == group.category):
                found.add(group.id)
        return found

    return of


def day_type(day: date) -> str:
    return "weekend" if day.weekday() >= 5 else "weekday"


@dataclass
class GroupState:
    counted_min: float
    budget_min: int | None
    bonus_min: int

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
        return GroupState(counted_min, self.budget(person, group, kind), self.bonus(person, group))
