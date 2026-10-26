"""What every Hearth TV entity shares: its device, and updating when the TV posts."""

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

from .const import CONF_MODEL, CONF_SW_VERSION, DOMAIN, SIGNAL_STATUS, SIGNAL_TV_ADDED
from .hub import HearthHub


class HearthEntity(Entity):
    _attr_has_entity_name = True
    _attr_should_poll = False

    def __init__(self, hub: HearthHub, tv_id: str, description: EntityDescription) -> None:
        self.hub = hub
        self.tv_id = tv_id
        self.entity_description = description
        tv = hub.tvs.get(tv_id, {})
        self._attr_unique_id = f"{tv_id}_{description.key}"
        self._attr_device_info = DeviceInfo(
            identifiers={(DOMAIN, tv_id)},
            name=tv.get("name") or "TV",
            manufacturer="Hearth",
            model=tv.get(CONF_MODEL),
            sw_version=tv.get(CONF_SW_VERSION),
        )

    @property
    def status(self) -> dict[str, Any] | None:
        return self.hub.tv(self.tv_id).status

    @property
    def available(self) -> bool:
        """What the TV last said, while it's still heard from."""
        return self.status is not None and self.hub.connected(self.tv_id)

    async def async_added_to_hass(self) -> None:
        self.async_on_remove(
            async_dispatcher_connect(self.hass, SIGNAL_STATUS.format(self.tv_id), self.async_write_ha_state)
        )
        # A TV that goes quiet turns unavailable (and Connected off) without a post to say so
        self.async_on_remove(async_track_time_interval(self.hass, self._tick, timedelta(minutes=1)))

    @callback
    def _tick(self, _now: datetime) -> None:
        self.async_write_ha_state()


def async_add_tv_entities(
    hass: HomeAssistant,
    hub: HearthHub,
    add_entities: AddConfigEntryEntitiesCallback,
    make: Callable[[str], Iterable[Entity]],
) -> Callable[[], None]:
    """Adds [make]'s entities for each paired TV now, and for each TV that pairs later."""
    added: set[str] = set()

    @callback
    def add(tv_id: str) -> None:
        if tv_id in added or tv_id not in hub.tvs:
            return
        added.add(tv_id)
        add_entities(make(tv_id))

    for tv_id in hub.tvs:
        add(tv_id)
    return async_dispatcher_connect(hass, SIGNAL_TV_ADDED, add)
