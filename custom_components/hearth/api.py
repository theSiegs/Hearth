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
import math
import re
from typing import Any

from aiohttp import web
import voluptuous as vol

from homeassistant.components.http import HomeAssistantView
from homeassistant.config_entries import SOURCE_INTEGRATION_DISCOVERY
from homeassistant.core import HomeAssistant
from homeassistant.util import dt as dt_util
from homeassistant.helpers.network import NoURLAvailableError, get_url
from homeassistant.util.network import is_local

from .const import (
    CAP_EVENTS,
    CAP_PUSH,
    CONF_PUSH_SERVER,
    CONF_ROLES,
    CONTRACT,
    DOMAIN,
    KIND_MOBILE,
    KIND_PANEL,
    KIND_TV,
    KINDS,
    MAX_STATUS_BYTES,
    PAIRING_EXPIRES,
    TICKET_EXPIRES,
    TICKET_KINDS,
)
from .hub import HearthHub, collect_secret, find_pairing, pin_lockout, save_pin_lockouts
from .wait import WAIT_MAX
from .push import clean_server, push_answer
from .attention import async_note_admins
from .notifications import notify_pairing
from . import notices, parent_pin, switch_approval
from .asks import AskError
from .status import clean_status, text
from .watch import MAX_EVENTS, clean_started
from .client import clean_client, locked
from .glint_agent import hearth_only
from .client_settings import MAX_DATA_BYTES, SettingsError, device_write, may_read, parse_scope, valid_name
from .pin_grants import GRANT_SECONDS, GRANT_WRITES

HEADER_SECRET = "X-Hearth-Secret"
HEADER_NONCE = "X-Hearth-Nonce"

_ID = re.compile(r"^[A-Za-z0-9_-]{8,64}$")
_NONCE = re.compile(r"^[A-Za-z0-9_-]{32,128}$")
# A panel's pair body may carry its settings from before it paired (glint_panel/, docs/contracts/panel-config.md)
MAX_SEED_BYTES = 16 * 1024
_DEFAULT_NAMES = {KIND_TV: "TV", KIND_MOBILE: "Phone", KIND_PANEL: "Panel"}


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


async def _json_body(request: web.Request, limit: int = MAX_STATUS_BYTES) -> Any:
    if request.content_length is not None and request.content_length > limit:
        return None
    # StreamReader.read(n) returns what has arrived so far, not n bytes: a body split across TCP segments would be
    # cut short. Read to the end, but never past the limit.
    body = bytearray()
    while chunk := await request.content.read(limit + 1 - len(body)):
        body += chunk
        if len(body) > limit:
            return None
    try:
        return json.loads(body)
    except (ValueError, RecursionError):
        # RecursionError: nesting deep enough ("[" * 60000 fits the size limit) is no body of ours
        return None


def _pair_client(body: dict[str, Any]) -> tuple[bool, dict[str, Any] | None]:
    """(valid, the client) from a pair or redeem body: a device that sends none is a contract-2 device (no client
    locked); one that sends a client that isn't valid is refused, so its developer hears of it."""
    if body.get("client") is None:
        return True, None
    found = clean_client(body["client"])
    return found is not None, found


