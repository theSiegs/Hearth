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
from homeassistant.util import dt as dt_util
from homeassistant.helpers.network import NoURLAvailableError, get_url
from homeassistant.util.network import is_local

from .const import DOMAIN, KIND_TV, KINDS, MAX_STATUS_BYTES, PAIRING_EXPIRES
from .hub import HearthHub, collect_secret, find_pairing
from .notifications import notify_pairing
from . import parent_pin
from .asks import AskError
from .status import clean_status, text
from .watch import MAX_EVENTS, clean_started

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
        notify_pairing(hass, pairing.pairing_id, pairing.name)
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
    {"status": "approved", "device_id", "secret", "urls": {"internal", "external"}}: where Home Assistant answers, at
    home and away (Home Assistant Cloud's when it's set up), either null when not known; a phone's app signs in there
    with Home Assistant's own login. An unknown or expired pairing is 404."""

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
        return web.json_response(
            {"status": "approved", "device_id": pairing.device_id, "secret": secret, "urls": _urls(hass)}
        )


def _urls(hass: HomeAssistant) -> dict[str, str | None]:
    def url(**kwargs) -> str | None:
        try:
            return get_url(hass, **kwargs)
        except NoURLAvailableError:
            return None

    return {
        "internal": url(allow_external=False, allow_cloud=False),
        "external": url(allow_internal=False, allow_ip=False, prefer_cloud=True),
    }


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
        # Loading (a restart, or a reload after an options change): not a refusal, or the device would unpair
        if hub is None:
            return _error(HTTPStatus.SERVICE_UNAVAILABLE, "not_set_up")
        if not hub.authorized(device_id, request.headers.get(HEADER_SECRET)):
            return _error(HTTPStatus.UNAUTHORIZED, "not_paired")
        if hub.too_often(device_id):
            return _error(HTTPStatus.TOO_MANY_REQUESTS, "too_often")
        status = clean_status(await _json_body(request))
        if status is None:
            return _error(HTTPStatus.BAD_REQUEST, "bad_request")
        hub.update_status(device_id, status)
        # What the device is told: each profile's (or the phone's person's) limits today
        return web.json_response({"ok": True, "state": hub.household.document_for(device_id)})


class EventsView(HomeAssistantView):
    """POST /api/hearth/device/{device_id}/events (header X-Hearth-Secret): {"events": [...]}, at most 50, each
    {"type": "video_started", "profile_id", "t" (ms), "v" (video id), "title", "ch" (channel), "cid" (channel id)}:
    what a kids profile started in HearthTube. A TV only. Answers {"ok": true, "added": n} once all are taken (a
    resend is harmless, and an entry of a profile mapped to no one, or one that isn't valid, is dropped), so the TV
    can mark them sent."""

    url = "/api/hearth/device/{device_id}/events"
    name = "api:hearth:device:events"
    requires_auth = False

    async def post(self, request: web.Request, device_id: str) -> web.Response:
        hass: HomeAssistant = request.app["hass"]
        if not _local(request):
            return _error(HTTPStatus.FORBIDDEN, "not_local")
        hub = _hub(hass)
        if hub is None:
            return _error(HTTPStatus.SERVICE_UNAVAILABLE, "not_set_up")
        if not hub.authorized(device_id, request.headers.get(HEADER_SECRET)):
            return _error(HTTPStatus.UNAUTHORIZED, "not_paired")
        if hub.kind(device_id) != KIND_TV:
            return _error(HTTPStatus.FORBIDDEN, "not_a_tv")
        if hub.too_many_events(device_id):
            return _error(HTTPStatus.TOO_MANY_REQUESTS, "too_often")
        body = await _json_body(request)
        events = body.get("events") if isinstance(body, dict) else None
        if not isinstance(events, list) or len(events) > MAX_EVENTS:
            return _error(HTTPStatus.BAD_REQUEST, "bad_request")
        household = hub.household
        now_ms = int(dt_util.utcnow().timestamp() * 1000)
        added = 0
        for raw in events:
            entry = clean_started(raw, now_ms)
            person = household.profile_person(entry["profile_id"]) if entry else None
            if entry and person and household.watch.add_started(person, entry, device_id):
                added += 1
        if added:
            household.watch.changed()
        return web.json_response({"ok": True, "added": added})


