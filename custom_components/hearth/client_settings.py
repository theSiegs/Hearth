"""Client settings (`hearth.client-settings/1`): small JSON documents Hearth keeps for the apps paired with it, without
reading them (docs/contracts/client-settings.md).

A document is addressed by (client, scope, name): the client's id (client.py), a scope (`household`,
`person:<person entity id>` or `device:<device id>`) and a name. Hearth parses only the envelope; `data` is the
client's. Limits: MAX_DATA_BYTES per document, MAX_DOCS per client and scope, MAX_CLIENT_BYTES per client.

Who may write (the contract's table):

| Scope       | An adult in Home Assistant | An adult's device | A kid's device           | A TV                  |
|-------------|----------------------------|-------------------|--------------------------|-----------------------|
| household   | yes                        | yes               | never, not with a grant  | with a grant          |
| person:<p>  | yes                        | yes               | its own person, grant    | with a grant          |
| device:<d>  | yes                        | its own device    | its own device           | its own device        |

A grant comes from a parent PIN checked by verify_pin (pin_grants.py); a write it allows is kept with updated_by
"pin". A phone whose person isn't an adult on Hearth's page counts as a kid's. So a kid's device can't loosen anything
kept at person or household scope; what restricts a kid belongs at person scope, never in the device's own.

Who may read: an adult in Home Assistant, everything; a device, its client's household documents, its own device's,
and its own person's (an adult's device: every person's; a TV: the people of its profiles).

Writes are optimistic: `if_etag` (null: only when there is none yet), else 409 with the current etag. Each change
fires hearth_client_settings_changed {client, scope, name} (never the contents), and the devices see the new etags in
their state documents. Removing a device deletes its device documents; the rest stay until an adult removes them.
"""

from __future__ import annotations

from collections.abc import Callable
import json
import re
import secrets
from typing import TYPE_CHECKING, Any

from homeassistant.core import HomeAssistant, callback
from homeassistant.helpers.dispatcher import async_dispatcher_send
from homeassistant.helpers.storage import Store
from homeassistant.util import dt as dt_util

from .client import client_id
from .const import CONF_KIND, CONF_PERSON, CONF_ROLES, KIND_TV, SIGNAL_PEOPLE

if TYPE_CHECKING:
    from .hub import HearthHub

FORMAT = "hearth.client-settings/1"
EVENT_CLIENT_SETTINGS_CHANGED = "hearth_client_settings_changed"
# A document changed or went: (client, scope, name, etag or None), for the WebSocket's subscribers
SIGNAL_CLIENT_SETTINGS = "hearth_client_settings"

MAX_DATA_BYTES = 64 * 1024
MAX_DOCS = 16
MAX_CLIENT_BYTES = 1024 * 1024
MAX_SCHEMA = 64
MAX_LABEL = 40
_CONTROL = re.compile(r"[\x00-\x1f\x7f-\x9f]")

HOUSEHOLD = "household"
PERSON = "person"
DEVICE = "device"

# Who writes: an adult in Home Assistant (an administrator, or a user linked to an adult), an adult's paired device, a
# kid's paired device (or a phone whose person isn't an adult), a TV (a shared device)
ADULT = "adult"
ADULT_DEVICE = "adult_device"
KID_DEVICE = "kid_device"
TV_DEVICE = "tv"
# updated_by: what made the last write
BY_ADULT = "adult"
BY_KID_DEVICE = "kid_device"
BY_DEVICE = "device"
BY_PIN = "pin"

_NAME = re.compile(r"^[a-z0-9][a-z0-9._-]{0,63}$")
_SCHEMA = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._/:-]{0,63}$")
_PERSON_ID = re.compile(r"^person\.[a-z0-9_]{1,64}$")
_DEVICE_ID = re.compile(r"^[A-Za-z0-9_-]{8,64}$")


class SettingsError(Exception):
    """A refused write: code is changed (409), too_large or too_many (413), forbidden (403) or bad_request (400)."""

    def __init__(self, code: str, etag: str | None = None) -> None:
        super().__init__(code)
        self.code = code
        self.etag = etag


def parse_scope(value: Any) -> tuple[str, str | None] | None:
    """("household", None), ("person", "person.sam") or ("device", "<device id>"); None for anything else."""
    if not isinstance(value, str):
        return None
    if value == HOUSEHOLD:
        return HOUSEHOLD, None
    kind, _, target = value.partition(":")
    if kind == PERSON and _PERSON_ID.match(target):
        return PERSON, target
    if kind == DEVICE and _DEVICE_ID.match(target):
        return DEVICE, target
    return None


def valid_name(value: Any) -> bool:
    return isinstance(value, str) and bool(_NAME.match(value))


def valid_schema(value: Any) -> bool:
    return isinstance(value, str) and bool(_SCHEMA.match(value))


def data_size(data: Any) -> int:
    return len(json.dumps(data, separators=(",", ":"), ensure_ascii=False).encode("utf-8"))