class PairStartView(HomeAssistantView):
    """POST /api/hearth/pair {device_id, kind, name, model, version, nonce, client?, person_name?, role?} ->
    {pairing_id, code, expires_in, approvers}.

    The device shows the code; an administrator checks it matches in Home Assistant (Hearth's page, their phone's
    notification with Approve and Deny, or Settings > Devices & services, a
    discovered Hearth device) and confirms. `client` ({"id", "version", "contract", "companions"}, client.py) is shown
    to the administrator and locked when they confirm.
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
        client_ok, client = _pair_client(body)
        if (
            not isinstance(device_id, str)
            or not _ID.match(device_id)
            or not isinstance(nonce, str)
            or not _NONCE.match(nonce)
            or kind not in KINDS
            or not client_ok
        ):
            return _error(HTTPStatus.BAD_REQUEST, "bad_request")
        seed = body.get("seed") if kind == KIND_PANEL else None
        if kind == KIND_PANEL and (
            kind not in hub.pairing_kinds
            or (seed is not None and (not isinstance(seed, dict) or len(json.dumps(seed)) > MAX_SEED_BYTES))
        ):
            return _error(HTTPStatus.BAD_REQUEST, "bad_request")
        # One id is one device: a panel never pairs over a TV or a phone, nor they over a panel
        if (kind == KIND_PANEL and device_id in hub.devices) or (
            kind != KIND_PANEL and KIND_PANEL in hub.pairing_kinds and hub.pairing_kinds[KIND_PANEL].owns(device_id)
        ):
            return _error(HTTPStatus.BAD_REQUEST, "bad_request")
        pairing = hub.start_pairing(
            request.remote or "",
            device_id,
            kind,
            name or _DEFAULT_NAMES[kind],
            text(body.get("model"), 64),
            text(body.get("version"), 32),
            nonce,
            client,
            # Who a phone says it's for, shown to the administrators asked (never trusted further)
            text(body.get("person_name"), 64) if kind == KIND_MOBILE else None,
            body.get("role") if kind == KIND_MOBILE and body.get("role") in ("adult", "kid") else None,
        )
        if pairing is None:
            return _error(HTTPStatus.TOO_MANY_REQUESTS, "try_later")
        pairing.seed = seed
        approvers = await async_note_admins(hass)
        notify_pairing(hass, pairing.pairing_id, pairing.name, pairing)
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
                # Who is asked to approve: the administrators, by name, and whether a phone of theirs got the notice
                # (with Approve and Deny); every one of them also sees it in Home Assistant's bell
                "approvers": approvers,
            }
        )


class PairStatusView(HomeAssistantView):
    """GET /api/hearth/pair/{pairing_id} (header X-Hearth-Nonce) -> {"status": "pending" | "denied"} or, once,
    {"status": "approved", "device_id", "secret", "person", "role": "kid" | "adult" | null, "urls": {"internal",
    "external"}}: whose phone it is, and where Home Assistant answers, at
    home and away (Home Assistant Cloud's when it's set up), either null when not known; a phone's app signs in there
    with Home Assistant's own login. A phone's answer also has "push": {"server", "topic"} (its ntfy channel, push.py)
    or null when the household has no push server. An unknown or expired pairing is 404."""

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
        return web.json_response(_approved(hass, pairing, secret))


def _approved(hass: HomeAssistant, pairing, secret: str) -> dict[str, Any]:
    """What an approved device is told, once: its secret, whose it is, and where Home Assistant answers."""
    # Whose phone it is, and whether they're a kid or an adult (as set on Hearth's page; null when not set). The
    # entry's options are read even while it reloads (approving the device reloads it)
    entries = hass.config_entries.async_entries(DOMAIN)
    options = entries[0].options if entries else {}
    roles = options.get(CONF_ROLES, {})
    return {
        "status": "approved",
        "contract": CONTRACT,
        "device_id": pairing.device_id,
        "secret": secret,
        "urls": _urls(hass),
        "person": pairing.person,
        "role": roles.get(pairing.person) if pairing.person else None,
        # A phone's push channel: where to listen for "changed" (push.py); null without a push server
        "push": push_answer(_server(options), pairing.push_topic) if pairing.kind == KIND_MOBILE else None,
        # The client locked with this pairing ({"id", "companions"}), null when the device sent none
        "client": locked(pairing.client),
        # What the device's kind adds (a Glint Panel's ha_token), handed over once with the secret
        **pairing.answer,
    }


class TicketView(HomeAssistantView):
    """POST /api/hearth/device/{device_id}/ticket (header X-Hearth-Secret, a paired TV): {"kind": "tv"} for another
    TV of its household, or {"kind": "mobile", "person": "person.x"} for a phone an adult bound as that adult's ->
    {"ticket", "expires_in"}. The ticket pairs one device at once through /api/hearth/pair/redeem, with no code to
    check: the paired TV vouches for it. Single use, five minutes."""

    url = "/api/hearth/device/{device_id}/ticket"
    name = "api:hearth:device:ticket"
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
        body = await _json_body(request)
        if not isinstance(body, dict) or body.get("kind") not in TICKET_KINDS:
            return _error(HTTPStatus.BAD_REQUEST, "bad_request")
        kind, person = body["kind"], body.get("person")
        if kind == KIND_MOBILE:
            # Only for an adult on Hearth's page: a ticket never makes a kid's phone, or an unknown person's
            if not isinstance(person, str) or hub.entry.options.get(CONF_ROLES, {}).get(person) != "adult":
                return _error(HTTPStatus.FORBIDDEN, "not_an_adult")
        if hub.too_often(device_id):
            return _error(HTTPStatus.TOO_MANY_REQUESTS, "too_often")
        ticket = hub.mint_ticket(device_id, kind, person)
        if ticket is None:
            return _error(HTTPStatus.TOO_MANY_REQUESTS, "try_later")
        return web.json_response({"ticket": ticket, "expires_in": int(TICKET_EXPIRES.total_seconds())})


class RedeemView(HomeAssistantView):
    """POST /api/hearth/pair/redeem {ticket, device_id, kind, name, model, version} -> the approved answer of a
    pairing (as GET /api/hearth/pair/<id> gives it), at once. 404 "unknown" for a ticket that's unknown, used, expired
    or for another kind; it's spent either way."""

    url = "/api/hearth/pair/redeem"
    name = "api:hearth:pair:redeem"
    requires_auth = False

    async def post(self, request: web.Request) -> web.Response:
        hass: HomeAssistant = request.app["hass"]
        if not _local(request):
            return _error(HTTPStatus.FORBIDDEN, "not_local")
        hub = _hub(hass)
        if hub is None:
            return _error(HTTPStatus.SERVICE_UNAVAILABLE, "not_set_up")
        body = await _json_body(request)
        if not isinstance(body, dict):
            return _error(HTTPStatus.BAD_REQUEST, "bad_request")
        ticket, device_id = body.get("ticket"), body.get("device_id")
        kind = body.get("kind", KIND_TV)
        client_ok, client = _pair_client(body)
        if (
            not isinstance(ticket, str)
            or not 16 <= len(ticket) <= 128
            or not isinstance(device_id, str)
            or not _ID.match(device_id)
            or kind not in TICKET_KINDS
            or not client_ok
        ):
            return _error(HTTPStatus.BAD_REQUEST, "bad_request")
        name = text(body.get("name"), 64) or _DEFAULT_NAMES[kind]
        pairing = await hub.async_redeem(
            ticket, device_id, kind, name, text(body.get("model"), 64), text(body.get("version"), 32), client
        )
        if pairing is None:
            return _error(HTTPStatus.NOT_FOUND, "unknown")
        secret = collect_secret(hass, pairing)
        if secret is None:
            return _error(HTTPStatus.NOT_FOUND, "unknown")
        return web.json_response(_approved(hass, pairing, secret))


