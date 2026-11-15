"""Glint agents through Hearth HA: the mailbox Hearth keeps for each Glint phone (Glint's docs/contracts/glint-agent-ha.md,
contract 1). The `glint` LLM API (glint_api.py) is its only writer of requests.

Three client-settings documents (client_settings.py) in the phone's own device scope, for the Glint client it locked
at pairing (`com.thesiegs.glint`, or a `.debug` / `.nightly` build):

| Name           | `schema`              | Written by                  | Read by    |
|----------------|-----------------------|-----------------------------|------------|
| `agent-inbox`  | `glint.agent-inbox/1` | Hearth only (`hearth`)      | Glint      |
| `agent-outbox` | `glint.agent-outbox/1`| Glint only (its own device) | Hearth     |
| `glint-state`  | `glint.state/1`       | Glint only (its own device) | Hearth     |

One writer each, so no etag races: neither the phone (device API) nor an adult (WebSocket) may write or delete the
inbox; over the WebSocket the outbox and the state are written only by the user whose person the phone is paired to,
and the three are read only by that user or, for a kid's phone, by an adult (client_settings_ws.py).

A request (§2): {id, agent, user, user_name, origin, action, args, created, expires}. At most MAX_REQUESTS waiting and
MAX_INBOX_BYTES; a request goes once the outbox holds a final result for it (applied, refused, expired), or once it's
past its expiry (at most MAX_AGE after it was made). Pruned when a request is added and when the outbox changes: no
timer. When a result turns final Hearth fires `glint_agent_done` {device_id, request, agent, status, said, undo} (and
action, code) once, and the tool call waiting on it (`wait`) gets it; `asked_on_phone` also answers a waiting call.

The Companion doorbell (§7.4): an adult may link a Home Assistant companion app (a `notify.mobile_app_*` service) to
a Glint phone (`hearth/glint/bell`); a write then also sends it `command_broadcast_intent` naming Glint's receiver.
It carries nothing: Glint only reads its inbox sooner.
"""

from __future__ import annotations

import asyncio
from datetime import datetime, timedelta
import logging
import secrets
from typing import TYPE_CHECKING, Any

from homeassistant.core import HomeAssistant, callback
from homeassistant.helpers.dispatcher import async_dispatcher_connect
from homeassistant.helpers.storage import Store
from homeassistant.util import dt as dt_util

from .client_settings import (
    DEVICE,
    KID_DEVICE,
    SIGNAL_CLIENT_SETTINGS,
    TV_DEVICE,
    SettingsError,
    data_size,
    parse_scope,
)
from .const import CONF_KIND, CONF_PERSON, KIND_TV

if TYPE_CHECKING:
    from .hub import HearthHub

_LOGGER = logging.getLogger(__name__)

CONTRACT = 1
# The Glint builds: each pairs with its own id, and its documents are kept under it
GLINT_CLIENT = "com.thesiegs.glint"
GLINT_CLIENTS = frozenset({GLINT_CLIENT, f"{GLINT_CLIENT}.debug", f"{GLINT_CLIENT}.nightly"})

INBOX = "agent-inbox"
OUTBOX = "agent-outbox"
STATE = "glint-state"
AGENT_DOCS = (INBOX, OUTBOX, STATE)
INBOX_FORMAT = "glint.agent-inbox/1"
OUTBOX_FORMAT = "glint.agent-outbox/1"
STATE_FORMAT = "glint.state/1"
INBOX_LABEL = "agent requests"
# updated_by of the inbox: Hearth itself wrote it
BY_HEARTH = "hearth"

MAX_REQUESTS = 20
MAX_INBOX_BYTES = 32 * 1024
MAX_ARGS_BYTES = 8 * 1024
MAX_AGE = timedelta(hours=24)
# How long a write's tool call waits for the phone's result before it answers "queued"
WAIT_FOR = 20.0

ORIGIN_TEXT = "text"
ORIGIN_VOICE = "voice"

APPLIED = "applied"
REFUSED = "refused"
ASKED = "asked_on_phone"
EXPIRED = "expired"
FINAL = (APPLIED, REFUSED, EXPIRED)

EVENT_AGENT_DONE = "glint_agent_done"

# The doorbell: the companion app's notification command, to Glint's exported receiver
BELL_MESSAGE = "command_broadcast_intent"
BELL_ACTION = "com.thesiegs.glint.action.AGENT_BELL"
BELL_CLASS = "com.thesiegs.glint.start.agent.AgentBellReceiver"
BELL_PREFIX = "notify.mobile_app_"