def write_access(
    writer: str, scope: tuple[str, str | None], *, person: str | None = None, device: str | None = None
) -> tuple[str | None, bool]:
    """(updated_by when [writer] may write [scope] on its own, else None; whether a PIN grant lets it). [person] and
    [device] are the writing device's own."""
    kind, target = scope
    if writer == ADULT:
        return BY_ADULT, False
    if kind == DEVICE:
        # Every device writes its own device documents, and only those
        if target != device:
            return None, False
        return {ADULT_DEVICE: BY_ADULT, KID_DEVICE: BY_KID_DEVICE}.get(writer, BY_DEVICE), False
    if writer == ADULT_DEVICE:
        return BY_ADULT, False
    if writer == KID_DEVICE:
        # Never household, not even with a grant; its own person only with one
        return None, kind == PERSON and person is not None and target == person
    if writer == TV_DEVICE:
        # Shared by everyone in the room: household and person documents only with a parent PIN
        return None, True
    return None, False


def may_read(
    writer: str,
    scope: tuple[str, str | None],
    *,
    person: str | None = None,
    device: str | None = None,
    people: set[str] | frozenset[str] = frozenset(),
) -> bool:
    """Whether [writer] may read [scope]: an adult everything; a device household, its own device, and its person's
    (an adult's device every person's, a TV its profiles' [people])."""
    kind, target = scope
    if writer == ADULT or kind == HOUSEHOLD:
        return True
    if kind == DEVICE:
        return target == device
    if writer == ADULT_DEVICE:
        return True
    if writer == KID_DEVICE:
        return person is not None and target == person
    if writer == TV_DEVICE:
        return target in people
    return False


def scope_key(scope: tuple[str, str | None]) -> str:
    kind, target = scope
    return kind if target is None else f"{kind}:{target}"


def _now() -> str:
    return dt_util.utcnow().replace(microsecond=0).isoformat().replace("+00:00", "Z")