def _server(options) -> str | None:
    try:
        return clean_server(options.get(CONF_PUSH_SERVER))
    except vol.Invalid:
        return None


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
        state = hub.household.document_for(device_id)
        answer: dict[str, Any] = {"ok": True, "contract": CONTRACT, "state": state}
        # Hearth's own day: a status for another day (the device's clock moved) doesn't count, and says so
        answer["day"] = dt_util.now().date().isoformat()
        if (hub.state(device_id).status or {}).get("clock_off"):
            answer["clock_off"] = True
        # The TV's own rules each profile had: which are taken (or passed over) for good, so it stops sending them
        if status.get("local_rules"):
            imported = hub.household.limits.data.imported
            answer["local_rules_taken"] = [p for p in status["local_rules"] if f"{device_id}:{p}" in imported]
        if hub.has_cap(device_id, CAP_PUSH):
            # The phone has this version now: it isn't pinged for it; and where to listen for the next (or null)
            hub.push.delivered(device_id, state["version"])
            answer["push"] = hub.push.answer_for(device_id)
        return web.json_response(answer)


class EventsView(HomeAssistantView):
    """POST /api/hearth/device/{device_id}/events (header X-Hearth-Secret): {"events": [...]}, at most 50, each
    {"type": "video_started", "profile_id", "t" (ms), "v" (video id), "title", "ch" (channel), "cid" (channel id),
    optional "pa" (true: a parent's PIN let it play past the limit or a lock)}: what a kids profile started in HearthTube. A TV only. Answers {"ok": true, "added": n} once all are taken (a
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
        # HearthTube's started videos: a TV's, unless a device says otherwise in its caps
        if not hub.has_cap(device_id, CAP_EVENTS):
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
            person = household.profile_person(device_id, entry["profile_id"]) if entry else None
            if entry and person and household.watch.add_started(person, entry, device_id):
                added += 1
        if added:
            household.watch.changed()
        return web.json_response({"ok": True, "added": added})


class VerifyPinView(HomeAssistantView):
    """POST /api/hearth/device/{device_id}/verify_pin (header X-Hearth-Secret): {"pin": "1234"} -> {"ok": true, "person":
    "person.alex", "grant", "grant_expires": seconds, "grant_writes": n} or {"ok": false}.

    The grant (contract 3, pin_grants.py) lets this device, and only it, make a few client-settings writes it couldn't
    make alone, for a short while. Checks the adults' parent PINs (Configure > Parent PINs), any of them; the answer says whose it was, and
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
        lock = pin_lockout(hass, device_id)
        now = dt_util.utcnow()
        if wait := parent_pin.retry_in(lock.locked_until, now):
            return web.json_response({"error": "locked_out", "retry_in": wait}, status=HTTPStatus.TOO_MANY_REQUESTS)
        body = await _json_body(request)
        pin = body.get("pin") if isinstance(body, dict) else None
        if not isinstance(pin, str):
            return _error(HTTPStatus.BAD_REQUEST, "bad_request")
        person, wait_for = await _check_pin(hass, device_id, stored, pin)
        if person:
            return web.json_response(
                {
                    "ok": True,
                    "person": person,
                    "grant": hub.pin_grants.mint(device_id, person),
                    "grant_expires": GRANT_SECONDS,
                    "grant_writes": GRANT_WRITES,
                }
            )
        answer: dict[str, Any] = {"ok": False}
        if wait_for:
            answer["retry_in"] = wait_for
        return web.json_response(answer)


