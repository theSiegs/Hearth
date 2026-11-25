"""The panel's WebSocket commands, on any Home Assistant login with the panel's device secret: subscribe (its document), report
(what it shows), verify_pin (a Parent PIN typed on it), set_start (its own Start, edited on the wall); and hello, with no
secret yet (a tablet being set up asks for one). Types are <domain>/panel/<name>."""

from __future__ import annotations

import json
from typing import Any

import voluptuous as vol
from homeassistant.components import websocket_api
from homeassistant.core import HomeAssistant, callback
from homeassistant.helpers.event import async_call_later

from . import start
from .const import BY_PANEL, MAX_PAGE, MAX_SEED_BYTES, MAX_STARTS, START_KINDS, ws_type
from .document import Refused
from .manager import HelloRefused, Panels

# The error while the serving integration reloads or hasn't loaded: retry after this many seconds
UNAVAILABLE = "unavailable"
UNAVAILABLE_RETRY = 5
# The error for a device secret that isn't this panel's (removed, paired again, or another panel's): the panel drops
# its secret and pairs again. Never Home Assistant's own "unauthorized" (a refused login token: the token is the
# owner's to fix, pairing again doesn't help)
UNKNOWN_PANEL = "unknown_panel"
# Kid time's changes come together (a status post recomputes everyone): one event for them, at most this often (s)
KIDS_EVERY = 2

_ID = vol.All(str, vol.Match(r"^[A-Za-z0-9_-]{8,64}$"))
_SECRET = vol.All(str, vol.Length(min=1, max=256))


def _side(value: Any) -> int:
    if not isinstance(value, int) or isinstance(value, bool) or not 1 <= value <= MAX_PAGE:
        raise vol.Invalid(f"a whole number from 1 to {MAX_PAGE}")
    return value


# The panel's page in cells (landscape: 8 x 5 today)
_PAGE = vol.Schema({vol.Required("cols"): _side, vol.Required("rows"): _side})


def _seed(value: Any) -> dict[str, Any]:
    if not isinstance(value, dict) or len(json.dumps(value)) > MAX_SEED_BYTES:
        raise vol.Invalid(f"an object of at most {MAX_SEED_BYTES} bytes as JSON")
    return value


def _words(most: int):
    return vol.All(str, vol.Length(max=most))


def _not_ready(connection, msg: dict[str, Any], domain: str) -> None:
    connection.send_error(
        msg["id"], UNAVAILABLE, f"Not ready: try again in {UNAVAILABLE_RETRY} s",
        translation_key=UNAVAILABLE, translation_domain=domain,
        translation_placeholders={"retry_in": str(UNAVAILABLE_RETRY)},
    )


def _panels(hass: HomeAssistant, domain: str, connection, msg: dict[str, Any]) -> Panels | None:
    """The panels, once the secret is the panel's; else the error sent."""
    panels = Panels.find(hass, domain)
    if panels is None:
        # Reloading, or not loaded yet: never "no PIN" (a panel keeps its door locked and tries again)
        _not_ready(connection, msg, domain)
        return None
    if not panels.authorized(msg["device_id"], msg["secret"]):
        connection.send_error(
            msg["id"], UNKNOWN_PANEL, "Not this panel's secret: pair again",
            translation_key=UNKNOWN_PANEL, translation_domain=domain,
        )
        return None
    return panels


