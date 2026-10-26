"""Hearth: the household's Hearth devices (TVs, phones and tablets) in Home Assistant.

See docs/home-assistant-integration.md.
"""

from __future__ import annotations

from homeassistant.config_entries import ConfigEntry
from homeassistant.const import Platform
from homeassistant.core import HomeAssistant
from homeassistant.helpers import device_registry as dr

from .api import async_register_views
from .const import DOMAIN
from .hub import HearthHub

PLATFORMS = [Platform.BINARY_SENSOR, Platform.SENSOR]

type HearthConfigEntry = ConfigEntry[HearthHub]

_VIEWS_REGISTERED = f"{DOMAIN}_views"


async def async_setup_entry(hass: HomeAssistant, entry: HearthConfigEntry) -> bool:
    hub = HearthHub(hass, entry)
    await hub.async_load()
    entry.runtime_data = hub
    # The views stay registered for Home Assistant's lifetime (aiohttp can't take one away); with no entry
    # loaded they answer that Hearth isn't set up
    if not hass.data.get(_VIEWS_REGISTERED):
        async_register_views(hass)
        hass.data[_VIEWS_REGISTERED] = True
    await hass.config_entries.async_forward_entry_setups(entry, PLATFORMS)
    return True


async def async_unload_entry(hass: HomeAssistant, entry: HearthConfigEntry) -> bool:
    await entry.runtime_data.async_flush()
    return await hass.config_entries.async_unload_platforms(entry, PLATFORMS)


async def async_remove_config_entry_device(
    hass: HomeAssistant, entry: HearthConfigEntry, device: dr.DeviceEntry
) -> bool:
    """Deleting a device removes it from the household: its secret stops working at once."""
    for domain, device_id in device.identifiers:
        if domain == DOMAIN:
            await entry.runtime_data.async_remove_device(device_id)
    return True
