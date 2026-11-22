"""The seam: everything Glint Panel needs from the integration that serves it, and nothing more.

The package imports nothing else of the integration's (ha_tests/test_glint_panel.py checks). What it needs from the
serving integration (today Hearth, through glint_panel_seam.py) comes through this interface; a new need is added here,
never as an import.
"""

from __future__ import annotations

from typing import Any, Protocol

from homeassistant.core import Context, ServiceCall


class PanelHost(Protocol):
    @property
    def domain(self) -> str:
        """The serving integration's domain: every wire name, the store key and `served_by` come from it."""

    @property
    def entry_id(self) -> str:
        """The config entry the panels' devices belong to."""

    def secret_matches(self, stored_hash: str | None, secret: str | None) -> bool:
        """Whether [secret] is the one whose hash pairing kept (compared in constant time)."""

    async def verify_pin(self, key: str, pin: str) -> dict[str, Any]:
        """A Parent PIN typed on the panel [key] (its lockout's own key): {"person"} when it's an adult's, else
        {"error": "wrong_pin" | "locked_out" | "no_pin", "retry_in": seconds}. Counted in the integration's lockout."""

    async def check_caller(self, call: ServiceCall) -> None:
        """Raises Unauthorized unless the call is an administrator's, an adult's or an automation's."""

    async def check_context(self, context: Context | None) -> None:
        """check_caller for an entity's service call (its context): no user (an automation, the system) may."""

    def page_url(self, device_id: str) -> str:
        """The panel's card on the integration's page (the device's configuration_url)."""
