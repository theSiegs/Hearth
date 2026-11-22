"""Each panel's entities: its settings (selects and switches, config) and what it says (Connected, View, On the
tablet, diagnostic). They show the store and write to it (Panels); nothing is restored from the state machine, and
no secret is ever a state or an attribute. The serving integration's platform files call async_setup_platform."""

from __future__ import annotations

from collections.abc import Callable, Iterable

from homeassistant.components.binary_sensor import (
    BinarySensorDeviceClass,
    BinarySensorEntity,
)
from homeassistant.components.select import SelectEntity
from homeassistant.components.sensor import SensorDeviceClass, SensorEntity
from homeassistant.components.switch import SwitchEntity
from homeassistant.const import EntityCategory
from homeassistant.core import HomeAssistant, callback
from homeassistant.exceptions import HomeAssistantError
from homeassistant.helpers import entity_registry as er
from homeassistant.helpers.device_registry import DeviceInfo
from homeassistant.helpers.dispatcher import async_dispatcher_connect
from homeassistant.helpers.entity import Entity

from .const import (
    HOUSE_PANEL,
    SELECTS,
    SWITCHES,
    VIEWS,
    identifier,
    signal,
    signal_added,
    unique_id,
)
from .manager import Panels


class PanelEntity(Entity):
    _attr_has_entity_name = True
    _attr_should_poll = False

    def __init__(self, panels: Panels, device_id: str, key: str) -> None:
        self.panels = panels
        self.device_id = device_id
        self.key = key
        self._attr_unique_id = unique_id(device_id, key)
        self._attr_translation_key = "connected" if key == "connected" else f"panel_{key}"
        self._attr_device_info = DeviceInfo(identifiers={identifier(panels.domain, device_id)})

    @property
    def available(self) -> bool:
        return self.panels.has(self.device_id)

    async def _check_caller(self) -> None:
        """A setting is the adults' to change, as set_panel's: an administrator, an adult, or no user (an
        automation); else Unauthorized."""
        host = self.panels.host
        if host is None:
            raise HomeAssistantError("Panels aren't set up")
        await host.check_context(self._context)

    async def async_added_to_hass(self) -> None:
        self.async_on_remove(
            async_dispatcher_connect(self.hass, signal(self.panels.domain, self.device_id), self.async_write_ha_state)
        )


class PanelSwitch(PanelEntity, SwitchEntity):
    _attr_entity_category = EntityCategory.CONFIG

    @property
    def is_on(self) -> bool:
        return bool(self.panels.value(self.device_id, self.key))

    async def async_turn_on(self, **kwargs) -> None:
        await self._check_caller()
        self.panels.set_values(self.device_id, {self.key: True if self.key == HOUSE_PANEL else self._kept(True)})

    async def async_turn_off(self, **kwargs) -> None:
        await self._check_caller()
        self.panels.set_values(self.device_id, {self.key: False if self.key == HOUSE_PANEL else self._kept(False)})

    def _kept(self, on: bool) -> bool | None:
        # The default isn't kept: it's derived
        return None if on == SWITCHES[self.key] else on


class PanelSelect(PanelEntity, SelectEntity):
    _attr_entity_category = EntityCategory.CONFIG

    def __init__(self, panels: Panels, device_id: str, key: str) -> None:
        super().__init__(panels, device_id, key)
        self._default, choices = SELECTS[key]
        self._attr_options = [str(c) for c in choices]

    @property
    def current_option(self) -> str:
        return str(self.panels.value(self.device_id, self.key))

    async def async_select_option(self, option: str) -> None:
        await self._check_caller()
        value: object = int(option) if isinstance(self._default, int) else option
        self.panels.set_values(self.device_id, {self.key: None if value == self._default else value})


class PanelConnected(PanelEntity, BinarySensorEntity):
    _attr_device_class = BinarySensorDeviceClass.CONNECTIVITY
    _attr_entity_category = EntityCategory.DIAGNOSTIC

    @property
    def is_on(self) -> bool:
        return self.panels.connected(self.device_id)


class PanelView(PanelEntity, SensorEntity):
    _attr_device_class = SensorDeviceClass.ENUM
    _attr_entity_category = EntityCategory.DIAGNOSTIC

    def __init__(self, panels: Panels, device_id: str, key: str) -> None:
        super().__init__(panels, device_id, key)
        self._attr_options = list(VIEWS)

    @property
    def native_value(self) -> str | None:
        return self.panels.view(self.device_id)


class PanelOnTablet(PanelEntity, SensorEntity):
    _attr_entity_category = EntityCategory.DIAGNOSTIC

    @property
    def native_value(self) -> str:
        return self.panels.on_tablet(self.device_id)


def _made(platform: str, panels: Panels, device_id: str) -> list[Entity]:
    if platform == "switch":
        return [PanelSwitch(panels, device_id, key) for key in (*SWITCHES, HOUSE_PANEL)]
    if platform == "select":
        return [PanelSelect(panels, device_id, key) for key in SELECTS]
    if platform == "binary_sensor":
        return [PanelConnected(panels, device_id, "connected")]
    if platform == "sensor":
        return [PanelView(panels, device_id, "view"), PanelOnTablet(panels, device_id, "on_the_tablet")]
    return []


def async_setup_platform(
    hass: HomeAssistant, panels: Panels, platform: str, add_entities: Callable[[Iterable[Entity]], None]
) -> Callable[[], None]:
    """Adds [platform]'s entities for each panel now, and each that pairs later; returns the stop."""
    added: set[str] = set()
    registry = er.async_get(hass)

    @callback
    def add(device_id: str) -> None:
        if not panels.has(device_id):
            return
        made = _made(platform, panels, device_id)
        # Paired again: its entities are there already. Removed and paired anew: they went with the device
        if device_id in added and registry.async_get_entity_id(platform, panels.domain, made[0].unique_id):
            return
        added.add(device_id)
        add_entities(made)

    for device_id in list(panels.panels):
        add(device_id)
    return async_dispatcher_connect(hass, signal_added(panels.domain), add)
