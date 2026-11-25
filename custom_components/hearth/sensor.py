"""Sensors: per Hearth device (the app in front, what's playing, usage today, and on a TV its state and profile), and
per person (screen time today, each group's time and minutes left, what they're playing)."""

from __future__ import annotations

from collections.abc import Callable
from dataclasses import dataclass
from datetime import date, datetime
from typing import Any

from homeassistant.components.sensor import (
    SensorDeviceClass,
    SensorEntity,
    SensorEntityDescription,
    SensorStateClass,
)
from homeassistant.const import UnitOfTime
from homeassistant.core import HomeAssistant, callback
from homeassistant.helpers import entity_registry as er
from homeassistant.helpers.dispatcher import async_dispatcher_connect
from homeassistant.helpers.entity_platform import AddConfigEntryEntitiesCallback
from homeassistant.helpers.restore_state import RestoreEntity
from homeassistant.util import dt as dt_util

from . import HearthConfigEntry
from .const import DOMAIN, KIND_MOBILE, KIND_TV, SIGNAL_WATCH, TV_STATES
from .counting import ALL
from .limits import never_held_group
from .schooldays import DAY_TYPES
from .entity import HearthEntity, HearthPersonEntity, async_add_device_entities
from .places import SIGNAL_PLACES, UNKNOWN
from .glint_panel import async_setup_platform

BOTH = frozenset({KIND_TV, KIND_MOBILE})
TV = frozenset({KIND_TV})


@dataclass(frozen=True, kw_only=True)
class HearthSensorDescription(SensorEntityDescription):
    value: Callable[[dict[str, Any]], Any]
    attributes: Callable[[dict[str, Any]], dict[str, Any]] | None = None
    # The kinds of device that have it
    kinds: frozenset[str] = BOTH


SENSORS: tuple[HearthSensorDescription, ...] = (
    HearthSensorDescription(
        key="state",
        translation_key="tv_state",
        device_class=SensorDeviceClass.ENUM,
        options=TV_STATES,
        value=lambda s: s.get("state"),
        kinds=TV,
    ),
    HearthSensorDescription(
        key="app",
        translation_key="app",
        value=lambda s: s.get("app"),
        attributes=lambda s: {"package": s.get("app_package")},
    ),
    HearthSensorDescription(
        key="media_title",
        translation_key="media_title",
        value=lambda s: s.get("media_title"),
        attributes=lambda s: {
            "album": s.get("media_album"),
            "duration_s": s.get("media_duration_s"),
            "now_playing_available": s.get("now_playing_available"),
        },
    ),
    HearthSensorDescription(key="media_artist", translation_key="media_artist", value=lambda s: s.get("media_artist")),
    HearthSensorDescription(key="media_app", translation_key="media_app", value=lambda s: s.get("media_app")),
    HearthSensorDescription(
        key="profile",
        translation_key="profile",
        value=lambda s: s.get("profile"),
        attributes=lambda s: {
            "profile_id": s.get("profile_id"),
            "profile_ref": s.get("profile_ref"),
            "kids_profile": s.get("kids_profile"),
        },
        kinds=TV,
    ),
    HearthSensorDescription(
        key="seconds_today",
        translation_key="seconds_today",
        device_class=SensorDeviceClass.DURATION,
        state_class=SensorStateClass.TOTAL_INCREASING,
        native_unit_of_measurement=UnitOfTime.SECONDS,
        suggested_unit_of_measurement=UnitOfTime.MINUTES,
        value=lambda s: s.get("seconds_today"),
        attributes=lambda s: {
            "day": s.get("day"),
            "apps": s.get("app_seconds_today") or {},
            "playing": s.get("playing_seconds_today") or {},
            "profiles": s.get("usage_today") or {},
        },
    ),
)


