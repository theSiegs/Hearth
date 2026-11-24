"""Bedtime schedule sync (docs/home-assistant-integration.md, Bedtime sync): the weekly schedule's bedtime and wake kept
in step in Family Link's bedtime and Family Safety's allowed hours.

The model is a weekly baseline plus a dated override. The baseline is the plain week (Monday to Sunday as edited): each
weekday's night (its last change when that's a Sleep, until the next day's first change that allows something) and
each weekday's window (from the end of the night carried in to the start of the day's last Sleep). The override is
today's: today's night and window as today really resolves (a "tonight only" change, a tonight-only wake, a day off, a
half day, tomorrow's day type).

- Family Link: one weekly slot per weekday (familylink.set_bedtime, weekly; keyed by the weekday the night starts on,
  its end the next morning), and a tonight-only override (scope "today") when tonight differs from today's slot.
- Family Safety: per platform (Windows, Xbox), one allowed window per weekday (set_screentime_intervals with
  day_of_week), rounded outward to the half hour so it's never stricter than Hearth, and a today-only window
  (NativeSync.async_set_window_today) when today differs.

It works by state, not by events: a ledger keeps, per target (kid, service, platform, weekday, and one "today"), the
value Hearth wants, the value it last wrote and when a reading first confirmed it. A write happens only when the want
differs from what was written (an edit, a new day), on a bounded retry, or when an adult asks. A reading equal to what
was written is Hearth's own echo. A reading that differs is a parent's change in their app only when the value was
confirmed before, the last write is older than the quiet time, the reading isn't one of Hearth's other writers' (a
bedtime lift's moved start, an extra time's moved end), and two readings a minute apart agree. Then tonight follows it
(Week.change_today, by the app), and an offer is made to keep it every week (hearth.bedtime_offer); Hearth never writes
over it unasked.

Nothing is written for a kid until an adult starts the sync after a preview (hearth.sync_bedtimes, the panel's review):
a kid whose schedule has a Sleep is pushed from Hearth; one without imports the apps' bedtime first (Family Link's when
its bedtime is on, else Family Safety's). Starting a kid whose Family Link bedtime is switched off switches it on after
the seven weekly slots are written; Hearth's own whole-device lock (Household.sleep_locks_devices) stays as the cover
for the gaps. A parent switching Family Link's bedtime off later lifts tonight's bedtime and isn't undone.
"""

from __future__ import annotations

import asyncio
import copy
from dataclasses import dataclass
from datetime import date, datetime, timedelta
import logging
import math
import re
import secrets
from typing import TYPE_CHECKING, Any

import voluptuous as vol

from homeassistant.core import HomeAssistant, callback
from homeassistant.helpers.storage import Store
from homeassistant.util import dt as dt_util

from . import family_link as fl
from .activity import call_service
from .attention import ADULTS, Action, Item
from .bedtime_lift import _local as _fl_local, bedtime_sensors, tonight
from .enforce import FAMILY_LINK, FAMILY_SAFETY, QUIET_AFTER_CALL, enforcers_from_options
from .entry_tasks import entry_task
from .native_sync import (
    FS_WEEKDAYS,
    SET_INTERVALS,
    _fs_window_data,
    fs_allowed_window,
    fs_policy_windows,
    fs_saved_schedule,
    fs_weekday_window,
)
from .weekly import (
    DAY_KEYS,
    DAY_OFF_KEY,
    DAYS,
    EVENT_SCHEDULE_CHANGED,
    NOTHING,
    ScheduleError,
    as_minutes,
    say_time,
    weekday_key,
    with_bedtime,
    with_wake,
)

if TYPE_CHECKING:
    from .household import Household

_LOGGER = logging.getLogger(__name__)

FL_DOMAIN = "familylink"
FS_DOMAIN = "microsoft_family_safety"
FS_PLATFORMS = ("Windows", "Xbox")
MINUTES_A_DAY = 1440

# A kid's sync state
REVIEW = "review"
ON = "on"
OFF = "off"
# Where the first sync starts from
AUTO = "auto"
FROM_HEARTH = "hearth"
FROM_FAMILY_LINK = "family_link"
FROM_FAMILY_SAFETY = "family_safety"
NOTHING_TO_SYNC = "none"
START_FROM = (AUTO, FROM_HEARTH, FROM_FAMILY_LINK, FROM_FAMILY_SAFETY)

# A target's status, best to worst
IN_SYNC = "in_sync"
WRITING = "writing"
WAITING = "waiting"
DIFFERS = "differs"
UNSUPPORTED = "unsupported"
FAILED = "failed"
STATUS_OFF = "off"
_WORST = (IN_SYNC, WRITING, WAITING, STATUS_OFF, UNSUPPORTED, DIFFERS, FAILED)

WEEKLY = "weekly"
TODAY = "today"
SEVERAL = "several"

# A parent's change only after Hearth's last write is this old (Family Link's poll is one to five minutes)
FL_QUIET = timedelta(minutes=3)
FS_QUIET = QUIET_AFTER_CALL
# Two readings this far apart must agree before a differing value is a parent's change
AGREE = timedelta(minutes=1)
# A written value no reading shows after this long didn't take
NOT_TAKEN = timedelta(minutes=10)
FIRST_RETRY = timedelta(minutes=5)
MAX_RETRY = timedelta(hours=1)
RETRY_NOT_LOADED = timedelta(seconds=30)
# The adults are told once a target failed this many times
TELL_AFTER = 3
# Seconds between two writes (one call at a time per kid)
PACE = 2.0

EVENT = "hearth_bedtime_sync"
REVIEW_KEY = "hearth_bedtime_sync_review"
VIA_NAMES = {FAMILY_LINK: "Family Link", FAMILY_SAFETY: "Family Safety"}


# Times


def hm(minutes: int) -> str:
    """Minutes from midnight as "HH:MM"; 1440 is "24:00" (midnight at the end of the day)."""
    return f"{minutes // 60:02d}:{minutes % 60:02d}"


def mins(value: str) -> int:
    hours, minutes = str(value).split(":")[:2]
    return int(hours) * 60 + int(minutes)


def round_out(begin: int, end: int) -> tuple[int, int]:
    """A window rounded outward to the half hour: begin down, end up (Family Safety's grid)."""
    return begin // 30 * 30, min(MINUTES_A_DAY, math.ceil(end / 30) * 30)


def _sleep(modes: dict[str, dict[str, Any]], mode: str | None) -> bool:
    return (modes.get(mode or "") or {}).get("allows") == NOTHING


# The model (pure)


def night_of(
    changes: list[tuple[int, str]], following: list[tuple[int, str]], modes: dict[str, dict[str, Any]]
) -> tuple[int, int] | str:
    """A day's night: (start, end) minutes, start on the day (its last change, a Sleep) and end on the next day (its
    first change that allows something). A reason instead when there's none or one the apps can't hold: no_bedtime,
    past_next_day."""
    if not changes or not _sleep(modes, changes[-1][1]):
        return "no_bedtime"
    start = changes[-1][0]
    end = next((m for m, mode in following if not _sleep(modes, mode)), None)
    if end is None or end >= start:
        return "past_next_day"
    return start, end


