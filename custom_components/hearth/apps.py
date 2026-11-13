"""New apps: every app the household's kids are given or start using, put in a group on its own.

The integration keeps a catalog of every app it has seen: from the screen time the devices report and from the app
lists the household chose to watch (Family Link's allowed apps, say). The first time it looks at a source (a device, a
list), everything already there is taken as known. After that, an app it hasn't seen before goes, with nobody asked,
to a group that lists it, else its category's group (its own category, else one a Glint phone sends from a shared
catalog), else Other; Hearth's page shows the ones sorted lately, and an adult moves one there (options "app_groups",
which beats every list and category).
"""

from __future__ import annotations

from dataclasses import dataclass
from typing import Any

from homeassistant.core import HomeAssistant
from homeassistant.helpers.storage import Store
from homeassistant.util import dt as dt_util

from .const import CONF_GROUP_APPS, CONF_GROUPS, DOMAIN
from .counting import ALL
from .limits import BUILTIN_GROUPS, GAMES, Group, one_pool_per_app, without_app

BUILTIN_IDS = frozenset(g.id for g in BUILTIN_GROUPS if g.id != ALL)

CONF_APP_WATCH = "app_watch"
CONF_ASK_NOTIFY = "ask_notify"
OTHER = "other"
EVENT_NEW_APP = "hearth_new_app"
ACTION_PREFIX = "HEARTH_APP|"
NOTIFICATION_ID = "hearth_new_apps"
MAX_APPS = 2000


@dataclass
class AppEntry:
    package: str
    name: str
    seen: str
    state: str  # "known" (there before), "new" (waiting for an adult), "sorted"
    group: str | None = None
    suggested: str | None = None
    who: str | None = None


def observed_from_entities(hass: HomeAssistant, entity_ids: list[str]) -> dict[str, tuple[str, str, str]]:
    """package -> (name, whose list it came from, the list), from sensors with an `apps` list of {package, name}."""
    found: dict[str, tuple[str, str, str]] = {}
    for entity_id in entity_ids:
        state = hass.states.get(entity_id)
        apps = state.attributes.get("apps") if state else None
        if not isinstance(apps, list):
            continue
        who = state.attributes.get("child_name") or state.name
        for app in apps[:500]:
            if isinstance(app, dict) and isinstance(app.get("package"), str) and app["package"]:
                package = app["package"][:128]
                found.setdefault(package, (str(app.get("name") or package)[:128], str(who)[:64], entity_id))
    return found


def suggest(package: str, category: str | None, groups: list[Group]) -> str | None:
    """A group for a new app: one that lists it already, else its Android category's."""
    for group in groups:
        if group.id != ALL and not group.builtin and package in group.apps:
            return group.id
    for group in groups:
        if group.builtin and group.id != ALL and package in group.apps:
            return group.id
    for group in groups:
        if group.category is not None and category == group.category:
            return group.id
    return None


