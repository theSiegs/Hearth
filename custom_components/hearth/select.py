"""Selects: each Glint Panel's settings (glint_panel/)."""

from __future__ import annotations

from homeassistant.core import HomeAssistant
from homeassistant.helpers.entity_platform import AddConfigEntryEntitiesCallback

from . import HearthConfigEntry
from .glint_panel import async_setup_platform


async def async_setup_entry(
    hass: HomeAssistant, entry: HearthConfigEntry, async_add_entities: AddConfigEntryEntitiesCallback
) -> None:
    hub = entry.runtime_data
    entry.async_on_unload(async_setup_platform(hass, hub.glint_panel, "select", async_add_entities))