def window_of(changes: list[tuple[int, str]], carried: str | None, modes: dict[str, dict[str, Any]]) -> tuple[int, int] | str:
    """A day's window: (begin, end) minutes, from the end of the night carried in (00:00 when none is) to the start
    of the day's last Sleep (1440 when the day doesn't end in one). A Sleep in the middle of the day isn't in it.
    asleep_all_day when nothing of the day is awake."""
    begin = 0
    if _sleep(modes, carried) or (not changes and carried is None):
        begin = next((m for m, mode in changes if not _sleep(modes, mode)), None)
        if begin is None:
            return "asleep_all_day" if _sleep(modes, carried) else (0, MINUTES_A_DAY)
    end = changes[-1][0] if changes and _sleep(modes, changes[-1][1]) else MINUTES_A_DAY
    if end <= begin:
        return "asleep_all_day"
    return begin, end


def week_days(sched: dict[str, Any], modes: dict[str, dict[str, Any]]) -> dict[str, list[tuple[int, str]]]:
    """The plain week's changes per day key (the baseline: weekdays as weekdays)."""
    return {
        key: [(m, mode) for m, mode in as_minutes((sched["days"].get(key) or {}).get("changes") or []) if mode in modes]
        for key in DAY_KEYS
    }


def baseline(days: dict[str, list[tuple[int, str]]], modes: dict[str, dict[str, Any]]) -> tuple[dict[str, Any], dict[str, Any]]:
    """The week's nights and windows by day key (mon..sun): what each weekday is in the apps."""
    nights: dict[str, Any] = {}
    windows: dict[str, Any] = {}
    for i, key in enumerate(DAYS):
        nights[key] = night_of(days[key], days[DAYS[(i + 1) % 7]], modes)
        carried = None
        for back in range(1, 8):
            earlier = days[DAYS[(i - back) % 7]]
            if earlier:
                carried = earlier[-1][1]
                break
        windows[key] = window_of(days[key], carried, modes)
    return nights, windows


def fl_value(night: tuple[int, int] | str) -> list[str] | None:
    return [hm(night[0]), hm(night[1])] if isinstance(night, tuple) else None


def fs_value(window: tuple[int, int] | str) -> list[str] | None:
    if not isinstance(window, tuple):
        return None
    begin, end = round_out(*window)
    return [hm(begin), hm(end)]


def fl_plan(nights: dict[str, Any]) -> dict[str, list[str] | None]:
    """Family Link's weekly slots ("1" Monday to "7" Sunday) for the nights."""
    return {str(i + 1): fl_value(nights[key]) for i, key in enumerate(DAYS)}


def fs_plan(windows: dict[str, Any]) -> dict[str, list[str] | None]:
    """Family Safety's days ("sunday".."saturday") for the windows, rounded out."""
    return {FS_WEEKDAYS[(i + 1) % 7]: fs_value(windows[key]) for i, key in enumerate(DAYS)}


def import_nights(
    fl_slots: dict[int, tuple[str, str]] | None = None, fs_windows: dict[str, list[tuple[int, int]]] | None = None
) -> dict[str, tuple[str | None, str | None]]:
    """What importing the apps' bedtime gives each day key: (wake, bedtime) "HH:MM" (None: left as it is). From
    Family Link's slots (by ISO weekday; a slot's start is that day's bedtime, its end the next day's wake), else
    Family Safety's windows per platform (by its weekday name; bedtime the earliest end, wake the latest begin). The Day
    off gets Saturday's wake and Sunday's bedtime. A day given a bedtime but no wake gets the week's most common wake,
    so no day is Sleep from start to end."""
    wake: dict[str, str] = {}
    bed: dict[str, str] = {}
    if fl_slots:
        for iso, (start, end) in fl_slots.items():
            bed[DAYS[iso - 1]] = start
            wake[DAYS[iso % 7]] = end
    elif fs_windows:
        for weekday, windows in fs_windows.items():
            key = DAYS[(FS_WEEKDAYS.index(weekday) + 6) % 7]
            ends = [e for _, e in windows if e < MINUTES_A_DAY]
            begins = [b for b, _ in windows if b > 0]
            if ends:
                bed[key] = hm(min(ends))
            if begins:
                wake[key] = hm(max(begins))
    if "sat" in wake:
        wake[DAY_OFF_KEY] = wake["sat"]
    if "sun" in bed:
        bed[DAY_OFF_KEY] = bed["sun"]
    common = max(sorted(set(wake.values())), key=list(wake.values()).count) if wake else None
    out: dict[str, tuple[str | None, str | None]] = {}
    for key in DAY_KEYS:
        if key not in wake and key not in bed:
            continue
        out[key] = (wake.get(key) or (common if key in bed else None), bed.get(key))
    return out