def is_glint(client: str | None) -> bool:
    return client in GLINT_CLIENTS


def is_agent_doc(client: str | None, scope: tuple[str, str | None], name: str) -> bool:
    """One of the three agent documents of a Glint phone."""
    return is_glint(client) and scope[0] == DEVICE and name in AGENT_DOCS


def hearth_only(client: str | None, scope: tuple[str, str | None], name: str) -> bool:
    """A document only Hearth writes (and nobody deletes): a Glint phone's inbox."""
    return is_glint(client) and scope[0] == DEVICE and name == INBOX


def iso(when: datetime) -> str:
    return when.astimezone(dt_util.UTC).replace(microsecond=0).isoformat().replace("+00:00", "Z")


def parse_time(value: Any) -> datetime | None:
    if not isinstance(value, str):
        return None
    parsed = dt_util.parse_datetime(value)
    if parsed is None:
        return None
    return parsed if parsed.tzinfo else parsed.replace(tzinfo=dt_util.UTC)


def until_of(request: dict[str, Any]) -> datetime | None:
    """When a request stops being run: its expires, never more than MAX_AGE after it was made (None: unreadable)."""
    created = parse_time(request.get("created"))
    if created is None:
        return None
    expires = parse_time(request.get("expires")) or created + MAX_AGE
    return min(expires, created + MAX_AGE)


def results_of(outbox: dict[str, Any] | None) -> dict[str, dict[str, Any]]:
    """The outbox's results by request id (the last one for an id wins)."""
    data = (outbox or {}).get("data") or {}
    results = data.get("results") if isinstance(data, dict) else None
    out: dict[str, dict[str, Any]] = {}
    for result in results if isinstance(results, list) else []:
        if isinstance(result, dict) and isinstance(result.get("id"), str):
            out[result["id"]] = result
    return out


def requests_of(inbox: dict[str, Any] | None) -> list[dict[str, Any]]:
    data = (inbox or {}).get("data") or {}
    requests = data.get("requests") if isinstance(data, dict) else None
    return [r for r in requests if isinstance(r, dict)] if isinstance(requests, list) else []


def inbox_data(requests: list[dict[str, Any]]) -> dict[str, Any]:
    return {"format": INBOX_FORMAT, "contract": CONTRACT, "requests": requests}


class InboxFull(Exception):
    """The phone has MAX_REQUESTS waiting (or no room left in its inbox)."""

    def __init__(self, waiting: int) -> None:
        super().__init__("inbox_full")
        self.waiting = waiting


