"""Client settings on Home Assistant's WebSocket, for an adult's app (client_settings.py, docs/contracts/client-settings.md).

Administrators and the users linked to an adult on Hearth's page (auth.py) read and write every scope, kept with
updated_by "adult". `hearth/client_settings/subscribe` sends {client, scope, name, etag} for each change (etag null:
it went), never the contents. `hearth/client_settings/clear` (Hearth's page, administrators) removes everything kept for
one client.
"""

from __future__ import annotations

from typing import Any

import voluptuous as vol

from homeassistant.components import websocket_api
from homeassistant.core import HomeAssistant, callback
from homeassistant.helpers.dispatcher import async_dispatcher_connect

from .auth import is_adult_user
from .client import client_id
from .client_settings import (
    BY_ADULT,
    DEVICE,
    PERSON,
    SIGNAL_CLIENT_SETTINGS,
    SettingsError,
    parse_scope,
    valid_name,
)
from .const import CONF_PERSON, DOMAIN

_CLIENT = vol.All(str, vol.Length(min=1, max=128))
_ADDRESS = {
    vol.Required("client"): _CLIENT,
    vol.Required("scope"): vol.All(str, vol.Length(min=1, max=80)),
    vol.Required("name"): vol.All(str, vol.Length(min=1, max=64)),
}


def _hub(hass: HomeAssistant):
    entries = hass.config_entries.async_loaded_entries(DOMAIN)
    return entries[0].runtime_data if entries else None


def _start(hass: HomeAssistant, connection, msg, address: bool = True):
    """(hub, client, scope) after the caller's checks, or None after an error was sent."""
    hub = _hub(hass)
    if hub is None:
        connection.send_error(msg["id"], "not_set_up", "Hearth isn't set up")
        return None
    if not is_adult_user(hass, hub, connection.user):
        connection.send_error(msg["id"], websocket_api.ERR_UNAUTHORIZED, "Unauthorized")
        return None
    if not address:
        return hub, None, None
    scope = parse_scope(msg["scope"])
    if client_id(msg["client"]) is None or scope is None or not valid_name(msg["name"]):
        connection.send_error(msg["id"], "invalid", "A client id, a scope (household, person:<id>, device:<id>) and a name")
        return None
    if scope[0] == DEVICE and scope[1] not in hub.devices:
        connection.send_error(msg["id"], websocket_api.ERR_NOT_FOUND, "No such device")
        return None
    return hub, msg["client"], scope


def _refused(connection, msg, err: SettingsError) -> None:
    if err.code == "changed":
        connection.send_error(msg["id"], "changed", f"The document changed: its etag is {err.etag}")
    else:
        connection.send_error(msg["id"], err.code, err.code.replace("_", " "))


@websocket_api.websocket_command({vol.Required("type"): "hearth/client_settings/list", vol.Optional("client"): _CLIENT})
@callback
def ws_list(hass: HomeAssistant, connection: websocket_api.ActiveConnection, msg: dict[str, Any]) -> None:
    """Every document's envelope and size (one client's, or all), never the data."""
    if (started := _start(hass, connection, msg, address=False)) is None:
        return
    hub = started[0]
    connection.send_result(msg["id"], {"documents": hub.client_settings.listing(msg.get("client"))})


@websocket_api.websocket_command({vol.Required("type"): "hearth/client_settings/get", **_ADDRESS})
@callback
def ws_get(hass: HomeAssistant, connection: websocket_api.ActiveConnection, msg: dict[str, Any]) -> None:
    if (started := _start(hass, connection, msg)) is None:
        return
    hub, client, scope = started
    doc = hub.client_settings.get(client, scope, msg["name"])
    if doc is None:
        connection.send_error(msg["id"], websocket_api.ERR_NOT_FOUND, "No such document")
        return
    connection.send_result(msg["id"], doc)


