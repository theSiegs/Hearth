"""Enforcing: when a person's group is out of time, the other parental controls hold its apps too.

Hearth's own devices are told in their state document (a TV or phone stops the group's apps itself). The household can
add, per person, the parental controls of other integrations (Configure > Enforce):

- Family Link (the HAFamilyLink integration): the group's Android apps are paused (familylink.pause_app: a 1 minute
  daily limit, the app stays installed) and resumed (resume_app puts back the setting they had). Google TV ignores app
  limits, which is why a TV is held by Hearth.
- Microsoft Family Safety: a platform (Xbox, Windows) is locked until midnight while one of the chosen groups (Games, All
  screen time) is out of time, and unlocked when it isn't.
- Nintendo Switch Parental Controls (built in): while one of the chosen groups (Games, All screen time) is out of time,
  the Switch's Max screentime today is set to 0 with Suspend software on, which suspends the game. Letting go puts back
  the limit and the Suspend software setting it had (kept with what's held). The limit is a setting of the Switch's (of
  every day, or of this weekday), not of today only, so it's put back before midnight.

What's held is kept with Home Assistant's storage helper, so only what Hearth held is let go, after a restart too. A
group gets time again (a bonus, a new day, a higher budget) and its apps are let go. Right after Home Assistant starts,
nothing is let go for a few minutes: the sources haven't all reported yet, and the counts would look low.

Another parental control is another kind here: what it holds, and the services that hold and let go.
"""

from __future__ import annotations

import asyncio
from dataclasses import dataclass, field
from datetime import datetime, timedelta
import logging
import math
from typing import TYPE_CHECKING, Any

from homeassistant.core import HomeAssistant, callback
from homeassistant.helpers import entity_registry as er
from homeassistant.helpers.storage import Store
from homeassistant.util import dt as dt_util

from .counting import ALL

if TYPE_CHECKING:
    from .household import PersonDay

_LOGGER = logging.getLogger(__name__)

CONF_ENFORCE = "enforce"
FAMILY_LINK = "family_link"
FAMILY_SAFETY = "family_safety"
NINTENDO = "nintendo"
KINDS = (FAMILY_LINK, FAMILY_SAFETY, NINTENDO)
PLATFORMS = ("Xbox", "Windows", "Mobile")
DEFAULT_FS_GROUPS = ("games", ALL)
DEFAULT_NINTENDO_GROUPS = ("games", ALL)
NINTENDO_DOMAIN = "nintendo_parental_controls"
# What a Nintendo enforcer holds: the person's Switch (its entity is the Switch's Max screentime today)
SWITCH = "Switch"
# A Switch's limit is put back this long before midnight: after it, "today" is another day's setting
NINTENDO_LET_GO_BEFORE_MIDNIGHT = timedelta(minutes=2)
NINTENDO_EACH_DAY = "each_day_of_the_week"
# Nothing is let go this long after Home Assistant starts (the sources report in first)
SETTLE = timedelta(minutes=5)
# A failed call is tried again after this long
RETRY = timedelta(minutes=5)
MAX_PACKAGES = 150

# Never paused, whatever group they're in: calls, texts, the system, and the apps that hold the rest
ESSENTIAL = frozenset(
    {
        "com.thesiegs.hearth",
        "com.thesiegs.hearth.mobile",
        "com.google.android.gms",
        "com.google.android.apps.messaging",
        "com.google.android.dialer",
        "com.google.android.contacts",
        "com.google.android.apps.kids.familylink",
        "com.google.android.apps.kids.familylinkhelper",
        "com.samsung.android.messaging",
        "com.samsung.android.dialer",
        "com.samsung.android.app.contacts",
        "com.android.settings",
        "com.android.vending",
    }
)


def essential(package: str) -> bool:
    return package in ESSENTIAL or package.startswith("com.android.") or package == "android"


