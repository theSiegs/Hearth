"""People, their screen time today, and their limits: from what the household's devices post and the screen time
sources it adds.

The people are Home Assistant persons the household maps to (options): each TV profile, each phone, each source. A
person's day is counted from the devices and sources (counting.py), live play is timed and "together" seen (live.py),
time is set against the budgets of each group (limits.py), and what each device is told (its state document) comes
from here.
"""

from __future__ import annotations

from dataclasses import dataclass, field
from datetime import date
import hashlib
import json
from typing import TYPE_CHECKING, Any

from homeassistant.core import HomeAssistant, callback
from homeassistant.helpers import entity_registry as er
from homeassistant.helpers.dispatcher import async_dispatcher_send
from homeassistant.util import dt as dt_util

from .const import (
    CONF_KIND,
    CONF_LOCKS,
    CONF_PERSON,
    CONF_PROFILES,
    CONF_ROLES,
    CONF_TILE_EXCHANGE,
    CONTRACT,
    DOMAIN,
    EVENT_BUDGET_REACHED,
    EVENT_PLAYING_TOGETHER,
    KIND_TV,
    SIGNAL_PEOPLE,
)
from .apps import (
    CONF_APP_WATCH,
    CONF_ASK_NOTIFY,
    EVENT_NEW_APP,
    AppCatalog,
    observed_from_entities,
    options_with_app_in_group,
    phone_actions,
    update_notification,
)
from .counting import ALL, DeviceUsage, Reading, group_seconds, merge
from .limits import CONF_APP_GROUPS, OTHER, OTHER_DAY, SCHOOL_DAY, Group, GroupState, Limits, groups_from_options, groups_of
from .enforce import FAMILY_LINK, FAMILY_SAFETY, Enforcement, enforcers_from_options, fs_account_of, fs_app, fs_app_platform
from .exceptions import Allows, Lifted, end_of_day
from .grants import Grants
from .native_sync import NativeSync
from . import family_link as fl
from .chores import ChoreWatcher
from .schedule import Scheduler
from .watch import WatchLog
from .pause import PAUSE, lock_kinds, lock_until, next_lock, pause_of
from . import parent_pin
from .media import media_rooms
from .profiles import REF_PREFIX, is_ref, split_tv_key, tv_key
from .schooldays import SchoolDays
from .live import LiveTracker, Observation, Together
from .sources import (
    Source,
    Title,
    device_key,
    now_playing,
    sources_from_options,
    title_key,
    titles_from_options,
    totals_reading,
)

if TYPE_CHECKING:
    from .hub import HearthHub

SOURCE_HEARTH = "hearth"


@dataclass
class Playing:
    app: str | None
    package: str | None
    device: str
    state: str | None


@dataclass
class PersonDay:
    person: str
    devices: dict[str, DeviceUsage] = field(default_factory=dict)
    groups: dict[str, float] = field(default_factory=dict)  # seconds
    limits: dict[str, GroupState] = field(default_factory=dict)
    playing: list[Playing] = field(default_factory=list)
    together_s: float = 0.0
    # A lock entity of theirs is on (Family Link's bedtime or school time, say)
    locked: bool = False
    locked_by: list[str] = field(default_factory=list)

    @property
    def total_s(self) -> float:
        return self.groups.get(ALL, 0.0)