class ClientSettings:
    """The household's client settings, by client, scope and name, in a Home Assistant Store."""

    def __init__(self, hass: HomeAssistant, hub: HearthHub) -> None:
        self.hass = hass
        self.hub = hub
        self._store: Store[dict[str, Any]] = Store(hass, 1, f"hearth.client_settings.{hub.entry.entry_id}")
        # client -> scope key -> name -> the document (the envelope with data)
        self.docs: dict[str, dict[str, dict[str, dict[str, Any]]]] = {}

    async def async_load(self) -> None:
        stored = await self._store.async_load() or {}
        docs = stored.get("docs")
        self.docs = docs if isinstance(docs, dict) else {}

    def _save(self) -> None:
        self._store.async_delay_save(lambda: {"docs": self.docs}, 5)

    async def async_flush(self) -> None:
        await self._store.async_save({"docs": self.docs})

    # Who a device is

    def device_writer(self, device_id: str) -> tuple[str, str | None, set[str]]:
        """(writer kind, its person, the people it may read) for a paired device."""
        device = self.hub.devices.get(device_id, {})
        if device.get(CONF_KIND) == KIND_TV:
            return TV_DEVICE, None, set(self.hub.household.device_profile_people(device_id).values())
        person = device.get(CONF_PERSON)
        role = self.hub.entry.options.get(CONF_ROLES, {}).get(person) if person else None
        return (ADULT_DEVICE if role == "adult" else KID_DEVICE), person, set()

    def device_client(self, device_id: str) -> str | None:
        """The client id locked at the device's pairing (none for a device paired before contract 3)."""
        return ((self.hub.devices.get(device_id) or {}).get("client") or {}).get("id")

    # Reading

    def get(self, client: str, scope: tuple[str, str | None], name: str) -> dict[str, Any] | None:
        return self.docs.get(client, {}).get(scope_key(scope), {}).get(name)

    def etags_for_device(self, device_id: str) -> dict[str, str] | None:
        """{"<scope>/<name>": etag} of what the device may read of its own client's; None without a locked client."""
        client = self.device_client(device_id)
        if client is None:
            return None
        writer, person, people = self.device_writer(device_id)
        found: dict[str, str] = {}
        for key, named in sorted(self.docs.get(client, {}).items()):
            scope = parse_scope(key)
            if scope is None or not may_read(writer, scope, person=person, device=device_id, people=people):
                continue
            for name, doc in sorted(named.items()):
                found[f"{key}/{name}"] = doc["etag"]
        return found

    def listing(self, client: str | None = None) -> list[dict[str, Any]]:
        """Every document's envelope with its size, never its data (one client's, or all)."""
        return [
            {**{k: v for k, v in doc.items() if k != "data"}, "size": data_size(doc.get("data"))}
            for c, scopes in sorted(self.docs.items())
            if client is None or c == client
            for _key, named in sorted(scopes.items())
            for _name, doc in sorted(named.items())
        ]

    def summary(self) -> dict[str, dict[str, Any]]:
        """{client: {"count", "bytes", "labels"}}: what Hearth's page shows; each document's label, else "<client> ·
        <name>"."""
        out: dict[str, dict[str, Any]] = {}
        for client, scopes in sorted(self.docs.items()):
            docs = [doc for _key, named in sorted(scopes.items()) for _n, doc in sorted(named.items())]
            if docs:
                out[client] = {
                    "count": len(docs),
                    "bytes": sum(data_size(d.get("data")) for d in docs),
                    "labels": list(dict.fromkeys(d.get("label") or f"{client} · {d['name']}" for d in docs)),
                }
        return out

    # Writing

    def put(
        self,
        client: str,
        scope: tuple[str, str | None],
        name: str,
        schema: str,
        data: dict[str, Any],
        updated_by: str,
        if_etag: Any = ...,
        label: Any = None,
    ) -> dict[str, Any]:
        """Saves a document; its envelope (without data). [if_etag]: the etag it must have now (None: there must be
        none yet; left out: any). [label]: the client's own words for it (at most MAX_LABEL), shown verbatim on
        Hearth's page. SettingsError otherwise, or when it's over a limit."""
        if client_id(client) is None or not valid_name(name) or not valid_schema(schema) or not isinstance(data, dict):
            raise SettingsError("bad_request")
        if label is not None:
            if not isinstance(label, str):
                raise SettingsError("bad_request")
            label = _CONTROL.sub("", label).strip()
            if len(label) > MAX_LABEL:
                raise SettingsError("bad_request")
            label = label or None
        key = scope_key(scope)
        scopes = self.docs.get(client, {})
        current = scopes.get(key, {}).get(name)
        if if_etag is not ... and if_etag != (current or {}).get("etag"):
            raise SettingsError("changed", (current or {}).get("etag"))
        size = data_size(data)
        if size > MAX_DATA_BYTES:
            raise SettingsError("too_large")
        if current is None and len(scopes.get(key, {})) >= MAX_DOCS:
            raise SettingsError("too_many")
        others = sum(
            data_size(doc.get("data"))
            for k, named in scopes.items()
            for n, doc in named.items()
            if (k, n) != (key, name)
        )
        if others + size > MAX_CLIENT_BYTES:
            raise SettingsError("too_large")
        doc = {
            "format": FORMAT,
            "client": client,
            "scope": key,
            "name": name,
            "schema": schema,
            **({"label": label} if label else {}),
            "etag": secrets.token_hex(8),
            "updated": _now(),
            "updated_by": updated_by,
            "data": data,
        }
        self.docs.setdefault(client, {}).setdefault(key, {})[name] = doc
        self._changed(client, key, name, doc["etag"])
        return {k: v for k, v in doc.items() if k != "data"}

    def delete(self, client: str, scope: tuple[str, str | None], name: str, if_etag: Any = ...) -> bool:
        """Removes a document; False when there was none. SettingsError "changed" when [if_etag] isn't its etag."""
        key = scope_key(scope)
        named = self.docs.get(client, {}).get(key, {})
        current = named.get(name)
        if if_etag is not ... and if_etag != (current or {}).get("etag"):
            raise SettingsError("changed", (current or {}).get("etag"))
        if current is None:
            return False
        del named[name]
        self._prune(client, key)
        self._changed(client, key, name, None)
        return True

    def remove_device(self, device_id: str) -> None:
        """A device left the household: its device documents go, of every client."""
        key = scope_key((DEVICE, device_id))
        for client in list(self.docs):
            for name in list(self.docs[client].get(key, {})):
                self.delete(client, (DEVICE, device_id), name)

    def clear_client(self, client: str) -> int:
        """An adult removed everything kept for a client; how many documents went."""
        gone = 0
        for key in list(self.docs.get(client, {})):
            scope = parse_scope(key)
            for name in list(self.docs.get(client, {}).get(key, {})):
                if scope is not None and self.delete(client, scope, name):
                    gone += 1
        self.docs.pop(client, None)
        self._save()
        return gone

    def _prune(self, client: str, key: str) -> None:
        if not self.docs.get(client, {}).get(key):
            self.docs.get(client, {}).pop(key, None)
        if not self.docs.get(client):
            self.docs.pop(client, None)

    @callback
    def _changed(self, client: str, key: str, name: str, etag: str | None) -> None:
        self._save()
        self.hass.bus.async_fire(EVENT_CLIENT_SETTINGS_CHANGED, {"client": client, "scope": key, "name": name})
        async_dispatcher_send(self.hass, SIGNAL_CLIENT_SETTINGS, client, key, name, etag)
        # The devices' state documents carry the etags: their waits and push pings look again
        async_dispatcher_send(self.hass, SIGNAL_PEOPLE, False)


def device_write(
    settings: ClientSettings,
    grants,
    device_id: str,
    scope: tuple[str, str | None],
    grant: str | None,
    write: Callable[[str], Any],
) -> Any:
    """Runs [write](updated_by) when the device may make it: on its own, or with its live PIN grant (one of the grant's
    writes is spent, and it's kept as "pin"). SettingsError "forbidden" otherwise."""
    writer, person, _people = settings.device_writer(device_id)
    updated_by, with_grant = write_access(writer, scope, person=person, device=device_id)
    if updated_by is not None:
        return write(updated_by)
    if with_grant and (held := grants.valid(device_id, grant)) is not None:
        result = write(BY_PIN)
        grants.spend(device_id, held)
        return result
    raise SettingsError("forbidden")
