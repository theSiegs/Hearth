"""A Hearth device's binary sensors: connected, and on a TV in a kids profile and screen time up."""

from __future__ import annotations

from collections.abc import Callable
from dataclasses import dataclass
from typing import Any

from homeassistant.components.binary_sensor import (
    BinarySensorDeviceClass,
    BinarySensorEntity,
    BinarySensorEntityDescription,
)
from homeassistant.const import EntityCategory
from homeassistant.core import HomeAssistant
from homeassistant.helpers.entity_platform import AddConfigEntryEntitiesCallback

from . import HearthConfigEntry
from .const import KIND_TV
from .entity import HearthEntity, async_add_device_entities


@dataclass(frozen=True, kw_only=True)
class HearthBinarySensorDescription(BinarySensorEntityDescription):
    value: Callable[[dict[str, Any]], bool | None]
    attributes: Callable[[dict[str, Any]], dict[str, Any]] | None = None


STATUS_SENSORS: tuple[HearthBinarySensorDescription, ...] = (
    HearthBinarySensorDescription(
        key="kids_profile",
        translation_key="kids_profile",
        value=lambda s: s.get("kids_profile"),
        attributes=lambda s: {"allowed_apps": s.get("allowed_apps")},
    ),
    HearthBinarySensorDescription(
        key="screen_time_up",
        translation_key="screen_time_up",
        value=lambda s: s.get("screen_time_up"),
        attributes=lambda s: {
            "reason": s.get("screen_time_reason"),
            "text": s.get("screen_time_text"),
            "minutes_left": s.get("screen_time_minutes_left"),
            "unlocks_at": s.get("screen_time_unlocks_at_iso") or s.get("screen_time_unlocks_at"),
            "event": s.get("screen_time_event"),
            "event_at": s.get("screen_time_event_at"),
        },
    ),
)

CONNECTED = BinarySensorEntityDescription(
    key="connected",
    translation_key="connected",
    device_class=BinarySensorDeviceClass.CONNECTIVITY,
    entity_category=EntityCategory.DIAGNOSTIC,
)


async def async_setup_entry(
    hass: HomeAssistant, entry: HearthConfigEntry, async_add_entities: AddConfigEntryEntitiesCallback
) -> None:
    hub = entry.runtime_data

    def make(device_id: str, kind: str | None):
        # A phone is one person's: no profile switching, and its screen time limits are Family Link's
        status = [HearthBinarySensor(hub, device_id, d) for d in STATUS_SENSORS] if kind == KIND_TV else []
        return [HearthConnected(hub, device_id, CONNECTED), *status]

    entry.async_on_unload(async_add_device_entities(hass, hub, async_add_entities, make))


class HearthBinarySensor(HearthEntity, BinarySensorEntity):
    entity_description: HearthBinarySensorDescription
    _unrecorded_attributes = frozenset({"allowed_apps"})

    @property
    def is_on(self) -> bool | None:
        return self.entity_description.value(self.status) if self.status is not None else None

    @property
    def extra_state_attributes(self) -> dict[str, Any] | None:
        if self.status is None or self.entity_description.attributes is None:
            return None
        return self.entity_description.attributes(self.status)


class HearthConnected(HearthEntity, BinarySensorEntity):
    """On while the device has posted in the last 15 minutes; always available, so it can say off."""

    @property
    def available(self) -> bool:
        return True

    @property
    def is_on(self) -> bool:
        return self.hub.connected(self.device_id)
