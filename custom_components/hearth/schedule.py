"""The household's schedule: what each kind of day does to the kids' Family Link, School time taken off and put back,
and the daily website list (docs/home-assistant-integration.md, Schedule).

Today's day type comes from School days (schooldays.py): school, half_day, day_off, weekend or no_school. Per day type
(Configure > Schedule):

- A day off: each kid's School time is switched off for the day (switch.turn_off on Family Link's School time switch,
  which turns off the weekly School time with today's), and put back on the next school day.
- A half day: School time ends some hours early, today only (familylink.set_school_time, scope today), for a kid whose
  School time is on; one whose School time is off gets the early end when it is put back.
- Both: bonus minutes, as Family Link's today-only daily limit (the weekday's limit plus the bonus, set_daily_limit
  without a day: an override that ends by itself) and/or as Hearth bonus minutes on a group.
- When chosen (bonus_family_safety, off by default), the same bonus reaches Family Safety (Windows, Xbox): for each
  platform of a kid's Family Safety enforcer, today's daily limit plus the bonus, today only
  (microsoft_family_safety.set_screentime_limit with today_only; Family Safety puts it back at midnight itself, and
  leaves a parent's own change alone). When a parent already changed today's limit for today only, the bonus goes on
  top of their value; Hearth keeps its own target to tell the two apart. Only with a Family Safety that takes
  today_only; an older one is skipped quietly. School time has no Family Safety equivalent, so a day off and a half
  day change nothing else there. A day off called off the same day (hearth.school_time_off_cancel), or today's day
  type changing away from a day off or half day, puts Family Safety's limit back at once: the one Hearth added to is
  written again, today only, and only while the platform still has Hearth's limit (a parent's change since stays).
- When chosen (bonus_nintendo, off by default), the same bonus reaches each chosen kid's Switch (their Nintendo
  enforcer's Max screentime today): today's limit plus the bonus (at most 360, the Switch's own maximum), set once per
  Switch even when kids share it. Nintendo has no today-only limit: the number is the setting of every day, or of
  this weekday, so Hearth keeps what it added to ("base", with the day, weekday, device and bedtime) in sw_limits,
  kept across a restart and midnight, and puts it back 2 minutes before midnight as the Nintendo enforcer does, or at
  once on a cancel or a day type that changed (as for Family Safety). Put back only while the limit still reads
  Hearth's: a parent's change since in the Nintendo app stays. After midnight (Home Assistant was off), a Switch with
  a limit per weekday gets that weekday's limit and bedtime back through update_daily_restrictions, as the enforcer
  does. A Switch with no limit (-1) is left alone: there's nothing to add to. While bonus time from the Nintendo app
  runs, the Switch refuses a new limit, so Hearth waits. While Hearth holds the Switch (limit 0 for a budget or a
  pause), nothing is written to it: the bonus goes into what the hold puts back (and comes out of it again on a
  cancel or at midnight), so letting go gives the raised limit and a hold never fights the bonus.

hearth.school_time_off takes School time off for some people on a date (today by default), from a time if given.

Putting School time back is the delicate part. Switching it on outside the kid's window opens a window from then until
23:59, so Hearth switches it on only inside the kid's own weekly window for today (some hours shorter on a half day),
then at once pins today's window to those hours (set_school_time, scope today), and checks each minute until the
child's devices say the pinned end. The weekly window is read from Family Link's time entities, and kept when School
time is taken off in case they read unknown while it's off. A kid whose window has ended is left for the next school
day. At the watchdog time on a school day, the adults are told about anyone whose School time is still off.

The day's actions run from DAY_START (00:05); a check at CHECK_AT (06:00) tries a School time that didn't go off again
and tells the adults what didn't apply, so nobody is woken at midnight. Each action runs once a day (kept across a
restart). The website list is synced once a day at its time, person by person, through Family Link
(familylink.sync_site_list) and Family Safety (microsoft_family_safety.sync_site_list, when it has it) each on its own:
a failure for one is logged, tried again later, and the others go on. The hearth_schedule events say which with "via".

What's pending is kept with Home Assistant's storage helper.
"""

from __future__ import annotations

import asyncio
from dataclasses import dataclass, field
from datetime import date, datetime, time, timedelta
import logging
import secrets
from typing import TYPE_CHECKING, Any

import voluptuous as vol

from homeassistant.components import persistent_notification
from homeassistant.core import HomeAssistant
from homeassistant.helpers.storage import Store
from homeassistant.util import dt as dt_util

from . import family_link as fl
from .enforce import (
    FAMILY_LINK,
    FAMILY_SAFETY,
    FS_DOMAIN,
    NINTENDO,
    QUIET_AFTER_CALL,
    Enforcer,
    enforcers_from_options,
    fs_account_of,
    near_midnight,
)
from .native_sync import fs_platform_state
from .schooldays import DAY_OFF, HALF_DAY, SCHOOL

if TYPE_CHECKING:
    from .household import Household

_LOGGER = logging.getLogger(__name__)

CONF_SCHEDULE = "schedule"
CONF_SITE_LIST = "site_list"
DAY_START = time(0, 5)
CHECK_AT = time(6, 0)
DEFAULT_WATCHDOG = time(10, 0)
DEFAULT_SITE_LIST_TIME = time(7, 30)
# A failed call is tried again after this long
RETRY = timedelta(minutes=5)
# A School time switched on or pinned isn't switched on or pinned again for this long (Family Link catching up)
SETTLE_CALL = timedelta(minutes=2)
MAX_REASON = 120
EVENT_SCHEDULE = "hearth_schedule"
# The reason of the School time off a day off takes
DAY_OFF_REASON = "Day off"
# Family Safety's today-only interface (a newer Family Safety)
FS_LIMIT = "set_screentime_limit"
FULL_DAY = 1440
# What a Family Safety platform's limit came to today: set (by Hearth), skip (nothing to add to: no limit)
FS_SET, FS_SKIP = "set", "skip"
# The most a Switch's Max screentime today takes (minutes); -1 is no limit
SWITCH_MAX = 360


def _clock(value: Any, default: time | None) -> time | None:
    if isinstance(value, time):
        return value
    if isinstance(value, str) and value.strip():
        try:
            return time.fromisoformat(value.strip()[:5] if len(value.strip()) >= 5 else value.strip())
        except ValueError:
            return default
    return default


def _number(value: Any, default: Any = 0) -> Any:
    try:
        number = float(value)
    except (TypeError, ValueError):
        return default
    return number if number == number else default


