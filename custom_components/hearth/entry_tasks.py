"""Background work that belongs to the Hearth entry.

A task made here is tracked by the config entry: when the entry unloads (a reload after an option change included),
Home Assistant waits for it before the new instance sets up. So a store write or a call to Family Link or Family
Safety that is under way finishes first, instead of running on against the old instance and saving over the new one's
state. Use it for work that writes Hearth's stores or a parental control; a plain notification needn't.
"""

from __future__ import annotations

import asyncio
from collections.abc import Coroutine
from typing import Any

from homeassistant.core import HomeAssistant


def entry_task(hass: HomeAssistant, entry_id: str, target: Coroutine[Any, Any, Any], name: str) -> asyncio.Task:
    """Run [target] as a task of the entry [entry_id] (a plain task if the entry is gone)."""
    entry = hass.config_entries.async_get_entry(entry_id)
    if entry is None:
        return hass.async_create_task(target, name)
    return entry.async_create_task(hass, target, name)
