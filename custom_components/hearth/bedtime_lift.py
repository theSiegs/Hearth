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
- A Family Link bedtime already under way isn't ended by moving its start (seen live: the call succeeds and the phone
  stays locked). What ends it is bonus time, as "Add time" in the Family Link app gives. So each device of the kid's
  whose Bedtime active sensor is on gets familylink.add_time_bonus for the minutes the lift has left (more extra time:
  the minutes more; a device that enters bedtime during the lift gets it then). A bonus can't be shortened, so when
  the lift ends Hearth resets it (familylink.reset_bonus), unless the device's latest bonus isn't one Hearth gave: a
  parent's, which stays. The bonus is Hearth's own in native_sync's count (never read as a parent's), and it adds
  nothing to Hearth's minutes: it only opens Family Link's bedtime.

Which night: Family Link keys a bedtime by the weekday it starts on, and a "today" override is for today's. So only a
bedtime that starts today, before the extra time ends, is moved. A bedtime that started yesterday evening (it's after
midnight now) is left alone: an override of yesterday's weekday isn't known to reach a night already under way, and
today's would move tonight's bedtime instead. Hearth's own locks are lifted all the same, and the bonus opens the phone
(it's per device, not per night). A start moved past midnight would read as a bedtime of this morning, so the moved
start is 23:59 at the latest.

The lifts, what Hearth moved and the bonuses it gave are kept with Home Assistant's storage helper, so a bedtime is put
back (and a bonus reset) after a restart too. A move from another day is gone with that day (the override was that
day's only).
"""

from __future__ import annotations

from datetime import datetime, timedelta
import logging
import math
from typing import TYPE_CHECKING, Any

from homeassistant.core import HomeAssistant, callback
from homeassistant.helpers.storage import Store
from homeassistant.util import dt as dt_util

from .entry_tasks import entry_task
from .activity import call_service

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
# Family Link's longest bonus (add_time_bonus takes 1 to 1440 minutes)
LONGEST_BONUS = 1440
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
        # By person: the Family Link bonus Hearth gave on devices already in bedtime, to reset when the lift ends:
        # {"child", "devices": {device id: {"until" (ISO, the lift's end it reaches), "given": [minutes, ...]}}}
        self.bonus: dict[str, dict[str, Any]] = {}
        self._failed_at: dict[str, datetime] = {}
        # By person: when their last lift ended (not kept over a restart), for sleep_locks_devices' grace
        self.ended_at: dict[str, datetime] = {}
        self._task = None
        self._again = False
        self._closed = False

    async def async_load(self) -> None:
        stored = await self._store.async_load() or {}
        self.lifts = {p: dict(r) for p, r in (stored.get("lifts") or {}).items() if isinstance(r, dict) and r.get("until")}
        self.moved = {p: dict(r) for p, r in (stored.get("moved") or {}).items() if isinstance(r, dict)}
        self.bonus = {
            p: dict(r)
            for p, r in (stored.get("bonus") or {}).items()
            if isinstance(r, dict) and r.get("child") and isinstance(r.get("devices"), dict)
        }

    def _data(self) -> dict[str, Any]:
        return {"lifts": self.lifts, "moved": self.moved, "bonus": self.bonus}

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

    def moved_today(self, person: str, now: datetime | None = None) -> set[str]:
        """Read only, for bedtime sync: the starts ("HH:MM") Hearth moved Family Link's bedtime tonight from and to
        for the person's lift (its own writes, never a parent's change); empty without one today."""
        moved = self.moved.get(person)
        if not moved or moved.get("day") != (now or dt_util.now()).date().isoformat():
            return set()
        return {str(moved.get("start")), str(moved.get("set"))}

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
            self.ended_at[person] = dt_util.now()
            _LOGGER.info("%s: bedtime back (the extra time is over)", person)
            self._save()
            self.hass.bus.async_fire(EVENT_BACK, {"person": person})
        self.sync()

    @callback
    def check(self, person: str, all_left: float | None, now: datetime | None = None) -> bool:
        """Each recompute: a lift whose time is up, or whose kid has no All screen time left, ends. Says whether the
        person's bedtime is lifted now."""
        now = now or dt_util.now()
        failed = self._failed_at.get(person)
        retry = failed is None or now - failed >= RETRY
        if person not in self.lifts:
            # A bonus of a lift that's over, whose reset failed: tried again
            if retry and person in self.bonus:
                self.sync()
            return False
        # A no-limits lift (hearth.no_limits) lasts its time whatever today's time says
        if self.until(person, now) is None or (all_left == 0 and not self.lifts[person].get("no_limits")):
            self.end(person)
            return False
        # A device that's in Family Link's bedtime and has no bonus for the lift yet (it entered bedtime meanwhile)
        if retry and self._bonus_due(person, self.until(person, now), now):
            self.sync()
        return True

    # Family Link

    @callback
    def sync(self) -> None:
        """Brings Family Link's bedtime in step with the lifts (one run at a time)."""
        if self._closed or not (self.lifts or self.moved or self.bonus):
            return
        if self._task is not None and not self._task.done():
            self._again = True
            return
        self._task = entry_task(self.hass, self._entry_id, self._async_sync(), "hearth bedtime lift")

    async def _async_sync(self) -> None:
        self._again = False
        now = dt_util.now()
        for person in sorted(set(self.lifts) | set(self.moved) | set(self.bonus)):
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
        await call_service(self.hass,
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

    def _bonus_due(self, person: str, until: datetime | None, now: datetime) -> list[tuple[Any, str, int]]:
        """The Family Link bonus the lift still owes: (device switch, device id, minutes) for each of the kid's devices
        in Family Link's bedtime now that has none for the lift yet (unless a bonus already keeps it open as long), and
        for each that has one that ends before the lift does (more extra time was given)."""
        from . import family_link as fl

        if until is None or not self.hass.services.has_service(FL_DOMAIN, "add_time_bonus"):
            return []
        child = self.household.family_link_child(person)
        if not child:
            return []
        given = (self.bonus.get(person) or {}).get("devices", {})
        in_bedtime = {str(s.attributes.get("device_id")) for s in bedtime_sensors(self.hass, child) if s.state == "on"}
        due: list[tuple[Any, str, int]] = []
        for device in fl.devices(self.hass, child):
            device_id = str(device.attributes.get("device_id"))
            record = given.get(device_id)
            reaches = dt_util.parse_datetime(str(record.get("until") or "")) if record else None
            if record is None and device_id not in in_bedtime:
                continue
            minutes = math.ceil((until - max(now, reaches or now)).total_seconds() / 60)
            if minutes <= 0 or (record is None and fl.bonus_left(self.hass, child, device) >= minutes):
                continue
            due.append((device, device_id, min(LONGEST_BONUS, minutes)))
        return due

    async def _give_bonus(self, person: str, until: datetime, now: datetime) -> dict[str, int]:
        """Bonus time on each device already in Family Link's bedtime, which is what ends a bedtime under way; what
        was given, by device name. Raises on the first device that fails (those done are kept; retried later)."""
        added: dict[str, int] = {}
        for device, device_id, minutes in self._bonus_due(person, until, now):
            await call_service(self.hass,
                FL_DOMAIN, "add_time_bonus", {"entity_id": device.entity_id, "bonus_minutes": minutes}, blocking=True
            )
            record = self.bonus.setdefault(
                person, {"child": self.household.family_link_child(person), "devices": {}}
            )
            mine = record["devices"].setdefault(device_id, {"given": []})
            mine["until"] = until.isoformat()
            mine["given"].append(minutes)
            self._save()
            self.household.sync.note_own_bonus(person, device_id, minutes)
            self.household.enforcement.refresh_soon(device.entity_id)
            added[str(device.attributes.get("device_name") or device.entity_id)] = minutes
        return added

    async def _bonus_back(self, person: str) -> dict[str, list[str]]:
        """The lift is over: the bonus Hearth gave for it is reset on each device (a bonus can't be shortened, and
        whether an unused one runs out by itself isn't known), unless the device's latest bonus isn't Hearth's. Family
        Link shows only a device's latest bonus: one of a size the lift didn't give is a parent's (where extra time's
        mirror gave some too, one bigger than all of Hearth's), and resetting would end theirs. Raises when a reset
        fails (kept, retried later)."""
        from . import family_link as fl

        record = self.bonus.get(person)
        if record is None:
            return {}
        child = str(record["child"])
        own = self.household.sync.own_bonus()
        devices = {str(d.attributes.get("device_id")): d for d in fl.devices(self.hass, child)}
        reset: list[str] = []
        kept: list[str] = []
        for device_id in list(record["devices"]):
            given = [int(m) for m in record["devices"][device_id].get("given") or []]
            device = devices.get(device_id)
            if device is not None:
                showing = fl._int(device.attributes.get("bonus_minutes")) or 0
                mirrored = own.get(device_id, 0) - sum(given)
                if showing > 0 and (showing > own.get(device_id, 0) if mirrored > 0 else showing not in given):
                    kept.append(device.entity_id)
                else:
                    await self.household.sync.reset_bonus(child, device)
                    self.household.sync.forget_own_bonus(person, device_id)
                    reset.append(device.entity_id)
            del record["devices"][device_id]
            self._save()
        self.bonus.pop(person, None)
        self._save()
        if kept:
            _LOGGER.info("%s: a Family Link bonus that isn't Hearth's is kept on %s", person, ", ".join(kept))
        return {"bedtime_bonus_reset": reset, "bedtime_bonus_kept": kept}

    async def _sync_person(self, person: str, now: datetime) -> None:
        until = self.until(person, now)
        moved = self.moved.get(person)
        today = now.date().isoformat()
        key = f"family_link|{person}"
        did: dict[str, Any] = {}
        failed: Exception | None = None
        if until is None:
            # A reset that fails doesn't stop the start from being put back
            try:
                did = await self._bonus_back(person)
            except Exception as err:  # noqa: BLE001 - raised again below, after tonight's start
                failed = err
            if moved is not None:
                await self._put_back(person, moved, today, did)
            elif any(did.values()):
                self.household.enforcement.note(key, **did)
            if failed is not None:
                raise failed
            return
        # A bedtime already under way first: only bonus time opens it. A failure there doesn't stop the start's move
        try:
            if added := await self._give_bonus(person, until, now):
                did = {"bedtime_bonus": added}
        except Exception as err:  # noqa: BLE001 - raised again below, after tonight's start
            failed = err
        if not await self._move_start(person, until, now, did) and did:
            self.household.enforcement.note(key, **did)
        if failed is not None:
            raise failed

    async def _move_start(self, person: str, until: datetime, now: datetime, did: dict[str, Any]) -> bool:
        """Tonight's Family Link bedtime starts when the lift ends. Says whether it noted what it did ([did], the
        bonus given just before, goes in the same note: Hearth's page shows an enforcer's last note only)."""
        moved = self.moved.get(person)
        today = now.date().isoformat()
        if not self.hass.services.has_service(FL_DOMAIN, "set_bedtime"):
            return False
        want = moved_start(until, now)
        if moved is not None and moved.get("day") == today:
            if moved.get("kept") or moved["set"] == want:
                return False
            # More extra time: tonight's start moves again, unless a parent changed it meanwhile
            if self._current_starts(moved["child"], today) - {moved["set"], moved["start"]}:
                moved["kept"] = True
                self.household.enforcement.note(f"family_link|{person}", bedtime=KEPT_CURRENT, **did)
                return True
            await self._set_bedtime(moved["child"], want, moved["end"], moved["weekday"])
            moved["set"] = want
            self.household.enforcement.note(f"family_link|{person}", bedtime_moved=want, **did)
            return True
        child = self.household.family_link_child(person)
        window = tonight(self.hass, child, now) if child else None
        # Only tonight's bedtime, and only when it would start before the extra time ends
        if window is None or window[0] >= until or window[1] <= now or _hhmm(window[0]) >= want:
            return False
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
        self.household.enforcement.note(f"family_link|{person}", bedtime_moved=want, bedtime_was=start, **did)
        return True

    async def _put_back(self, person: str, moved: dict[str, Any], today: str, did: dict[str, Any] | None = None) -> None:
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
        self.household.enforcement.note(key, bedtime=outcome, bedtime_start=moved["start"], **(did or {}))


def lift_minutes(minutes: int, all_left: float | None) -> int:
    """How long extra time lifts bedtime: the minutes given, never more than All screen time has left."""
    if all_left is None:
        return minutes
    return max(0, min(minutes, math.floor(all_left)))
