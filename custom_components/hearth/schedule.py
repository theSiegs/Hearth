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
- When chosen (bonus_family_safety, off by default) or chosen for the Switch (bonus_nintendo, off by default), the same
  bonus raises a limit that is a setting, not today's alone, as a temporary limit Hearth puts back itself
  (temporary_limit.py: Hearth records what it added to and what it wrote before writing, kept across a restart and
  midnight; puts it back 2 minutes before midnight, at once when the day off is called off the same day
  (hearth.school_time_off_cancel) or today's day type changes away from a day off or half day, or on the next start
  when that was missed; only while the limit still reads Hearth's, so a parent's change since stays; a write that
  failed isn't counted as done and is tried again while it's still today):
  - Family Safety (Windows, Xbox): for each of those platforms of a kid's Family Safety enforcer, this weekday's limit
    (the integration's per-day limit number: Windows' <weekday> Limit, the Xbox <weekday> Limit) plus the bonus, at
    most 24 hours, through microsoft_family_safety.set_screentime_limit with day_of_week (upstream's service, the
    child's entity or account). A parent's own change before Hearth's is what the bonus goes on top of. The Xbox's
    goes through the Xbox Family Settings sign-in, and fails without it: not set, tried again, reported at the check.
    A platform without a limit today (24 hours) is left alone. Hearth never uses Family Safety's account lock switch
    (lock_account), which saves the limits it finds as its restore point: on a bonus day that would be the raised
    one, but Hearth puts its value back only while it still reads it. School time has no Family Safety equivalent,
    so a day off and a half day change nothing else there.
  - The Switch: each chosen kid's Switch (their Nintendo enforcer's Max screentime today) gets today's limit plus the
    bonus (at most 360, the Switch's own maximum), set once per Switch even when kids share it. Nintendo has no
    today-only limit: the number is the setting of every day, or of this weekday. It's put back as the Nintendo
    enforcer does; after midnight (Home Assistant was off), a Switch with a limit per weekday gets that weekday's
    limit and bedtime back through update_daily_restrictions. A Switch with no limit (-1) is left alone: there's
    nothing to add to. While bonus time from the Nintendo app runs, the Switch refuses a new limit, so Hearth waits.
    While Hearth holds the Switch (limit 0 for a budget or a pause), nothing is written to it: the bonus goes into
    what the hold puts back (and comes out of it again on a cancel or at midnight), so letting go gives the raised
    limit and a hold never fights the bonus.

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
    WEEKDAYS,
    Enforcer,
    enforcers_from_options,
    fs_account_of,
    fs_day_limit_entity,
    near_midnight,
)
from .schooldays import DAY_OFF, HALF_DAY, SCHOOL
from .temporary_limit import DONE, SET, SKIP, SWITCH, WAIT, WINDOWS, WRITE, XBOX, TemporaryLimits

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
# Family Safety's limit of a weekday (Windows, or the Xbox through the Xbox Family Settings sign-in)
FS_LIMIT = "set_screentime_limit"
FULL_DAY = 1440
# The platforms whose weekday limit takes the day's extra minutes
FS_LIMIT_PLATFORMS = (WINDOWS, XBOX)
# Family Safety's day_of_week: 0 is Sunday
FS_DAYS = ("sunday", "monday", "tuesday", "wednesday", "thursday", "friday", "saturday")
# A Family Safety limit Hearth just wrote may read the old value till the integration's next read (5 minutes)
FS_SETTLE = timedelta(minutes=5)
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
        # The limits the day's extra raised, kept until they're put back, over midnight and a restart too
        # (temporary_limit.py): a Switch (its Max screentime today entity, with what putting it back after midnight
        # needs: device_id, bedtime_alarm, bedtime_end_time) and a Family Safety child's Windows or Xbox (by
        # "family_safety|<enforcer entity>|<platform>", with the enforcer's entity_id)
        self.temporary = TemporaryLimits(self._save)
        self._lock = asyncio.Lock()
        self._failed: dict[str, datetime] = {}
        self._done_at: dict[str, datetime] = {}

    # Storage

    async def async_load(self) -> None:
        stored = await self._store.async_load() or {}
        self.day = stored.get("day")
        self.marks = {k: list(v) for k, v in (stored.get("marks") or {}).items()}
        self.limits_set = {k: int(v) for k, v in (stored.get("limits_set") or {}).items()}
        # An older Hearth kept the Switches' as sw_limits; its fs_limits were Family Safety's own today-only changes,
        # which Family Safety put back itself: nothing of Hearth's to put back
        self.temporary.load(stored.get("temporary_limits"), stored.get("sw_limits"))
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
            "temporary_limits": self.temporary.dump(),
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
            self.day, self.marks, self.limits_set = today.isoformat(), {}, {}
            self._save()
        kind = self.day_type(today)
        config = self.config
        people = self.people(config.people)
        clock = now.time()
        if clock >= DAY_START:
            for person in people:
                await self._day_actions(person, kind, config, today)
        await self._family_safety_day(now, kind, config)
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

    # Family Safety (Windows, Xbox): the day's extra minutes on the weekday's limit, put back by Hearth

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
        """The call's data when this Family Safety takes it (its schema accepts it), targeting the child's entity, else
        its account id (an older Family Safety); None when it doesn't (skipped quietly)."""
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

    def _fs_limit_wanted(self, enforcer: Enforcer, config: ScheduleConfig) -> bool:
        """Family Safety takes part: its extra minutes are chosen (Configure > Schedule) and it has a weekday's limit."""
        return config.bonus_family_safety and self._fs_data(
            enforcer.entity_id, FS_LIMIT, {"platform": WINDOWS, "day_of_week": 0, "hours": 1, "minutes": 0}
        ) is not None

    @staticmethod
    def _fs_key(entity_id: str, platform: str) -> str:
        return f"{FAMILY_SAFETY}|{entity_id}|{platform}"

    def _fs_current(self, entity_id: str, platform: str, weekday: str) -> float | None:
        """The platform's limit of the weekday as Family Safety reads it (its per-day limit number); None when unread."""
        limit = fs_day_limit_entity(self.hass, entity_id, platform, weekday)
        state = self.hass.states.get(limit) if limit else None
        return _number(state.state if state else None, None)

    async def _fs_write(self, key: str, entity_id: str, platform: str, weekday: str, minutes: int) -> bool | None:
        """The platform's limit of the weekday = [minutes]: True when written, False when the call failed (tried again
        after RETRY), None when this Family Safety doesn't take it."""
        hours, rest = divmod(int(minutes), 60)
        data = self._fs_data(
            entity_id,
            FS_LIMIT,
            {"platform": platform, "day_of_week": FS_DAYS.index(weekday), "hours": hours, "minutes": rest},
        )
        if data is None:
            return None
        return await self._call(key, FS_DOMAIN, FS_LIMIT, data)

    async def _family_safety_day(self, now: datetime, kind: str, config: ScheduleConfig) -> None:
        """What Hearth added to a Family Safety platform goes back when due (a later day, just before midnight, a
        cancel, a day type that changed); then a day off or half day's extra goes on each chosen platform, once a
        day."""
        today = now.date()
        extra_day = kind in (DAY_OFF, HALF_DAY)
        for key, mine in self.temporary.of(FS_LIMIT_PLATFORMS):
            people = mine.get("people") or []
            called_off = bool(people and all(self._marked(p, "fs_cancel") for p in people))
            if self.temporary.due(mine, now, extra_day, called_off) and await self._family_safety_restore(key, mine):
                self.temporary.drop(key)
                self._mark("", f"fs_back:{key}")
        minutes = config.day_off_bonus if kind == DAY_OFF else config.half_day_bonus if kind == HALF_DAY else 0
        if not minutes or near_midnight(now) or now.time() < DAY_START:
            return
        for person in self.family_safety_people(config.people):
            enforcer = self.family_safety_enforcer(person)
            if enforcer is None or self._marked(person, "fs_cancel") or not self._fs_limit_wanted(enforcer, config):
                continue
            for platform in enforcer.platforms:
                if platform not in FS_LIMIT_PLATFORMS or self._marked(person, f"bonus_fs:{platform}"):
                    continue
                if self._marked("", f"fs_back:{self._fs_key(enforcer.entity_id, platform)}"):
                    continue  # put back already today: not raised again
                done = await self._family_safety_limit(person, enforcer, platform, today, minutes)
                if done is not None:
                    self._mark(person, f"bonus_fs:{platform}")

    async def _family_safety_limit(
        self, person: str, enforcer: Enforcer, platform: str, today: date, minutes: int
    ) -> str | None:
        """This weekday's limit of the platform + [minutes]. SET, SKIP (no limit today: nothing to add to; or Hearth's
        limit changed since, by a parent), or None when not done (not read, just written, an earlier day's not put back
        yet, or the call failed: tried again; the Xbox's fails without the Xbox Family Settings sign-in).

        The limit read is the weekday's as it is now: a parent's change before Hearth's is what the extra goes on top
        of. Hearth's own (kept in temporary) is never added to again."""
        key = self._fs_key(enforcer.entity_id, platform)
        weekday = WEEKDAYS[today.weekday()]
        current = self._fs_current(enforcer.entity_id, platform, weekday)
        mine = self.temporary.get(key)
        if mine is not None:
            if not self.temporary.today(mine, today):
                return None  # an earlier day's isn't put back yet: its base would be lost
            seen = self.temporary.raised(key, current, FS_SETTLE)
            if seen == WAIT:
                return None
            if seen != WRITE:
                return seen  # SET (already: a restart before it was marked), SKIP (a parent's since)
            # The last write failed: the limit still reads the base, written again below
        if current is None:
            return None
        if current < 0 or current >= FULL_DAY:
            return SKIP
        target = min(FULL_DAY, int(current) + minutes)
        # Kept before the call: one that reached Family Safety but whose answer was lost is still known as Hearth's
        self.temporary.begin(key, platform, int(current), target, [person], entity_id=enforcer.entity_id)
        await self.async_flush()
        written = await self._fs_write(f"{person}|fs_limit:{platform}", enforcer.entity_id, platform, weekday, target)
        if written is None:
            self.temporary.drop(key)
            return SKIP
        if not written:
            # Not set: not Hearth's limit, and not done (tried again while it's still today)
            self.temporary.failed(key)
            return None
        self.temporary.written(key)
        self._event("bonus", person, via="family_safety", platform=platform, minutes=minutes, daily_minutes=target)
        return SET

    async def _family_safety_restore(self, key: str, mine: dict[str, Any]) -> bool:
        """The limit Hearth added to goes back on the recorded weekday (on a later day too: a weekday's limit reads and
        writes any day), only while it still reads Hearth's. True when done (put back, or nothing of Hearth's left: a
        parent's change stays), False to try again next minute."""
        entity_id, platform, weekday = mine.get("entity_id"), mine["platform"], mine.get("weekday")
        if not isinstance(entity_id, str) or weekday not in FS_DAYS:
            return True
        current = self._fs_current(entity_id, platform, weekday)
        what = self.temporary.put_back(mine, current, FS_SETTLE)
        if what == WAIT:
            return False
        if what == DONE:
            if mine.get("written_at") and current != mine["base"]:
                _LOGGER.info(
                    "Family Safety's %s limit for %s reads %s, not Hearth's %s: a parent's change, left alone",
                    platform, weekday, current, mine["target"],
                )
            return True
        if not await self._fs_write(f"fs_back:{key}", entity_id, platform, weekday, mine["base"]):
            return False
        for person in mine.get("people") or []:
            self._event("bonus_back", person, via="family_safety", platform=platform, daily_minutes=mine["base"])
        return True

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
        extra_day = kind in (DAY_OFF, HALF_DAY)
        for entity_id, mine in self.temporary.of((SWITCH,)):
            people = mine.get("people") or []
            called_off = bool(people and all(self._marked(p, "sw_cancel") for p in people))
            if self.temporary.due(mine, now, extra_day, called_off) and await self._nintendo_restore(
                entity_id, mine, today
            ):
                self.temporary.drop(entity_id)
                self._mark("", f"sw_back:{entity_id}")
        minutes = config.day_off_bonus if kind == DAY_OFF else config.half_day_bonus if kind == HALF_DAY else 0
        if not minutes or not config.bonus_nintendo or near_midnight(now) or now.time() < DAY_START:
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
        """Today's limit of the Switch + [minutes]. SET, SKIP (no limit, or at the most already), or None when not
        done (not read, bonus time running, Hearth's hold under way, the call failed: tried again)."""
        enforcement = self.household.enforcement
        mine = self.temporary.get(entity_id)
        state = self.hass.states.get(entity_id)
        current = _number(state.state if state else None, None)
        hold = enforcement.switch_hold(entity_id)
        if mine is not None:
            if not self.temporary.today(mine, today):
                return None  # an earlier day's isn't put back yet: its base would be lost
            # Already (a restart before it was marked): never added to twice
            if hold is not None and hold.restore.get("max") == mine["target"]:
                return SET
            seen = self.temporary.raised(entity_id, current)
            if seen == WAIT:
                return None
            if seen != WRITE:
                return seen  # SET, or SKIP: changed since (a parent's)
            # The last write failed: the limit still reads the base, written again below
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
            return SKIP  # no limit, or the most already: nothing to add to
        target = min(SWITCH_MAX, int(base) + minutes)
        # Kept before any change: one that reached Nintendo but whose answer was lost is still known as Hearth's
        self.temporary.begin(
            entity_id, SWITCH, int(base), target, people, via_hold=hold is not None, **enforcement.switch_day(entity_id)
        )
        await self.async_flush()
        if hold is not None:
            hold.restore["max"] = target
            enforcement.save()
        elif not await self._call(
            f"sw_limit:{entity_id}", "number", "set_value", {"entity_id": entity_id, "value": target}
        ):
            # Not set: not Hearth's limit, and not done (tried again while it's still today)
            self.temporary.failed(entity_id)
            return None
        self.temporary.written(entity_id)
        for person in people:
            self._event("bonus", person, via="nintendo", switch=entity_id, minutes=minutes, daily_minutes=target)
        return SET

    async def _nintendo_restore(self, entity_id: str, mine: dict[str, Any], today: date) -> bool:
        """The limit Hearth added to goes back, only while the Switch has Hearth's: True when done (put back, or a
        parent's change left alone), False to try again next minute."""
        enforcement = self.household.enforcement
        target, base = mine["target"], mine["base"]
        later_day = not self.temporary.today(mine, today)
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
        if later_day and enforcement.switch_each_day(entity_id) and mine.get("written_at"):
            # Not put back before midnight (Home Assistant was off): today's limit is another weekday's, so that
            # weekday's own goes back with its bedtime (unread: Nintendo shows only today's)
            await enforcement.put_back_weekday(entity_id, mine, base)
            self._back(entity_id, mine)
            return True
        state = self.hass.states.get(entity_id)
        current = _number(state.state if state else None, None)
        if current == 0 and target != 0:
            # 0: Hearth's hold may have just let go and the Switch not caught up yet. Tried again; on a later day a 0
            # isn't Hearth's any more
            return later_day
        what = self.temporary.put_back(mine, current)
        if what == WAIT:
            return False
        if what == DONE:
            if mine.get("written_at") and current != base:
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
            missing = [
                p
                for p in enforcer.platforms
                if p in FS_LIMIT_PLATFORMS
                and not self._marked(person, f"bonus_fs:{p}")
                and not self._marked("", f"fs_back:{self._fs_key(enforcer.entity_id, p)}")
            ]
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
