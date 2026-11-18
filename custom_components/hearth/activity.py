"""The action log (docs/home-assistant-integration.md, Activity): what Hearth did, durably.

Every call Hearth makes to another integration goes through call_service (a test checks that no module calls
hass.services.async_call itself), which times it and records {at, kind: call, person, target, service, args, why,
result: ok | failed, error, duration_ms}. Holds Hearth starts and ends are recorded too ({kind: hold_start | hold_end,
person, target, reason, by}), and so are TV commands, Glint inbox writes and a standing rule going on or off ({kind:
rule}: Messages when away).

Records name people and devices by their entity or device ids only, never a name, and keep only call arguments from a
short allow list (ids, minutes, times, packages): never a message, a PIN or a token. They are kept 14 days, at most
MAX_RECORDS, with Home Assistant's storage helper (as history.py). hearth.get_activity, the hearth/activity command and
the page's Activity view read them; diagnostics include the last 200.
"""

from __future__ import annotations

from collections.abc import Iterable
from datetime import datetime, timedelta
import logging
import time
from typing import Any

from homeassistant.core import HomeAssistant, callback
from homeassistant.helpers.storage import Store
from homeassistant.util import dt as dt_util

from .const import DOMAIN

_LOGGER = logging.getLogger(__name__)

KEEP = timedelta(days=14)
MAX_RECORDS = 5000
CALL = "call"
HOLD_START = "hold_start"
HOLD_END = "hold_end"
TV_COMMAND = "tv_command"
GLINT_INBOX = "glint_inbox"
# A standing rule went on or off for a kid (presence_rules.py): {person, target: its apps, reason: the rule, result:
# opened | closed}. Never where they were
RULE = "rule"
KINDS = (CALL, HOLD_START, HOLD_END, TV_COMMAND, GLINT_INBOX, RULE)
# Call arguments kept in a record: ids, numbers and times. Anything else (a message, a title, a PIN, a token, a code)
# is left out
SAFE_ARGS = frozenset(
    {
        "entity_id", "device_id", "child_id", "account_id", "package_name", "packages", "app", "apps", "platform",
        "daily_minutes", "minutes", "bonus_minutes", "day", "day_of_week", "hours", "until", "scope", "start_time",
        "end_time", "value", "option", "lock", "duration", "request_id", "approve",
    }
)
# Domains whose calls name a person's device: the person is found from the entity's enforcer
_TRACKED = frozenset({"familylink", "microsoft_family_safety", "nintendo_parental_controls"})


def safe_args(data: dict[str, Any] | None) -> dict[str, Any]:
    out: dict[str, Any] = {}
    for key, value in (data or {}).items():
        if key not in SAFE_ARGS:
            continue
        if isinstance(value, (list, tuple, set)):
            value = [str(v)[:120] for v in list(value)[:50]]
        elif not isinstance(value, (int, float, bool)) and value is not None:
            value = str(value)[:120]
        out[key] = value
    return out


def _log_of(hass: HomeAssistant) -> ActivityLog | None:
    for entry in hass.config_entries.async_loaded_entries(DOMAIN):
        hub = getattr(entry, "runtime_data", None)
        log = getattr(getattr(hub, "household", None), "activity", None)
        if log is not None:
            return log
    return None


async def call_service(
    hass: HomeAssistant,
    domain: str,
    service: str,
    data: dict[str, Any] | None = None,
    blocking: bool = False,
    context: Any = None,
    target: dict[str, Any] | None = None,
    return_response: bool = False,
    *,
    person: str | None = None,
    why: str | None = None,
) -> Any:
    """hass.services.async_call, recorded in the action log (every outbound call of Hearth's goes through here)."""
    started = time.monotonic()
    try:
        result = await hass.services.async_call(
            domain, service, data, blocking=blocking, context=context, target=target, return_response=return_response
        )
    except Exception as err:
        _record_call(hass, domain, service, data, person, why, started, err)
        raise
    _record_call(hass, domain, service, data, person, why, started, None)
    return result


