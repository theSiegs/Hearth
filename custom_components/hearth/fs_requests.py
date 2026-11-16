"""Requests for more time made on an Xbox or a PC, from the released Microsoft Family Safety.

A Family Safety that fires microsoft_family_safety_request and _request_resolved (a fork's) tells Hearth itself. The
released one (upstream's 2.3.0) fires neither, but keeps each child's Pending Requests sensor (unique id
<entry>_<account>_pending_requests): its state is the count, its `requests` attribute Microsoft's request dicts (id,
type, platform, requestedTime, displayName / appName, ...). Hearth reads it for each child with a Family Safety
enforcer and tells the requests apart by id:

- An id not seen before is a new request: the same as the event (Asks.from_family_safety: the ask, the adults told).
- An id gone from the list is resolved: the same as the event's "via app" (Asks.resolved_elsewhere, handled; an ask
  Hearth answered itself is already closed, so nothing more happens). Only once it has been gone for
  REQUEST_GONE_AFTER while the sensor still reads (an empty or failed read is no answer, as the fork's own events
  wait some polls).
- An unavailable or unknown sensor, or one without `requests`, changes nothing.
- The first reading of a child's sensor only learns what's pending (nothing is announced); what's known is kept with
  Home Assistant's storage helper, so a restart doesn't announce anything again, and a request that came or went
  while Home Assistant was off is found.
- Where the fork's events fire too, each request is handled once: the event marks its id known (and a resolved one
  forgotten), and Asks itself takes one ask per request id.
"""

from __future__ import annotations

from datetime import timedelta
import logging
from typing import TYPE_CHECKING, Any

from homeassistant.core import HomeAssistant, callback
from homeassistant.helpers import entity_registry as er
from homeassistant.helpers.storage import Store
from homeassistant.util import dt as dt_util

from .const import DOMAIN
from .enforce import FAMILY_SAFETY, FS_DOMAIN, enforcers_from_options, fs_account_of

if TYPE_CHECKING:
    from .hub import Hub

_LOGGER = logging.getLogger(__name__)

# A request gone from the list this long (while the sensor reads) is resolved
REQUEST_GONE_AFTER = timedelta(minutes=5)
# How many resolved request ids are remembered
RESOLVED_MEMORY = 200
# hass.data key: Family Safety fired its own request events here (a fork's): fs_capabilities says so
EVENTS_SEEN = f"{DOMAIN}_fs_request_events"


def pending_sensor(hass: HomeAssistant, account: str) -> str | None:
    """The child's Pending Requests sensor (by its unique id's end)."""
    suffix = f"_{account}_pending_requests"
    return next(
        (
            entry.entity_id
            for entry in er.async_get(hass).entities.values()
            if entry.domain == "sensor" and entry.platform == FS_DOMAIN and str(entry.unique_id).endswith(suffix)
        ),
        None,
    )


def request_event(account: str, request: dict[str, Any]) -> dict[str, Any]:
    """A request as the fork's microsoft_family_safety_request event has it."""
    return {
        "account_id": account,
        "request_id": str(request["id"]),
        "type": request.get("type"),
        "platform": request.get("platform"),
        "app_id": request.get("appId"),
        "app_name": request.get("displayName") or request.get("appName"),
        "requested_time": request.get("requestedTime"),
        "via_sensor": True,
    }


