"""Switches: each Glint Panel's settings (glint_panel/), and each TV's "Share Bluetooth with Home Assistant"
(bt_proxy.py)."""

from __future__ import annotations

from typing import Any

from homeassistant.components.switch import SwitchEntity, SwitchEntityDescription
from homeassistant.const import EntityCategory
from homeassistant.core import HomeAssistant
from homeassistant.exceptions import ServiceValidationError
from homeassistant.helpers.dispatcher import async_dispatcher_connect
from homeassistant.helpers.entity_platform import AddConfigEntryEntitiesCallback

from . import HearthConfigEntry
from .auth import is_adult_user
from .bt_proxy import SIGNAL_BT_PROXY
from .const import CAP_BT_PROXY, KIND_TV
from .entity import HearthEntity, async_add_device_entities
from .glint_panel import async_setup_platform

SHARE_BLUETOOTH = SwitchEntityDescription(
    key="share_bluetooth", translation_key="share_bluetooth", entity_category=EntityCategory.CONFIG
)


async def async_setup_entry(
    hass: HomeAssistant, entry: HearthConfigEntry, async_add_entities: AddConfigEntryEntitiesCallback
) -> None:
    hub = entry.runtime_data
    entry.async_on_unload(async_setup_platform(hass, hub.glint_panel, "switch", async_add_entities))
    entry.async_on_unload(
        async_add_device_entities(
            hass,
            hub,
            async_add_entities,
            lambda device_id, kind: [ShareBluetooth(hub, device_id, SHARE_BLUETOOTH)] if kind == KIND_TV else [],
        )
    )


class ShareBluetooth(HearthEntity, SwitchEntity):
    """A TV shares its Bluetooth with Home Assistant (an ESPHome proxy), off by default. Available once the TV says it
    can (a Hearth TV new enough); it may be set while the TV is away, which takes it with its next word. Adults only,
    as Hearth's other controls: an administrator, a user whose person is an adult, or an automation."""

    @property
    def available(self) -> bool:
        return self.hub.has_cap(self.device_id, CAP_BT_PROXY)

    @property
    def is_on(self) -> bool:
        return self.hub.bt_proxy.wanted(self.device_id)

    async def async_added_to_hass(self) -> None:
        await super().async_added_to_hass()
        self.async_on_remove(
            async_dispatcher_connect(self.hass, SIGNAL_BT_PROXY.format(self.device_id), self.async_write_ha_state)
        )

    async def _check_writer(self) -> None:
        context = self._context
        user_id = context.user_id if context is not None else None
        if user_id is None:
            return
        user = await self.hass.auth.async_get_user(user_id)
        if user is None or not is_adult_user(self.hass, self.hub, user):
            raise ServiceValidationError(
                "Only an adult can change whether a TV shares its Bluetooth (an administrator, or a user whose "
                "person is an adult on Hearth's page)"
            )

    async def async_turn_on(self, **kwargs: Any) -> None:
        await self._check_writer()
        self.hub.bt_proxy.set(self.device_id, True)

    async def async_turn_off(self, **kwargs: Any) -> None:
        await self._check_writer()
        self.hub.bt_proxy.set(self.device_id, False)
