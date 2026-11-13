"""Background work that belongs to the Hearth entry.

A task made here is tracked for the config entry: when the entry unloads (a reload after an option change included),
the unload waits for it (up to UNLOAD_WAIT seconds) BEFORE it flushes the stores, so a store write or a call to Family
Link or Family Safety that is under way finishes and is saved with the rest, instead of running on against the old
instance and saving over the new one's state. Use it for work that writes Hearth's stores or a parental control; a
plain notification needn't.
"""

from __future__ import annotations

import asyncio
from collections.abc import Coroutine
import logging
from typing import Any

from homeassistant.core import HomeAssistant

from .const import DOMAIN

_LOGGER = logging.getLogger(__name__)
# How long an unload waits for the entry's tasks before it flushes anyway
UNLOAD_WAIT = 10.0


def _tasks(hass: HomeAssistant, entry_id: str) -> set[asyncio.Task]:
    return hass.data.setdefault(f"{DOMAIN}_entry_tasks", {}).setdefault(entry_id, set())


def entry_task(hass: HomeAssistant, entry_id: str, target: Coroutine[Any, Any, Any], name: str) -> asyncio.Task:
    """Run [target] as a task of the entry [entry_id] (a plain task if the entry is gone)."""
    entry = hass.config_entries.async_get_entry(entry_id)
    if entry is None:
        return hass.async_create_task(target, name)
    task = entry.async_create_task(hass, target, name)
    tasks = _tasks(hass, entry_id)
    tasks.add(task)
    task.add_done_callback(tasks.discard)
    return task


async def async_wait_for_entry_tasks(hass: HomeAssistant, entry_id: str) -> None:
    """Waits for the entry's tasks still running (at most UNLOAD_WAIT seconds), so their writes are flushed."""
    pending = [t for t in _tasks(hass, entry_id) if not t.done()]
    if not pending:
        return
    _done, still = await asyncio.wait(pending, timeout=UNLOAD_WAIT)
    if still:
        _LOGGER.warning("Unloading with %d Hearth task(s) still running", len(still))
