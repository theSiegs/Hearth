"""The household's schedule: what each kind of day does to the kids' Family Link, School time taken off and put back,
and the daily website list (docs/home-assistant-integration.md, Schedule).

Today's day type comes from School days (schooldays.py): school, half_day, day_off, weekend or no_school. Per day type
(Configure > Schedule):

- A day off: each kid's School time is switched off for the day (switch.turn_off on Family Link's School time switch,
  which turns off the weekly School time with today's), and put back on the next school day.
- A half day: School time ends some hours early, today only (familylink.set_school_time, scope today), for a kid whose
  School time is on; one whose School time is off gets the early end when it is put back.
How much time a day gets is its budget and nothing else: school days the school-day budget; weekends, days off and
no-school days the other days' budget; a half day the one School days chooses (half_day_budget, other days' by
default); a kid kept home (hearth.home_today) the other days'. The schedule adds no time of its own (an older Hearth's
day_off_bonus, half_day_bonus and bonus_group, which stacked a bonus on top of the other days' budget, are ignored).
An adult's bonus time comes on top as always.

The parents' own apps follow the day's budget instead, so one never stops a kid before Hearth's budget does, every
day (not only days off: a weekend's budget can be over a weekday limit just as well), without changing their weekly
settings for good. Only ever raised, never lowered: a native limit at or over the budget, or with no limit, is left
alone, and Hearth's own holds still stop the kid when the budget is spent.

- Family Link: with Hearth's Family Link backstop on (the default, backstop.py) its daily limit already follows
  Hearth's time left: nothing more here. With the backstop off, and when chosen (follow_family_link, off by default:
  turning the backstop off means keeping Family Link's own limits), today's daily limit is raised to the day's All
  screen time budget when the weekday's limit is lower, as a today-only override (set_daily_limit without a day: it
  ends by itself; written only once Hearth's own hold of the devices is let go; written again if the day's budget
  changes, the weekday's own limit when the budget falls to it).
- When chosen for Family Safety (follow_family_safety, off by default) or for the Switch (follow_nintendo, off by
  default), a limit that is a setting, not today's alone, is raised to the day's budget as a temporary limit Hearth
  puts back itself. The budget of a platform is the least of the budgets of the groups its enforcer holds for (All
  screen time and Games by default): the first of those to run out holds the platform, so it can never give more.
  (temporary_limit.py: Hearth records what it raised from and what it wrote before writing, kept across a restart
  and midnight; puts it back 2 minutes before midnight, at once when the day's budget changes (School days say
  otherwise, a kid kept home or that cancelled, a budget changed) and then raises it again to the new budget once
  the platform shows the put-back, or on the next start when that was missed; only while the limit still reads
  Hearth's, so a parent's change since stays; a write that failed isn't counted as done and is tried again while it's
  still today):
  - Family Safety (Windows, Xbox): for each of those platforms of a kid's Family Safety enforcer, this weekday's limit
    (the integration's per-day limit number: Windows' <weekday> Limit, the Xbox <weekday> Limit) goes up to the
    budget, at most 24 hours, through microsoft_family_safety.set_screentime_limit with day_of_week (upstream's
    service, the child's entity or account). A parent's own change before Hearth's is read as the limit now. The
    Xbox's goes through the Xbox Family Settings sign-in, and fails without it: not set, tried again, reported at the
    check. A platform without a limit today (24 hours) is left alone. Hearth never uses Family Safety's account lock
    switch (lock_account), which saves the limits it finds as its restore point: on a raised day that would be the
    raised one, but Hearth puts its value back only while it still reads it.
  - The Switch: each chosen kid's Switch (their Nintendo enforcer's Max screentime today) goes up to the budget (at
    most 360, the Switch's own maximum), set once per Switch; a Switch kids share takes the biggest of their budgets,
    so it never stops the kid with the most time first (each kid's own hold still stops them at theirs). Nintendo
    has no today-only limit: the number is the setting of every day, or of this weekday. It's put back as the
    Nintendo enforcer does; after midnight (Home Assistant was off), a Switch with a limit per weekday gets that
    weekday's limit and bedtime back through update_daily_restrictions. A Switch with no limit (-1) is left alone.
    While bonus time from the Nintendo app runs, the Switch refuses a new limit, so Hearth waits. While Hearth holds
    the Switch (limit 0 for a budget or a pause), nothing is written to it: the raise goes into what the hold puts
    back (and comes out of it again when the budget changes or at midnight), so letting go gives the raised limit and
    a hold never fights it.
- Bonus time an adult gives goes to the parents' apps as their own extra time (native_sync.mirror_bonus), on top of
  the raised limit.

hearth.school_time_off takes School time off for some people on a date (today by default), from a time if given.

hearth.home_today keeps a kid home on a school day (a sick day): that day is a day off for them alone. Their weekly
schedule and limits are the Day off's, and with Family Link their School time is taken off for the whole day (as
school_time_off, put back on their next school day). hearth.home_today_cancel undoes it; on the day itself School time
goes back on inside their window, as a cancelled School time off does. Kept per person and date (home), till the day
has passed.

Putting School time back is the delicate part. Switching it on outside the kid's window opens a window from then until
23:59, so Hearth switches it on only inside the kid's own weekly window for today (some hours shorter on a half day),
then at once pins today's window to those hours (set_school_time, scope today), and checks each minute until the
child's devices say the pinned end. The weekly window is read from Family Link's time entities, and kept when School
time is taken off in case they read unknown while it's off. A kid whose window has ended is left for the next school
day. At the watchdog time on a school day, the adults are told about anyone whose School time is still off.

The day's actions run from DAY_START (00:05); a check at CHECK_AT (06:00) tries a School time that didn't go off again
and tells the adults what didn't apply, so nobody is woken at midnight. Each action runs once a day (kept across a
restart). The website list is synced once a day at its time, person by person, through Family Link
(familylink.sync_site_list) and Family Safety each on its own: a Family Safety with sync_site_list (a fork's) does it
itself; the released one is kept in step by Hearth (fs_site_list.py: the list downloaded once, get_sites, block_website,
remove_website, what Hearth added kept here). A failure for one is logged, tried again later, and the others go on. The
hearth_schedule events say which with "via". Sites an adult blocked by hand (hearth.block_site, site_blocks.py, kept here
too) stay blocked when the list drops them.

What's pending is kept with Home Assistant's storage helper.
"""