async def _check_pin(hass: HomeAssistant, device_id: str, stored: dict[str, str], pin: str) -> tuple[str | None, int]:
    """A parent PIN from a device that isn't locked out, counted in its lockout (shared by every endpoint that takes
    one): (whose it is, 0), or (None, the seconds of the lockout this wrong one started, 0 for none)."""
    lock = pin_lockout(hass, device_id)
    now = dt_util.utcnow()
    # Locked out meanwhile, or the free tries already taken by guesses still being checked (sent all at once): refused
    # unchecked, in the same step as the count, so parallel guesses never get past the free tries
    if wait := parent_pin.retry_in(lock.locked_until, now):
        return None, wait
    if lock.checking and parent_pin.lockout(lock.failures):
        # Past the free tries one guess is checked at a time: the others wait for its answer
        return None, 1
    # Counted before the slow check, so parallel guesses can't all slip in under the free tries
    lock.failures += 1
    lock.checking += 1
    try:
        person = await hass.async_add_executor_job(parent_pin.whose, stored, pin)
    finally:
        lock.checking -= 1
    save_pin_lockouts(hass)
    if person:
        lock.failures = 0
        lock.locked_until = None
        hass.bus.async_fire(parent_pin.EVENT_PARENT_PIN_USED, {"device_id": device_id, "person": person})
        return person, 0
    if wait_for := parent_pin.lockout(lock.failures):
        lock.locked_until = dt_util.utcnow() + wait_for
        retry = parent_pin.retry_in(lock.locked_until, dt_util.utcnow())
        hass.bus.async_fire(
            parent_pin.EVENT_PARENT_PIN_LOCKED_OUT,
            {"device_id": device_id, "failures": lock.failures, "retry_in": retry},
        )
        return None, retry
    return None, 0


