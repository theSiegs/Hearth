"""Requests for more time made on an Xbox or a PC, from the released Microsoft Family Safety.

A Family Safety that fires microsoft_family_safety_request and _request_resolved (a fork's) tells Hearth itself. The
released one (upstream's 2.3.0) fires neither, but keeps each child's Pending Requests sensor (unique id
<entry>_<account>_pending_requests): its state is the count, its `requests` attribute Microsoft's request dicts (id,
type, platform, requestedTime, displayName / appName, ...). Hearth reads it for each child with a Family Safety
enforcer and tells the requests apart by id:

- An id not seen before is a new request: the same as the event (Asks.from_family_safety: the ask, the adults told).
- An id gone from the list is resolved: the same as the event's "via app" (Asks.resolved_elsewhere; an ask Hearth
  answered itself is already closed, so nothing more happens). Once it is missing from a fresh reading (the sensor
  written again by a Family Safety poll: its last_reported moved), so within one poll, and GONE_GRACE has passed: the
  same poll writes the Allowed Now sensors too, maybe a moment after this one, and extra time showing there says how
  it was answered (below). Otherwise it closes as handled, as Family Safety doesn't say. Back in the list before
  that, it isn't resolved.
- Sooner, and as approved, when extra time newly shows on the request's platform for that kid (the platform's Allowed
  Now sensor: an allowUntil override that wasn't there, and isn't Hearth's own extra time) within MATCH_WINDOW of the
  id leaving the list: a parent approved it in the Family Safety app. The minutes are those to the extra time's end.
- An unavailable or unknown sensor, or one without `requests`, changes nothing (and isn't a reading). A list cut short
  (`truncated`) resolves nothing: a request it leaves out isn't gone (new ones it shows are still asks).
- The first reading of a child's sensor only learns what's pending (nothing is announced); what's known is kept with
  Home Assistant's storage helper, so a restart doesn't announce anything again, and a request that came or went
  while Home Assistant was off is found.
- Where the fork's events fire too, each request is handled once: the event marks its id known (and a resolved one
  forgotten), and Asks itself takes one ask per request id.
"""

from __future__ import annotations

from datetime import datetime, timedelta
import logging
from typing import TYPE_CHECKING, Any

from homeassistant.core import CALLBACK_TYPE, HomeAssistant, callback
from homeassistant.helpers.event import async_call_later
from homeassistant.helpers import entity_registry as er
from homeassistant.helpers.storage import Store
from homeassistant.util import dt as dt_util

from .const import DOMAIN
from .enforce import FAMILY_SAFETY, FS_ALLOW_UNTIL, FS_DOMAIN, FS_OWN_TOLERANCE, enforcers_from_options, fs_account_of

if TYPE_CHECKING:
    from .hub import Hub

_LOGGER = logging.getLogger(__name__)

# A request missing from this many fresh readings of the sensor in a row is resolved
GONE_READINGS = 1
# ... once this long after it first went missing: the rest of that Family Safety poll (its Allowed Now sensors) lands
GONE_GRACE = timedelta(seconds=5)
# Extra time that newly shows this close to a request leaving the list is its approval
MATCH_WINDOW = timedelta(minutes=3)
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


def _gone(value: Any) -> dict[str, Any] | None:
    """A known request's record: None while listed, else {since (ISO), readings (fresh ones without it)}. An older
    Hearth kept only when it went (ISO): one reading."""
    if isinstance(value, dict) and isinstance(value.get("since"), str):
        return {"since": value["since"], "readings": int(value.get("readings") or 0)}
    if isinstance(value, str):
        return {"since": value, "readings": 1}
    return None


def _platform(state: Any) -> str:
    named = state.attributes.get("platform") or ("Xbox" if "xbox" in state.entity_id else "Windows")
    return str(named).lower()