def apply_import(
    days: dict[str, list[tuple[int, str]]], nights: dict[str, tuple[str | None, str | None]], modes: dict[str, dict[str, Any]]
) -> dict[str, list[tuple[int, str]]]:
    """The week's days with an import applied (for a preview; Week.set_nights does the same for real)."""
    out = copy.deepcopy(days)
    for key, (wake, bed) in nights.items():
        changes = out[key]
        if wake:
            changes = with_wake(changes, mins(wake) // 15 * 15, modes)
        if bed:
            changes = with_bedtime(changes, mins(bed) // 15 * 15, modes)
        out[key] = changes
    return out


def _scrub(text: Any) -> str:
    """An error as shown: long numbers (account and child ids) left out."""
    return re.sub(r"\d{6,}", "<id>", str(text))[:200]


def fl_capabilities(hass: HomeAssistant) -> dict[str, bool]:
    """What the installed Family Link can do for bedtime sync: weekly slots (set_bedtime), and tonight-only overrides
    (its set_bedtime schema takes scope today)."""
    found = hass.services.async_services_for_domain(FL_DOMAIN).get("set_bedtime")
    if found is None:
        return {"bedtime_weekly": False, "bedtime_today": False}
    today = True
    if found.schema is not None:
        try:
            found.schema({"child_id": "1", "start_time": "21:00", "end_time": "07:00", "day": "1", "scope": "today"})
        except vol.Invalid:
            today = False
    return {"bedtime_weekly": True, "bedtime_today": today}


@dataclass(frozen=True)
class Target:
    via: str
    platform: str | None
    scope: str
    # "1".."7" for Family Link, "sunday".. for Family Safety; None for today
    day: str | None

    def day_key(self, now: datetime) -> str:
        """The weekday (mon..sun) whose bedtime this is."""
        if self.day is None:
            return weekday_key(now.date())
        if self.via == FAMILY_LINK:
            return DAYS[int(self.day) - 1]
        return DAYS[(FS_WEEKDAYS.index(self.day) + 6) % 7]


def _entry() -> dict[str, Any]:
    return {"want": None, "written": None, "written_at": None, "confirmed_at": None, "theirs": None, "fails": 0,
            "retry_at": None}


def _when(value: Any) -> datetime | None:
    parsed = dt_util.parse_datetime(str(value or ""))
    return dt_util.as_utc(parsed) if parsed is not None else None


class BedtimeSync:
    """Each kid's bedtime kept in step in Family Link and Family Safety, with its ledger and offers."""

    def __init__(self, hass: HomeAssistant, household: Household, entry_id: str) -> None:
        self.hass = hass
        self.household = household
        self._entry_id = entry_id
        self._store: Store[dict[str, Any]] = Store(hass, 1, f"hearth.bedtime_sync.{entry_id}")
        # By person: {"state", "fl" {...}, "fs" {platform: {...}}} (see the design's ledger)
        self.people: dict[str, dict[str, Any]] = {}
        self.offers: list[dict[str, Any]] = []
        self._task: asyncio.Task | None = None
        self._again = False
        self._closed = False

    # Storage

    async def async_load(self) -> None:
        stored = await self._store.async_load() or {}
        self.people = {p: r for p, r in (stored.get("people") or {}).items() if isinstance(r, dict)}
        self.offers = [o for o in stored.get("offers") or [] if isinstance(o, dict) and o.get("id")]

    def _data(self) -> dict[str, Any]:
        return {"people": self.people, "offers": self.offers}

    def _save(self) -> None:
        self._store.async_delay_save(self._data, 2)

    async def async_flush(self) -> None:
        self._closed = True
        task = self._task
        if task is not None and not task.done():
            task.cancel()
        await self._store.async_save(self._data())

    # Who

    def _enforcer(self, person: str, kind: str):
        return next(
            (e for e in enforcers_from_options(self.household.options) if e.kind == kind and e.person == person), None
        )

    def kids(self) -> list[str]:
        """The kids with a Family Link or Family Safety enforcer (Configure > Enforce)."""
        return [
            p for p in self.household.week_people()
            if self._enforcer(p, FAMILY_LINK) is not None or self._enforcer(p, FAMILY_SAFETY) is not None
        ]

    def state(self, person: str) -> str:
        return (self.people.get(person) or {}).get("state", REVIEW)

    def _platforms(self, person: str) -> list[str]:
        enforcer = self._enforcer(person, FAMILY_SAFETY)
        return [p for p in enforcer.platforms if p in FS_PLATFORMS] if enforcer else []

    # Reading the apps

    def _fl_slot(self, child: str, iso: int) -> list[str] | None:
        found = fl.bedtime_slot(self.hass, child, iso)
        return list(found) if found else None

    def _fl_switch(self, child: str) -> bool | None:
        entity_id = fl.bedtime_switch(self.hass, child)
        state = self.hass.states.get(entity_id) if entity_id else None
        if state is None or state.state not in ("on", "off"):
            return None
        return state.state == "on"

    def _fl_tonight(self, child: str, now: datetime) -> list[str] | None:
        found = tonight(self.hass, child, now)
        return [hm(found[0].hour * 60 + found[0].minute), hm(found[1].hour * 60 + found[1].minute)] if found else None

    def _fl_last_night_on(self, child: str, now: datetime) -> bool:
        """Last night's bedtime still under way on a device (it started before today)."""
        for state in bedtime_sensors(self.hass, child):
            start = _fl_local(state.attributes.get("bedtime_start"))
            if state.state == "on" and start is not None and start.date() < now.date():
                return True
        return False

    def _fs_weekly(self, entity_id: str, platform: str, weekday: str, now: datetime) -> list[str] | str | None:
        windows = fs_policy_windows(self.hass, entity_id, platform, weekday)
        if windows is None:
            one = fs_weekday_window(self.hass, entity_id, platform, weekday, now)
            windows = [one] if one else None
        if windows is None:
            return None
        if len(windows) > 1:
            return SEVERAL
        if not windows:
            return ["00:00", "00:00"]
        return [hm(windows[0][0]), hm(windows[0][1])]

    def _fs_today(self, entity_id: str, platform: str) -> list[str] | None:
        found = fs_allowed_window(self.hass, entity_id, platform)
        return [hm(found[0]), hm(found[1])] if found else None

    # The week

    def _days(self, person: str) -> dict[str, list[tuple[int, str]]]:
        week = self.household.week
        return week_days(week.schedule_of(person), week.data.modes)

    def _effective(self, person: str, now: datetime) -> tuple[Any, Any]:
        """Today's night and window as today really resolves."""
        week = self.household.week
        today = now.date()
        modes = week.data.modes
        changes = week.resolve(person, today).changes
        following = week.resolve(person, today + timedelta(days=1)).changes
        return night_of(changes, following, modes), window_of(changes, week._carry(person, today), modes)

    def has_sleep(self, person: str) -> bool:
        """The kid's own schedule has a Sleep at the end of a day."""
        week = self.household.week
        if not week.is_set(person):
            return False
        modes = week.data.modes
        return any(changes and _sleep(modes, changes[-1][1]) for changes in self._days(person).values())

    # Running

    @callback
    def reconcile(self) -> None:
        """Brings the apps in step with the schedule (one run at a time)."""
        if self._closed:
            return
        if self._task is not None and not self._task.done():
            self._again = True
            return
        self._task = entry_task(self.hass, self._entry_id, self._async_reconcile(), "hearth bedtime sync")

    async def _async_reconcile(self) -> None:
        self._again = False
        if self.household.enforcement._may_let_go():
            now = dt_util.now()
            for person in self.kids():
                record = self.people.get(person)
                if not record or record.get("state") != ON:
                    continue
                try:
                    await self._sync_person(person, record, now)
                except Exception:  # noqa: BLE001 - one kid's trouble never stops another's
                    _LOGGER.exception("Bedtime sync for %s failed", person)
            self._attention()
            self._save()
        if self._again and not self._closed:
            self.reconcile()

    async def _sync_person(self, person: str, record: dict[str, Any], now: datetime) -> None:
        self._offers_due(person, now)
        days = self._days(person)
        nights, windows = baseline(days, self.household.week.data.modes)
        night, window = self._effective(person, now)
        if (enforcer := self._enforcer(person, FAMILY_LINK)) is not None:
            child = fl.child_of(self.hass, enforcer.entity_id)
            if child:
                await self._sync_family_link(person, record, child, nights, night, now)
        if (enforcer := self._enforcer(person, FAMILY_SAFETY)) is not None:
            await self._sync_family_safety(person, record, enforcer.entity_id, windows, window, now)

    async def _sync_family_link(
        self, person: str, record: dict[str, Any], child: str, nights: dict[str, Any], night: Any, now: datetime
    ) -> None:
        ledger = record.setdefault("fl", {})
        ledger["child"] = child
        weekly = ledger.setdefault("weekly", {})
        plan = fl_plan(nights)
        for i, key in enumerate(DAYS):
            iso = str(i + 1)
            entry = weekly.setdefault(iso, _entry())
            await self._step(
                person, Target(FAMILY_LINK, None, WEEKLY, iso), entry, plan[iso], nights[key],
                self._fl_slot(child, i + 1), now, quiet=FL_QUIET,
            )
        await self._family_link_switch(person, record, ledger, child, plan, now)
        # Tonight
        caps = fl_capabilities(self.hass)
        slot = weekly[str(now.isoweekday())]
        base = _app_value(slot)
        today = ledger.get("today")
        if today and today.get("date") != now.date().isoformat():
            today = None
        if today is None:
            today = {**_entry(), "date": now.date().isoformat()}
        blocked = None
        if self.household.bedtime_lift.until(person, now) is not None:
            blocked = "Extra time at bedtime is running"
        elif self._fl_switch(child) is False:
            blocked = "Bedtime is switched off in Family Link"
        elif self._fl_last_night_on(child, now):
            blocked = "Last night's bedtime is still on"
        want = fl_value(night)
        reason = night if want is None else None
        if want is not None and not caps["bedtime_today"]:
            want, reason = None, "This Family Link takes no tonight-only bedtime"
        await self._step(
            person, Target(FAMILY_LINK, None, TODAY, None), today, want, reason, self._fl_tonight(child, now), now,
            quiet=FL_QUIET, base=base, base_confirmed=bool(slot.get("confirmed_at")),
            base_written_at=slot.get("written_at"), blocked=blocked,
            own=self.household.bedtime_lift.moved_today(person, now),
        )
        ledger["today"] = today if _keep_today(today) else None

    async def _family_link_switch(
        self, person: str, record: dict[str, Any], ledger: dict[str, Any], child: str, plan: dict[str, Any], now: datetime
    ) -> None:
        """Switched on after the first sync's weekly slots are written (it was off); a parent switching it off later
        lifts tonight's bedtime and is left so."""
        on = self._fl_switch(child)
        if ledger.get("enable_pending"):
            if on is True:
                ledger["enable_pending"] = False
            elif on is False and all(
                (e := ledger["weekly"].get(iso) or {}).get("written") == want
                for iso, want in plan.items() if want is not None
            ):
                retry = _when(ledger.get("enable_retry_at"))
                if retry is None or dt_util.utcnow() >= retry:
                    try:
                        await call_service(self.hass, FL_DOMAIN, "enable_bedtime", {"child_id": child}, blocking=True,
                                           person=person, why="bedtime_sync")
                    except Exception as err:  # noqa: BLE001
                        ledger["enable_retry_at"] = (dt_util.utcnow() + FIRST_RETRY).isoformat()
                        ledger["switch_error"] = _scrub(err)
                        return
                    ledger.update(enable_pending=False, switched_on=True, switch_seen_on=True, switch_error=None)
                    self._fire(person, "written", FAMILY_LINK, None, "switch", None, None, "Bedtime switched on")
                    self.household.enforcement.refresh_soon(fl.bedtime_switch(self.hass, child))
            return
        if on is True:
            ledger.update(switch_seen_on=True, switch_off_seen=None, switched_off=None)
            return
        if on is False and ledger.get("switch_seen_on"):
            seen = _when(ledger.get("switch_off_seen"))
            if seen is None:
                ledger["switch_off_seen"] = dt_util.utcnow().isoformat()
                return
            if dt_util.utcnow() - seen < AGREE:
                return
            # A parent switched Family Link's bedtime off: tonight's bedtime is lifted, and it isn't switched back on
            ledger.update(switch_seen_on=False, switch_off_seen=None, switched_off=now.date().isoformat())
            self._fire(person, "outside_change", FAMILY_LINK, None, "switch", None, None, "Bedtime switched off")
            current = self.household.week.now(person, now)
            until = None
            if current is not None:
                until = current.until if _sleep(self.household.week.data.modes, current.mode) else current.wake
            if until is not None and until > now:
                self.household.bedtime_lift.give(person, 0, now, until=until)
            self.household.note_origin(person, "bedtime", "Bedtime switched off tonight", FAMILY_LINK)

    async def _sync_family_safety(
        self, person: str, record: dict[str, Any], entity_id: str, windows: dict[str, Any], window: Any, now: datetime
    ) -> None:
        ledgers = record.setdefault("fs", {})
        plan = fs_plan(windows)
        today_name = FS_WEEKDAYS[(now.weekday() + 1) % 7]
        for platform in self._platforms(person):
            ledger = ledgers.setdefault(platform, {})
            ledger["entity_id"] = entity_id
            weekly = ledger.setdefault("weekly", {})
            day = now.date().isoformat()
            cut = self.household.sync.cutoff_today(person, platform)
            # Every end extra time moved, today's and yesterday's: Hearth's own, also when a second extra time moved
            # it again or the extra time is over and the end still shows
            moved = self.household.sync.moved_windows(person, platform)
            for i, key in enumerate(DAYS):
                weekday = FS_WEEKDAYS[(i + 1) % 7]
                entry = weekly.setdefault(weekday, _entry())
                today = ledger.get("today") if (ledger.get("today") or {}).get("date") == day else None
                own: set[Any] = set()
                follows = False
                if weekday == today_name:
                    # Today's weekday also shows today's own window (today only, or upstream's weekday write)
                    if today and today.get("written"):
                        own.add(tuple(today["written"]))
                    if cut:
                        own.add((hm(cut["begin"]), hm(cut["set"])))
                    follows = bool(today and today.get("follows") == day)
                # Hearth's own today window of that weekday may still show for a poll or two after midnight (the
                # fork's put back, or native_sync's for upstream's weekday write)
                if (kept := entry.get("today_value")) and entry.get("today_date", "") >= (
                    now.date() - timedelta(days=1)
                ).isoformat():
                    own.add(tuple(kept))
                own.update((hm(m["begin"]), hm(m["end"])) for m in moved if m["weekday"] == weekday)
                for window in self.household.sync.windows.values():
                    if window.get("entity_id") == entity_id and window.get("platform") == platform and window.get(
                        "weekday"
                    ) == weekday:
                        own.add((hm(window["target_begin"]), hm(window["target"])))
                reading = self._fs_weekly(entity_id, platform, weekday, now)
                before = entry.get("written")
                await self._step(
                    person, Target(FAMILY_SAFETY, platform, WEEKLY, weekday), entry, plan[weekday], windows[key],
                    reading, now, quiet=FS_QUIET, own=own, detect_only=follows,
                )
                if weekday == today_name and entry.get("written") != before and entry.get("written") is not None:
                    # A weekly write drops a pending today-only value: today's is worked out again
                    if today and today.get("follows") != day:
                        ledger["today"] = None
            today = ledger.get("today") if (ledger.get("today") or {}).get("date") == day else None
            if today is None:
                today = {**_entry(), "date": now.date().isoformat()}
            blocked = None
            if cut is not None:
                blocked = "Extra time moved today's end"
            elif platform == "Windows" and fs_saved_schedule(self.hass, entity_id):
                blocked = "Family Safety keeps a saved schedule"
            slot = weekly[today_name]
            await self._step(
                person, Target(FAMILY_SAFETY, platform, TODAY, None), today, fs_value(window),
                window if not isinstance(window, tuple) else None, self._fs_today(entity_id, platform), now,
                quiet=FS_QUIET, base=_app_value(slot), base_confirmed=bool(slot.get("confirmed_at")),
                base_written_at=slot.get("written_at"), blocked=blocked,
                own={(hm(m["begin"]), hm(m["end"])) for m in moved if m["day"] == day},
            )
            if today.get("written"):
                slot.update(today_value=today["written"], today_date=day)
            ledger["today"] = today if _keep_today(today) else None

    async def _step(
        self,
        person: str,
        target: Target,
        entry: dict[str, Any],
        want: list[str] | None,
        reason: Any,
        reading: Any,
        now: datetime,
        *,
        quiet: timedelta,
        base: list[str] | None = None,
        base_confirmed: bool = False,
        base_written_at: Any = None,
        blocked: str | None = None,
        own: set[Any] | frozenset[Any] = frozenset(),
        detect_only: bool = False,
    ) -> None:
        """One target: confirm, detect a parent's change, write when Hearth's want differs from what it wrote."""
        utc = dt_util.utcnow()
        entry["want"] = want
        if entry.get("follows") == now.date().isoformat():
            self._status(entry, IN_SYNC, "Follows the app tonight")
            return
        writing = entry.pop("writing", None)
        if writing and reading is not None and reading == writing.get("value"):
            # Hearth wrote it before a restart, and it landed
            entry.update(written=writing["value"], written_at=writing.get("at"))
        written = entry.get("written")
        if written is None and base is None and reading is not None and reading == want:
            # Already in step (a first look, or a ledger lost): nothing to write
            written = entry["written"] = want
        known = written if written is not None else base
        confirmed = bool(entry.get("confirmed_at")) if written is not None else base_confirmed
        if reading is not None and known is not None and reading == known:
            if written is not None and not entry.get("confirmed_at"):
                entry["confirmed_at"] = utc.isoformat()
                self._fire(person, "confirmed", target.via, target.platform, target.scope, target.day, want=reading)
            entry["seen"] = None
            if reading == want:
                # What Hearth wants shows: a failure before is over (one still pending keeps its wait)
                entry.update(fails=0, retry_at=None, told=False)
        elif (
            reading is not None
            and known is not None
            and confirmed
            and reading != entry.get("theirs")
            and blocked is None
        ):
            just = any(
                (w := _when(at)) is not None and utc - w < quiet
                for at in (entry.get("written_at"), base_written_at)
            )
            if _matches(reading, own) or just:
                entry["seen"] = None
            else:
                seen = entry.get("seen") or {}
                if seen.get("value") == reading and (at := _when(seen.get("at"))) is not None and utc - at >= AGREE:
                    entry["seen"] = None
                    await self._outside(person, target, entry, reading, now)
                    return
                if seen.get("value") != reading:
                    entry["seen"] = {"value": reading, "at": utc.isoformat()}
        if detect_only:
            self._status(entry, IN_SYNC, "Follows the app tonight")
            return
        if entry.get("theirs") is not None:
            if entry.get("theirs_want") == want:
                self._status(entry, DIFFERS, f"Changed in {VIA_NAMES[target.via]}")
                return
            # An adult changed Hearth's bedtime since: Hearth's is what's wanted again
            entry["theirs"] = None
            self._drop_offers(person, target)
        if want is None:
            self._status(entry, UNSUPPORTED, _reason_text(target, reason))
            return
        if blocked is not None:
            self._status(entry, WAITING, blocked)
            return
        if written is None and base is not None and base == want:
            # Nothing dated needed tonight
            self._status(entry, IN_SYNC, None)
            return
        retry = _when(entry.get("retry_at"))
        due = retry is not None and utc >= retry
        if known == want:
            if entry.get("confirmed_at") or (written is None and base_confirmed):
                self._status(entry, IN_SYNC, None)
                return
            if not due:
                written_at = _when(entry.get("written_at"))
                if retry is None and written_at is not None and utc - written_at >= NOT_TAKEN:
                    self._failed(person, target, entry, "The app doesn't show it yet")
                elif retry is None:
                    self._status(entry, WRITING, None)
                return
        else:
            if entry.get("unsupported_for") == want:
                self._status(entry, UNSUPPORTED, entry.get("reason"))
                return
            if retry is not None and not due and entry.get("tried") == want:
                return
        await self._write(person, target, entry, want, now)

    async def _write(self, person: str, target: Target, entry: dict[str, Any], want: list[str], now: datetime) -> None:
        domain, service = (FL_DOMAIN, "set_bedtime") if target.via == FAMILY_LINK else (FS_DOMAIN, SET_INTERVALS)
        if not self.hass.services.has_service(domain, service):
            entry["retry_at"] = (dt_util.utcnow() + RETRY_NOT_LOADED).isoformat()
            entry["tried"] = want
            self._status(entry, WAITING, f"{VIA_NAMES[target.via]} isn't loaded yet")
            return
        utc = dt_util.utcnow()
        # Kept before the call: a restart in between still knows it
        entry["writing"] = {"value": want, "at": utc.isoformat()}
        entry["tried"] = want
        await self._store.async_save(self._data())
        try:
            await self._call(person, target, want, now)
        except vol.Invalid as err:
            entry.pop("writing", None)
            entry["unsupported_for"] = want
            self._status(entry, UNSUPPORTED, _scrub(err))
            self._fire(person, "failed", target.via, target.platform, target.scope, target.day, want, _scrub(err))
            return
        except Exception as err:  # noqa: BLE001 - shown on the Bedtime card and told once
            entry.pop("writing", None)
            self._failed(person, target, entry, _scrub(err))
            return
        entry.pop("writing", None)
        entry.update(written=want, written_at=utc.isoformat(), confirmed_at=None, seen=None, retry_at=None,
                     unsupported_for=None)
        self._status(entry, WRITING, None)
        self._fire(person, "written", target.via, target.platform, target.scope, target.day, want)
        if PACE:
            await asyncio.sleep(PACE)

    async def _call(self, person: str, target: Target, want: list[str], now: datetime) -> None:
        if target.via == FAMILY_LINK:
            child = self.people[person]["fl"]["child"]
            data: dict[str, Any] = {"child_id": child, "start_time": want[0], "end_time": want[1]}
            if target.scope == TODAY:
                data.update(day=str(now.isoweekday()), scope="today")
            else:
                data["day"] = target.day
            await call_service(self.hass, FL_DOMAIN, "set_bedtime", data, blocking=True, person=person, why="bedtime_sync")
            sensors = bedtime_sensors(self.hass, child)
            self.household.enforcement.refresh_soon(
                fl.bedtime_switch(self.hass, child) or (sensors[0].entity_id if sensors else None)
            )
            return
        ledger = self.people[person]["fs"][target.platform]
        entity_id = ledger["entity_id"]
        begin, end = mins(want[0]), mins(want[1])
        if target.scope == TODAY:
            await self.household.sync.async_set_window_today(person, entity_id, target.platform, begin, end)
            return
        await call_service(
            self.hass, FS_DOMAIN, SET_INTERVALS, _fs_window_data(entity_id, target.platform, begin, end, target.day),
            blocking=True, person=person, why="bedtime_sync",
        )
        self.household.enforcement.refresh_soon(entity_id)

    def _failed(self, person: str, target: Target, entry: dict[str, Any], reason: str) -> None:
        fails = int(entry.get("fails") or 0) + 1
        wait = min(MAX_RETRY, FIRST_RETRY * (2 ** (fails - 1)))
        entry.update(fails=fails, retry_at=(dt_util.utcnow() + wait).isoformat())
        self._status(entry, FAILED if fails >= TELL_AFTER else WAITING, reason)
        self._fire(person, "failed", target.via, target.platform, target.scope, target.day, entry.get("want"), reason)
        if fails >= TELL_AFTER and not entry.get("told"):
            entry["told"] = True
            what = VIA_NAMES[target.via] + (f" ({target.platform})" if target.platform else "")
            day = "tonight's" if target.scope == TODAY else f"{_long(target.day_key(dt_util.now()))}'s"
            self._notify(
                Item(
                    f"hearth_bedtime_sync_failed_{person}_{target.via}_{target.platform}",
                    f"{what} didn't take {day} bedtime for {self.household.person_name(person)}: {reason}",
                    title="Bedtime not in step",
                    audience=ADULTS,
                    bell=True,
                    about={"person": person},
                )
            )

    def _status(self, entry: dict[str, Any], status: str, reason: str | None) -> None:
        entry["status"] = status
        entry["reason"] = reason

    # A parent's change in their app

    async def _outside(self, person: str, target: Target, entry: dict[str, Any], reading: Any, now: datetime) -> None:
        was = entry.get("written") or entry.get("want")
        entry.update(theirs=reading, theirs_want=entry.get("want"), status=DIFFERS,
                     reason=f"Changed in {VIA_NAMES[target.via]}")
        self._fire(person, "outside_change", target.via, target.platform, target.scope, target.day, reading)
        self._again = True
        if reading == SEVERAL:
            self._add_offer(person, target, None, None, was, now, adoptable=False)
            return
        start, end = reading
        today_key = weekday_key(now.date())
        day_key = target.day_key(now)
        if target.via == FAMILY_LINK:
            bedtime, wake = start, end
        else:
            bedtime = end if end != "24:00" else None
            wake = start if start != "00:00" else None
        if target.scope == TODAY:
            # A tonight-only change in the app: tonight follows it, no offer
            entry["follows"] = now.date().isoformat()
            self._follow_tonight(person, target, bedtime, wake if target.via == FAMILY_LINK else None, now)
            return
        offer = self._add_offer(person, target, bedtime, wake, was, now)
        if day_key == today_key:
            offer["applied"] = now.date().isoformat()
            self._follow_tonight(
                person, target, bedtime,
                wake if target.via == FAMILY_LINK and (not was or wake != was[1]) else None, now,
            )

    def _follow_tonight(self, person: str, target: Target, bedtime: str | None, wake: str | None, now: datetime) -> None:
        """Tonight follows a parent's change in their app (Hearth, and so every other service)."""
        week = self.household.week
        # The app this came from isn't written tonight
        self._hold_tonight(person, target, now)
        if bedtime is not None and target.via == FAMILY_SAFETY and mins(bedtime) <= now.hour * 60 + now.minute:
            bedtime = None  # already past: nothing to follow tonight
        if bedtime is None and wake is None:
            return
        try:
            week.change_today(person, now.date(), bedtime=bedtime, wake=wake, by=target.via,
                              reason=f"Changed in {VIA_NAMES[target.via]}")
        except ScheduleError as err:
            _LOGGER.info("%s: tonight can't follow %s: %s", person, VIA_NAMES[target.via], err)
            return
        self.hass.bus.async_fire(
            EVENT_SCHEDULE_CHANGED,
            {"person": person, "days": [weekday_key(now.date())], "today_only": True, "by": target.via},
        )
        said = say_time(mins(bedtime)) if bedtime else f"wake {say_time(mins(wake))}"
        self.household.note_origin(person, "bedtime", f"Bedtime {said} tonight", target.via)
        self.household.recompute()

    def _hold_tonight(self, person: str, target: Target, now: datetime) -> None:
        record = self.people.setdefault(person, {"state": ON})
        day = now.date().isoformat()
        if target.via == FAMILY_LINK:
            ledger = record.setdefault("fl", {})
            ledger["today"] = {**(ledger.get("today") or _entry()), "date": day, "follows": day}
        else:
            ledger = record.setdefault("fs", {}).setdefault(target.platform, {})
            ledger["today"] = {**(ledger.get("today") or _entry()), "date": day, "follows": day}

    # Offers

    def _add_offer(
        self, person: str, target: Target, bedtime: str | None, wake: str | None, was: Any, now: datetime,
        adoptable: bool = True,
    ) -> dict[str, Any]:
        self._drop_offers(person, target)
        was_bed, was_wake = (None, None)
        if isinstance(was, list):
            was_bed, was_wake = (was[0], was[1]) if target.via == FAMILY_LINK else (was[1], was[0])
        offer = {
            "id": secrets.token_hex(6),
            "person": person,
            "via": target.via,
            "platform": target.platform,
            "slot": target.day,
            "day": target.day_key(now),
            "bedtime": bedtime,
            "wake": wake,
            "was": {"bedtime": was_bed, "wake": was_wake},
            "adoptable": adoptable,
            "at": now.isoformat(),
        }
        self.offers.append(offer)
        self._fire(person, "offer", target.via, target.platform, WEEKLY, target.day, None, None)
        name, day = self.household.person_name(person), _long(offer["day"])
        app = VIA_NAMES[target.via] + (f" ({target.platform})" if target.platform else "")
        if adoptable:
            text = f"{name}'s {day} bedtime was changed in {app}: {_say(bedtime)}"
            if wake and target.via == FAMILY_LINK:
                text += f", wake {_say(wake)}"
            text += f" (Hearth has {_say(was_bed)}). Tonight follows it on {day}s until you choose."
            actions = (
                Action("keep", f"Every {day}", "hearth.bedtime_offer", {"id": offer["id"], "accept": True}),
                Action("back", "Put Hearth's back", "hearth.bedtime_offer", {"id": offer["id"], "accept": False}),
            )
        else:
            text = f"{name}'s {day} allowed hours in {app} now have several windows, which Hearth can't keep in step."
            actions = (Action("back", "Put Hearth's back", "hearth.bedtime_offer", {"id": offer["id"], "accept": False}),)
        self._notify(Item(f"hearth_bedtime_offer_{offer['id']}", text, title="Bedtime changed in an app",
                          audience=ADULTS, actions=actions, about={"person": person}, once=True))
        return offer

    def _drop_offers(self, person: str, target: Target) -> None:
        for offer in [o for o in self.offers if _offer_of(o, person, target)]:
            self.offers.remove(offer)
            self._clear(f"hearth_bedtime_offer_{offer['id']}")

    def _offers_due(self, person: str, now: datetime) -> None:
        """An offer still open when its weekday comes: that night follows the app's change."""
        today = now.date().isoformat()
        for offer in self.offers:
            if (
                offer["person"] != person or not offer.get("adoptable") or offer.get("applied") == today
                or offer["day"] != weekday_key(now.date())
            ):
                continue
            offer["applied"] = today
            target = Target(offer["via"], offer.get("platform"), WEEKLY, offer.get("slot"))
            self._follow_tonight(person, target, offer.get("bedtime"),
                                 offer.get("wake") if offer["via"] == FAMILY_LINK else None, now)

    def answer(self, offer_id: str, accept: bool) -> dict[str, Any]:
        """An adult's answer: keep it every week (Hearth's schedule takes the app's value, and every other service
        follows), or put Hearth's back in that app."""
        offer = next((o for o in self.offers if o["id"] == offer_id), None)
        if offer is None:
            raise ScheduleError("That change was already answered")
        if accept and not offer.get("adoptable"):
            raise ScheduleError("Hearth can't keep several windows a day; put Hearth's back instead")
        person = offer["person"]
        week = self.household.week
        now = dt_util.now()
        target = Target(offer["via"], offer.get("platform"), WEEKLY, offer.get("slot"))
        entry = self._entry_of(person, target)
        undo = None
        if accept:
            nights: dict[str, tuple[str | None, str | None]] = {}
            day = offer["day"]
            if offer["via"] == FAMILY_LINK:
                nights[day] = (None, offer.get("bedtime"))
                following = DAYS[(DAYS.index(day) + 1) % 7]
                if offer.get("wake"):
                    nights[following] = (offer["wake"], None)
            else:
                nights[day] = (offer.get("wake"), offer.get("bedtime"))
            undo = week.set_nights({person: nights})
            if entry is not None:
                # What the app shows is now Hearth's (a time moved by the 15-minute grid is written back)
                entry.update(written=entry.get("theirs"), confirmed_at=dt_util.utcnow().isoformat(), theirs=None,
                             theirs_want=None, seen=None)
        elif entry is not None:
            # Hearth's goes back in that app: what it shows now is what's there
            entry.update(written=entry.get("theirs") or entry.get("written"), confirmed_at=dt_util.utcnow().isoformat(),
                         theirs=None, theirs_want=None, seen=None, retry_at=None)
        # Tonight's change the app's change made goes: the schedule's own again
        today = week.data.today.get(person)
        if today and today.get("by") == offer["via"]:
            week.resume([person])
        self._unhold_tonight(person, target)
        self.offers.remove(offer)
        self._clear(f"hearth_bedtime_offer_{offer['id']}")
        self._fire(person, "offer_answered", offer["via"], offer.get("platform"), WEEKLY, offer.get("slot"), None,
                   "accepted" if accept else "declined")
        self.hass.bus.async_fire(
            EVENT_SCHEDULE_CHANGED,
            {"person": person, "days": [offer["day"]], "today_only": not accept, "by": "panel"},
        )
        self._save()
        self.household.recompute()
        self.reconcile()
        return {"person": person, "accepted": accept, "undo": undo, "day": offer["day"]}

    def _unhold_tonight(self, person: str, target: Target) -> None:
        record = self.people.get(person) or {}
        if target.via == FAMILY_LINK:
            ledger = record.get("fl") or {}
        else:
            ledger = (record.get("fs") or {}).get(target.platform) or {}
        if ledger.get("today"):
            ledger["today"] = None

    def _entry_of(self, person: str, target: Target) -> dict[str, Any] | None:
        record = self.people.get(person) or {}
        if target.via == FAMILY_LINK:
            return ((record.get("fl") or {}).get("weekly") or {}).get(target.day or "")
        return (((record.get("fs") or {}).get(target.platform or "") or {}).get("weekly") or {}).get(target.day or "")

    # Starting, stopping, checking

    def direction(self, person: str, start_from: str = AUTO) -> str:
        """Where a kid's first sync starts from: Hearth's schedule when it has a Sleep; else the apps' bedtime (Family
        Link's when its bedtime is on, else Family Safety's); none with nothing to sync."""
        if start_from != AUTO:
            return start_from
        if self.has_sleep(person):
            return FROM_HEARTH
        if self._import_slots(person):
            return FROM_FAMILY_LINK
        if self._import_windows(person):
            return FROM_FAMILY_SAFETY
        return NOTHING_TO_SYNC

    def _import_slots(self, person: str) -> dict[int, tuple[str, str]]:
        enforcer = self._enforcer(person, FAMILY_LINK)
        child = fl.child_of(self.hass, enforcer.entity_id) if enforcer else None
        if not child or self._fl_switch(child) is not True:
            return {}
        return {iso: found for iso in range(1, 8) if (found := fl.bedtime_slot(self.hass, child, iso))}

    def _import_windows(self, person: str) -> dict[str, list[tuple[int, int]]]:
        enforcer = self._enforcer(person, FAMILY_SAFETY)
        if enforcer is None:
            return {}
        out: dict[str, list[tuple[int, int]]] = {}
        for weekday in FS_WEEKDAYS:
            found: list[tuple[int, int]] = []
            for platform in self._platforms(person):
                windows = fs_policy_windows(self.hass, enforcer.entity_id, platform, weekday)
                if windows and len(windows) == 1 and windows[0] != (0, MINUTES_A_DAY):
                    found.append(windows[0])
            if found:
                out[weekday] = found
        return out

    def _import_of(self, person: str, direction: str) -> dict[str, tuple[str | None, str | None]]:
        if direction == FROM_FAMILY_LINK:
            return import_nights(fl_slots=self._import_slots(person))
        if direction == FROM_FAMILY_SAFETY:
            return import_nights(fs_windows=self._import_windows(person))
        return {}

    def preview(self, person: str, start_from: str = AUTO) -> dict[str, Any]:
        """What starting the kid would do: per weekday and service, what's there and what it becomes."""
        now = dt_util.now()
        modes = self.household.week.data.modes
        direction = self.direction(person, start_from)
        nights_in = self._import_of(person, direction)
        days = apply_import(self._days(person), nights_in, modes) if nights_in else self._days(person)
        nights, windows = baseline(days, modes)
        out: dict[str, Any] = {
            "person": person,
            "name": self.household.person_name(person),
            "state": self.state(person),
            "start_from": direction,
            "import": {k: {"wake": w, "bedtime": b} for k, (w, b) in nights_in.items()},
            "days": {
                key: {"bedtime": fl_value(nights[key])[0] if fl_value(nights[key]) else None,
                      "wake": hm(days[key][0][0]) if days[key] and not _sleep(modes, days[key][0][1]) else None}
                for key in DAYS
            },
            "family_link": [],
            "family_safety": [],
            "unsupported": [],
            "switch_on": False,
        }
        if (enforcer := self._enforcer(person, FAMILY_LINK)) is not None and (
            child := fl.child_of(self.hass, enforcer.entity_id)
        ):
            for iso, want in fl_plan(nights).items():
                was = self._fl_slot(child, int(iso))
                if want is None:
                    out["unsupported"].append({"via": FAMILY_LINK, "day": iso, "reason": _reason_text(
                        Target(FAMILY_LINK, None, WEEKLY, iso), nights[DAYS[int(iso) - 1]])})
                    continue
                out["family_link"].append({"day": iso, "scope": WEEKLY, "start": want[0], "end": want[1], "was": was,
                                           "write": was != want})
            out["switch_on"] = direction != NOTHING_TO_SYNC and self._fl_switch(child) is False
        if (enforcer := self._enforcer(person, FAMILY_SAFETY)) is not None:
            for platform in self._platforms(person):
                for weekday, want in fs_plan(windows).items():
                    was = self._fs_weekly(enforcer.entity_id, platform, weekday, now)
                    if want is None:
                        out["unsupported"].append({"via": FAMILY_SAFETY, "platform": platform, "day": weekday,
                                                   "reason": "Asleep the whole day"})
                        continue
                    out["family_safety"].append({"platform": platform, "day": weekday, "scope": WEEKLY,
                                                 "start": want[0], "end": want[1], "was": was, "write": was != want,
                                                 "several": was == SEVERAL})
        return out

    def start(self, people: list[str], start_from: str = AUTO) -> dict[str, Any]:
        """Starts the kids' sync (an adult confirmed the preview): imports first where that's the direction."""
        results: dict[str, Any] = {}
        for person in people:
            plan = self.preview(person, start_from)
            direction = plan["start_from"]
            record = self.people.setdefault(person, {"state": REVIEW})
            if direction == NOTHING_TO_SYNC:
                results[person] = {**plan, "started": False}
                continue
            undo = None
            if nights := self._import_of(person, direction):
                undo = self.household.week.set_nights({person: nights})
                self.hass.bus.async_fire(
                    EVENT_SCHEDULE_CHANGED,
                    {"person": person, "days": list(nights), "today_only": False, "by": "import"},
                )
            record["state"] = ON
            record["since"] = dt_util.utcnow().isoformat()
            if plan["switch_on"]:
                record.setdefault("fl", {})["enable_pending"] = True
            self._fire(person, "started", None, None, None, None, None, direction)
            results[person] = {**plan, "started": True, "undo": undo}
        self._save()
        self._attention()
        self.household.recompute()
        self.reconcile()
        return results

    def stop(self, people: list[str]) -> None:
        """Nothing more is written for them, and nothing is put back (the apps keep the hours they have)."""
        for person in people:
            self.people.setdefault(person, {})["state"] = OFF
            self._fire(person, "stopped", None, None, None, None, None, None)
            for offer in [o for o in self.offers if o["person"] == person]:
                self.offers.remove(offer)
                self._clear(f"hearth_bedtime_offer_{offer['id']}")
        self._save()
        self._attention()

    def check_now(self, people: list[str]) -> None:
        """An adult's "Check now": waiting retries go now."""
        for person in people:
            for entry in self._entries(person):
                if entry.get("retry_at"):
                    entry["retry_at"] = None
                    entry["tried"] = None
                entry.pop("unsupported_for", None)
        self.reconcile()

    async def async_family_link_bedtime_on(self, person: str) -> None:
        """An adult's "Turn it back on" for a bedtime a parent switched off in Family Link."""
        enforcer = self._enforcer(person, FAMILY_LINK)
        child = fl.child_of(self.hass, enforcer.entity_id) if enforcer else None
        if not child:
            raise ScheduleError("No Family Link for them")
        await call_service(self.hass, FL_DOMAIN, "enable_bedtime", {"child_id": child}, blocking=True,
                           person=person, why="bedtime_sync")
        ledger = self.people.setdefault(person, {}).setdefault("fl", {})
        ledger.update(switch_seen_on=True, switched_off=None, switch_off_seen=None)
        self._save()

    def _entries(self, person: str) -> list[dict[str, Any]]:
        record = self.people.get(person) or {}
        found = list(((record.get("fl") or {}).get("weekly") or {}).values())
        if (record.get("fl") or {}).get("today"):
            found.append(record["fl"]["today"])
        for ledger in (record.get("fs") or {}).values():
            found += list((ledger.get("weekly") or {}).values())
            if ledger.get("today"):
                found.append(ledger["today"])
        return found

    # Views

    def view(self, person: str) -> dict[str, Any]:
        """{state, services [{via, platform, status, reason, next_try, days, tonight}], offers} for the Bedtime card,
        the summary and hearth.explain."""
        record = self.people.get(person) or {}
        state = record.get("state", REVIEW)
        services: list[dict[str, Any]] = []
        fl_ledger = record.get("fl")
        if self._enforcer(person, FAMILY_LINK) is not None:
            services.append(self._service_view(FAMILY_LINK, None, fl_ledger or {}, state))
            if fl_ledger and fl_ledger.get("switched_off") and state == ON:
                services[-1].update(status=STATUS_OFF, reason="Bedtime is switched off in Family Link")
        for platform in self._platforms(person):
            services.append(self._service_view(FAMILY_SAFETY, platform, (record.get("fs") or {}).get(platform) or {}, state))
        return {
            "state": state,
            "services": services,
            "offers": [dict(o) for o in self.offers if o["person"] == person],
        }

    def _service_view(self, via: str, platform: str | None, ledger: dict[str, Any], state: str) -> dict[str, Any]:
        entries = dict(ledger.get("weekly") or {})
        today = ledger.get("today")
        statuses = [e.get("status") or WAITING for e in entries.values()] + ([today.get("status")] if today and today.get("status") else [])
        if state != ON:
            status, reason = (STATUS_OFF, None)
        elif not statuses:
            status, reason = WAITING, "Not checked yet"
        else:
            status = max(statuses, key=lambda s: _WORST.index(s) if s in _WORST else 0)
            reason = next((e.get("reason") for e in [*entries.values(), today or {}] if e.get("status") == status), None)
        retries = [r for e in entries.values() if (r := _when(e.get("retry_at")))]
        return {
            "via": via,
            "platform": platform,
            "status": status,
            "reason": reason,
            "next_try": dt_util.as_local(min(retries)).isoformat() if retries else None,
            "days": {
                day: {"want": e.get("want"), "written": e.get("written"), "theirs": e.get("theirs"),
                      "status": e.get("status"), "reason": e.get("reason"), "written_at": e.get("written_at")}
                for day, e in entries.items()
            },
            "tonight": {"want": today.get("want"), "written": today.get("written"), "status": today.get("status"),
                        "reason": today.get("reason")} if today else None,
        }

    def explain_lines(self, person: str) -> list[str]:
        """hearth.explain's lines for each service that isn't in step."""
        view = self.view(person)
        if view["state"] != ON:
            return []
        lines = []
        for service in view["services"]:
            if service["status"] in (IN_SYNC, WRITING):
                continue
            what = VIA_NAMES[service["via"]] + (f" ({service['platform']})" if service["platform"] else "")
            lines.append(f"{what}: {service['reason'] or service['status']}")
        return lines

    # Telling the adults

    def _attention(self) -> None:
        """The review item while a kid waits for the first sync with something to sync."""
        attention = getattr(self.household.hub, "attention", None)
        if attention is None:
            return
        waiting = [
            p for p in self.kids()
            if self.state(p) == REVIEW and self.direction(p) != NOTHING_TO_SYNC
        ]
        if waiting and attention.item(REVIEW_KEY) is None:
            attention.notify(
                Item(
                    REVIEW_KEY,
                    "Hearth can keep each kid's bedtime in step in Family Link and Family Safety. Open Hearth's "
                    "Schedule tab to see what changes and start it.",
                    title="Bedtimes can now be kept in step",
                    audience=ADULTS,
                    bell=True,
                    phone=False,
                )
            )
        elif not waiting and attention.item(REVIEW_KEY) is not None:
            attention.clear(REVIEW_KEY, bell_too=True)

    def _notify(self, item: Item) -> None:
        attention = getattr(self.household.hub, "attention", None)
        if attention is not None:
            attention.notify(item)

    def _clear(self, key: str) -> None:
        attention = getattr(self.household.hub, "attention", None)
        if attention is not None and attention.item(key) is not None:
            attention.clear(key, bell_too=True, phone=True)

    def _fire(
        self, person: str, action: str, via: str | None, platform: str | None, scope: str | None, day: str | None,
        want: Any = None, reason: str | None = None,
    ) -> None:
        start = end = None
        if isinstance(want, list):
            start, end = want
        self.hass.bus.async_fire(
            EVENT,
            {"person": person, "action": action, "via": via, "platform": platform, "scope": scope, "day": day,
             "start": start, "end": end, "reason": reason},
        )


def _keep_today(entry: dict[str, Any]) -> bool:
    """Tonight's entry is kept while it holds something: a write, a parent's value, a reading being checked."""
    return any(entry.get(k) for k in ("written", "follows", "theirs", "seen", "retry_at", "unsupported_for"))


def _app_value(entry: dict[str, Any]) -> list[str] | None:
    """What the app's weekly slot holds as far as Hearth knows: a parent's value, else Hearth's written, else wanted."""
    for key in ("theirs", "written", "want"):
        if entry.get(key) is not None:
            return entry[key]
    return None


def _matches(reading: Any, own: Any) -> bool:
    return any(reading == o or (isinstance(o, tuple) and isinstance(reading, list) and tuple(reading) == o)
               or (isinstance(o, str) and isinstance(reading, list) and reading[0] == o)
               for o in own)


def _offer_of(offer: dict[str, Any], person: str, target: Target) -> bool:
    return (offer["person"] == person and offer["via"] == target.via and offer.get("platform") == target.platform
            and offer.get("slot") == target.day)


def _long(key: str) -> str:
    return {"mon": "Monday", "tue": "Tuesday", "wed": "Wednesday", "thu": "Thursday", "fri": "Friday",
            "sat": "Saturday", "sun": "Sunday", DAY_OFF_KEY: "Day off"}.get(key, key)


def _say(value: str | None) -> str:
    if not value:
        return "none"
    return say_time(mins(value)) if value != "24:00" else "midnight"


def _reason_text(target: Target, reason: Any) -> str | None:
    if not isinstance(reason, str):
        return None
    if reason == "no_bedtime":
        return ("Family Link can't drop one day's bedtime" if target.via == FAMILY_LINK
                else "No bedtime that day")
    if reason == "past_next_day":
        return "A night past the next day can't be set in Family Link"
    if reason == "asleep_all_day":
        return "Asleep the whole day"
    return reason
