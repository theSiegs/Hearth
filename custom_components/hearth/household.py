"""People, their screen time today, and their limits: from what the household's devices post and the screen time
sources it adds.

The people are Home Assistant persons the household maps to (options): each TV profile, each phone, each source. A
person's day is counted from the devices and sources (counting.py), live play is timed and "together" seen (live.py),
time is set against the budgets of each group (limits.py), and what each device is told (its state document) comes
from here.
"""

from __future__ import annotations

import logging
import math

from dataclasses import dataclass, field
from datetime import date, datetime, time, timedelta
import hashlib
import secrets
import json
from typing import TYPE_CHECKING, Any

from homeassistant.core import CoreState, HomeAssistant, callback
from homeassistant.helpers.storage import Store
from homeassistant.helpers import entity_registry as er
from homeassistant.helpers.dispatcher import async_dispatcher_send
from homeassistant.util import dt as dt_util

from .entry_tasks import entry_task
from .attention import CHOSEN_PHONE, Action, Item
from .const import (
    CAP_NOTICES,
    CONF_KIND,
    CONF_LOCKS,
    CONF_MEDIA_PLAYERS,
    CONF_PERSON,
    CONF_PROFILES,
    CONF_ROLES,
    CONTRACT,
    DOMAIN,
    EVENT_BUDGET_REACHED,
    EVENT_PLAYING_TOGETHER,
    KIND_TV,
    SIGNAL_PEOPLE,
)
from .apps import (
    CONF_APP_WATCH,
    EVENT_NEW_APP,
    AppCatalog,
    observed_from_entities,
    phone_actions,
    update_notification,
)
from .counting import ALL, DeviceUsage, Reading, group_seconds, merge, minus, without
from .categories import CategoryBook
from .client import exempt_packages
from .limits import (
    CONF_APP_GROUPS,
    CONF_CATEGORY_POOLS,
    ACCESSIBILITY,
    OTHER,
    INTERFACE,
    OTHER_DAY,
    SCHOOL_DAY,
    Group,
    GroupState,
    Limits,
    Placement,
    groups_from_options,
    never_counted_group,
    never_held_group,
    placer,
    pool_map,
    without_app,
)
from .enforce import (
    FAMILY_LINK,
    FAMILY_SAFETY,
    NINTENDO,
    SYSTEM_NEVER_PAUSED,
    Enforcement,
    enforcers_from_options,
    fs_account_of,
    fs_app,
    fs_app_platform,
)
from .app_blocks import AppBlocks
from .exceptions import Allows, Lifted, end_of_day
from .history import BONUS, DEVICE_BONUS, RAISE, History
from .time_model import (
    Raise,
    account,
    category_text,
    limit_text,
    origin_text,
    say_clock,
    say_minutes,
    split_bonus,
    today_text,
)
from .grants import Grants
from .device_extra import ALLOW as EXTRA_ALLOW, BONUS as EXTRA_BONUS, DeviceExtra, DeviceExtras
from .native_sync import NativeSync
from .backstop import Backstop
from .unlimited import Unlimited
from .activity import ActivityLog
from .bedtime_lift import BedtimeLifts, in_family_link_bedtime, lift_minutes
from . import family_link as fl
from .todos import ChoreBook
from .schedule import Scheduler
from .weekly import EVENT_MODE, Now, Week, mode_closed, mode_lock
from .watch import WatchLog
from .pause import PAUSE, SCHEDULE, app_pauses_of, end_pause, lock_kinds, lock_until, next_lock, pause_ends_on, pause_of
from .places import Places, happened, matches
from . import parent_pin
from .media import media_rooms
from .phones import person_phones
from .profiles import REF_PREFIX, is_ref, split_tv_key, tv_key
from .schooldays import SchoolDays
from .live import LiveTracker, Observation, Together
from .nintendo import playing_entities, playing_title, switch_console, switch_name
from .sources import (
    Source,
    Title,
    device_key,
    fs_applications_of,
    now_playing,
    phone_app_playing,
    screen_entity,
    sources_from_options,
    title_key,
    titles_from_options,
    totals_reading,
)

_LOGGER = logging.getLogger(__name__)

if TYPE_CHECKING:
    from .hub import HearthHub

SOURCE_HEARTH = "hearth"
# Where an app lands when the household or what it is (categories.py) put it in a pool (limits.Placement.why): a
# client's own packages placed so are never kept from pausing (client_exempt)
POOLED_BY_HOUSEHOLD_OR_CATEGORY = ("moved", "list", "starter", "category", "suggested")
# What a kid on their Switch plays when Nintendo's integration doesn't say the game
SWITCH_ITEM = "Switch"


@dataclass
class Playing:
    app: str | None
    package: str | None
    device: str
    state: str | None
    # The device as a target id (targets.py): hearth:<id>, fl:<id>, nintendo:<entity> or source:<id>
    target: str | None = None
    # The most specific thing on, when known: an episode's, a video's or a movie's title, a track, a game (a Switch's,
    # a live source's); else None and the app is what's on
    title: str | None = None
    # A show's episode as "s2e4" (or "e4"), when its media player says
    episode: str | None = None
    # When this play started (ISO, UTC; live.py)
    since: str | None = None
    # video (a show, video or movie from a media player or the device's media session), music (a track), game (a
    # Switch's or a live source's title; the household summary makes an app in the Games group a game) or app
    kind: str | None = None
    # A show's name (the episode's series); a track's artist
    series: str | None = None
    artist: str | None = None
    # Its length and where it is, when the player says: seconds, the position as of [position_at]; paused freezes it
    duration_s: float | None = None
    position_s: float | None = None
    position_at: datetime | None = None
    paused: bool = False
    # What it counts and is timed under (live.py's item, a title key or the app), its live source when timed there,
    # and its name as the history's `played` events have it
    key: str | None = None
    source: str | None = None
    label: str | None = None

    def view(self) -> dict[str, Any]:
        return {
            "kind": self.kind,
            "app": self.app,
            "package": self.package,
            "title": self.title,
            "series": self.series,
            "artist": self.artist,
            "episode": self.episode,
            "device": self.device,
            "state": self.state,
            "target": self.target,
            "since": self.since,
        }


@dataclass
class PersonDay:
    person: str
    devices: dict[str, DeviceUsage] = field(default_factory=dict)
    groups: dict[str, float] = field(default_factory=dict)  # seconds
    limits: dict[str, GroupState] = field(default_factory=dict)
    playing: list[Playing] = field(default_factory=list)
    together_s: float = 0.0
    # Today's seconds per group before unlimited windows were left out (unlimited.py)
    raw_groups: dict[str, float] = field(default_factory=dict)
    # A lock entity of theirs is on (Family Link's bedtime or school time, say)
    locked: bool = False
    locked_by: list[str] = field(default_factory=list)

    @property
    def total_s(self) -> float:
        return self.groups.get(ALL, 0.0)


# Right after Home Assistant starts (or Hearth loads), the parental-control sources load one by one: for a few seconds
# today's count is short and a kid who was out of time looks as if they had some. A limit reached today stays held
# until the sources have settled this long after Home Assistant is running
STARTUP_SETTLE = timedelta(seconds=90)


def _keep_held(state: GroupState) -> None:
    """A group reached before a restart stays at 0 left while the sources settle."""
    if state.modeled:
        state.held_left = 0
        state.usable = 0
    elif state.budget_min is not None:
        state.counted_min = max(state.counted_min, state.budget_min + state.bonus_min)


# A totals source correcting itself down by this much is taken as it is; a bigger drop (its own day ending at
# another hour, a cloud hiccup reporting 0) never lowers today's count
TOTALS_CORRECTION_S = 5 * 60


def _higher(kept: Reading, new: Reading) -> Reading:
    """A totals source's reading today, never much lower than it was: a small correction down is taken as it is, a
    bigger drop keeps the higher total and each app's higher seconds."""
    if new.total_s >= kept.total_s - TOTALS_CORRECTION_S:
        return new
    items = dict(kept.items)
    for key, seconds in new.items.items():
        items[key] = max(items.get(key, 0.0), seconds)
    return Reading(new.source, max(kept.total_s, new.total_s), items, new.rest_group)