async def async_setup_entry(
    hass: HomeAssistant, entry: HearthConfigEntry, async_add_entities: AddConfigEntryEntitiesCallback
) -> None:
    hub = entry.runtime_data
    entry.async_on_unload(
        async_add_device_entities(
            hass,
            hub,
            async_add_entities,
            lambda device_id, kind: [
                *(HearthSensor(hub, device_id, d) for d in SENSORS if kind in d.kinds),
                # A phone or tablet: when it was last used, and whether from the home network
                *([DeviceLastInteraction(hub, device_id, LAST_INTERACTION)] if kind == KIND_MOBILE else []),
            ],
        )
    )
    household = hub.household
    people: list[SensorEntity] = []
    for person in household.people():
        people.append(PersonScreenTime(hub, person, "screen_time_today"))
        people.append(PersonPlaying(hub, person, "playing"))
        people.append(PersonTogetherToday(hub, person, "together_today"))
        people.append(PersonHeld(hub, person, "held"))
        people.append(PersonBonusLeft(hub, person, "bonus_time_left"))
        for group in household.groups:
            if group.id != ALL:
                people.append(PersonGroupToday(hub, person, "group_today", group))
            # Accessibility has no budget (nothing pauses its apps)
            if not never_held_group(group):
                people.append(PersonMinutesLeft(hub, person, "minutes_left", group))
    for person in household.youtube_people():
        people.append(PersonLastVideoStarted(hub, person, "last_video_started"))
    # Where each kid is, as a place name (places.py)
    for person in household.places.people():
        people.append(PersonPlace(hub, person, "place"))
    # Each kid's mode and tonight's bedtime from the weekly schedule (weekly.py)
    for person in household.week_people():
        people.append(PersonMode(hub, person, "mode"))
        people.append(PersonBedtime(hub, person, "bedtime"))
        people.append(PersonSchoolToday(hub, person, "school_today"))
    async_add_entities(people)
    async_add_entities([AppsToSort(hub), DayType(hub)])
    # Each Glint Panel's View and On the tablet (glint_panel/)
    entry.async_on_unload(async_setup_platform(hass, hub.glint_panel, "sensor", async_add_entities))


class HearthSensor(HearthEntity, SensorEntity):
    entity_description: HearthSensorDescription
    # Usage by app and profile changes all day: kept in the state machine, not in history
    _unrecorded_attributes = frozenset({"apps", "playing", "profiles"})

    @property
    def native_value(self) -> Any:
        return self.entity_description.value(self.status) if self.status is not None else None

    @property
    def extra_state_attributes(self) -> dict[str, Any] | None:
        if self.status is None or self.entity_description.attributes is None:
            return None
        attrs = self.entity_description.attributes(self.status)
        if self.entity_description.key == "profile":
            # A TV's sibling entities by id (docs/contracts/tv-entities.md), so a reader never guesses unique-id suffixes
            registry = er.async_get(self.hass)
            for name, key in (("state_entity", "state"), ("media_title_entity", "media_title")):
                attrs[name] = registry.async_get_entity_id("sensor", DOMAIN, f"{self.device_id}_{key}")
        return attrs


LAST_INTERACTION = SensorEntityDescription(
    key="last_interaction", translation_key="last_interaction", device_class=SensorDeviceClass.TIMESTAMP
)


def _iso(when: datetime | None) -> str | None:
    return dt_util.as_local(when).isoformat() if when else None


class DeviceLastInteraction(HearthEntity, SensorEntity):
    """When a phone or tablet was last used, by its status posts, and whether those came straight over the home
    network (docs/contracts/device-presence.md). Kept while the device is quiet, and across restarts."""

    @property
    def available(self) -> bool:
        return True

    @property
    def native_value(self) -> datetime | None:
        return self.hub.state(self.device_id).used

    @property
    def extra_state_attributes(self) -> dict[str, Any]:
        state = self.hub.state(self.device_id)
        seen = state.seen.replace(second=0, microsecond=0) if state.seen else None
        return {
            "kind": "last_interaction",
            "person": self.hub.household.device_person(self.device_id),
            "device_id": self.device_id,
            "last_interaction": _iso(state.used),
            "last_interaction_local": state.used_local,
            "last_user": state.used_by,
            "last_post": _iso(seen),
            "local": state.seen_local,
        }