class RequestTracker:
    """The Family Safety requests Hearth knows per child account: {account: {request id: gone since (ISO) or None}}."""

    def __init__(self, hass: HomeAssistant, hub: Hub) -> None:
        self.hass = hass
        self.hub = hub
        self._store: Store[dict[str, Any]] = Store(hass, 1, f"hearth.fs_requests.{hub.entry.entry_id}")
        self.known: dict[str, dict[str, str | None]] = {}
        # The Pending Requests sensors read (a change of one reads again)
        self.watched: set[str] = set()
        # Request ids resolved lately (newest last)
        self.resolved: list[str] = []

    async def async_load(self) -> None:
        stored = await self._store.async_load() or {}
        self.known = {
            str(account): {str(i): (g if isinstance(g, str) else None) for i, g in ids.items()}
            for account, ids in (stored.get("known") or {}).items()
            if isinstance(ids, dict)
        }
        self.resolved = [str(i) for i in stored.get("resolved") or []][-RESOLVED_MEMORY:]
        if stored.get("events_seen"):
            self.hass.data[EVENTS_SEEN] = True

    def _data(self) -> dict[str, Any]:
        return {"known": self.known, "resolved": self.resolved, "events_seen": bool(self.hass.data.get(EVENTS_SEEN))}

    def _save(self) -> None:
        self._store.async_delay_save(self._data, 2)

    async def async_flush(self) -> None:
        await self._store.async_save(self._data())

    # The fork's events: the same requests, handled once

    @callback
    def event_seen(self, account: str | None, request_id: str) -> None:
        """A microsoft_family_safety_request: its id is known (the diff won't announce it again)."""
        self.hass.data[EVENTS_SEEN] = True
        if account:
            self.known.setdefault(str(account), {})[str(request_id)] = None
        self._save()

    @callback
    def resolved_seen(self, request_id: str) -> None:
        """A microsoft_family_safety_request_resolved: its id is forgotten (the diff won't resolve it again)."""
        self.hass.data[EVENTS_SEEN] = True
        for ids in self.known.values():
            ids.pop(str(request_id), None)
        self._resolved(str(request_id))
        self._save()

    def _resolved(self, request_id: str) -> None:
        """Remembered a while: a sensor still listing it (not refreshed yet) doesn't make it new again."""
        if request_id in self.resolved:
            self.resolved.remove(request_id)
        self.resolved.append(request_id)
        del self.resolved[:-RESOLVED_MEMORY]

    # The diff

    def _accounts(self) -> dict[str, str]:
        """{account: person} of the Family Safety enforcers."""
        found = {}
        for enforcer in enforcers_from_options(self.hub.entry.options):
            if enforcer.kind == FAMILY_SAFETY and (account := fs_account_of(self.hass, enforcer.entity_id)):
                found.setdefault(account, enforcer.person)
        return found

    @callback
    def check(self) -> None:
        """Reads each child's Pending Requests sensor: new ids are asks, ids gone long enough are resolved."""
        watched = set()
        changed = False
        now = dt_util.utcnow()
        for account, person in self._accounts().items():
            entity_id = pending_sensor(self.hass, account)
            if entity_id is None:
                continue
            watched.add(entity_id)
            state = self.hass.states.get(entity_id)
            requests = state.attributes.get("requests") if state is not None else None
            if state is None or state.state in ("unavailable", "unknown") or not isinstance(requests, list):
                continue  # no reading: no change
            current = {
                str(r["id"]): r for r in requests if isinstance(r, dict) and r.get("id") not in (None, "")
            }
            if account not in self.known:
                # The first reading: what's pending is learned, not announced
                self.known[account] = {request_id: None for request_id in current}
                changed = True
                continue
            known = self.known[account]
            for request_id, request in current.items():
                if request_id not in known and request_id in self.resolved:
                    continue  # resolved already: the sensor hasn't caught up
                if request_id not in known:
                    known[request_id] = None
                    changed = True
                    _LOGGER.debug("A Family Safety request seen on its Pending Requests sensor")
                    self.hub.asks.from_family_safety(person, request_event(account, request))
                elif known[request_id] is not None:
                    known[request_id] = None  # back in the list: not resolved
                    changed = True
            for request_id, gone in list(known.items()):
                if request_id in current:
                    continue
                if gone is None:
                    known[request_id] = now.isoformat()
                    changed = True
                elif (since := dt_util.parse_datetime(gone)) is None or now - since >= REQUEST_GONE_AFTER:
                    del known[request_id]
                    self._resolved(request_id)
                    changed = True
                    self.hub.asks.resolved_elsewhere(request_id, "unknown")
        self.watched = watched
        if changed:
            self._save()