@dataclass(frozen=True)
class Enforcer:
    """One parental control holding one person's apps."""

    kind: str
    person: str
    entity_id: str
    groups: tuple[str, ...] = ()
    platforms: tuple[str, ...] = ()

    @property
    def key(self) -> str:
        return f"{self.kind}|{self.person}"


def enforcers_from_options(options: dict[str, Any]) -> list[Enforcer]:
    found: list[Enforcer] = []
    for raw in options.get(CONF_ENFORCE, []):
        kind, person, entity_id = raw.get("kind"), raw.get("person"), raw.get("entity_id")
        if kind not in KINDS or not person or not entity_id:
            continue
        groups = tuple(raw.get("groups") or ())
        platforms = tuple(p for p in raw.get("platforms") or () if p in PLATFORMS)
        if kind == FAMILY_SAFETY:
            groups = groups or DEFAULT_FS_GROUPS
            platforms = platforms or ("Xbox",)
        elif kind == NINTENDO:
            groups = groups or DEFAULT_NINTENDO_GROUPS
        found.append(Enforcer(kind, person, entity_id, groups, platforms))
    return found


def out_of_time(day: PersonDay | None, groups: tuple[str, ...]) -> list[str]:
    """The person's groups (of [groups], or any) with no minutes left."""
    if day is None:
        return []
    return sorted(
        group_id
        for group_id, state in day.limits.items()
        if state.minutes_left == 0 and (not groups or group_id in groups)
    )


def wanted(enforcer: Enforcer, day: PersonDay | None, apps_of, now: datetime | None = None) -> set[str]:
    """What the enforcer should hold now: packages for Family Link, platforms for Family Safety, the Switch for
    Nintendo."""
    closed = out_of_time(day, enforcer.groups)
    if enforcer.kind == FAMILY_SAFETY:
        return set(enforcer.platforms) if closed else set()
    if enforcer.kind == NINTENDO:
        now = now or dt_util.now()
        late = dt_util.start_of_local_day(now + timedelta(days=1)) - now <= NINTENDO_LET_GO_BEFORE_MIDNIGHT
        return {SWITCH} if closed and not late else set()
    packages: set[str] = set()
    for group_id in closed:
        if group_id != ALL:
            packages |= {p for p in apps_of(group_id) if not essential(p)}
    return set(sorted(packages)[:MAX_PACKAGES])


@dataclass
class Held:
    items: set[str] = field(default_factory=set)
    entity_id: str | None = None
    error: str | None = None
    failed_at: datetime | None = None
    # What letting go puts back (a Switch's limit and Suspend software, as they were before the hold)
    restore: dict[str, Any] = field(default_factory=dict)


