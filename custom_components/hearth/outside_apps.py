"""App limits loosened outside Hearth: the adults are told (docs/home-assistant-integration.md, Outside app changes).

Each parental-controls provider's app lists for a kid (or a console) are compared with what they were at the last
look. A change that gives an app more room, made by someone other than Hearth, goes to every adult's phone:

- an app unblocked (it left the blocked apps and is still installed);
- an app's time limit raised, or taken off (still installed and not blocked);
- an app made Always allowed (Family Link), or put on a console's allow list (Nintendo: it then starts whatever its
  age rating).

The providers, each read the same way into {installed, blocked, limits, paused, always, names}:
- Family Link: the kid's app list sensors (Blocked, With time limits, Without limits, Always allowed). Block again
  runs hearth.block_app.
- Family Safety: the kid's Applications sensor (Windows and Xbox apps, each blocked or with a limit).
- Nintendo: each of the kid's Switches' applications and allow list (list_applications, read from the integration's
  last poll, no call to Nintendo), looked at every NINTENDO_EVERY; the allow list is the console's, so it is told once
  for the console.

The providers can't say who made a change: a parent in their app, or anyone holding a parent's phone. Hearth's own
writes are told apart by its action log (activity.py): a call of the provider's that names the same app in the last
OWN_WINDOW is Hearth's. Apps Hearth pauses (paused_apps) are left out of the limit comparison, before and after.
Tightening (a block, a lower limit) is never told.

Nothing is told on the first look (there is nothing to compare with), nor while a list is missing or cut short.
The last look is stored, so a change made while Home Assistant was down is told at the first look after.
"""

from __future__ import annotations

import logging
import re
from dataclasses import dataclass
from datetime import datetime, timedelta
from typing import TYPE_CHECKING, Any

from homeassistant.core import HomeAssistant, callback
from homeassistant.helpers import entity_registry as er
from homeassistant.helpers.storage import Store
from homeassistant.util import dt as dt_util

from . import family_link as fl
from .activity import call_service
from .attention import ADULTS, NOTICE, Action, Item
from .const import DOMAIN
from .entry_tasks import entry_task

if TYPE_CHECKING:
    from .household import Household

_LOGGER = logging.getLogger(__name__)

EVENT = "hearth_outside_app_change"
# Activity record kind for a change told
OUTSIDE = "outside_app_change"
# A call of the provider's naming the same app this recently made the change
OWN_WINDOW = timedelta(minutes=30)
# Nintendo's allow list is read through a service: at most this often
NINTENDO_EVERY = timedelta(minutes=10)

FS_DOMAIN = "microsoft_family_safety"
NINTENDO_DOMAIN = "nintendo_parental_controls"

UNBLOCKED = "unblocked"
LIMIT_RAISED = "limit_raised"
LIMIT_REMOVED = "limit_removed"
ALWAYS_ALLOWED = "always_allowed"


@dataclass
class Look:
    """One provider's app lists for a kid or a console, at one look."""

    # What the last look is stored under: "<person>|family_link", "<person>|fs:<sensor>", "nintendo:<device id>"
    key: str
    person: str
    provider: str  # "Family Link", "Family Safety", "Nintendo"
    lists: dict[str, Any]
    # The provider's calls that change an app (Hearth's own, when they name it)
    own_services: frozenset[str]
    # "on <the console>" for a console's list
    where: str | None = None
    # The words for an app put on the always list, and the button that takes it off
    always_words: str = "was made Always allowed"
    undo_always: str = "Block"


def _empty() -> dict[str, Any]:
    return {"installed": set(), "blocked": set(), "limits": {}, "paused": set(), "always": set(), "names": {}}