class NoticeView(HomeAssistantView):
    """POST /api/hearth/device/{device_id}/notice (header X-Hearth-Secret, a TV that shows notices): {"key": a
    notice's key, "action": its button's number, and "pin": "<digits>" or "approval": "phone"} (notices.py).

    With a Parent PIN (checked as verify_pin checks one, in the same lockout), the button's service runs as that adult:
    {"ok": true, "done": true}. With "approval": "phone", the adults' phones are asked, and an adult's tap there runs it:
    {"ok": true, "pending": "phone"}. 404 gone (no such notice for this TV now), 403 wrong_pin (with "retry_after" once
    locked out), 400 bad_request, 429 too_many. A secret alone never runs a service."""

    url = "/api/hearth/device/{device_id}/notice"
    name = "api:hearth:device:notice"
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
        if hub.too_many_notice_presses(device_id):
            return _error(HTTPStatus.TOO_MANY_REQUESTS, "too_many")
        body = await _json_body(request)
        if not isinstance(body, dict):
            return _error(HTTPStatus.BAD_REQUEST, "bad_request")
        key, n, pin, approval = body.get("key"), body.get("action"), body.get("pin"), body.get("approval")
        if (
            not isinstance(key, str)
            or not 0 < len(key) <= 256
            or not isinstance(n, int)
            or isinstance(n, bool)
            or n < 0
            or (pin is None) == (approval is None)
            or (pin is not None and (not isinstance(pin, str) or not pin.isdigit() or len(pin) > 16))
            or (approval is not None and approval != notices.VIA_PHONE)
        ):
            return _error(HTTPStatus.BAD_REQUEST, "bad_request")
        item = notices.shown(hub, device_id).get(key)
        if item is None:
            return _error(HTTPStatus.NOT_FOUND, "gone")
        # Only a button the TV was shown: a hearth service
        if n >= len(item.actions) or not hub.attention.runs(item.actions[n]):
            return _error(HTTPStatus.BAD_REQUEST, "bad_request")
        if approval is not None:
            notices.ask_phone(hub, device_id, item, n)
            return web.json_response({"ok": True, "pending": notices.VIA_PHONE})

        lock = pin_lockout(hass, device_id)
        if wait := parent_pin.retry_in(lock.locked_until, dt_util.utcnow()):
            return web.json_response({"error": "wrong_pin", "retry_after": wait}, status=HTTPStatus.FORBIDDEN)
        stored = parent_pin.stored_pins(hub.entry.options)
        if not stored:
            # No Parent PIN in Home Assistant: none can be right (the TV can still ask a parent's phone)
            return _error(HTTPStatus.FORBIDDEN, "wrong_pin")
        person, wait_for = await _check_pin(hass, device_id, stored, pin)
        if not person:
            answer: dict[str, Any] = {"error": "wrong_pin"}
            if wait_for:
                answer["retry_after"] = wait_for
            return web.json_response(answer, status=HTTPStatus.FORBIDDEN)
        # The notice may have gone while the PIN was checked
        if notices.shown(hub, device_id).get(key) is None:
            return _error(HTTPStatus.NOT_FOUND, "gone")
        user_id = await notices.adult_user(hass, hub, person)
        if not await hub.attention.run(item.actions[n], user_id):
            return _error(HTTPStatus.INTERNAL_SERVER_ERROR, "failed")
        notices.log_answer(
            hub,
            {"person": item.about.get("person"), "notice": item.key, "action": n, "device": device_id},
            notices.VIA_PIN,
            person=person,
            user_id=user_id,
        )
        return web.json_response({"ok": True, "done": True})


class AskView(HomeAssistantView):
    """POST /api/hearth/device/{device_id}/ask (header X-Hearth-Secret): {"minutes": 15|30|45|60, "group": "all" or a
    group id, "note": short text, "profile_id": a TV's profile (a phone asks for its own person)} -> {"ok": true,
    "request": {id, status, minutes, asked_minutes, group, expires}}. 409 already_open (with that request), 429 cooldown
    (with retry_in) after a "not now", 400 closed for a category that's off today, 400 for anything else wrong, 404
    no_person when the profile is nobody's. The answer comes in the person's state document ("request") with the next
    status answers."""

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
            person = hub.household.profile_person(device_id, profile_id) if profile_id else None
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


class SwitchApprovalView(HomeAssistantView):
    """POST /api/hearth/device/{device_id}/switch_approval (header X-Hearth-Secret, a TV): {"profile_id": the TV's
    profile, "phone": the notify service chosen for it, optional} -> {"ok": true, "request": {id, status}, "phones": n,
    "expires": seconds}. The integration asks the profile's adult on their phones (switch_approval.py). 404 no_person,
    403 not_adult, 404 no_phone, 502 not_sent, 429 too_often, 400 bad_request."""

    url = "/api/hearth/device/{device_id}/switch_approval"
    name = "api:hearth:device:switch_approval"
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
            return _error(HTTPStatus.BAD_REQUEST, "bad_request")
        if hub.too_many_events(device_id):
            return _error(HTTPStatus.TOO_MANY_REQUESTS, "too_often")
        body = await _json_body(request)
        if not isinstance(body, dict):
            return _error(HTTPStatus.BAD_REQUEST, "bad_request")
        profile_id = text(body.get("profile_id"), 64)
        phone = body.get("phone")
        if not profile_id or (phone is not None and not switch_approval.valid_service(phone)):
            return _error(HTTPStatus.BAD_REQUEST, "bad_request")
        try:
            asked = await hub.switch_approvals.ask(device_id, profile_id, phone)
        except switch_approval.SwitchApprovalError as err:
            status = {
                "no_person": HTTPStatus.NOT_FOUND,
                "no_phone": HTTPStatus.NOT_FOUND,
                "not_adult": HTTPStatus.FORBIDDEN,
            }.get(err.code, HTTPStatus.BAD_GATEWAY)
            return _error(status, err.code)
        return web.json_response(
            {
                "ok": True,
                "request": asked.view(),
                "phones": len(asked.services),
                "expires": switch_approval.ANSWER_SECONDS,
            }
        )