class Household:
    def __init__(self, hass: HomeAssistant, hub: HearthHub) -> None:
        self.hass = hass
        self.hub = hub
        self.limits = Limits(hass, hub.entry.entry_id)
        self.live = LiveTracker(hass, hub.entry.entry_id)
        self.apps = AppCatalog(hass, hub.entry.entry_id)
        self.school = SchoolDays(hass)
        self.school.configure(dict(hub.entry.options))
        self.enforcement = Enforcement(hass, hub.entry.entry_id)
        self.watch = WatchLog(hass, hub.entry.entry_id)
        self.allows = Allows(hass, hub.entry.entry_id)
        self.grants = Grants(hass, hub.entry.entry_id)
        self.sync = NativeSync(hass, self)
        self.scheduler = Scheduler(hass, self, hub.entry.entry_id)
        self.chores = ChoreWatcher(hass, self)
        self.days: dict[str, PersonDay] = {}
        # The day [days] is of
        self.today: date | None = None
        # Each totals source's last reading today, which counts while its sensor has no number (unavailable)
        self._last_totals: dict[str, tuple[date, Reading]] = {}
        self.groups: list[Group] = []
        self.sources: list[Source] = []
        self.titles: list[Title] = []
        self.categories: dict[str, str] = {}
        # Groups an item is in because of where its time came from (a Switch's titles are games)
        self._hints: dict[str, set[str]] = {}

    async def async_load(self) -> None:
        await self.limits.async_load()
        await self.live.async_load()
        await self.apps.async_load()
        await self.enforcement.async_load()
        await self.watch.async_load()
        await self.allows.async_load()
        await self.grants.async_load()
        await self.scheduler.async_load()

    async def async_flush(self) -> None:
        await self.limits.async_flush()
        await self.live.async_flush()
        await self.enforcement.async_flush()
        await self.watch.async_flush()
        await self.allows.async_flush()
        await self.grants.async_flush()
        await self.scheduler.async_flush()

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
        playing = [e for enforcer in enforcers_from_options(self.options) for e in enforcer.playing]
        return (
            [s.entity_id for s in sources_from_options(self.options)]
            + locks
            + watched
            + playing
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

    def _lock_entities(self, person: str) -> list[str]:
        return [lock["entity_id"] for lock in self.options.get(CONF_LOCKS, []) if lock.get("person") == person]

    def _locks_document(self, person: str, day: PersonDay | None) -> dict[str, Any]:
        """Why and until when the person is held ("lock" {by, until}), a family pause ("pause" {until, reason}), and
        the next bedtime or school time ("next_lock" {at, by, kind}), for winding down before it."""
        out: dict[str, Any] = {}
        pause = pause_of(self.hass, person)
        if pause:
            out["pause"] = pause
        if day and day.locked:
            ends = [lock_until(self.hass, [e for e in day.locked_by if e != PAUSE])]
            if pause:
                ends.append(dt_util.parse_datetime(pause["until"]))
            until = max((e for e in ends if e is not None), default=None)
            kinds = lock_kinds(self.hass, day.locked_by)
            out["lock"] = {
                "by": list(day.locked_by),
                # bedtime, school_time, pause or other: the first of them (bedtime before school time before a pause)
                "kind": next((k for k in ("bedtime", "school_time", "pause", "other") if k in kinds), "other"),
                "kinds": kinds,
                "until": dt_util.as_local(until).isoformat() if until else None,
            }
        if upcoming := next_lock(self.hass, self._lock_entities(person)):
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
        Family Safety enforcer (their account's sensors), for the app pickers; only ids pause_app takes."""
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
                continue
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

    def membership(self):
        """An item's groups: from the group lists, Android's category, where its time came from, and for a title
        its apps'."""
        base = groups_of(self.groups, self.categories, self.options.get(CONF_APP_GROUPS, {}))
        hints = self._hints
        titles = {f"title:{t.id}": t for t in self.titles}

        def of(item: str) -> set[str]:
            found = base(item) | hints.get(item, set())
            title = titles.get(item)
            if title is not None:
                for raw in title.raw:
                    found |= base(raw) | hints.get(raw, set())
            return found

        return of

    @callback
    def recompute(self) -> None:
        now = dt_util.now()
        # A TV's commands that waited too long are told as expired
        self.hub.commands.prune()
        today = now.date()
        new_day = self.limits.new_day(today)
        options = self.options
        self.groups = groups_from_options(options)
        self.sources = sources_from_options(options)
        self.titles = titles_from_options(options)
        by_id = {s.id: s for s in self.sources}
        readings: dict[str, dict[str, list[Reading]]] = {}
        playing: dict[str, list[Playing]] = {}
        observations: list[Observation] = []
        categories: dict[str, str] = {}
        catalog: dict[str, str] = {}
        hints: dict[str, set[str]] = {}
        def add(person: str, device: str, reading: Reading) -> None:
            items = {}
            for item, seconds in reading.items.items():
                key = self._key(item)
                items[key] = max(items.get(key, 0.0), seconds)
                if reading.rest_group:
                    hints.setdefault(key, set()).add(reading.rest_group)
            mapped = Reading(reading.source, reading.total_s, items, reading.rest_group)
            readings.setdefault(person, {}).setdefault(device, []).append(mapped)

        # Hearth's own devices
        for device_id, device in self.hub.devices.items():
            status = self.hub.state(device_id).status
            if status is None:
                continue
            categories.update(status.get("app_categories") or {})
            catalog.update(status.get("catalog_categories") or {})
            name = device.get("name") or device_id
            # Yesterday's counts from a device that hasn't posted since midnight don't count today
            fresh = status.get("day") == today.isoformat()
            if device.get(CONF_KIND) == KIND_TV:
                profiles = self.device_profile_people(device_id)
                if fresh:
                    for profile_id, usage in (status.get("usage_today") or {}).items():
                        person = profiles.get(profile_id)
                        if person:
                            add(person, device_id, Reading(SOURCE_HEARTH, float(usage.get("seconds") or 0),
                                                           usage.get("apps") or {}))
                person = profiles.get(status.get("profile_id") or "")
            else:
                person = device.get(CONF_PERSON)
                if person and fresh:
                    add(person, device_id, Reading(SOURCE_HEARTH, float(status.get("seconds_today") or 0),
                                                   status.get("app_seconds_today") or {}))
            package = status.get("app_package")
            if person and status.get("screen") == "on" and self.hub.connected(device_id) and package:
                playing.setdefault(person, []).append(Playing(status.get("app"), package, name, status.get("state")))
                key = self._key(package)
                observations.append(Observation(person, device_id, key, None, self._label(key, status.get("app"))))

        # Sources: totals now; live ones are looked at (and timed) below
        for source in self.sources:
            device = device_key(source, by_id)
            if source.live:
                item = now_playing(self.hass, source)
                if item is not None:
                    key = self._key(item)
                    observations.append(
                        Observation(source.person, device, key, source.reading_source, self._label(key, item))
                    )
                    playing.setdefault(source.person, []).append(Playing(item, None, source.name, "playing"))
            else:
                reading = totals_reading(self.hass, source)
                if reading is not None:
                    self._last_totals[source.id] = (today, reading)
                elif (last := self._last_totals.get(source.id)) is not None and last[0] == today:
                    reading = last[1]
                if reading is not None:
                    add(source.person, device, reading)

        started, ended = self.live.look(now, today, observations)
        for source in self.sources:
            if source.live:
                timed = self.live.seconds.get(source.reading_source, {})
                if timed:
                    add(source.person, device_key(source, by_id),
                        Reading(source.reading_source, sum(timed.values()), timed, source.group))
                    for key in timed:
                        if source.group:
                            hints.setdefault(key, set()).add(source.group)

        # An app's own category first, the shared catalog's for the rest
        for package, category in catalog.items():
            categories.setdefault(package, category)
        self.categories = categories
        self._hints = hints
        self._look_for_new_apps(categories)
        membership = self.membership()
        # Today's answer as last worked out; if the day turned without a refresh yet, what's known now
        is_school = (
            self.school.school if self.school.day == today else self.school.budget_is_school(self.school.decide_type(today))
        )
        kind = SCHOOL_DAY if is_school else OTHER_DAY
        days: dict[str, PersonDay] = {}
        for person in self.people():
            devices = {device: merge(r) for device, r in readings.get(person, {}).items()}
            seconds = group_seconds(devices, membership, self.outside_all())
            locked_by = self._locked_by(person)
            # A family pause holds them as a lock does
            if pause_of(self.hass, person, now):
                locked_by.append(PAUSE)
            day = PersonDay(person, devices, seconds, playing=playing.get(person, []),
                            together_s=self.live.together_s.get(person, 0.0), locked=bool(locked_by),
                            locked_by=locked_by)
            for group in self.groups:
                state = self.limits.state(person, group.id, seconds.get(group.id, 0.0) / 60, kind)
                day.limits[group.id] = state
                if state.minutes_left == 0:
                    if self.limits.mark_reached(person, group.id):
                        self.hass.bus.async_fire(
                            EVENT_BUDGET_REACHED, {"person": person, "group": group.id, "group_name": group.name}
                        )
                elif state.minutes_left is not None:
                    self.limits.clear_reached(person, group.id)
            days[person] = day
        self.days = days
        self.today = today
        groups_by_id = {g.id: g for g in self.groups}

        def apps_of(group_id: str, person: str) -> list[str]:
            if group_id == ALL:
                return self._person_apps(days.get(person), membership)
            if group_id not in groups_by_id:
                return []
            # With the Xbox and Windows apps a group lists, for Family Safety
            return self._group_apps(groups_by_id[group_id], membership, with_fs=True)

        self.allows.prune()
        self.grants.prune()
        # A parent's changes in their own apps first: they lift what they came from
        self.sync.detect()
        self.enforcement.update(
            enforcers_from_options(options),
            days,
            apps_of,
            lifted_of=self.allows.lifted,
            school_time_of=self.in_school_time,
            groups_of_app=membership,
            granted_of=self.grants.lifted,
        )
        # An adult's allow of All screen time opens Google's and Microsoft's own limits too
        self.sync.mirror_allows()
        for together, what in [(t, "started") for t in started] + [(t, "ended") for t in ended]:
            self.hass.bus.async_fire(EVENT_PLAYING_TOGETHER, self._together_event(together, what))
        async_dispatcher_send(self.hass, SIGNAL_PEOPLE, new_day)

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
        # Sorted on their own (a group that lists them, their category, the catalog's, else Other): nobody is asked;
        # an adult moves one on Hearth's page if it landed wrong
        for entry in fresh:
            self.hass.bus.async_fire(
                EVENT_NEW_APP,
                {"package": entry.package, "name": entry.name, "who": entry.who, "group": entry.group or OTHER},
            )
        if fresh:
            update_notification(self.hass, [], self.groups)

    def _ask_on_phone(self, entry) -> None:
        service = self.options.get(CONF_ASK_NOTIFY)
        if not service or "." not in service:
            return
        domain, name = service.split(".", 1)
        if not self.hass.services.has_service(domain, name):
            return
        self.hass.async_create_task(
            self.hass.services.async_call(
                domain,
                name,
                {
                    "title": "New app: " + entry.name,
                    "message": (f"{entry.who} has {entry.name}. " if entry.who else f"{entry.name} is new. ")
                    + "Which group does it count in?",
                    "data": {"tag": f"hearth_app_{entry.package}", "actions": phone_actions(entry, self.groups)},
                },
                blocking=False,
            )
        )

    @callback
    def sort_app(self, package: str, group: str) -> bool:
        """An adult moved an app to a group (or Other: All screen time only); it beats every automatic source."""
        if group != OTHER and self.group(group) is None:
            return False
        self.apps.sort(package, group)
        moved = {**self.options.get(CONF_APP_GROUPS, {}), package: group}
        self.hass.config_entries.async_update_entry(self.hub.entry, options={**self.hub.entry.options, CONF_APP_GROUPS: moved})
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
        apps = [
            {"package": p, "name": name, "group": self.app_group(p, membership), "moved": p in moved}
            for p, name in sorted(known.items(), key=lambda kv: kv[1].lower())
        ]
        recent = sorted(
            (e for e in self.apps.apps.values() if e.state != "known"), key=lambda e: e.seen, reverse=True
        )[:25]
        return {
            "apps": apps,
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

    def _group_apps(self, group: Group, membership, with_fs: bool = False) -> list[str]:
        """The packages a device should hold to a group: its own list and the apps seen in it (a title's packages).
        [with_fs]: with the group's Xbox and Windows apps (Family Safety's ids), which no Hearth device holds."""
        if group.id == ALL:
            return []
        titles = {f"title:{t.id}": t for t in self.titles}
        found: set[str] = set()
        for item in set(group.apps) | {k for k in self.known_apps() if group.id in membership(k)}:
            title = titles.get(item)
            for candidate in (title.raw if title else (item,)):
                if fs_app(candidate):
                    if with_fs:
                        found.add(candidate)
                elif "." in candidate and " " not in candidate:
                    found.add(candidate)
        return sorted(found)

    def outside_all(self) -> set[str]:
        """The groups whose time isn't screen time (Configure > Not screen time)."""
        return {g.id for g in self.groups if not g.in_all and g.id != ALL}

    def _spared(self, membership) -> set[str]:
        """The packages All screen time never holds: those of the groups outside it."""
        found: set[str] = set()
        for group in self.groups:
            if group.id in self.outside_all():
                found |= set(self._group_apps(group, membership))
        return found

    def group_packages(self) -> dict[str, list[str]]:
        """Each group's packages (not All's: every app), as devices are held to them."""
        membership = self.membership()
        return {g.id: self._group_apps(g, membership) for g in self.groups if g.id != ALL}

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

    def _person_document(self, person: str) -> dict[str, Any]:
        day = self.days.get(person)
        membership = self.membership()
        # An adult's allows: an allowed group is left out (nothing holds it), an allowed app is taken out of every
        # group and is one of All screen time's exceptions
        lifted = self.allows.lifted(person)
        groups = []
        for group in self.groups:
            state = day.limits.get(group.id) if day else None
            if state is None or state.budget_min is None or lifted.group(group.id):
                continue
            apps = self._group_apps(group, membership)
            entry = {
                "id": group.id,
                "name": group.name,
                "minutes_left": state.minutes_left,
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
        return {
            "person": person,
            "groups": groups,
            "locked": bool(day and day.locked),
            **self._locks_document(person, day),
            # A parent let this person's phone share with the launcher's tile exchange (off unless chosen)
            "tile_exchange_share": person in self.options.get(CONF_TILE_EXCHANGE, []),
            # Their latest request for more time and its answer (asks.py), while it's still news
            **({"request": ask.device_view()} if (ask := self.hub.asks.latest_for(person)) else {}),
            # What a parent blocked here, for HearthTube in the person's kids profiles (a TV's Hearth passes it on)
            "youtube_blocks": self.watch.blocks_document(person),
        }

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
                    profile_id: self._person_document(profiles[profile_id])
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
            person = device.get(CONF_PERSON)
            body = {"person": self._person_document(person) if person else None}
            if body["person"] is not None:
                role = self.options.get(CONF_ROLES, {}).get(person)
                # kid / adult as set on Hearth's page (kind_set); else a kid when they have limits
                body["person"]["kind"] = role or ("kid" if any(g["minutes_left"] is not None for g in body["person"]["groups"]) else "person")
                body["person"]["kind_set"] = role is not None
            # What's playing where in the house is anyone's to see: every room's players, for a phone's Music
            body["media_rooms"] = media_rooms(self.hass)
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
            "allows": [a.view(person) for a in self.allows.of(person)],
            # A parent's change in the Family Link, Nintendo or Family Safety app that lifts one of Hearth's holds
            "grants": [g.view() for g in self.grants.of(person)],
            "school_time_off": self.scheduler.offs_of(person),
        }

    def explain(self, person: str, app: str | None = None, group: str | None = None) -> dict[str, Any]:
        """Why an app or a group is held for the person now, or isn't: allowed, until, blocked_by [{kind, by, until}],
        exceptions (the allows that apply)."""
        now = dt_util.now()
        membership = self.membership()
        day = self.days.get(person)
        lifted = self.allows.lifted(person)
        outside = self.outside_all()
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
            if state is not None and state.minutes_left == 0:
                hold = {"kind": "budget", "by": group_id, "until": midnight}
                (lifted_holds if excepted or lifted.group(group_id) else blocked).append(hold)
        for entity_id in (day.locked_by if day else []):
            if entity_id == PAUSE:
                pause = pause_of(self.hass, person, now) or {}
                blocked.append(
                    {"kind": "pause", "by": "hearth.pause", "until": pause.get("until"), "reason": pause.get("reason")}
                )
                continue
            until = lock_until(self.hass, [entity_id])
            blocked.append(
                {
                    "kind": lock_kinds(self.hass, [entity_id])[0],
                    "by": entity_id,
                    "until": dt_util.as_local(until).isoformat() if until else None,
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
        if app is not None:
            for enforcer in enforcers_from_options(self.options):
                if enforcer.person == person and app in enforcer.school_apps and self.in_school_time(enforcer):
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
        return {
            "person": person,
            "app": app,
            "group": group,
            "allowed": not blocked,
            "until": until,
            "blocked_by": blocked,
            "lifted": lifted_holds,
            "exceptions": [a.view(person) for a in applying] + granted,
            "school_time_off": self.scheduler.offs_of(person),
        }

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

    @callback
    def add_bonus(self, person: str, group: str, minutes: int) -> None:
        day = self.days.get(person)
        had_none = bool(day and (state := day.limits.get(ALL)) and state.minutes_left == 0)
        self.limits.set_bonus(person, group, self.limits.bonus(person, group) + minutes)
        self.recompute()
        if group == ALL and minutes > 0:
            # All screen time back: Google's and Microsoft's own limits get as much
            self.sync.mirror_bonus(person, had_none)

    @callback
    def set_bonus(self, person: str, group: str, minutes: int) -> None:
        self.limits.set_bonus(person, group, minutes)
        self.recompute()

    @callback
    def set_budget(self, person: str, group: str, kind: str, minutes: int | None) -> None:
        self.limits.set_budget(person, group, kind, minutes)
        self.recompute()


def person_identifier(person: str) -> tuple[str, str]:
    return (DOMAIN, f"person:{person}")