from __future__ import annotations

import asyncio
from dataclasses import dataclass, field
from datetime import date, datetime, time, timedelta
import logging
import secrets
from typing import TYPE_CHECKING, Any

from homeassistant.core import HomeAssistant
from homeassistant.exceptions import HomeAssistantError
from homeassistant.helpers.storage import Store
from homeassistant.util import dt as dt_util

from . import family_link as fl
from . import fs_site_list
from .counting import ALL
from .enforce import (
    FAMILY_LINK,
    FAMILY_SAFETY,
    FS_DOMAIN,
    NINTENDO,
    WEEKDAYS,
    Enforcer,
    enforcers_from_options,
    fs_accepts,
    fs_account_of,
    fs_day_limit_entity,
    near_midnight,
)
from .schooldays import DAY_OFF, HALF_DAY, SCHOOL
from .temporary_limit import DONE, SET, SKIP, SWITCH, WAIT, WINDOWS, WRITE, XBOX, TemporaryLimits
from .activity import call_service
from .site_blocks import SiteBlocks

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
# Weekly School time hours Hearth just wrote (hearth.set_school_time) count over Family Link's time entities this long:
# they show the old hours until its next refresh
HOURS_FRESH = timedelta(minutes=15)
MAX_REASON = 120
EVENT_SCHEDULE = "hearth_schedule"
# The reason of the School time off a day off takes
DAY_OFF_REASON = "Day off"
# The reason of the School time off a kid kept home takes, when none is given
HOME_REASON = "Home today"
# Family Safety's limit of a weekday (Windows, or the Xbox through the Xbox Family Settings sign-in)
FS_LIMIT = "set_screentime_limit"
FULL_DAY = 1440
# The platforms whose weekday limit follows the day's budget
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
    half_day_hours_early: float = 0
    # With the backstop off, Family Link's daily limit today goes up to the day's budget. Off unless chosen: the
    # backstop off means keeping Family Link's own limits (an older Hearth's bonus_family_link, on by default, did
    # nothing without day-off minutes, so it isn't carried over)
    follow_family_link: bool = False
    # Off unless chosen: a household that set this up for Family Link doesn't get its Windows and Xbox raised too
    # (an older Hearth's bonus_family_safety, chosen, carries over)
    follow_family_safety: bool = False
    # Off unless chosen, as Family Safety's: the Switch's limit is a setting Hearth must put back itself
    follow_nintendo: bool = False
    # Whose (empty: everyone with Family Link, and for Family Safety's and the Switch's everyone with them, in
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
            half_day_hours_early=max(0.0, min(12.0, _number(raw.get("half_day_hours_early")))),
            follow_family_link=raw.get("follow_family_link") is True,
            follow_family_safety=raw.get("follow_family_safety", raw.get("bonus_family_safety")) is True,
            follow_nintendo=raw.get("follow_nintendo", raw.get("bonus_nintendo")) is True,
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
    # Made by hearth.home_today (keep_home): the only School time off hearth.home_today_cancel ends
    home: bool = False

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


WEEKDAY_KEYS = ("mon", "tue", "wed", "thu", "fri", "sat", "sun")