def read_family_link(hass: HomeAssistant, child: str) -> dict[str, Any] | None:
    """The child's Family Link app lists, or None when one is missing or cut short."""
    found = _empty()
    seen: set[str] = set()
    for suffix, state in fl._child_lists(hass, child):
        apps = fl._apps_of(state)
        if not isinstance(apps, list) or state.attributes.get("truncated"):
            return None
        seen.add(suffix)
        for app in apps:
            package = app.get("package") if isinstance(app, dict) else app
            if not isinstance(package, str) or not package:
                continue
            found["installed"].add(package)
            if isinstance(app, dict) and isinstance(app.get("name"), str) and app["name"]:
                found["names"][package] = app["name"]
            if suffix == "_blocked_apps":
                found["blocked"].add(package)
            elif suffix == "_always_allowed_apps":
                found["always"].add(package)
            elif suffix == "_apps_with_time_limits" and isinstance(app, dict) and app.get("enabled", True):
                minutes = app.get("limit_minutes")
                if isinstance(minutes, (int, float)):
                    found["limits"][package] = int(minutes)
        if suffix == "_apps_with_time_limits":
            found["paused"] |= _paused(state.attributes.get("paused_apps"))
    return found if seen == set(fl.INSTALLED_LISTS) else None


def read_family_safety(attrs: dict[str, Any]) -> dict[str, Any] | None:
    """A Family Safety Applications sensor's apps (Windows and Xbox), or None without its list."""
    applications = attrs.get("applications")
    if not isinstance(applications, list) or attrs.get("truncated"):
        return None
    found = _empty()
    for app in applications:
        if not isinstance(app, dict) or not isinstance(app_id := app.get("app_id"), str) or not app_id:
            continue
        found["installed"].add(app_id)
        if isinstance(app.get("app_name"), str) and app["app_name"]:
            found["names"][app_id] = app["app_name"]
        if app.get("blocked"):
            found["blocked"].add(app_id)
        minutes = app.get("limit_minutes")
        if app.get("limit_enabled", True) and isinstance(minutes, (int, float)):
            found["limits"][app_id] = int(minutes)
    found["paused"] = _paused(attrs.get("paused_apps"))
    return found


def read_nintendo(response: dict[str, Any] | None) -> dict[str, Any] | None:
    """A Switch's applications (list_applications): the allowed ones as its always list."""
    applications = (response or {}).get("applications")
    if not isinstance(applications, list):
        return None
    found = _empty()
    for app in applications:
        if not isinstance(app, dict) or not (app_id := app.get("application_id")):
            continue
        app_id = str(app_id)
        found["installed"].add(app_id)
        if isinstance(app.get("name"), str) and app["name"]:
            found["names"][app_id] = app["name"]
        if app.get("allowed"):
            found["always"].add(app_id)
    return found


def _paused(rows: Any) -> set[str]:
    out: set[str] = set()
    for row in rows or []:
        package = row.get("package") if isinstance(row, dict) else row
        if isinstance(package, str) and package:
            out.add(package)
    return out


def changes(before: dict[str, Any], now: dict[str, Any]) -> list[tuple[str, str, Any, Any]]:
    """What gives an app more room between two looks: [(change, app, before, after)]."""
    found: list[tuple[str, str, Any, Any]] = []
    installed = now["installed"]
    blocked_before, blocked_now = set(before.get("blocked", ())), now["blocked"]
    for package in sorted(blocked_before - blocked_now):
        if package in installed:
            found.append((UNBLOCKED, package, "blocked", "limited" if package in now["limits"] else "allowed"))
    paused = set(before.get("paused", ())) | now["paused"]
    limits_before: dict[str, int] = before.get("limits", {})
    for package, minutes in sorted(limits_before.items()):
        if package in paused or package in blocked_now or package in blocked_before:
            continue
        after = now["limits"].get(package)
        if after is None:
            if package in installed:
                found.append((LIMIT_REMOVED, package, minutes, None))
        elif after > minutes:
            found.append((LIMIT_RAISED, package, minutes, after))
    for package in sorted(now["always"] - set(before.get("always", ()))):
        found.append((ALWAYS_ALLOWED, package, None, None))
    return found


def _snapshot(lists: dict[str, Any]) -> dict[str, Any]:
    held = lists["blocked"] | set(lists["limits"]) | lists["always"]
    return {
        "blocked": sorted(lists["blocked"]),
        "limits": dict(sorted(lists["limits"].items())),
        "paused": sorted(lists["paused"]),
        "always": sorted(lists["always"]),
        # The names of the apps held (an unblocked app's name may be only on the blocked list)
        "names": {p: n for p, n in sorted(lists["names"].items()) if p in held},
    }


