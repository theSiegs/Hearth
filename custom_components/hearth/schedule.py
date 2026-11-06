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

hearth.school_time_off takes School time off for some people on a date (today by default), from a time if given.

Putting School time back is the delicate part. Switching it on outside the kid's window opens a window from then until
23:59, so Hearth switches it on only inside the kid's own weekly window for today (some hours shorter on a half day),
then at once pins today's window to those hours (set_school_time, scope today), and checks each minute until the
child's devices say the pinned end. The weekly window is read from Family Link's time entities, and kept when School
time is taken off in case they read unknown while it's off. A kid whose window has ended is left for the next school
day. At the watchdog time on a school day, the adults are told about anyone whose School time is still off.

The day's actions run from DAY_START (00:05); a check at CHECK_AT (06:00) tries a School time that didn't go off again
and tells the adults what didn't apply, so nobody is woken at midnight. Each action runs once a day (kept across a
restart). The website list (familylink.sync_site_list) is synced once a day at its time, person by person: a failure
for one is logged and the others go on.

What's pending is kept with Home Assistant's storage helper.
"""

from __future__ import annotations

import asyncio
from dataclasses import dataclass, field
from datetime import date, datetime, time, timedelta
import logging
import secrets
from typing import TYPE_CHECKING, Any

from homeassistant.components import persistent_notification
from homeassistant.core import HomeAssistant
from homeassistant.helpers.storage import Store
from homeassistant.util import dt as dt_util

from . import family_link as fl
from .enforce import FAMILY_LINK, enforcers_from_options
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


def _clock(value: Any, default: time | None) -> time | None:
    if isinstance(value, time):
        return value
    if isinstance(value, str) and value.strip():
        try:
            return time.fromisoformat(value.strip()[:5] if len(value.strip()) >= 5 else value.strip())
        except ValueError:
            return default
    return default


def _number(value: Any, default: float = 0) -> float:
    try:
        return float(value)
    except (TypeError, ValueError):
        return default


@dataclass(frozen=True)
class ScheduleConfig:
    """Configure > Schedule: what each day type does. Empty: nothing."""

    day_off_school_time_off: bool = False
    day_off_bonus: int = 0
    half_day_hours_early: float = 0
    half_day_bonus: int = 0
    bonus_family_link: bool = True
    bonus_group: str | None = None
    # Whose (empty: everyone with Family Link in Configure > Enforce)
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

    def view(self) -> dict[str, Any]:
        return {
            "id": self.id,
            "person": self.person,
            "date": self.day.isoformat(),
            "from": self.start.strftime("%H:%M") if self.start else None,
            "reason": self.reason,
            "applied": self.applied,
            "restore_from": self.restore_from.isoformat() if self.restore_from else None,
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
        self._lock = asyncio.Lock()
        self._failed: dict[str, datetime] = {}
        self._done_at: dict[str, datetime] = {}

    # Storage

    async def async_load(self) -> None:
        stored = await self._store.async_load() or {}
        self.day = stored.get("day")
        self.marks = {k: list(v) for k, v in (stored.get("marks") or {}).items()}
        self.limits_set = {k: int(v) for k, v in (stored.get("limits_set") or {}).items()}
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
                )
            except (KeyError, ValueError):
                continue
            self.offs[off.id] = off

    def _data(self) -> dict[str, Any]:
        return {
            "day": self.day,
            "marks": self.marks,
            "limits_set": self.limits_set,
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

    def offs_of(self, person: str) -> list[dict[str, Any]]:
        return [o.view() for o in sorted(self.offs.values(), key=lambda o: (o.day, o.id)) if o.person == person]

    # Services

    def take_off(self, people: list[str], day: date, start: time | None, reason: str | None) -> list[str]:
        ids: list[str] = []
        for person in people:
            same = next(
                (o for o in self.offs.values() if o.person == person and o.day == day and not o.applied), None
            )
            if same is not None:
                same.start, same.reason = start, (reason or same.reason or "").strip()[:MAX_REASON]
                ids.append(same.id)
                continue
            off = Off(secrets.token_hex(6), person, day, start, (reason or "").strip()[:MAX_REASON])
            self.offs[off.id] = off
            ids.append(off.id)
        self._save()
        return ids

    def cancel(self, people: list[str] | None, day: date | None) -> list[str]:
        """Not taken off yet: dropped. Taken off: put back from today (inside the window, as always)."""
        today = dt_util.now().date()
        changed: list[str] = []
        for off in list(self.offs.values()):
            if people is not None and off.person not in people:
                continue
            if day is not None and off.day != day:
                continue
            if off.applied:
                off.restore_from = today
            else:
                del self.offs[off.id]
            changed.append(off.id)
        self._save()
        return changed

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
            self.take_off([person], today, None, "Day off")
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
        if problems:
            self.tell("Today's schedule", ". ".join(problems) + ". Check Family Link.", "hearth_schedule_check")

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

    async def _site_list(self, now: datetime) -> None:
        sites = SiteListConfig.from_options(self.household.options)
        if not sites.url or now.time() < sites.at:
            return
        for person in self.people(sites.people):
            if self._marked(person, "sites"):
                continue
            entity_id = self.family_link_entity(person)
            if entity_id is None:
                continue
            key = f"{person}|sites"
            if self._waiting(key):
                continue
            try:
                await self.hass.services.async_call(
                    "familylink", "sync_site_list", {"entity_id": entity_id, "url": sites.url}, blocking=True
                )
            except Exception as err:  # noqa: BLE001 - one child's list failing mustn't stop the others
                _LOGGER.warning("Hearth couldn't sync the website list for %s: %s", person, err)
                self._failed[key] = dt_util.utcnow()
                # Tried again later today; told once
                if not self._marked(person, "sites_failed"):
                    self._mark(person, "sites_failed")
                    self._event("site_list_failed", person, error=str(err)[:200])
                continue
            self._mark(person, "sites")
            self._event("site_list", person)

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
