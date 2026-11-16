"""Family Link's daily limit as a backstop (docs/home-assistant-integration.md, Family Link backstop).

Hearth's own holds are the real limit. Family Link's per-device daily limit is kept a little above them, so a phone
whose Hearth companion is off, or a device Hearth can't see, still stops near the end of the day:

    daily limit = the most screen time Family Link counted today on one of the kid's devices (not a TV)
                  + Hearth's daily time left (bonus included) + margin

rounded up to 5 minutes, at most a day (time_model.backstop_minutes). It's anchored on what Family Link itself counted,
so it never sits below real use: time Hearth doesn't count (a category outside daily time, System screens, Unlimited)
raises it, and spending counted time (bonus included) leaves it steady, since the device's minutes grow as Hearth's
time left shrinks. The margin is 30 minutes by default (Configure > Enforce). While Unlimited is on it is a whole day,
and the same sum again as soon as Unlimited ends. A kid with no daily time in Hearth is left alone.

- Written with hysteresis: when the wanted value is higher than what Hearth wrote today, or more than HYSTERESIS lower
  (and again after Hearth's own whole-device hold let go, which puts back the weekday's limit). Never below a device's
  minutes today + 5. Through familylink.set_daily_limit with the child's id alone: today's override on each device of
  the child that takes a daily limit (Family Link skips Google TVs). The child's id is read from the entity's
  attributes and passed as a string, never templated (Home Assistant would read its 21 digits as a number).
- Nothing is written while Hearth holds the child's devices (daily time used up: enforce.py sets the limit to 0), nor
  when daily time is used up and that hold is about to start; both are checked again right before each write.
- A parent's change: the override is today's only, and Hearth writes it each day, so the backstop wins over a weekday
  limit a parent changed in the Family Link app (and over a today's limit they set, at the next write). Switch the
  backstop off to keep Family Link's own limits.
- Every grant of bonus time also adds a Family Link bonus where the device would stop sooner (native_sync.mirror_bonus).
"""

from __future__ import annotations

from datetime import datetime, timedelta
import logging
import math
from typing import TYPE_CHECKING, Any

from homeassistant.core import HomeAssistant, callback
from homeassistant.helpers.storage import Store
from homeassistant.util import dt as dt_util

from . import family_link as fl
from .counting import ALL
from .enforce import FAMILY_LINK
from .entry_tasks import entry_task
from .time_model import BACKSTOP_MARGIN, backstop_minutes
from .activity import call_service

if TYPE_CHECKING:
    from .household import Household

_LOGGER = logging.getLogger(__name__)