def async_register_commands(hass: HomeAssistant, domain: str) -> None:
    @websocket_api.websocket_command(
        {
            vol.Required("type"): ws_type(domain, "hello"),
            vol.Required("device_id"): _ID,
            vol.Optional("name"): vol.Any(None, _words(64)),
            vol.Optional("model"): vol.Any(None, _words(64)),
            vol.Optional("version"): vol.Any(None, _words(32)),
            # The room: an area id or an area's name
            vol.Optional("area"): vol.Any(None, _words(100)),
            vol.Optional("seed"): vol.Any(None, _seed),
            # false: never take an offline panel's place (a second tablet in the room)
            vol.Optional("replaces"): vol.Any(None, bool),
        }
    )
    @callback
    def ws_hello(hass: HomeAssistant, connection: websocket_api.ActiveConnection, msg: dict[str, Any]) -> None:
        """A tablet being set up, on any login, with no secret yet: result null, then {"status": "pending"},
        {"status": "approved", device_id, secret, name, area_id, urls} or {"status": "denied"} (a pending one is
        answered later on the same subscription). Errors: taken (the id is a TV's or a phone's), try_later (too many
        wait), unavailable."""
        panels = Panels.find(hass, domain)
        if panels is None:
            _not_ready(connection, msg, domain)
            return
        msg_id = msg["id"]
        token = hass.auth.async_get_refresh_token(connection.refresh_token_id) if connection.refresh_token_id else None
        # The first answer comes right after the result null; later ones (an approval or a refusal in HA) straight out
        queued: list[dict[str, Any]] | None = []

        @callback
        def send(event: dict[str, Any]) -> None:
            if queued is not None:
                queued.append(event)
            else:
                connection.send_message(websocket_api.event_message(msg_id, event))

        try:
            unsubscribe = panels.hello(msg, connection.user, token.client_name if token else None, send)
        except HelloRefused as err:
            connection.send_error(
                msg_id, err.code, str(err), translation_key=f"hello_{err.code}", translation_domain=domain
            )
            return
        connection.subscriptions[msg_id] = unsubscribe
        connection.send_result(msg_id)
        first, queued = queued, None
        for event in first:
            connection.send_message(websocket_api.event_message(msg_id, event))

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
        user = connection.user
        panels.note_login(
            msg["device_id"], user.name if user else None, token.client_name if token else None,
            user.id if user else None,
        )
        # The ack of an approved hello: its secret is never sent again
        panels.taken_up(msg["device_id"])
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
            # The room's layout as the panel lays it out (built-in kinds only), to start a first change from
            vol.Optional("room_layout"): vol.Any(None, list),
            # The page it lays tiles on, {cols, rows}: the page a service's ops fit tiles on
            vol.Optional("page"): vol.Any(None, _PAGE),
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
        if msg.get("room_layout") is not None:
            # A tile of a kind this server doesn't know yet (a newer panel) is left out, not the whole report
            known = [t for t in msg["room_layout"] if not isinstance(t, dict) or t.get("kind") in START_KINDS]
            try:
                msg = {**msg, "room_layout": start.check_tiles(known, panels.never_dealt, built_in_only=True)}
            except Refused as err:
                _invalid(connection, msg["id"], domain, str(err))
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
        """{person} for an adult's Parent PIN; else error wrong_pin, locked_out (retry_in), no_pin (no adult has a
        Parent PIN) or unavailable (not ready: retry_in)."""
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

    @websocket_api.websocket_command(
        {
            vol.Required("type"): ws_type(domain, "set_start"),
            vol.Required("device_id"): _ID,
            vol.Required("secret"): _SECRET,
            vol.Required("start"): vol.Any(None, dict),
            vol.Optional("base_version", default=None): vol.Any(None, vol.All(str, vol.Length(max=32))),
        }
    )
    @callback
    def ws_set_start(hass: HomeAssistant, connection: websocket_api.ActiveConnection, msg: dict[str, Any]) -> None:
        """The panel's whole Start after an edit on the wall (null: the room's layout), made from [base_version]:
        {version, undo}; else error too_often, stale (version: the stored one) or invalid (why)."""
        panels = _panels(hass, domain, connection, msg)
        if panels is None:
            return
        device_id = msg["device_id"]
        if panels.too_many_starts(device_id):
            connection.send_error(msg["id"], "too_often", f"At most {MAX_STARTS} Start changes a minute")
            return
        stored = panels.start_version(device_id)
        if msg["base_version"] != stored:
            connection.send_error(
                msg["id"], "stale", f"Start was changed elsewhere (now {stored or 'null'})",
                translation_key="stale", translation_domain=domain,
                translation_placeholders={"version": stored or ""},
            )
            return
        try:
            tiles = start.check_start(msg["start"], panels.never_dealt, grid=panels.start_grid(device_id))
        except Refused as err:
            _invalid(connection, msg["id"], domain, str(err))
            return
        version, undo = panels.set_start(device_id, tiles, BY_PANEL)
        connection.send_result(msg["id"], {"version": version, "undo": undo})

    @websocket_api.websocket_command(
        {vol.Required("type"): ws_type(domain, "kids/subscribe"), vol.Required("device_id"): _ID, vol.Required("secret"): _SECRET}
    )
    @callback
    def ws_kids_subscribe(hass: HomeAssistant, connection: websocket_api.ActiveConnection, msg: dict[str, Any]) -> None:
        """Each kid's time today, read only (the host's kids_time): result null, then an event with it, and again when
        it changes (batched KIDS_EVERY; only when its version differs). Not part of the document: live minutes would
        change the document's version every minute."""
        panels = _panels(hass, domain, connection, msg)
        if panels is None:
            return
        msg_id = msg["id"]
        sent: dict[str, Any] = {"version": None, "cancel": None}

        @callback
        def send(_now=None) -> None:
            sent["cancel"] = None
            current = Panels.find(hass, domain)
            if current is None or not current.authorized(msg["device_id"], msg["secret"]):
                return
            body = current.host.kids_time()
            if body.get("version") != sent["version"]:
                sent["version"] = body.get("version")
                connection.send_message(websocket_api.event_message(msg_id, body))

        @callback
        def changed() -> None:
            if sent["cancel"] is None:
                sent["cancel"] = async_call_later(hass, KIDS_EVERY, send)

        unwatch = panels.host.watch_kids_time(changed)

        @callback
        def unsubscribe() -> None:
            unwatch()
            if sent["cancel"] is not None:
                sent["cancel"]()

        connection.subscriptions[msg_id] = unsubscribe
        connection.send_result(msg_id)
        send()

    for command in (ws_hello, ws_subscribe, ws_report, ws_verify_pin, ws_set_start, ws_kids_subscribe):
        websocket_api.async_register_command(hass, command)


def _invalid(connection: websocket_api.ActiveConnection, msg_id: int, domain: str, why: str) -> None:
    connection.send_error(
        msg_id, "invalid", f"Not a Start layout: {why}",
        translation_key="invalid", translation_domain=domain, translation_placeholders={"why": why},
    )