class SwitchApprovalRequestView(HomeAssistantView):
    """GET /api/hearth/device/{device_id}/switch_approval/{request_id}?timeout=<s> (header X-Hearth-Secret): {"ok":
    true, "request": {id, status}} as soon as its status isn't "pending", or after <s> seconds (at most 55): pending,
    allowed, denied, expired or withdrawn. DELETE withdraws it. 404 gone (no such request of this TV's)."""

    url = "/api/hearth/device/{device_id}/switch_approval/{request_id}"
    name = "api:hearth:device:switch_approval:request"
    requires_auth = False

    async def _find(self, request: web.Request, device_id: str, request_id: str):
        hass: HomeAssistant = request.app["hass"]
        if not _local(request):
            return None, _error(HTTPStatus.FORBIDDEN, "not_local")
        hub = _hub(hass)
        if hub is None:
            return None, _error(HTTPStatus.SERVICE_UNAVAILABLE, "not_set_up")
        if not hub.authorized(device_id, request.headers.get(HEADER_SECRET)):
            return None, _error(HTTPStatus.UNAUTHORIZED, "not_paired")
        found = hub.switch_approvals.get(device_id, request_id) if switch_approval.valid_id(request_id) else None
        if found is None:
            return None, _error(HTTPStatus.NOT_FOUND, "gone")
        return (hub, found), None

    async def get(self, request: web.Request, device_id: str, request_id: str) -> web.Response:
        found, error = await self._find(request, device_id, request_id)
        if error is not None:
            return error
        hub, asked = found
        try:
            timeout = float(request.query.get("timeout", 0))
        except ValueError:
            return _error(HTTPStatus.BAD_REQUEST, "bad_request")
        if not math.isfinite(timeout):
            return _error(HTTPStatus.BAD_REQUEST, "bad_request")
        timeout = min(max(timeout, 0.0), float(switch_approval.WAIT_MAX))
        await hub.switch_approvals.wait(asked, timeout)
        return web.json_response({"ok": True, "request": asked.view()})

    async def delete(self, request: web.Request, device_id: str, request_id: str) -> web.Response:
        found, error = await self._find(request, device_id, request_id)
        if error is not None:
            return error
        hub, asked = found
        await hub.switch_approvals.withdraw(asked)
        return web.json_response({"ok": True, "request": asked.view()})


class WaitView(HomeAssistantView):
    """GET /api/hearth/device/{device_id}/wait?version=<v>&timeout=<s> (header X-Hearth-Secret): {"changed": bool}
    once the device's state document isn't <v>, or after <s> seconds (wait.py)."""

    url = "/api/hearth/device/{device_id}/wait"
    name = "api:hearth:device:wait"
    requires_auth = False

    async def get(self, request: web.Request, device_id: str) -> web.Response:
        hass: HomeAssistant = request.app["hass"]
        if not _local(request):
            return _error(HTTPStatus.FORBIDDEN, "not_local")
        hub = _hub(hass)
        if hub is None:
            return _error(HTTPStatus.SERVICE_UNAVAILABLE, "not_set_up")
        if not hub.authorized(device_id, request.headers.get(HEADER_SECRET)):
            return _error(HTTPStatus.UNAUTHORIZED, "not_paired")
        version = request.query.get("version")
        if version is not None and (not version or len(version) > 32):
            return _error(HTTPStatus.BAD_REQUEST, "bad_request")
        try:
            asked = float(request.query.get("timeout", WAIT_MAX))
        except ValueError:
            return _error(HTTPStatus.BAD_REQUEST, "bad_request")
        # nan (or inf) would pass the clamp below and put a timer with no deadline on the loop
        if not math.isfinite(asked):
            return _error(HTTPStatus.BAD_REQUEST, "bad_request")
        timeout = min(max(asked, 1.0), float(WAIT_MAX))
        return web.json_response({"changed": await hub.waits.wait(device_id, version, timeout)})