class Enforcement:
    """What each enforcer holds, brought in step with what it should (after every recompute, one run at a time)."""

    def __init__(self, hass: HomeAssistant, entry_id: str) -> None:
        self.hass = hass
        self._store: Store[dict[str, Any]] = Store(hass, 1, f"hearth.enforce.{entry_id}")
        self.held: dict[str, Held] = {}
        self.enforcers: list[Enforcer] = []
        self.started = dt_util.utcnow()
        self._wanted: dict[str, set[str]] = {}
        self._task: asyncio.Task | None = None
        self._again = False

    async def async_load(self) -> None:
        stored = await self._store.async_load() or {}
        for key, data in stored.get("held", {}).items():
            self.held[key] = Held(
                set(data.get("items", [])), data.get("entity_id"), restore=dict(data.get("restore") or {})
            )

    def _save(self) -> None:
        self._store.async_delay_save(self._data, 2)

    def _data(self) -> dict[str, Any]:
        return {
            "held": {
                key: {"items": sorted(h.items), "entity_id": h.entity_id, "restore": h.restore}
                for key, h in self.held.items()
                if h.items or h.restore
            }
        }

    async def async_flush(self) -> None:
        if self._task is not None and not self._task.done():
            self._task.cancel()
        await self._store.async_save(self._data())

    def held_for(self, person: str) -> dict[str, Any]:
        """A person's held things and the last error, for their sensor."""
        found: dict[str, Any] = {}
        for key, held in self.held.items():
            kind, who = key.split("|", 1)
            if who == person and (held.items or held.error):
                found[kind] = {"held": sorted(held.items), "error": held.error}
        return found

    @callback
    def update(self, enforcers: list[Enforcer], days: dict[str, PersonDay], apps_of) -> None:
        """[apps_of]: a group id's packages."""
        self.enforcers = enforcers
        now = dt_util.now()
        wanted_now = {e.key: wanted(e, days.get(e.person), apps_of, now) for e in enforcers}
        # What an enforcer no longer configured held is let go
        for key in self.held:
            wanted_now.setdefault(key, set())
        self._wanted = wanted_now
        if any(self._differs(key) for key in wanted_now):
            self._run()

    def _differs(self, key: str) -> bool:
        held = self.held.get(key) or Held()
        want = self._wanted.get(key, set())
        if want - held.items:
            return True
        return bool(_holding(held) - want) and self._may_let_go()

    def _may_let_go(self) -> bool:
        return dt_util.utcnow() - self.started >= SETTLE

    def _run(self) -> None:
        if self._task is not None and not self._task.done():
            self._again = True
            return
        self._task = self.hass.async_create_task(self._async_apply(), "hearth enforcement")

    async def _async_apply(self) -> None:
        self._again = False
        now = dt_util.utcnow()
        by_key = {e.key: e for e in self.enforcers}
        for key, want in list(self._wanted.items()):
            held = self.held.setdefault(key, Held())
            if held.failed_at and now - held.failed_at < RETRY:
                continue
            enforcer = by_key.get(key)
            kind, person = key.split("|", 1)
            entity_id = enforcer.entity_id if enforcer else held.entity_id
            hold = want - held.items
            let_go = _holding(held) - want if self._may_let_go() else set()
            if not (hold or let_go) or entity_id is None:
                continue
            # Kept before the calls: a half-done hold is let go through it if the enforcer is removed meanwhile
            held.entity_id = entity_id
            try:
                if let_go:
                    await self._call(kind, entity_id, let_go, False, held)
                    held.items -= let_go
                if hold:
                    await self._call(kind, entity_id, hold, True, held)
                    held.items |= hold
                held.error, held.failed_at = None, None
                self.hass.bus.async_fire(
                    "hearth_enforced",
                    {"person": person, "by": kind, "held": sorted(hold), "let_go": sorted(let_go)},
                )
            except Exception as err:  # noqa: BLE001 - one parental control failing mustn't stop the others
                _LOGGER.warning("Hearth couldn't %s for %s through %s: %s", "hold" if hold else "let go", person, kind, err)
                held.error, held.failed_at = str(err)[:200], now
            if not _holding(held) and not held.error and enforcer is None:
                self.held.pop(key, None)
            self._save()
        if self._again:
            self._run()

    async def _call(self, kind: str, entity_id: str, items: set[str], hold: bool, held: Held) -> None:
        if kind == NINTENDO:
            await (self._hold_switch(entity_id, held) if hold else self._let_go_switch(entity_id, held))
            return
        if kind == FAMILY_LINK:
            await self.hass.services.async_call(
                "familylink",
                "pause_app" if hold else "resume_app",
                {"entity_id": entity_id, "packages": sorted(items)},
                blocking=True,
            )
            return
        account = self._account_id(entity_id)
        for platform in sorted(items):
            if hold:
                await self.hass.services.async_call(
                    "microsoft_family_safety",
                    "lock_platform",
                    {"account_id": account, "platform": platform, "duration_hours": hours_to_midnight()},
                    blocking=True,
                )
            else:
                await self.hass.services.async_call(
                    "microsoft_family_safety",
                    "unlock_platform",
                    {"account_id": account, "platform": platform},
                    blocking=True,
                )

    def _account_id(self, entity_id: str) -> str:
        """The Family Safety account: the user_id of the person's account sensor (or the id itself, typed in)."""
        if "." not in entity_id:
            return entity_id
        state = self.hass.states.get(entity_id)
        account = state.attributes.get("user_id") if state else None
        if account in (None, ""):
            raise ValueError(f"{entity_id} has no user_id")
        return str(account)

    def _switch_entity(self, entity_id: str, domain: str, key: str) -> str | None:
        """Another entity of the Switch whose Max screentime today is [entity_id] (by its key: suspend_software)."""
        registry = er.async_get(self.hass)
        entry = registry.async_get(entity_id)
        if entry is not None and entry.device_id:
            for other in er.async_entries_for_device(registry, entry.device_id):
                if other.domain == domain and other.platform == NINTENDO_DOMAIN and other.unique_id.endswith(f"_{key}"):
                    return other.entity_id
        # Not in the registry (or renamed oddly): the id Home Assistant gives it from the Switch's name
        guess = f"{domain}.{entity_id.split('.', 1)[-1].removesuffix('_max_screentime_today')}_{key}"
        return guess if self.hass.states.get(guess) is not None else None

    async def _hold_switch(self, entity_id: str, held: Held) -> None:
        """Max screentime today to 0 with Suspend software on: the game is suspended. What they were is kept first
        (once: a retry after a half-done hold mustn't keep the 0)."""
        if not held.restore:
            state = self.hass.states.get(entity_id)
            limit = _number(state.state if state else None)
            if limit is None:
                raise ValueError(f"{entity_id} has no limit to keep")
            suspend = self._switch_entity(entity_id, "switch", "suspend_software")
            suspend_state = self.hass.states.get(suspend) if suspend else None
            held.restore = {
                "max": int(limit),
                "suspend": suspend,
                "suspend_was": suspend_state.state if suspend_state else None,
                "day": dt_util.now().date().isoformat(),
            }
            self._save()
        suspend = held.restore.get("suspend")
        if suspend and held.restore.get("suspend_was") != "on":
            await self.hass.services.async_call("switch", "turn_on", {"entity_id": suspend}, blocking=True)
        await self.hass.services.async_call(
            "number", "set_value", {"entity_id": entity_id, "value": 0}, blocking=True
        )

    async def _let_go_switch(self, entity_id: str, held: Held) -> None:
        """The limit and Suspend software back as they were. On a later day (Home Assistant was off over midnight),
        a Switch with a limit per weekday shows another day's now: that one is left alone, and said so."""
        restore = held.restore
        limit = restore.get("max", -1)
        mode = self._switch_entity(entity_id, "select", "timer_mode")
        mode_state = self.hass.states.get(mode) if mode else None
        if restore.get("day") not in (None, dt_util.now().date().isoformat()) and (
            mode_state is not None and mode_state.state == NINTENDO_EACH_DAY
        ):
            _LOGGER.warning(
                "Hearth held %s past midnight; its limit of %s minutes for %s wasn't put back (check it in the "
                "Nintendo app)", entity_id, limit, restore.get("day")
            )
        else:
            await self.hass.services.async_call(
                "number", "set_value", {"entity_id": entity_id, "value": limit}, blocking=True
            )
        suspend = restore.get("suspend")
        if suspend and restore.get("suspend_was") == "off":
            await self.hass.services.async_call("switch", "turn_off", {"entity_id": suspend}, blocking=True)
        held.restore = {}


def _holding(held: Held) -> set[str]:
    """What's held, with a Switch whose hold was started (its limit kept) but didn't finish."""
    return held.items | ({SWITCH} if held.restore else set())


def _number(value: Any) -> float | None:
    try:
        number = float(value)
    except (TypeError, ValueError):
        return None
    return number if number == number else None


def hours_to_midnight(now: datetime | None = None) -> int:
    """Whole hours until the next local midnight (at least 1): a lock that lasts the day, and ends with it."""
    now = now or dt_util.now()
    midnight = dt_util.start_of_local_day(now + timedelta(days=1))
    return max(1, min(24, math.ceil((midnight - now).total_seconds() / 3600)))