class VerifyPinView(HomeAssistantView):
    """POST /api/hearth/device/{device_id}/verify_pin (header X-Hearth-Secret): {"pin": "1234"} -> {"ok": true, "person":
    "person.alex"} or {"ok": false}.

    Checks the adults' parent PINs (Configure > Parent PINs), any of them; the answer says whose it was, and
    hearth_parent_pin_used tells automations. The device never gets a PIN or a hash. After
    parent_pin.FREE_TRIES wrong ones in a row the device waits, longer each time: 429 {"error": "locked_out",
    "retry_in": s}, and a wrong answer says its own "retry_in" once it starts one. 404 "no_pin" when none is set (the
    device uses its own). Any paired device may ask."""

    url = "/api/hearth/device/{device_id}/verify_pin"
    name = "api:hearth:device:verify_pin"
    requires_auth = False

    async def post(self, request: web.Request, device_id: str) -> web.Response:
        hass: HomeAssistant = request.app["hass"]
        if not _local(request):
            return _error(HTTPStatus.FORBIDDEN, "not_local")
        hub = _hub(hass)
        if hub is None:
            return _error(HTTPStatus.SERVICE_UNAVAILABLE, "not_set_up")
        if not hub.authorized(device_id, request.headers.get(HEADER_SECRET)):
            return _error(HTTPStatus.UNAUTHORIZED, "not_paired")
        stored = parent_pin.stored_pins(hub.entry.options)
        if not stored:
            return _error(HTTPStatus.NOT_FOUND, "no_pin")
        state = hub.state(device_id)
        now = dt_util.utcnow()
        if wait := parent_pin.retry_in(state.pin_locked_until, now):
            return web.json_response({"error": "locked_out", "retry_in": wait}, status=HTTPStatus.TOO_MANY_REQUESTS)
        body = await _json_body(request)
        pin = body.get("pin") if isinstance(body, dict) else None
        if not isinstance(pin, str):
            return _error(HTTPStatus.BAD_REQUEST, "bad_request")
        # Counted before the slow check, so parallel guesses can't all slip in under the free tries
        state.pin_failures += 1
        if person := await hass.async_add_executor_job(parent_pin.whose, stored, pin):
            state.pin_failures = 0
            state.pin_locked_until = None
            hass.bus.async_fire(parent_pin.EVENT_PARENT_PIN_USED, {"device_id": device_id, "person": person})
            return web.json_response({"ok": True, "person": person})
        answer: dict[str, Any] = {"ok": False}
        if wait_for := parent_pin.lockout(state.pin_failures):
            state.pin_locked_until = dt_util.utcnow() + wait_for
            answer["retry_in"] = parent_pin.retry_in(state.pin_locked_until, dt_util.utcnow())
            hass.bus.async_fire(
                parent_pin.EVENT_PARENT_PIN_LOCKED_OUT,
                {"device_id": device_id, "failures": state.pin_failures, "retry_in": answer["retry_in"]},
            )
        return web.json_response(answer)


class AskView(HomeAssistantView):
    """POST /api/hearth/device/{device_id}/ask (header X-Hearth-Secret): {"minutes": 15|30|45|60, "group": "all" or a
    group id, "note": short text, "profile_id": a TV's profile (a phone asks for its own person)} -> {"ok": true,
    "request": {id, status, minutes, asked_minutes, group, expires}}. 409 already_open (with that request), 429 cooldown
    (with retry_in) after a "not now", 400 for anything else wrong, 404 no_person when the profile is nobody's. The
    answer comes in the person's state document ("request") with the next status answers."""

    url = "/api/hearth/device/{device_id}/ask"
    name = "api:hearth:device:ask"
    requires_auth = False

    async def post(self, request: web.Request, device_id: str) -> web.Response:
        hass: HomeAssistant = request.app["hass"]
        if not _local(request):
            return _error(HTTPStatus.FORBIDDEN, "not_local")
        hub = _hub(hass)
        if hub is None:
            return _error(HTTPStatus.SERVICE_UNAVAILABLE, "not_set_up")
        if not hub.authorized(device_id, request.headers.get(HEADER_SECRET)):
            return _error(HTTPStatus.UNAUTHORIZED, "not_paired")
        if hub.too_many_events(device_id):
            return _error(HTTPStatus.TOO_MANY_REQUESTS, "too_often")
        body = await _json_body(request)
        if not isinstance(body, dict) or not isinstance(body.get("minutes", 15), int):
            return _error(HTTPStatus.BAD_REQUEST, "bad_request")
        if hub.kind(device_id) == KIND_TV:
            profile_id = text(body.get("profile_id"), 64) or (hub.state(device_id).status or {}).get("profile_id")
            person = hub.household.profile_person(profile_id) if profile_id else None
        else:
            person = hub.household.device_person(device_id)
        if not person:
            return _error(HTTPStatus.NOT_FOUND, "no_person")
        try:
            ask = hub.asks.ask(
                person, body.get("minutes", 15), text(body.get("group"), 64) or "all", text(body.get("note"), 200), device_id
            )
        except AskError as err:
            if err.code == "already_open":
                return web.json_response(
                    {"error": "already_open", "request": err.detail.device_view()}, status=HTTPStatus.CONFLICT
                )
            if err.code == "cooldown":
                return web.json_response(
                    {"error": "cooldown", "retry_in": err.detail}, status=HTTPStatus.TOO_MANY_REQUESTS
                )
            return _error(HTTPStatus.BAD_REQUEST, err.code)
        return web.json_response({"ok": True, "request": ask.device_view()})


def async_register_views(hass: HomeAssistant) -> None:
    for view in (PairStartView, PairStatusView, StatusView, EventsView, VerifyPinView, AskView):
        hass.http.register_view(view())
