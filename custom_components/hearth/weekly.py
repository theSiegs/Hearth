"""The weekly schedule (docs/home-assistant-integration.md, Schedule): each kid's week of modes and limits.

Each kid has a week (Monday to Sunday) and two special days: the Day off and the Half day. A day is a list of changes
["HH:MM", mode] ("at 7:45, School"), each running until the next, and the day's limits per group (minutes; None or
missing is no limit, 0 is none). The modes are the household's: a name and what it allows while it's on:

- everything (Free time): screens open, the day's limits count;
- some (Homework, Wind down): the listed groups are closed, held as a group out of time is, and an allow lifts that;
- school (School): a School time lock;
- nothing (Sleep): a bedtime lock.

The night carries over: whatever ends a day runs into the next until that day's first change. Times snap to 15
minutes; two neighbouring changes with the same mode merge; at most 12 changes a day and 8 modes.

Which day a date uses comes from its day type (schooldays.py): a school day or a weekend day uses its weekday (an
extra school day on a weekend uses Friday's), a day off and a weekday outside the school year use the Day off, and a
half day uses its weekday's changes with School ending at the half day's "School ends at" time (or some minutes
earlier than the weekday's end, as Configure > Schedule said) and the Day off's or the weekday's limits.

A today-only change copies today's day and changes it; it ends at midnight, and resume_schedule drops it sooner.

Until an adult edits a kid's schedule, it is the migration of the kid's two budgets, worked out when asked: the
school-day budget on Monday to Friday, the other-day budget on Saturday, Sunday and the Day off, the half day's limits
as half_day_budget said, and no changes at all. With no changes, nothing of the schedule holds anything: bedtime and
School time come from the lock entities (Family Link's) as before. The first edit keeps that migration and changes it.
The two budgets stay in step with Monday's and Saturday's limits (hearth.set_budget and the old numbers write
Monday to Friday, or Saturday, Sunday and the Day off).

Phase 1: Hearth enforces the schedule with its own holds only; nothing is written to Family Link's, Family Safety's
or Nintendo's own schedules.
"""

from __future__ import annotations

from collections.abc import Callable
import copy
from dataclasses import dataclass, field
from datetime import date, datetime, time, timedelta
import logging
import re
import secrets
from typing import Any

from homeassistant.core import HomeAssistant
from homeassistant.helpers.storage import Store

from .schooldays import DAY_OFF, HALF_DAY, NO_SCHOOL, SCHOOL

_LOGGER = logging.getLogger(__name__)

DAYS = ("mon", "tue", "wed", "thu", "fri", "sat", "sun")
DAY_OFF_KEY = "day_off"
DAY_KEYS = (*DAYS, DAY_OFF_KEY)
# The names hearth.set_schedule takes for several days at once
DAY_SETS: dict[str, tuple[str, ...]] = {
    "school_days": DAYS[:5],
    "weekend": DAYS[5:],
    "every_day": DAY_KEYS,
}
LONG_DAYS = {
    "mon": "Monday", "tue": "Tuesday", "wed": "Wednesday", "thu": "Thursday", "fri": "Friday", "sat": "Saturday",
    "sun": "Sunday", DAY_OFF_KEY: "Day off", "half_day": "Half day",
}

SNAP = 15
DAY_MINUTES = 1440
MAX_CHANGES = 12
MAX_MODES = 8
MAX_NAME = 40
MAX_LIMIT = 1440

# What a mode allows while it's on
EVERYTHING = "everything"
SOME = "some"
SCHOOL_MODE = "school"
NOTHING = "nothing"
ALLOWS = (EVERYTHING, SOME, SCHOOL_MODE, NOTHING)
# The locks of the modes that are locks
LOCK_KIND = {NOTHING: "bedtime", SCHOOL_MODE: "school_time"}

SLEEP = "sleep"
SCHOOL_ID = "school"
FREE = "free"
BUILTIN_MODES: dict[str, dict[str, Any]] = {
    SLEEP: {"name": "Sleep", "allows": NOTHING, "keep_not_screen_time": True, "builtin": True},
    SCHOOL_ID: {"name": "School", "allows": SCHOOL_MODE, "builtin": True},
    FREE: {"name": "Free time", "allows": EVERYTHING, "builtin": True},
}
# Starters a household can change or remove
STARTER_MODES: dict[str, dict[str, Any]] = {
    "homework": {"name": "Homework", "allows": SOME, "closed": ["games", "youtube", "streaming", "social"]},
    "wind": {"name": "Wind down", "allows": SOME, "closed": ["games", "social"]},
}