def _when(value: Any) -> datetime:
    """A kept UTC time, or long ago."""
    parsed = dt_util.parse_datetime(value) if isinstance(value, str) else None
    return parsed if parsed is not None else datetime.min.replace(tzinfo=dt_util.UTC)


@dataclass(frozen=True)
class ScheduleConfig:
    """Configure > Schedule: what each day type does. Empty: nothing."""

    day_off_school_time_off: bool = False
    day_off_bonus: int = 0
    half_day_hours_early: float = 0
    half_day_bonus: int = 0
    bonus_family_link: bool = True
    # Off unless chosen: a household that set this up for Family Link doesn't get its Windows and Xbox raised too
    bonus_family_safety: bool = False
    # Off unless chosen, as Family Safety's: the Switch's limit is a setting Hearth must put back itself
    bonus_nintendo: bool = False
    bonus_group: str | None = None
    # Whose (empty: everyone with Family Link, and for Family Safety's extra time everyone with Family Safety, in
    # Configure > Enforce)
    people: tuple[str, ...] = ()
    notify: str | None = None
    watchdog: time | None = DEFAULT_WATCHDOG
    # Set up at all (the watchdog only looks then)
    enabled: bool = False

    @classmethod
    def from_options(cls, options: dict[str, Any]) -> ScheduleConfig:
        raw = options.get(CONF_SCHEDULE) or {}
        return cls(
            enabled=bool(raw),
            day_off_school_time_off=bool(raw.get("day_off_school_time_off")),
            day_off_bonus=max(0, min(720, int(_number(raw.get("day_off_bonus"))))),
            half_day_hours_early=max(0.0, min(12.0, _number(raw.get("half_day_hours_early")))),
            half_day_bonus=max(0, min(720, int(_number(raw.get("half_day_bonus"))))),
            bonus_family_link=raw.get("bonus_family_link", True) is not False,
            bonus_family_safety=raw.get("bonus_family_safety") is True,
            bonus_nintendo=raw.get("bonus_nintendo") is True,
            bonus_group=raw.get("bonus_group") or None,
            people=tuple(raw.get("people") or ()),
            notify=raw.get("notify") or None,
            watchdog=None if raw.get("watchdog") == "off" else _clock(raw.get("watchdog"), DEFAULT_WATCHDOG),
        )


@dataclass(frozen=True)
class SiteListConfig:
    url: str | None = None
    at: time = DEFAULT_SITE_LIST_TIME
    people: tuple[str, ...] = ()

    @classmethod
    def from_options(cls, options: dict[str, Any]) -> SiteListConfig:
        raw = options.get(CONF_SITE_LIST) or {}
        url = (raw.get("url") or "").strip() or None
        return cls(url, _clock(raw.get("time"), DEFAULT_SITE_LIST_TIME) or DEFAULT_SITE_LIST_TIME, tuple(raw.get("people") or ()))


@dataclass
class Off:
    """School time taken off for a person on a day (from a time), put back from restore_from on."""

    id: str
    person: str
    day: date
    start: time | None = None
    reason: str = ""
    applied: bool = False
    restore_from: date | None = None
    # The weekly window when it was taken off: ISO weekday -> [start, end] (HH:MM)
    windows: dict[str, list[str]] = field(default_factory=dict)
    failed_at: datetime | None = None
    # Put back sooner, that day, when the person's place says so: {"arrive" | "leave": <place key>} (places.py)
    ends_on: dict[str, str] | None = None

    def view(self) -> dict[str, Any]:
        return {
            "id": self.id,
            "person": self.person,
            "date": self.day.isoformat(),
            "from": self.start.strftime("%H:%M") if self.start else None,
            "reason": self.reason,
            "applied": self.applied,
            "restore_from": self.restore_from.isoformat() if self.restore_from else None,
            **({"ends_on": dict(self.ends_on)} if self.ends_on else {}),
        }


def hours_earlier(end: time, hours: float) -> time:
    moved = datetime.combine(date(2000, 1, 1), end) - timedelta(hours=hours)
    return moved.time() if moved.date() == date(2000, 1, 1) else time(0, 0)


def hhmm(value: time) -> str:
    return value.strftime("%H:%M")


