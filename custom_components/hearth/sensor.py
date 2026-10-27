"""Sensors: per Hearth device (the app in front, what's playing, usage today, and on a TV its state and profile), and
per person (screen time today, each group's time and minutes left, what they're playing)."""

from __future__ import annotations

from collections.abc import Callable
from dataclasses import dataclass
from typing import Any

from homeassistant.components.sensor import (
    SensorDeviceClass,
    SensorEntity,
    SensorEntityDescription,
    SensorStateClass,
)
from homeassistant.const import UnitOfTime
from homeassistant.core import HomeAssistant, callback
from homeassistant.helpers.entity_platform import AddConfigEntryEntitiesCallback

from . import HearthConfigEntry
from .const import KIND_MOBILE, KIND_TV, TV_STATES
from .counting import ALL
from .entity import HearthEntity, HearthPersonEntity, async_add_device_entities

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
        attributes=lambda s: {"profile_id": s.get("profile_id"), "kids_profile": s.get("kids_profile")},
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
            lambda device_id, kind: [HearthSensor(hub, device_id, d) for d in SENSORS if kind in d.kinds],
        )
    )
    household = hub.household
    people: list[SensorEntity] = []
    for person in household.people():
        people.append(PersonScreenTime(hub, person, "screen_time_today"))
        people.append(PersonPlaying(hub, person, "playing"))
        people.append(PersonTogetherToday(hub, person, "together_today"))
        people.append(PersonHeld(hub, person, "held"))
        for group in household.groups:
            if group.id != ALL:
                people.append(PersonGroupToday(hub, person, "group_today", group))
            people.append(PersonMinutesLeft(hub, person, "minutes_left", group))
    async_add_entities(people)
    async_add_entities([AppsToSort(hub)])


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
        return self.entity_description.attributes(self.status)


def _minutes(seconds: float) -> int:
    return int(seconds // 60)


class PersonScreenTime(HearthPersonEntity, SensorEntity):
    """All of the person's screen time today, each minute counted once."""

    _attr_translation_key = "person_screen_time_today"
    _attr_device_class = SensorDeviceClass.DURATION
    _attr_state_class = SensorStateClass.TOTAL_INCREASING
    _attr_native_unit_of_measurement = UnitOfTime.MINUTES
    _unrecorded_attributes = frozenset({"devices", "groups"})

    @property
    def native_value(self) -> int:
        return _minutes(self.day.total_s) if self.day else 0

    @property
    def extra_state_attributes(self) -> dict[str, Any]:
        day = self.day
        if day is None:
            return {}
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
        }


class PersonGroupToday(HearthPersonEntity, SensorEntity):
    """The person's time today in one group (Video, Games, YouTube)."""

    _attr_translation_key = "person_group_today"
    _attr_device_class = SensorDeviceClass.DURATION
    _attr_state_class = SensorStateClass.TOTAL_INCREASING
    _attr_native_unit_of_measurement = UnitOfTime.MINUTES

    @property
    def native_value(self) -> int:
        return _minutes(self.day.groups.get(self.budget_group.id, 0.0)) if self.day else 0


class PersonMinutesLeft(HearthPersonEntity, SensorEntity):
    """What's left today of the person's budget for one group; unknown while it has no budget."""

    _attr_translation_key = "person_minutes_left"
    _attr_device_class = SensorDeviceClass.DURATION
    _attr_native_unit_of_measurement = UnitOfTime.MINUTES

    @property
    def native_value(self) -> int | None:
        state = self.day.limits.get(self.budget_group.id) if self.day else None
        return state.minutes_left if state else None

    @property
    def extra_state_attributes(self) -> dict[str, Any]:
        state = self.day.limits.get(self.budget_group.id) if self.day else None
        if state is None:
            return {}
        return {"budget": state.budget_min, "bonus": state.bonus_min, "counted": int(state.counted_min)}


class PersonPlaying(HearthPersonEntity, SensorEntity):
    """What the person is playing now, on a Hearth device; unknown when nothing."""

    _attr_translation_key = "person_playing"

    @property
    def native_value(self) -> str | None:
        playing = self.day.playing if self.day else []
        return (playing[0].app or playing[0].package) if playing else None

    @property
    def extra_state_attributes(self) -> dict[str, Any]:
        playing = self.day.playing if self.day else []
        return {
            "playing": [
                {"app": p.app, "package": p.package, "device": p.device, "state": p.state} for p in playing
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
