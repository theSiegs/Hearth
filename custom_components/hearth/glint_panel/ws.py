"""The panel's WebSocket commands, on any Home Assistant login with the panel's device secret: subscribe (its document), report
(what it shows), verify_pin (a Parent PIN typed on it). Types are <domain>/panel/<name>."""

from __future__ import annotations

from typing import Any

import voluptuous as vol
from homeassistant.components import websocket_api
from homeassistant.core import HomeAssistant, callback

from .const import ws_type
from .manager import Panels

_ID = vol.All(str, vol.Match(r"^[A-Za-z0-9_-]{8,64}$"))
_SECRET = vol.All(str, vol.Length(min=1, max=256))


def _panels(hass: HomeAssistant, domain: str, connection, msg: dict[str, Any]) -> Panels | None:
    """The panels, once the secret is the panel's; else the error sent."""
    panels = Panels.find(hass, domain)
    if panels is None:
        connection.send_error(msg["id"], "not_set_up", "Panels aren't set up")
        return None
    if not panels.authorized(msg["device_id"], msg["secret"]):
        connection.send_error(msg["id"], websocket_api.ERR_UNAUTHORIZED, "Not this panel's secret")
        return None
    return panels


def async_register_commands(hass: HomeAssistant, domain: str) -> None:
    @websocket_api.websocket_command(
        {vol.Required("type"): ws_type(domain, "subscribe"), vol.Required("device_id"): _ID, vol.Required("secret"): _SECRET}
    )
    @callback
    def ws_subscribe(hass: HomeAssistant, connection: websocket_api.ActiveConnection, msg: dict[str, Any]) -> None:
        """Result null, then an event with the whole document, and again whenever it changes."""
        panels = _panels(hass, domain, connection, msg)
        if panels is None:
            return
        msg_id = msg["id"]
        token = hass.auth.async_get_refresh_token(connection.refresh_token_id) if connection.refresh_token_id else None
        panels.note_login(
            msg["device_id"], connection.user.name if connection.user else None, token.client_name if token else None
        )
        connection.send_result(msg_id)

        @callback
        def send(doc: dict[str, Any]) -> None:
            connection.send_message(websocket_api.event_message(msg_id, doc))

        connection.subscriptions[msg_id] = panels.subscribe(msg["device_id"], send)

    @websocket_api.websocket_command(
        {
            vol.Required("type"): ws_type(domain, "report"),
            vol.Required("device_id"): _ID,
            vol.Required("secret"): _SECRET,
            vol.Optional("view"): vol.Any(None, vol.All(str, vol.Length(max=32))),
            vol.Optional("version"): vol.Any(None, vol.All(str, vol.Length(max=32))),
            vol.Optional("on_tablet"): vol.Any(
                None, vol.All(str, vol.Length(max=1024)), vol.All([vol.All(str, vol.Length(max=256))], vol.Length(max=16))
            ),
            vol.Optional("sw_version"): vol.All(str, vol.Length(max=64)),
            vol.Optional("model"): vol.All(str, vol.Length(max=64)),
            vol.Optional("unpaired"): bool,
        }
    )
    @websocket_api.async_response
    async def ws_report(hass: HomeAssistant, connection: websocket_api.ActiveConnection, msg: dict[str, Any]) -> None:
        """What the panel shows and has; unpaired: true removes it."""
        panels = _panels(hass, domain, connection, msg)
        if panels is None:
            return
        device_id = msg["device_id"]
        if msg.get("unpaired"):
            connection.send_result(msg["id"])
            await panels.async_remove(device_id)
            return
        if panels.too_many_reports(device_id):
            connection.send_error(msg["id"], "too_often", "Report on change only")
            return
        panels.report(device_id, msg)
        connection.send_result(msg["id"])

    @websocket_api.websocket_command(
        {
            vol.Required("type"): ws_type(domain, "verify_pin"),
            vol.Required("device_id"): _ID,
            vol.Required("secret"): _SECRET,
            vol.Required("pin"): vol.All(str, vol.Length(max=16)),
        }
    )
    @websocket_api.async_response
    async def ws_verify_pin(hass: HomeAssistant, connection: websocket_api.ActiveConnection, msg: dict[str, Any]) -> None:
        """{person} for an adult's Parent PIN; else error wrong_pin, locked_out (retry_in) or no_pin."""
        panels = _panels(hass, domain, connection, msg)
        if panels is None:
            return
        answer = await panels.host.verify_pin(f"panel:{msg['device_id']}", msg["pin"])
        if answer.get("person"):
            connection.send_result(msg["id"], {"person": answer["person"]})
            return
        error, retry_in = answer.get("error") or "wrong_pin", int(answer.get("retry_in") or 0)
        message = {
            "wrong_pin": "Not a Parent PIN",
            "locked_out": f"Too many wrong PINs: try again in {retry_in} s",
            "no_pin": "No Parent PIN is set",
        }.get(error, "Not a Parent PIN")
        connection.send_error(
            msg["id"], error, message,
            translation_key=error, translation_domain=domain, translation_placeholders={"retry_in": str(retry_in)},
        )

    for command in (ws_subscribe, ws_report, ws_verify_pin):
        websocket_api.async_register_command(hass, command)