class RequestTracker:
    """The Family Safety requests Hearth knows per child account: {account: {request id: None while listed, or
    {since, readings} once gone}}, with each request's platform."""

    def __init__(self, hass: HomeAssistant, hub: Hub) -> None:
        self.hass = hass
        self.hub = hub
        self._store: Store[dict[str, Any]] = Store(hass, 1, f"hearth.fs_requests.{hub.entry.entry_id}")
        self.known: dict[str, dict[str, dict[str, Any] | None]] = {}
        # Each known request's platform (lowercase), for matching extra time that shows when it goes
        self.platforms: dict[str, str] = {}
        # The Pending Requests sensors read, and the kids' Allowed Now sensors (a change of one reads again)
        self.watched: set[str] = set()
        # The sensor's last reading counted, per account (its last_reported): a fresh one is another poll
        self._readings: dict[str, str] = {}
        # The extra time in force per account and platform (its end, or None), and when extra time newly showed
        self._extra: dict[str, dict[str, str | None]] = {}
        self._extra_at: dict[str, dict[str, tuple[Any, str]]] = {}
        # The check waiting for a grace to pass (one at a time)
        self._later: CALLBACK_TYPE | None = None
        # Request ids resolved lately (newest last)
        self.resolved: list[str] = []

    async def async_load(self) -> None:
        stored = await self._store.async_load() or {}
        self.known = {
            str(account): {str(i): _gone(g) for i, g in ids.items()}
            for account, ids in (stored.get("known") or {}).items()
            if isinstance(ids, dict)
        }
        self.platforms = {str(i): str(p) for i, p in (stored.get("platforms") or {}).items() if p}
        self.resolved = [str(i) for i in stored.get("resolved") or []][-RESOLVED_MEMORY:]
        if stored.get("events_seen"):
            self.hass.data[EVENTS_SEEN] = True

    def _data(self) -> dict[str, Any]:
        return {
            "known": self.known,
            "platforms": self.platforms,
            "resolved": self.resolved,
            "events_seen": bool(self.hass.data.get(EVENTS_SEEN)),
        }

    def _save(self) -> None:
        self._store.async_delay_save(self._data, 2)

    async def async_flush(self) -> None:
        if self._later is not None:
            self._later()
            self._later = None
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
        self.platforms.pop(str(request_id), None)
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

    def _hearth_s(self, person: str, platform: str, until: str) -> bool:
        """Extra time ending at [until] is the extra time Hearth itself last gave there (not a parent's approval)."""
        enforcement = self.hub.household.enforcement
        if enforcement.fs_bonus_until is None:
            return False
        named = "Xbox" if platform == "xbox" else "Windows"
        # Any of Hearth's extra time there today, not only the latest
        ends = enforcement.fs_bonus_ends
        ours = list(ends(person, named)) if ends is not None else []
        latest = enforcement.fs_bonus_until(person, named)
        if latest is not None:
            ours.append(latest)
        shown = dt_util.parse_datetime(until)
        if not ours or shown is None:
            return False
        if shown.tzinfo is None:
            shown = shown.replace(tzinfo=dt_util.get_default_time_zone())
        return any(abs(dt_util.as_utc(shown) - dt_util.as_utc(end)) <= FS_OWN_TOLERANCE for end in ours)

    def _read_extra(self, account: str, person: str, watched: set[str], now: datetime) -> None:
        """The kid's Allowed Now sensors: extra time (allowUntil) that newly shows is noted with when."""
        seen = self._extra.setdefault(account, {})
        for state in self.hass.states.async_all("binary_sensor"):
            attrs = state.attributes
            if "override" not in attrs or str(attrs.get("user_id")) != account:
                continue
            watched.add(state.entity_id)
            if state.state in ("unavailable", "unknown"):
                continue
            platform = _platform(state)
            until = attrs.get("override_until") if attrs.get("override") == FS_ALLOW_UNTIL else None
            until = str(until) if until else None
            first = platform not in seen
            before = seen.get(platform)
            seen[platform] = until
            if first or until is None or until == before or self._hearth_s(person, platform, until):
                continue
            self._extra_at.setdefault(account, {})[platform] = (now, until)

    def _approval(self, account: str, request_id: str, since: str) -> int | None:
        """The minutes of extra time that newly showed on the request's platform around when it left the list (a
        parent's approval in the Family Safety app); None when none did."""
        gone = dt_util.parse_datetime(since)
        if gone is None:
            return None
        wanted = self.platforms.get(request_id)
        for platform, (at, until) in (self._extra_at.get(account) or {}).items():
            if (wanted and platform != wanted) or abs(at - gone) > MATCH_WINDOW:
                continue
            ends = dt_util.parse_datetime(until)
            if ends is None:
                return 0
            if ends.tzinfo is None:
                ends = ends.replace(tzinfo=dt_util.get_default_time_zone())
            return max(round((dt_util.as_utc(ends) - at).total_seconds() / 60), 0)
        return None

    @callback
    def _check_later(self) -> None:
        """Reads again once GONE_GRACE has passed (a request gone without extra time showing yet)."""
        if self._later is not None:
            return

        @callback
        def _due(_now: Any) -> None:
            self._later = None
            self.check()

        self._later = async_call_later(self.hass, GONE_GRACE.total_seconds() + 0.1, _due)

    @callback
    def check(self) -> None:
        """Reads each child's Pending Requests sensor: new ids are asks, ids gone from enough fresh readings in a row
        (or as extra time shows) are resolved."""
        watched: set[str] = set()
        changed = False
        now = dt_util.utcnow()
        for account, person in self._accounts().items():
            entity_id = pending_sensor(self.hass, account)
            if entity_id is None:
                continue
            watched.add(entity_id)
            self._read_extra(account, person, watched, now)
            state = self.hass.states.get(entity_id)
            requests = state.attributes.get("requests") if state is not None else None
            if state is None or state.state in ("unavailable", "unknown") or not isinstance(requests, list):
                continue  # no reading: no change
            reading = (getattr(state, "last_reported", None) or state.last_updated).isoformat()
            fresh = self._readings.get(account) != reading
            self._readings[account] = reading
            current = {
                str(r["id"]): r for r in requests if isinstance(r, dict) and r.get("id") not in (None, "")
            }
            for request_id, request in current.items():
                platform = str(request.get("platform") or "").lower()
                if platform and self.platforms.get(request_id) != platform:
                    self.platforms[request_id] = platform
                    changed = True
            # A list cut short (truncated): the requests it shows are there, but one it leaves out isn't gone
            cut_short = bool(state.attributes.get("truncated"))
            if account not in self.known:
                if cut_short:
                    continue  # learned from a whole list only: the rest would be announced as new later
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
                if request_id in current or cut_short:
                    continue
                if gone is None:
                    gone = known[request_id] = {"since": now.isoformat(), "readings": 1}
                    self._check_later()
                    changed = True
                elif fresh:
                    gone["readings"] += 1
                    changed = True
                minutes = self._approval(account, request_id, gone["since"])
                if minutes is None:
                    since = dt_util.parse_datetime(gone["since"])
                    if gone["readings"] < GONE_READINGS:
                        continue
                    if since is not None and now - since < GONE_GRACE:
                        self._check_later()
                        continue
                del known[request_id]
                self.platforms.pop(request_id, None)
                self._resolved(request_id)
                changed = True
                if minutes is not None:
                    _LOGGER.debug("A Family Safety request left its list as extra time showed: approved")
                    self.hub.asks.resolved_elsewhere(request_id, "approved", minutes or None)
                else:
                    self.hub.asks.resolved_elsewhere(request_id, "unknown")
        # Extra time noted a while ago matches nothing any more
        for platforms in self._extra_at.values():
            for platform, (at, _until) in list(platforms.items()):
                if now - at > MATCH_WINDOW * 2:
                    del platforms[platform]
        self.watched = watched
        if changed:
            self._save()
