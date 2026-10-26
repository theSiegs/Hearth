"""Hearth: the household's Hearth devices (TVs, phones and tablets) in Home Assistant.

See docs/home-assistant-integration.md.
"""

from __future__ import annotations

from datetime import timedelta

import voluptuous as vol

from homeassistant.config_entries import ConfigEntry
from homeassistant.const import Platform
from homeassistant.core import HomeAssistant, ServiceCall, callback
from homeassistant.exceptions import ServiceValidationError
from homeassistant.helpers import config_validation as cv
from homeassistant.helpers import device_registry as dr
from homeassistant.helpers.event import async_track_time_change, async_track_time_interval

from .api import async_register_views
from .const import DOMAIN
from .hub import HearthHub
from .limits import DAY_TYPES

PLATFORMS = [Platform.BINARY_SENSOR, Platform.NUMBER, Platform.SENSOR]

type HearthConfigEntry = ConfigEntry[HearthHub]

CONFIG_SCHEMA = cv.config_entry_only_config_schema(DOMAIN)

_VIEWS_REGISTERED = f"{DOMAIN}_views"

SERVICE_ADD_BONUS = "add_bonus"
SERVICE_SET_BUDGET = "set_budget"

ADD_BONUS_SCHEMA = vol.Schema(
    {
        vol.Required("person"): cv.entity_id,
        vol.Required("minutes"): vol.All(vol.Coerce(int), vol.Range(min=-1440, max=1440)),
        vol.Optional("group", default="all"): cv.string,
    }
)
SET_BUDGET_SCHEMA = vol.Schema(
    {
        vol.Required("person"): cv.entity_id,
        vol.Required("group"): cv.string,
        vol.Required("minutes"): vol.Any(None, vol.All(vol.Coerce(int), vol.Range(min=0, max=1440))),
        vol.Optional("days", default="both"): vol.In(["weekday", "weekend", "both"]),
    }
)


async def async_setup(hass: HomeAssistant, config: dict) -> bool:
    def household(call: ServiceCall):
        entries = hass.config_entries.async_loaded_entries(DOMAIN)
        if not entries:
            raise ServiceValidationError("Hearth isn't set up")
        household = entries[0].runtime_data.household
        if call.data["person"] not in household.people():
            raise ServiceValidationError(f"{call.data['person']} isn't one of the household's people")
        if household.group(call.data["group"]) is None:
            raise ServiceValidationError(f"No group {call.data['group']}")
        return household

    @callback
    def add_bonus(call: ServiceCall) -> None:
        """Minutes added to (or, negative, taken from) a person's group today: the one way to extend."""
        household(call).add_bonus(call.data["person"], call.data["group"], call.data["minutes"])

    @callback
    def set_budget(call: ServiceCall) -> None:
        target = household(call)
        days = DAY_TYPES if call.data["days"] == "both" else (call.data["days"],)
        for kind in days:
            target.set_budget(call.data["person"], call.data["group"], kind, call.data["minutes"])

    hass.services.async_register(DOMAIN, SERVICE_ADD_BONUS, add_bonus, schema=ADD_BONUS_SCHEMA)
    hass.services.async_register(DOMAIN, SERVICE_SET_BUDGET, set_budget, schema=SET_BUDGET_SCHEMA)
    return True


async def async_setup_entry(hass: HomeAssistant, entry: HearthConfigEntry) -> bool:
    hub = HearthHub(hass, entry)
    await hub.async_load()
    entry.runtime_data = hub
    hub.household.recompute()
    # The views stay registered for Home Assistant's lifetime (aiohttp can't take one away); with no entry
    # loaded they answer that Hearth isn't set up
    if not hass.data.get(_VIEWS_REGISTERED):
        async_register_views(hass)
        hass.data[_VIEWS_REGISTERED] = True
    await hass.config_entries.async_forward_entry_setups(entry, PLATFORMS)

    @callback
    def recompute(_now) -> None:
        hub.household.recompute()

    # A new day starts at midnight; budgets, bonuses and quiet devices are looked at again every minute
    entry.async_on_unload(async_track_time_change(hass, recompute, hour=0, minute=0, second=1))
    entry.async_on_unload(async_track_time_interval(hass, recompute, timedelta(minutes=1)))
    # People and groups come from the entry: when it changes (options, a phone paired), its entities are made again
    entry.async_on_unload(entry.add_update_listener(_async_entry_updated))
    return True


async def _async_entry_updated(hass: HomeAssistant, entry: HearthConfigEntry) -> None:
    hass.config_entries.async_schedule_reload(entry.entry_id)


async def async_unload_entry(hass: HomeAssistant, entry: HearthConfigEntry) -> bool:
    await entry.runtime_data.async_flush()
    return await hass.config_entries.async_unload_platforms(entry, PLATFORMS)


async def async_remove_config_entry_device(
    hass: HomeAssistant, entry: HearthConfigEntry, device: dr.DeviceEntry
) -> bool:
    """Deleting a Hearth device removes it from the household: its secret stops working at once. A person's device
    goes with their mapping, so it can only be removed there."""
    for domain, device_id in device.identifiers:
        if domain == DOMAIN:
            if device_id.startswith("person:"):
                return False
            await entry.runtime_data.async_remove_device(device_id)
    return True