class GlintAgent:
    """The mailboxes of the household's Glint phones, the tool calls waiting on them, and the doorbells."""

    def __init__(self, hass: HomeAssistant, hub: HearthHub) -> None:
        self.hass = hass
        self.hub = hub
        self._store: Store[dict[str, Any]] = Store(hass, 1, f"hearth.glint_agent.{hub.entry.entry_id}")
        # device id -> the companion app's notify service ("notify.mobile_app_<name>") that rings its doorbell
        self.bells: dict[str, str] = {}
        # (device id, request id) -> the waiting tool call's future
        self._waiting: dict[tuple[str, str], asyncio.Future[dict[str, Any]]] = {}
        self._unsub = None

    async def async_load(self) -> None:
        stored = await self._store.async_load() or {}
        bells = stored.get("bells")
        self.bells = {
            d: s for d, s in (bells.items() if isinstance(bells, dict) else []) if isinstance(s, str) and d in self.hub.devices
        }

    def _save(self) -> None:
        self._store.async_delay_save(lambda: {"bells": dict(self.bells)}, 5)

    async def async_flush(self) -> None:
        await self._store.async_save({"bells": dict(self.bells)})

    @callback
    def start(self) -> None:
        self._unsub = async_dispatcher_connect(self.hass, SIGNAL_CLIENT_SETTINGS, self._changed)

    @callback
    def stop(self) -> None:
        if self._unsub is not None:
            self._unsub()
            self._unsub = None
        for future in self._waiting.values():
            if not future.done():
                future.cancel()
        self._waiting.clear()

    # The phones

    def client_of(self, device_id: str) -> str | None:
        return self.hub.client_settings.device_client(device_id)

    def phones(self) -> list[str]:
        """The paired devices running Glint (by the client each locked at pairing), TVs aside."""
        return [
            d
            for d, device in self.hub.devices.items()
            if device.get(CONF_KIND) != KIND_TV and is_glint(self.client_of(d))
        ]

    def is_kid_phone(self, device_id: str) -> bool:
        """A phone whose person isn't an adult on Hearth's page (as client settings count it): unknown is a kid's."""
        writer = self.hub.client_settings.device_writer(device_id)[0]
        return writer in (KID_DEVICE, TV_DEVICE)

    def person_of(self, device_id: str) -> str | None:
        return (self.hub.devices.get(device_id) or {}).get(CONF_PERSON)

    def name_of(self, device_id: str) -> str:
        return (self.hub.devices.get(device_id) or {}).get("name") or device_id

    def reachable(self, person: str | None, *, voice: bool = False) -> list[str]:
        """The Glint phones a caller may address: an adult (by [person], None for one with no person) their own and
        kids'; a voice call with no user only adults' phones (it never reaches a kid's)."""
        found = []
        for device_id in self.phones():
            kid = self.is_kid_phone(device_id)
            if voice:
                if not kid:
                    found.append(device_id)
            elif kid or (person is not None and self.person_of(device_id) == person):
                found.append(device_id)
        return found

    def inbox_etags(self, person: str) -> dict[str, str]:
        """{"device:<id>/agent-inbox": etag} of the Glint phones paired to [person] (hearth/me, ask G-2)."""
        out: dict[str, str] = {}
        for device_id in sorted(self.phones()):
            if self.person_of(device_id) != person:
                continue
            doc = self.doc(device_id, INBOX)
            if doc is not None:
                out[f"device:{device_id}/{INBOX}"] = doc["etag"]
        return out

    # The documents

    def doc(self, device_id: str, name: str) -> dict[str, Any] | None:
        client = self.client_of(device_id)
        if not is_glint(client):
            return None
        return self.hub.client_settings.get(client, (DEVICE, device_id), name)

    def state(self, device_id: str) -> dict[str, Any] | None:
        """The phone's glint-state data, when it published one."""
        doc = self.doc(device_id, STATE)
        data = (doc or {}).get("data")
        return data if isinstance(data, dict) else None

    def results(self, device_id: str) -> dict[str, dict[str, Any]]:
        return results_of(self.doc(device_id, OUTBOX))

    def pending(self, device_id: str) -> list[dict[str, Any]]:
        """The requests waiting in the phone's inbox (as kept; pruned on the next change)."""
        return requests_of(self.doc(device_id, INBOX))

    def _write_inbox(self, device_id: str, requests: list[dict[str, Any]]) -> None:
        client = self.client_of(device_id)
        self.hub.client_settings.put(
            client, (DEVICE, device_id), INBOX, INBOX_FORMAT, inbox_data(requests), BY_HEARTH, ..., INBOX_LABEL
        )

    def _kept(self, device_id: str, now: datetime) -> tuple[list[dict[str, Any]], bool]:
        """The inbox's requests that still wait (no final result, not past their time), and whether any went."""
        requests = self.pending(device_id)
        results = self.results(device_id)
        kept = []
        for request in requests:
            until = until_of(request)
            final = (results.get(str(request.get("id"))) or {}).get("status") in FINAL
            if final or until is None or now >= until:
                continue
            kept.append(request)
        return kept, len(kept) != len(requests)

    # Adding a request

    def new_id(self, device_id: str) -> str:
        """A request id never used on this phone: not in its inbox or its outbox."""
        used = {str(r.get("id")) for r in self.pending(device_id)} | set(self.results(device_id))
        while True:
            request_id = f"r-{secrets.token_urlsafe(8)}"
            if request_id not in used:
                return request_id

    def add(
        self,
        device_id: str,
        action: str,
        args: dict[str, Any],
        *,
        agent: str,
        origin: str,
        user: str | None,
        user_name: str | None,
        expires: datetime | None = None,
    ) -> dict[str, Any]:
        """Adds a request to the phone's inbox (pruned first); the request. InboxFull at MAX_REQUESTS or when it
        doesn't fit; SettingsError when the documents are over a limit; ValueError for args over MAX_ARGS_BYTES."""
        if data_size(args) > MAX_ARGS_BYTES:
            raise ValueError("args")
        now = dt_util.utcnow().replace(microsecond=0)
        kept, _gone = self._kept(device_id, now)
        if len(kept) >= MAX_REQUESTS:
            raise InboxFull(len(kept))
        until = now + MAX_AGE if expires is None else max(now, min(expires, now + MAX_AGE))
        request = {
            "id": self.new_id(device_id),
            "agent": agent,
            "user": user,
            "user_name": user_name,
            "origin": ORIGIN_VOICE if origin == ORIGIN_VOICE else ORIGIN_TEXT,
            "action": action,
            "args": args,
            "created": iso(now),
            "expires": iso(until),
        }
        requests = [*kept, request]
        if data_size(inbox_data(requests)) > MAX_INBOX_BYTES:
            raise InboxFull(len(kept))
        self._write_inbox(device_id, requests)
        return request

    def watch(self, device_id: str, request_id: str) -> asyncio.Future[dict[str, Any]]:
        """A future that gets the request's result once it's final or asked on the phone."""
        future: asyncio.Future[dict[str, Any]] = self.hass.loop.create_future()
        self._waiting[(device_id, request_id)] = future
        return future

    async def wait(self, device_id: str, futures: dict[str, asyncio.Future[dict[str, Any]]]) -> dict[str, dict[str, Any] | None]:
        """Waits up to WAIT_FOR for every future; {request id: its result, or None when it didn't come in time}."""
        try:
            if futures and WAIT_FOR > 0:
                await asyncio.wait(list(futures.values()), timeout=WAIT_FOR)
        finally:
            for request_id in futures:
                self._waiting.pop((device_id, request_id), None)
        return {
            rid: (f.result() if f.done() and not f.cancelled() and f.exception() is None else None)
            for rid, f in futures.items()
        }

    # The phone wrote its outbox

    @callback
    def _changed(self, client: str, scope: str, name: str, etag: str | None) -> None:
        if not is_glint(client) or name != OUTBOX or etag is None:
            return
        parsed = parse_scope(scope)
        if parsed is None or parsed[0] != DEVICE or self.client_of(parsed[1]) != client:
            return
        self.outbox_changed(parsed[1])

    @callback
    def outbox_changed(self, device_id: str) -> None:
        """The outbox changed: each waiting request with a result there answers its tool call; one with a final
        result is told once (glint_agent_done) and leaves the inbox, as do requests past their time."""
        results = self.results(device_id)
        requests = self.pending(device_id)
        now = dt_util.utcnow()
        kept = []
        for request in requests:
            request_id = str(request.get("id"))
            result = results.get(request_id)
            status = (result or {}).get("status")
            if result is not None and status in (*FINAL, ASKED):
                future = self._waiting.get((device_id, request_id))
                if future is not None and not future.done():
                    future.set_result(result)
            if status in FINAL:
                self.hass.bus.async_fire(
                    EVENT_AGENT_DONE,
                    {
                        "device_id": device_id,
                        "request": request_id,
                        "agent": result.get("agent", request.get("agent")),
                        "action": result.get("action", request.get("action")),
                        "status": status,
                        "said": result.get("said") if isinstance(result.get("said"), list) else [],
                        "undo": result.get("undo"),
                        "code": result.get("code"),
                    },
                )
                continue
            until = until_of(request)
            if until is None or now >= until:
                continue
            kept.append(request)
        if len(kept) != len(requests):
            try:
                self._write_inbox(device_id, kept)
            except SettingsError as err:  # pragma: no cover - a smaller inbox always fits
                _LOGGER.warning("Couldn't prune the agent inbox of %s: %s", device_id, err.code)

    # The doorbell

    def set_bell(self, device_id: str, service: str | None) -> None:
        if service:
            self.bells[device_id] = service
        else:
            self.bells.pop(device_id, None)
        self._save()

    async def ring(self, device_id: str) -> bool:
        """Rings the phone's doorbell through its linked companion app: whether it was sent. It carries nothing."""
        service = self.bells.get(device_id)
        client = self.client_of(device_id)
        if not service or not is_glint(client) or not service.startswith(BELL_PREFIX):
            return False
        domain, _, name = service.partition(".")
        if not self.hass.services.has_service(domain, name):
            return False
        try:
            await self.hass.services.async_call(
                domain,
                name,
                {
                    "message": BELL_MESSAGE,
                    "data": {"intent_package_name": client, "intent_action": BELL_ACTION, "intent_class_name": BELL_CLASS},
                },
                blocking=True,
            )
        except Exception as err:  # noqa: BLE001 - a doorbell that doesn't ring only means the request waits
            _LOGGER.debug("Couldn't ring %s's doorbell: %s", device_id, err)
            return False
        return True

    def forget(self, device_id: str) -> None:
        """A device left the household: its doorbell link and its waiting calls go (its documents go with it)."""
        if self.bells.pop(device_id, None) is not None:
            self._save()
        for key in [k for k in self._waiting if k[0] == device_id]:
            future = self._waiting.pop(key)
            if not future.done():
                future.cancel()
