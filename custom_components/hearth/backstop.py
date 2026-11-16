"""Family Link's daily limit as a backstop (docs/home-assistant-integration.md, Family Link backstop).

Hearth's own holds are the real limit. Family Link's per-device daily limit is kept a little above them, so a phone
whose Hearth companion is off, or a device Hearth can't see, still stops near the end of the day:

    daily limit = daily time + bonus time left + raised limits of categories outside daily time + margin

rounded up to 5 minutes, at most a day (time_model.backstop_minutes). The margin is 30 minutes by default (Configure >
Enforce). With limits paused (hearth.pause_limits) it is a whole day, and back to the sum when the pause ends. A kid
with no daily time in Hearth is left alone.

- Written only when the value changes (and again after Hearth's own whole-device hold let go, which puts back the
  weekday's limit), through familylink.set_daily_limit with the child's id alone: today's override on each device of the
  child that takes a daily limit (Family Link skips Google TVs). The child's id is read from the entity's attributes
  and passed as a string, never templated (Home Assistant would read its 21 digits as a number).
- Nothing is written while Hearth holds the child's devices (daily time used up: enforce.py sets the limit to 0), nor
  when daily time is used up and that hold is about to start.
- A parent's change: the override is today's only, and Hearth writes it each day, so the backstop wins over a weekday
  limit a parent changed in the Family Link app (and over a today's limit they set, at the next change of Hearth's
  numbers). Switch the backstop off to keep Family Link's own limits.
- Every grant of bonus time also adds a Family Link bonus where the device would stop sooner (native_sync.mirror_bonus).
"""

from __future__ import annotations

from datetime import datetime, timedelta
import logging
from typing import TYPE_CHECKING, Any

from homeassistant.core import HomeAssistant, callback
from homeassistant.helpers.storage import Store
from homeassistant.util import dt as dt_util

from .counting import ALL
from .enforce import FAMILY_LINK
from .entry_tasks import entry_task
from .time_model import BACKSTOP_MARGIN, backstop_minutes

if TYPE_CHECKING:
    from .household import Household

_LOGGER = logging.getLogger(__name__)

FL_DOMAIN = "familylink"
# Options (Configure > Enforce): the backstop on (default) or off, and its margin in minutes
CONF_FL_BACKSTOP = "fl_backstop"
CONF_FL_BACKSTOP_MARGIN = "fl_backstop_margin"
RETRY = timedelta(minutes=5)


class Backstop:
    """Each kid's Family Link daily limit, kept at Hearth's numbers plus a margin."""

    def __init__(self, hass: HomeAssistant, household: Household, entry_id: str) -> None:
        self.hass = hass
        self.household = household
        self._entry_id = entry_id
        self._store: Store[dict[str, Any]] = Store(hass, 1, f"hearth.backstop.{entry_id}")
        # By person: {"day", "minutes", "at"}: what Hearth last wrote today
        self.written: dict[str, dict[str, Any]] = {}
        self._failed: dict[str, datetime] = {}
        self._held: set[str] = set()
        self._task = None
        self._again = False
        self._closed = False

    async def async_load(self) -> None:
        stored = await self._store.async_load() or {}
        self.written = {p: dict(r) for p, r in (stored.get("written") or {}).items() if isinstance(r, dict)}

    def _save(self) -> None:
        self._store.async_delay_save(lambda: {"written": self.written}, 2)

    async def async_flush(self) -> None:
        self._closed = True
        await self._store.async_save({"written": self.written})

    def enabled(self) -> bool:
        return bool(self.household.options.get(CONF_FL_BACKSTOP, True))

    def margin(self) -> int:
        try:
            return max(0, min(240, int(self.household.options.get(CONF_FL_BACKSTOP_MARGIN, BACKSTOP_MARGIN))))
        except (TypeError, ValueError):
            return BACKSTOP_MARGIN

    def wanted(self, person: str) -> int | None:
        """The daily limit Family Link should have today for the person; None: leave it alone."""
        day = self.household.days.get(person)
        state = day.limits.get(ALL) if day else None
        if state is None:
            return None
        paused = self.household.no_limits_until(person) is not None
        if not paused and state.minutes_left == 0:
            return None
        outside = self.household.outside_all()
        raised = sum(
            max(0, s.bonus_min)
            for gid, s in day.limits.items()
            if gid != ALL and gid in outside and s.raised is not None and s.budget_min is not None
        )
        return backstop_minutes(state.budget_min, state.bonus_left, raised, self.margin(), paused)

    def holds(self, person: str) -> bool:
        """Hearth's whole-device hold of the person's Family Link devices is on (enforce.py set the limit to 0)."""
        from .enforce import key_parts

        return any(
            key_parts(key)[1] == person and "lock_minutes" in held.restore
            for key, held in self.household.enforcement.held.items()
        )

    def view(self, person: str) -> dict[str, Any] | None:
        record = self.written.get(person)
        if not record or record.get("day") != dt_util.now().date().isoformat():
            return None
        return {"minutes": record.get("minutes"), "at": record.get("at")}

    @callback
    def check(self) -> None:
        """Each recompute: the kids whose Family Link limit should change are written (one run at a time)."""
        if self._closed or not self.enabled() or not self.hass.services.has_service(FL_DOMAIN, "set_daily_limit"):
            return
        if self._task is not None and not self._task.done():
            self._again = True
            return
        plans = self.plans()
        if plans:
            self._task = entry_task(self.hass, self._entry_id, self._write(plans), "hearth family link backstop")

    def plans(self, now: datetime | None = None) -> dict[str, tuple[str, int]]:
        """{person: (child id, minutes)} to write now."""
        now = now or dt_util.now()
        today = now.date().isoformat()
        out: dict[str, tuple[str, int]] = {}
        for person in self.household.people():
            child = self.household.family_link_child(person)
            if child is None:
                continue
            if self.holds(person):
                # What letting go puts back is the weekday's limit: written again after it
                self._held.add(person)
                continue
            if person in self._held:
                self._held.discard(person)
                self.written.pop(person, None)
            minutes = self.wanted(person)
            if minutes is None:
                continue
            record = self.written.get(person) or {}
            if record.get("day") == today and record.get("minutes") == minutes:
                continue
            failed = self._failed.get(person)
            if failed is not None and now - failed < RETRY:
                continue
            out[person] = (str(child), minutes)
        return out

    async def _write(self, plans: dict[str, tuple[str, int]]) -> None:
        self._again = False
        for person, (child, minutes) in plans.items():
            try:
                # The child's id as a string, from its entity's attributes: never a template
                await self.hass.services.async_call(
                    FL_DOMAIN, "set_daily_limit", {"child_id": child, "daily_minutes": minutes}, blocking=True
                )
            except Exception as err:  # noqa: BLE001 - one kid's failure mustn't stop the others; tried again later
                _LOGGER.warning("Hearth couldn't set Family Link's daily limit for %s to %s: %s", person, minutes, err)
                self._failed[person] = dt_util.now()
                self.household.enforcement.note(f"{FAMILY_LINK}|{person}", backstop=minutes, error=str(err)[:200])
                continue
            self._failed.pop(person, None)
            now = dt_util.now()
            self.written[person] = {"day": now.date().isoformat(), "minutes": minutes, "at": now.isoformat()}
            self.household.enforcement.note(f"{FAMILY_LINK}|{person}", backstop=minutes)
            _LOGGER.info("%s: Family Link's daily limit is %s min today (Hearth's backstop)", person, minutes)
        self._save()
        if self._again:
            self.check()