class OutsideAppChanges:
    """Each provider's app lists at the last look, and the notices for what loosened since."""

    def __init__(self, hass: HomeAssistant, household: Household, entry_id: str) -> None:
        self.hass = hass
        self.household = household
        self._entry_id = entry_id
        self._store: Store[dict[str, Any]] = Store(hass, 1, f"hearth.outside_apps.{entry_id}")
        self.last: dict[str, dict[str, Any]] = {}
        self._nintendo_at: datetime | None = None
        self._nintendo_task = None

    async def async_load(self) -> None:
        stored = await self._store.async_load() or {}
        # Keys are "<person>|<provider>" or "nintendo:<device>"; anything else is an older layout's, looked at again
        self.last = {
            k: v for k, v in (stored.get("last") or {}).items() if isinstance(v, dict) and ("|" in k or ":" in k)
        }

    def _save(self) -> None:
        self._store.async_delay_save(lambda: {"last": self.last}, 5)

    async def async_flush(self) -> None:
        await self._store.async_save({"last": self.last})

    # Reading

    def _kids(self) -> list[str]:
        return self.household.blocks.kids()

    def _looks(self) -> list[Look]:
        """Family Link's and Family Safety's lists for each kid, as their entities say now."""
        looks: list[Look] = []
        registry = er.async_get(self.hass)
        for person in self._kids():
            target = self.household.blocks.target_of(person)
            if target is not None and (lists := read_family_link(self.hass, target[1])) is not None:
                looks.append(
                    Look(
                        f"{person}|family_link", person, "Family Link", lists,
                        frozenset({"familylink.block_app", "familylink.unblock_app", "familylink.pause_app",
                                   "familylink.resume_app", "familylink.set_app_daily_limit"}),
                    )
                )
            for entity_id in self._fs_applications(person, registry):
                state = self.hass.states.get(entity_id)
                if state is not None and (lists := read_family_safety(dict(state.attributes))) is not None:
                    looks.append(
                        Look(
                            f"{person}|fs:{entity_id}", person, "Family Safety", lists,
                            frozenset({f"{FS_DOMAIN}.pause_app", f"{FS_DOMAIN}.resume_app", f"{FS_DOMAIN}.pause_apps",
                                       f"{FS_DOMAIN}.block_app", f"{FS_DOMAIN}.unblock_app"}),
                        )
                    )
        return looks

    def blocked_elsewhere(self, person: str, app: str) -> list[dict[str, Any]]:
        """hearth.explain's blocked_by for a block made in Family Link or Family Safety, not by Hearth (a parent's own,
        in their app): no allow of Hearth's lifts it. Hearth's own block is told by app_blocks.explain instead."""
        found: list[dict[str, Any]] = []
        blocks = self.household.blocks
        if app in blocks.blocked_packages(person) and not blocks.why_blocked(person, app):
            found.append({"kind": "blocked_app", "by": "family_link", "provider": "Family Link", "app": app,
                          "why": ["parent"], "until": None})
        for entity_id in self._fs_applications(person, er.async_get(self.hass)):
            state = self.hass.states.get(entity_id)
            lists = read_family_safety(dict(state.attributes)) if state is not None else None
            if lists is not None and app in lists["blocked"]:
                found.append({"kind": "blocked_app", "by": entity_id, "provider": "Family Safety", "app": app,
                              "why": ["parent"], "until": None})
        return found

    def _fs_applications(self, person: str, registry: er.EntityRegistry) -> list[str]:
        """The kid's Family Safety Applications sensors: on the device of an enforcer's entity, or naming its
        account (user_id)."""
        from .enforce import FAMILY_SAFETY, fs_account_of

        devices: set[str] = set()
        accounts: set[str] = set()
        for enforcer in self.household.enforcement.enforcers:
            if enforcer.person != person or enforcer.kind != FAMILY_SAFETY:
                continue
            entry = registry.async_get(enforcer.entity_id)
            if entry is not None and entry.device_id:
                devices.add(entry.device_id)
            if account := fs_account_of(self.hass, enforcer.entity_id):
                accounts.add(str(account))
        if not devices and not accounts:
            return []
        found: list[str] = []
        for state in self.hass.states.async_all("sensor"):
            if not isinstance(state.attributes.get("applications"), list):
                continue
            entry = registry.async_get(state.entity_id)
            mine = str(state.attributes.get("user_id")) in accounts or (
                entry is not None and entry.platform == FS_DOMAIN and entry.device_id in devices
            )
            if mine:
                found.append(state.entity_id)
        return sorted(found)

    async def _nintendo_looks(self) -> list[Look]:
        """Each kid's Switches' applications and allow list (one look per console, under its first kid)."""
        from . import nintendo

        looks: list[Look] = []
        if not self.hass.services.has_service(NINTENDO_DOMAIN, nintendo.LIST_APPS):
            return looks
        done: set[str] = set()
        for person in self._kids():
            for switch in nintendo.switches(self.household, person):
                device_id = switch["device_id"]
                if device_id in done:
                    continue
                done.add(device_id)
                try:
                    response = await call_service(
                        self.hass, NINTENDO_DOMAIN, nintendo.LIST_APPS, {"device_id": device_id}, blocking=True,
                        return_response=True, person=person, why="outside_apps",
                    )
                except Exception as err:  # noqa: BLE001 - a console that can't be read is looked at next time
                    _LOGGER.debug("outside apps: couldn't list %s's applications: %s", switch["name"], err)
                    continue
                if (lists := read_nintendo(response)) is not None:
                    looks.append(
                        Look(
                            f"nintendo:{device_id}", person, "Nintendo", lists,
                            frozenset({f"{NINTENDO_DOMAIN}.set_app_allowed"}),
                            where=f"on {switch['name']}",
                            always_words="was put on the allow list (it starts whatever its age rating)",
                            undo_always="Take off allow list",
                        )
                    )
        return looks

    # The button

    async def async_block(self, source: str, app: str, context: Any = None) -> dict[str, Any]:
        """Puts an app told about back under a block, in the provider it changed in: Hearth's own block in Family Link
        (hearth.block_app's), Family Safety's block_app, or off the Switch's allow list. Only an app of a list Hearth
        looks at."""
        before = self.last.get(source)
        if before is None or not isinstance(app, str) or not app:
            raise ValueError("Hearth doesn't look at that list")
        person, _, provider = source.partition("|")
        if source.startswith("nintendo:"):
            device_id = source.removeprefix("nintendo:")
            if app not in before.get("always", []):
                raise ValueError("That game isn't on the allow list")
            await call_service(
                self.hass, NINTENDO_DOMAIN, "set_app_allowed",
                {"device_id": device_id, "application_id": app, "allowed": False}, blocking=True, context=context,
                why="outside_apps",
            )
            return {"blocked": app, "provider": "Nintendo"}
        if person not in self._kids():
            raise ValueError("Not a kid's list")
        if provider == "family_link":
            from .app_blocks import android_package, never_blocked

            if not android_package(app) or never_blocked(app):
                raise ValueError("Hearth doesn't block that app")
            if not self.household.blocks.block([person], [app]):
                raise ValueError("Hearth couldn't block that app")
            self.household.recompute()
            return {"blocked": app, "provider": "Family Link"}
        if provider.startswith("fs:"):
            await call_service(
                self.hass, FS_DOMAIN, "block_app", {"entity_id": provider.removeprefix("fs:"), "app_id": app},
                blocking=True, context=context, person=person, why="outside_apps",
            )
            return {"blocked": app, "provider": "Family Safety"}
        raise ValueError("Hearth doesn't look at that list")

    # Comparing

    def _hearths(self, look: Look, app: str) -> bool:
        """Hearth itself called the provider about this app just now."""
        activity = getattr(self.household, "activity", None)
        if activity is None:
            return False
        for record in activity.query(kind="call", since=dt_util.utcnow() - OWN_WINDOW, limit=1000):
            if record.get("service") not in look.own_services:
                continue
            args = record.get("args") or {}
            named = {args.get("package_name"), args.get("app"), args.get("application_id")}
            listed = set(args.get("packages") or []) | set(args.get("apps") or [])
            if app in named or app in listed:
                return True
        return False

    def _compare(self, looks: list[Look]) -> None:
        dirty = False
        for look in looks:
            snapshot = _snapshot(look.lists)
            before = self.last.get(look.key)
            if before == snapshot:
                continue
            if before is not None:
                for change, app, was, now in changes(before, look.lists):
                    if self._hearths(look, app):
                        continue
                    name = look.lists["names"].get(app) or (before.get("names") or {}).get(app)
                    if not name and look.provider == "Family Link":
                        name = self.household.blocks.name_of(app, look.person)
                    self._tell(look, change, app, name or app, was, now)
            self.last[look.key] = snapshot
            dirty = True
        if dirty:
            self._save()

    @callback
    def check(self) -> None:
        """Family Link and Family Safety now (their entities); Nintendo when it's due (a service call)."""
        self._compare(self._looks())
        now = dt_util.utcnow()
        due = self._nintendo_at is None or now - self._nintendo_at >= NINTENDO_EVERY
        if due and (self._nintendo_task is None or self._nintendo_task.done()):
            self._nintendo_at = now
            self._nintendo_task = entry_task(self.hass, self._entry_id, self._async_nintendo(), "hearth outside apps")

    async def _async_nintendo(self) -> None:
        self._compare(await self._nintendo_looks())

    # Telling

    def _tell(self, look: Look, change: str, app: str, name: str, was: Any, now: Any) -> None:
        person = look.person
        what = {
            UNBLOCKED: "was unblocked",
            LIMIT_RAISED: f"time limit went from {was} to {now} minutes",
            LIMIT_REMOVED: f"time limit ({was} minutes) was taken off",
            ALWAYS_ALLOWED: look.always_words,
        }[change]
        local = dt_util.as_local(dt_util.utcnow())
        at = f"{local.hour % 12 or 12}:{local.minute:02d} {'AM' if local.hour < 12 else 'PM'}"
        owner = "'s" if change in (LIMIT_RAISED, LIMIT_REMOVED) else ""
        where = f" {look.where}" if look.where else ""
        text = f"{name}{owner} {what}{where} in {look.provider}, not by Hearth ({at})."
        _LOGGER.info("%s: %s %s in %s outside Hearth (%s -> %s)", look.key, app, change, look.provider, was, now)
        self.hass.bus.async_fire(
            EVENT,
            {"person": person, "provider": look.provider, "app": app, "change": change, "before": was, "after": now},
        )
        activity = getattr(self.household, "activity", None)
        if activity is not None:
            activity.add(OUTSIDE, person=person, target=[app], reason=change, by=look.provider)
        attention = getattr(self.household.hub, "attention", None)
        if attention is None:
            return
        # One button for every provider: hearth.block_outside_app puts the app back under a block
        label = {UNBLOCKED: "Block again", ALWAYS_ALLOWED: look.undo_always}.get(change, "Block")
        actions = (Action("block", label, f"{DOMAIN}.block_outside_app", {"source": look.key, "app": app}),)
        who = look.where[3:] if look.where else self.household.person_name(person)
        headline = {
            UNBLOCKED: "unblocked",
            LIMIT_RAISED: "limit raised",
            LIMIT_REMOVED: "limit taken off",
            ALWAYS_ALLOWED: "allowed" if look.where else "always allowed",
        }[change]
        attention.notify(
            Item(
                # Only letters, digits, dots and underscores: a phone button sends the key between "|"s
                re.sub(r"[^A-Za-z0-9._]", "_", f"outside_app_{look.key}_{app}"),
                text,
                title=f"{who}: {name} {headline}",
                urgency=NOTICE,
                audience=ADULTS,
                actions=actions,
                about={"person": person},
                once=True,
            )
        )
