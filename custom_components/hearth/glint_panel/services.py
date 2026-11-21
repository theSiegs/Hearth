"""<domain>.set_panel, <domain>.set_panel_defaults, <domain>.get_panel, <domain>.change_panel_start and
<domain>.undo_panel_start: administrators and adults (and automations), as the host checks its other services. Answers
never carry a secret."""

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

from . import document, start
from .const import BY_SERVICE, HOUSE_KEYS, HOUSE_PANEL, IDENTIFIER_PREFIX, PANEL_KEYS, START_MAX_NAME
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
# Who made the change, when an agent calls: shown on the panel as "changed by ..."
_BY = vol.All(cv.string, vol.Length(min=1, max=START_MAX_NAME))
CHANGE_START_SCHEMA = vol.Schema(
    {
        vol.Required("device_id"): _DEVICES,
        vol.Required("ops"): vol.All(cv.ensure_list, [dict]),
        vol.Optional("by"): _BY,
    }
)
UNDO_START_SCHEMA = vol.Schema(
    {
        vol.Required("device_id"): _DEVICES,
        vol.Required("undo"): vol.All(cv.string, vol.Length(min=1, max=32)),
        vol.Optional("by"): _BY,
    }
)


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


async def _one_panel(hass: HomeAssistant, domain: str, call: ServiceCall) -> tuple[Panels, str]:
    panels = _loaded(hass, domain)
    await panels.host.check_caller(call)
    targets = _panel_ids(panels, call.data["device_id"])
    if len(targets) != 1:
        raise ServiceValidationError("Target one panel")
    return panels, targets[0]


def _start_answer(panels: Panels, device_id: str, said: list[str], undo: str) -> dict[str, Any]:
    return {"changed": "; ".join(said), "start": panels.start_section(device_id), "undo": undo}


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

    async def change_panel_start(call: ServiceCall) -> ServiceResponse:
        """The ops in order on the panel's Start, all or none; a first change starts from the room's layout the panel
        last reported. {changed: words, start, undo}."""
        panels, device_id = await _one_panel(hass, domain, call)
        known = panels.known()
        ctx = start.Context(
            seed=lambda: panels.room_layout(device_id), entity=known.entity, never_dealt=panels.never_dealt
        )
        try:
            tiles, said = start.apply(panels.start_tiles(device_id), call.data["ops"], ctx)
        except document.Refused as err:
            raise ServiceValidationError(str(err)) from err
        _version, undo = panels.set_start(device_id, tiles, call.data.get("by") or BY_SERVICE)
        return _start_answer(panels, device_id, said, undo)

    async def undo_panel_start(call: ServiceCall) -> ServiceResponse:
        """Puts back the Start from before change [undo] (any of the last 10), as a new change."""
        panels, device_id = await _one_panel(hass, domain, call)
        undo = call.data["undo"]
        try:
            tiles = panels.undo_start(device_id, undo)
        except document.Refused as err:
            raise ServiceValidationError(str(err)) from err
        _version, new_undo = panels.set_start(device_id, tiles, call.data.get("by") or BY_SERVICE)
        return _start_answer(panels, device_id, [f"change {undo} undone"], new_undo)

    hass.services.async_register(
        domain, "change_panel_start", change_panel_start, schema=CHANGE_START_SCHEMA,
        supports_response=SupportsResponse.OPTIONAL,
    )
    hass.services.async_register(
        domain, "undo_panel_start", undo_panel_start, schema=UNDO_START_SCHEMA,
        supports_response=SupportsResponse.OPTIONAL,
    )
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
