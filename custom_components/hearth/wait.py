"""Long-poll for a device's state document.

GET /api/hearth/device/<id>/wait?version=<v>&timeout=<s> (the device's secret in X-Hearth-Secret) answers
{"changed": true} as soon as the device's state document has another version than <v> (at once when it already has,
or when <v> is missing), else {"changed": false} after <s> seconds (at most WAIT_MAX). It never carries the
document: the device then posts its status and reads the state from that answer, as after a push ping.

A TV holds one while it is paired and its screen is on, so a pause, a lock or an answered ask reaches it within
seconds instead of at its next two-minute status post. A phone holds one only while its ask waits. Nothing here
needs a Home Assistant user, only the device's secret.
"""

from __future__ import annotations

import asyncio
from datetime import datetime
import hashlib
import json
from typing import TYPE_CHECKING, Any

from homeassistant.core import CALLBACK_TYPE, HomeAssistant, callback
from homeassistant.helpers.dispatcher import async_dispatcher_connect
from homeassistant.helpers.event import async_call_later

from .const import SIGNAL_COMMANDS, SIGNAL_NOTICES, SIGNAL_PAIRINGS, SIGNAL_PEOPLE, SIGNAL_WATCH

if TYPE_CHECKING:
    from .hub import HearthHub

# Seconds a wait is held at most: under the idle timeouts of common proxies
WAIT_MAX = 55
# Changes come together (a status post recomputes everyone): look once, this long after the first
WAIT_DEBOUNCE = 1.0


def _settled(value: Any) -> Any:
    """[value] with every minutes_left reduced to whether it's none left, and the version left out."""
    if isinstance(value, dict):
        return {
            k: (v == 0 if k == "minutes_left" and isinstance(v, (int, float)) else _settled(v))
            for k, v in value.items()
            if k != "version"
        }
    if isinstance(value, list):
        return [_settled(v) for v in value]
    return value


def signature(document: dict[str, Any]) -> str:
    """What in a device's document should wake its wait: everything but minutes counting down (a pause, a lock, an
    answer, a command, a group running out)."""
    return hashlib.sha256(json.dumps(_settled(document), sort_keys=True, default=str).encode()).hexdigest()[:16]


class DeviceWaits:
    """The household's held waits, one per device (a new one ends the device's previous with "not changed")."""

    def __init__(self, hass: HomeAssistant, hub: HearthHub) -> None:
        self.hass = hass
        self.hub = hub
        # device -> (what the document says that matters to it, the waiting future)
        self._waiting: dict[str, tuple[str | None, asyncio.Future[bool]]] = {}
        self._cancel: CALLBACK_TYPE | None = None
        self._unsubs: list[CALLBACK_TYPE] = []

    @callback
    def start(self) -> None:
        self._unsubs = [
            async_dispatcher_connect(self.hass, signal, self.changed)
            for signal in (SIGNAL_PEOPLE, SIGNAL_WATCH, SIGNAL_PAIRINGS, SIGNAL_COMMANDS, SIGNAL_NOTICES)
        ]

    @callback
    def stop(self) -> None:
        """The household unloads (a reload included): every held wait ends "not changed", the device asks again."""
        for unsub in self._unsubs:
            unsub()
        self._unsubs = []
        if self._cancel is not None:
            self._cancel()
            self._cancel = None
        for _, future in self._waiting.values():
            if not future.done():
                future.set_result(False)
        self._waiting.clear()

    @callback
    def changed(self, *_args: Any) -> None:
        if not self._waiting or self._cancel is not None:
            return
        self._cancel = async_call_later(self.hass, WAIT_DEBOUNCE, self._check)

    @callback
    def _check(self, _now: datetime | None = None) -> None:
        self._cancel = None
        for device_id, (version, future) in list(self._waiting.items()):
            if not future.done() and self._signature(device_id) != version:
                future.set_result(True)

    def _document(self, device_id: str) -> dict[str, Any] | None:
        if device_id not in self.hub.devices:
            return None
        return self.hub.household.document_for(device_id)

    def _version(self, device_id: str) -> str | None:
        document = self._document(device_id)
        return document["version"] if document is not None else None

    def _signature(self, device_id: str) -> str | None:
        document = self._document(device_id)
        return signature(document) if document is not None else None

    async def wait(self, device_id: str, version: str | None, timeout: float) -> bool:
        """True once the device's document is not [version]; False after [timeout] or when the household unloads."""
        if version is None or self._version(device_id) != version:
            return True
        previous = self._waiting.pop(device_id, None)
        if previous is not None and not previous[1].done():
            previous[1].set_result(False)
        # From here a change is what the TV acts on: minutes counting down don't wake it, a group running out does
        held = (self._signature(device_id), self.hass.loop.create_future())
        self._waiting[device_id] = held
        try:
            async with asyncio.timeout(timeout):
                return await held[1]
        except TimeoutError:
            return False
        finally:
            if self._waiting.get(device_id) is held:
                del self._waiting[device_id]
