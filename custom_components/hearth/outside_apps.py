"""App limits loosened outside Hearth: the adults are told (docs/home-assistant-integration.md, Outside app changes).

Each kid's Family Link app lists are compared with what they were at the last look. A change that gives an app more
room, made by someone other than Hearth, goes to every adult's phone:

- an app unblocked (it left Blocked apps and is still installed), with a "Block again" button (hearth.block_app);
- an app's time limit raised, or taken off (it left Apps with time limits, still installed and not blocked);
- an app made Always allowed.

Family Link can't say who made a change: a parent in the Family Link app, or anyone holding a parent's phone. Hearth's
own writes are told apart by its action log (activity.py): a familylink call for the same kid and app in the last
OWN_WINDOW is Hearth's. Apps Hearth pauses (paused_apps: pause_app holds them with a 1-minute limit and resume_app
puts back the saved one) are left out of the limit comparison, before and after. Tightening (a block, a lower limit)
is never told.

Nothing is told on the first look (there is nothing to compare with), nor while a list is missing or cut short.
The last look is stored, so a change made while Home Assistant was down is told at the first look after.
"""

from __future__ import annotations

from datetime import timedelta
import logging
from typing import TYPE_CHECKING, Any

from homeassistant.core import HomeAssistant, callback
from homeassistant.helpers.storage import Store
from homeassistant.util import dt as dt_util

from . import family_link as fl
from .attention import ADULTS, NOTICE, Action, Item

if TYPE_CHECKING:
    from .household import Household

_LOGGER = logging.getLogger(__name__)

EVENT = "hearth_outside_app_change"
# Activity record kind for a change told
OUTSIDE = "outside_app_change"
# A familylink call of Hearth's for the same kid and app this recently made the change
OWN_WINDOW = timedelta(minutes=30)
OWN_SERVICES = frozenset(
    {"familylink.block_app", "familylink.unblock_app", "familylink.pause_app", "familylink.resume_app"}
)

UNBLOCKED = "unblocked"
LIMIT_RAISED = "limit_raised"
LIMIT_REMOVED = "limit_removed"
ALWAYS_ALLOWED = "always_allowed"


def read_lists(hass: HomeAssistant, child: str) -> dict[str, Any] | None:
    """The child's app lists now: {blocked, limits: {package: minutes}, paused, always, names}, or None when one is
    missing or cut short."""
    found: dict[str, Any] = {
        "installed": set(), "blocked": set(), "limits": {}, "paused": set(), "always": set(), "names": {}
    }
    seen: set[str] = set()
    for suffix, state in fl._child_lists(hass, child):  # noqa: SLF001 - the module's own list reader
        apps = fl._apps_of(state)  # noqa: SLF001
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
            found["paused"] |= {
                str(p.get("package")) for p in state.attributes.get("paused_apps") or [] if isinstance(p, dict)
            }
    if seen != set(fl.INSTALLED_LISTS):
        return None
    return found


def changes(before: dict[str, Any], now: dict[str, Any]) -> list[tuple[str, str, Any, Any]]:
    """What gives an app more room between two looks: [(change, package, before, after)]."""
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
    return {
        "blocked": sorted(lists["blocked"]),
        "limits": dict(sorted(lists["limits"].items())),
        "paused": sorted(lists["paused"]),
        "always": sorted(lists["always"]),
        # The names of the apps held (an unblocked app's name is only on the Blocked list)
        "names": {
            p: n for p, n in sorted(lists["names"].items())
            if p in lists["blocked"] or p in lists["limits"] or p in lists["always"]
        },
    }


class OutsideAppChanges:
    """Each kid's app lists at the last look, and the notices for what loosened since."""

    def __init__(self, hass: HomeAssistant, household: Household, entry_id: str) -> None:
        self.hass = hass
        self.household = household
        self._store: Store[dict[str, Any]] = Store(hass, 1, f"hearth.outside_apps.{entry_id}")
        self.last: dict[str, dict[str, Any]] = {}

    async def async_load(self) -> None:
        stored = await self._store.async_load() or {}
        self.last = {p: v for p, v in (stored.get("last") or {}).items() if isinstance(v, dict)}

    def _save(self) -> None:
        self._store.async_delay_save(lambda: {"last": self.last}, 5)

    async def async_flush(self) -> None:
        await self._store.async_save({"last": self.last})

    def _hearths(self, person: str, package: str) -> bool:
        """Hearth itself called Family Link for this kid and app just now."""
        activity = getattr(self.household, "activity", None)
        if activity is None:
            return False
        for record in activity.query(person=person, kind="call", since=dt_util.utcnow() - OWN_WINDOW, limit=500):
            if record.get("service") not in OWN_SERVICES:
                continue
            args = record.get("args") or {}
            named = args.get("package_name") or args.get("app")
            packages = args.get("packages") or args.get("apps") or []
            if named == package or package in packages:
                return True
        return False

    @callback
    def check(self) -> None:
        blocks = self.household.blocks
        dirty = False
        for person in blocks.kids():
            target = blocks.target_of(person)
            if target is None:
                continue
            lists = read_lists(self.hass, target[1])
            if lists is None:
                continue
            snapshot = _snapshot(lists)
            before = self.last.get(person)
            if before == snapshot:
                continue
            if before is not None:
                for change, package, was, now in changes(before, lists):
                    if self._hearths(person, package):
                        continue
                    name = lists["names"].get(package) or (before.get("names") or {}).get(package)
                    self._tell(person, change, package, name or blocks.name_of(package, person), was, now)
            self.last[person] = snapshot
            dirty = True
        if dirty:
            self._save()

    def _tell(self, person: str, change: str, package: str, name: str, was: Any, now: Any) -> None:
        who = self.household.person_name(person)
        what = {
            UNBLOCKED: "was unblocked",
            LIMIT_RAISED: f"time limit went from {was} to {now} minutes",
            LIMIT_REMOVED: f"time limit ({was} minutes) was taken off",
            ALWAYS_ALLOWED: "was made Always allowed",
        }[change]
        local = dt_util.as_local(dt_util.utcnow())
        at = f"{local.hour % 12 or 12}:{local.minute:02d} {'AM' if local.hour < 12 else 'PM'}"
        owner = "'s" if change in (LIMIT_RAISED, LIMIT_REMOVED) else ""
        text = f"{name}{owner} {what} in Family Link, not by Hearth ({at})."
        _LOGGER.info("%s: %s %s outside Hearth (%s -> %s)", person, package, change, was, now)
        self.hass.bus.async_fire(EVENT, {"person": person, "app": package, "change": change, "before": was, "after": now})
        activity = getattr(self.household, "activity", None)
        if activity is not None:
            activity.add(OUTSIDE, person=person, target=[package], reason=change)
        attention = getattr(self.household.hub, "attention", None)
        if attention is None:
            return
        actions: tuple[Action, ...] = ()
        if change in (UNBLOCKED, ALWAYS_ALLOWED, LIMIT_REMOVED):
            actions = (Action("block", "Block again" if change == UNBLOCKED else "Block", "hearth.block_app",
                              {"people": [person], "app": package}),)
        attention.notify(
            Item(
                f"outside_app_{person}_{package}",
                text,
                title=f"{who}: {name} {'unblocked' if change == UNBLOCKED else 'limit changed'}"
                if change != ALWAYS_ALLOWED else f"{who}: {name} always allowed",
                urgency=NOTICE,
                audience=ADULTS,
                actions=actions,
                about={"person": person},
                once=True,
            )
        )