def _minutes(seconds: float) -> int:
    return int(seconds // 60)


class _TodaySoFar(HearthPersonEntity, SensorEntity, RestoreEntity):
    """A time today that only goes up until midnight (total increasing): the count itself can dip a minute (a
    source's number corrected down, one device's sources taking turns at the larger), which the recorder would read as
    a reset. The highest shown today is shown until the count passes it; a new day starts again from the count.
    Restored after a restart on the same day."""

    _attr_device_class = SensorDeviceClass.DURATION
    _attr_state_class = SensorStateClass.TOTAL_INCREASING
    _attr_native_unit_of_measurement = UnitOfTime.MINUTES
    _high: tuple[date, int] | None = None

    def _count(self) -> int:
        raise NotImplementedError

    async def async_added_to_hass(self) -> None:
        await super().async_added_to_hass()
        last = await self.async_get_last_state()
        try:
            minutes = int(float(last.state)) if last is not None else None
        except ValueError:
            minutes = None
        if last is not None and minutes is not None and minutes >= 0:
            self._high = (dt_util.as_local(last.last_updated).date(), minutes)

    @property
    def native_value(self) -> int:
        count = self._count()
        today = self.hub.household.today or dt_util.now().date()
        if self._high is not None and self._high[0] == today and self._high[1] > count:
            return self._high[1]
        self._high = (today, count)
        return count


class PersonScreenTime(_TodaySoFar):
    """All of the person's screen time today, each minute counted once."""

    _attr_translation_key = "person_screen_time_today"
    _unrecorded_attributes = frozenset({"devices", "groups", "groups_apps", "not_screen_time"})

    def _count(self) -> int:
        return _minutes(self.day.total_s) if self.day else 0

    @property
    def extra_state_attributes(self) -> dict[str, Any]:
        day = self.day
        if day is None:
            return {"exceptions": self.hub.household.exceptions_of(self.person)}
        names = {device_id: d.get("name") or device_id for device_id, d in self.hub.devices.items()}
        names.update({f"source:{s.id}": s.name for s in self.hub.household.sources})
        return {
            "devices": {
                names.get(device_id, device_id): {
                    "minutes": _minutes(usage.total_s),
                    "sources": {source: _minutes(s) for source, s in usage.sources.items()},
                }
                for device_id, usage in day.devices.items()
            },
            "groups": {group: _minutes(seconds) for group, seconds in day.groups.items()},
            # Each group's packages (All screen time: every app), and the groups whose time isn't in it
            "groups_apps": self.hub.household.group_packages(),
            "not_screen_time": sorted(self.hub.household.outside_all()),
            # An adult's allows and School time taken off (hearth.allow, hearth.school_time_off)
            "exceptions": self.hub.household.exceptions_of(self.person),
        }


class PersonGroupToday(_TodaySoFar):
    """The person's time today in one group (Video, Games, YouTube)."""

    _attr_translation_key = "person_group_today"

    def _count(self) -> int:
        return _minutes(self.day.groups.get(self.budget_group.id, 0.0)) if self.day else 0


class PersonMinutesLeft(HearthPersonEntity, SensorEntity):
    """The minutes the person can still use today: daily time's (bonus time included), or a category's (its limit
    plus the bonus time left, never more than daily time left: time_model.py); unknown without a limit."""

    _attr_device_class = SensorDeviceClass.DURATION
    _attr_native_unit_of_measurement = UnitOfTime.MINUTES

    def __init__(self, hub, person: str, key: str, group) -> None:
        # Its entity id stays as an older Hearth named it ("All screen time minutes left")
        legacy = "All screen time minutes left" if group.id == ALL else None
        super().__init__(hub, person, key, group, legacy, "sensor" if legacy else None)
        self._attr_translation_key = "daily_time_left" if group.id == ALL else "person_minutes_left"

    @property
    def native_value(self) -> int | None:
        state = self.day.limits.get(self.budget_group.id) if self.day else None
        return state.shown_left if state else None

    @property
    def extra_state_attributes(self) -> dict[str, Any]:
        state = self.day.limits.get(self.budget_group.id) if self.day else None
        if state is None:
            return {}
        out = {
            # Daily time: today's base time; a category: its limit as set (before a raise)
            "budget": state.budget_min,
            "bonus": state.bonus_min,
            "bonus_chores": state.bonus_chores,
            "counted": int(state.counted_min),
            "bonus_left": state.bonus_left,
            # What holds it (0: held); a category's may be more than daily time left
            "held_left": state.minutes_left,
        }
        if self.budget_group.id != ALL:
            out["limit_today"] = None if state.budget_min is None else state.budget_min + state.bonus_min
            out["raised"] = state.raised.view() if state.raised is not None else None
        return out


class PersonBonusLeft(HearthPersonEntity, SensorEntity):
    """The bonus time the person has left today (no category: spent anywhere, minutes past a limit included)."""

    _attr_translation_key = "bonus_time_left"
    _attr_device_class = SensorDeviceClass.DURATION
    _attr_native_unit_of_measurement = UnitOfTime.MINUTES

    @property
    def native_value(self) -> int | None:
        state = self.day.limits.get(ALL) if self.day else None
        return state.bonus_left if state else None

    @property
    def extra_state_attributes(self) -> dict[str, Any]:
        state = self.day.limits.get(ALL) if self.day else None
        return {} if state is None else {"bonus": state.bonus_min, "bonus_chores": state.bonus_chores}


class PersonPlaying(HearthPersonEntity, SensorEntity):
    """What the person is playing now (a TV's show, a game, an app), anywhere Hearth sees; unknown when nothing."""

    _attr_translation_key = "person_playing"

    @property
    def native_value(self) -> str | None:
        playing = self.day.playing if self.day else []
        # The show's name over its episode's: what a glance at the sensor wants
        return (playing[0].series or playing[0].title or playing[0].app or playing[0].package) if playing else None

    @property
    def extra_state_attributes(self) -> dict[str, Any]:
        playing = self.day.playing if self.day else []
        return {
            "playing": [
                {k: v for k, v in p.view().items() if k != "target"} for p in playing
            ]
        }


class PersonTogetherToday(HearthPersonEntity, SensorEntity):
    """How long the person has played together with someone else of the household today."""

    _attr_translation_key = "person_together_today"
    _attr_device_class = SensorDeviceClass.DURATION
    _attr_state_class = SensorStateClass.TOTAL_INCREASING
    _attr_native_unit_of_measurement = UnitOfTime.MINUTES

    @property
    def native_value(self) -> int:
        return _minutes(self.day.together_s) if self.day else 0


class PersonHeld(HearthPersonEntity, SensorEntity):
    """How many apps and platforms the other parental controls hold for the person now (Configure > Enforce)."""

    _attr_translation_key = "person_held"

    @property
    def native_value(self) -> int:
        return sum(len(v["held"]) for v in self.hub.household.enforcement.held_for(self.person).values())

    @property
    def extra_state_attributes(self) -> dict[str, Any]:
        return self.hub.household.enforcement.held_for(self.person)


class PersonMode(HearthPersonEntity, SensorEntity):
    """The kid's mode now in their weekly schedule (Sleep, School, Free time, Homework...): the automation hook
    ("when Homework starts, turn on the desk lamp"). With no changes in their schedule: from their lock entities
    (sleep during a bedtime lock, school during School time, else free), as source "locks"."""

    _attr_translation_key = "person_mode"
    _attr_device_class = SensorDeviceClass.ENUM

    @property
    def options(self) -> list[str]:
        return list(self.hub.household.week.data.modes)

    @property
    def native_value(self) -> str | None:
        return self.hub.household.mode_of(self.person)["mode"]

    @property
    def extra_state_attributes(self) -> dict[str, Any]:
        return {
            "person": self.person,
            **{k: v for k, v in self.hub.household.mode_of(self.person).items() if k != "mode"},
        }


class PersonBedtime(HearthPersonEntity, SensorEntity):
    """Tonight's bedtime (a timestamp), from the weekly schedule's Sleep, else the lock entities' bedtime; the
    morning's wake as an attribute."""

    _attr_translation_key = "person_bedtime"
    _attr_device_class = SensorDeviceClass.TIMESTAMP

    @property
    def native_value(self):
        found = self.hub.household.bedtime_tonight(self.person)
        return dt_util.parse_datetime(found["at"]) if found else None

    @property
    def extra_state_attributes(self) -> dict[str, Any]:
        found = self.hub.household.bedtime_tonight(self.person)
        return {"person": self.person, "wake": found.get("wake") if found else None,
                "source": found.get("source") if found else None}


class PersonSchoolToday(HearthPersonEntity, SensorEntity):
    """The kid's school today: school, half_day, off, or home_today (kept home, hearth.home_today); today's School
    time window (start, end) as it is, with no travel time, from Family Link (else the School mode of their weekly
    schedule), and what decided the day (docs/contracts/people-entities.md)."""

    _attr_translation_key = "person_school_today"
    _attr_device_class = SensorDeviceClass.ENUM
    _attr_options = ["school", "half_day", "off", "home_today"]

    @property
    def native_value(self) -> str:
        return self.hub.household.school_today(self.person)["state"]

    @property
    def extra_state_attributes(self) -> dict[str, Any]:
        found = self.hub.household.school_today(self.person)
        return {"person": self.person, **{k: v for k, v in found.items() if k != "state"}}


class PersonLastVideoStarted(HearthPersonEntity, SensorEntity):
    """The last YouTube video the person started in HearthTube, in a kids profile; the newest 50 and what a parent
    blocked are in its attributes, for a dashboard and for an agent reading Home Assistant."""

    _attr_translation_key = "person_last_video_started"
    # The list changes with every video: kept in the state machine, not in history (get_watch_log has it all)
    _unrecorded_attributes = frozenset({"recent", "blocked"})

    async def async_added_to_hass(self) -> None:
        await super().async_added_to_hass()
        self.async_on_remove(async_dispatcher_connect(self.hass, SIGNAL_WATCH, self.async_write_ha_state))

    @property
    def native_value(self) -> str | None:
        latest = self.hub.household.watch.latest(self.person)
        return latest["title"][:255] or latest["video_id"] if latest else None

    @property
    def extra_state_attributes(self) -> dict[str, Any]:
        watch = self.hub.household.watch
        latest = watch.latest(self.person) or {}
        return {
            "video_id": latest.get("video_id"),
            "channel": latest.get("channel"),
            "url": latest.get("url"),
            "time": latest.get("time"),
            "recent": watch.recent(self.person),
            "blocked": watch.blocked(self.person),
        }


class PersonPlace(HearthPersonEntity, SensorEntity):
    """Where the person is: a place key (home, school, a favorite place's), away, or unknown. Hearth keeps no
    coordinates: its attributes are the place's name, since when, where it came from (family_link or person), the
    reading's accuracy, whether it's fresh and as of when, and who they're with (people's ids) and whether they're out
    without an adult (presence.py)."""

    _attr_translation_key = "person_place"
    # The state (a place key) is history enough: when it changed, how good each reading was, and who they were with
    # aren't kept
    _unrecorded_attributes = frozenset({"since", "source", "accuracy", "fresh", "as_of", "with", "apart_from_adults"})

    async def async_added_to_hass(self) -> None:
        await super().async_added_to_hass()
        self.async_on_remove(async_dispatcher_connect(self.hass, SIGNAL_PLACES, self.async_write_ha_state))

    @property
    def native_value(self) -> str | None:
        place = self.hub.household.places.view(self.person)["state"]
        # Unknown is the state machine's own unknown
        return None if place == UNKNOWN else place

    @property
    def extra_state_attributes(self) -> dict[str, Any]:
        view = self.hub.household.places.view(self.person)
        return {
            "person": self.person,
            **{k: view[k] for k in ("name", "since", "source", "accuracy", "fresh", "as_of")},
            **self.hub.household.presence.view(self.person),
        }


class AppsToSort(SensorEntity):
    """How many new apps wait for an adult to put them in a group; which, in its attributes."""

    _attr_has_entity_name = True
    _attr_should_poll = False
    _attr_translation_key = "apps_to_sort"

    def __init__(self, hub) -> None:
        from homeassistant.helpers.device_registry import DeviceInfo

        from .const import DOMAIN

        self.hub = hub
        self._attr_unique_id = f"{hub.entry.entry_id}_apps_to_sort"
        self._attr_device_info = DeviceInfo(
            identifiers={(DOMAIN, "household")}, name=f"Hearth: {hub.entry.title}", manufacturer="Hearth", model="Household"
        )

    async def async_added_to_hass(self) -> None:
        from homeassistant.helpers.dispatcher import async_dispatcher_connect

        from .const import SIGNAL_PEOPLE

        self.async_on_remove(async_dispatcher_connect(self.hass, SIGNAL_PEOPLE, self._changed))

    @callback
    def _changed(self, _new_day: bool = False) -> None:
        self.async_write_ha_state()

    @property
    def native_value(self) -> int:
        return len(self.hub.household.apps.new_apps())

    @property
    def extra_state_attributes(self) -> dict:
        return {
            "apps": [
                {"package": e.package, "name": e.name, "who": e.who, "suggested": e.suggested}
                for e in self.hub.household.apps.new_apps()[:50]
            ]
        }


class DayType(SensorEntity):
    """Today's day type (school, half_day, day_off, weekend, no_school), from School days: for the schedule, and for
    anything else that wants to know."""

    _attr_has_entity_name = True
    _attr_should_poll = False
    _attr_translation_key = "day_type"
    _attr_device_class = SensorDeviceClass.ENUM
    _attr_options = list(DAY_TYPES)

    def __init__(self, hub) -> None:
        from homeassistant.helpers.device_registry import DeviceInfo

        from .const import DOMAIN

        self.hub = hub
        self._attr_unique_id = f"{hub.entry.entry_id}_day_type"
        self._attr_device_info = DeviceInfo(
            identifiers={(DOMAIN, "household")}, name=f"Hearth: {hub.entry.title}", manufacturer="Hearth", model="Household"
        )

    async def async_added_to_hass(self) -> None:
        from .const import SIGNAL_PEOPLE

        self.async_on_remove(async_dispatcher_connect(self.hass, SIGNAL_PEOPLE, self._changed))

    @callback
    def _changed(self, _new_day: bool = False) -> None:
        self.async_write_ha_state()

    @property
    def native_value(self) -> str:
        school = self.hub.household.school
        today = dt_util.now().date()
        return school.day_type if school.day == today else school.decide_type(today)

    @property
    def extra_state_attributes(self) -> dict[str, Any]:
        school = self.hub.household.school
        return {"school_budget": school.school, "decided_by": school.reason}