class AppCatalog:
    def __init__(self, hass: HomeAssistant, entry_id: str) -> None:
        self.hass = hass
        self._store: Store[dict[str, Any]] = Store(hass, 1, f"hearth.apps.{entry_id}")
        self.apps: dict[str, AppEntry] = {}
        # Sources (devices, lists) looked at before: a source's first look is what it already had
        self.sources: set[str] = set()

    async def async_load(self) -> None:
        stored = await self._store.async_load() or {}
        self.sources = set(stored.get("sources", []))
        for package, data in stored.get("apps", {}).items():
            self.apps[package] = AppEntry(package=package, **data)

    def data(self) -> dict[str, Any]:
        return {
            "sources": sorted(self.sources),
            "apps": {p: {k: v for k, v in e.__dict__.items() if k != "package"} for p, e in self.apps.items()},
        }

    def _save(self) -> None:
        self._store.async_delay_save(self.data, 10)

    async def async_flush(self) -> None:
        await self._store.async_save(self.data())

    def new_apps(self) -> list[AppEntry]:
        return sorted((e for e in self.apps.values() if e.state == "new"), key=lambda e: e.seen)

    def observe(
        self,
        observed: dict[str, tuple[str, str, str]],
        categories: dict[str, str],
        groups: list[Group],
        sources: set[str],
    ) -> list[AppEntry]:
        """Notes the apps seen now in [sources]; answers the ones that are new (none from a source seen for the
        first time: those it had already)."""
        new_sources = sources - self.sources
        now = dt_util.utcnow().isoformat()
        fresh: list[AppEntry] = []
        for package, (name, who, source) in observed.items():
            first_look = source in new_sources
            entry = self.apps.get(package)
            if entry is not None:
                if entry.name == package and name != package:
                    entry.name = name
                continue
            if len(self.apps) >= MAX_APPS:
                break
            suggested = suggest(package, categories.get(package), groups)
            # Sorted on its own: nobody is asked (an adult moves it on Hearth's page if it's wrong)
            state = "known" if first_look else "auto"
            entry = AppEntry(package, name, now, state, suggested, suggested, who)
            self.apps[package] = entry
            if state == "auto":
                fresh.append(entry)
        if observed or new_sources:
            self.sources |= new_sources
            self._save()
        return fresh

    def sort(self, package: str, group: str) -> AppEntry | None:
        entry = self.apps.get(package)
        if entry is None:
            return None
        entry.state = "sorted"
        entry.group = None if group == OTHER else group
        self._save()
        return entry


def options_with_app_in_group(options: dict[str, Any], package: str, group_id: str) -> dict[str, Any]:
    """The options with [package] added to group [group_id]'s apps (the built-in groups keep theirs in group_apps),
    and out of every other group's list: an app is in one pool."""
    before = options
    options = dict(options)
    if group_id in BUILTIN_IDS:
        added = {k: list(v) for k, v in options.get(CONF_GROUP_APPS, {}).items()}
        if package not in added.setdefault(group_id, []):
            added[group_id].append(package)
        options[CONF_GROUP_APPS] = added
    else:
        groups = [dict(g, apps=list(g.get("apps", []))) for g in options.get(CONF_GROUPS, [])]
        for group in groups:
            if group["id"] == group_id and package not in group["apps"]:
                group["apps"].append(package)
        options[CONF_GROUPS] = groups
    return without_app(one_pool_per_app(before, options), package, keep=group_id)


def update_notification(hass: HomeAssistant, waiting: list[AppEntry], groups: list[Group]) -> None:
    """One notification in Home Assistant's bell listing the apps waiting to be sorted (gone when none are)."""
    from .attention import Item, attention

    if not waiting:
        attention(hass).clear(NOTIFICATION_ID, bell_too=True)
        return
    names = {g.id: g.name for g in groups}
    lines = [
        f"- **{e.name}**" + (f" ({e.who})" if e.who else "") + (f", suggested: {names.get(e.suggested, e.suggested)}" if e.suggested else "")
        for e in waiting[:20]
    ]
    attention(hass).notify(
        Item(
            NOTIFICATION_ID,
            "New apps to sort into a group:\n" + "\n".join(lines)
            + "\n\nSort them in [Hearth's options](/config/integrations/integration/" + DOMAIN + ") (Configure > Sort new apps).",
            title="Hearth: new apps",
            bell=True,
            phone=False,
        )
    )


def phone_actions(entry: AppEntry, groups: list[Group]) -> list[dict[str, str]]:
    """Up to three buttons for a phone notification: the suggestion, the likeliest other group, and Other. (A phone
    shows three at most; every group is a choice in the options' Sort new apps.)"""
    custom = [g.id for g in groups if not g.builtin]
    # One's own groups other than the YouTube one are the likeliest homes for an app that isn't a game
    preferred = [entry.suggested] + [g for g in custom if "youtube" not in g] + [GAMES] + custom
    choices: list[str] = []
    for candidate in preferred:
        if candidate and candidate not in choices and len(choices) < 2:
            choices.append(candidate)
    choices = choices[:2] + [OTHER]
    names = {g.id: g.name for g in groups} | {OTHER: "Other"}
    return [{"action": f"{ACTION_PREFIX}{c}|{entry.package}", "title": names.get(c, c)} for c in choices]