HEADER_GRANT = "X-Hearth-Grant"
# A settings body: the document's data (at most MAX_DATA_BYTES as stored) with its envelope, room for escaping
MAX_SETTINGS_BODY = 2 * MAX_DATA_BYTES
_SETTINGS_ERRORS = {
    "changed": HTTPStatus.CONFLICT,
    "too_large": HTTPStatus.REQUEST_ENTITY_TOO_LARGE,
    "too_many": HTTPStatus.REQUEST_ENTITY_TOO_LARGE,
    "forbidden": HTTPStatus.FORBIDDEN,
    "bad_request": HTTPStatus.BAD_REQUEST,
}


class SettingsView(HomeAssistantView):
    """/api/hearth/device/{device_id}/settings/{scope}/{name} (header X-Hearth-Secret): the device's client settings
    (client_settings.py), for the client locked at its pairing.

    GET -> the document, or 404 none. PUT {"schema", "data", "label"?, "if_etag"?, "grant"?} -> {"etag", "updated_by"}; DELETE {"if_etag"?,
    "grant"?} -> {"ok": true}. 403 forbidden (this device may not, or its grant isn't live), 403 no_client (paired
    before contract 3, or without a client: pair again), 409 changed {"etag": current}, 413 too_large or too_many, 400
    bad_request. A grant may come as X-Hearth-Grant instead."""

    url = "/api/hearth/device/{device_id}/settings/{scope}/{name}"
    name = "api:hearth:device:settings"
    requires_auth = False

    async def _start(self, request: web.Request, device_id: str, scope: str, name: str):
        """(hub, client, scope) or an error response."""
        hass: HomeAssistant = request.app["hass"]
        if not _local(request):
            return _error(HTTPStatus.FORBIDDEN, "not_local")
        hub = _hub(hass)
        if hub is None:
            return _error(HTTPStatus.SERVICE_UNAVAILABLE, "not_set_up")
        if not hub.authorized(device_id, request.headers.get(HEADER_SECRET)):
            return _error(HTTPStatus.UNAUTHORIZED, "not_paired")
        if hub.too_many_settings_calls(device_id):
            return _error(HTTPStatus.TOO_MANY_REQUESTS, "too_often")
        parsed = parse_scope(scope)
        if parsed is None or not valid_name(name):
            return _error(HTTPStatus.BAD_REQUEST, "bad_request")
        client = hub.client_settings.device_client(device_id)
        if client is None:
            return _error(HTTPStatus.FORBIDDEN, "no_client")
        return hub, client, parsed

    async def get(self, request: web.Request, device_id: str, scope: str, name: str) -> web.Response:
        started = await self._start(request, device_id, scope, name)
        if isinstance(started, web.Response):
            return started
        hub, client, parsed = started
        writer, person, people = hub.client_settings.device_writer(device_id)
        if not may_read(writer, parsed, person=person, device=device_id, people=people):
            return _error(HTTPStatus.FORBIDDEN, "forbidden")
        doc = hub.client_settings.get(client, parsed, name)
        if doc is None:
            return _error(HTTPStatus.NOT_FOUND, "none")
        return web.json_response(doc)

    async def put(self, request: web.Request, device_id: str, scope: str, name: str) -> web.Response:
        started = await self._start(request, device_id, scope, name)
        if isinstance(started, web.Response):
            return started
        hub, client, parsed = started
        if request.content_length is not None and request.content_length > MAX_SETTINGS_BODY:
            return _error(HTTPStatus.REQUEST_ENTITY_TOO_LARGE, "too_large")
        body = await _json_body(request, MAX_SETTINGS_BODY)
        if not isinstance(body, dict) or not isinstance(body.get("data"), dict) or not isinstance(body.get("schema"), str):
            return _error(HTTPStatus.BAD_REQUEST, "bad_request")
        if hearth_only(client, parsed, name):
            # A Glint phone's agent inbox is Hearth's alone (glint_agent.py)
            return _error(HTTPStatus.FORBIDDEN, "forbidden")
        if_etag = body["if_etag"] if "if_etag" in body else ...
        grant = body.get("grant") or request.headers.get(HEADER_GRANT)
        try:
            doc = device_write(
                hub.client_settings,
                hub.pin_grants,
                device_id,
                parsed,
                grant,
                lambda by: hub.client_settings.put(
                    client, parsed, name, body["schema"], body["data"], by, if_etag, body.get("label")
                ),
            )
        except SettingsError as err:
            return _settings_error(err)
        return web.json_response({"etag": doc["etag"], "updated_by": doc["updated_by"]})

    async def delete(self, request: web.Request, device_id: str, scope: str, name: str) -> web.Response:
        started = await self._start(request, device_id, scope, name)
        if isinstance(started, web.Response):
            return started
        hub, client, parsed = started
        body = await _json_body(request) if request.can_read_body else None
        body = body if isinstance(body, dict) else {}
        if hearth_only(client, parsed, name):
            return _error(HTTPStatus.FORBIDDEN, "forbidden")
        if_etag = body["if_etag"] if "if_etag" in body else ...
        grant = body.get("grant") or request.headers.get(HEADER_GRANT)
        try:
            gone = device_write(
                hub.client_settings,
                hub.pin_grants,
                device_id,
                parsed,
                grant,
                lambda _by: hub.client_settings.delete(client, parsed, name, if_etag),
            )
        except SettingsError as err:
            return _settings_error(err)
        if not gone:
            return _error(HTTPStatus.NOT_FOUND, "none")
        return web.json_response({"ok": True})


