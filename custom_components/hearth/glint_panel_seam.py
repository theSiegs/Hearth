"""Hearth's side of the Glint Panel seam: the one object glint_panel/ gets from Hearth (glint_panel/host.py says what
it may ask). Nothing here imports glint_panel/; the panels import nothing of Hearth's."""

from __future__ import annotations

import hmac
from typing import Any

from homeassistant.config_entries import SOURCE_INTEGRATION_DISCOVERY
from homeassistant.core import Context, HomeAssistant, ServiceCall
from homeassistant.util import dt as dt_util

from . import parent_pin
from .auth import async_check_caller, async_check_context, is_adult_user
from .const import DOMAIN, KIND_PANEL, PANEL_HELLO
from .hub import HearthHub, hash_secret, pin_lockout
from .notifications import clear_panel_hello, notify_panel_hello
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

    async def check_context(self, context: Context | None) -> None:
        await async_check_context(self._hass, context)

    def page_url(self, device_id: str) -> str:
        return f"homeassistant://{URL_PATH}#panel-{device_id}"

    def hash_secret(self, secret: str) -> str:
        return hash_secret(secret)

    def trusted(self, user: Any) -> bool:
        return user is not None and user.is_active and not user.system_generated and is_adult_user(
            self._hass, self._hub, user
        )

    def taken(self, device_id: str) -> bool:
        # hub.owned_by_another_kind: one id is one device, a TV's or a phone's id is never a panel's
        return self._hub.owned_by_another_kind(device_id, KIND_PANEL)

    def urls(self) -> dict[str, str | None]:
        from .api import _urls

        return _urls(self._hass)

    def hello_waiting(self, device_id: str, title: str, *, again: bool = False) -> None:
        if not again:
            notify_panel_hello(self._hass, device_id, title)
        unique_id = f"{PANEL_HELLO}{device_id}"
        if any(
            flow.get("context", {}).get("unique_id") == unique_id
            for flow in self._hass.config_entries.flow.async_progress_by_handler(DOMAIN)
        ):
            return
        self._hass.async_create_task(
            self._hass.config_entries.flow.async_init(
                DOMAIN, context={"source": SOURCE_INTEGRATION_DISCOVERY}, data={"panel_hello": device_id}
            )
        )

    def hello_answered(self, device_id: str) -> None:
        clear_panel_hello(self._hass, device_id)
        unique_id = f"{PANEL_HELLO}{device_id}"
        for flow in self._hass.config_entries.flow.async_progress_by_handler(DOMAIN):
            if flow.get("context", {}).get("unique_id") == unique_id:
                self._hass.config_entries.flow.async_abort(flow["flow_id"])