def _iso_date(value: Any) -> date | None:
    try:
        return date.fromisoformat(str(value))
    except ValueError:
        return None


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
        # The limits raised to the day's budget, kept until they're put back, over midnight and a restart too
        # (temporary_limit.py): a Switch (its Max screentime today entity, with what putting it back after midnight
        # needs: device_id, bedtime_alarm, bedtime_end_time) and a Family Safety child's Windows or Xbox (by
        # "family_safety|<enforcer entity>|<platform>", with the enforcer's entity_id)
        self.temporary = TemporaryLimits(self._save)
        self._lock = asyncio.Lock()
        self._failed: dict[str, datetime] = {}
        self._done_at: dict[str, datetime] = {}
        # What Hearth blocked from website lists in Family Safety itself (no sync_site_list): {account: {url: [domains]}}
        self.fs_sites = fs_site_list.FsSiteList(hass, {}, self._save)
        # Websites an adult blocked by hand (hearth.block_site): what Hearth's block added, per kid and side
        self.site_blocks = SiteBlocks(hass, self)
        # Kids kept home on a school day (hearth.home_today): person -> {ISO date: reason}
        self.home: dict[str, dict[str, str]] = {}
        # Family Link School time to switch on (hearth.set_school_time switch_on): person -> ISO date from which. Put
        # on as a School time off is put back: on a school day, inside the kid's window, and pinned at once
        self.turn_on: dict[str, str] = {}
        # Weekly School time hours Hearth wrote: person -> {ISO weekday: (start, end, when)}, used over Family Link's
        # time entities for HOURS_FRESH (a switch-on right after the write mustn't pin the old hours)
        self.written_hours: dict[str, dict[int, tuple[time, time, datetime]]] = {}

    # Storage

    async def async_load(self) -> None:
        stored = await self._store.async_load() or {}
        self.day = stored.get("day")
        self.marks = {k: list(v) for k, v in (stored.get("marks") or {}).items()}
        self.limits_set = {k: int(v) for k, v in (stored.get("limits_set") or {}).items()}
        self.fs_sites.owned = {
            str(account): {str(url): [str(d) for d in domains] for url, domains in lists.items() if isinstance(domains, list)}
            for account, lists in (stored.get("fs_sites") or {}).items()
            if isinstance(lists, dict)
        }
        self.site_blocks.load(stored.get("site_blocks"))
        # An older Hearth kept the Switches' as sw_limits; its fs_limits were Family Safety's own today-only changes,
        # which Family Safety put back itself: nothing of Hearth's to put back
        self.temporary.load(stored.get("temporary_limits"), stored.get("sw_limits"))
        self.home = {
            str(person): {str(d): str(r or "") for d, r in days.items()}
            for person, days in (stored.get("home") or {}).items()
            if isinstance(days, dict)
        }
        self._prune_home(dt_util.now().date())
        self.turn_on = {
            str(person): str(day)
            for person, day in (stored.get("turn_on") or {}).items()
            if isinstance(day, str) and _iso_date(day) is not None
        }
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
            # Stored before home was kept: a whole-day one of a day the person is kept home on was keep_home's
            off.home = (
                bool(raw["home"])
                if "home" in raw
                else off.start is None and off.ends_on is None and self.home_on(off.person, off.day) is not None
            )
            self.offs[off.id] = off

    def _data(self) -> dict[str, Any]:
        return {
            "day": self.day,
            "marks": self.marks,
            "limits_set": self.limits_set,
            "temporary_limits": self.temporary.dump(),
            "fs_sites": self.fs_sites.owned,
            "site_blocks": self.site_blocks.dump(),
            "home": self.home,
            "turn_on": self.turn_on,
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
                    "home": o.home,
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

    def _unmark(self, who: str, prefix: str) -> None:
        """Today's marks of [who] starting with [prefix] are dropped (done again)."""
        kept = [m for m in self.marks.get(who, []) if not m.startswith(prefix)]
        if who in self.marks and len(kept) != len(self.marks[who]):
            self.marks[who] = kept
            self._save()

    def off_now(self, person: str, now: datetime | None = None) -> Off | None:
        """School time is off for the person by Hearth now: taken off for a day that isn't over (one waiting to be put
        back is a school day again, whether or not Family Link has caught up)."""
        today = dt_util.as_local(now or dt_util.now()).date()
        return next(
            (
                o
                for o in self.offs.values()
                if o.person == person and o.applied and (o.restore_from is None or today < o.restore_from)
            ),
            None,
        )

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

    # Kept home (a sick day)

    def home_on(self, person: str, day: date) -> str | None:
        """The reason the person is kept home on [day] ("" when none was given), or None when they aren't."""
        return self.home.get(person, {}).get(day.isoformat())

    def homes_of(self, person: str) -> list[dict[str, Any]]:
        """The days from today on the person is kept home (yesterday's is kept for the history only, _prune_home)."""
        today = dt_util.now().date().isoformat()
        return [{"date": d, "reason": r} for d, r in sorted(self.home.get(person, {}).items()) if d >= today]

    def keep_home(self, people: list[str], day: date, reason: str | None) -> list[str]:
        """The people are home on [day]: a day off for them alone, and School time off for the day for those with
        Family Link. Returns the School time off ids.

        The School time off is keep_home's own (Off.home), next to any the day already has (one from 13:00 that ends
        on arriving somewhere): that one keeps its time, reason and ends_on, and cancel_home leaves it."""
        reason = (reason or "").strip()[:MAX_REASON]
        for person in people:
            self.home.setdefault(person, {})[day.isoformat()] = reason
        ids: list[str] = []
        for person in people:
            if self.child(person) is None:
                continue
            own = next((o for o in self._home_offs(person, day) if o.restore_from is None or o.restore_from > day), None)
            if own is None:
                own = Off(secrets.token_hex(6), person, day, None, home=True)
                self.offs[own.id] = own
            own.reason = reason or HOME_REASON
            ids.append(own.id)
        self._save()
        return ids

    def _home_offs(self, person: str, day: date) -> list[Off]:
        return [o for o in self.offs.values() if o.home and o.person == person and o.day == day]

    def cancel_home(self, people: list[str] | None, day: date | None) -> list[str]:
        """Not home after all: each one's day is a school day again, and the School time off keep_home made ends as a
        cancelled School time off does (not taken off yet: dropped; taken off: put back from today). Any other School
        time off of that day stays. Returns the people it changed."""
        today = dt_util.now().date()
        changed: list[str] = []
        for person in list(self.home):
            if people is not None and person not in people:
                continue
            days = self.home[person]
            # Not a day that's over (yesterday's, kept for the history)
            for iso in [d for d in days if d >= today.isoformat() and (day is None or d == day.isoformat())]:
                del days[iso]
                if person not in changed:
                    changed.append(person)
                for off in self._home_offs(person, date.fromisoformat(iso)):
                    if off.applied:
                        off.restore_from = today
                    else:
                        del self.offs[off.id]
            if not days:
                del self.home[person]
        self._save()
        return changed

    def _prune_home(self, today: date) -> None:
        """Yesterday's stays one more day: its history (household.budget_on of the day before) is still asked for,
        and must show the day off's budget. Everything else asks by date (home_on) or from today on (homes_of)."""
        keep_from = (today - timedelta(days=1)).isoformat()
        for person in list(self.home):
            self.home[person] = {d: r for d, r in self.home[person].items() if d >= keep_from}
            if not self.home[person]:
                del self.home[person]

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
                (
                    o
                    for o in self.offs.values()
                    # Never hearth.home_today's own: that one stays whole-day, and its cancel ends it alone
                    if o.person == person and o.day == day and not o.applied and not o.home
                ),
                None,
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

        School time only: the day's budget, and the parents' limits raised to it, stay what the day type says (an
        older Hearth called off a day off's Family Safety and Switch extra time here; there's no extra any more)."""
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
            self._prune_home(today)
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
        # With Hearth's Family Link backstop on (backstop.py), Family Link's limit follows Hearth's time left already
        if config.follow_family_link and not self.household.backstop.enabled():
            await self._family_link_follow(person, today)

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
            await call_service(self.hass, domain, service, data, blocking=True)
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
        window = self.weekly(person, child, today)
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

    # The day's budget, which the parents' apps follow

    def budget_known(self, person: str, today: date) -> bool:
        """Hearth has worked out the person's day today (a restart, or the first minutes past midnight, may not yet):
        until then nothing is raised or put back for a budget change."""
        household = self.household
        return household.today == today and person in household.days

    def day_budget(self, person: str, groups: tuple[str, ...], today: date) -> int | None:
        """Hearth's budget today (no bonus) of the first of [groups] to run out: the least of their budgets, the most
        a platform held for those groups gives. None: none of them has one, or the day isn't worked out yet."""
        if not self.budget_known(person, today):
            return None
        budgets = self.household.budget_on(person, today)
        found = [int(b) for g in groups if (b := budgets.get(g)) is not None]
        return min(found) if found else None

    def _family_link_target(self, person: str, child: str, today: date) -> int | None:
        """The today-only daily limit Family Link should have for the day's budget: the budget when the weekday's
        limit is lower; the weekday's own when Hearth raised it today and the budget has fallen to it since; None when
        there's nothing to write (no daily limit today, the day not worked out, already done)."""
        switch = fl.daily_limit_switch(self.hass, child)
        switch_state = self.hass.states.get(switch) if switch else None
        if switch_state is not None and switch_state.state != "on":
            return None  # no daily limit today: nothing to raise
        limit = fl.weekday_limit(self.hass, child, today)
        weekly = limit.get("weekly_minutes") if limit else None
        if not isinstance(weekly, (int, float)) or not self.budget_known(person, today):
            return None
        budget = self.day_budget(person, (ALL,), today)
        target = max(int(weekly), min(FULL_DAY, budget)) if budget is not None else int(weekly)
        done = self.limits_set.get(person)
        if done == target or (done is None and target <= int(weekly)):
            return None
        return target

    async def _family_link_follow(self, person: str, today: date) -> bool:
        """Today's daily limit = the day's All screen time budget when the weekday's limit is lower, as a today-only
        override (no day); written again when the budget changes.

        Not while Hearth holds the kid's devices (Sleep past midnight, daily time out, a family pause: the weekday's
        limit at 0): the override would open them, read as a parent's change in the Family Link app, and keep the
        weekday's real limit from being put back. False then, so it's tried again each minute and written once the
        hold is let go, as Family Link extra time waits (native_sync._give_family_link). Never folded into the limit
        the hold puts back (as a Switch's is): that one is the weekday's own setting, for every week."""
        child = self.child(person)
        if child is None:
            return True
        if self.household.enforcement.family_link_devices_held(person):
            return False
        target = self._family_link_target(person, child, today)
        if target is None:
            return True
        # The child's id as a string, never a template: Home Assistant reads 21 digits as a number and loses some
        ok = await self._call(
            f"{person}|limit", "familylink", "set_daily_limit", {"child_id": str(child), "daily_minutes": target}
        )
        if ok:
            self.limits_set[person] = target
            self._save()
            self._event("limit_raised", person, via="family_link", daily_minutes=target)
        return ok

    # Family Safety (Windows, Xbox): the weekday's limit raised to the day's budget, put back by Hearth

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
        targets = [{"entity_id": entity_id}] if "." in entity_id else []
        account = fs_account_of(self.hass, entity_id)
        if account is not None:
            targets.append({"account_id": account})
        for target in targets:
            data = {**target, **fields}
            if fs_accepts(self.hass, service, data):
                return data
        return None

    def _fs_limit_wanted(self, enforcer: Enforcer, config: ScheduleConfig) -> bool:
        """Family Safety takes part: following the day's budget is chosen (Configure > Schedule) and it has a weekday's
        limit."""
        return config.follow_family_safety and self._fs_data(
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

    def _fs_target(self, enforcer: Enforcer, today: date) -> int | None:
        """What a Family Safety platform of the enforcer goes up to today: the day's budget of the groups it holds
        for, at most a day. None: no budget."""
        budget = self.day_budget(enforcer.person, enforcer.groups, today)
        return None if budget is None else min(FULL_DAY, budget)

    def _fs_still_wanted(self, mine: dict[str, Any], config: ScheduleConfig, today: date) -> bool:
        """A Family Safety raise of today is still the one the day's budget wants (or the day isn't worked out yet:
        nothing changes on a guess)."""
        people = mine.get("people") or []
        person = people[0] if people else None
        enforcer = self.family_safety_enforcer(person) if person else None
        if enforcer is None or enforcer.entity_id != mine.get("entity_id") or not config.follow_family_safety:
            return False
        if not self.budget_known(person, today):
            return True
        return self._fs_target(enforcer, today) == mine["target"]

    def _moved(self, key: str, target: Any) -> None:
        """A raise put back because the day's budget changed: raised again to the new budget, but only once the
        platform no longer reads the one put back (it may show it till its next read)."""
        self._mark("", f"moved:{key}={target}")

    def _moved_from(self, key: str, current: Any) -> bool:
        """The platform still reads a raise put back today for a budget change: not read back yet, wait."""
        value = _number(current, None)
        return value is not None and self._marked("", f"moved:{key}={int(value) if value == int(value) else value}")

    async def _family_safety_day(self, now: datetime, kind: str, config: ScheduleConfig) -> None:
        """What Hearth raised on a Family Safety platform goes back when due (a later day, just before midnight, the
        day's budget changed); then each chosen platform goes up to the day's budget, once a day (again after a
        budget change)."""
        today = now.date()
        for key, mine in self.temporary.of(FS_LIMIT_PLATFORMS):
            still = self._fs_still_wanted(mine, config, today)
            reading = self._fs_current(str(mine.get("entity_id")), mine["platform"], str(mine.get("weekday")))
            # Raised again for the new budget, unless a parent changed the limit since (theirs stays all day)
            moved = (
                not still
                and self.temporary.today(mine, today)
                and not near_midnight(now)
                and not (mine.get("written_at") and reading not in (None, mine["target"], mine["base"]))
            )
            if self.temporary.due(mine, now, still) and await self._family_safety_restore(key, mine):
                self.temporary.drop(key)
                if moved:
                    self._moved(key, mine["target"])
                    for person in mine.get("people") or []:
                        self._unmark(person, f"fs_raised:{mine['platform']}@")
                else:
                    self._mark("", f"fs_back:{key}")
        if near_midnight(now) or now.time() < DAY_START:
            return
        for person in self.family_safety_people(config.people):
            enforcer = self.family_safety_enforcer(person)
            if enforcer is None or not self._fs_limit_wanted(enforcer, config):
                continue
            target = self._fs_target(enforcer, today)
            if target is None:
                continue
            for platform in enforcer.platforms:
                # Done once per budget: a budget changed since is looked at again
                if platform not in FS_LIMIT_PLATFORMS or self._marked(person, f"fs_raised:{platform}@{target}"):
                    continue
                if self._marked("", f"fs_back:{self._fs_key(enforcer.entity_id, platform)}"):
                    continue  # put back already today: not raised again
                done = await self._family_safety_limit(person, enforcer, platform, today, target)
                if done is not None:
                    self._mark(person, f"fs_raised:{platform}@{target}")

    async def _family_safety_limit(
        self, person: str, enforcer: Enforcer, platform: str, today: date, budget: int
    ) -> str | None:
        """This weekday's limit of the platform up to [budget]. SET, SKIP (no limit today, or one at the budget or over
        it: nothing to raise; or Hearth's limit changed since, by a parent), or None when not done (not read, just
        written, an earlier day's not put back yet, or the call failed: tried again; the Xbox's fails without the Xbox
        Family Settings sign-in).

        The limit read is the weekday's as it is now: a parent's change before Hearth's is what's raised from.
        Hearth's own (kept in temporary) is never taken as the limit to raise from."""
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
        elif self._moved_from(key, current):
            return None  # Hearth's earlier raise of today, put back for a budget change: not read back yet
        if current is None:
            return None
        if current < 0 or current >= FULL_DAY:
            return SKIP
        target = min(FULL_DAY, budget)
        if target <= current:
            return SKIP  # the limit is at the budget or over it: it never stops the kid first
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
        self._event("limit_raised", person, via="family_safety", platform=platform, daily_minutes=target)
        return SET

    async def _family_safety_restore(self, key: str, mine: dict[str, Any]) -> bool:
        """The limit Hearth raised goes back on the recorded weekday (on a later day too: a weekday's limit reads and
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
            self._event("limit_back", person, via="family_safety", platform=platform, daily_minutes=mine["base"])
        return True

    # Nintendo Switch: its Max screentime today raised to the day's budget, put back by Hearth

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

    def _switch_target(self, entity_id: str, people: list[str], today: date) -> int | None:
        """What a Switch goes up to today: the biggest of its kids' day budgets (each of the groups their Nintendo
        enforcer holds for), so it never stops the kid with the most time first, at most SWITCH_MAX. A kid with no
        budget isn't counted (the Switch's own limit is their only one). None: no budget."""
        budgets = [
            budget
            for e in enforcers_from_options(self.household.options)
            if e.kind == NINTENDO and e.entity_id == entity_id and e.person in people
            and (budget := self.day_budget(e.person, e.groups, today)) is not None
        ]
        return min(SWITCH_MAX, max(budgets)) if budgets else None

    def _switch_still_wanted(self, entity_id: str, mine: dict[str, Any], config: ScheduleConfig, today: date) -> bool:
        """A Switch's raise of today is still the one the day's budgets want (or a day isn't worked out yet)."""
        people = self.nintendo_switches(config.people).get(entity_id)
        if not people or not config.follow_nintendo:
            return False
        if not all(self.budget_known(p, today) for p in people):
            return True
        return self._switch_target(entity_id, people, today) == mine["target"]

    async def _nintendo_day(self, now: datetime, kind: str, config: ScheduleConfig) -> None:
        """What Hearth raised on a Switch goes back when due (a later day, just before midnight, the day's budget
        changed); then each chosen Switch goes up to the day's budget, once a day (again after a budget change)."""
        today = now.date()
        for entity_id, mine in self.temporary.of((SWITCH,)):
            still = self._switch_still_wanted(entity_id, mine, config, today)
            state = self.hass.states.get(entity_id)
            reading = _number(state.state if state else None, None)
            hold = self.household.enforcement.switch_hold(entity_id)
            # Raised again for the new budget, unless a parent changed the limit since (theirs stays all day)
            theirs = bool(hold.restore.get("adopted")) if hold is not None else bool(
                mine.get("written_at") and reading not in (None, 0, mine["target"], mine["base"])
            )
            moved = not still and self.temporary.today(mine, today) and not near_midnight(now) and not theirs
            if self.temporary.due(mine, now, still) and await self._nintendo_restore(entity_id, mine, today):
                self.temporary.drop(entity_id)
                if moved:
                    self._moved(entity_id, mine["target"])
                    self._unmark("", f"sw_raised:{entity_id}@")
                else:
                    self._mark("", f"sw_back:{entity_id}")
        if not config.follow_nintendo or near_midnight(now) or now.time() < DAY_START:
            return
        for entity_id, people in self.nintendo_switches(config.people).items():
            target = self._switch_target(entity_id, people, today)
            if target is None:
                continue
            # Done once per budget: a budget changed since is looked at again
            if self._marked("", f"sw_raised:{entity_id}@{target}") or self._marked("", f"sw_back:{entity_id}"):
                continue
            done = await self._nintendo_raise(entity_id, people, target, today)
            if done is not None:
                self._mark("", f"sw_raised:{entity_id}@{target}")

    async def _nintendo_raise(self, entity_id: str, people: list[str], budget: int, today: date) -> str | None:
        """Today's limit of the Switch up to [budget]. SET, SKIP (no limit, or one at the budget or over it), or None
        when not done (not read, bonus time running, Hearth's hold under way, the call failed: tried again)."""
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
            # Held (limit 0): nothing is written to the Switch. The raise goes into what letting go puts back
            if hold.restore.get("adopted"):
                return None  # a parent's change lets the hold go: then their limit is the one to raise from
            if current != 0:
                # Not reading the hold's 0 yet: changing what it puts back now would look like a parent's change
                return None
            base = _number(hold.restore.get("max"), None)
        else:
            if enforcement.switch_extended(entity_id):
                return None  # bonus time from the Nintendo app runs: the Switch refuses a new limit till it's over
            if mine is None and self._moved_from(entity_id, current):
                return None  # Hearth's earlier raise of today, put back for a budget change: not read back yet
            base = current
        if base is None:
            return None
        if base < 0 or base >= SWITCH_MAX:
            return SKIP  # no limit, or the most already: nothing to raise
        target = min(SWITCH_MAX, budget)
        if target <= base:
            return SKIP  # the limit is at the budget or over it: it never stops the kid first
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
            self._event("limit_raised", person, via="nintendo", switch=entity_id, daily_minutes=target)
        return SET

    async def _nintendo_restore(self, entity_id: str, mine: dict[str, Any], today: date) -> bool:
        """The limit Hearth raised goes back, only while the Switch has Hearth's: True when done (put back, or a
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
            self._event("limit_back", person, via="nintendo", switch=entity_id, daily_minutes=mine["base"])

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

    def weekly(self, person: str, child: str, day: date) -> tuple[time, time] | None:
        """The day's weekly School time window: hours Hearth wrote in the last HOURS_FRESH, else Family Link's."""
        written = self.written_hours.get(person, {}).get(day.isoweekday())
        if written is not None and dt_util.utcnow() - written[2] < HOURS_FRESH:
            return written[0], written[1]
        return fl.weekly_window(self.hass, child, day)

    def _window(self, person: str, child: str, today: date, kind: str, config: ScheduleConfig) -> tuple[time, time] | None:
        window = self.weekly(person, child, today)
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
        for person, since in self.turn_on.items():
            if (from_day := _iso_date(since)) is not None and from_day <= today:
                due.setdefault(person, [])
        for person, offs in due.items():
            # Taken off for today too (a second day off in a row, or from a time later today): not put back today.
            # Today's off may be applied already (at midnight), so whether it is doesn't matter
            # (one ended early today, on arriving at school, is due itself)
            if any(
                o.day == today and (o.restore_from is None or o.restore_from > today)
                for o in self.offs.values()
                if o.person == person
            ):
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
                    self.turn_on.pop(person, None)
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
            self.turn_on.pop(person, None)
            self._save()
            self._event("school_time_back", person, end=hhmm(end))
            self.household.recompute()

    # hearth.set_school_time: Family Link's weekly School time hours, and switching it on

    async def set_school_hours(self, person: str, hours: dict[int, tuple[time, time]]) -> dict[str, Any]:
        """Writes the person's weekly Family Link School time for each ISO weekday in [hours] ({iso: (start, end)}),
        through familylink.set_school_time (weekly scope; the day must have School time in Family Link already).
        A day already at those hours isn't written. Recorded as Hearth's own calls."""
        child = self.child(person)
        switch = fl.school_time_switch(self.hass, child) if child else None
        if child is None or switch is None:
            raise HomeAssistantError(f"No Family Link School time for {self.household.person_name(person)}")
        today = dt_util.now().date()
        done: dict[str, str] = {}
        same: list[str] = []
        failed: dict[str, str] = {}
        for iso, (start, end) in sorted(hours.items()):
            name = WEEKDAY_KEYS[iso - 1]
            day = today + timedelta(days=(iso - today.isoweekday()) % 7)
            if self.weekly(person, child, day) == (start, end):
                same.append(name)
                continue
            try:
                await call_service(
                    self.hass,
                    "familylink",
                    "set_school_time",
                    {"entity_id": switch, "day": str(iso), "start_time": hhmm(start), "end_time": hhmm(end)},
                    blocking=True,
                    person=person,
                    why="school_hours",
                )
            except Exception as err:  # noqa: BLE001 - one day's failure mustn't stop the others
                failed[name] = (str(err) or type(err).__name__)[:200]
                continue
            done[name] = f"{hhmm(start)}-{hhmm(end)}"
            self.written_hours.setdefault(person, {})[iso] = (start, end, dt_util.utcnow())
        return {"set": done, "same": same, "failed": failed}

    def switch_on_from(self, person: str, day: date) -> str:
        """Family Link School time is switched on from [day]: on a school day, inside the kid's window, then pinned
        (switch.turn_on alone opens a window until 23:59). Says "already" when it's on and nothing waits."""
        child = self.child(person)
        switch = fl.school_time_switch(self.hass, child) if child else None
        if child is None or switch is None:
            raise HomeAssistantError(f"No Family Link School time for {self.household.person_name(person)}")
        state = self.hass.states.get(switch)
        if state is not None and state.state == "on" and not any(
            o.person == person and o.applied for o in self.offs.values()
        ):
            self.turn_on.pop(person, None)
            self._save()
            return "already"
        self.turn_on[person] = day.isoformat()
        self._save()
        return day.isoformat()

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
                problems.append(f"{self.household.person_name(person)}'s limit for today's budget didn't apply")
        # With the backstop on, Family Link follows Hearth's time left (backstop.py): nothing of its own to check
        if config.follow_family_link and not self.household.backstop.enabled():
            for person in people:
                child = self.child(person)
                # Waiting for Hearth's own hold of the devices to be let go is no failure
                if (
                    child is not None
                    and self._family_link_target(person, child, today) is not None
                    and not self.household.enforcement.family_link_devices_held(person)
                ):
                    name = self.household.person_name(person)
                    problems.append(f"{name}'s limit couldn't be raised to today's budget")
        fs_problems: list[str] = []
        for person in self.family_safety_people(config.people):
            enforcer = self.family_safety_enforcer(person)
            if enforcer is None or not self._fs_limit_wanted(enforcer, config):
                continue
            target = self._fs_target(enforcer, today)
            if target is None:
                continue
            missing = [
                p
                for p in enforcer.platforms
                if p in FS_LIMIT_PLATFORMS
                and not self._marked(person, f"fs_raised:{p}@{target}")
                and not self._marked("", f"fs_back:{self._fs_key(enforcer.entity_id, p)}")
            ]
            if missing:
                fs_problems.append(
                    f"{self.household.person_name(person)}'s {' and '.join(missing)} limit couldn't be raised to "
                    "today's budget"
                )
        sw_problems: list[str] = []
        switches = self.nintendo_switches(config.people) if config.follow_nintendo else {}
        for entity_id, owners in switches.items():
            target = self._switch_target(entity_id, owners, today)
            if target is None or self._marked("", f"sw_raised:{entity_id}@{target}"):
                continue
            if self._marked("", f"sw_back:{entity_id}"):
                continue
            names = " and ".join(self.household.person_name(p) for p in owners)
            sw_problems.append(f"{names}'s Switch limit couldn't be raised to today's budget")
        if problems or fs_problems or sw_problems:
            apps = (("Family Link", problems), ("Family Safety", fs_problems), ("the Nintendo app", sw_problems))
            where = " and ".join(name for name, found in apps if found)
            message = ". ".join(problems + fs_problems + sw_problems) + f". Check {where}."
            self.tell("Today's schedule", message, "hearth_schedule_check")

    def _watchdog(self, people: list[str], today: date) -> None:
        off: list[str] = []
        off_people: list[str] = []
        for person in people:
            if any(o.person == person and o.day == today for o in self.offs.values()):
                continue  # taken off for today on purpose
            child = self.child(person)
            switch = fl.school_time_switch(self.hass, child) if child else None
            state = self.hass.states.get(switch) if switch else None
            if state is not None and state.state == "off":
                off.append(self.household.person_name(person))
                off_people.append(person)
        if off:
            self.tell(
                "School time is off on a school day",
                f"Family Link School time is still off for {', '.join(off)}. Check Family Link.",
                "hearth_school_time_watchdog",
                off_people,
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
        hold up the other, or another kid). A Family Safety with sync_site_list does it itself; one without (the
        released one) is kept in step by Hearth (fs_site_list.py), the list downloaded once for everyone; one with
        neither is skipped quietly."""
        sites = SiteListConfig.from_options(self.household.options)
        if not sites.url or now.time() < sites.at:
            return
        listed: dict[str, Any] = {}
        for person in self.site_list_people(sites.people):
            fl_entity = self.family_link_entity(person)
            if fl_entity is not None:
                await self._sync_sites(person, "family_link", "familylink", {"entity_id": fl_entity, "url": sites.url})
            fs_entity = self.family_safety_entity(person)
            if fs_entity is None:
                continue
            target = {"entity_id": fs_entity} if "." in fs_entity else {"account_id": fs_entity}
            if self.hass.services.has_service(FS_DOMAIN, "sync_site_list"):
                await self._sync_sites(person, "family_safety", FS_DOMAIN, {**target, "url": sites.url})
            elif fs_site_list.available(self.hass):
                await self._sync_sites(
                    person,
                    "family_safety",
                    FS_DOMAIN,
                    target,
                    own=lambda t=target, p=person: self._fs_own_sync(t, sites.url, listed, p),
                )

    async def _fs_own_sync(
        self, target: dict[str, str], url: str, listed: dict[str, Any], person: str = ""
    ) -> dict[str, Any]:
        """Hearth's own sync of the list into one kid's Family Safety (fs_site_list.py); the list is downloaded once
        per run ([listed] keeps it, or the download's failure, for the next kid). The kid's hand-blocked sites
        (hearth.block_site) are never taken back by it."""
        if "domains" not in listed:
            try:
                listed["domains"] = fs_site_list.parse(await fs_site_list.fetch(self.hass, url))
            except fs_site_list.SiteListError as err:
                listed["domains"] = err
        if isinstance(listed["domains"], Exception):
            raise listed["domains"]
        entity = target.get("entity_id") or target.get("account_id") or ""
        account = fs_account_of(self.hass, entity) or entity
        keep = self.site_blocks.domains(person, FAMILY_SAFETY)
        return await self.fs_sites.sync(target, account, url, listed["domains"], keep=keep)

    async def _sync_sites(
        self, person: str, via: str, domain: str, data: dict[str, Any], own=None
    ) -> None:
        """One side's sync for one person: marked done for the day, or tried again after RETRY (told once). [own]: Hearth
        does the sync itself (Family Safety without sync_site_list); sites that failed are told per site, and tried
        again the next day, unless every one failed (tried again after RETRY, as a failed call is)."""
        # Family Link's marks keep their older names (a restart mid-day doesn't sync twice)
        mark = "sites" if via == "family_link" else f"sites_{via}"
        if self._marked(person, mark):
            return
        key = f"{person}|{mark}"
        if self._waiting(key):
            return
        result: dict[str, Any] | None = None
        target = {k: v for k, v in data.items() if k != "url"}
        try:
            # One at a time with hearth.block_site / unblock_site (site_blocks.py)
            async with self.site_blocks.lock:
                if own is not None:
                    result = await own()
                    failed = result.get("failed") or []
                    if failed and len(failed) >= result.get("attempted", 0):
                        raise HomeAssistantError(
                            "every site failed: " + "; ".join(f"{f['site']} ({f['error']})" for f in failed[:5])
                        )
                else:
                    # The provider's own sync takes out what its list dropped, hand-blocked or not: what it took out
                    # of a hand block is blocked again right after (also when it failed part-way: the next try's
                    # read no longer shows it as the list's)
                    at_risk = await self.site_blocks.at_risk(person, via, target)
                    try:
                        await call_service(self.hass, domain, "sync_site_list", data, blocking=True)
                    finally:
                        await self.site_blocks.restore(person, via, target, at_risk)
        except Exception as err:  # noqa: BLE001 - one child's list failing mustn't stop the others
            _LOGGER.warning("Hearth couldn't sync the website list for %s through %s: %s", person, via, err)
            self._failed[key] = dt_util.utcnow()
            # Tried again later today; told once
            if not self._marked(person, f"{mark}_failed"):
                self._mark(person, f"{mark}_failed")
                extra = {"failed": result["failed"]} if result and result.get("failed") else {}
                self._event("site_list_failed", person, via=via, error=str(err)[:200], **extra)
            return
        self._mark(person, mark)
        if result is None:
            self._event("site_list", person, via=via)
            return
        if result["failed"]:
            _LOGGER.warning(
                "Hearth couldn't change %d site(s) of the website list for %s in Family Safety: %s",
                len(result["failed"]),
                person,
                ", ".join(f"{f['site']} ({f['error']})" for f in result["failed"][:10]),
            )
        self._event(
            "site_list",
            person,
            via=via,
            by="hearth",
            added=len(result["added"]),
            removed=len(result["removed"]),
            kept=result["kept"],
            skipped_allowed=len(result["skipped_allowed"]),
            failed=result["failed"],
        )

    # Telling

    def _event(self, action: str, person: str, **data: Any) -> None:
        self.hass.bus.async_fire(EVENT_SCHEDULE, {"action": action, "person": person, **data})

    def tell(self, title: str, message: str, notification_id: str, people: list[str] | None = None) -> None:
        """The adults: a notification in Home Assistant, and on the schedule's phone (else the one that answers
        requests for more time), tagged with the notification's id; about [people] when given."""
        from .attention import SCHEDULE_PHONE, Item

        about = {"people": list(people)} if people else {}
        self.household.hub.attention.notify(
            Item(notification_id, message, title=title, audience=SCHEDULE_PHONE, bell=True, about=about)
        )
