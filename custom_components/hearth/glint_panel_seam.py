"""Hearth's side of the Glint Panel seam: the one object glint_panel/ gets from Hearth (glint_panel/host.py says what
it may ask). Nothing here imports glint_panel/; the panels import nothing of Hearth's."""

from __future__ import annotations

import hmac
from typing import Any

from homeassistant.core import HomeAssistant, ServiceCall
from homeassistant.util import dt as dt_util

from . import parent_pin
from .auth import async_check_caller
from .const import DOMAIN
from .hub import HearthHub, hash_secret, pin_lockout
from .panel import URL_PATH


class HearthPanelHost:
    """What a Glint Panel needs from Hearth: the domain, the entry, the device-secret check, the Parent PIN check (with
    Hearth's lockout, as phones' verify_pin), the service caller check and the page's link."""

    def __init__(self, hass: HomeAssistant, hub: HearthHub) -> None:
        self._hass = hass
        self._hub = hub

    @property
    def domain(self) -> str:
        return DOMAIN

    @property
    def entry_id(self) -> str:
        return self._hub.entry.entry_id

    def secret_matches(self, stored_hash: str | None, secret: str | None) -> bool:
        if not stored_hash or not secret:
            return False
        return hmac.compare_digest(stored_hash, hash_secret(secret))

    async def verify_pin(self, key: str, pin: str) -> dict[str, Any]:
        from .api import _check_pin

        stored = parent_pin.stored_pins(self._hub.entry.options)
        if not stored:
            return {"error": "no_pin"}
        lock = pin_lockout(self._hass, key)
        if wait := parent_pin.retry_in(lock.locked_until, dt_util.utcnow()):
            return {"error": "locked_out", "retry_in": wait}
        person, wait_for = await _check_pin(self._hass, key, stored, pin)
        if person:
            return {"person": person}
        return {"error": "wrong_pin", "retry_in": wait_for}

    async def check_caller(self, call: ServiceCall) -> None:
        await async_check_caller(self._hass, call)

    def page_url(self, device_id: str) -> str:
        return f"homeassistant://{URL_PATH}#panel-{device_id}"
