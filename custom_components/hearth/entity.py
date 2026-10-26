"""What every Hearth device entity shares: its device, and updating when the device posts."""

from __future__ import annotations

from collections.abc import Callable, Iterable
from datetime import datetime, timedelta
from typing import Any

from homeassistant.core import HomeAssistant, callback
from homeassistant.helpers.device_registry import DeviceInfo
from homeassistant.helpers.dispatcher import async_dispatcher_connect
from homeassistant.helpers.entity import Entity, EntityDescription
from homeassistant.helpers.entity_platform import AddConfigEntryEntitiesCallback
from homeassistant.helpers.event import async_track_time_interval

from .const import CONF_MODEL, CONF_SW_VERSION, DOMAIN, KIND_TV, SIGNAL_DEVICE_ADDED, SIGNAL_PEOPLE, SIGNAL_STATUS
from .household import PersonDay, person_identifier
from .hub import HearthHub
from .limits import Group


class HearthEntity(Entity):
    _attr_has_entity_name = True
    _attr_should_poll = False

    def __init__(self, hub: HearthHub, device_id: str, description: EntityDescription) -> None:
        self.hub = hub
        self.device_id = device_id
        self.entity_description = description
        device = hub.devices.get(device_id, {})
        self._attr_unique_id = f"{device_id}_{description.key}"
        self._attr_device_info = DeviceInfo(
            identifiers={(DOMAIN, device_id)},
            name=device.get("name") or "Hearth",
            manufacturer="Hearth",
            model=device.get(CONF_MODEL) or ("TV" if hub.kind(device_id) == KIND_TV else "Mobile"),
            sw_version=device.get(CONF_SW_VERSION),
        )

    @property
    def status(self) -> dict[str, Any] | None:
        return self.hub.state(self.device_id).status

    @property
    def available(self) -> bool:
        """What the device last said, while it's still heard from."""
        return self.status is not None and self.hub.connected(self.device_id)

    async def async_added_to_hass(self) -> None:
        self.async_on_remove(
            async_dispatcher_connect(self.hass, SIGNAL_STATUS.format(self.device_id), self.async_write_ha_state)
        )
        # A device that goes quiet turns unavailable (and Connected off) without a post to say so
        self.async_on_remove(async_track_time_interval(self.hass, self._tick, timedelta(minutes=1)))

    @callback
    def _tick(self, _now: datetime) -> None:
        self.async_write_ha_state()


def async_add_device_entities(
    hass: HomeAssistant,
    hub: HearthHub,
    add_entities: AddConfigEntryEntitiesCallback,
    make: Callable[[str, str | None], Iterable[Entity]],
) -> Callable[[], None]:
    """Adds [make]'s entities (given the device and its kind) for each paired device now, and each that pairs later."""
    added: set[str] = set()

    @callback
    def add(device_id: str) -> None:
        if device_id in added or device_id not in hub.devices:
            return
        added.add(device_id)
        add_entities(make(device_id, hub.kind(device_id)))

    for device_id in hub.devices:
        add(device_id)
    return async_dispatcher_connect(hass, SIGNAL_DEVICE_ADDED, add)


class HearthPersonEntity(Entity):
    """An entity of one person's (a device of its own, "Hearth: <person>"), updated when anyone's day changes."""

    _attr_has_entity_name = True
    _attr_should_poll = False

    def __init__(self, hub: HearthHub, person: str, key: str, group: Group | None = None) -> None:
        self.hub = hub
        self.person = person
        self.group = group
        suffix = f"_{group.id}" if group else ""
        self._attr_unique_id = f"{hub.entry.entry_id}_{person}_{key}{suffix}"
        if group is not None:
            self._attr_translation_placeholders = {"group": group.name}
        self._attr_device_info = DeviceInfo(
            identifiers={person_identifier(person)},
            name=f"Hearth: {hub.household.person_name(person)}",
            manufacturer="Hearth",
            model="Person",
        )

    @property
    def day(self) -> PersonDay | None:
        return self.hub.household.days.get(self.person)

    async def async_added_to_hass(self) -> None:
        self.async_on_remove(async_dispatcher_connect(self.hass, SIGNAL_PEOPLE, self._people_changed))

    @callback
    def _people_changed(self, _new_day: bool = False) -> None:
        self.async_write_ha_state()