def _settings_error(err: SettingsError) -> web.Response:
    body: dict[str, Any] = {"error": err.code}
    if err.code == "changed":
        body["etag"] = err.etag
    return web.json_response(body, status=_SETTINGS_ERRORS.get(err.code, HTTPStatus.BAD_REQUEST))


class EndGrantView(HomeAssistantView):
    """POST /api/hearth/device/{device_id}/end_grant (header X-Hearth-Secret, an adult's phone): {"origin_id": an
    origin's id from a person's time.origins (the household summary)} -> {"ok": true, "ended": {service, data}}. Runs
    the origin's end (taking back its unused minutes, ending a raised limit, Unlimited or Pause screens) as that adult's
    Home Assistant user, through the same guard as every Hearth service, so it's in the action log. 403 not_adult (the
    phone isn't an adult's), 404 not_found (no such origin, or nothing of it left to end), 400 bad_request."""

    url = "/api/hearth/device/{device_id}/end_grant"
    name = "api:hearth:device:end_grant"
    requires_auth = False

    async def post(self, request: web.Request, device_id: str) -> web.Response:
        from homeassistant.core import Context

        from .activity import call_service
        from .const import CONF_ROLES

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
        adult = hub.household.device_person(device_id)
        if not adult or hub.entry.options.get(CONF_ROLES, {}).get(adult) != "adult":
            return _error(HTTPStatus.FORBIDDEN, "not_adult")
        body = await _json_body(request)
        origin_id = text(body.get("origin_id"), 64) if isinstance(body, dict) else None
        if not origin_id:
            return _error(HTTPStatus.BAD_REQUEST, "bad_request")
        household = hub.household
        person = household.person_of_origin(origin_id)
        found = next((o for o in household.origins_of(person) if o["id"] == origin_id), None) if person else None
        if found is None or not found["endable"]:
            return _error(HTTPStatus.NOT_FOUND, "not_found")
        user_id = await notices.adult_user(hass, hub, adult)
        try:
            ended = await call_service(
                hass, DOMAIN, "end_grant", {"origin_id": origin_id}, blocking=True, context=Context(user_id=user_id),
                return_response=True, why=f"end_grant:{origin_id}",
            )
        except Exception as err:  # noqa: BLE001 - said to the phone
            return web.json_response({"error": "failed", "detail": str(err)[:200]}, status=HTTPStatus.BAD_REQUEST)
        return web.json_response({"ok": True, "ended": ended})


def async_register_views(hass: HomeAssistant) -> None:
    for view in (
        PairStartView,
        PairStatusView,
        RedeemView,
        StatusView,
        EventsView,
        VerifyPinView,
        NoticeView,
        AskView,
        SwitchApprovalView,
        SwitchApprovalRequestView,
        WaitView,
        TicketView,
        SettingsView,
        EndGrantView,
    ):
        hass.http.register_view(view())