# The half day's limits: the Day off's, or the weekday's
HALF_LIMITS = (DAY_OFF_KEY, "weekday")
DEFAULT_SCHOOL_ENDS = "12:00"

EVENT_MODE = "hearth_mode"
EVENT_SCHEDULE_CHANGED = "hearth_schedule_changed"
# How many undo tokens are kept (the panel's Undo is for the last few copies)
MAX_UNDO = 10

_CLOCK = re.compile(r"^(\d{1,2}):(\d{2})(?::\d{2})?$")


class ScheduleError(ValueError):
    """A schedule that can't be saved, with a sentence for the adult."""


# Times


def snap(minutes: float) -> int:
    """To the nearest 15 minutes, within the day (00:00 to 23:45)."""
    snapped = int(round(minutes / SNAP)) * SNAP
    return max(0, min(DAY_MINUTES - SNAP, snapped))


def minutes_of(value: Any) -> int:
    """A time of day ("HH:MM", a time, or minutes) as minutes since midnight, snapped to 15 minutes."""
    if isinstance(value, time):
        return snap(value.hour * 60 + value.minute)
    if isinstance(value, (int, float)) and not isinstance(value, bool):
        return snap(value)
    match = _CLOCK.match(str(value or "").strip())
    if not match or int(match[1]) > 23 or int(match[2]) > 59:
        raise ScheduleError(f"{value!r} isn't a time of day (HH:MM)")
    return snap(int(match[1]) * 60 + int(match[2]))


def hhmm(minutes: int) -> str:
    return f"{minutes // 60:02d}:{minutes % 60:02d}"


def say_time(minutes: int) -> str:
    """"9:30 PM", "7 AM", "noon", "midnight"."""
    minutes %= DAY_MINUTES
    if minutes == 0:
        return "midnight"
    if minutes == 720:
        return "noon"
    h, m = divmod(minutes, 60)
    suffix = "AM" if h < 12 else "PM"
    return f"{h % 12 or 12}{f':{m:02d}' if m else ''} {suffix}"


def weekday_key(day: date) -> str:
    return DAYS[day.weekday()]


# Modes


def default_modes() -> dict[str, dict[str, Any]]:
    return copy.deepcopy({**BUILTIN_MODES, **STARTER_MODES})


def mode_lock(modes: dict[str, dict[str, Any]], mode: str | None) -> str | None:
    """bedtime or school_time for a mode that's a lock; None for the rest."""
    found = modes.get(mode or "")
    return LOCK_KIND.get(found["allows"]) if found else None


def mode_closed(modes: dict[str, dict[str, Any]], mode: str | None) -> list[str]:
    """The groups a mode closes (Some groups closed); none for the others."""
    found = modes.get(mode or "")
    return list(found.get("closed") or []) if found and found["allows"] == SOME else []


def describe_mode(mode: dict[str, Any], group_name: Callable[[str], str] | None = None) -> str:
    """A plain sentence for what a mode does."""
    allows = mode.get("allows")
    if allows == NOTHING:
        return "Bedtime: screens locked." + (" Music and audiobooks stay on." if mode.get("keep_not_screen_time") else "")
    if allows == SCHOOL_MODE:
        return "School time: only the apps School time allows."
    if allows == SOME:
        names = [group_name(g) if group_name else g for g in mode.get("closed") or []]
        if not names:
            return "Nothing closed yet."
        said = names[0] if len(names) == 1 else f"{', '.join(names[:-1])} and {names[-1]}"
        return f"{said} closed."
    return "Everything, within the day's limits."


# Changes


def normalize_changes(changes: Any, modes: dict[str, dict[str, Any]]) -> list[list[str]]:
    """A day's changes as saved: [[HH:MM, mode]], times snapped to 15 minutes, sorted, one per time (the last given
    wins), neighbours with the same mode merged, at most 12."""
    by_time: dict[int, str] = {}
    for item in changes or []:
        if isinstance(item, dict):
            at, mode = item.get("at"), item.get("mode")
        elif isinstance(item, (list, tuple)) and len(item) == 2:
            at, mode = item
        else:
            raise ScheduleError(f"A change is a time and a mode, not {item!r}")
        if mode not in modes:
            raise ScheduleError(f"No mode {mode!r}")
        by_time[minutes_of(at)] = mode
    out: list[list[str]] = []
    for minute in sorted(by_time):
        if out and out[-1][1] == by_time[minute]:
            continue
        out.append([hhmm(minute), by_time[minute]])
    if len(out) > MAX_CHANGES:
        raise ScheduleError(f"At most {MAX_CHANGES} changes a day")
    return out


