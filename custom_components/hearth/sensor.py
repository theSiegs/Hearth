"""A Hearth device's sensors: the app in front, what's playing, usage today, and on a TV its state and profile."""

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
from homeassistant.core import HomeAssistant
from homeassistant.helpers.entity_platform import AddConfigEntryEntitiesCallback

from . import HearthConfigEntry
from .const import KIND_MOBILE, KIND_TV, TV_STATES
from .entity import HearthEntity, async_add_device_entities

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
