"""What a Hearth device (Hearth on a TV, Hearth Mobile on a phone or tablet) calls: pairing, and posting its status.

All of it answers local network addresses only (a phone away from home is a later step, see
docs/home-assistant-integration.md). The device proves who it is with its own secret (header X-Hearth-Secret), made
at pairing; it works on these endpoints only, never as a Home Assistant login. A refused secret gets a plain 401
answer, not a failed login, so a device removed from the household isn't banned from Home Assistant's other pages
for posting with its old one.
"""

from __future__ import annotations

from http import HTTPStatus
from ipaddress import ip_address
import json
import re
from typing import Any

from aiohttp import web

from homeassistant.components.http import HomeAssistantView
from homeassistant.config_entries import SOURCE_INTEGRATION_DISCOVERY
from homeassistant.core import HomeAssistant
from homeassistant.util.network import is_local

from .const import DOMAIN, KIND_TV, KINDS, MAX_STATUS_BYTES, PAIRING_EXPIRES
from .hub import HearthHub, collect_secret, find_pairing
from .status import clean_status, text

HEADER_SECRET = "X-Hearth-Secret"
HEADER_NONCE = "X-Hearth-Nonce"

_ID = re.compile(r"^[A-Za-z0-9_-]{8,64}$")
_NONCE = re.compile(r"^[A-Za-z0-9_-]{32,128}$")


def _hub(hass: HomeAssistant) -> HearthHub | None:
    entries = hass.config_entries.async_loaded_entries(DOMAIN)
    return entries[0].runtime_data if entries else None


def _local(request: web.Request) -> bool:
    try:
        return request.remote is not None and is_local(ip_address(request.remote))
    except ValueError:
        return False


def _error(status: HTTPStatus, reason: str) -> web.Response:
    return web.json_response({"error": reason}, status=status)


async def _json_body(request: web.Request) -> Any:
    if request.content_length is not None and request.content_length > MAX_STATUS_BYTES:
        return None
    body = await request.content.read(MAX_STATUS_BYTES + 1)
    if len(body) > MAX_STATUS_BYTES:
        return None
    try:
        return json.loads(body)
    except ValueError:
        return None


class PairStartView(HomeAssistantView):
    """POST /api/hearth/pair {device_id, kind, name, model, version, nonce} -> {pairing_id, code, expires_in}.

    The device shows the code; an administrator checks it matches in Home Assistant (Settings > Devices & services, a
    discovered Hearth device) and confirms.
    """

    url = "/api/hearth/pair"
    name = "api:hearth:pair"
    requires_auth = False

    async def post(self, request: web.Request) -> web.Response:
        hass: HomeAssistant = request.app["hass"]
        if not _local(request):
            return _error(HTTPStatus.FORBIDDEN, "not_local")
        hub = _hub(hass)
        if hub is None:
            return _error(HTTPStatus.NOT_FOUND, "not_set_up")
        body = await _json_body(request)
        if not isinstance(body, dict):
            return _error(HTTPStatus.BAD_REQUEST, "bad_request")
        device_id, nonce = body.get("device_id"), body.get("nonce")
        kind = body.get("kind", KIND_TV)
        name = text(body.get("name"), 64)
        if (
            not isinstance(device_id, str)
            or not _ID.match(device_id)
            or not isinstance(nonce, str)
            or not _NONCE.match(nonce)
            or kind not in KINDS
        ):
            return _error(HTTPStatus.BAD_REQUEST, "bad_request")
        pairing = hub.start_pairing(
            request.remote or "",
            device_id,
            kind,
            name or ("TV" if kind == KIND_TV else "Phone"),
            text(body.get("model"), 64),
            text(body.get("version"), 32),
            nonce,
        )
        if pairing is None:
            return _error(HTTPStatus.TOO_MANY_REQUESTS, "try_later")
        hass.async_create_task(
            hass.config_entries.flow.async_init(
                DOMAIN,
                context={"source": SOURCE_INTEGRATION_DISCOVERY},
                data={"pairing_id": pairing.pairing_id},
            )
        )
        return web.json_response(
            {
                "pairing_id": pairing.pairing_id,
                "code": pairing.code,
                "expires_in": int(PAIRING_EXPIRES.total_seconds()),
            }
        )


class PairStatusView(HomeAssistantView):
    """GET /api/hearth/pair/{pairing_id} (header X-Hearth-Nonce) -> {"status": "pending" | "denied"} or, once,
    {"status": "approved", "device_id", "secret"}. An unknown or expired pairing is 404."""

    url = "/api/hearth/pair/{pairing_id}"
    name = "api:hearth:pair:status"
    requires_auth = False

    async def get(self, request: web.Request, pairing_id: str) -> web.Response:
        hass: HomeAssistant = request.app["hass"]
        if not _local(request):
            return _error(HTTPStatus.FORBIDDEN, "not_local")
        # Not through the entry: approving saves the device and reloads the entry, and this must answer meanwhile
        pairing = find_pairing(hass, pairing_id, request.headers.get(HEADER_NONCE))
        if pairing is None:
            return _error(HTTPStatus.NOT_FOUND, "unknown")
        if pairing.denied:
            return web.json_response({"status": "denied"})
        secret = collect_secret(hass, pairing)
        if secret is None:
            return web.json_response({"status": "pending"})
        return web.json_response({"status": "approved", "device_id": pairing.device_id, "secret": secret})


class StatusView(HomeAssistantView):
    """POST /api/hearth/device/{device_id}/status (header X-Hearth-Secret): the device's status JSON."""

    url = "/api/hearth/device/{device_id}/status"
    name = "api:hearth:device:status"
    requires_auth = False

    async def post(self, request: web.Request, device_id: str) -> web.Response:
        hass: HomeAssistant = request.app["hass"]
        if not _local(request):
            return _error(HTTPStatus.FORBIDDEN, "not_local")
        hub = _hub(hass)
        if hub is None or not hub.authorized(device_id, request.headers.get(HEADER_SECRET)):
            return _error(HTTPStatus.UNAUTHORIZED, "not_paired")
        if hub.too_often(device_id):
            return _error(HTTPStatus.TOO_MANY_REQUESTS, "too_often")
        status = clean_status(await _json_body(request))
        if status is None:
            return _error(HTTPStatus.BAD_REQUEST, "bad_request")
        hub.update_status(device_id, status)
        # What the device is told: each profile's (or the phone's person's) limits today
        return web.json_response({"ok": True, "state": hub.household.document_for(device_id)})


def async_register_views(hass: HomeAssistant) -> None:
    for view in (PairStartView, PairStatusView, StatusView):
        hass.http.register_view(view())