FL_DOMAIN = "familylink"
# Options (Configure > Enforce): the backstop on (default) or off, and its margin in minutes
CONF_FL_BACKSTOP = "fl_backstop"
CONF_FL_BACKSTOP_MARGIN = "fl_backstop_margin"
RETRY = timedelta(minutes=5)
# A lower value is written only when it's this much lower than the one written today
HYSTERESIS = 30
# Never less than a device's minutes today plus this
FLOOR = 5


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
        # Daily time out while a category stays open: {"base", "allowance", "last"} per person (_open_limit)
        self._opened: dict[str, dict[str, int]] = {}
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

    def device_minutes(self, person: str, child: str | None = None) -> float:
        """The most screen time Family Link counted today on one of the person's devices that take a daily limit
        (fl.device_minutes_today: never a Google TV); without any, what Hearth counted today across everything
        (Unlimited minutes included), which is never less."""
        child = child or self.household.family_link_child(person)
        found = [m for _, m in fl.device_minutes_today(self.hass, child)] if child else []
        if found:
            return max(found)
        day = self.household.days.get(person)
        return ((day.raw_groups or day.groups).get(ALL, 0.0) / 60) if day else 0.0

    def _out(self, person: str) -> bool:
        """Daily time used up (not Unlimited): Hearth's whole-device hold is the limit then."""
        day = self.household.days.get(person)
        state = day.limits.get(ALL) if day else None
        return bool(
            state
            and state.minutes_left == 0
            and self.household.no_limits_until(person) is None
            and not self.household.open_groups(person)
        )

    def _open_limit(self, person: str, open_groups: set[str]) -> int:
        """Daily time out while a category stays open (its own bonus, an allow): the device's minutes when it opened +
        what was open then (more added since counts too) + margin. Never follows the device's minutes upward."""
        left = sum(self.household.open_left(person, g) for g in open_groups)
        record = self._opened.get(person)
        if record is None:
            record = self._opened[person] = {
                "base": int(math.ceil(self.device_minutes(person))), "allowance": left, "last": left
            }
        elif left > record["last"]:
            # More given since (a bigger bonus, a longer allow)
            record["allowance"] += left - record["last"]
        record["last"] = left
        total = record["base"] + record["allowance"] + self.margin()
        _LOGGER.debug("backstop %s: open past daily time (%s), %s", person, sorted(open_groups), record)
        return min(1440, int(math.ceil(total / 5) * 5))

    def wanted(self, person: str) -> int | None:
        """The daily limit Family Link should have today for the person; None: leave it alone."""
        day = self.household.days.get(person)
        state = day.limits.get(ALL) if day else None
        if state is None or state.budget_min is None:
            return None
        if self._out(person):
            self._opened.pop(person, None)
            return None
        unlimited = self.household.no_limits_until(person) is not None
        if not unlimited and state.minutes_left == 0:
            return self._open_limit(person, self.household.open_groups(person))
        self._opened.pop(person, None)
        # Daily time left, and each category's own bonus left (usable there past daily time)
        left = (state.minutes_left or 0) + sum(s.cat_bonus_left for g, s in day.limits.items() if g != ALL)
        return backstop_minutes(
            state.budget_min, int(math.ceil(self.device_minutes(person))), left, self.margin(), unlimited
        )

    def limit_on(self, child: str) -> bool:
        """The child's daily limit isn't known to be off in Family Link: its switch is on, or not found (an older Family
        Link). A switch that's off or unavailable: not on."""
        switch = fl.daily_limit_switch(self.hass, str(child))
        if switch is None:
            return True
        state = self.hass.states.get(switch)
        return state is not None and state.state == "on"

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
            if not self.limit_on(child):
                # With the child's daily limit switched off, Family Link writes the weekday's own limit (every week),
                # not today's override: nothing to back up then, and nothing written
                _LOGGER.debug("backstop %s: Family Link's daily limit is off, nothing written", person)
                continue
            if self.holds(person):
                _LOGGER.debug("backstop %s: Hearth's whole-device hold is on, nothing written", person)
                # What letting go puts back is the weekday's limit: written again after it
                self._held.add(person)
                continue
            if person in self._held:
                self._held.discard(person)
                self.written.pop(person, None)
            minutes = self.wanted(person)
            _LOGGER.debug(
                "backstop %s: device minutes %.0f, wanted %s, margin %s", person, self.device_minutes(person, child),
                minutes, self.margin(),
            )
            if minutes is None:
                continue
            record = self.written.get(person) or {}
            last = record.get("minutes") if record.get("day") == today else None
            if last is not None and last - HYSTERESIS <= minutes <= last:
                _LOGGER.debug("backstop %s: %s wanted, %s written: within the hysteresis, not written", person, minutes, last)
                continue
            failed = self._failed.get(person)
            if failed is not None and now - failed < RETRY:
                continue
            out[person] = (str(child), minutes)
        return out

    async def _write(self, plans: dict[str, tuple[str, int]]) -> None:
        self._again = False
        for person, (child, minutes) in plans.items():
            # Again right before the write: a hold may have started, daily time run out, or the limit been switched off
            if self.holds(person) or self._out(person) or not self.limit_on(child):
                _LOGGER.debug("backstop %s: skipped at the write (a hold started or daily time ran out)", person)
                continue
            # Never below what a device already used today
            if person not in self._opened:
                # (Open past daily time it stays bounded: never the device's minutes upward)
                minutes = min(1440, max(minutes, int(math.ceil(self.device_minutes(person, child))) + FLOOR))
            try:
                # The child's id as a string, from its entity's attributes: never a template
                await call_service(self.hass,
                    FL_DOMAIN, "set_daily_limit", {"child_id": child, "daily_minutes": minutes}, blocking=True,
                    person=person, why="backstop",
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

    def written_minutes(self) -> set[int]:
        """Every value the backstop wrote today (enforce.py never puts one of these back as a weekday's limit)."""
        today = dt_util.now().date().isoformat()
        return {int(r["minutes"]) for r in self.written.values() if r.get("day") == today and r.get("minutes")}