def as_minutes(changes: list[list[str]]) -> list[tuple[int, str]]:
    return [(minutes_of(at), mode) for at, mode in changes]


def merged(changes: list[tuple[int, str]]) -> list[tuple[int, str]]:
    out: list[tuple[int, str]] = []
    for minute, mode in sorted(changes):
        if out and out[-1][0] == minute:
            out[-1] = (minute, mode)
        elif not out or out[-1][1] != mode:
            out.append((minute, mode))
    # A time given twice may have left neighbours equal
    final: list[tuple[int, str]] = []
    for minute, mode in out:
        if not final or final[-1][1] != mode:
            final.append((minute, mode))
    return final


def normalize_limits(limits: Any) -> dict[str, int | None]:
    if limits is None:
        return {}
    if not isinstance(limits, dict):
        raise ScheduleError("Limits are {group: minutes or null}")
    out: dict[str, int | None] = {}
    for group, minutes in limits.items():
        if minutes is None:
            out[str(group)] = None
            continue
        try:
            value = int(minutes)
        except (TypeError, ValueError) as err:
            raise ScheduleError(f"{group}: {minutes!r} isn't a number of minutes") from err
        out[str(group)] = max(0, min(MAX_LIMIT, value))
    return out


def half_day_changes(
    base: list[tuple[int, str]], modes: dict[str, dict[str, Any]], school_ends: int | None, early: int | None
) -> list[tuple[int, str]]:
    """A half day's changes: the weekday's, with its first School ending at [school_ends] (or [early] minutes before
    the weekday's School ends), then whatever came after School. A School ending later than the weekday's is left."""
    index = next((i for i, (_, m) in enumerate(base) if (modes.get(m) or {}).get("allows") == SCHOOL_MODE), None)
    if index is None:
        return list(base)
    start = base[index][0]
    after = base[index + 1] if index + 1 < len(base) else None
    if early:
        if after is None:
            return list(base)
        end = snap(after[0] - early)
    else:
        end = school_ends if school_ends is not None else minutes_of(DEFAULT_SCHOOL_ENDS)
    if end <= start or (after is not None and end >= after[0]):
        return list(base)
    then = after[1] if after is not None else FREE
    rest = [c for c in base[index + 2:] if c[0] > end] if after is not None else []
    return merged([*base[: index + 1], (end, then), *rest])


# The resolved day


@dataclass
class Day:
    """What a date uses: its changes (minutes, mode) and limits, and where they came from."""

    date: date
    changes: list[tuple[int, str]]
    limits: dict[str, int | None]
    # mon..sun, day_off or half_day
    uses: str
    # The weekday whose changes a half day took
    base: str | None = None
    changed_today: bool = False

    @property
    def bedtime(self) -> int | None:
        return None if not self.changes else self.changes[-1][0]


def day_key_for(day: date, day_type: str) -> tuple[str, bool]:
    """The day a date uses for its day type: (key, half). An extra school day on a weekend uses Friday's."""
    if day_type in (DAY_OFF, NO_SCHOOL):
        return DAY_OFF_KEY, False
    key = weekday_key(day)
    if day_type in (SCHOOL, HALF_DAY) and day.weekday() >= 5:
        key = "fri"
    return key, day_type == HALF_DAY


@dataclass
class Moment:
    at: datetime
    mode: str


@dataclass
class Now:
    """A person's schedule at a moment: the mode, since and until when, the next change, tonight's bedtime."""

    mode: str
    since: datetime | None
    until: datetime | None
    next: Moment | None
    bedtime: datetime | None
    wake: datetime | None
    day: Day
    # The next Sleep or School to start: (at, bedtime | school_time)
    next_lock: tuple[datetime, str] | None = None


@dataclass
class Undo:
    token: str
    people: dict[str, dict[str, Any] | None]
    today: dict[str, dict[str, Any] | None]
    modes: dict[str, dict[str, Any]] | None = None