class Scheduler:
    def __init__(self, hass: HomeAssistant, household: Household, entry_id: str) -> None:
        self.hass = hass
        self.household = household
        self._store: Store[dict[str, Any]] = Store(hass, 1, f"hearth.schedule.{entry_id}")
        self.offs: dict[str, Off] = {}
        # Today's marks: what ran today, person -> marks (and "" for the household's)
        self.day: str | None = None
        self.marks: dict[str, list[str]] = {}
        # person -> the Family Link daily limit set for today (checked at CHECK_AT)
        self.limits_set: dict[str, int] = {}
        # person -> platform -> the today-only Family Safety limit Hearth set today ("target") and the limit it added
        # to ("base"): tells Hearth's own today-only change from a parent's, and what a cancel goes back to
        self.fs_limits: dict[str, dict[str, dict[str, int]]] = {}
        # Switch (its Max screentime today entity) -> the limit Hearth set for the day's extra ("target"), the one it
        # added to ("base"), whose it is ("people"), and what putting it back after midnight needs (day, weekday,
        # device_id, bedtime_alarm, bedtime_end_time). Kept until it's put back, over midnight and a restart too
        self.sw_limits: dict[str, dict[str, Any]] = {}
        self._lock = asyncio.Lock()
        self._failed: dict[str, datetime] = {}
        self._done_at: dict[str, datetime] = {}

    # Storage

    async def async_load(self) -> None:
        stored = await self._store.async_load() or {}
        self.day = stored.get("day")
        self.marks = {k: list(v) for k, v in (stored.get("marks") or {}).items()}
        self.limits_set = {k: int(v) for k, v in (stored.get("limits_set") or {}).items()}
        self.fs_limits = {}
        for person, platforms in (stored.get("fs_limits") or {}).items():
            for platform, held in (platforms or {}).items() if isinstance(platforms, dict) else ():
                try:
                    kept = {"target": int(held["target"]), "base": int(held["base"])}
                except (KeyError, TypeError, ValueError):
                    continue
                self.fs_limits.setdefault(person, {})[platform] = kept
        self.sw_limits = {}
        for entity_id, held in (stored.get("sw_limits") or {}).items():
            try:
                kept_sw = {**held, "target": int(held["target"]), "base": int(held["base"]), "day": str(held["day"])}
            except (KeyError, TypeError, ValueError):
                continue
            self.sw_limits[entity_id] = kept_sw
        for raw in stored.get("offs", []):
            try:
                off = Off(
                    raw["id"],
                    raw["person"],
                    date.fromisoformat(raw["date"]),
                    _clock(raw.get("from"), None),
                    raw.get("reason") or "",
                    bool(raw.get("applied")),
                    date.fromisoformat(raw["restore_from"]) if raw.get("restore_from") else None,
                    dict(raw.get("windows") or {}),
                    ends_on=dict(raw["ends_on"]) if isinstance(raw.get("ends_on"), dict) and raw["ends_on"] else None,
                )
            except (KeyError, ValueError):
                continue
            self.offs[off.id] = off

    def _data(self) -> dict[str, Any]:
        return {
            "day": self.day,
            "marks": self.marks,
            "limits_set": self.limits_set,
            "fs_limits": self.fs_limits,
            "sw_limits": self.sw_limits,
            "offs": [
                {
                    "id": o.id,
                    "person": o.person,
                    "date": o.day.isoformat(),
                    "from": hhmm(o.start) if o.start else None,
                    "reason": o.reason,
                    "applied": o.applied,
                    "restore_from": o.restore_from.isoformat() if o.restore_from else None,
                    "windows": o.windows,
                    "ends_on": o.ends_on,
                }
                for o in self.offs.values()
            ],
        }

    def _save(self) -> None:
        self._store.async_delay_save(self._data, 2)

    async def async_flush(self) -> None:
        await self._store.async_save(self._data())

    # Who and what

    @property
    def config(self) -> ScheduleConfig:
        return ScheduleConfig.from_options(self.household.options)

    def family_link_entity(self, person: str) -> str | None:
        """The person's Family Link entity (Configure > Enforce)."""
        return next(
            (
                e.entity_id
                for e in enforcers_from_options(self.household.options)
                if e.kind == FAMILY_LINK and e.person == person
            ),
            None,
        )

    def child(self, person: str) -> str | None:
        entity_id = self.family_link_entity(person)
        return fl.child_of(self.hass, entity_id) if entity_id else None

    def people(self, chosen: tuple[str, ...] = ()) -> list[str]:
        """The chosen people with Family Link, or everyone with Family Link."""
        with_fl = [
            e.person for e in enforcers_from_options(self.household.options) if e.kind == FAMILY_LINK
        ]
        return sorted(set(chosen) & set(with_fl)) if chosen else sorted(set(with_fl))

    def _mark(self, who: str, what: str) -> None:
        self.marks.setdefault(who, []).append(what)
        self._save()

    def _marked(self, who: str, what: str) -> bool:
        return what in self.marks.get(who, [])

    def off_now(self, person: str, now: datetime | None = None) -> Off | None:
        """School time is off for the person by Hearth now (taken off, not put back yet)."""
        return next((o for o in self.offs.values() if o.person == person and o.applied), None)

    def window_today(self, person: str, now: datetime | None = None) -> tuple[datetime, datetime] | None:
        """The person's School time today (a school or half day with a Family Link window), as local datetimes."""
        now = now or dt_util.now()
        today = now.date()
        kind = self.day_type(today)
        child = self.child(person)
        if kind not in (SCHOOL, HALF_DAY) or child is None:
            return None
        window = self._window(person, child, today, kind, self.config)
        if window is None:
            return None
        zone = now.tzinfo
        return datetime.combine(today, window[0], zone), datetime.combine(today, window[1], zone)

    def offs_of(self, person: str) -> list[dict[str, Any]]:
        return [o.view() for o in sorted(self.offs.values(), key=lambda o: (o.day, o.id)) if o.person == person]

    # Services

    def take_off(
        self,
        people: list[str],
        day: date,
        start: time | None,
        reason: str | None,
        ends_on: dict[str, str] | None = None,
    ) -> list[str]:
        ids: list[str] = []
        for person in people:
            same = next(
                (o for o in self.offs.values() if o.person == person and o.day == day and not o.applied), None
            )
            if same is not None:
                same.start, same.reason = start, (reason or same.reason or "").strip()[:MAX_REASON]
                same.ends_on = dict(ends_on) if ends_on else None
                ids.append(same.id)
                continue
            off = Off(secrets.token_hex(6), person, day, start, (reason or "").strip()[:MAX_REASON])
            off.ends_on = dict(ends_on) if ends_on else None
            self.offs[off.id] = off
            ids.append(off.id)
        self._save()
        return ids

    def cancel(self, people: list[str] | None, day: date | None) -> list[str]:
        """Not taken off yet: dropped. Taken off: put back from today (inside the window, as always).

        On a day off, a cancel for today also calls off the day's Family Safety and Switch extra time (put back as the
        tick gets to it, and not set again today) for each person with either it names (everyone without people), whether
        or not School time was taken off: Family Safety has no School time, and a day off only takes School time off
        when the schedule says so. A cancel that only drops a later School time off (from a time, or another day)
        leaves it."""
        today = dt_util.now().date()
        changed: list[str] = []
        touched: dict[str, list[Off]] = {}
        for off in list(self.offs.values()):
            if people is not None and off.person not in people:
                continue
            if day is not None and off.day != day:
                continue
            touched.setdefault(off.person, []).append(off)
            if off.applied:
                off.restore_from = today
            else:
                del self.offs[off.id]
            changed.append(off.id)
        if (day is None or day == today) and self.day == today.isoformat() and self.day_type(today) == DAY_OFF:
            for with_it, mark in ((self.family_safety_people(), "fs_cancel"), (self.nintendo_people(), "sw_cancel")):
                for person in with_it:
                    if people is not None and person not in people:
                        continue
                    offs = touched.get(person)
                    if offs and all(o.day != today or o.start is not None for o in offs):
                        continue
                    if not self._marked(person, mark):
                        self._mark(person, mark)
        self._save()
        return changed

    def ending_on_place(self, person: str, today: date) -> list[Off]:
        """The person's School time off today that a place can end: not put back yet, with an ends_on."""
        return [
            o
            for o in self.offs.values()
            if o.person == person
            and o.ends_on
            and o.day == today
            and (o.restore_from is None or o.restore_from > today)
        ]

    def end_one(self, off: Off) -> None:
        """As school_time_off_cancel for this one: not taken off yet, dropped; taken off, put back from today."""
        if off.applied:
            off.restore_from = dt_util.now().date()
        else:
            self.offs.pop(off.id, None)
        self._save()

    # The minute's work

    def day_type(self, today: date) -> str:
        school = self.household.school
        return school.day_type if school.day == today else school.decide_type(today)

    async def async_tick(self, now: datetime | None = None) -> None:
        if self._lock.locked():
            return
        async with self._lock:
            await self._tick(now or dt_util.now())

    async def _tick(self, now: datetime) -> None:
        today = now.date()
        if self.day != today.isoformat():
            self.day, self.marks, self.limits_set, self.fs_limits = today.isoformat(), {}, {}, {}
            self._save()
        kind = self.day_type(today)
        config = self.config
        people = self.people(config.people)
        clock = now.time()
        if clock >= DAY_START:
            for person in people:
                await self._day_actions(person, kind, config, today)
            for person in self.family_safety_people(config.people):
                await self._family_safety_day(person, kind, config, today)
        await self._nintendo_day(now, kind, config)
        await self._take_off_due(now)
        if kind in (SCHOOL, HALF_DAY):
            await self._put_back(now, kind, config)
        if clock >= CHECK_AT and not self._marked("", "checked"):
            self._mark("", "checked")
            await self._check(people, kind, config, today)
        if (
            config.enabled
            and config.watchdog is not None
            and kind in (SCHOOL, HALF_DAY)
            and clock >= config.watchdog
            and not self._marked("", "watchdog")
        ):
            self._mark("", "watchdog")
            self._watchdog(people, today)
        await self._site_list(now)

    async def _day_actions(self, person: str, kind: str, config: ScheduleConfig, today: date) -> None:
        if kind == DAY_OFF and config.day_off_school_time_off and not self._marked(person, "off"):
            self._mark(person, "off")
            self.take_off([person], today, None, DAY_OFF_REASON)
        if kind == HALF_DAY and config.half_day_hours_early and not self._marked(person, "early"):
            if await self._end_early(person, today, config.half_day_hours_early):
                self._mark(person, "early")
        minutes = config.day_off_bonus if kind == DAY_OFF else config.half_day_bonus if kind == HALF_DAY else 0
        if minutes and config.bonus_family_link and not self._marked(person, "bonus_fl"):
            if await self._family_link_bonus(person, today, minutes):
                self._mark(person, "bonus_fl")
        if minutes and config.bonus_group and not self._marked(person, "bonus_hearth"):
            if self.household.group(config.bonus_group) is not None:
                self._mark(person, "bonus_hearth")
                self.household.add_bonus(person, config.bonus_group, minutes)

    def _did(self, key: str) -> None:
        self._done_at[key] = dt_util.utcnow()

    def _recent(self, key: str) -> bool:
        done = self._done_at.get(key)
        return done is not None and dt_util.utcnow() - done < SETTLE_CALL

    def _waiting(self, key: str) -> bool:
        failed = self._failed.get(key)
        return failed is not None and dt_util.utcnow() - failed < RETRY

    async def _call(self, key: str, domain: str, service: str, data: dict[str, Any]) -> bool:
        """A call that may fail: logged, tried again after RETRY."""
        if self._waiting(key):
            return False
        try:
            await self.hass.services.async_call(domain, service, data, blocking=True)
        except Exception as err:  # noqa: BLE001 - one person's failure mustn't stop the others
            _LOGGER.warning("Hearth's schedule: %s.%s failed for %s: %s", domain, service, key, err)
            self._failed[key] = dt_util.utcnow()
            return False
        self._failed.pop(key, None)
        return True

    async def _end_early(self, person: str, today: date, hours: float) -> bool:
        """Today's School time ends [hours] early, if it's on (one whose School time is off gets it when put back)."""
        child = self.child(person)
        switch = fl.school_time_switch(self.hass, child) if child else None
        state = self.hass.states.get(switch) if switch else None
        if state is None or state.state != "on":
            return True
        window = fl.weekly_window(self.hass, child, today)
        if window is None:
            return True
        end = hours_earlier(window[1], hours)
        ok = await self._call(
            f"{person}|early",
            "familylink",
            "set_school_time",
            {"entity_id": switch, "scope": "today", "start_time": hhmm(window[0]), "end_time": hhmm(end)},
        )
        if ok:
            self._event("half_day", person, end=hhmm(end))
        return ok

    async def _family_link_bonus(self, person: str, today: date, minutes: int) -> bool:
        """Today's daily limit = the weekday's limit + [minutes], as a today-only override (no day)."""
        child = self.child(person)
        if child is None:
            return True
        switch = fl.daily_limit_switch(self.hass, child)
        switch_state = self.hass.states.get(switch) if switch else None
        if switch_state is not None and switch_state.state != "on":
            return True  # no daily limit today: nothing to add to
        limit = fl.weekday_limit(self.hass, child, today)
        weekly = limit.get("weekly_minutes") if limit else None
        if not isinstance(weekly, (int, float)):
            return True
        target = int(weekly) + minutes
        # The child's id as a string, never a template: Home Assistant reads 21 digits as a number and loses some
        ok = await self._call(
            f"{person}|limit", "familylink", "set_daily_limit", {"child_id": str(child), "daily_minutes": target}
        )
        if ok:
            self.limits_set[person] = target
            self._save()
            self._event("bonus", person, minutes=minutes, daily_minutes=target)
        return ok

    # Family Safety (Windows, Xbox): the day's extra minutes as a today-only daily limit

    def family_safety_enforcer(self, person: str) -> Enforcer | None:
        return next(
            (
                e
                for e in enforcers_from_options(self.household.options)
                if e.kind == FAMILY_SAFETY and e.person == person
            ),
            None,
        )

    def family_safety_people(self, chosen: tuple[str, ...] = ()) -> list[str]:
        """The chosen people with Family Safety, or everyone with Family Safety."""
        with_fs = [e.person for e in enforcers_from_options(self.household.options) if e.kind == FAMILY_SAFETY]
        return sorted(set(chosen) & set(with_fs)) if chosen else sorted(set(with_fs))

    def _fs_data(self, entity_id: str, service: str, fields: dict[str, Any]) -> dict[str, Any] | None:
        """The call's data when this Family Safety takes it (its schema accepts it: a newer one, with today_only),
        targeting the child's entity, else its account id; None when it doesn't (an older one: skipped quietly)."""
        services = self.hass.services.async_services_for_domain(FS_DOMAIN)
        found = services.get(service)
        if found is None:
            return None
        targets = [{"entity_id": entity_id}] if "." in entity_id else []
        account = fs_account_of(self.hass, entity_id)
        if account is not None:
            targets.append({"account_id": account})
        for target in targets:
            data = {**target, **fields}
            if found.schema is None:
                return data
            try:
                found.schema(dict(data))
            except vol.Invalid:
                continue
            return data
        return None

    def _fs_pending(self, entity_id: str, platform: str, today: date) -> dict[str, Any] | None:
        """Today's today-only change of the platform, from the child's Screen time policy sensor's today_only
        attribute ({platform: {date, restores_at, limit_minutes, restore_limit_minutes, ...}})."""
        account = fs_account_of(self.hass, entity_id)
        if account is None:
            return None
        for state in self.hass.states.async_all("sensor"):
            if not state.entity_id.endswith("_screen_time_policy") or str(state.attributes.get("user_id")) != account:
                continue
            pending = state.attributes.get("today_only")
            entry = pending.get(platform) if isinstance(pending, dict) else None
            if isinstance(entry, dict) and entry.get("date") == today.isoformat():
                return entry
        return None

    def _written_today(self, entity_id: str | None, today: date) -> bool:
        """Family Safety wrote the entity since local midnight (a poll writes it even when nothing changed:
        last_reported; it says no date of its own)."""
        state = self.hass.states.get(entity_id) if entity_id else None
        if state is None:
            return False
        written = max(state.last_updated, getattr(state, "last_reported", None) or state.last_updated)
        return dt_util.as_local(written).date() >= today

    def _fs_limit_wanted(self, enforcer: Enforcer, config: ScheduleConfig) -> bool:
        """Family Safety takes part: its extra minutes are chosen (Configure > Schedule) and it has today_only."""
        return config.bonus_family_safety and self._fs_data(
            enforcer.entity_id, FS_LIMIT, {"platform": "Windows", "today_only": True, "hours": 1, "minutes": 0}
        ) is not None

    async def _family_safety_day(self, person: str, kind: str, config: ScheduleConfig, today: date) -> None:
        enforcer = self.family_safety_enforcer(person)
        if enforcer is None:
            return
        if (
            kind not in (DAY_OFF, HALF_DAY)
            and not self._marked(person, "fs_cancel")
            and any(self._marked(person, f"fs_set:{p}") for p in enforcer.platforms)
        ):
            # Today isn't a day off or a half day any more (School days changed): its extra time goes back
            self._mark(person, "fs_cancel")
        if self._marked(person, "fs_cancel"):
            await self._family_safety_restore(person, enforcer, today)
            return
        minutes = config.day_off_bonus if kind == DAY_OFF else config.half_day_bonus if kind == HALF_DAY else 0
        if not minutes or not self._fs_limit_wanted(enforcer, config):
            return
        for platform in enforcer.platforms:
            if self._marked(person, f"bonus_fs:{platform}"):
                continue
            done = await self._family_safety_limit(person, enforcer, platform, today, minutes)
            if done is not None:
                self._mark(person, f"bonus_fs:{platform}")
            if done == FS_SET:
                self._mark(person, f"fs_set:{platform}")

    async def _family_safety_limit(
        self, person: str, enforcer: Enforcer, platform: str, today: date, minutes: int
    ) -> str | None:
        """Today's daily limit of the platform = today's limit + [minutes], today only. FS_SET, FS_SKIP (no limit
        today: nothing to add to), or None when not done (not read yet, or the call failed: tried again).

        Today's limit is a today-only one already set for today by someone else (a parent in the Family Safety app or
        an automation: the extra goes on top of theirs, so their cut or raise stays), else the platform's allowance.
        Hearth's own today-only limit (kept in fs_limits) is never added to again."""
        pending = self._fs_pending(enforcer.entity_id, platform, today)
        pending_limit = int(_number(pending.get("limit_minutes"), -1)) if pending else -1
        mine = self.fs_limits.get(person, {}).get(platform)
        if mine is not None and pending_limit == mine["target"]:
            return FS_SET  # already (a restart before it was marked)
        base: float = pending_limit
        if base >= FULL_DAY:
            return FS_SKIP
        if base < 0:
            # Today's limit as Family Safety says it (its Allowed Now / Time Remaining attributes)
            state = fs_platform_state(self.hass, enforcer.entity_id, platform)
            if state is None or not self._written_today(state.get("entity_id"), today):
                # Not read since midnight yet: its allowance may still be yesterday's. Read again next minute
                return None
            allowance = _number(state.get("allowance_minutes"), -1)
            if state.get("reason") == "no_limits" or allowance >= FULL_DAY:
                return FS_SKIP
            if allowance < 0:
                return None  # locked or extra time now: the allowance isn't said; read again next minute
            base = allowance
        target = min(FULL_DAY, int(base) + minutes)
        hours, rest = divmod(target, 60)
        data = self._fs_data(
            enforcer.entity_id,
            FS_LIMIT,
            {"platform": platform, "today_only": True, "hours": hours, "minutes": rest},
        )
        if data is None:
            return FS_SKIP
        # Kept before the call: one that reached Family Safety but whose answer was lost is still known as Hearth's
        self.fs_limits.setdefault(person, {})[platform] = {"target": target, "base": int(base)}
        await self.async_flush()
        if not await self._call(f"{person}|fs_limit:{platform}", FS_DOMAIN, FS_LIMIT, data):
            return None
        self._event("bonus", person, via="family_safety", platform=platform, minutes=minutes, daily_minutes=target)
        return FS_SET

    async def _family_safety_restore(self, person: str, enforcer: Enforcer, today: date) -> None:
        """Today's extra was called off: each platform Hearth set today goes back now, once, to the limit Hearth added
        to (set_screentime_limit, today only: the weekly value ends Family Safety's today-only change, a parent's
        today-only value stays theirs till midnight). Never restore_today_only: it puts back every today-only change of
        the platform, a parent's later one too. Only while the platform still has Hearth's limit: when a parent changed
        it since, or it's back already, theirs stays."""
        for platform in enforcer.platforms:
            if not self._marked(person, f"fs_set:{platform}") or self._marked(person, f"fs_back:{platform}"):
                continue
            mine = self.fs_limits.get(person, {}).get(platform)
            pending = self._fs_pending(enforcer.entity_id, platform, today)
            if (
                mine is None
                or pending is None
                or int(_number(pending.get("limit_minutes"), -1)) != mine["target"]
            ):
                # Not Hearth's limit any more (or not known as Hearth's): left alone; midnight puts Hearth's back
                self._mark(person, f"fs_back:{platform}")
                continue
            hours, rest = divmod(mine["base"], 60)
            data = self._fs_data(
                enforcer.entity_id,
                FS_LIMIT,
                {"platform": platform, "today_only": True, "hours": hours, "minutes": rest},
            )
            if data is None:
                # Family Safety can't put it back early: it does at midnight
                self._mark(person, f"fs_back:{platform}")
                continue
            if await self._call(f"{person}|fs_back:{platform}", FS_DOMAIN, FS_LIMIT, data):
                self._mark(person, f"fs_back:{platform}")
                self._event(
                    "bonus_back", person, via="family_safety", platform=platform, daily_minutes=mine["base"]
                )

    # Nintendo Switch: the day's extra minutes on its Max screentime today, put back by Hearth

    def nintendo_switches(self, chosen: tuple[str, ...] = ()) -> dict[str, list[str]]:
        """Each Switch of the chosen people's Nintendo enforcers (everyone's without), with its people: a Switch two
        kids share is one."""
        found: dict[str, list[str]] = {}
        for e in enforcers_from_options(self.household.options):
            if e.kind == NINTENDO and (not chosen or e.person in chosen):
                people = found.setdefault(e.entity_id, [])
                if e.person not in people:
                    people.append(e.person)
        return found

    def nintendo_people(self, chosen: tuple[str, ...] = ()) -> list[str]:
        return sorted({p for people in self.nintendo_switches(chosen).values() for p in people})

    async def _nintendo_day(self, now: datetime, kind: str, config: ScheduleConfig) -> None:
        """What Hearth added to a Switch goes back when due (a later day, just before midnight, a cancel, a day type
        that changed); then a day off or half day's extra goes on each chosen Switch, once a day."""
        today = now.date()
        late = near_midnight(now)
        extra_day = kind in (DAY_OFF, HALF_DAY)
        for entity_id, mine in list(self.sw_limits.items()):
            people = mine.get("people") or []
            due = (
                mine["day"] != today.isoformat()
                or late
                or not extra_day
                or bool(people and all(self._marked(p, "sw_cancel") for p in people))
            )
            if due and await self._nintendo_restore(entity_id, mine, today):
                self.sw_limits.pop(entity_id, None)
                self._mark("", f"sw_back:{entity_id}")
                self._save()
        minutes = config.day_off_bonus if kind == DAY_OFF else config.half_day_bonus if kind == HALF_DAY else 0
        if not minutes or not config.bonus_nintendo or late or now.time() < DAY_START:
            return
        for entity_id, people in self.nintendo_switches(config.people).items():
            if self._marked("", f"bonus_sw:{entity_id}") or self._marked("", f"sw_back:{entity_id}"):
                continue
            if all(self._marked(p, "sw_cancel") for p in people):
                continue
            done = await self._nintendo_bonus(entity_id, people, minutes, today)
            if done is not None:
                self._mark("", f"bonus_sw:{entity_id}")

    async def _nintendo_bonus(self, entity_id: str, people: list[str], minutes: int, today: date) -> str | None:
        """Today's limit of the Switch + [minutes]. FS_SET, FS_SKIP (no limit, or at the most already), or None when
        not done (not read, bonus time running, Hearth's hold under way, the call failed: tried again)."""
        enforcement = self.household.enforcement
        mine = self.sw_limits.get(entity_id)
        state = self.hass.states.get(entity_id)
        current = _number(state.state if state else None, None)
        hold = enforcement.switch_hold(entity_id)
        if mine is not None and mine["day"] == today.isoformat():
            # Already (a restart before it was marked): never added to twice
            if (hold is not None and hold.restore.get("max") == mine["target"]) or current == mine["target"]:
                return FS_SET
            if not mine.get("via_hold") and dt_util.utcnow() - _when(mine.get("written_at")) < QUIET_AFTER_CALL:
                return None  # just written: the Switch's limit doesn't read it yet
            return FS_SKIP  # changed since (a parent): theirs
        if enforcement.switch_quiet(entity_id):
            return None
        if hold is not None:
            # Held (limit 0): nothing is written to the Switch. The extra goes into what letting go puts back
            if hold.restore.get("adopted"):
                return None  # a parent's change lets the hold go: then their limit is the one to add to
            if current != 0:
                # Not reading the hold's 0 yet: changing what it puts back now would look like a parent's change
                return None
            base = _number(hold.restore.get("max"), None)
        else:
            if enforcement.switch_extended(entity_id):
                return None  # bonus time from the Nintendo app runs: the Switch refuses a new limit till it's over
            base = current
        if base is None:
            return None
        if base < 0 or base >= SWITCH_MAX:
            return FS_SKIP  # no limit, or the most already: nothing to add to
        target = min(SWITCH_MAX, int(base) + minutes)
        # Kept before any change: one that reached Nintendo but whose answer was lost is still known as Hearth's
        self.sw_limits[entity_id] = {
            "target": target,
            "base": int(base),
            "people": list(people),
            "via_hold": hold is not None,
            "written_at": dt_util.utcnow().isoformat(),
            **enforcement.switch_day(entity_id),
        }
        await self.async_flush()
        if hold is not None:
            hold.restore["max"] = target
            enforcement.save()
        elif not await self._call(
            f"sw_limit:{entity_id}", "number", "set_value", {"entity_id": entity_id, "value": target}
        ):
            return None
        for person in people:
            self._event("bonus", person, via="nintendo", switch=entity_id, minutes=minutes, daily_minutes=target)
        return FS_SET

    async def _nintendo_restore(self, entity_id: str, mine: dict[str, Any], today: date) -> bool:
        """The limit Hearth added to goes back, only while the Switch has Hearth's: True when done (put back, or a
        parent's change left alone), False to try again next minute."""
        enforcement = self.household.enforcement
        target, base = mine["target"], mine["base"]
        later_day = mine["day"] != today.isoformat()
        if enforcement.switch_quiet(entity_id):
            return False
        hold = enforcement.switch_hold(entity_id)
        if hold is not None:
            # Held now: letting go puts the base back instead (a parent's change, adopted by the hold, stays)
            if hold.restore.get("max") == target and not hold.restore.get("adopted"):
                state = self.hass.states.get(entity_id)
                if _number(state.state if state else None, None) != 0:
                    # Not reading the hold's 0: the hold finds out first whether it's a parent's change
                    return False
                hold.restore["max"] = base
                enforcement.save()
                self._back(entity_id, mine)
            return True
        if later_day and enforcement.switch_each_day(entity_id):
            # Not put back before midnight (Home Assistant was off): today's limit is another weekday's, so that
            # weekday's own goes back with its bedtime (unread: Nintendo shows only today's)
            await enforcement.put_back_weekday(entity_id, mine, base)
            self._back(entity_id, mine)
            return True
        state = self.hass.states.get(entity_id)
        current = _number(state.state if state else None, None)
        if current is None or (current == 0 and target != 0):
            # Not read, or 0: Hearth's hold may have just let go and the Switch not caught up yet. Tried again; on a
            # later day a 0 isn't Hearth's any more
            return later_day and current is not None
        if current != target:
            if current == base and dt_util.utcnow() - _when(mine.get("written_at")) < QUIET_AFTER_CALL:
                return False  # just written: not read back yet
            _LOGGER.info("%s reads %s, not Hearth's %s: a parent's change, left alone", entity_id, current, target)
            return True
        if enforcement.switch_extended(entity_id):
            return False  # the Switch refuses a new limit while the Nintendo app's bonus time runs
        if not await self._call(f"sw_back:{entity_id}", "number", "set_value", {"entity_id": entity_id, "value": base}):
            return False
        self._back(entity_id, mine)
        return True

    def _back(self, entity_id: str, mine: dict[str, Any]) -> None:
        for person in mine.get("people") or []:
            self._event("bonus_back", person, via="nintendo", switch=entity_id, daily_minutes=mine["base"])

    async def _take_off_due(self, now: datetime) -> None:
        today = now.date()
        for off in list(self.offs.values()):
            if off.applied:
                continue
            if off.day < today:
                # Its day passed with Home Assistant off: nothing to take off any more
                _LOGGER.info("Hearth's schedule: School time off for %s on %s was missed", off.person, off.day)
                del self.offs[off.id]
                self._save()
                continue
            if off.day > today or (off.start is not None and now.time() < off.start):
                continue
            child = self.child(off.person)
            switch = fl.school_time_switch(self.hass, child) if child else None
            if switch is None:
                _LOGGER.warning("Hearth's schedule: no Family Link School time switch for %s", off.person)
                del self.offs[off.id]
                self._save()
                continue
            # The weekly windows, kept in case they read unknown while School time is off
            for day_n in range(7):
                weekday = today + timedelta(days=day_n)
                if (window := fl.weekly_window(self.hass, child, weekday)) is not None:
                    off.windows[str(weekday.isoweekday())] = [hhmm(window[0]), hhmm(window[1])]
            if await self._call(f"{off.person}|off", "switch", "turn_off", {"entity_id": switch}):
                off.applied = True
                off.restore_from = off.restore_from or off.day + timedelta(days=1)
                self._save()
                self._event("school_time_off", off.person, reason=off.reason)
                # The School-time apps are let go at once (the child's devices take a minute to say so)
                self.household.recompute()

    def _window(self, person: str, child: str, today: date, kind: str, config: ScheduleConfig) -> tuple[time, time] | None:
        window = fl.weekly_window(self.hass, child, today)
        if window is None:
            kept = next(
                (
                    o.windows[str(today.isoweekday())]
                    for o in self.offs.values()
                    if o.person == person and str(today.isoweekday()) in o.windows
                ),
                None,
            )
            if kept is None:
                return None
            window = (time.fromisoformat(kept[0]), time.fromisoformat(kept[1]))
        start, end = window
        if kind == HALF_DAY and config.half_day_hours_early:
            end = hours_earlier(end, config.half_day_hours_early)
        return (start, end) if start < end else None

    async def _put_back(self, now: datetime, kind: str, config: ScheduleConfig) -> None:
        today = now.date()
        due: dict[str, list[Off]] = {}
        for off in self.offs.values():
            if off.applied and off.restore_from is not None and off.restore_from <= today:
                due.setdefault(off.person, []).append(off)
        for person, offs in due.items():
            # Taken off for today too (from a time): not put back today
            if any(o.day == today and not o.applied for o in self.offs.values() if o.person == person):
                continue
            child = self.child(person)
            switch = fl.school_time_switch(self.hass, child) if child else None
            if child is None or switch is None:
                continue
            window = self._window(person, child, today, kind, config)
            if window is None:
                if not any(o.windows for o in offs) and not self._has_any_window(child, today):
                    # No School time in the whole week, then or now: there's nothing to put back
                    for off in offs:
                        self.offs.pop(off.id, None)
                    self._save()
                continue
            start, end = window
            if not (start <= now.time() < end):
                continue
            state = self.hass.states.get(switch)
            pin = {"entity_id": switch, "scope": "today", "start_time": hhmm(start), "end_time": hhmm(end)}
            if state is None or state.state != "on":
                # On only inside the window, and pinned at once: on alone opens a window until 23:59. Not again
                # while Family Link catches up
                if self._recent(f"{person}|on"):
                    continue
                if await self._call(f"{person}|on", "switch", "turn_on", {"entity_id": switch}):
                    self._did(f"{person}|on")
                    self._failed.pop(f"{person}|pin", None)
                    if await self._call(f"{person}|pin", "familylink", "set_school_time", pin):
                        self._did(f"{person}|pin")
                continue
            said = fl.school_time_end(self.hass, child)
            if said is not None and hhmm(dt_util.as_local(said).time()) != hhmm(end):
                # Pinned again until the devices say so (Family Link is read once a minute)
                if not self._recent(f"{person}|pin") and await self._call(
                    f"{person}|pin", "familylink", "set_school_time", pin
                ):
                    self._did(f"{person}|pin")
                continue
            for off in offs:
                self.offs.pop(off.id, None)
            self._save()
            self._event("school_time_back", person, end=hhmm(end))
            self.household.recompute()

    def _has_any_window(self, child: str, today: date) -> bool:
        return any(fl.weekly_window(self.hass, child, today + timedelta(days=n)) for n in range(7))

    async def _check(self, people: list[str], kind: str, config: ScheduleConfig, today: date) -> None:
        """At CHECK_AT: a School time that should be off and isn't is switched off again; what didn't apply is told."""
        problems: list[str] = []
        for off in self.offs.values():
            if off.applied and off.day == today and off.start is None:
                child = self.child(off.person)
                switch = fl.school_time_switch(self.hass, child) if child else None
                state = self.hass.states.get(switch) if switch else None
                if state is not None and state.state == "on":
                    self._failed.pop(f"{off.person}|off", None)
                    await self._call(f"{off.person}|off", "switch", "turn_off", {"entity_id": switch})
                    problems.append(f"{self.household.person_name(off.person)}'s School time is still on")
        for person, target in self.limits_set.items():
            child = self.child(person)
            limit = fl.weekday_limit(self.hass, child, today) if child else None
            override = limit.get("override_minutes") if limit else None
            if override is not None and int(_number(override, -1)) != target:
                problems.append(f"{self.household.person_name(person)}'s extra time didn't apply")
        minutes = config.day_off_bonus if kind == DAY_OFF else config.half_day_bonus if kind == HALF_DAY else 0
        if minutes and config.bonus_family_link:
            for person in people:
                if not self._marked(person, "bonus_fl"):
                    problems.append(f"{self.household.person_name(person)}'s extra time couldn't be set")
        fs_problems: list[str] = []
        for person in self.family_safety_people(config.people) if minutes else []:
            enforcer = self.family_safety_enforcer(person)
            if enforcer is None or self._marked(person, "fs_cancel") or not self._fs_limit_wanted(enforcer, config):
                continue
            missing = [p for p in enforcer.platforms if not self._marked(person, f"bonus_fs:{p}")]
            if missing:
                fs_problems.append(
                    f"{self.household.person_name(person)}'s {' and '.join(missing)} extra time couldn't be set"
                )
        sw_problems: list[str] = []
        switches = self.nintendo_switches(config.people) if minutes and config.bonus_nintendo else {}
        for entity_id, owners in switches.items():
            if self._marked("", f"bonus_sw:{entity_id}") or all(self._marked(p, "sw_cancel") for p in owners):
                continue
            names = " and ".join(self.household.person_name(p) for p in owners)
            sw_problems.append(f"{names}'s Switch extra time couldn't be set")
        if problems or fs_problems or sw_problems:
            apps = (("Family Link", problems), ("Family Safety", fs_problems), ("the Nintendo app", sw_problems))
            where = " and ".join(name for name, found in apps if found)
            message = ". ".join(problems + fs_problems + sw_problems) + f". Check {where}."
            self.tell("Today's schedule", message, "hearth_schedule_check")

    def _watchdog(self, people: list[str], today: date) -> None:
        off: list[str] = []
        for person in people:
            if any(o.person == person and o.day == today for o in self.offs.values()):
                continue  # taken off for today on purpose
            child = self.child(person)
            switch = fl.school_time_switch(self.hass, child) if child else None
            state = self.hass.states.get(switch) if switch else None
            if state is not None and state.state == "off":
                off.append(self.household.person_name(person))
        if off:
            self.tell(
                "School time is off on a school day",
                f"Family Link School time is still off for {', '.join(off)}. Check Family Link.",
                "hearth_school_time_watchdog",
            )

    def family_safety_entity(self, person: str) -> str | None:
        """The person's Family Safety entity or typed-in account id (Configure > Enforce)."""
        return next(
            (
                e.entity_id
                for e in enforcers_from_options(self.household.options)
                if e.kind == FAMILY_SAFETY and e.person == person
            ),
            None,
        )

    def site_list_people(self, chosen: tuple[str, ...] = ()) -> list[str]:
        """The chosen people with Family Link or Family Safety, or everyone with either."""
        with_any = [
            e.person
            for e in enforcers_from_options(self.household.options)
            if e.kind in (FAMILY_LINK, FAMILY_SAFETY)
        ]
        return sorted(set(chosen) & set(with_any)) if chosen else sorted(set(with_any))

    async def _site_list(self, now: datetime) -> None:
        """The website list, once a day: Family Link's and Family Safety's, each on its own (one failing doesn't
        hold up the other, or another kid). Family Safety is skipped quietly while it has no sync_site_list."""
        sites = SiteListConfig.from_options(self.household.options)
        if not sites.url or now.time() < sites.at:
            return
        for person in self.site_list_people(sites.people):
            fl_entity = self.family_link_entity(person)
            if fl_entity is not None:
                await self._sync_sites(person, "family_link", "familylink", {"entity_id": fl_entity, "url": sites.url})
            fs_entity = self.family_safety_entity(person)
            if fs_entity is not None and self.hass.services.has_service(FS_DOMAIN, "sync_site_list"):
                target = {"entity_id": fs_entity} if "." in fs_entity else {"account_id": fs_entity}
                await self._sync_sites(person, "family_safety", FS_DOMAIN, {**target, "url": sites.url})

    async def _sync_sites(self, person: str, via: str, domain: str, data: dict[str, Any]) -> None:
        """One side's sync for one person: marked done for the day, or tried again after RETRY (told once)."""
        # Family Link's marks keep their older names (a restart mid-day doesn't sync twice)
        mark = "sites" if via == "family_link" else f"sites_{via}"
        if self._marked(person, mark):
            return
        key = f"{person}|{mark}"
        if self._waiting(key):
            return
        try:
            await self.hass.services.async_call(domain, "sync_site_list", data, blocking=True)
        except Exception as err:  # noqa: BLE001 - one child's list failing mustn't stop the others
            _LOGGER.warning("Hearth couldn't sync the website list for %s through %s: %s", person, via, err)
            self._failed[key] = dt_util.utcnow()
            # Tried again later today; told once
            if not self._marked(person, f"{mark}_failed"):
                self._mark(person, f"{mark}_failed")
                self._event("site_list_failed", person, via=via, error=str(err)[:200])
            return
        self._mark(person, mark)
        self._event("site_list", person, via=via)

    # Telling

    def _event(self, action: str, person: str, **data: Any) -> None:
        self.hass.bus.async_fire(EVENT_SCHEDULE, {"action": action, "person": person, **data})

    def tell(self, title: str, message: str, notification_id: str) -> None:
        """The adults: a notification in Home Assistant, and on the schedule's phone (else the one that answers
        requests for more time)."""
        persistent_notification.async_create(self.hass, message, title=title, notification_id=notification_id)
        from .apps import CONF_ASK_NOTIFY

        service = self.config.notify or self.household.options.get(CONF_ASK_NOTIFY)
        if not service or "." not in service:
            return
        domain, name = service.split(".", 1)
        if self.hass.services.has_service(domain, name):
            self.hass.async_create_task(
                self.hass.services.async_call(domain, name, {"title": title, "message": message}, blocking=False)
            )
