"""The action log (docs/home-assistant-integration.md, Activity): what Hearth did, durably.

Every call Hearth makes to another integration goes through call_service (a test checks that no module calls
hass.services.async_call itself), which times it and records {at, kind: call, person, target, service, args, why,
result: ok | failed, error, duration_ms}. Holds Hearth starts and ends are recorded too ({kind: hold_start | hold_end,
person, target, reason, by}), and so are TV commands, Glint inbox writes and a standing rule going on or off ({kind:
rule}: Messages when away).

Records name people and devices by their entity or device ids only, never a name, and keep only call arguments from a
short allow list (ids, minutes, times, packages): never a message, a PIN or a token. They are kept 14 days, with Home
Assistant's storage helper (as history.py). The count is capped per kind (MAX_RECORDS calls, MAX_OTHER of each other
kind), so a busy kind never pushes out another's: the stray-pause release (stray_pauses.py) reads a week of hold
records, which a day's calls used to evict. A routine read that changes nothing (quiet=True: the Nintendo
applications list every 10 minutes) is recorded only when it fails. hearth.get_activity, the hearth/activity command
and the page's Activity view read them; diagnostics include the last 200.

Next to the records, the log knows which apps Hearth's own calls touch (own_call), for telling Hearth's changes from
an adult's in the provider's app (outside_apps.py): every app a call names, however many (a record keeps the first 50
of a list), from the moment the call starts (a pause of 150 apps takes minutes, and is recorded when it returns), and
when the call last ran. Kept OWN_KEEP, over a restart.
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
# The most call records kept
MAX_RECORDS = 5000
# The most records kept of each other kind (holds, TV commands, rules...): their own room, whatever the calls do
MAX_OTHER = 2000
# The log is trimmed every this many records added
TRIM_EVERY = 100
# How long the apps Hearth's own calls touched stay known (own_call)
OWN_KEEP = timedelta(days=1)
# The arguments of a call that name the app (or apps) it changes
_APP_ARGS = ("package_name", "app", "application_id", "app_id")
_APP_LIST_ARGS = ("packages", "apps")
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
        "end_time", "value", "option", "lock", "duration", "request_id", "approve", "application_id",
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


def apps_of(data: dict[str, Any] | None) -> frozenset[str]:
    """Every app a call names (a package, an application id), all of a list however long."""
    found: set[str] = set()
    for key in _APP_ARGS:
        value = (data or {}).get(key)
        if isinstance(value, str) and value:
            found.add(value)
    for key in _APP_LIST_ARGS:
        value = (data or {}).get(key)
        if isinstance(value, str) and value:
            found.add(value)
        elif isinstance(value, (list, tuple, set, frozenset)):
            found |= {v for v in value if isinstance(v, str) and v}
    return frozenset(found)


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
    quiet: bool = False,
) -> Any:
    """hass.services.async_call, recorded in the action log (every outbound call of Hearth's goes through here).

    [quiet]: a routine read that changes nothing; recorded only when it fails."""
    started = time.monotonic()
    # Known as Hearth's from now, not from when it returns: its changes show while it still runs
    log = _log_of(hass)
    token = log.begin(f"{domain}.{service}", data) if log is not None else None
    try:
        result = await hass.services.async_call(
            domain, service, data, blocking=blocking, context=context, target=target, return_response=return_response
        )
    except Exception as err:
        _record_call(hass, domain, service, data, person, why, started, err)
        raise
    finally:
        # Also when cancelled (a reload mid-call): what it changed until then is still Hearth's
        if log is not None and token is not None:
            log.finish(token)
    if quiet:
        _LOGGER.debug("call %s.%s for %s (%s): ok, not recorded", domain, service, person, why)
        return result
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
    """The records, newest last, kept 14 days and at most MAX_RECORDS calls and MAX_OTHER of each other kind."""

    def __init__(self, hass: HomeAssistant, household: Any, entry_id: str) -> None:
        self.hass = hass
        self.household = household
        self._store: Store[dict[str, Any]] = Store(hass, 1, f"hearth.activity.{entry_id}")
        self.records: list[dict[str, Any]] = []
        self._added = 0
        # The apps Hearth's own calls touched: service -> app -> when a call naming it last started or ended (ISO,
        # UTC). Every app of a call, not a record's first 50
        self._own: dict[str, dict[str, str]] = {}
        # Calls running now: token -> (service, its apps)
        self._running: dict[int, tuple[str, frozenset[str]]] = {}
        self._token = 0

    async def async_load(self) -> None:
        stored = await self._store.async_load() or {}
        self.records = [r for r in stored.get("records") or [] if isinstance(r, dict) and r.get("at")]
        own = stored.get("own")
        self._own = {
            str(service): {str(app): at for app, at in apps.items() if isinstance(at, str)}
            for service, apps in (own.items() if isinstance(own, dict) else ())
            if isinstance(apps, dict)
        }
        self._trim()

    def _data(self) -> dict[str, Any]:
        return {"records": self.records, "own": self._own}

    def _save(self) -> None:
        self._store.async_delay_save(self._data, 10)

    async def async_flush(self) -> None:
        await self._store.async_save(self._data())

    def _trim(self) -> None:
        """Drops what is older than KEEP, and of each kind what is beyond its own count (the oldest first): calls are
        many and holds few, and a count over all kinds let a week of calls push the holds out."""
        now = dt_util.utcnow()
        cutoff = (now - KEEP).isoformat()
        room: dict[str, int] = {}
        kept: list[dict[str, Any]] = []
        for record in reversed(self.records):
            if str(record.get("at")) < cutoff:
                continue
            kind = str(record.get("kind"))
            left = room.get(kind, MAX_RECORDS if kind == CALL else MAX_OTHER)
            if left <= 0:
                continue
            room[kind] = left - 1
            kept.append(record)
        kept.reverse()
        self.records = kept
        own_cutoff = (now - OWN_KEEP).isoformat()
        self._own = {
            service: fresh
            for service, apps in self._own.items()
            if (fresh := {app: at for app, at in apps.items() if at >= own_cutoff})
        }

    # Hearth's own calls, by app

    @callback
    def begin(self, service: str, data: dict[str, Any] | None) -> int | None:
        """A call of Hearth's starts: every app it names is Hearth's from now. Gives what finish() takes; None when
        the call names no app."""
        apps = apps_of(data)
        if not apps:
            return None
        self._token += 1
        self._running[self._token] = (service, apps)
        self._stamp(service, apps)
        return self._token

    @callback
    def finish(self, token: int) -> None:
        """That call returned (or failed, or was cancelled): its apps were last touched now."""
        service, apps = self._running.pop(token, (None, frozenset()))
        if service is not None:
            self._stamp(service, apps)

    def _stamp(self, service: str, apps: frozenset[str]) -> None:
        # Saved at the start too: a restart in the middle of a long call still knows its apps
        at = dt_util.utcnow().isoformat()
        mine = self._own.setdefault(service, {})
        for app in apps:
            mine[app] = at
        self._save()

    def own_call(self, services: Iterable[str], app: str, since: datetime) -> bool:
        """Whether a call of Hearth's to one of [services] naming [app] is running now, or ran (started or ended) at
        or after [since]."""
        services = set(services)
        if any(service in services and app in apps for service, apps in self._running.values()):
            return True
        lo = dt_util.as_utc(since).isoformat()
        return any((at := self._own.get(service, {}).get(app)) is not None and at >= lo for service in services)

    def person_of(self, data: dict[str, Any] | None) -> str | None:
        """The person an outbound call is about: the enforcer whose entity (or Family Link child, or Family Safety
        account: an older Family Safety is called by account id only) it names."""
        from . import family_link as fl
        from .enforce import FAMILY_SAFETY, enforcers_from_options, fs_account_of

        data = data or {}
        entity = data.get("entity_id")
        entity = entity[0] if isinstance(entity, list) and entity else entity
        child = data.get("child_id")
        account = data.get("account_id")
        for enforcer in enforcers_from_options(self.household.options):
            if entity and enforcer.entity_id == entity:
                return enforcer.person
            if child and fl.child_of(self.hass, enforcer.entity_id) == str(child):
                return enforcer.person
            if (
                account not in (None, "")
                and enforcer.kind == FAMILY_SAFETY
                and fs_account_of(self.hass, enforcer.entity_id) == str(account)
            ):
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
        self._added += 1
        if self._added >= TRIM_EVERY:
            self._added = 0
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