@dataclass
class WeekData:
    modes: dict[str, dict[str, Any]] = field(default_factory=default_modes)
    # person -> {"days": {key: {"changes", "limits"}}, "half_day": {...}}, once an adult edited it
    people: dict[str, dict[str, Any]] = field(default_factory=dict)
    # person -> today's change: {"date", "changes" (or None: the day's), "limits" (or None), "by", "reason"}
    today: dict[str, dict[str, Any]] = field(default_factory=dict)


class Week:
    """The household's weekly schedule, kept with Home Assistant's storage helper."""

    def __init__(
        self,
        hass: HomeAssistant,
        entry_id: str,
        budgets: Callable[[], dict[str, dict[str, dict[str, int | None]]]],
        options: Callable[[], dict[str, Any]],
    ) -> None:
        self.hass = hass
        self._store: Store[dict[str, Any]] = Store(hass, 1, f"hearth.weekly.{entry_id}")
        self.data = WeekData()
        # The two budgets (Limits.data.budgets) and the entry's options, for the migration
        self._budgets = budgets
        self._options = options
        self._undo: list[Undo] = []
        # The day type of a date (Household.day_type_on)
        self.type_of: Callable[[date], str] = lambda d: SCHOOL if d.weekday() < 5 else "weekend"

    # Storage

    async def async_load(self) -> None:
        stored = await self._store.async_load() or {}
        modes = stored.get("modes")
        self.data = WeekData(
            modes=modes if isinstance(modes, dict) and modes else default_modes(),
            people=dict(stored.get("people") or {}),
            today=dict(stored.get("today") or {}),
        )
        # The built-ins are always there
        for mode_id, mode in BUILTIN_MODES.items():
            self.data.modes.setdefault(mode_id, copy.deepcopy(mode))

    def _dump(self) -> dict[str, Any]:
        return {"modes": self.data.modes, "people": self.data.people, "today": self.data.today}

    def _save(self) -> None:
        self._store.async_delay_save(self._dump, 2)

    async def async_flush(self) -> None:
        await self._store.async_save(self._dump())

    # The migration

    def is_set(self, person: str) -> bool:
        """Whether an adult has edited the person's schedule (else it's their budgets, worked out when asked)."""
        return person in self.data.people

    def migrated(self, person: str) -> dict[str, Any]:
        """The person's schedule from their two budgets and Configure > School days and Schedule: the school-day
        budget on Monday to Friday, the other-day budget on the weekend and the Day off, no changes."""
        budgets = self._budgets().get(person) or {}
        school = {g: kinds.get("weekday") for g, kinds in budgets.items() if "weekday" in kinds}
        other = {g: kinds.get("weekend") for g, kinds in budgets.items() if "weekend" in kinds}
        options = self._options()
        half_budget = (options.get("school_days") or {}).get("half_day_budget")
        try:
            early_hours = float((options.get("schedule") or {}).get("half_day_hours_early") or 0)
        except (TypeError, ValueError):
            early_hours = 0.0
        early = snap(early_hours * 60) if early_hours > 0 else None
        days = {key: {"changes": [], "limits": dict(school if key in DAYS[:5] else other)} for key in DAY_KEYS}
        return {
            "days": days,
            "half_day": {
                "school_ends": None if early else DEFAULT_SCHOOL_ENDS,
                "early": early,
                "limits": "weekday" if half_budget == "school_days" else DAY_OFF_KEY,
            },
        }

    def schedule_of(self, person: str) -> dict[str, Any]:
        """The person's schedule as saved, or as migrated from their budgets."""
        return self.data.people.get(person) or self.migrated(person)

    def _own(self, person: str) -> dict[str, Any]:
        """The person's schedule to edit: the migration kept on the first edit."""
        if person not in self.data.people:
            self.data.people[person] = self.migrated(person)
        return self.data.people[person]

    # Reading

    def resolve(self, person: str, day: date, day_type: str | None = None, *, with_today: bool = True) -> Day:
        """What [day] uses for the person: its changes and limits."""
        sched = self.schedule_of(person)
        day_type = day_type or self.type_of(day)
        key, half = day_key_for(day, day_type)
        own = sched["days"].get(key) or {}
        modes = self.data.modes
        changes = [(m, mode) for m, mode in as_minutes(own.get("changes") or []) if mode in modes]
        limits = dict(own.get("limits") or {})
        uses, base = key, None
        if half:
            settings = sched.get("half_day") or {}
            ends = settings.get("school_ends")
            changes = half_day_changes(
                changes, modes, minutes_of(ends) if ends else None, settings.get("early") or None
            )
            if settings.get("limits", DAY_OFF_KEY) == DAY_OFF_KEY:
                limits = dict((sched["days"].get(DAY_OFF_KEY) or {}).get("limits") or {})
            uses, base = "half_day", key
        out = Day(day, changes, limits, uses, base)
        today = self.data.today.get(person) if with_today else None
        if today and today.get("date") == day.isoformat():
            if today.get("changes") is not None:
                out.changes = [(m, mode) for m, mode in as_minutes(today["changes"]) if mode in modes]
            if today.get("limits") is not None:
                out.limits = {**out.limits, **today["limits"]}
            out.changed_today = True
        return out

    def limits_on(self, person: str, day: date, day_type: str | None = None) -> dict[str, int | None]:
        return self.resolve(person, day, day_type).limits

    def limit(self, person: str, group: str, day: date, day_type: str | None = None) -> int | None:
        return self.resolve(person, day, day_type).limits.get(group)

    def _carry(self, person: str, day: date) -> str | None:
        """The mode the night before carries into [day]: the last change of the latest day before it with any."""
        for back in range(1, 8):
            changes = self.resolve(person, day - timedelta(days=back)).changes
            if changes:
                return changes[-1][1]
        return None

    def segments(self, person: str, day: date) -> list[dict[str, Any]]:
        """The day as stretches: [{start, end (minutes), mode, carried}]; empty when the schedule has no changes."""
        resolved = self.resolve(person, day)
        carry = self._carry(person, day)
        if carry is None and not resolved.changes:
            return []
        out: list[dict[str, Any]] = []
        at, mode, carried = 0, carry, True
        for minute, changed in resolved.changes:
            if minute > at and mode is not None:
                out.append({"start": at, "end": minute, "mode": mode, "carried": carried})
            at, mode, carried = minute, changed, False
        if mode is not None:
            out.append({"start": at, "end": DAY_MINUTES, "mode": mode, "carried": carried})
        return out

    def timeline(self, person: str, now: datetime) -> list[Moment]:
        """The changes from the week before to the day after tomorrow, as times: the night before carries over."""
        today = now.date()
        zone = now.tzinfo
        out: list[Moment] = []
        for back in range(7, -3, -1):
            day = today - timedelta(days=back)
            for minute, mode in self.resolve(person, day).changes:
                at = datetime.combine(day, time(minute // 60, minute % 60), zone)
                if out and out[-1].mode == mode:
                    continue
                out.append(Moment(at, mode))
        return out

    def now(self, person: str, now: datetime) -> Now | None:
        """The person's schedule at [now], or None while it has no changes (the locks do it then)."""
        if person not in self.data.people and person not in self.data.today:
            # Their budgets, worked out: no changes
            return None
        moments = self.timeline(person, now)
        current = next((i for i in range(len(moments) - 1, -1, -1) if moments[i].at <= now), None)
        if current is None:
            return None
        mode = moments[current].mode
        since = moments[current].at
        following = moments[current + 1] if current + 1 < len(moments) else None
        today = self.resolve(person, now.date())
        tomorrow = self.resolve(person, now.date() + timedelta(days=1))
        bedtime = wake = None
        zone = now.tzinfo
        if today.changes and self.data.modes.get(today.changes[-1][1], {}).get("allows") == NOTHING:
            minute = today.changes[-1][0]
            bedtime = datetime.combine(now.date(), time(minute // 60, minute % 60), zone)
            if tomorrow.changes:
                first = tomorrow.changes[0][0]
                wake = datetime.combine(now.date() + timedelta(days=1), time(first // 60, first % 60), zone)
        lock = None
        for moment in moments[current + 1:]:
            kind = mode_lock(self.data.modes, moment.mode)
            if kind is not None:
                lock = (moment.at, kind)
                break
        return Now(mode, since, following.at if following else None,
                   following, bedtime, wake, today, lock)

    # Editing

    def _snapshot(self, people: list[str], modes: bool = False) -> Undo:
        token = secrets.token_hex(6)
        undo = Undo(
            token,
            {p: copy.deepcopy(self.data.people.get(p)) for p in people},
            {p: copy.deepcopy(self.data.today.get(p)) for p in people},
            copy.deepcopy(self.data.modes) if modes else None,
        )
        self._undo = [*self._undo[-(MAX_UNDO - 1):], undo]
        return undo

    def undo(self, token: str) -> list[str]:
        """Puts back what an edit changed; returns the people it did."""
        found = next((u for u in self._undo if u.token == token), None)
        if found is None:
            raise ScheduleError("That can't be undone any more")
        self._undo.remove(found)
        for person, before in found.people.items():
            if before is None:
                self.data.people.pop(person, None)
            else:
                self.data.people[person] = before
        for person, before in found.today.items():
            if before is None:
                self.data.today.pop(person, None)
            else:
                self.data.today[person] = before
        if found.modes is not None:
            self.data.modes = found.modes
        self._save()
        return list(found.people)

    def set_days(
        self,
        people: list[str],
        days: list[str],
        changes: Any = None,
        limits: Any = None,
        half_day_ends: Any = None,
        half_day_limits: str | None = None,
        *,
        replace_limits: bool = False,
    ) -> str:
        """Each person's [days] get [changes] and/or [limits] (limits merge into the day's unless [replace_limits]);
        the half day's School end. Returns an undo token."""
        if (changes is not None or limits is not None) or days:
            keys = expand_days(days)
        elif half_day_ends in (None, "") and half_day_limits is None:
            raise ScheduleError("Say what to change")
        else:
            keys = []
        new_changes = normalize_changes(changes, self.data.modes) if changes is not None else None
        new_limits = normalize_limits(limits) if limits is not None else None
        ends = hhmm(minutes_of(half_day_ends)) if half_day_ends not in (None, "") else None
        if half_day_limits is not None and half_day_limits not in HALF_LIMITS:
            raise ScheduleError("The half day's limits are the Day off's (day_off) or the weekday's (weekday)")
        undo = self._snapshot(people)
        for person in people:
            sched = self._own(person)
            for key in keys:
                day = sched["days"].setdefault(key, {"changes": [], "limits": {}})
                if new_changes is not None:
                    day["changes"] = copy.deepcopy(new_changes)
                if new_limits is not None:
                    day["limits"] = dict(new_limits) if replace_limits else {**(day.get("limits") or {}), **new_limits}
            half = sched.setdefault("half_day", {"school_ends": DEFAULT_SCHOOL_ENDS, "early": None, "limits": DAY_OFF_KEY})
            if ends is not None:
                half["school_ends"], half["early"] = ends, None
            if half_day_limits is not None:
                half["limits"] = half_day_limits
        self._save()
        return undo.token

    def copy(
        self,
        source: str,
        day: str | None,
        to_people: list[str] | None,
        to_days: list[str] | None,
        times: bool = True,
        limits: bool = True,
    ) -> str:
        """Copies one day of [source]'s to other days of theirs ([to_days]), or their week or one day to other people
        ([to_people]): what's copied replaces what was there. Returns an undo token."""
        if not times and not limits:
            raise ScheduleError("Copy the times, the limits or both")
        sched = copy.deepcopy(self.schedule_of(source))
        if to_days:
            if day is None or day not in DAY_KEYS:
                raise ScheduleError("Say which day to copy")
            keys = [k for k in expand_days(to_days) if k != day]
            undo = self._snapshot([source])
            own = self._own(source)
            for key in keys:
                own["days"][key] = _copied(sched["days"].get(day) or {}, own["days"].get(key) or {}, times, limits)
            self._save()
            return undo.token
        targets = [p for p in (to_people or []) if p != source]
        if not targets:
            raise ScheduleError("Pick someone to copy to")
        if day is not None and day not in (*DAY_KEYS, "half_day"):
            raise ScheduleError(f"No day {day}")
        undo = self._snapshot(targets)
        for person in targets:
            own = self._own(person)
            if day is None:
                for key in DAY_KEYS:
                    own["days"][key] = _copied(sched["days"].get(key) or {}, own["days"].get(key) or {}, times, limits)
                if times:
                    own["half_day"] = {
                        **copy.deepcopy(sched.get("half_day") or {}),
                        **({} if limits else {"limits": (own.get("half_day") or {}).get("limits", DAY_OFF_KEY)}),
                    }
            elif day == "half_day":
                own["half_day"] = copy.deepcopy(sched.get("half_day") or {})
            else:
                own["days"][day] = _copied(sched["days"].get(day) or {}, own["days"].get(day) or {}, times, limits)
        self._save()
        return undo.token

    def change_today(
        self,
        person: str,
        day: date,
        *,
        changes: Any = None,
        limits: Any = None,
        bedtime: Any = None,
        mode: str | None = None,
        start: int | None = None,
        until: Any = None,
        by: str = "service",
        reason: str | None = None,
    ) -> str:
        """Today only: a copy of today's day, changed: its changes ([changes]), a later or earlier [bedtime] (the
        day's last Sleep moves, or one is added), or [mode] from [start] (minutes; now by default) [until] a time (the
        next change by default); limits merge into the day's. Ends at midnight. Returns an undo token."""
        undo = self._snapshot([person])
        current = self.resolve(person, day)
        mine = self.data.today.get(person)
        if not mine or mine.get("date") != day.isoformat():
            mine = {"date": day.isoformat(), "changes": None, "limits": None, "by": by, "reason": None}
        base = list(current.changes)
        new: list[tuple[int, str]] | None = None
        if changes is not None:
            new = as_minutes(normalize_changes(changes, self.data.modes))
        elif bedtime is not None:
            at = minutes_of(bedtime)
            sleep = next((m for m in self.data.modes if self.data.modes[m]["allows"] == NOTHING), SLEEP)
            kept = list(base)
            if kept and self.data.modes.get(kept[-1][1], {}).get("allows") == NOTHING:
                kept = kept[:-1]
            kept = [c for c in kept if c[0] < at]
            new = merged([*kept, (at, sleep)])
        elif mode is not None:
            if mode not in self.data.modes:
                raise ScheduleError(f"No mode {mode!r}")
            begin = start if start is not None else 0
            end = minutes_of(until) if until not in (None, "") else next((m for m, _ in base if m > begin), None)
            if end is not None and end <= begin:
                raise ScheduleError("It has to end after it starts")
            # What ran at [end] before, so it picks up again there
            before_end = None
            if end is not None:
                before_end = next((md for m, md in reversed(base) if m <= end), None) or self._carry(person, day)
            kept = [c for c in base if c[0] < begin or (end is not None and c[0] > end)]
            new_items = [*kept, (begin, mode)]
            if end is not None and before_end is not None and not any(c[0] == end for c in kept):
                new_items.append((end, before_end))
            new = merged(new_items)
        if new is not None:
            if len(new) > MAX_CHANGES:
                raise ScheduleError(f"At most {MAX_CHANGES} changes a day")
            mine["changes"] = [[hhmm(m), md] for m, md in new]
        if limits is not None:
            mine["limits"] = {**(mine.get("limits") or {}), **normalize_limits(limits)}
        if mine.get("changes") is None and mine.get("limits") is None:
            raise ScheduleError("Say what changes today")
        mine["by"] = by
        mine["reason"] = (reason or "").strip()[:80] or mine.get("reason")
        self.data.today[person] = mine
        self._save()
        return undo.token

    def resume(self, people: list[str]) -> list[str]:
        """Drops today's changes: back to the schedule."""
        dropped = [p for p in people if self.data.today.pop(p, None) is not None]
        if dropped:
            self._save()
        return dropped

    def new_day(self, today: date) -> list[str]:
        """Today-only changes of days gone by end (at midnight)."""
        gone = [p for p, t in self.data.today.items() if t.get("date") != today.isoformat()]
        for person in gone:
            self.data.today.pop(person)
        if gone:
            self._save()
        return gone

    # Modes

    def set_mode(
        self,
        mode_id: str | None,
        name: str,
        allows: str,
        closed: list[str] | None = None,
        keep_not_screen_time: bool | None = None,
        color: str | None = None,
    ) -> str:
        """Adds a mode or changes one (everywhere it's used). Returns its id."""
        name = (name or "").strip()[:MAX_NAME]
        if not name:
            raise ScheduleError("Give the mode a name")
        if allows not in ALLOWS:
            raise ScheduleError(f"A mode allows one of {', '.join(ALLOWS)}")
        modes = self.data.modes
        if mode_id is None or mode_id not in modes:
            if len(modes) >= MAX_MODES:
                raise ScheduleError(f"At most {MAX_MODES} modes")
            base = mode_id or re.sub(r"[^a-z0-9]+", "_", name.lower()).strip("_")[:24] or "mode"
            mode_id, n = base, 2
            while mode_id in modes:
                mode_id, n = f"{base}_{n}", n + 1
        existing = modes.get(mode_id) or {}
        if existing.get("builtin") and existing.get("allows") != allows:
            raise ScheduleError(f"{existing['name']} always {describe_allows(existing['allows'])}")
        self._snapshot([], modes=True)
        mode: dict[str, Any] = {"name": name, "allows": allows}
        if existing.get("builtin"):
            mode["builtin"] = True
        if allows == SOME:
            mode["closed"] = [g for g in dict.fromkeys(closed or []) if g and g != "all"]
        if allows == NOTHING:
            mode["keep_not_screen_time"] = (
                bool(keep_not_screen_time) if keep_not_screen_time is not None else existing.get("keep_not_screen_time", True)
            )
        if color or existing.get("color"):
            mode["color"] = color or existing.get("color")
        modes[mode_id] = mode
        self._save()
        return mode_id

    def remove_mode(self, mode_id: str) -> list[str]:
        """Removes a mode that isn't built in: where it was used, the change goes (the one before runs on).
        Returns the people whose schedules used it."""
        mode = self.data.modes.get(mode_id)
        if mode is None:
            raise ScheduleError(f"No mode {mode_id!r}")
        if mode.get("builtin"):
            raise ScheduleError(f"{mode['name']} is built in and can't be removed")
        touched = [p for p, s in self.data.people.items() if _uses(s, mode_id)] + [
            p for p, t in self.data.today.items() if any(m == mode_id for _, m in t.get("changes") or [])
        ]
        self._snapshot(list(dict.fromkeys(touched)), modes=True)
        del self.data.modes[mode_id]
        for sched in self.data.people.values():
            for day in sched["days"].values():
                day["changes"] = [[hhmm(a), m] for a, m in merged([c for c in as_minutes(day.get("changes") or []) if c[1] != mode_id])]
        for today in self.data.today.values():
            if today.get("changes") is not None:
                today["changes"] = [[hhmm(a), m] for a, m in merged([c for c in as_minutes(today["changes"]) if c[1] != mode_id])]
        self._save()
        return list(dict.fromkeys(touched))

    # The two budgets

    def budget_of_kind(self, person: str, group: str, kind: str) -> int | None:
        """A budget as the old numbers show it: Monday's limit for school days, Saturday's for other days."""
        days = self.schedule_of(person)["days"]
        return (days.get("mon" if kind == "weekday" else "sat") or {}).get("limits", {}).get(group)

    def set_budget_kind(self, person: str, group: str, kind: str, minutes: int | None) -> None:
        """The old budgets write the schedule: school days Monday to Friday; other days Saturday, Sunday and the Day
        off. A person whose schedule an adult never edited follows the budgets anyway."""
        if person not in self.data.people:
            return
        keys = DAYS[:5] if kind == "weekday" else (*DAYS[5:], DAY_OFF_KEY)
        for key in keys:
            self.data.people[person]["days"].setdefault(key, {"changes": [], "limits": {}}).setdefault("limits", {})[group] = minutes
        self._save()

    # Views

    def view(self, person: str) -> dict[str, Any]:
        sched = self.schedule_of(person)
        return {
            "set": self.is_set(person),
            "days": copy.deepcopy(sched["days"]),
            "half_day": copy.deepcopy(sched.get("half_day") or {}),
            "today": copy.deepcopy(self.data.today.get(person)),
        }


def describe_allows(allows: str) -> str:
    return {
        EVERYTHING: "allows everything",
        SOME: "closes some groups",
        SCHOOL_MODE: "is School time",
        NOTHING: "is bedtime",
    }.get(allows, allows)


def expand_days(days: list[str] | str | None) -> list[str]:
    """mon..sun, day_off and the sets (school_days, weekend, every_day) as day keys, in order."""
    out: list[str] = []
    for given in [days] if isinstance(days, str) else days or []:
        for key in DAY_SETS.get(given, (given,)):
            if key not in DAY_KEYS:
                raise ScheduleError(f"No day {given!r} (mon to sun, day_off, school_days, weekend, every_day)")
            if key not in out:
                out.append(key)
    if not out:
        raise ScheduleError("Say which days")
    return out


def _copied(source: dict[str, Any], target: dict[str, Any], times: bool, limits: bool) -> dict[str, Any]:
    return {
        "changes": copy.deepcopy(source.get("changes") or []) if times else copy.deepcopy(target.get("changes") or []),
        "limits": dict(source.get("limits") or {}) if limits else dict(target.get("limits") or {}),
    }


def _uses(sched: dict[str, Any], mode_id: str) -> bool:
    return any(m == mode_id for day in sched.get("days", {}).values() for _, m in day.get("changes") or [])
