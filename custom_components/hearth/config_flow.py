"""Setting up the household, and pairing each device (Hearth on a TV, Hearth Mobile on a phone or tablet).

The household is set up once (Settings > Devices & services > Add > Hearth). A device then asks to pair from its own
settings: it shows a code, and Home Assistant shows the same code as a discovered Hearth device. An administrator who
sees the codes match confirms, and the device gets its own secret. No token or webhook ID is typed anywhere.
"""

from __future__ import annotations

from typing import Any

import voluptuous as vol

from homeassistant.config_entries import ConfigFlow, ConfigFlowResult
from homeassistant.const import CONF_NAME

from .const import DOMAIN


class HearthConfigFlow(ConfigFlow, domain=DOMAIN):
    VERSION = 1

    _pairing_id: str

    async def async_step_user(self, user_input: dict[str, Any] | None = None) -> ConfigFlowResult:
        # One household (not the manifest's single_config_entry: that would also stop the TVs' pairing flows)
        if self._async_current_entries(include_ignore=False):
            return self.async_abort(reason="single_instance_allowed")
        if user_input is not None:
            return self.async_create_entry(title=user_input[CONF_NAME], data={CONF_NAME: user_input[CONF_NAME]})
        return self.async_show_form(
            step_id="user",
            data_schema=vol.Schema({vol.Required(CONF_NAME, default="Home"): str}),
        )

    async def async_step_integration_discovery(self, discovery_info: dict[str, Any]) -> ConfigFlowResult:
        """A device asked to pair (see api.PairStartView)."""
        self._pairing_id = discovery_info["pairing_id"]
        pairing = self._hub_pairing()
        if pairing is None:
            return self.async_abort(reason="expired")
        self.context["title_placeholders"] = {"name": pairing.name}
        return await self.async_step_confirm()

    async def async_step_confirm(self, user_input: dict[str, Any] | None = None) -> ConfigFlowResult:
        pairing = self._hub_pairing()
        if pairing is None:
            return self.async_abort(reason="expired")
        if user_input is not None:
            entries = self.hass.config_entries.async_loaded_entries(DOMAIN)
            if not entries or not await entries[0].runtime_data.async_approve(self._pairing_id):
                return self.async_abort(reason="expired")
            return self.async_abort(reason="paired", description_placeholders={"name": pairing.name})
        return self.async_show_form(
            step_id="confirm",
            description_placeholders={"name": pairing.name, "code": pairing.code},
        )

    def _hub_pairing(self):
        entries = self.hass.config_entries.async_loaded_entries(DOMAIN)
        return entries[0].runtime_data.pairing(self._pairing_id) if entries else None