class Household:
    def __init__(self, hass: HomeAssistant, hub: HearthHub) -> None:
        self.hass = hass
        self.hub = hub
        # When the sources count as settled after a start (STARTUP_SETTLE); None until Home Assistant is running. A
        # reload (a setting changed) finds them loaded: nothing to wait for
        self._settle_until: datetime | None = dt_util.utcnow() if hass.state is CoreState.running else None
        self.limits = Limits(hass, hub.entry.entry_id)
        self.live = LiveTracker(hass, hub.entry.entry_id)
        self.apps = AppCatalog(hass, hub.entry.entry_id)
        # What each app is, by its keys on every platform: the owner's overrides, Hearth's starter list, and store and
        # AI answers looked up when a kid first uses an app (categories.py)
        self.categories_book = CategoryBook(hass, hub.entry.entry_id, dict(hub.entry.options))
        self.school = SchoolDays(hass)
        self.school.configure(dict(hub.entry.options))
        self.enforcement = Enforcement(hass, hub.entry.entry_id)
        # Hearth's own blocks of Android apps, through Family Link (app_blocks.py)
        self.blocks = AppBlocks(hass, self, hub.entry.entry_id)
        self.watch = WatchLog(hass, hub.entry.entry_id)
        self.allows = Allows(hass, hub.entry.entry_id)
        self.grants = Grants(hass, hub.entry.entry_id)
        self.device_extras = DeviceExtras(hass, hub.entry.entry_id)
        self.history = History(hass, hub.entry.entry_id)
        self.sync = NativeSync(hass, self, hub.entry.entry_id)
        # Family Link's daily limit kept as a backstop above Hearth's own numbers (backstop.py)
        self.backstop = Backstop(hass, self, hub.entry.entry_id)
        self.enforcement.backstop_values = self.backstop.written_minutes
        # Unlimited windows: time used then isn't counted (unlimited.py)
        self.unlimited = Unlimited(hass, self, hub.entry.entry_id)
        # The action log: every outbound call, hold, TV command and Glint inbox write (activity.py)
        self.activity = ActivityLog(hass, self, hub.entry.entry_id)
        self.enforcement.activity = self.activity
        # An adult's extra time at bedtime lifts it while it lasts (bedtime_lift.py)
        self.bedtime_lift = BedtimeLifts(hass, self, hub.entry.entry_id)
        self.scheduler = Scheduler(hass, self, hub.entry.entry_id)
        # The weekly schedule (weekly.py): each kid's modes and limits per day
        self.week = Week(hass, hub.entry.entry_id, lambda: self.limits.data.budgets, lambda: self.options)
        self.week.type_of = self.day_type_on
        self.limits.week = self.week
        # Each person's schedule now (weekly.Now, None without one), as of the last recompute; the mode last told
        # (hearth_mode fires when it changes)
        self.schedule_now: dict[str, Now | None] = {}
        self._modes_told: dict[str, str] = {}
        self.todos = ChoreBook(hass, self, hub.entry.entry_id)
        # Chore minutes earned today count as bonus (todos.py)
        self.limits.chore_minutes = self.todos.minutes_today
        self.places = Places(hass, self)
        self.days: dict[str, PersonDay] = {}
        # What the time model said last per person (debug logs only a change)
        self._model_logged: dict[str, tuple] = {}
        # The day [days] is of
        self.today: date | None = None
        # Each totals source's highest reading today (each app's, and the total): it counts while the sensor has no
        # number (unavailable), and a lower one (a cloud hiccup, the source's own day ending at another hour) never
        # lowers today's count. Kept across a restart (a source still unavailable then loses nothing)
        self._last_totals: dict[str, tuple[date, Reading]] = {}
        self._totals_store: Store[dict[str, Any]] = Store(hass, 1, f"hearth.totals.{hub.entry.entry_id}")
        self.groups: list[Group] = []
        self.sources: list[Source] = []
        self.titles: list[Title] = []
        self.categories: dict[str, str] = {}
        # Groups an item is in because of where its time came from (a Switch's titles are games)
        self._hints: dict[str, set[str]] = {}
        # known_apps() for one document build: every builder makes one membership() and hands it to each
        # _group_apps() call, so the walk over devices, sources and every sensor runs once per build, not per group
        self._known_for: tuple[Any, dict[str, str]] | None = None
        # never_held() for one membership(), the same way
        self._never_held_for: tuple[Any, frozenset[str]] | None = None

    async def async_load(self) -> None:
        stored = await self._totals_store.async_load() or {}
        for source_id, kept in stored.items():
            try:
                self._last_totals[source_id] = (
                    date.fromisoformat(kept["day"]),
                    Reading(
                        kept["source"], float(kept["total_s"]), {k: float(v) for k, v in (kept.get("items") or {}).items()},
                        kept.get("rest_group"),
                    ),
                )
            except (KeyError, TypeError, ValueError):
                continue
        await self.limits.async_load()
        await self.live.async_load()
        await self.apps.async_load()
        await self.categories_book.async_load()
        await self.enforcement.async_load()
        await self.blocks.async_load()
        await self.watch.async_load()
        await self.allows.async_load()
        await self.grants.async_load()
        await self.device_extras.async_load()
        await self.history.async_load()
        await self.sync.async_load()
        await self.backstop.async_load()
        await self.unlimited.async_load()
        await self.activity.async_load()
        # Once: today's bonus time, category bonuses, raised limits and a running Unlimited become grants
        running = {p: w for p in list(self.unlimited.windows) if (w := self.unlimited.active(p)) is not None}
        self.limits.migrate_grants(running, self.latest_origin)
        await self.bedtime_lift.async_load()
        await self.scheduler.async_load()
        await self.week.async_load()
        await self.todos.async_load()

    def _totals_data(self) -> dict[str, Any]:
        return {
            source_id: {
                "day": day.isoformat(), "source": reading.source, "total_s": reading.total_s,
                "items": dict(reading.items), "rest_group": reading.rest_group,
            }
            for source_id, (day, reading) in self._last_totals.items()
        }

    async def async_flush(self) -> None:
        await self._totals_store.async_save(self._totals_data())
        await self.limits.async_flush()
        await self.categories_book.async_flush()
        await self.live.async_flush()
        await self.enforcement.async_flush()
        await self.blocks.async_flush()
        await self.watch.async_flush()
        await self.allows.async_flush()
        await self.grants.async_flush()
        await self.device_extras.async_flush()
        await self.history.async_flush()
        await self.sync.async_flush()
        await self.backstop.async_flush()
        await self.unlimited.async_flush()
        await self.activity.async_flush()
        await self.bedtime_lift.async_flush()
        await self.scheduler.async_flush()
        await self.week.async_flush()
        await self.todos.async_flush()

    # The mapping

    @property
    def options(self) -> dict[str, Any]:
        return dict(self.hub.entry.options)

    def profile_people(self) -> dict[str, str]:
        return dict(self.options.get(CONF_PROFILES, {}))

    def tv_profiles(self, device_id: str) -> dict[str, dict[str, str | None]]:
        """The profiles a TV has reported, by its own keys ("user:10"): {"name", "ref"}. A TV too old to send refs
        has none (its profiles are mapped by TV key only)."""
        status = self.hub.state(device_id).status or {}
        out: dict[str, dict[str, str | None]] = {}
        for key, entry in (status.get("profiles") or {}).items():
            out[key] = {"name": entry.get("name"), "ref": entry.get("ref")}
        for key, usage in (status.get("usage_today") or {}).items():
            entry = out.setdefault(key, {"name": None, "ref": None})
            entry["name"] = entry["name"] or usage.get("profile_name")
            entry["ref"] = entry["ref"] or usage.get("profile_ref")
        if key := status.get("profile_id"):
            entry = out.setdefault(key, {"name": None, "ref": None})
            entry["name"] = status.get("profile") or entry["name"]
            entry["ref"] = status.get("profile_ref") or entry["ref"]
        return out

    def _mapped(self, device_id: str, profile_id: str, known: dict[str, dict[str, str | None]]) -> str | None:
        """The person one profile of this TV is mapped to: by its household ref first, else by this TV's key."""
        profiles = self.profile_people()
        ref = (known.get(profile_id) or {}).get("ref")
        if ref and profiles.get(ref):
            return profiles[ref]
        return profiles.get(tv_key(device_id, profile_id)) or None

    def profile_person(self, device_id: str, profile_id: str | None) -> str | None:
        """The person a TV's profile is mapped to. Never by the bare key: its serial is this TV's own. Hearth keeps a
        kids profile's log under its user ("user:10"), which matches a mapping of the same user with its account
        ("user:10:sam") when there is only one."""
        if not profile_id:
            return None
        known = self.tv_profiles(device_id)
        if person := self._mapped(device_id, profile_id, known):
            return person
        prefix = f"{profile_id}:"
        own = tv_key(device_id, prefix)
        found = {self._mapped(device_id, key, known) for key in known if key.startswith(prefix)}
        found |= {person for key, person in self.profile_people().items() if person and key.startswith(own)}
        found.discard(None)
        return found.pop() if len(found) == 1 else None

    def google_tv_limits(self, person: str) -> list[str]:
        """The connected TVs where Google TV's own Kids daily limit holds this person's profile now (its time up screen,
        google_time_up). Hearth can't lift it: only raising or turning off the limit in Google TV does."""
        found = []
        for device_id, device in sorted(self.hub.devices.items()):
            status = self.hub.state(device_id).status or {}
            if (
                device.get(CONF_KIND) == KIND_TV
                and status.get("google_time_up")
                and self.hub.connected(device_id)
                and self.profile_person(device_id, status.get("profile_id")) == person
            ):
                found.append(device_id)
        return found

    def device_profile_people(self, device_id: str) -> dict[str, str]:
        """This TV's profiles, by its own keys, and whose each is (the mapped ones only)."""
        keys = set(self.tv_profiles(device_id))
        keys |= {split[1] for key in self.profile_people() if (split := split_tv_key(key)) and split[0] == device_id}
        return {key: person for key in sorted(keys) if (person := self.profile_person(device_id, key))}

    def youtube_people(self) -> list[str]:
        """The people with a TV profile: whose videos started can come up, and who can have YouTube blocks."""
        return sorted({p for p in self.profile_people().values() if p})

    def device_person(self, device_id: str) -> str | None:
        return self.hub.devices.get(device_id, {}).get(CONF_PERSON)

    def people(self) -> list[str]:
        """Everyone the household maps something to, in a stable order."""
        found = {p for p in self.profile_people().values() if p}
        found |= {d.get(CONF_PERSON) for d in self.hub.devices.values() if d.get(CONF_PERSON)}
        found |= {s.person for s in sources_from_options(self.options)}
        found |= {lock["person"] for lock in self.options.get(CONF_LOCKS, []) if lock.get("person")}
        # The kids named on Hearth's page, before anything of theirs is set up
        found |= {p for p, role in self.options.get(CONF_ROLES, {}).items() if role == "kid"}
        return sorted(found)

    def person_name(self, person: str) -> str:
        state = self.hass.states.get(person)
        return state.name if state else person.split(".", 1)[-1].replace("_", " ").title()

    def source_entities(self) -> list[str]:
        """Entities whose changes count: the screen time sources and the locks."""
        locks = [lock["entity_id"] for lock in self.options.get(CONF_LOCKS, [])]
        watched = list(self.options.get(CONF_APP_WATCH, []))
        # Who's playing a shared Switch: a change holds or lets it go
        enforcers = enforcers_from_options(self.options)
        playing = [
            e for enforcer in enforcers if enforcer.kind == NINTENDO
            for e in playing_entities(self.hass, enforcer, enforcers)
        ]
        sources = sources_from_options(self.options)
        # A phone app source is playing only while its screen is on
        screens = [found for s in sources if s.phone_app and (found := screen_entity(self.hass, s))]
        # A Family Safety Screen Time's breakdown is its child's Applications sensor's
        applications = [
            found[0] for s in sources if not s.live and (found := fs_applications_of(self.hass, s.entity_id))
        ]
        return (
            [s.entity_id for s in sources]
            + applications
            + locks
            + watched
            + playing
            + screens
            + self.school.watched_entities()
            + self._school_time_sensors()
        )

    def _school_time_sensors(self) -> list[str]:
        """The School time sensors of the children whose School-time apps are paused (else the minute's recompute
        would see School time start a minute late)."""
        children = {
            child
            for e in enforcers_from_options(self.options)
            if e.kind == FAMILY_LINK and e.school_apps and (child := fl.child_of(self.hass, e.entity_id))
        }
        return [s.entity_id for child in children for s in fl.school_time_sensors(self.hass, child)]

    def _locked_by(self, person: str) -> list[str]:
        return [
            lock["entity_id"]
            for lock in self.options.get(CONF_LOCKS, [])
            if lock.get("person") == person
            and (state := self.hass.states.get(lock["entity_id"])) is not None
            and state.state == "on"
        ]

    def _locks_now(self, person: str, now: datetime | None = None) -> list[str]:
        """What locks the person now: their lock entities that are on, a family pause (PAUSE), the schedule's Sleep
        or School (SCHEDULE). While extra time lifts their bedtime (bedtime_lift.py), its bedtime locks don't."""
        locked_by = self._locked_by(person)
        # A family pause holds them as a lock does
        if pause_of(self.hass, person, now):
            locked_by.append(PAUSE)
        # The schedule's Sleep and School are locks
        if self.schedule_lock(person) is not None:
            locked_by.append(SCHEDULE)
        if self.bedtime_lift.until(person, now) is None:
            return locked_by
        kind = self.schedule_lock(person)
        return [e for e in locked_by if e == PAUSE or lock_kinds(self.hass, [e], kind) != ["bedtime"]]

    def in_bedtime(self, person: str) -> bool:
        """The person is in bedtime now, lifted or not: the schedule's Sleep, a lock entity of theirs that's a bedtime
        (Family Link's, Family Safety's downtime), or Family Link's own bedtime on one of their devices."""
        if self.schedule_lock(person) == "bedtime" or "bedtime" in lock_kinds(self.hass, self._locked_by(person)):
            return True
        child = self.family_link_child(person)
        return child is not None and in_family_link_bedtime(self.hass, child)

    def _lock_entities(self, person: str) -> list[str]:
        return [lock["entity_id"] for lock in self.options.get(CONF_LOCKS, []) if lock.get("person") == person]

    def bedtime_today(self, person: str, now: datetime | None = None) -> dict[str, str] | None:
        """Today's bedtime from the person's lock entities in Hearth's settings (those that say bedtime_start and
        bedtime_end, as Family Link's bedtime does): {start: tonight's, end: this morning's wake}, local ISO times on
        today's date. With more than one, the earliest start and the latest end; None when none says. A weekly
        schedule with a Sleep tonight says it instead: {start: tonight's bedtime, end: this morning's wake}."""
        local_now = dt_util.as_local(now or dt_util.now())
        if (scheduled := self._schedule_bedtime(person, local_now)) is not None:
            return scheduled
        return self._locks_bedtime(person, local_now)

    def _locks_bedtime(self, person: str, now: datetime | None = None) -> dict[str, str] | None:
        """bedtime_today from the lock entities only."""
        today = dt_util.as_local(now or dt_util.now()).date()
        starts: list[time] = []
        ends: list[time] = []
        for entity_id in self._lock_entities(person):
            state = self.hass.states.get(entity_id)
            if state is None:
                continue
            for key, into in (("bedtime_start", starts), ("bedtime_end", ends)):
                if (clock := _clock_of(state.attributes.get(key))) is not None:
                    into.append(clock)
        if not starts or not ends:
            return None
        zone = dt_util.get_default_time_zone()
        start = datetime.combine(today, min(starts), zone)
        end = datetime.combine(today, max(ends), zone)
        if end >= start:  # not a night: nothing to draw
            return None
        return {"start": start.isoformat(), "end": end.isoformat()}

    def _schedule_bedtime(self, person: str, now: datetime) -> dict[str, str] | None:
        """Tonight's bedtime and this morning's wake from the weekly schedule, when today ends in Sleep."""
        found = self.schedule_now.get(person)
        if found is None or found.day.date != now.date() or found.bedtime is None or not found.day.changes:
            return None
        first = found.day.changes[0][0]
        morning = datetime.combine(now.date(), time(first // 60, first % 60), found.bedtime.tzinfo)
        if morning >= found.bedtime:
            return None
        return {"start": found.bedtime.isoformat(), "end": morning.isoformat()}

    def schedule_lock(self, person: str) -> str | None:
        """bedtime or school_time while the person's weekly schedule is in Sleep or School (School time taken off
        today lifts School)."""
        found = self.schedule_now.get(person)
        if found is None:
            return None
        kind = mode_lock(self.week.data.modes, found.mode)
        if kind == "school_time" and self.scheduler.off_now(person) is not None:
            return None
        return kind

    def schedule_closed(self, person: str) -> list[str]:
        """The groups the person's mode closes now (Homework, Wind down), those the household has."""
        found = self.schedule_now.get(person)
        if found is None:
            return []
        ids = {g.id for g in self.groups if g.id != ALL}
        return [g for g in mode_closed(self.week.data.modes, found.mode) if g in ids]

    def schedule_holds(self, person: str) -> set[str]:
        """What the schedule closes now for the other parental controls: the mode's groups, and All screen time in
        Sleep and School (Family Safety's platforms and the Switch are held then; Family Link keeps its own bedtime and
        School time in phase 1)."""
        found = set(self.schedule_closed(person))
        lock = self.schedule_lock(person)
        # Extra time at bedtime lifts Sleep's hold while it lasts (bedtime_lift.py)
        if lock is not None and not (lock == "bedtime" and self.bedtime_lift.until(person) is not None):
            found.add(ALL)
        return found

    def week_people(self) -> list[str]:
        """The people with a weekly schedule of their own: the kids."""
        roles = self.options.get(CONF_ROLES, {})
        return sorted(p for p in self.people() if roles.get(p) == "kid")

    def mode_of(self, person: str) -> dict[str, Any]:
        """The person's mode now, for their mode sensor: {mode, name, since, until, next {at, mode}, today_changed,
        source}. From the weekly schedule; while it has no changes, from the lock entities (sleep in a bedtime,
        school in School time, else free)."""
        found = self.schedule_now.get(person)
        modes = self.week.data.modes
        if found is not None:
            return {
                "mode": found.mode,
                "name": (modes.get(found.mode) or {}).get("name", found.mode),
                "since": dt_util.as_local(found.since).isoformat() if found.since else None,
                "until": dt_util.as_local(found.until).isoformat() if found.until else None,
                "next": {"at": dt_util.as_local(found.next.at).isoformat(), "mode": found.next.mode} if found.next else None,
                "today_changed": found.day.changed_today,
                "source": "schedule",
            }
        day = self.days.get(person)
        kinds = lock_kinds(self.hass, [e for e in (day.locked_by if day else []) if e != PAUSE])
        mode = "sleep" if "bedtime" in kinds else "school" if "school_time" in kinds else "free"
        return {
            "mode": mode,
            "name": (modes.get(mode) or {}).get("name", mode),
            "since": None,
            "until": None,
            "next": None,
            "today_changed": False,
            "source": "locks",
        }

    def bedtime_tonight(self, person: str) -> dict[str, Any] | None:
        """Tonight's bedtime: {at, wake, source}: the weekly schedule's Sleep, else the lock entities' bedtime."""
        found = self.schedule_now.get(person)
        if found is not None and found.bedtime is not None:
            return {
                "at": dt_util.as_local(found.bedtime).isoformat(),
                "wake": dt_util.as_local(found.wake).isoformat() if found.wake else None,
                "source": "schedule",
            }
        locks = self._locks_bedtime(person)
        if locks is None:
            return None
        wake = dt_util.parse_datetime(locks["end"])
        return {
            "at": locks["start"],
            "wake": (wake + timedelta(days=1)).isoformat() if wake else None,
            "source": "locks",
        }

    def schedule_view(self, person: str) -> dict[str, Any] | None:
        """The person's schedule now, as the household summary and the state document carry it: the mode, the next
        change, tonight's bedtime and the day used. None while their schedule has no changes."""
        found = self.schedule_now.get(person)
        if found is None:
            return None
        modes = self.week.data.modes
        mode = modes.get(found.mode) or {}

        def iso(value: datetime | None) -> str | None:
            return dt_util.as_local(value).isoformat() if value else None

        return {
            "mode": {
                "id": found.mode,
                "name": mode.get("name", found.mode),
                "allows": mode.get("allows"),
                "since": iso(found.since),
                "until": iso(found.until),
                "closed": self.schedule_closed(person),
            },
            "next": (
                {"at": iso(found.next.at), "mode": found.next.mode, "name": (modes.get(found.next.mode) or {}).get("name")}
                if found.next
                else None
            ),
            "bedtime": {"at": iso(found.bedtime), "wake": iso(found.wake)} if found.bedtime else None,
            "day": {
                "date": found.day.date.isoformat(),
                "uses": found.day.uses,
                "changed_today": found.day.changed_today,
            },
        }

    def _locks_document(self, person: str, day: PersonDay | None) -> dict[str, Any]:
        """Why and until when the person is held ("lock" {by, until}), a family pause ("pause" {until, reason}), and
        the next bedtime or school time ("next_lock" {at, by, kind}), for winding down before it. The weekly
        schedule's Sleep and School are locks too (by "schedule"), and its next one is the next_lock when it comes
        before the lock entities'."""
        out: dict[str, Any] = {}
        pause = pause_of(self.hass, person)
        if pause:
            out["pause"] = pause
        # Extra time an adult gave at bedtime lifts it until then (bedtime_lift.py): {since, until}
        if (lifted := self.bedtime_lift.view(person)) is not None:
            out["bedtime_lifted"] = lifted
        scheduled = self.schedule_now.get(person)
        if day and day.locked:
            ends = [lock_until(self.hass, [e for e in day.locked_by if e not in (PAUSE, SCHEDULE)])]
            if pause:
                ends.append(dt_util.parse_datetime(pause["until"]))
            if SCHEDULE in day.locked_by and scheduled is not None:
                ends.append(scheduled.until)
            until = max((e for e in ends if e is not None), default=None)
            kinds = lock_kinds(self.hass, day.locked_by, self.schedule_lock(person))
            out["lock"] = {
                "by": list(day.locked_by),
                # bedtime, school_time, pause or other: the first of them (bedtime before school time before a pause)
                "kind": next((k for k in ("bedtime", "school_time", "pause", "other") if k in kinds), "other"),
                "kinds": kinds,
                "until": dt_util.as_local(until).isoformat() if until else None,
            }
        upcoming = next_lock(self.hass, self._lock_entities(person))
        if scheduled is not None and scheduled.next_lock is not None:
            at, kind = scheduled.next_lock
            if upcoming is None or at < dt_util.parse_datetime(upcoming["at"]):
                upcoming = {"at": dt_util.as_local(at).isoformat(), "by": SCHEDULE, "kind": kind}
        if upcoming:
            out["next_lock"] = upcoming
        return out

    def seen_profiles(self) -> dict[str, str]:
        """The TV profiles to map, for the options: option key -> how to show it. A profile a TV reports with its
        household ref is one choice for every TV ("Sam · Kitchen, Playroom"); one without (an older Hearth) is that TV's
        ("Sam on Playroom"). Keys already mapped are listed too, the old bare ones as needing a new pick."""
        tvs: dict[str, list[str]] = {}
        names: dict[str, str | None] = {}
        for device_id, device in self.hub.devices.items():
            if device.get(CONF_KIND) != KIND_TV:
                continue
            tv_name = device.get("name") or device_id
            for profile_id, entry in self.tv_profiles(device_id).items():
                key = entry["ref"] or tv_key(device_id, profile_id)
                names[key] = names.get(key) or entry["name"]
                tvs.setdefault(key, [])
                if tv_name not in tvs[key]:
                    tvs[key].append(tv_name)
        found: dict[str, str] = {}
        for key, on in tvs.items():
            name = names.get(key) or "Profile"
            found[key] = f"{name} · {', '.join(sorted(on))}" if is_ref(key) else f"{name} on {on[0]} (this TV only)"
        for key in self.profile_people():
            if key in found:
                continue
            if is_ref(key):
                found[key] = f"{key[len(REF_PREFIX):]} · no TV has reported it yet"
            elif split := split_tv_key(key):
                tv_name = self.hub.devices.get(split[0], {}).get("name") or "a TV no longer paired"
                found[key] = f"{split[1]} on {tv_name} (this TV only)"
            else:
                found[key] = f"Old mapping {key}: the same number is a different profile on each TV, pick again"
        return found

    def app_names(self, packages: set[str], person: str | None = None) -> dict[str, str]:
        """package -> the app's name, for the packages a name is known for: Hearth's app catalog, else the `apps` lists
        of the person's Family Link sensors (Apps with time limits, Daily screen time)."""
        found: dict[str, str] = {}
        for package in packages:
            entry = self.apps.apps.get(package)
            if entry is not None and entry.name and entry.name != package:
                found[package] = entry.name
        missing = packages - found.keys()
        child = self.family_link_child(person) if missing and person else None
        if child is None:
            return found
        for state in self.hass.states.async_all("sensor"):
            if not missing:
                break
            if str(state.attributes.get("child_id")) != str(child):
                continue
            for app in state.attributes.get("apps") or []:
                if not isinstance(app, dict) or app.get("package") not in missing:
                    continue
                if isinstance(name := app.get("name"), str) and name.strip() and name != app["package"]:
                    found[app["package"]] = name.strip()[:64]
                    missing.discard(app["package"])
        return found

    def known_apps(self) -> dict[str, str]:
        """Apps, played titles and titles seen: key -> how to show it, for the options' choices."""
        apps: dict[str, str] = {}
        for device_id in self.hub.devices:
            status = self.hub.state(device_id).status or {}
            for usage in (status.get("usage_today") or {}).values():
                for package in usage.get("apps", {}):
                    apps.setdefault(package, package)
            for package in status.get("app_seconds_today") or {}:
                apps.setdefault(package, package)
            if status.get("app_package"):
                apps[status["app_package"]] = status.get("app") or status["app_package"]
        for source in self.sources:
            state = self.hass.states.get(source.entity_id)
            for app in (state.attributes.get("apps") if state else None) or []:
                if isinstance(app, dict) and isinstance(app.get("package"), str):
                    apps.setdefault(app["package"], app.get("name") or app["package"])
        for by_item in self.live.seconds.values():
            for item in by_item:
                if not item.startswith("title:"):
                    apps.setdefault(item, item)
        # The Xbox and Windows apps of the kids with Family Safety (its Screen Time and Applications sensors)
        for package, name in self._family_safety_apps().items():
            apps.setdefault(package, name)
        # Every app the catalog has seen (a watched list, a device), with its name when one was given
        for entry in self.apps.apps.values():
            if apps.get(entry.package, entry.package) == entry.package:
                apps[entry.package] = entry.name or entry.package
        for title in self.titles:
            apps[f"title:{title.id}"] = f"{title.name} (title)"
        return apps

    def _family_safety_apps(self) -> dict[str, str]:
        """App id -> "name (platform)" from the `apps` attribute of the Family Safety sensors of the people with a
        Family Safety enforcer (their account's sensors), or the Applications sensor's `applications` ({app_id,
        app_name}) without one, for the app pickers; only ids pause_app takes."""
        enforcers = [e for e in enforcers_from_options(self.options) if e.kind == FAMILY_SAFETY]
        found: dict[str, str] = {}
        if not enforcers:
            return found
        accounts = {account for e in enforcers if (account := fs_account_of(self.hass, e.entity_id))}
        registry = er.async_get(self.hass)
        devices = {
            entry.device_id for e in enforcers if (entry := registry.async_get(e.entity_id)) and entry.device_id
        }
        for state in self.hass.states.async_all("sensor"):
            apps = state.attributes.get("apps")
            if not isinstance(apps, list):
                applications = state.attributes.get("applications")
                if not isinstance(applications, list):
                    continue
                apps = [
                    {"package": app.get("app_id"), "name": app.get("app_name")}
                    for app in applications[:500]
                    if isinstance(app, dict)
                ]
            # Theirs: by the account (Screen Time has user_id) or the account's device (Applications doesn't)
            if str(state.attributes.get("user_id")) not in accounts:
                entry = registry.async_get(state.entity_id)
                if entry is None or entry.device_id not in devices:
                    continue
            for app in apps[:500]:
                package = app.get("package") if isinstance(app, dict) else None
                if isinstance(package, str) and fs_app(package):
                    name = str(app.get("name") or package)[:128]
                    found.setdefault(package[:128], f"{name} ({fs_app_platform(package)})")
        return found

    # Counting

    def _today(self) -> date:
        return dt_util.now().date()

    def _key(self, item: str) -> str:
        return title_key(self.titles, item)

    def pools(self) -> dict[str, str]:
        """What each value an app is (categories.py, or the device's own) goes to in this household: a pool, or
        "other" (limits.pool_map)."""
        return pool_map(self.groups, self.options.get(CONF_CATEGORY_POOLS))

    def placement(self):
        """Where an item counts and why (limits.placer): an adult's move, the household's lists, Hearth's curated
        lists, a confirmed answer of what it is (categories.py), the device's own category, an unconfirmed answer,
        where its time came from (a Switch's: games), else Other; for a
        title its apps' (the first that has one)."""
        place = placer(
            self.groups,
            self.categories,
            self.options.get(CONF_APP_GROUPS, {}),
            lookup=self.categories_book.lookup,
            pools=self.pools(),
            hints=self._hints,
        )
        titles = {f"title:{t.id}": t for t in self.titles}

        def of(item: str) -> Placement:
            found = place(item)
            title = titles.get(item)
            if title is not None and found.pool is None and found.why not in ("moved", "category"):
                for raw in title.raw:
                    if (raw_found := place(raw)).pool is not None:
                        return raw_found
            return found

        return of

    def never_counted(self):
        """item -> whether it's in System screens (limits.INTERFACE): never anyone's screen time, in no group. Only an
        adult's move or list, Hearth's own list or a curated `interface` (an override, the starter list) puts an app there
        (limits.placer), so the devices' own categories aren't read."""
        group = self.group(INTERFACE)
        if group is None or not never_counted_group(group):
            return lambda item: False
        place = placer(
            self.groups,
            {},
            self.options.get(CONF_APP_GROUPS, {}),
            lookup=self.categories_book.lookup,
            pools=self.pools(),
        )
        return lambda item: place(item).pool == INTERFACE

    def _device_reading(self, device_id: str, status: dict[str, Any]) -> Reading:
        """A phone's or tablet's own count today. On the day it paired, only what came after: its first post after
        pairing is the baseline (hub.py), taken off its later posts that day."""
        reading = Reading(SOURCE_HEARTH, float(status.get("seconds_today") or 0), status.get("app_seconds_today") or {})
        base = self.hub.state(device_id).baseline
        if base and base.get("day") and base["day"] == status.get("day"):
            reading = minus(reading, float(base.get("seconds") or 0), base.get("apps") or {})
        return reading

    def membership(self):
        """An item's groups: All and at most one pool (placement)."""
        place = self.placement()

        def of(item: str) -> set[str]:
            pool = place(item).pool
            return {ALL, pool} if pool else {ALL}

        return of

    def _settling(self, now: datetime) -> bool:
        """Whether the sources may still be loading after a start: until Home Assistant runs, then STARTUP_SETTLE
        more (a recompute is due once it's over, so a reopened group opens on time)."""
        if self.hass.state is not CoreState.running:
            return True
        if self._settle_until is None:
            self._settle_until = dt_util.as_utc(now) + STARTUP_SETTLE
            if STARTUP_SETTLE > timedelta(0):
                from homeassistant.helpers.event import async_call_later

                self.hub.entry.async_on_unload(
                    async_call_later(
                        self.hass, STARTUP_SETTLE.total_seconds() + 1, callback(lambda _now: self.recompute())
                    )
                )
        return dt_util.as_utc(now) < self._settle_until

    @callback
    def recompute(self) -> None:
        self._known_for = None
        self._never_held_for = None
        self._group_packages_cache = None
        now = dt_util.now()
        # A TV's commands that waited too long are told as expired
        self.hub.commands.prune()
        today = now.date()
        new_day = self.limits.new_day(today)
        self.limits.prune_raises(now)
        # Home Assistant was down at midnight: yesterday's minutes are still in the devices' last statuses and the live
        # timings (kept across the restart), so they're recorded from those on the first look after it starts
        yesterday = (today - timedelta(days=1)).isoformat()
        backfill = self.today is None and self.live.day == yesterday
        back_readings: dict[str, dict[str, list[Reading]]] = {}
        back_live = self.live.seconds if backfill else {}
        options = self.options
        self.groups = groups_from_options(options)
        self.sources = sources_from_options(options)
        self.titles = titles_from_options(options)
        by_id = {s.id: s for s in self.sources}
        readings: dict[str, dict[str, list[Reading]]] = {}
        playing: dict[str, list[Playing]] = {}
        observations: list[Observation] = []
        categories: dict[str, str] = {}
        hints: dict[str, set[str]] = {}
        # Each Playing with its play's key in live.py, for when it started
        plays: list[tuple[Playing, tuple[str, str, str]]] = []

        def observe(entry: Playing, person: str, device: str, item: str, source: str | None, label: str | None) -> None:
            key = self._key(item)
            observations.append(Observation(person, device, key, source, self._label(key, label)))
            entry.key, entry.source, entry.label = key, source, self._label(key, label)
            playing.setdefault(person, []).append(entry)
            plays.append((entry, (person, device, key)))

        never_counted = self.never_counted()

        def add(
            person: str,
            device: str,
            reading: Reading,
            into: dict[str, dict[str, list[Reading]]] = readings,
            own_items: bool = False,
        ) -> None:
            # System screens count nowhere; a device's own total is then its kept apps' sum ([own_items])
            reading = without(reading, never_counted, own_items and bool(reading.items))
            items = {}
            for item, seconds in reading.items.items():
                key = self._key(item)
                items[key] = max(items.get(key, 0.0), seconds)
                if reading.rest_group:
                    hints.setdefault(key, set()).add(reading.rest_group)
            mapped = Reading(reading.source, reading.total_s, items, reading.rest_group)
            into.setdefault(person, {}).setdefault(device, []).append(mapped)

        # Hearth's own devices
        for device_id, device in self.hub.devices.items():
            status = self.hub.state(device_id).status
            if status is None:
                continue
            categories.update(status.get("app_categories") or {})
            name = device.get("name") or device_id
            # Yesterday's counts from a device that hasn't posted since midnight don't count today
            into = (
                readings if status.get("day") == today.isoformat()
                else back_readings if backfill and status.get("day") == yesterday
                else None
            )
            if device.get(CONF_KIND) == KIND_TV:
                profiles = self.device_profile_people(device_id)
                if into is not None:
                    for profile_id, usage in (status.get("usage_today") or {}).items():
                        person = profiles.get(profile_id)
                        if person:
                            add(person, device_id, Reading(SOURCE_HEARTH, float(usage.get("seconds") or 0),
                                                           usage.get("apps") or {}), into)
                person = profiles.get(status.get("profile_id") or "")
            else:
                person = device.get(CONF_PERSON)
                if person and into is not None:
                    add(person, device_id, self._device_reading(device_id, status), into, own_items=True)
            package = status.get("app_package")
            if person and status.get("screen") == "on" and self.hub.connected(device_id) and package:
                # A TV's media player says what's on, else the device's own media session: the show (else the title)
                # is what "together" matches on then
                media = (self._tv_media(device_id) if device.get(CONF_KIND) == KIND_TV else None) or _status_media(status)
                entry = Playing(status.get("app"), package, name, status.get("state"), f"hearth:{device_id}", kind="app")
                for field_name, value in (media or {}).items():
                    setattr(entry, field_name, value)
                shown = entry.series or entry.title
                observe(entry, person, device_id, shown or package, None, shown or status.get("app"))

        # Sources: totals now; live ones are looked at (and timed) below
        for source in self.sources:
            device = device_key(source, by_id)
            if source.phone_app:
                # A phone's app in use, while its screen is: not timed (its own parental controls count it)
                package = phone_app_playing(self.hass, source)
                if package is not None:
                    from .targets import target_of_counted

                    target, _ = target_of_counted(self, source.person, f"source:{source.id}")
                    app = self._app_name(package)
                    observe(Playing(app, package, source.name, "playing", target, kind="app"), source.person, device,
                            package, None, app)
            elif source.live:
                item = now_playing(self.hass, source)
                if item is not None:
                    from .targets import target_of_counted

                    target, _ = target_of_counted(self, source.person, f"source:{source.id}")
                    observe(
                        Playing(item, None, source.name, "playing", target, item, kind="game"),
                        source.person, device, item, source.reading_source, item,
                    )
            else:
                reading = totals_reading(self.hass, source, today)
                last = self._last_totals.get(source.id)
                last = last[1] if last is not None and last[0] == today else None
                if reading is not None:
                    higher = _higher(last, reading) if last is not None else reading
                    if higher != last:
                        self._last_totals[source.id] = (today, higher)
                        self._totals_store.async_delay_save(self._totals_data, 30)
                    reading = higher
                else:
                    reading = last
                if reading is not None:
                    add(source.person, device, reading)

        # A kid on their Switch (Nintendo's playing sensors): not timed (Nintendo's own minutes count), but together
        enforcers = enforcers_from_options(options)
        for enforcer in enforcers:
            if enforcer.kind != NINTENDO:
                continue
            target = f"nintendo:{enforcer.entity_id}"
            # A live source on the same Switch says it already
            if any(p.target == target for p in playing.get(enforcer.person, [])):
                continue
            on = [
                state for entity_id in playing_entities(self.hass, enforcer, enforcers)
                if (state := self.hass.states.get(entity_id)) is not None and state.state == "on"
            ]
            if on:
                game = next((t for state in on if (t := playing_title(state))), None)
                # Without the game's name, "together" only on the same console (never two Switches both saying
                # "Switch")
                item = game or f"{SWITCH_ITEM}@{switch_console(self.hass, enforcer.entity_id)}"
                observe(
                    Playing(game or SWITCH_ITEM, None, switch_name(self.hass, enforcer.entity_id), "playing", target, game,
                            kind="game"),
                    enforcer.person, target, item, None, game or SWITCH_ITEM,
                )

        started, ended = self.live.look(now, today, observations)
        for entry, key in plays:
            entry.since = self.live.since_of(*key)
        # What was played, once it ends: the week's top titles later (history.py, `played`)
        for play in self.live.ended_plays:
            self.history.log_played(play.person, play.label, play.device, play.minutes)
        for source in self.sources:
            if source.live and (timed := back_live.get(source.reading_source)):
                add(source.person, device_key(source, by_id),
                    Reading(source.reading_source, sum(timed.values()), timed, source.group), back_readings)
            if source.live:
                timed = self.live.seconds.get(source.reading_source, {})
                if timed:
                    add(source.person, device_key(source, by_id),
                        Reading(source.reading_source, sum(timed.values()), timed, source.group))
                    for key in timed:
                        if source.group:
                            hints.setdefault(key, set()).add(source.group)

        self.categories = categories
        self._hints = hints
        self._note_for_lookup(readings)
        self._look_for_new_apps(categories)
        membership = self.membership()
        # The day turned: each person's final minutes of the day before, as last counted (history.py, `day`)
        if self.today is not None and self.today != today:
            for person, last in self.days.items():
                self.history.log_day(person, self.today, self.day_minutes(last), self.day_budget(last))
        elif backfill:
            back_day = today - timedelta(days=1)
            # Only who had time counted on Hearth's devices or live sources: a totals sensor has started today since
            for person in back_readings:
                devices = {device: merge(r) for device, r in back_readings[person].items()}
                seconds = group_seconds(devices, membership, self.outside_all())
                self.history.log_day(person, back_day, self.day_minutes(PersonDay(person, groups=seconds)),
                                     self.budget_on(person, back_day))
        # Today's answer as last worked out; if the day turned without a refresh yet, what's known now
        is_school = (
            self.school.school if self.school.day == today else self.school.budget_is_school(self.school.decide_type(today))
        )
        kind = SCHOOL_DAY if is_school else OTHER_DAY
        day_type = self.day_type_on(today)
        if new_day or self.today != today:
            # Today-only changes of the schedule end at midnight
            self.week.new_day(today)
        days: dict[str, PersonDay] = {}
        for person in self.people():
            # The weekly schedule now: the mode, and what it locks or closes (weekly.py); today's limits
            self.schedule_now[person] = self.week.now(person, now)
            day_limits = self.week.limits_on(person, today, day_type)
            devices = {device: merge(r) for device, r in readings.get(person, {}).items()}
            if _LOGGER.isEnabledFor(logging.DEBUG):
                _LOGGER.debug(
                    "counting %s: %s", person,
                    {d: (int(u.total_s), len(u.items)) for d, u in devices.items()},
                )
            raw = group_seconds(devices, membership, self.outside_all())
            # Minutes used while unlimited aren't counted (unlimited.py)
            seconds = self.unlimited.exclude(person, raw, now)
            day = PersonDay(person, devices, seconds, playing=playing.get(person, []),
                            together_s=self.live.together_s.get(person, 0.0), raw_groups=raw)
            for group in self.groups:
                day.limits[group.id] = self.limits.state(
                    person, group.id, seconds.get(group.id, 0.0) / 60, kind, day_limits.get(group.id)
                )
            # Today's time, caps and bonus time (time_model.py)
            self.apply_time_model(person, day.limits, now)
            if self._settling(now):
                for group in self.groups:
                    state = day.limits[group.id]
                    if (state.minutes_left or 0) > 0 and self.limits.is_reached(person, group.id):
                        _keep_held(state)
            for group in self.groups:
                state = day.limits[group.id]
                if state.minutes_left == 0:
                    if self.limits.mark_reached(person, group.id):
                        self.hass.bus.async_fire(
                            EVENT_BUDGET_REACHED, {"person": person, "group": group.id, "group_name": group.name}
                        )
                        # Hearth's own hold of the group's apps (its devices, and the parental controls after)
                        self.activity.hold(True, person, group.id, "daily_time" if group.id == ALL else "limit", "hearth")
                elif state.minutes_left is not None:
                    if self.limits.clear_reached(person, group.id):
                        self.activity.hold(False, person, group.id, "time_given", "hearth")
            all_state = day.limits.get(ALL)
            # Extra time at bedtime: over once its time is up or All screen time runs out again
            self.bedtime_lift.check(person, all_state.minutes_left if all_state else None, now)
            day.locked_by = self._locks_now(person, now)
            day.locked = bool(day.locked_by)
            days[person] = day
        self.days = days
        # Unlimited windows that ended since: told once, with today's time as it is again (unlimited.py)
        self.unlimited.tell_ended()
        self.today = today
        self._tell_modes()
        groups_by_id = {g.id: g for g in self.groups}

        spared = self.never_held(membership)

        def apps_of(group_id: str, person: str) -> list[str]:
            if group_id == ALL:
                return self._person_apps(days.get(person), membership)
            if group_id not in groups_by_id:
                return []
            # With the Xbox and Windows apps a group lists, for Family Safety; never an accessibility app
            return [p for p in self._group_apps(groups_by_id[group_id], membership, with_fs=True) if p not in spared]

        self.allows.prune()
        self.grants.prune()
        self._prune_device_extras()
        # A parent's changes in their own apps first: they lift what they came from
        self.sync.detect()
        self.enforcement.update(
            enforcers_from_options(options),
            days,
            apps_of,
            lifted_of=self.allows.lifted,
            budget_lifted_of=self.budget_lifted,
            school_time_of=self.in_school_time,
            groups_of_app=membership,
            granted_of=self.grants.lifted,
            paused_of=lambda person: self.paused_packages(person, membership, with_fs=True),
            spared=spared,
            device_lifted_of=self._device_lifted,
            paused_groups_of=lambda person: self.paused_groups(person, now),
            closed_of=self.schedule_holds,
            exempt_of=self.client_exempt(),
            blocked_of=self.blocks.blocked_packages,
        )
        # Hearth's app blocks in step with Family Link (an app that showed up, a block or unblock of an adult's)
        self.blocks.sync()
        # An adult's allow of All screen time opens Google's and Microsoft's own limits too
        self.sync.mirror_allows()
        # Family Link's daily limit in step with today's time (backstop.py)
        self.backstop.check()
        # Family Link's bedtime in step with the lifts (moved while one lasts, put back after)
        if self.bedtime_lift.lifts or self.bedtime_lift.moved:
            self.bedtime_lift.sync()
        for together, what in [(t, "started") for t in started] + [(t, "ended") for t in ended]:
            self.hass.bus.async_fire(EVENT_PLAYING_TOGETHER, self._together_event(together, what))
        async_dispatcher_send(self.hass, SIGNAL_PEOPLE, new_day)

    def client_exempt(self):
        """person -> the packages never paused for them: the client (and its companions) locked at the pairing of
        each of their devices, as an adult approved it (client.py). Never one the household or what it is put in a
        pool (an adult's move or list, Hearth's lists, categories.py's answer): those are held like any app. A
        client a device reports later that isn't the one it paired with changes nothing."""
        place = self.placement()
        found: dict[str, set[str]] = {}
        for device in self.hub.devices.values():
            person = device.get(CONF_PERSON)
            if not person or device.get(CONF_KIND) == KIND_TV:
                continue
            for package in exempt_packages(device):
                placed = place(package)
                if placed.pool is not None and placed.why in POOLED_BY_HOUSEHOLD_OR_CATEGORY:
                    continue
                found.setdefault(person, set()).add(package)
        return lambda person: found.get(person, set())

    def day_type_on(self, day: date) -> str:
        """A date's day type: today's as last worked out (the entity and the calendar too), another day's from the
        dates typed in and the rule (schooldays.type_by_dates)."""
        if self.school.day == day:
            return self.school.day_type
        if day == dt_util.now().date():
            return self.school.decide_type(day)
        return self.school.type_by_dates(day)

    def _tell_modes(self) -> None:
        """hearth_mode when a person's mode changed since the last look (not on the first look after a start)."""
        for person, found in self.schedule_now.items():
            mode = found.mode if found is not None else None
            before = self._modes_told.get(person)
            if mode is None:
                self._modes_told.pop(person, None)
                continue
            self._modes_told[person] = mode
            if before is None or before == mode:
                continue
            self.hass.bus.async_fire(
                EVENT_MODE,
                {
                    "person": person,
                    "mode": mode,
                    "mode_name": (self.week.data.modes.get(mode) or {}).get("name", mode),
                    "previous": before,
                    "until": dt_util.as_local(found.until).isoformat() if found.until else None,
                },
            )

    def day_minutes(self, day: PersonDay | None) -> dict[str, int]:
        """A person's minutes per group of the household (seconds / 60, rounded), as the summary's `week` shows them."""
        groups = day.groups if day is not None else {}
        return {g.id: int(round(groups.get(g.id, 0.0) / 60)) for g in self.groups}

    def day_budget(self, day: PersonDay) -> dict[str, int | None]:
        """A person's budget per group of the household that day, without bonus (None: no limit), as counted."""
        return {g.id: (state.budget_min if (state := day.limits.get(g.id)) else None) for g in self.groups}

    def budget_on(self, person: str, day: date) -> dict[str, int | None]:
        """The person's budget per group on [day]: today's as counted, another day's from its day type by the dates
        and the rule (schooldays.type_by_dates) and the budgets now."""
        if day == self.today and (today := self.days.get(person)) is not None:
            return self.day_budget(today)
        limits = self.week.limits_on(person, day, self.school.type_by_dates(day))
        return {g.id: limits.get(g.id) for g in self.groups}

    # New apps

    def _look_for_new_apps(self, categories: dict[str, str]) -> None:
        watched = [e for e in self.options.get(CONF_APP_WATCH, []) if self.hass.states.get(e) is not None]
        observed = observed_from_entities(self.hass, watched)
        sources = set(watched)
        for device_id, device in self.hub.devices.items():
            status = self.hub.state(device_id).status
            if status is None:
                continue
            sources.add(f"hearth:{device_id}")
            where = device.get("name") or device_id
            packages = set(status.get("app_seconds_today") or {})
            for usage in (status.get("usage_today") or {}).values():
                packages |= set(usage.get("apps") or {})
            for package in packages:
                observed.setdefault(package, (package, where, f"hearth:{device_id}"))
            if status.get("app_package"):
                observed[status["app_package"]] = (
                    status.get("app") or status["app_package"], where, f"hearth:{device_id}"
                )
        fresh = self.apps.observe(observed, categories, self.groups, sources)
        # Sorted on their own (a group that lists them, what they are, their category, else Other): nobody is asked;
        # an adult moves one on Hearth's page if it landed wrong. Where it went is where it counts (a later answer of
        # what it is
        # included)
        place = self.placement() if fresh else None
        for entry in fresh:
            entry.group = entry.suggested = place(entry.package).pool
            self.hass.bus.async_fire(
                EVENT_NEW_APP,
                {"package": entry.package, "name": entry.name, "who": entry.who, "group": entry.group or OTHER},
            )
        if fresh:
            update_notification(self.hass, [], self.groups)

    def _note_for_lookup(self, readings: dict[str, dict[str, list[Reading]]]) -> None:
        """The apps a kid used today that the owner's overrides and the starter list don't cover join the lookup queue
        (categories.py: a store's genre, then maybe the owner's AI). Adults' apps aren't looked up."""
        roles = self.options.get(CONF_ROLES, {})
        used: set[str] = set()
        for person, devices in readings.items():
            if roles.get(person) == "adult":
                continue
            for device_readings in devices.values():
                for reading in device_readings:
                    used |= {item for item, seconds in reading.items.items() if seconds}
        # An adult's move or list, or Hearth's own pool lists, already say where it counts: nothing to look up
        place = self.placement()
        used = {item for item in used if place(item).why not in ("moved", "list", "starter")}
        if not used:
            return
        names ={item: entry.name for item in used if (entry := self.apps.apps.get(item)) is not None and entry.name}
        if any(i.startswith("x:") for i in used):
            names.update({i: n for i, n in self._family_safety_apps().items() if i in used and i not in names})
        self.categories_book.note_used({item: names.get(item) for item in sorted(used)})

    @callback
    def categorize_app(self, item: str, category: str | None, detail: str | None, clear: bool = False) -> None:
        """An adult said what [item] is (category None: none of the ten), or took that back ([clear]). The latest
        thing an adult did wins: a move or a pool's list of the app goes, so what it is decides its pool."""
        options = CategoryBook.with_override(dict(self.hub.entry.options), item, category, detail, clear)
        if not clear:
            options = without_app(options, item, keep=None)
            moved = dict(options.get(CONF_APP_GROUPS, {}))
            if moved.pop(item, None) is not None:
                options[CONF_APP_GROUPS] = moved
        self.hass.config_entries.async_update_entry(self.hub.entry, options=options)

    def check_these(self, known: dict[str, str] | None = None) -> list[dict[str, Any]]:
        """Apps an adult should look at: placed on an unconfirmed answer (a store's loose genre, an AI's guess), or
        where a confirmed answer and the device disagree on whether it's a game (Hearth goes by the answer). Gone once
        an adult moves, confirms or says what one is."""
        known = known if known is not None else self.known_apps()
        place = self.placement()
        found = []
        for item, name in known.items():
            p = place(item)
            if p.why == "suggested":
                hit = self.categories_book.lookup(item)
                source = hit.source if hit is not None else None
                why = f"{'an AI guessed' if source == 'ai' else 'the store says'} {p.value}"
            elif p.why == "category" and p.disagree:
                hit = self.categories_book.lookup(item)
                if hit is not None and hit.source == "override":
                    continue
                why = f"Hearth says {p.value or 'none of its kinds'}, the device says {p.declared}"
            else:
                continue
            found.append({
                "package": item,
                "name": name,
                "group": p.pool or OTHER,
                "why": why,
                "suggested": p.why == "suggested",
            })
        # Suggestions first, then disagreements, each by name
        return sorted(found, key=lambda a: (not a["suggested"], str(a["name"]).lower()))[:50]

    def category_note(self, item: str, group: str) -> str | None:
        """For an app an adult moved: what Hearth now knows it is, when that would put it elsewhere (shown quietly;
        the adult's choice stands)."""
        hit = self.categories_book.lookup(item)
        if hit is None or not hit.confirmed or hit.value is None:
            return None
        pools = self.pools()
        value = hit.detail if hit.detail in pools else hit.category
        pool = pools.get(value) if value else None
        pool = pool if pool and self.group(pool) is not None else OTHER
        return None if pool == group else hit.value

    def _ask_on_phone(self, entry) -> None:
        self.hub.attention.notify(
            Item(
                f"hearth_app_{entry.package}",
                (f"{entry.who} has {entry.name}. " if entry.who else f"{entry.name} is new. ")
                + "Which group does it count in?",
                title="New app: " + entry.name,
                audience=CHOSEN_PHONE,
                actions=tuple(Action(a["action"], a["title"]) for a in phone_actions(entry, self.groups)),
            )
        )

    @callback
    def sort_app(self, package: str, group: str) -> bool:
        """An adult moved an app to a group (or Other: All screen time only); it beats every automatic source."""
        if group != OTHER and self.group(group) is None:
            return False
        self.apps.sort(package, group)
        moved = {**self.options.get(CONF_APP_GROUPS, {}), package: group}
        # An app is in one pool: it leaves any other pool's list
        options = without_app(dict(self.hub.entry.options), package, keep=None if group == OTHER else group)
        self.hass.config_entries.async_update_entry(self.hub.entry, options={**options, CONF_APP_GROUPS: moved})
        return True

    def app_group(self, package: str, membership=None) -> str:
        """Where an app counts now: its first group besides All, or Other."""
        groups = (membership or self.membership())(package) - {ALL}
        order = [g.id for g in self.groups]
        return min(groups, key=order.index) if groups else OTHER

    def apps_overview(self) -> dict[str, Any]:
        """Every known app with its group (and whether an adult moved it), and the ones sorted lately, newest first."""
        membership = self.membership()
        moved = self.options.get(CONF_APP_GROUPS, {})
        known = self.known_apps()
        apps = []
        for p, name in sorted(known.items(), key=lambda kv: kv[1].lower()):
            row = {"package": p, "name": name, "group": self.app_group(p, membership), "moved": p in moved}
            row.update(self.categories_book.describe(p))
            if p in moved and (note := self.category_note(p, row["group"])):
                row["category_says"] = note
            apps.append(row)
        recent = sorted(
            (e for e in self.apps.apps.values() if e.state != "known"), key=lambda e: e.seen, reverse=True
        )[:25]
        return {
            "apps": apps,
            "check_these": self.check_these(known),
            "recent": [
                {
                    "package": e.package,
                    "name": known.get(e.package, e.name),
                    "who": e.who,
                    "seen": e.seen,
                    "group": self.app_group(e.package, membership),
                    "moved": e.package in moved,
                }
                for e in recent
            ],
        }

    def _app_name(self, package: str) -> str:
        entry = self.apps.apps.get(package)
        return entry.name if entry is not None and entry.name else package

    def _tv_media(self, device_id: str) -> dict[str, Any] | None:
        """What a TV's media player (options' media_players) says is on, as Playing's fields (kind, title, series,
        episode, artist, and its length and position when known), or None."""
        entity_id = self.options.get(CONF_MEDIA_PLAYERS, {}).get(device_id)
        state = self.hass.states.get(entity_id) if entity_id else None
        if state is None or state.state not in ("playing", "paused", "buffering", "on"):
            return None
        attrs = state.attributes

        def text(name: str) -> str | None:
            value = attrs.get(name)
            return value.strip()[:128] if isinstance(value, str) and value.strip() else None

        series, title, artist = text("media_series_title"), text("media_title"), text("media_artist")
        if not (series or title):
            return None
        if series and (not title or title == series):
            # Only the show's name: it's the most specific known
            series, title = None, series
        music = attrs.get("media_content_type") == "music" or (artist is not None and series is None)
        season, number = attrs.get("media_season"), attrs.get("media_episode")
        episode = None
        if series and str(number or "").isdigit():
            episode = f"s{season}e{number}" if str(season or "").isdigit() else f"e{number}"
        at = attrs.get("media_position_updated_at")
        if isinstance(at, str):
            at = dt_util.parse_datetime(at)
        return {
            "kind": "music" if music else "video",
            "title": title,
            "series": None if music else series,
            "artist": artist if music else None,
            "episode": episode,
            **_timing(attrs.get("media_duration"), attrs.get("media_position"), at if isinstance(at, datetime) else None),
            "paused": state.state == "paused",
        }

    def _label(self, key: str, fallback: str | None) -> str:
        if key.startswith("title:"):
            title = next((t for t in self.titles if f"title:{t.id}" == key), None)
            if title:
                return title.name
        return fallback or key

    @staticmethod
    def _together_event(together: Together, what: str) -> dict[str, Any]:
        return {"title": together.label, "people": together.people, "devices": together.devices, "event": what}

    # What a device is told

    def _known_apps_for(self, membership) -> dict[str, str]:
        """known_apps(), computed once per membership() (one document build) rather than once per group."""
        cached = self._known_for
        if cached is not None and cached[0] is membership:
            return cached[1]
        known = self.known_apps()
        self._known_for = (membership, known)
        return known

    def _group_apps(self, group: Group, membership, with_fs: bool = False) -> list[str]:
        """The packages a device should hold to a group: its own list and the apps seen in it (a title's packages).
        [with_fs]: with the group's Xbox and Windows apps (Family Safety's ids), which no Hearth device holds."""
        if group.id == ALL:
            return []
        titles = {f"title:{t.id}": t for t in self.titles}
        found: set[str] = set()
        for item in set(group.apps) | {k for k in self._known_apps_for(membership) if group.id in membership(k)}:
            title = titles.get(item)
            for candidate in (title.raw if title else (item,)):
                if fs_app(candidate):
                    if with_fs:
                        found.add(candidate)
                elif "." in candidate and " " not in candidate:
                    found.add(candidate)
        return sorted(found)

    def paused_packages(self, person: str, membership, with_fs: bool = False) -> set[str]:
        """The apps an adult paused for the person (hearth.pause with an app or a group), while those pauses last."""
        found: set[str] = set()
        for pause in app_pauses_of(self.hass, person):
            if pause["app"] is not None:
                found.add(pause["app"])
            elif (group := self.group(pause["group"])) is not None:
                found |= set(self._group_apps(group, membership, with_fs=with_fs))
        return found - self.never_held(membership)

    def paused_groups(self, person: str, now: datetime | None = None) -> set[str]:
        """The groups an adult paused for the person while those pauses last, All screen time for a family pause (a
        Switch is held for them: enforce.py)."""
        found = {ALL} if pause_of(self.hass, person, now) else set()
        for pause in app_pauses_of(self.hass, person, now):
            if pause["group"] is not None and (group := self.group(pause["group"])) is not None:
                found.add(group.id)
        return found

    def _paused_groups_document(self, person: str, membership) -> list[dict[str, Any]]:
        """The person's app and group pauses as groups with no time left, which every Hearth TV and phone already
        holds (HearthTube too, when one lists it): {id "pause:<app or group>", name, minutes_left 0, apps, paused}."""
        out = []
        for pause in app_pauses_of(self.hass, person):
            if pause["app"] is not None:
                if pause["app"] in self.never_held(membership):
                    continue
                apps = [pause["app"]]
                known = self.apps.apps.get(pause["app"])
                key, name = f"app:{pause['app']}", (known.name if known else None) or pause["app"]
            else:
                group = self.group(pause["group"])
                if group is None:
                    continue
                apps = self._held_apps(group, membership)
                key, name = f"group:{group.id}", group.name
            out.append(
                {
                    "id": f"pause:{key}",
                    "name": f"{name} (paused: {pause['reason']})" if pause["reason"] else f"{name} (paused)",
                    "minutes_left": 0,
                    "apps": apps,
                    # The plain name too, for a device that says "<name> is paused" (and offers no ask for it)
                    "paused": {
                        "until": dt_util.as_local(pause["until"]).isoformat(),
                        "reason": pause["reason"],
                        "name": name,
                    },
                }
            )
        return out

    def _closed_groups_document(self, person: str, membership, lifted: Lifted) -> list[dict[str, Any]]:
        """The groups the schedule's mode closes now (Homework, Wind down) as paused groups, which every Hearth TV and
        phone already holds and offers no ask for more: {id "schedule:<group>", name "Games (Homework until 5 PM)",
        minutes_left 0, apps, paused}. An allow of the group lifts it; an allowed app leaves it."""
        found = self.schedule_now.get(person)
        if found is None:
            return []
        mode = self.week.data.modes.get(found.mode) or {}
        until = dt_util.as_local(found.until) if found.until else None
        when = f" until {_say_clock(until)}" if until else ""
        out = []
        for group_id in self.schedule_closed(person):
            group = self.group(group_id)
            if group is None or (lifted and lifted.group(group_id)):
                continue
            apps = self._held_apps(group, membership)
            if lifted:
                apps = [p for p in apps if not lifted.app(p, membership(p))]
            out.append(
                {
                    "id": f"schedule:{group_id}",
                    "name": f"{group.name} ({mode.get('name', found.mode)}{when})",
                    "minutes_left": 0,
                    "apps": apps,
                    "paused": {
                        "until": until.isoformat() if until else None,
                        "reason": mode.get("name", found.mode),
                        "name": group.name,
                    },
                }
            )
        return out

    def app_pause_views(self, person: str) -> list[dict[str, Any]]:
        """The person's app and group pauses as an adult's app shows them: [{app, group, name, until, reason}]."""
        out = []
        for pause in app_pauses_of(self.hass, person):
            if pause["app"] is not None:
                known = self.apps.apps.get(pause["app"])
                name = (known.name if known else None) or pause["app"]
            elif (group := self.group(pause["group"])) is not None:
                name = group.name
            else:
                continue
            out.append(
                {
                    "app": pause["app"],
                    "group": pause["group"],
                    "name": name,
                    "until": dt_util.as_local(pause["until"]).isoformat(),
                    "reason": pause["reason"],
                }
            )
        return out

    def outside_all(self) -> set[str]:
        """The groups whose time isn't screen time (Configure > Not screen time)."""
        return {g.id for g in self.groups if not g.in_all and g.id != ALL}

    def _spared(self, membership) -> set[str]:
        """The packages All screen time never holds: those of the groups outside it, and the accessibility apps."""
        found: set[str] = set(self.never_held(membership))
        for group in self.groups:
            if group.id in self.outside_all():
                found |= set(self._group_apps(group, membership))
        return found

    def never_held(self, membership) -> frozenset[str]:
        """The packages nothing of Hearth's ever pauses: the built-in Accessibility pool's (Voice Access, Lookout, Live
        Transcribe: an app a kid may rely on) and System screens' (the home screen, keyboards, Android's own screens).
        Not a budget running out, an adult's pause of an app or group, School time's apps nor the weekly schedule. Only
        a confirmed answer puts an app there (limits.placer)."""
        cached = self._never_held_for
        if cached is not None and cached[0] is membership:
            return cached[1]
        found = frozenset(
            package
            for group_id in (ACCESSIBILITY, INTERFACE)
            if (group := self.group(group_id)) is not None and never_held_group(group)
            for package in self._group_apps(group, membership)
        )
        self._never_held_for = (membership, found)
        return found

    def _held_apps(self, group: Group, membership) -> list[str]:
        """The packages a device holds to [group]: its apps but the accessibility ones."""
        spared = self.never_held(membership)
        return [p for p in self._group_apps(group, membership) if p not in spared]

    def group_packages(self) -> dict[str, list[str]]:
        """Each group's packages (not All's: every app), as devices are held to them. Worked out once a recompute: every
        person's sensor reads it on each write."""
        cached = getattr(self, "_group_packages_cache", None)
        if cached is None:
            membership = self.membership()
            cached = {g.id: self._group_apps(g, membership) for g in self.groups if g.id != ALL}
            self._group_packages_cache = cached
        return {gid: list(apps) for gid, apps in cached.items()}

    def _lifted_packages(self, lifted: Lifted, membership) -> set[str]:
        """The packages a person's allows lift: the allowed apps, and the apps of the allowed groups."""
        found = {p for p in lifted.apps if "." in p}
        for group in self.groups:
            if group.id != ALL and group.id in lifted.groups:
                found |= set(self._group_apps(group, membership))
        return found

    def _person_apps(self, day: PersonDay | None, membership) -> list[str]:
        """Every app of a person's Hearth knows, for holding All screen time: the apps of every group, and those in
        their usage today on any device and from any source (a title's packages); never those of a group outside All
        screen time."""
        outside = self.outside_all()
        found: set[str] = set()
        for group in self.groups:
            if group.id != ALL and group.id not in outside:
                found |= set(self._group_apps(group, membership))
        titles = {f"title:{t.id}": t for t in self.titles}
        for usage in (day.devices.values() if day else ()):
            for item in usage.items:
                if membership(item) & outside:
                    continue
                title = titles.get(item)
                for candidate in (title.raw if title else (item,)):
                    if "." in candidate and " " not in candidate:
                        found.add(candidate)
        return sorted(found - self._spared(membership))

    def _person_document(self, person: str, device_id: str | None = None) -> dict[str, Any]:
        """[device_id]: the Hearth device asking, whose extra time of the person's (device_extra.py) shows here only."""
        day = self.days.get(person)
        membership = self.membership()
        extras = self.device_extras.of(person, f"hearth:{device_id}") if device_id else []
        allowed_here = {e.group for e in extras if e.kind == EXTRA_ALLOW}
        bonus_here: dict[str, int] = {}
        for extra in extras:
            if extra.kind == EXTRA_BONUS:
                bonus_here[extra.group] = max(bonus_here.get(extra.group, 0), self._extra_left(extra) or 0)
        # An adult's allows: an allowed group is left out (nothing holds it), an allowed app is taken out of every
        # group and is one of All screen time's exceptions
        # A category with its own bonus left is lifted the same way, for its budget only (its apps run past daily time)
        lifted = self.budget_lifted(person)
        groups = []
        for group in self.groups:
            state = day.limits.get(group.id) if day else None
            if state is None or state.budget_min is None or lifted.group(group.id) or group.id in allowed_here:
                continue
            apps = self._held_apps(group, membership)
            entry = {
                "id": group.id,
                "name": group.name,
                # Extra time on this device: what's left of it here, when that's more than the pool's
                "minutes_left": max(state.minutes_left, bonus_here.get(group.id, 0)),
                "apps": [p for p in apps if not lifted.app(p, membership(p))] if lifted else apps,
            }
            # All screen time holds every app but these (a group outside it: music, say; what an allow lifts)
            if group.id == ALL:
                spared = self._spared(membership)
                if lifted:
                    spared |= self._lifted_packages(lifted, membership)
                if spared:
                    entry["except"] = sorted(spared)
            groups.append(entry)
        groups += self._paused_groups_document(person, membership)
        groups += self._closed_groups_document(person, membership, self.allows.lifted(person))
        return {
            "person": person,
            "groups": groups,
            # Today's time, bonus time and category limits as a person is shown them (docs/contracts/time-model.md)
            "time": self.time_view(person),
            "locked": bool(day and day.locked),
            **self._locks_document(person, day),
            # The accessibility apps no group above holds, for a device that can spare them from a lock too
            **({"never_held": sorted(never)} if (never := self.never_held(membership)) else {}),
            # Never paused by Hearth for any reason: the system list enforce.py uses (calls, Settings, Play services,
            # Family Link, the Play Store, Hearth and Glint) with the launchers, keyboards and accessibility apps.
            # A client holds everything else, Messaging included (docs/contracts/time-model.md)
            "never_paused": sorted(SYSTEM_NEVER_PAUSED | never),
            # What they're playing now, anywhere (as the household summary's `playing`)
            "playing": [p.view() for p in (day.playing if day else [])],
            # The weekly schedule now: the mode, the next change, tonight's bedtime (weekly.py)
            **({"schedule": view} if (view := self.schedule_view(person)) else {}),
            # Retired: no client shares app data any more, so always false (kept so contract 3 clients read it as off)
            "share_app_data": False,
            # A kid's to-do list today, counts only (todos.py); the money balance stays on adults' screens
            **({"todo": self.todos.counts(person)} if person in self.todos.kids() else {}),
            # Their latest request for more time and its answer (asks.py), while it's still news
            **({"request": ask.device_view()} if (ask := self.hub.asks.latest_for(person)) else {}),
            # What a parent blocked here, for HearthTube in the person's kids profiles (a TV's Hearth passes it on)
            "youtube_blocks": self.watch.blocks_document(person),
            # Their own allows that end on a place: "ends when you get home". Never where they are
            **({"allow_ends": ends} if (ends := self._allow_ends(person)) else {}),
        }

    def _allow_ends(self, person: str) -> list[dict[str, Any]]:
        return [
            {
                "id": a.id,
                "app": a.app,
                "group": a.group,
                "until": dt_util.as_local(a.until[person]).isoformat(),
                "text": self.places.ends_on_view(person, a.ends_on, you=True)["text"],
            }
            for a in self.allows.of(person)
            if a.ends_on
        ]

    def document_for(self, device_id: str) -> dict[str, Any]:
        """The device's state document: per TV profile (or, for a phone, its person) what's left today."""
        device = self.hub.devices.get(device_id, {})
        if device.get(CONF_KIND) == KIND_TV:
            status = self.hub.state(device_id).status or {}
            profile_ids = set((status.get("usage_today") or {}).keys())
            if status.get("profile_id"):
                profile_ids.add(status["profile_id"])
            # By this TV's own keys: what the TV looks its profiles up by
            profiles = self.device_profile_people(device_id)
            body: dict[str, Any] = {
                "profiles": {
                    profile_id: self._person_document(profiles[profile_id], device_id)
                    for profile_id in sorted(profile_ids)
                    if profiles.get(profile_id)
                },
                # Every mapped profile's YouTube blocks, not only today's: a kid who hasn't used this TV today is held
                # to them from the first moment (their limits come with their first post, as before)
                "youtube_blocks": {
                    profile_id: self.watch.blocks_document(person)
                    for profile_id, person in sorted(profiles.items())
                    if person
                },
                # One-shot commands waiting for this TV (hearth.play_on_tv): it runs each id once and says so in its
                # next status (commands_done)
                "commands": self.hub.commands.document_for(device_id),
                # Who each of this TV's mapped profiles is, by its own keys: a notification's "for" may name a person
                # ("person.sam"), and the TV finds that person's profile here
                "people": {profile_id: person for profile_id, person in sorted(profiles.items()) if person},
            }
            # Each adult profile's phones, by this TV's own keys: the notify services of their person's companion
            # apps (phones.py person_phones), so phone approval reaches them without anyone picking a phone on the
            # TV. A phone chosen on a TV (synced between the household's TVs) wins over these.
            if adult_phones := self.adult_phones(profiles):
                body["adult_phones"] = adult_phones
            # What the adults should see on this TV (attention items for TVs: the chosen suggestions), for a TV that
            # says it shows them; it shows each in its adult profiles only ("for" names one person, else every adult)
            if self.hub.has_cap(device_id, CAP_NOTICES):
                body["notices"] = self.hub.attention.tv_notices({p for p in profiles.values() if p})
            # The adults' parent PINs (hashes, never a PIN): a paired TV asks verify_pin, and keeps these (sealed) to
            # check PINs with Home Assistant down. Sent only when they changed since the TV's copy (its
            # parent_pins_version); the version alone says its copy is current. Each says the TV profiles of its adult.
            if pins := parent_pin.stored_pins(self.options):
                listed = [
                    {
                        "person": person,
                        "name": self.person_name(person),
                        "hash": stored,
                        "profiles": sorted(p for p, who in profiles.items() if who == person),
                    }
                    for person, stored in sorted(pins.items())
                ]
                pins_version = hashlib.sha256(json.dumps(listed, sort_keys=True).encode()).hexdigest()[:16]
                body["parent_pins_version"] = pins_version
                if status.get("parent_pins_version") != pins_version:
                    body["parent_pins"] = listed
        else:
            body = self._phone_body(device.get(CONF_PERSON), device_id)
        # Contract 3: the etags of the client settings this device may read, for the client it paired with, so it
        # fetches only what changed (client_settings.py); none for a device paired without a client
        if (etags := self.hub.client_settings.etags_for_device(device_id)) is not None:
            body["client_settings"] = etags
        body["version"] = hashlib.sha256(json.dumps(body, sort_keys=True).encode()).hexdigest()[:16]
        body["contract"] = CONTRACT
        return body

    def adult_phones(self, profiles: dict[str, str]) -> dict[str, list[str]]:
        """{profile_id: [notify service, ...]} for [profiles] (a TV's keys -> person) whose person is an adult on
        Hearth's page and has a companion app; the services in person_phones' order."""
        roles = self.options.get(CONF_ROLES, {})
        out: dict[str, list[str]] = {}
        for profile_id, person in sorted(profiles.items()):
            if not person or roles.get(person) != "adult":
                continue
            if services := [service for service, _ in person_phones(self.hass, person)]:
                out[profile_id] = services
        return out

    def _phone_body(self, person: str | None, device_id: str | None = None) -> dict[str, Any]:
        """What a phone of [person]'s is told (without version and contract)."""
        body: dict[str, Any] = {"person": self._person_document(person, device_id) if person else None}
        if body["person"] is not None:
            role = self.options.get(CONF_ROLES, {}).get(person)
            # kid / adult as set on Hearth's page (kind_set); else a kid when they have limits
            body["person"]["kind"] = role or ("kid" if any(g["minutes_left"] is not None for g in body["person"]["groups"]) else "person")
            body["person"]["kind_set"] = role is not None
        # What's playing where in the house is anyone's to see: every room's players, for a phone's Music
        body["media_rooms"] = media_rooms(self.hass)
        return body

    def own_document(self, person: str) -> dict[str, Any]:
        """A person's own document, for their own Home Assistant user (hearth/me): what a paired phone of theirs gets,
        version and contract included. Nothing about anyone else."""
        body = self._phone_body(person)
        if self.options.get(CONF_ROLES, {}).get(person) == "adult":
            # The agent inbox etags of the adult's Glint phones (glint_agent.py): a new request changes the version, so
            # a Glint with Start in front hears it on hearth/me/subscribe. Always there for an adult ({} with none),
            # so Glint knows this Hearth pushes them
            body["client_settings"] = self.hub.glint_agent.inbox_etags(person)
        body["version"] = hashlib.sha256(json.dumps(body, sort_keys=True).encode()).hexdigest()[:16]
        body["contract"] = CONTRACT
        return body

    # School time and exceptions

    def family_link_child(self, person: str) -> str | None:
        enforcer = next(
            (e for e in enforcers_from_options(self.options) if e.kind == FAMILY_LINK and e.person == person), None
        )
        return fl.child_of(self.hass, enforcer.entity_id) if enforcer else None

    def in_school_time(self, enforcer) -> bool:
        """The enforcer's child is in School time now (any device of theirs says so), and Hearth hasn't taken it off."""
        if not enforcer.school_apps:
            return False
        child = fl.child_of(self.hass, enforcer.entity_id)
        if child is None or self.scheduler.off_now(enforcer.person) is not None:
            return False
        return fl.school_time_active(self.hass, child)

    def exceptions_of(self, person: str) -> dict[str, Any]:
        """The person's allows and School time taken off, for their sensor and Hearth's page."""
        return {
            "allows": self.allow_views(person),
            # A parent's change in the Family Link, Nintendo or Family Safety app that lifts one of Hearth's holds
            "grants": [g.view() for g in self.grants.of(person)],
            "school_time_off": self.off_views(person),
        }

    def allow_views(self, person: str, allows=None) -> list[dict[str, Any]]:
        """The person's allows as shown: an ends_on says its place and "ends when Sam gets home, or 21:00"."""
        out = []
        for allow in self.allows.of(person) if allows is None else allows:
            view = allow.view(person)
            if allow.ends_on:
                view["ends_on"] = self.places.ends_on_view(person, allow.ends_on, allow.until[person])
            out.append(view)
        return out

    def off_views(self, person: str) -> list[dict[str, Any]]:
        out = []
        for view in self.scheduler.offs_of(person):
            if view.get("ends_on"):
                view["ends_on"] = self.places.ends_on_view(person, view["ends_on"])
            out.append(view)
        return out

    def pause_view(self, person: str) -> dict[str, Any] | None:
        """The pause's ends_on as shown, while the person's pause has one."""
        found = pause_ends_on(self.hass, person)
        return self.places.ends_on_view(person, found[0], found[1]) if found else None

    @callback
    def place_changed(self, person: str, came_from: str | None, went_to: str) -> None:
        """A confirmed change of the person's place: what ends on it ends for them, as allow_end, pause_end and
        school_time_off_cancel would, and the adults are told."""
        ended: list[tuple[dict[str, str], str]] = []
        for allow in list(self.allows.of(person)):
            if matches(allow.ends_on, came_from, went_to) and self.allows.end_for(allow.id, person):
                group = self.group(allow.group) if allow.group else None
                what = (
                    "screen time" if allow.group == "all" else group.name if group else allow.group or allow.app
                )
                ended.append((allow.ends_on, f"their allow ({what}) ended"))
        if (pause := pause_ends_on(self.hass, person)) and matches(pause[0], came_from, went_to):
            self.end_pause_now([person])
            ended.append((pause[0], "their pause ended"))
        offs = [
            off
            for off in self.scheduler.ending_on_place(person, dt_util.now().date())
            if matches(off.ends_on, came_from, went_to)
        ]
        for off in offs:
            self.scheduler.end_one(off)
            ended.append((off.ends_on, "School time is back on"))
        if not ended:
            return
        self.recompute()
        # Extra time Hearth gave in Family Link or Family Safety for an allow that ended goes too
        self.sync.allow_ended()
        if offs:
            entry_task(self.hass, self.hub.entry.entry_id, self.scheduler.async_tick(), "hearth school time back")
        who = self.person_name(person)
        lines = [
            f"{happened(ends_on, who, self.places.place_name(person, next(iter(ends_on.values()))))}; {what}."
            for ends_on, what in ended
        ]
        self.hub.asks.tell(f"{who}: {self.places.place_name(person, went_to)}", " ".join(lines), f"hearth_place_{person}")

    def explain(self, person: str, app: str | None = None, group: str | None = None) -> dict[str, Any]:
        """Why an app or a group is held for the person now, or isn't: allowed, until, blocked_by [{kind, by, until}],
        exceptions (the allows that apply)."""
        now = dt_util.now()
        membership = self.membership()
        day = self.days.get(person)
        lifted = self.allows.lifted(person)
        outside = self.outside_all()
        # An accessibility app: no budget, pause or School time of Hearth's holds it (a lock still does)
        spared = app is not None and app in self.never_held(membership)
        if app is not None:
            groups = membership(app)
            if groups & outside:
                groups = groups - {ALL}
            excepted = lifted.app(app, groups)
        else:
            target = self.group(group)
            groups = {group}
            if group != ALL and target is not None and target.in_all:
                groups.add(ALL)
            excepted = lifted.group(group) or (group != ALL and lifted.group(ALL))
        midnight = dt_util.as_local(end_of_day(now)).isoformat()
        blocked: list[dict[str, Any]] = []
        lifted_holds: list[dict[str, Any]] = []
        for group_id in sorted(groups):
            state = day.limits.get(group_id) if day else None
            if state is not None and state.minutes_left == 0 and not spared:
                hold = {"kind": "budget", "by": group_id, "until": midnight}
                # A category's own bonus left lifts daily time's hold of its apps
                bonus_open = group_id == ALL and bool(self.bonus_groups(person) & groups)
                (lifted_holds if excepted or lifted.group(group_id) or bonus_open else blocked).append(hold)
        for entity_id in (day.locked_by if day else []):
            if entity_id == PAUSE:
                pause = pause_of(self.hass, person, now) or {}
                item = {"kind": "pause", "by": "hearth.pause", "until": pause.get("until"), "reason": pause.get("reason")}
                if ends_on := self.pause_view(person):
                    item["ends_on"] = ends_on
                blocked.append(item)
                continue
            until = lock_until(self.hass, [entity_id])
            blocked.append(
                {
                    "kind": lock_kinds(self.hass, [entity_id])[0],
                    "by": entity_id,
                    "until": dt_util.as_local(until).isoformat() if until else None,
                }
            )
        # An adult's pause of this app or group (or of a group the app is in, or the app of a group asked about)
        asked = {app} if app is not None else set(self._group_apps(target, membership)) if group != ALL and target else set()
        for pause in app_pauses_of(self.hass, person, now):
            if pause["group"] is not None and (pause["group"] == group or pause["group"] in groups):
                hit = True
            elif pause["group"] is not None and app is not None:
                hit = (paused_group := self.group(pause["group"])) is not None and app in self._group_apps(
                    paused_group, membership
                )
            else:
                hit = pause["app"] is not None and (pause["app"] in asked)
            if hit and not spared:
                blocked.append(
                    {
                        "kind": "pause",
                        "by": "hearth.pause",
                        "app": pause["app"],
                        "group": pause["group"],
                        "until": dt_util.as_local(pause["until"]).isoformat(),
                        "reason": pause["reason"],
                    }
                )
        # Google TV's own Kids daily limit: it holds the whole profile, whatever Hearth allows
        for device_id in self.google_tv_limits(person):
            blocked.append(
                {
                    "kind": "google_tv_limit",
                    "by": device_id,
                    "device": self.hub.devices.get(device_id, {}).get("name") or device_id,
                    "until": None,
                }
            )
        # Google's and Microsoft's own limits, and a parent's own Family Safety lock: they stop a device of theirs
        # whatever Hearth allows
        blocked += self.sync.blocked_by(person, midnight)
        # A parent's own Family Link app limit: Hearth's allows and bonuses don't raise it
        if app is not None:
            packages = {app}
        elif group is not None and group != ALL and (target := self.group(group)) is not None:
            packages = set(self._group_apps(target, membership))
        else:
            packages = set()
        blocked += self.sync.app_limits_reached(person, packages, midnight)
        # Hearth's own block of the app (hearth.block_app, or the browser rule): no allow lifts it
        if app is not None:
            blocked += self.blocks.explain(person, app)
        if app is not None:
            for enforcer in enforcers_from_options(self.options):
                if (
                    enforcer.person == person
                    and not spared
                    and app in enforcer.school_apps
                    and self.in_school_time(enforcer)
                ):
                    child = fl.child_of(self.hass, enforcer.entity_id)
                    end = fl.school_time_end(self.hass, child) if child else None
                    hold = {
                        "kind": "school_time_apps",
                        "by": enforcer.entity_id,
                        "until": dt_util.as_local(end).isoformat() if end else None,
                    }
                    (lifted_holds if excepted else blocked).append(hold)
        applying = [
            a
            for a in self.allows.of(person)
            if a.group == ALL
            or (app is not None and (a.app == app or (a.group is not None and a.group in groups)))
            or (group is not None and a.group == group)
        ]
        # A parent's grants: a whole device, Switch or platform; an app only when it's the one asked about
        granted = [
            g.view()
            for g in self.grants.of(person)
            if g.kind != "app" or (app is not None and g.value == app)
        ]
        if blocked:
            ends = [b.get("until") for b in blocked]
            until = None if None in ends else max(ends)
        elif applying:
            until = dt_util.as_local(min(a.until[person] for a in applying)).isoformat()
        else:
            until = None
        # The app's category (its one group besides All screen time) and every group it counts in
        pool = None
        if app is not None:
            pool = next((g for g in sorted(membership(app)) if g != ALL), None)
        time_now = self.time_view(person)
        cap = next((c for c in time_now["categories"] if c["id"] == (pool if app is not None else group)), None)
        return {
            "person": person,
            "app": app,
            "group": pool if app is not None else group,
            "pool": pool if app is not None else (group if group != ALL else None),
            "groups": sorted(groups),
            # Today's time (time_model.py): bonus time left, and the category's raised limit, if any
            "today_left": time_now["today_left"],
            "bonus_left": time_now["bonus_left"],
            "unlimited": time_now["unlimited"],
            "category_limit": cap,
            "raised_limits": [c for c in time_now["categories"] if c["raised"]],
            "origins": time_now["origins"],
            "allowed": not blocked,
            "until": until,
            "blocked_by": blocked,
            "lifted": lifted_holds,
            "exceptions": self.allow_views(person, applying) + granted,
            "school_time_off": self.off_views(person),
            # Extra time on one device (a device's own bonus or allow): that device may go on whatever the pool says
            "device_extras": [
                v for v in self.device_extra_views(person) if v["group"] == ALL or v["group"] in groups
            ],
        }

    # Extra time on one device (device_extra.py)

    def _device_group_seconds(self, person: str, device_id: str, group: str) -> float:
        day = self.days.get(person)
        usage = day.devices.get(device_id) if day else None
        if usage is None:
            return 0.0
        return group_seconds({device_id: usage}, self.membership(), self.outside_all()).get(group, 0.0)

    def _extra_left(self, extra: DeviceExtra, now: datetime | None = None) -> int | None:
        """Minutes left of it: a Hearth device's bonus by what that device used of the group since; a Family Link
        device's bonus is Google's to count (its minutes as given); the rest by the clock."""
        now = now or dt_util.now()
        if extra.kind == EXTRA_BONUS and extra.target.startswith("hearth:"):
            used = self._device_group_seconds(extra.person, extra.target.removeprefix("hearth:"), extra.group)
            return max(0, int((extra.minutes or 0) - (used - extra.base_s) / 60))
        if extra.kind == EXTRA_BONUS and extra.via == "family_link":
            return extra.minutes
        return max(0, int((extra.until - now).total_seconds() // 60))

    def _prune_device_extras(self) -> None:
        self.device_extras.prune()
        for extra in list(self.device_extras.extras.values()):
            if extra.kind == EXTRA_BONUS and extra.target.startswith("hearth:") and self._extra_left(extra) == 0:
                self.device_extras.end(extra.id, None, None)

    def _device_lifted(self, enforcer) -> set[str]:
        """What extra time on one device lifts of an enforcer's holds: a Family Safety platform, the Switch."""
        from .enforce import NINTENDO, SWITCH

        lifted: set[str] = set()
        for extra in self.device_extras.of(enforcer.person):
            if enforcer.kind == FAMILY_SAFETY and extra.target.startswith("fs:"):
                platform = extra.target.removeprefix("fs:").capitalize()
                if platform in enforcer.platforms:
                    lifted.add(platform)
            elif enforcer.kind == NINTENDO and extra.target == f"nintendo:{enforcer.entity_id}":
                lifted.add(SWITCH)
        return lifted

    def device_extra_views(self, person: str) -> list[dict[str, Any]]:
        """[{id, target, name, via, kind (bonus | allow), group, until, minutes_left, reason}]"""
        from .targets import targets_of

        names = {t["id"]: t["name"] for t in targets_of(self, person)}
        return [
            {
                "id": e.id,
                "target": e.target,
                "name": names.get(e.target, e.target),
                "via": e.via,
                "kind": e.kind,
                "group": e.group,
                "until": dt_util.as_local(e.until).isoformat(),
                "minutes_left": self._extra_left(e),
                "reason": e.reason,
            }
            for e in self.device_extras.of(person)
        ]

    def add_device_extra(
        self,
        person: str,
        target: str,
        kind: str,
        group: str,
        minutes: int | None = None,
        until: datetime | None = None,
        reason: str | None = None,
    ) -> DeviceExtra:
        """Extra time for the person on one of their devices: a bonus of [minutes] from now, or an allow of [group]
        until [until]. Only All screen time on a device whose holds are the whole account's (Family Link, Family
        Safety, a Switch)."""
        from homeassistant.exceptions import ServiceValidationError

        from .targets import targets_of

        found = next((t for t in targets_of(self, person) if t["id"] == target), None)
        if found is None:
            raise ServiceValidationError(f"{target} isn't one of {self.person_name(person)}'s devices")
        if group != ALL and not found["groups"]:
            raise ServiceValidationError(
                f"Only All screen time can be given on {found['name']}: what holds a group there holds it on every "
                "device of theirs"
            )
        now = dt_util.now()
        midnight = end_of_day(now)
        base_s = 0.0
        if kind == EXTRA_BONUS:
            if found["via"] == "hearth":
                until = midnight
                base_s = self._device_group_seconds(person, target.removeprefix("hearth:"), group)
            else:
                until = min(now + timedelta(minutes=minutes or 0), midnight)
        extra = self.device_extras.add(person, target, found["via"], kind, group, until, minutes, base_s, reason)
        if kind == EXTRA_BONUS:
            self.history.log(DEVICE_BONUS, person, device=target, group=group, minutes=minutes)
        self.recompute()
        if found["via"] == "family_link":
            self.sync.give_device(person, extra.id, until, target.removeprefix("fl:"), None)
        elif found["via"] == "family_safety":
            self.sync.give_device(person, extra.id, until, None, target.removeprefix("fs:").capitalize())
        return extra

    def end_device_extras(self, extra_id: str | None, people: list[str] | None, target: str | None) -> list[str]:
        ended = self.device_extras.end(extra_id, people, target)
        for extra in ended:
            if extra.via in ("family_link", "family_safety"):
                self.sync.device_ended(extra.person, extra.id)
        if ended:
            self.recompute()
        return [e.id for e in ended]

    @callback
    def end_grant(self, grant_id: str):
        """An adult ends a parent's grant early (hearth.allow_end with its id): Hearth's hold comes back with the next
        recompute; where the grant maps to a first-party write (a Family Link bonus reset, Family Safety extra time
        cancelled) that's done too. None when no grant has that id."""
        grant = self.grants.end(grant_id)
        if grant is not None:
            self.sync.end_grant(grant)
        return grant

    # Changes from services and entities

    def group(self, group_id: str) -> Group | None:
        return next((g for g in self.groups if g.id == group_id), None)

    def apply_time_model(self, person: str, states: dict[str, GroupState], now: datetime) -> None:
        """Today's time, caps and bonus time (time_model.py) over the groups' states as Limits.state gave them: All
        screen time gets today's base and bonus time (an adult's, and every chore minute whatever group its reward
        names), each category the cap in effect (raised or not) and what holds it."""
        all_state = states.get(ALL)
        if all_state is None:
            return
        chores = self.limits.chores_today(person, list(states))
        base, bonus = split_bonus(all_state.budget_min, self.limits.bonus(person, ALL) + chores)
        caps: dict[str, tuple[int | None, float]] = {}
        configured: dict[str, int | None] = {}
        raised: dict[str, Raise] = {}
        for gid, state in states.items():
            if gid == ALL:
                continue
            held = self.limits.raise_of(person, gid, now)
            configured[gid] = state.budget_min
            if held is not None:
                raised[gid] = held
            cap = held.cap(state.budget_min) if held is not None else state.budget_min
            caps[gid] = (cap, state.counted_min)
        # Each category's own bonus (hearth.add_time with a category): spent there first
        outside = self.outside_all()
        cat_bonuses = {
            gid: (own, state.counted_min, gid not in outside)
            for gid, state in states.items()
            if gid != ALL and (own := self.limits.cat_bonus(person, gid)) > 0
        }
        result = account(base, bonus, all_state.counted_min, caps, cat_bonuses)
        # Debug, only when it changed for the person (each recompute would repeat it)
        summary = (base, bonus, int(all_state.counted_min), result.bonus_used, result.today_left,
                   tuple(sorted((g, c, result.cap_left[g]) for g, (c, _) in caps.items() if c is not None)))
        if self._model_logged.get(person) != summary:
            self._model_logged[person] = summary
            _LOGGER.debug(
                "time model %s: base %s, bonus %s, used %s, bonus used %s, today left %s, limits (cap, held left) %s",
                person, *summary,
            )
        all_state.budget_min, all_state.bonus_min, all_state.bonus_chores = base, bonus, chores
        all_state.modeled = True
        all_state.held_left = all_state.usable = result.today_left
        all_state.bonus_left = result.bonus_left
        for gid, (cap, _) in caps.items():
            state = states[gid]
            base_cap = configured[gid]
            state.modeled = True
            state.configured = base_cap
            state.raised = raised.get(gid)
            state.closed = gid in result.closed
            state.bonus_left = 0 if state.closed else result.bonus_left
            if cap is None:
                state.budget_min, state.bonus_min = None, 0
            else:
                state.budget_min = base_cap if base_cap is not None else cap
                state.bonus_min = cap - state.budget_min
            state.held_left = result.cap_left[gid]
            state.usable = result.usable[gid]
            state.cat_bonus = cat_bonuses[gid][0] if gid in cat_bonuses else 0
            state.cat_bonus_left = result.cat_left.get(gid, 0)

    @staticmethod
    def used_minutes(day: PersonDay | None) -> int:
        """Daily time used today in whole minutes, as every view shows it (time.used, the by-category split): a minute
        counts once it's over, as today_left takes it (time_model.account)."""
        return int(math.floor(day.groups.get(ALL, 0.0) / 60)) if day else 0

    def by_category(self, person: str) -> tuple[list[dict[str, Any]], int]:
        """Today's counted minutes split by category, each minute once ([{id, name, minutes}] in the household's
        order, then "other"; together daily time used), and the minutes not counted in daily time (categories
        outside it, Unlimited and allowed windows). The panel's daily-time bar and the device API read the same."""
        day = self.days.get(person)
        if day is None:
            return [], 0
        used = self.used_minutes(day)
        outside = self.outside_all()
        parts: list[dict[str, Any]] = []
        if used > 0:
            # Largest remainders: each part's whole minutes, then the minutes the rounding of the whole leaves go to
            # the parts with the largest fractions, so they add up to daily time used exactly
            total_s = day.groups.get(ALL, 0.0)
            seconds = [
                (g.id, g.name, s)
                for g in self.groups
                if g.id != ALL and g.in_all and g.id not in outside and (s := day.groups.get(g.id, 0.0)) > 0
            ]
            other_s = max(0.0, total_s - sum(s for _, _, s in seconds))
            if other_s > 0:
                seconds.append((OTHER, "Other", other_s))
            whole = [int(s // 60) for _, _, s in seconds]
            spare = used - sum(whole)
            order = sorted(range(len(seconds)), key=lambda i: seconds[i][2] / 60 - whole[i], reverse=True)
            for i in order[: max(0, spare)]:
                whole[i] += 1
            for i in reversed(order):
                # (the rounding of the whole down: the smallest fractions give a minute back)
                if spare >= 0:
                    break
                if whole[i] > 0:
                    whole[i] -= 1
                    spare += 1
            parts = [
                {"id": gid, "name": name, "minutes": m} for (gid, name, _), m in zip(seconds, whole, strict=True) if m > 0
            ]
        not_in_day = sum(
            day.groups.get(g.id, 0.0) for g in self.groups if g.id != ALL and (g.id in outside or not g.in_all)
        )
        unlimited = max(0.0, (day.raw_groups or day.groups).get(ALL, 0.0) - day.groups.get(ALL, 0.0))
        return parts, int(round((not_in_day + unlimited) / 60))

    def time_view(self, person: str) -> dict[str, Any]:
        """Today's time as people are shown it, for screens and the device API (docs/contracts/time-model.md):
        {today_left, today_minutes, base_minutes, bonus, bonus_left, used, unlimited {until, open, include_bedtime,
        text} | None, unlimited_today [{start, end, minutes, text}], text (the kid's line), adult_text,
        categories [{id, name, limit, limit_today, raised, until, left, used, text, limit_text}]} (time_model.py).
        "left" is what can actually be used (a category's never more than today's time left)."""
        day = self.days.get(person)
        all_state = day.limits.get(ALL) if day else None
        unlimited = self.unlimited.view(person)
        active = unlimited["active"]
        today_left = all_state.shown_left if all_state else None
        bonus_left = all_state.bonus_left if all_state else 0
        categories = []
        for group in self.groups:
            state = day.limits.get(group.id) if day else None
            if group.id == ALL or state is None or not (
                state.budget_min is not None or state.raised is not None or state.cat_bonus
            ):
                continue
            limit_today = None if state.budget_min is None else state.budget_min + state.bonus_min
            raised = state.raised is not None
            categories.append(
                {
                    "id": group.id,
                    "name": group.name,
                    # The limit an adult set for today's kind of day (None: no limit), and today's (raised or not)
                    "limit": state.configured,
                    "limit_today": limit_today,
                    "raised": raised,
                    # Its limit today is 0: bonus time doesn't open it (only its own bonus, a raise or Unlimited)
                    "closed": state.closed,
                    "until": state.raised.until if raised else None,
                    "left": state.shown_left,
                    "used": int(state.counted_min),
                    "text": None if active else category_text(
                        group.name, state.shown_left, today_left, state.cat_bonus_left, state.closed
                    ),
                    "limit_text": limit_text(group.name, state.configured, limit_today, raised),
                    "bonus": state.cat_bonus,
                    "bonus_left": state.cat_bonus_left,
                    "origin": self.latest_origin(person, "raise", group.id) if raised else None,
                }
            )
        return {
            "today_left": today_left,
            "today_minutes": (
                None if not all_state or all_state.budget_min is None else all_state.budget_min + all_state.bonus_min
            ),
            "base_minutes": all_state.budget_min if all_state else None,
            "bonus": all_state.bonus_min if all_state else 0,
            "bonus_left": bonus_left,
            # The latest bonus time given today (its origin, for the status line's link to "where it came from")
            "bonus_origin": self.latest_origin(person, "bonus"),
            # Whole minutes, rounded as by_category rounds them: the split adds up to it exactly
            "used": self.used_minutes(day),
            "unlimited": {**active, "origin": self.latest_origin(person, "unlimited")} if active else None,
            "unlimited_today": unlimited["today"],
            "text": today_text(today_left, bonus_left, active["text"] if active else None),
            "adult_text": today_text(today_left, bonus_left, active["text"] if active else None, adult=True),
            "categories": categories,
            # Today's counted minutes by category, each once (they add up to daily time used), and the minutes not
            # counted in daily time apart
            "by_category": (split := self.by_category(person))[0],
            "uncounted": split[1],
            # Categories with their own bonus today ("+15 min Messaging bonus"), with or without a limit
            "category_bonuses": [
                {
                    "id": g.id,
                    "name": g.name,
                    "bonus": s.cat_bonus,
                    "bonus_left": s.cat_bonus_left,
                    "origin": self.latest_origin(person, "bonus", g.id),
                    "left": s.shown_left,
                    "text": f"{g.name}: {say_minutes(s.cat_bonus_left)} bonus left" if s.cat_bonus_left else f"{g.name}: bonus used",
                }
                for g in self.groups
                if g.id != ALL and day and (s := day.limits.get(g.id)) is not None and s.cat_bonus
            ],
            # Where today's statuses came from (bonus time, raised limits, Unlimited, Pause screens), newest first
            "origins": self.origins_of(person),
        }

    @callback
    def note_origin(
        self, person: str, kind: str, detail: str, source: str = "hearth", by: str | None = None, **about: Any
    ) -> dict[str, Any]:
        """Where one of today's changes came from (kind: bonus, raise, unlimited, pause, daily_time; source: hearth,
        family_link, family_safety, nintendo, chore, ask; by: an adult's name when known), for the "?" on a status
        line: {id (stable), kind, source, by, at, detail, ...}; origins_of adds text, endable and end."""
        now = dt_util.now()
        record = {
            "id": secrets.token_hex(6), "kind": kind, "source": source, "by": by, "at": now.isoformat(), "detail": detail,
            **about,
        }
        self.limits.add_origin(person, record)
        return record

    def origins_of(self, person: str) -> list[dict[str, Any]]:
        """Today's origins of the person's statuses, newest first, each with its text, and whether it can be ended:
        {endable, end: {service: hearth.end_grant, data: {origin_id}} | None}: ending one ends exactly that grant
        (a bonus's unused part, a raise, an Unlimited grant, a chore's reward, Pause screens)."""
        out = []
        for record in reversed(self.limits.data.origins.get(person, [])):
            at = dt_util.parse_datetime(record.get("at") or "")
            local = dt_util.as_local(at) if at else None
            origin_id = record.get("id") or f"{record.get('kind')}:{record.get('at')}"
            endable = self._endable(person, {**record, "id": origin_id})
            ended_at, ended_by = (None, None) if endable else self._ended(person, {**record, "id": origin_id})
            out.append(
                {
                    **record,
                    "id": origin_id,
                    "text": origin_text(
                        record.get("detail") or "", record.get("source") or "hearth", record.get("by"),
                        say_clock(local.hour, local.minute) if local else None,
                    ),
                    "endable": endable,
                    "end": {"service": "hearth.end_grant", "data": {"origin_id": origin_id}} if endable else None,
                    # Ended (ISO; by: the adult's name when known): a client drops or strikes it. A bonus that was
                    # only spent isn't ended (spent time stays given)
                    "ended_at": ended_at,
                    "ended_by": ended_by,
                }
            )
        return out

    def _endable(self, person: str, record: dict[str, Any]) -> bool:
        """Whether something of an origin's change can still be ended now (hearth.end_grant). An ended one never is
        again."""
        now = dt_util.now()
        if record.get("ended_at"):
            return False
        grant = self.limits.grant(person, record["id"])
        if grant is not None:
            if grant.get("ended"):
                return False
            if grant["kind"] == "bonus":
                return self._bonus_unused(person, grant) > 0
            return grant in self.limits.grants(person, grant["kind"], now=now)
        if record.get("kind") == "bonus" and record.get("source") == "chore" and record.get("chore"):
            entry = next((e for e in self.todos.ledger if e.get("key") == record["chore"]), None)
            return entry is not None and not entry.get("reversed_at")
        if record.get("kind") == "pause":
            # Only the pause that's on: an earlier one it replaced is over
            return pause_of(self.hass, person, now) is not None and record["id"] == self.latest_origin(person, "pause")
        return False

    def _ended(self, person: str, record: dict[str, Any]) -> tuple[str | None, str | None]:
        """When an origin that can't be ended any more was ended (ISO, local) and by whom (an adult's name, None when
        not known or when its time ran out); (None, None) while its change is still in effect (a bonus spent)."""
        if record.get("ended_at"):
            return record["ended_at"], record.get("ended_by")
        now = dt_util.now()

        def iso(value: str | None) -> str | None:
            parsed = dt_util.parse_datetime(value or "")
            return dt_util.as_local(parsed).isoformat() if parsed else None

        grant = self.limits.grant(person, record["id"])
        if grant is not None:
            until = dt_util.parse_datetime(grant.get("until") or "")
            ended = dt_util.parse_datetime(grant.get("ended") or "")
            if grant["kind"] != "bonus" and until is not None and until <= (ended or now):
                return iso(grant["until"]), None
            return (iso(grant["ended"]) if ended else None), None
        if record.get("kind") == "bonus" and record.get("source") == "chore" and record.get("chore"):
            entry = next((e for e in self.todos.ledger if e.get("key") == record["chore"]), None)
            return (iso(entry.get("reversed_at")) if entry and entry.get("reversed_at") else None), None
        if record.get("kind") == "pause":
            # Its time ran out, or a later pause took its place
            until = dt_util.parse_datetime(record.get("until") or "")
            if until is not None and until <= now:
                return iso(record["until"]), None
            later = None
            seen = False
            for other in self.limits.data.origins.get(person, []):
                if seen and other.get("kind") == "pause":
                    later = other
                    break
                seen = seen or other.get("id") == record["id"]
            return (iso(later.get("at")) if later else now.isoformat()), None
        return None, None

    def _over(self, person: str, record: dict[str, Any]) -> bool:
        """An origin whose change was ended (or ran out): a status line no longer links to it."""
        if record.get("ended_at"):
            return True
        grant = self.limits.grant(person, record.get("id") or "")
        if grant is None:
            return False
        if grant.get("ended"):
            return True
        return grant["kind"] != "bonus" and grant not in self.limits.grants(person, grant["kind"], now=dt_util.now())

    def latest_origin(self, person: str, kind: str, group: str | None = None) -> str | None:
        """The id of the latest origin of [kind] (and [group]) today that's still in effect, for a status line's link
        to its origin (after the latest of two Unlimited grants ends, the one still on)."""
        for record in reversed(self.limits.data.origins.get(person, [])):
            if record.get("kind") == kind and record.get("group") == group and record.get("id"):
                if self._over(person, record):
                    continue
                return record["id"]
        return None

    def end_pause_now(self, people: list[str] | None, by: str | None = None) -> None:
        """Pause screens end now for the people (None: everyone): the pause that was on is noted as ended (by [by])."""
        for person in people if people is not None else self.people():
            if pause_of(self.hass, person) is not None and (origin := self.latest_origin(person, "pause")):
                self.limits.end_origin(person, origin, by)
        end_pause(self.hass, people)

    def person_of_origin(self, origin_id: str) -> str | None:
        """Whose origin (or grant) [origin_id] is."""
        for person, records in self.limits.data.origins.items():
            if any(r.get("id") == origin_id for r in records):
                return person
        return next((p for p in self.limits.data.grants if self.limits.grant(p, origin_id)), None)

    def bonus_groups(self, person: str) -> set[str]:
        """The categories with their own bonus left today (hearth.add_time with a category)."""
        day = self.days.get(person)
        return {gid for gid, s in (day.limits.items() if day else []) if gid != ALL and s.cat_bonus_left > 0}

    def budget_lifted(self, person: str) -> Lifted:
        """What lifts a budget hold for the person: their allows, and each category with its own bonus left (its apps
        run past daily time and its limit). Never bedtime, School time or a pause."""
        lifted = self.allows.lifted(person)
        extra = self.bonus_groups(person)
        groups = set(lifted.groups) | extra
        return Lifted(lifted.everything, groups, set(lifted.apps), self.open_groups(person, groups))

    def open_groups(self, person: str, candidates: set[str] | None = None) -> set[str]:
        """Of the categories open past daily time for the person (their own bonus left, an allow of them), the ones
        that may keep Family Link's devices unlocked (every other app paused instead): spendable (in daily time, or
        with a limit) and with an app of it installed on the kid's devices. Otherwise the whole-device lock stays."""
        if candidates is None:
            candidates = set(self.allows.lifted(person).groups) | self.bonus_groups(person)
        candidates = {g for g in candidates if g != ALL}
        if not candidates:
            return set()
        child = self.family_link_child(person)
        installed = fl.installed_apps(self.hass, child) if child else None
        if not installed:
            return set()
        day = self.days.get(person)
        outside = self.outside_all()
        membership = self.membership()
        found = set()
        for gid in candidates:
            state = day.limits.get(gid) if day else None
            spendable = gid not in outside or (state is not None and state.budget_min is not None)
            if spendable and any(gid in membership(p) for p in installed):
                found.add(gid)
        return found

    def open_left(self, person: str, group: str, now: datetime | None = None) -> int:
        """The minutes an open category has left past daily time: its own bonus left, or an allow's minutes to its
        end (the longer)."""
        now = now or dt_util.now()
        day = self.days.get(person)
        state = day.limits.get(group) if day else None
        own = state.cat_bonus_left if state else 0
        ends = [a.until[person] for a in self.allows.of(person) if a.group == group and a.until.get(person, now) > now]
        allow = int((max(ends) - now).total_seconds() // 60) if ends else 0
        return max(own, allow)

    def person_of_user(self, user_id: str | None) -> str | None:
        """The person entity whose Home Assistant user this is (the action log's "by": an id, never a name)."""
        if not user_id:
            return None
        return next(
            (s.entity_id for s in self.hass.states.async_all("person") if s.attributes.get("user_id") == user_id), None
        )

    def name_of_user(self, user_id: str | None) -> str | None:
        """The name of the person whose Home Assistant user this is (an adult's, for an origin's "by")."""
        if not user_id:
            return None
        for state in self.hass.states.async_all("person"):
            if state.attributes.get("user_id") == user_id:
                return state.name
        return None

    def no_limits_until(self, person: str) -> datetime | None:
        """When the person's unlimited time ends (unlimited.py), None while it isn't on."""
        window = self.unlimited.active(person)
        return dt_util.parse_datetime(window["until"]) if window else None

    @callback
    def add_time(
        self,
        person: str,
        minutes: int,
        reason: str | None = None,
        via: str | None = None,
        by: str | None = None,
        category: str | None = None,
    ) -> None:
        """Bonus time today (hearth.add_time): a grant of its own, no category, spent anywhere. Google's and
        Microsoft's own limits get as much (each grant), and given in bedtime it lifts it. [via]: ask, day_off or none
        (an adult); [by]: the adult's name, for its origin. With a [category]: a bonus for that category only ("+15
        min Messaging bonus"), usable there past daily time and its limit, spent before the general bonus. A negative
        [minutes] (hearth.add_bonus's older "take away") lowers today's adjustment instead of a grant."""
        if category is not None and category != ALL:
            self._add_category_bonus(person, category, minutes, reason, by)
            return
        if minutes > 0:
            grant = self.limits.add_grant(person, "bonus", None, minutes)
        elif minutes < 0:
            # hearth.add_bonus's older "take away": takes bonus given back, newest grant first; never daily time
            self.remove_bonus(person, ALL, -minutes)
            return
        else:
            self.recompute()
            return
        fields = {k: v for k, v in (("reason", reason), ("via", via)) if v}
        self.history.log(BONUS, person, group=ALL, minutes=minutes, **fields)
        detail = f"Bonus {'+' if minutes > 0 else '−'}{abs(minutes)}"
        if via == "day_off":
            detail += " (day off)"
        if reason:
            detail += f" · {reason}"
        about = {"id": grant["id"]} if grant else {}
        self.note_origin(person, "bonus", detail, "ask" if via == "ask" else "hearth", by, minutes=minutes, **about)
        in_bedtime = minutes > 0 and self.in_bedtime(person)
        self.recompute()
        if minutes > 0:
            self.sync.mirror_bonus(person)
            if in_bedtime:
                self._lift_bedtime(person, minutes)

    def _add_category_bonus(self, person: str, category: str, minutes: int, reason: str | None, by: str | None) -> None:
        if minutes <= 0:
            return
        grant = self.limits.add_grant(person, "bonus", category, minutes)
        fields = {"reason": reason} if reason else {}
        self.history.log(BONUS, person, group=category, minutes=minutes, category=True, **fields)
        target = self.group(category)
        detail = f"{target.name if target else category} bonus +{minutes}" + (f" · {reason}" if reason else "")
        self.note_origin(person, "bonus", detail, "hearth", by, minutes=minutes, group=category, id=grant["id"])
        self.recompute()
        # The phone mustn't lock before it's used: Family Link and Family Safety get as much
        self.sync.mirror_bonus(person)

    @callback
    def remove_time(self, person: str, minutes: int, category: str | None = None) -> int:
        """Takes back up to [minutes] of the bonus time given today (hearth.remove_time), newest grant first; of one
        category's bonus with [category]. Never more than the grants give: daily time itself is never cut. The
        minutes taken back."""
        if category is None or category == ALL:
            return self.remove_bonus(person, ALL, minutes)
        taken = self.limits.take_back(person, category, minutes)
        if taken:
            self.history.log(BONUS, person, group=category, minutes=-taken, category=True, undo=True)
            self.recompute()
        return taken

    @callback
    def raise_cap(
        self,
        person: str,
        group: str,
        minutes: int | None = None,
        to: int | None = None,
        no_cap: bool = False,
        until: datetime | None = None,
        by: str | None = None,
    ) -> Raise:
        """A category's limit today, raised (hearth.raise_cap): a grant of its own, by [minutes] (raises "by" add up),
        to [to] minutes or no limit at all (a floor: the highest wins), until [until] (None: the end of the day).
        Daily time is unchanged. The raise in effect now."""
        stamp = dt_util.as_local(until).isoformat() if until is not None else None
        grant = self.limits.add_grant(
            person, "raise", group, 0 if (no_cap or to is not None) else int(minutes or 0),
            None if no_cap or to is None else int(to), bool(no_cap), stamp,
        )
        self.history.log(
            RAISE, person, group=group,
            **{k: v for k, v in (("minutes", minutes), ("to", to), ("no_cap", no_cap or None), ("until", stamp)) if v is not None},
        )
        name = self.group(group).name if self.group(group) else group
        what = "no limit" if no_cap else f"limit {say_minutes(to)}" if to is not None else f"limit +{minutes or 0}"
        self.note_origin(person, "raise", f"{name}: {what} today", "hearth", by, group=group, id=grant["id"])
        self.recompute()
        return self.limits.raise_of(person, group, dt_util.now()) or Raise()

    @callback
    def raise_cap_end(self, person: str, group: str | None = None) -> list[str]:
        """Every raise of [group] (every category's: None) ends now (hearth.raise_cap_end); the categories."""
        ended = self.limits.end_raises(person, group)
        for gid in ended:
            self.history.log(RAISE, person, group=gid, ended=True)
        if ended:
            self.recompute()
        return ended

    @callback
    def start_unlimited(
        self,
        people: list[str],
        until: dict[str, datetime],
        include_bedtime: bool = False,
        open_ended: bool = False,
        reason: str | None = None,
        by: str | None = None,
    ):
        """Unlimited (hearth.unlimited): a grant of its own, until [until] (at midnight at the latest): nothing Hearth
        holds for daily time or a category's limit holds the people, and the time they use isn't counted
        (unlimited.py). Another while one runs extends it (on until the latest end of the grants left). Bedtime,
        School time and Pause screens still lock, but bedtime not with [include_bedtime]. The allow it is."""
        allowed = self.allows.add(until, None, ALL, reason or "Unlimited")
        for person in people:
            grant = self.limits.add_grant(
                person, "unlimited", None, until=until[person].isoformat(), open=open_ended, allow=allowed.id,
                include_bedtime=include_bedtime,
            )
            self.unlimited.start(person, allowed.id, until[person], open_ended, include_bedtime)
            if include_bedtime:
                self.bedtime_lift.give(person, 0, until=until[person])
            local = dt_util.as_local(until[person])
            detail = "Unlimited" + ("" if open_ended else f" until {say_clock(local.hour, local.minute)}")
            if reason:
                detail += f" · {reason}"
            self.note_origin(person, "unlimited", detail, "hearth", by, id=grant["id"])
        self.recompute()
        return allowed

    @callback
    def end_unlimited(self, people: list[str] | None, by: str | None = None) -> list[str]:
        """The people's unlimited time ends now, every grant of it (hearth.unlimited_end): limits are back on where
        they were when it started. The people it ended for."""
        ended: list[str] = []
        for person in people or self.people():
            grants = self.limits.grants(person, "unlimited")
            running = [g["id"] for g in self.limits.grants(person, "unlimited", now=dt_util.now())]
            for grant in grants:
                self.limits.end_grant(person, grant["id"])
                if grant["id"] in running:
                    # One whose time had run out ended then, not now
                    self.limits.end_origin(person, grant["id"], by)
                if grant.get("allow"):
                    self.allows.end_for(grant["allow"], person)
            window = self.unlimited.end(person)
            if window is None and not grants:
                continue
            ended.append(person)
            if window is not None:
                self.allows.end_for(window["allow"], person)
            if (self.bedtime_lift.lifts.get(person) or {}).get("no_limits"):
                self.bedtime_lift.end(person)
        if ended:
            self.recompute()
            self.sync.allow_ended()
        return ended

    def _bonus_unused(self, person: str, grant: dict[str, Any]) -> int:
        """What of a bonus grant isn't spent yet: the bonus spent today is put on the oldest givers first (chores and
        an older adjustment, then the grants by age), so this grant's unused part is what's left of it after them."""
        day = self.days.get(person)
        group = grant.get("group")
        state = day.limits.get(group or ALL) if day else None
        if state is None:
            return self.limits.given(grant)
        if group:
            total, left = self.limits.cat_bonus(person, group), state.cat_bonus_left
        else:
            total, left = state.bonus_min, state.bonus_left
        spent = max(0, total - left)
        grants = self.limits.grants(person, "bonus", group)
        others = total - sum(self.limits.given(g) for g in grants)
        spent -= min(spent, max(0, others))
        # Never more than the net bonus given (an older lowered adjustment may have cut it): daily time stays
        net = max(0, self.limits.cat_bonus(person, group) if group else self.limits.bonus(person, ALL))
        for g in grants:
            share = min(spent, self.limits.given(g))
            if g["id"] == grant["id"]:
                return max(0, min(self.limits.given(g) - share, net))
            spent -= share
        return 0

    @callback
    def end_time_grant(self, person: str, origin_id: str, by: str | None = None) -> dict[str, Any] | None:
        """hearth.end_grant: ends exactly the change [origin_id] made (an origin's id): a bonus's unused part goes, a
        raise or an Unlimited grant ends (the others stay in effect), a chore's reward is undone, Pause screens end.
        What it did, None when there's nothing of it left to end. One ended stays ended ([by]: who ended it): it never
        takes again, whatever is given after it."""
        record = next((o for o in self.limits.data.origins.get(person, []) if o.get("id") == origin_id), None)
        if not self._endable(person, record or {"id": origin_id}):
            return None
        done = self._end_time_grant(person, origin_id, by)
        if done is not None:
            self.limits.end_origin(person, origin_id, by)
        return done

    def _end_time_grant(self, person: str, origin_id: str, by: str | None) -> dict[str, Any] | None:
        grant = self.limits.grant(person, origin_id)
        now = dt_util.now()
        if grant is not None:
            kind = grant["kind"]
            if kind == "bonus":
                unused = self._bonus_unused(person, grant)
                if unused <= 0:
                    return None
                self.limits.end_grant(person, origin_id, unused)
                self.history.log(BONUS, person, group=grant.get("group") or ALL, minutes=-unused, undo=True)
                if not grant.get("group"):
                    # As remove_time: its bedtime lift is that much shorter, and Family Link and Family Safety lose
                    # what Hearth gave for it once daily time is none again
                    self.bedtime_lift.take(person, unused)
                self.recompute()
                if not grant.get("group"):
                    day = self.days.get(person)
                    state = day.limits.get(ALL) if day else None
                    if state is not None and state.minutes_left == 0:
                        self.sync.take_back_bonus(person)
                return {"kind": "bonus", "taken": unused}
            if grant.get("ended") or (kind != "bonus" and grant not in self.limits.grants(person, kind, now=now)):
                return None
            self.limits.end_grant(person, origin_id)
            if kind == "raise":
                self.history.log(RAISE, person, group=grant.get("group"), ended=True)
                self.recompute()
                return {"kind": "raise", "group": grant.get("group")}
            if kind == "unlimited":
                if grant.get("allow"):
                    self.allows.end_for(grant["allow"], person)
                left = self.limits.grants(person, "unlimited", now=now)
                if left:
                    ends = [dt_util.parse_datetime(g["until"]) for g in left if g.get("until")]
                    self.unlimited.extend_to(person, max(ends) if ends else None, any(g.get("open") for g in left))
                else:
                    window = self.unlimited.end(person)
                    if window is not None:
                        self.allows.end_for(window["allow"], person)
                    if (self.bedtime_lift.lifts.get(person) or {}).get("no_limits"):
                        self.bedtime_lift.end(person)
                self.recompute()
                self.sync.allow_ended()
                return {"kind": "unlimited", "still_on": bool(left)}
            return None
        origin = next((o for o in self.limits.data.origins.get(person, []) if o.get("id") == origin_id), None)
        if origin is None:
            return None
        if origin.get("kind") == "bonus" and origin.get("source") == "chore" and origin.get("chore"):
            self.todos.undo(origin["chore"], None)
            return {"kind": "chore"}
        if origin.get("kind") == "pause" and pause_of(self.hass, person, now) is not None:
            self.end_pause_now([person], by)
            self.recompute()
            return {"kind": "pause"}
        return None

    @callback
    def add_bonus(self, person: str, group: str, minutes: int, by: str | None = None) -> None:
        """hearth.add_bonus, kept: daily time's (or none) is bonus time; a category's raises its limit by as many
        minutes today (a raise grant; negative lowers it)."""
        if group == ALL:
            self.add_time(person, minutes, by=by)
            return
        if not minutes:
            # Nothing to give: a recompute all the same (older automations call it so)
            self.recompute()
            return
        grant = self.limits.add_grant(person, "raise", group, int(minutes))
        self.history.log(RAISE, person, group=group, minutes=minutes)
        name = self.group(group).name if self.group(group) else group
        self.note_origin(person, "raise", f"{name}: limit {minutes:+d} today", "hearth", by, group=group, id=grant["id"])
        self.recompute()

    def _lift_bedtime(self, person: str, minutes: int) -> None:
        """Extra time given in bedtime lifts it while it lasts, when the kid then has All screen time to use."""
        day = self.days.get(person)
        state = day.limits.get(ALL) if day else None
        left = state.minutes_left if state else None
        lift = lift_minutes(minutes, left)
        if lift <= 0:
            return
        self.bedtime_lift.give(person, lift)
        self.recompute()

    @callback
    def remove_bonus(self, person: str, group: str, minutes: int) -> int:
        """Takes back up to [minutes] of the extra time given [person]'s group today (an undo, hearth.remove_bonus
        and remove_time): never more than was given, so it never takes their own daily time (and chores' minutes
        stay); bonus time newest grant first. Logged as a negative bonus. When daily time is none again, what Hearth
        gave for it in Family Link and Family Safety goes too. The minutes taken back."""
        if group == ALL:
            taken = self.limits.take_back(person, None, minutes)
        else:
            given = max(0, self.limits.bonus(person, group))
            taken = max(0, min(int(minutes), given))
            if taken:
                self.limits.set_bonus(person, group, given - taken)
        if not taken:
            return 0
        # A category's: its raised limit is that much lower again (hearth.add_bonus with a group raised it)
        self.history.log(BONUS if group == ALL else RAISE, person, group=group, minutes=-taken, undo=True)
        if group == ALL:
            # Its bedtime lift is that much shorter too
            self.bedtime_lift.take(person, taken)
        self.recompute()
        day = self.days.get(person)
        state = day.limits.get(ALL) if day else None
        if group == ALL and state is not None and state.minutes_left == 0:
            self.sync.take_back_bonus(person)
        return taken

    @callback
    def set_bonus(self, person: str, group: str, minutes: int) -> None:
        self.limits.set_bonus(person, group, minutes)
        self.recompute()

    @callback
    def set_budget(self, person: str, group: str, kind: str, minutes: int | None) -> None:
        self.limits.set_budget(person, group, kind, minutes)
        self.recompute()

    @callback
    def import_local_rules(self, device_id: str, rules: dict[str, dict[str, dict[str, int]]] | None) -> list[str]:
        """A TV's own rules from before it was paired (status "local_rules"): each kids profile's, once mapped to a
        kid, become that kid's budgets when the kid has none yet. Once per TV and profile; bedtime isn't taken (Home
        Assistant's are lock entities). Returns the people whose budgets were set."""
        taken: list[str] = []
        groups = {group.id for group in self.groups}
        roles = self.options.get(CONF_ROLES, {})
        for profile_id, budgets in (rules or {}).items():
            person = self.profile_person(device_id, profile_id)
            if person is None or roles.get(person) == "adult":
                continue
            if self.limits.take_rules(f"{device_id}:{profile_id}", person, budgets, groups):
                taken.append(person)
        if taken:
            self.recompute()
            names = ", ".join(
                (state.name if (state := self.hass.states.get(p)) else p) for p in taken
            )
            self.hub.attention.notify(
                Item(
                    f"hearth_rules_{device_id}",
                    f"Hearth took the screen time set on a TV as the first daily limits for {names}. Change them on "
                    "Hearth's page. Bedtime set on the TV isn't taken: set it under Locks.",
                    title="Screen time from the TV",
                    bell=True,
                    phone=False,
                )
            )
        return taken


def _status_media(status: dict[str, Any]) -> dict[str, Any] | None:
    """What a Hearth device's own media session says is on (status.py: media_title, media_artist, and from newer
    builds media_duration_s with media_position_s as of media_position_at), while it plays or is paused."""
    title = status.get("media_title")
    if not title or status.get("state") not in ("playing", "paused"):
        return None
    artist = status.get("media_artist")
    at = status.get("media_position_at")
    when = dt_util.utc_from_timestamp(at / 1000) if isinstance(at, int) else None
    return {
        "kind": "music" if artist else "video",
        "title": title,
        "artist": artist,
        **_timing(status.get("media_duration_s"), status.get("media_position_s"), when),
        "paused": status.get("state") == "paused",
    }


def _timing(duration: Any, position: Any, at: datetime | None) -> dict[str, Any]:
    """A play's length and position (seconds), when the player gives a usable length; else none of them."""
    if isinstance(duration, bool) or not isinstance(duration, (int, float)) or duration <= 0:
        return {}
    if isinstance(position, bool) or not isinstance(position, (int, float)) or position < 0 or at is None:
        return {"duration_s": float(duration)}
    return {"duration_s": float(duration), "position_s": min(float(position), float(duration)), "position_at": at}


def person_identifier(person: str) -> tuple[str, str]:
    return (DOMAIN, f"person:{person}")


def _say_clock(value: datetime) -> str:
    """"5 PM", "8:30 PM"."""
    hour, minute = value.hour, value.minute
    return f"{hour % 12 or 12}{f':{minute:02d}' if minute else ''} {'AM' if hour < 12 else 'PM'}"


def _clock_of(value: Any) -> time | None:
    """A lock entity's bedtime_start or bedtime_end as a clock time: an ISO time with a date (its local clock), or a
    time of day ("21:00:00")."""
    if not isinstance(value, str) or not value:
        return None
    if (parsed := dt_util.parse_datetime(value)) is not None:
        if parsed.tzinfo is not None:
            parsed = dt_util.as_local(parsed)
        return parsed.time().replace(second=0, microsecond=0)
    if (clock := dt_util.parse_time(value)) is not None:
        return clock.replace(second=0, microsecond=0)
    return None
