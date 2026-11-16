"""An adult's extra time lifts bedtime while it lasts (docs/home-assistant-integration.md, Extra time at bedtime).

Extra time of All screen time an adult gives a kid in bedtime (hearth.add_bonus, the page's +15, an approved ask)
lifts bedtime for that kid when All screen time then has minutes left. In bedtime: the weekly schedule's Sleep, a lock
entity of theirs that's a bedtime (Family Link's, Family Safety's downtime), or Family Link's own bedtime on one of
their devices. The lift lasts as many minutes from now as were given (more extra time adds on) and ends sooner when All
screen time runs out again; an adult taking the extra time back (hearth.remove_bonus) shortens it. While it lasts:

- Hearth's own Sleep and the bedtime lock entities don't lock the kid: the TVs and phones (their state documents), and
  Family Safety's platforms and the Switch (the schedule's holds) let go. The state document says so
  ("bedtime_lifted" {since, until}).
- Family Link's bedtime tonight starts when the extra time ends: familylink.set_bedtime with scope "today", a one-off
  override for today's weekday that leaves the weekly schedule alone, the start moved and the end kept. More extra
  time moves it again. When the lift ends, the start Hearth found is put back the same way, only while the bedtime
  still reads Hearth's start or the one it found: a start a parent changed in the Family Link app meanwhile is theirs,
  and stays (kept_current, as the daily limit's hold does).

Which night: Family Link keys a bedtime by the weekday it starts on, and a "today" override is for today's. So only a
bedtime that starts today, before the extra time ends, is moved. A bedtime that started yesterday evening (it's after
midnight now) is left alone: an override of yesterday's weekday isn't known to reach a night already under way, and
today's would move tonight's bedtime instead. Hearth's own locks are lifted all the same. A start moved past midnight
would read as a bedtime of this morning, so the moved start is 23:59 at the latest.

The lifts and what Hearth moved are kept with Home Assistant's storage helper, so a bedtime is put back after a restart
too. A move from another day is gone with that day (the override was that day's only).
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
from .entry_tasks import entry_task

if TYPE_CHECKING:
    from .household import Household

_LOGGER = logging.getLogger(__name__)

FL_DOMAIN = "familylink"
# What putting Family Link's bedtime back did (enforce.py's words)
RESTORED = "restored"
KEPT_CURRENT = "kept_current"
# The override was another day's: nothing to put back
EXPIRED = "expired"
# A failed call is tried again after this long
RETRY = timedelta(minutes=5)
LATEST_START = "23:59"
# Fired when extra time lifts a kid's bedtime {person, until}, and when it's back {person}
EVENT_LIFTED = "hearth_bedtime_lifted"
EVENT_BACK = "hearth_bedtime_back"


def bedtime_sensors(hass: HomeAssistant, child: str) -> list[Any]:
    """The child's Bedtime active sensors, one per device (bedtime_start and bedtime_end among their attributes)."""
    return [
        s
        for s in hass.states.async_all("binary_sensor")
        if "_bedtime_active" in s.entity_id and str(s.attributes.get("child_id")) == child
    ]


def _local(value: Any) -> datetime | None:
    """A sensor's bedtime_start or bedtime_end as a local time (Family Link gives a local time without its offset)."""
    parsed = dt_util.parse_datetime(str(value or ""))
    if parsed is None:
        return None
    return parsed.replace(tzinfo=dt_util.get_default_time_zone()) if parsed.tzinfo is None else dt_util.as_local(parsed)


def _hhmm(value: datetime) -> str:
    return f"{value.hour:02d}:{value.minute:02d}"


def tonight(hass: HomeAssistant, child: str, now: datetime) -> tuple[datetime, datetime] | None:
    """Family Link's bedtime that starts today (its earliest start, its latest end), from the child's sensors; None
    when none of their devices has one that starts today."""
    starts: list[datetime] = []
    ends: list[datetime] = []
    for state in bedtime_sensors(hass, child):
        start, end = _local(state.attributes.get("bedtime_start")), _local(state.attributes.get("bedtime_end"))
        if start is None or end is None or start.date() != now.date() or end <= start:
            continue
        starts.append(start)
        ends.append(end)
    if not starts:
        return None
    return min(starts), max(ends)


def in_family_link_bedtime(hass: HomeAssistant, child: str) -> bool:
    """Family Link's bedtime is on now on any of the child's devices."""
    return any(s.state == "on" for s in bedtime_sensors(hass, child))


def moved_start(until: datetime, now: datetime) -> str:
    """Where tonight's bedtime starts for extra time until [until]: that minute (rounded up), 23:59 at the latest."""
    local = dt_util.as_local(until)
    if local.second or local.microsecond:
        local = local.replace(second=0, microsecond=0) + timedelta(minutes=1)
    if local.date() != now.date():
        return LATEST_START
    return _hhmm(local)