@websocket_api.websocket_command(
    {
        vol.Required("type"): "hearth/client_settings/set",
        **_ADDRESS,
        vol.Required("schema"): str,
        vol.Required("data"): dict,
        vol.Optional("label"): vol.Any(None, str),
        vol.Optional("if_etag"): vol.Any(None, str),
    }
)
@callback
def ws_set(hass: HomeAssistant, connection: websocket_api.ActiveConnection, msg: dict[str, Any]) -> None:
    """Saves a document as an adult: its envelope (without data)."""
    if (started := _start(hass, connection, msg)) is None:
        return
    hub, client, scope = started
    try:
        doc = hub.client_settings.put(
            client,
            scope,
            msg["name"],
            msg["schema"],
            msg["data"],
            BY_ADULT,
            msg["if_etag"] if "if_etag" in msg else ...,
            msg.get("label"),
        )
    except SettingsError as err:
        _refused(connection, msg, err)
        return
    connection.send_result(msg["id"], doc)


@websocket_api.websocket_command(
    {vol.Required("type"): "hearth/client_settings/delete", **_ADDRESS, vol.Optional("if_etag"): vol.Any(None, str)}
)
@callback
def ws_delete(hass: HomeAssistant, connection: websocket_api.ActiveConnection, msg: dict[str, Any]) -> None:
    if (started := _start(hass, connection, msg)) is None:
        return
    hub, client, scope = started
    try:
        gone = hub.client_settings.delete(client, scope, msg["name"], msg["if_etag"] if "if_etag" in msg else ...)
    except SettingsError as err:
        _refused(connection, msg, err)
        return
    if not gone:
        connection.send_error(msg["id"], websocket_api.ERR_NOT_FOUND, "No such document")
        return
    connection.send_result(msg["id"], {"ok": True})


@websocket_api.websocket_command(
    {
        vol.Required("type"): "hearth/client_settings/subscribe",
        vol.Optional("client"): _CLIENT,
        vol.Optional("person"): vol.All(str, vol.Length(min=1, max=80)),
    }
)
@callback
def ws_subscribe(hass: HomeAssistant, connection: websocket_api.ActiveConnection, msg: dict[str, Any]) -> None:
    """Each change from now on: {client, scope, name, etag} (etag null: it went). With [person]: only that person's
    documents and the device documents of their paired devices (looked up at each change), never anyone else's."""
    if _start(hass, connection, msg, address=False) is None:
        return
    only = msg.get("client")
    person = msg.get("person")

    def about_person(scope: str) -> bool:
        parsed = parse_scope(scope)
        if parsed is None:
            return False
        if parsed[0] == PERSON:
            return parsed[1] == person
        if parsed[0] == DEVICE:
            hub = _hub(hass)
            return hub is not None and (hub.devices.get(parsed[1]) or {}).get(CONF_PERSON) == person
        return False

    @callback
    def changed(client: str, scope: str, name: str, etag: str | None) -> None:
        if only is not None and client != only:
            return
        if person is not None and not about_person(scope):
            return
        # The caller is checked again: a user who's no longer an adult stops hearing
        if not is_adult_user(hass, _hub(hass), connection.user):
            return
        connection.send_message(
            websocket_api.event_message(msg["id"], {"client": client, "scope": scope, "name": name, "etag": etag})
        )

    connection.subscriptions[msg["id"]] = async_dispatcher_connect(hass, SIGNAL_CLIENT_SETTINGS, changed)
    connection.send_result(msg["id"])


@websocket_api.require_admin
@websocket_api.websocket_command({vol.Required("type"): "hearth/client_settings/clear", vol.Required("client"): _CLIENT})
@callback
def ws_clear(hass: HomeAssistant, connection: websocket_api.ActiveConnection, msg: dict[str, Any]) -> None:
    """Hearth's page: everything kept for one client goes."""
    if (started := _start(hass, connection, msg, address=False)) is None:
        return
    connection.send_result(msg["id"], {"removed": started[0].client_settings.clear_client(msg["client"])})


@callback
def async_register_commands(hass: HomeAssistant) -> None:
    for command in (ws_list, ws_get, ws_set, ws_delete, ws_subscribe, ws_clear):
        websocket_api.async_register_command(hass, command)


