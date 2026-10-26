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
from homeassistant.core import callback
from homeassistant.helpers.device_registry import DeviceInfo
from homeassistant.helpers.dispatcher import async_dispatcher_connect

from .const import DOMAIN, SIGNAL_PEOPLE
from .entity import HearthEntity, async_add_device_entities
from .hub import HearthHub


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
    async_add_entities([PlayingTogether(hub)])


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


class PlayingTogether(BinarySensorEntity):
    """On while two or more of the household's people play the same title (or app) at the same time."""

    _attr_has_entity_name = True
    _attr_should_poll = False
    _attr_translation_key = "playing_together"

    def __init__(self, hub: HearthHub) -> None:
        self.hub = hub
        self._attr_unique_id = f"{hub.entry.entry_id}_playing_together"
        self._attr_device_info = DeviceInfo(
            identifiers={(DOMAIN, "household")}, name=f"Hearth: {hub.entry.title}", manufacturer="Hearth", model="Household"
        )

    async def async_added_to_hass(self) -> None:
        self.async_on_remove(async_dispatcher_connect(self.hass, SIGNAL_PEOPLE, self._changed))

    @callback
    def _changed(self, _new_day: bool = False) -> None:
        self.async_write_ha_state()

    @property
    def is_on(self) -> bool:
        return bool(self.hub.household.live.together)

    @property
    def extra_state_attributes(self) -> dict:
        household = self.hub.household
        together = list(household.live.together.values())
        return {
            "together": [
                {
                    "title": t.label,
                    "people": [household.person_name(p) for p in t.people],
                    "person_ids": t.people,
                    "devices": [self.hub.devices.get(d, {}).get("name") or d for d in t.devices],
                    "since": t.since,
                }
                for t in together
            ]
        }