class BedtimeLifts:
    """Each kid's bedtime lift, and what Hearth moved of Family Link's bedtime for it."""

    def __init__(self, hass: HomeAssistant, household: Household, entry_id: str) -> None:
        self.hass = hass
        self.household = household
        self._entry_id = entry_id
        self._store: Store[dict[str, Any]] = Store(hass, 1, f"hearth.bedtime_lift.{entry_id}")
        # By person: {"since", "until"} (ISO)
        self.lifts: dict[str, dict[str, str]] = {}
        # By person: what Hearth moved in Family Link: {"child", "day", "weekday", "start", "end", "set"}
        self.moved: dict[str, dict[str, Any]] = {}
        self._failed_at: dict[str, datetime] = {}
        self._task = None
        self._again = False
        self._closed = False

    async def async_load(self) -> None:
        stored = await self._store.async_load() or {}
        self.lifts = {p: dict(r) for p, r in (stored.get("lifts") or {}).items() if isinstance(r, dict) and r.get("until")}
        self.moved = {p: dict(r) for p, r in (stored.get("moved") or {}).items() if isinstance(r, dict)}

    def _data(self) -> dict[str, Any]:
        return {"lifts": self.lifts, "moved": self.moved}

    def _save(self) -> None:
        self._store.async_delay_save(self._data, 2)

    async def async_flush(self) -> None:
        self._closed = True
        task = self._task
        if task is not None and not task.done():
            task.cancel()
        await self._store.async_save(self._data())

    def until(self, person: str, now: datetime | None = None) -> datetime | None:
        """When the person's bedtime lift ends; None without one (or once it's over)."""
        record = self.lifts.get(person)
        until = dt_util.parse_datetime(record["until"]) if record else None
        if until is None or until <= (now or dt_util.now()):
            return None
        return until

    def view(self, person: str) -> dict[str, str] | None:
        """{since, until} (local ISO) while the person's bedtime is lifted."""
        until = self.until(person)
        if until is None:
            return None
        since = dt_util.parse_datetime(self.lifts[person].get("since") or "")
        return {
            "since": dt_util.as_local(since).isoformat() if since else None,
            "until": dt_util.as_local(until).isoformat(),
        }

    @callback
    def give(
        self, person: str, minutes: int, now: datetime | None = None, until: datetime | None = None
    ) -> datetime:
        """Extra time given in bedtime: the lift lasts [minutes] more (from now, or from when it would end). With
        [until] (hearth.no_limits with include_bedtime): until then, whatever today's time says."""
        now = now or dt_util.now()
        running = self.until(person, now)
        record = self.lifts.get(person) if running is not None else None
        since = record.get("since") if record else None
        no_limits = until is not None or bool(record and record.get("no_limits"))
        if until is None:
            until = (running or now) + timedelta(minutes=minutes)
        elif running is not None and running > until:
            until = running
        self.lifts[person] = {"since": since or now.isoformat(), "until": until.isoformat()}
        if no_limits:
            self.lifts[person]["no_limits"] = True
        _LOGGER.info("%s: bedtime lifted until %s for extra time", person, dt_util.as_local(until).strftime("%H:%M"))
        self._save()
        self.hass.bus.async_fire(EVENT_LIFTED, {"person": person, "until": dt_util.as_local(until).isoformat()})
        self.sync()
        return until

    @callback
    def take(self, person: str, minutes: int, now: datetime | None = None) -> None:
        """Extra time taken back: the lift is that much shorter (over when that's now or before)."""
        now = now or dt_util.now()
        until = self.until(person, now)
        if until is None or minutes <= 0:
            return
        until -= timedelta(minutes=minutes)
        if until <= now:
            self.end(person)
            return
        self.lifts[person]["until"] = until.isoformat()
        self._save()
        self.sync()

    @callback
    def end(self, person: str) -> None:
        if self.lifts.pop(person, None) is not None:
            _LOGGER.info("%s: bedtime back (the extra time is over)", person)
            self._save()
            self.hass.bus.async_fire(EVENT_BACK, {"person": person})
        self.sync()

    @callback
    def check(self, person: str, all_left: float | None, now: datetime | None = None) -> bool:
        """Each recompute: a lift whose time is up, or whose kid has no All screen time left, ends. Says whether the
        person's bedtime is lifted now."""
        now = now or dt_util.now()
        if person not in self.lifts:
            return False
        # A no-limits lift (hearth.no_limits) lasts its time whatever today's time says
        if self.until(person, now) is None or (all_left == 0 and not self.lifts[person].get("no_limits")):
            self.end(person)
            return False
        return True

    # Family Link

    @callback
    def sync(self) -> None:
        """Brings Family Link's bedtime in step with the lifts (one run at a time)."""
        if self._closed or not (self.lifts or self.moved):
            return
        if self._task is not None and not self._task.done():
            self._again = True
            return
        self._task = entry_task(self.hass, self._entry_id, self._async_sync(), "hearth bedtime lift")

    async def _async_sync(self) -> None:
        self._again = False
        now = dt_util.now()
        for person in sorted(set(self.lifts) | set(self.moved)):
            failed = self._failed_at.get(person)
            if failed is not None and now - failed < RETRY:
                continue
            try:
                await self._sync_person(person, now)
                self._failed_at.pop(person, None)
            except Exception as err:  # noqa: BLE001 - shown on Hearth's page; Hearth's own locks are lifted anyway
                _LOGGER.warning("Hearth couldn't move Family Link's bedtime for %s: %s", person, err)
                self._failed_at[person] = now
                self.household.enforcement.note(f"family_link|{person}", bedtime_error=True, error=str(err)[:200])
            self._save()
        if self._again:
            self.sync()

    async def _set_bedtime(self, child: str, start: str, end: str, weekday: int) -> None:
        await self.hass.services.async_call(
            FL_DOMAIN,
            "set_bedtime",
            {"child_id": child, "start_time": start, "end_time": end, "day": weekday, "scope": "today"},
            blocking=True,
        )

    def _current_starts(self, child: str, day: str) -> set[str]:
        """Tonight's bedtime start as each of the child's devices reads it now ("HH:MM"), those that say."""
        found: set[str] = set()
        for state in bedtime_sensors(self.hass, child):
            start = _local(state.attributes.get("bedtime_start"))
            if start is not None and start.date().isoformat() == day:
                found.add(_hhmm(start))
        return found

    async def _sync_person(self, person: str, now: datetime) -> None:
        until = self.until(person, now)
        moved = self.moved.get(person)
        today = now.date().isoformat()
        if until is None:
            if moved is not None:
                await self._put_back(person, moved, today)
            return
        if not self.hass.services.has_service(FL_DOMAIN, "set_bedtime"):
            return
        want = moved_start(until, now)
        if moved is not None and moved.get("day") == today:
            if moved.get("kept") or moved["set"] == want:
                return
            # More extra time: tonight's start moves again, unless a parent changed it meanwhile
            if self._current_starts(moved["child"], today) - {moved["set"], moved["start"]}:
                moved["kept"] = True
                self.household.enforcement.note(f"family_link|{person}", bedtime=KEPT_CURRENT)
                return
            await self._set_bedtime(moved["child"], want, moved["end"], moved["weekday"])
            moved["set"] = want
            self.household.enforcement.note(f"family_link|{person}", bedtime_moved=want)
            return
        child = self.household.family_link_child(person)
        window = tonight(self.hass, child, now) if child else None
        # Only tonight's bedtime, and only when it would start before the extra time ends
        if window is None or window[0] >= until or window[1] <= now or _hhmm(window[0]) >= want:
            return
        start, end = _hhmm(window[0]), _hhmm(window[1])
        # Kept before the call: a restart in between still puts it back
        self.moved[person] = {
            "child": child,
            "day": today,
            "weekday": now.isoweekday(),
            "start": start,
            "end": end,
            "set": want,
        }
        self._save()
        await self._set_bedtime(child, want, end, now.isoweekday())
        self.household.enforcement.refresh_soon(next(iter(bedtime_sensors(self.hass, child))).entity_id)
        self.household.enforcement.note(f"family_link|{person}", bedtime_moved=want, bedtime_was=start)

    async def _put_back(self, person: str, moved: dict[str, Any], today: str) -> None:
        """The lift is over: tonight's start back as Hearth found it, while it still reads Hearth's (or that one)."""
        key = f"family_link|{person}"
        if moved.get("day") != today:
            outcome = EXPIRED
        elif moved.get("kept") or self._current_starts(moved["child"], today) - {moved["set"], moved["start"]}:
            _LOGGER.info("%s: Family Link's bedtime changed while lifted: kept, %s not put back", person, moved["start"])
            outcome = KEPT_CURRENT
        else:
            await self._set_bedtime(moved["child"], moved["start"], moved["end"], moved["weekday"])
            outcome = RESTORED
        self.moved.pop(person, None)
        self.household.enforcement.note(key, bedtime=outcome, bedtime_start=moved["start"])


def lift_minutes(minutes: int, all_left: float | None) -> int:
    """How long extra time lifts bedtime: the minutes given, never more than All screen time has left."""
    if all_left is None:
        return minutes
    return max(0, min(minutes, math.floor(all_left)))
