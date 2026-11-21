"""<domain>.set_panel, <domain>.set_panel_defaults and <domain>.get_panel: administrators and adults (and
automations), as the host checks its other services. Answers never carry a secret."""

from __future__ import annotations

from typing import Any

import voluptuous as vol
from homeassistant.core import (
    HomeAssistant,
    ServiceCall,
    ServiceResponse,
    SupportsResponse,
)
from homeassistant.exceptions import ServiceValidationError
from homeassistant.helpers import config_validation as cv
from homeassistant.helpers import device_registry as dr

from . import document
from .const import HOUSE_KEYS, HOUSE_PANEL, IDENTIFIER_PREFIX, PANEL_KEYS
from .manager import Panels

_DEVICES = vol.All(cv.ensure_list, [cv.string])
SET_PANEL_SCHEMA = vol.Schema(
    {
        vol.Required("device_id"): _DEVICES,
        **{vol.Optional(key): vol.Any(None, object) for key in (*PANEL_KEYS, HOUSE_PANEL)},
    }
)
SET_DEFAULTS_SCHEMA = vol.Schema({vol.Optional(key): vol.Any(None, object) for key in HOUSE_KEYS})
GET_PANEL_SCHEMA = vol.Schema({vol.Optional("device_id"): _DEVICES})


def _loaded(hass: HomeAssistant, domain: str) -> Panels:
    panels = Panels.find(hass, domain)
    if panels is None:
        raise ServiceValidationError("Panels aren't set up")
    return panels


def _panel_ids(panels: Panels, registry_ids: list[str]) -> list[str]:
    """The panels of Home Assistant devices (the service's target); refused, naming it, when one isn't a panel."""
    registry = dr.async_get(panels.hass)
    found = []
    for registry_id in registry_ids:
        device = registry.async_get(registry_id)
        panel = next(
            (
                ident[len(IDENTIFIER_PREFIX):]
                for domain, ident in (device.identifiers if device else ())
                if domain == panels.domain and ident.startswith(IDENTIFIER_PREFIX)
            ),
            None,
        )
        if panel is None or not panels.has(panel):
            raise ServiceValidationError(f"Not a panel: {registry_id}")
        found.append(panel)
    return found


def async_register_services(hass: HomeAssistant, domain: str) -> None:
    async def set_panel(call: ServiceCall) -> ServiceResponse:
        panels = _loaded(hass, domain)
        await panels.host.check_caller(call)
        targets = _panel_ids(panels, call.data["device_id"])
        if len(targets) != 1:
            raise ServiceValidationError("Target one panel")
        known = panels.known()
        changes: dict[str, Any] = {}
        try:
            for key in PANEL_KEYS:
                if key in call.data:
                    changes[key] = document.panel_value(key, call.data[key], known)
        except document.Refused as err:
            raise ServiceValidationError(str(err)) from err
        if HOUSE_PANEL in call.data:
            on = call.data[HOUSE_PANEL]
            if on is not None and not isinstance(on, bool):
                raise ServiceValidationError("house_panel is true, false or null")
            changes[HOUSE_PANEL] = on
        panels.set_values(targets[0], changes)
        return document.public(panels.document(targets[0]))

    async def set_panel_defaults(call: ServiceCall) -> ServiceResponse:
        panels = _loaded(hass, domain)
        await panels.host.check_caller(call)
        known = panels.known()
        try:
            changes = {key: document.house_value(key, call.data[key], known) for key in HOUSE_KEYS if key in call.data}
        except document.Refused as err:
            raise ServiceValidationError(str(err)) from err
        panels.set_house(changes)
        return {"defaults": panels.describe_house()}

    async def get_panel(call: ServiceCall) -> ServiceResponse:
        panels = _loaded(hass, domain)
        await panels.host.check_caller(call)
        targets = _panel_ids(panels, call.data["device_id"]) if call.data.get("device_id") else sorted(panels.panels)
        return {"panels": [panels.describe(t) for t in targets], "defaults": panels.describe_house()}

    hass.services.async_register(
        domain, "set_panel", set_panel, schema=SET_PANEL_SCHEMA, supports_response=SupportsResponse.OPTIONAL
    )
    hass.services.async_register(
        domain, "set_panel_defaults", set_panel_defaults, schema=SET_DEFAULTS_SCHEMA,
        supports_response=SupportsResponse.OPTIONAL,
    )
    hass.services.async_register(
        domain, "get_panel", get_panel, schema=GET_PANEL_SCHEMA, supports_response=SupportsResponse.ONLY
    )