def _record_call(
    hass: HomeAssistant, domain: str, service: str, data: dict[str, Any] | None, person: str | None,
    why: str | None, started: float, err: BaseException | None,
) -> None:
    log = _log_of(hass)
    duration = int((time.monotonic() - started) * 1000)
    if err is None:
        _LOGGER.debug("call %s.%s for %s (%s): ok in %d ms", domain, service, person, why, duration)
    else:
        _LOGGER.debug("call %s.%s for %s (%s): failed in %d ms: %s", domain, service, person, why, duration, err)
    if log is None:
        return
    if person is None and domain in _TRACKED:
        person = log.person_of(data)
    # A notification's text names people: only that one went out
    args = {} if domain in ("notify", "persistent_notification", "tts", "conversation") else safe_args(data)
    target_ids: list[str] = []
    for key in ("entity_id", "device_id"):
        given = (data or {}).get(key)
        if given:
            target_ids += [str(x) for x in (given if isinstance(given, (list, tuple)) else [given])]
    log.add(
        CALL,
        person=person,
        target=target_ids,
        service=f"{domain}.{service}",
        args=args,
        why=why,
        result="ok" if err is None else "failed",
        error=None if err is None else str(err)[:200],
        duration_ms=duration,
    )


class ActivityLog:
    """The records, newest last, kept 14 days and at most MAX_RECORDS."""

    def __init__(self, hass: HomeAssistant, household: Any, entry_id: str) -> None:
        self.hass = hass
        self.household = household
        self._store: Store[dict[str, Any]] = Store(hass, 1, f"hearth.activity.{entry_id}")
        self.records: list[dict[str, Any]] = []

    async def async_load(self) -> None:
        stored = await self._store.async_load() or {}
        self.records = [r for r in stored.get("records") or [] if isinstance(r, dict) and r.get("at")]
        self._trim()

    def _data(self) -> dict[str, Any]:
        return {"records": self.records}

    def _save(self) -> None:
        self._store.async_delay_save(self._data, 10)

    async def async_flush(self) -> None:
        await self._store.async_save(self._data())

    def _trim(self) -> None:
        cutoff = (dt_util.utcnow() - KEEP).isoformat()
        self.records = [r for r in self.records if str(r.get("at")) >= cutoff][-MAX_RECORDS:]

    def person_of(self, data: dict[str, Any] | None) -> str | None:
        """The person an outbound call is about: the enforcer whose entity (or Family Link child) it names."""
        from . import family_link as fl
        from .enforce import enforcers_from_options

        data = data or {}
        entity = data.get("entity_id")
        entity = entity[0] if isinstance(entity, list) and entity else entity
        child = data.get("child_id")
        for enforcer in enforcers_from_options(self.household.options):
            if entity and enforcer.entity_id == entity:
                return enforcer.person
            if child and fl.child_of(self.hass, enforcer.entity_id) == str(child):
                return enforcer.person
        if entity and child is None:
            state = self.hass.states.get(entity)
            child = state.attributes.get("child_id") if state else None
            if child:
                return self.person_of({"child_id": child})
        return None

    @callback
    def add(self, kind: str, **fields: Any) -> dict[str, Any]:
        record = {"at": dt_util.utcnow().isoformat(), "kind": kind, **{k: v for k, v in fields.items() if v not in (None, [], {})}}
        self.records.append(record)
        if len(self.records) > MAX_RECORDS + 100:
            self._trim()
        self._save()
        return record

    @callback
    def hold(self, start: bool, person: str, target: Iterable[str] | str, reason: str | None, by: str | None) -> None:
        targets = [target] if isinstance(target, str) else sorted(target)
        _LOGGER.debug("%s %s for %s (%s, %s)", "hold" if start else "let go", targets, person, reason, by)
        self.add(HOLD_START if start else HOLD_END, person=person, target=targets, reason=reason, by=by)

    def query(
        self,
        person: str | None = None,
        kind: str | None = None,
        since: datetime | None = None,
        until: datetime | None = None,
        limit: int = 200,
    ) -> list[dict[str, Any]]:
        """Newest first."""
        out = []
        lo = dt_util.as_utc(since).isoformat() if since else None
        hi = dt_util.as_utc(until).isoformat() if until else None
        for record in reversed(self.records):
            if person and record.get("person") != person:
                continue
            if kind and record.get("kind") != kind:
                continue
            if lo and record["at"] < lo:
                continue
            if hi and record["at"] > hi:
                continue
            out.append(record)
            if len(out) >= limit:
                break
        return out
