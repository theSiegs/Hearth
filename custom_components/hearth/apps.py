"""New apps: every app the household's kids are given or start using, put in a group by an adult.

The integration keeps a catalog of every app it has seen: from the screen time the devices report and from the app
lists the household chose to watch (Family Link's allowed apps, say). The first time it looks at a source (a device, a
list), everything already there is taken as known. After that, an app it hasn't seen before is new: it's suggested a group (its Android category, or
a group that already lists it), and an adult is asked to sort it, in Home Assistant's notifications, on a phone if the
household chose one, and in the options (Sort new apps). Sorting it adds it to that group's apps.
"""

from __future__ import annotations

from dataclasses import dataclass
from typing import Any

from homeassistant.components import persistent_notification
from homeassistant.core import HomeAssistant
from homeassistant.helpers.storage import Store
from homeassistant.util import dt as dt_util

from .const import CONF_GROUP_APPS, CONF_GROUPS, DOMAIN
from .counting import ALL
from .limits import GAMES, VIDEO, Group

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
    if category == "game":
        return GAMES
    if category == "video":
        return VIDEO
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
            listed = any(package in g.apps for g in groups if not g.builtin)
            state = "known" if first_look else ("sorted" if listed else "new")
            entry = AppEntry(package, name, now, state, suggested if listed else None, suggested, who)
            self.apps[package] = entry
            if state == "new":
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
    """The options with [package] added to group [group_id]'s apps (Video and Games keep theirs in group_apps)."""
    options = dict(options)
    if group_id in (VIDEO, GAMES):
        added = {k: list(v) for k, v in options.get(CONF_GROUP_APPS, {}).items()}
        if package not in added.setdefault(group_id, []):
            added[group_id].append(package)
        options[CONF_GROUP_APPS] = added
        return options
    groups = [dict(g, apps=list(g.get("apps", []))) for g in options.get(CONF_GROUPS, [])]
    for group in groups:
        if group["id"] == group_id and package not in group["apps"]:
            group["apps"].append(package)
    options[CONF_GROUPS] = groups
    return options


def update_notification(hass: HomeAssistant, waiting: list[AppEntry], groups: list[Group]) -> None:
    """One notification in Home Assistant's bell listing the apps waiting to be sorted (gone when none are)."""
    if not waiting:
        persistent_notification.async_dismiss(hass, NOTIFICATION_ID)
        return
    names = {g.id: g.name for g in groups}
    lines = [
        f"- **{e.name}**" + (f" ({e.who})" if e.who else "") + (f", suggested: {names.get(e.suggested, e.suggested)}" if e.suggested else "")
        for e in waiting[:20]
    ]
    persistent_notification.async_create(
        hass,
        "New apps to sort into a group:\n" + "\n".join(lines)
        + "\n\nSort them in [Hearth's options](/config/integrations/integration/" + DOMAIN + ") (Configure > Sort new apps).",
        title="Hearth: new apps",
        notification_id=NOTIFICATION_ID,
    )


def phone_actions(entry: AppEntry, groups: list[Group]) -> list[dict[str, str]]:
    """Up to three buttons for a phone notification: the suggestion, the likeliest other group, and Other. (A phone
    shows three at most; every group is a choice in the options' Sort new apps.)"""
    custom = [g.id for g in groups if not g.builtin]
    # One's own groups other than the YouTube one are the likeliest homes for an app that isn't a game
    preferred = [entry.suggested] + [g for g in custom if "youtube" not in g] + [GAMES] + custom + [VIDEO]
    choices: list[str] = []
    for candidate in preferred:
        if candidate and candidate not in choices and len(choices) < 2:
            choices.append(candidate)
    choices = choices[:2] + [OTHER]
    names = {g.id: g.name for g in groups} | {OTHER: "Other"}
    return [{"action": f"{ACTION_PREFIX}{c}|{entry.package}", "title": names.get(c, c)} for c in choices]
