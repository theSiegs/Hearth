"""The household's Hearth devices as Home Assistant knows them: their secrets, what each last said, and pairing."""

from __future__ import annotations

from dataclasses import dataclass, field
import hashlib
import hmac
import secrets
from datetime import datetime
from typing import Any

from homeassistant.components import persistent_notification
from homeassistant.config_entries import ConfigEntry
from homeassistant.core import HomeAssistant, callback
from homeassistant.helpers.dispatcher import async_dispatcher_send
from homeassistant.helpers.storage import Store
from homeassistant.util import dt as dt_util

from .const import (
    DOMAIN,
    APPROVED_EXPIRES,
    CONF_DEVICES,
    CONF_KIND,
    CONF_MODEL,
    CONF_PERSON,
    CONF_PUSH_TOPIC,
    CONF_SECRET_HASH,
    CONF_SW_VERSION,
    CONNECTED_WITHIN,
    KIND_MOBILE,
    MAX_EVENT_POSTS,
    MAX_PENDING_PAIRINGS,
    MAX_STATUS_POSTS,
    PAIRING_EXPIRES,
    PAIRING_INTERVAL_PER_ADDRESS,
    EVENT_DEVICE_PAIRED,
    KIND_TV,
    MAX_TICKETS,
    TICKET_EXPIRES,
    SIGNAL_DEVICE_ADDED,
    SIGNAL_PAIRINGS,
    SIGNAL_STATUS,
    STATUS_WINDOW,
    STORAGE_KEY,
    STORAGE_VERSION,
)
from .asks import Asks
from .commands import Commands
from .push import PushChannel, new_topic
from .wait import DeviceWaits
from .household import Household
from .parent_pin import EVENT_PARENT_PIN_LOCKED_OUT


def hash_secret(secret: str) -> str:
    return hashlib.sha256(secret.encode()).hexdigest()


@dataclass
class Pairing:
    """A device asking to join, waiting for an administrator to check its code."""

    pairing_id: str
    code: str
    nonce_hash: str
    device_id: str
    kind: str
    name: str
    model: str | None
    sw_version: str | None
    expires: datetime
    # A phone's person, chosen when an administrator confirms
    person: str | None = None
    # Set once approved: the secret, handed to the device once
    secret: str | None = None
    # A phone's ntfy topic, made when it's approved (push.py)
    push_topic: str | None = None
    denied: bool = False


@dataclass
class Ticket:
    """A single-use pairing ticket a paired TV asked for: the device that redeems it pairs with no code to check."""

    kind: str
    # A phone's person (an adult's); None for a TV
    person: str | None
    # The paired TV that asked for it
    minted_by: str
    expires: datetime


def _shared(hass: HomeAssistant) -> dict[str, dict]:
    """Pairings kept outside the entry: approving one saves the device, which reloads the entry, and the device
    asking for its secret meanwhile must still find it. Tickets too, so an options change doesn't void one."""
    shared = hass.data.setdefault(f"{DOMAIN}_pairing", {"pairings": {}, "asked_at": {}})
    shared.setdefault("tickets", {})
    return shared


@dataclass
class PinLockout:
    """Wrong parent PINs in a row from one device, and the lockout they earned."""

    failures: int = 0
    locked_until: datetime | None = None


def pin_lockout(hass: HomeAssistant, device_id: str) -> PinLockout:
    """A device's parent-PIN lockout, kept outside the entry like the pairings: changing an option reloads the
    entry, and that must not hand someone guessing the PIN a fresh set of tries. A restart still clears it."""
    lockouts: dict[str, PinLockout] = hass.data.setdefault(f"{DOMAIN}_pin_lockout", {})
    return lockouts.setdefault(device_id, PinLockout())


def find_pairing(hass: HomeAssistant, pairing_id: str, nonce: str | None) -> Pairing | None:
    """A waiting pairing, only for the device that started it (it holds the nonce); works while the entry reloads."""
    pairings: dict[str, Pairing] = _shared(hass)["pairings"]
    now = dt_util.utcnow()
    for gone in [p.pairing_id for p in pairings.values() if p.expires <= now]:
        del pairings[gone]
    pairing = pairings.get(pairing_id)
    if pairing is None or not nonce or not hmac.compare_digest(pairing.nonce_hash, hash_secret(nonce)):
        return None
    return pairing


def collect_secret(hass: HomeAssistant, pairing: Pairing) -> str | None:
    """The approved secret, once: the pairing ends with it."""
    secret = pairing.secret
    if secret is not None:
        _shared(hass)["pairings"].pop(pairing.pairing_id, None)
    return secret


@dataclass
class DeviceState:
    status: dict[str, Any] | None = None
    seen: datetime | None = None
    posts: list[datetime] = field(default_factory=list)
    event_posts: list[datetime] = field(default_factory=list)


class HearthHub:
    """One per config entry (the household)."""

    def __init__(self, hass: HomeAssistant, entry: ConfigEntry) -> None:
        self.hass = hass
        self.entry = entry
        self._store: Store[dict[str, Any]] = Store(hass, STORAGE_VERSION, f"{STORAGE_KEY}.{entry.entry_id}")
        self._states: dict[str, DeviceState] = {}
        # A Home Assistant user's own asks (hearth/ask), counted as a device's events posts are
        self._user_posts: dict[str, list] = {}
        # Kept outside the entry, so a pairing waiting to be collected survives the entry reloading
        shared = _shared(hass)
        self._pairings: dict[str, Pairing] = shared["pairings"]
        self._asked_at: dict[str, datetime] = shared["asked_at"]
        # Pairing tickets by their hash (the ticket itself is never kept)
        self._tickets: dict[str, Ticket] = shared["tickets"]
        self.household = Household(hass, self)
        self.asks = Asks(hass, self)
        # One-shot commands for the TVs (hearth.play_on_tv), handed over in their state documents
        self.commands = Commands(hass)
        # "Something changed" pings to the phones, when the household has a push server
        self.push = PushChannel(hass, self)
        self.waits = DeviceWaits(hass, self)

    # The devices

    @property
    def devices(self) -> dict[str, dict[str, Any]]:
        return self.entry.data.get(CONF_DEVICES, {})

    def kind(self, device_id: str) -> str | None:
        device = self.devices.get(device_id)
        return device.get(CONF_KIND) if device else None

    def state(self, device_id: str) -> DeviceState:
        return self._states.setdefault(device_id, DeviceState())

    async def async_load(self) -> None:
        await self.household.async_load()
        stored = await self._store.async_load() or {}
        for device_id, kept in stored.items():
            if device_id not in self.devices or not isinstance(kept, dict):
                continue
            state = self.state(device_id)
            state.status = kept.get("status")
            seen = kept.get("seen")
            state.seen = dt_util.parse_datetime(seen) if isinstance(seen, str) else None

    def authorized(self, device_id: str, secret: str | None) -> bool:
        """The secret is this device's (compared in constant time; a removed device has none)."""
        device = self.devices.get(device_id)
        if device is None or not secret:
            return False
        return hmac.compare_digest(device.get(CONF_SECRET_HASH, ""), hash_secret(secret))

    def connected(self, device_id: str) -> bool:
        seen = self.state(device_id).seen
        return seen is not None and dt_util.utcnow() - seen < CONNECTED_WITHIN

    def too_often(self, device_id: str) -> bool:
        """Notes a post, and says whether the device posted too many in the last minute."""
        now = dt_util.utcnow()
        state = self.state(device_id)
        state.posts = [t for t in state.posts if now - t < STATUS_WINDOW]
        if len(state.posts) >= MAX_STATUS_POSTS:
            return True
        state.posts.append(now)
        return False

    def too_many_events(self, device_id: str) -> bool:
        """The same for its events posts, counted on their own."""
        now = dt_util.utcnow()
        state = self.state(device_id)
        state.event_posts = [t for t in state.event_posts if now - t < STATUS_WINDOW]
        if len(state.event_posts) >= MAX_EVENT_POSTS:
            return True
        state.event_posts.append(now)
        return False

    def too_many_user_asks(self, user_id: str) -> bool:
        """too_many_events for a Home Assistant user's own asks (hearth/ask)."""
        now = dt_util.utcnow()
        posts = [t for t in self._user_posts.get(user_id, []) if now - t < STATUS_WINDOW]
        self._user_posts[user_id] = posts
        if len(posts) >= MAX_EVENT_POSTS:
            return True
        posts.append(now)
        return False

    @callback
    def update_status(self, device_id: str, status: dict[str, Any]) -> None:
        state = self.state(device_id)
        # A TV checks the Parent PIN itself: a lockout there is told as for a phone that asked here
        before = (state.status or {}).get("pin_lockouts")
        after = status.get("pin_lockouts")
        if before is not None and after is not None and after > before:
            self.hass.bus.async_fire(
                EVENT_PARENT_PIN_LOCKED_OUT, {"device_id": device_id, "lockouts": after - before, "retry_in": None}
            )
        state.status = status
        state.seen = dt_util.utcnow()
        # What the TV ran of its commands leaves the queue (its answer no longer carries them)
        if status.get("commands_done"):
            self.commands.take_done(device_id, status["commands_done"])
        self._store.async_delay_save(self._data_to_save, 30)
        async_dispatcher_send(self.hass, SIGNAL_STATUS.format(device_id))
        # A TV paired after it had rules of its own: they're the kids' first budgets
        if status.get("local_rules") and self.kind(device_id) == KIND_TV:
            self.household.import_local_rules(device_id, status["local_rules"])
        self.household.recompute()

    @callback
    def _data_to_save(self) -> dict[str, Any]:
        return {
            device_id: {"status": state.status, "seen": state.seen.isoformat() if state.seen else None}
            for device_id, state in self._states.items()
            if device_id in self.devices
        }

    async def async_flush(self) -> None:
        """Saves what the devices last said now (Home Assistant also does when it stops)."""
        await self._store.async_save(self._data_to_save())
        await self.household.async_flush()
        await self.household.apps.async_flush()

    async def async_remove_device(self, device_id: str) -> None:
        """Forgets a device: its secret stops working at once."""
        devices = {k: v for k, v in self.devices.items() if k != device_id}
        self.hass.config_entries.async_update_entry(self.entry, data={**self.entry.data, CONF_DEVICES: devices})
        self._states.pop(device_id, None)
        self.commands.forget(device_id)
        await self._store.async_save(self._data_to_save())
        self.household.recompute()

    # Pairing

    def _drop_expired(self) -> None:
        now = dt_util.utcnow()
        for pairing_id in [p.pairing_id for p in self._pairings.values() if p.expires <= now]:
            del self._pairings[pairing_id]

    def start_pairing(
        self,
        address: str,
        device_id: str,
        kind: str,
        name: str,
        model: str | None,
        sw_version: str | None,
        nonce: str,
    ) -> Pairing | None:
        """A device asks to pair; None when too many are waiting or this address asked a moment ago."""
        self._drop_expired()
        now = dt_util.utcnow()
        last = self._asked_at.get(address)
        if last is not None and now - last < PAIRING_INTERVAL_PER_ADDRESS:
            return None
        if len(self._pairings) >= MAX_PENDING_PAIRINGS:
            return None
        self._asked_at[address] = now
        # The same device asking again replaces its earlier request
        for old in [p.pairing_id for p in self._pairings.values() if p.device_id == device_id]:
            del self._pairings[old]
        pairing = Pairing(
            pairing_id=secrets.token_urlsafe(16),
            code=f"{secrets.randbelow(1_000_000):06d}",
            nonce_hash=hash_secret(nonce),
            device_id=device_id,
            kind=kind,
            name=name,
            model=model,
            sw_version=sw_version,
            expires=now + PAIRING_EXPIRES,
        )
        self._pairings[pairing.pairing_id] = pairing
        async_dispatcher_send(self.hass, SIGNAL_PAIRINGS)
        return pairing

    def pending_pairings(self) -> list[Pairing]:
        """The devices waiting for an administrator to check their code."""
        self._drop_expired()
        return [p for p in self._pairings.values() if p.secret is None and not p.denied]

    def pairing(self, pairing_id: str) -> Pairing | None:
        self._drop_expired()
        return self._pairings.get(pairing_id)

    def pairing_for(self, pairing_id: str, nonce: str | None) -> Pairing | None:
        """The pairing, only for the device that started it (it holds the nonce)."""
        pairing = self.pairing(pairing_id)
        if pairing is None or not nonce or not hmac.compare_digest(pairing.nonce_hash, hash_secret(nonce)):
            return None
        return pairing

    async def async_approve(self, pairing_id: str, person: str | None = None) -> bool:
        """An administrator checked the code: the device joins (or gets a new secret, if it was here)."""
        pairing = self.pairing(pairing_id)
        if pairing is None or pairing.denied:
            return False
        secret = secrets.token_urlsafe(32)
        # A phone gets its own push topic; pairing again makes a new one, as it does a new secret
        topic = new_topic() if pairing.kind == KIND_MOBILE else None
        devices = {
            **self.devices,
            pairing.device_id: {
                "name": pairing.name,
                CONF_KIND: pairing.kind,
                CONF_MODEL: pairing.model,
                CONF_SW_VERSION: pairing.sw_version,
                CONF_SECRET_HASH: hash_secret(secret),
                CONF_PERSON: person,
                **({CONF_PUSH_TOPIC: topic} if topic else {}),
            },
        }
        self.hass.config_entries.async_update_entry(self.entry, data={**self.entry.data, CONF_DEVICES: devices})
        pairing.secret = secret
        pairing.person = person
        pairing.push_topic = topic
        pairing.expires = dt_util.utcnow() + APPROVED_EXPIRES
        async_dispatcher_send(self.hass, SIGNAL_DEVICE_ADDED, pairing.device_id)
        async_dispatcher_send(self.hass, SIGNAL_PAIRINGS)
        return True

    # Tickets: one confirmed pairing adds the household's other TVs, and a parent's phone in one tap

    def mint_ticket(self, minted_by: str, kind: str, person: str | None) -> str | None:
        """A single-use ticket a paired TV hands to another TV of its household (kind tv) or to a phone an adult bound
        as a parent's (kind mobile, for that adult); None when too many are outstanding."""
        now = dt_util.utcnow()
        for gone in [h for h, t in self._tickets.items() if t.expires <= now]:
            del self._tickets[gone]
        if len(self._tickets) >= MAX_TICKETS:
            return None
        ticket = secrets.token_urlsafe(32)
        self._tickets[hash_secret(ticket)] = Ticket(kind, person if kind == KIND_MOBILE else None, minted_by,
                                                    now + TICKET_EXPIRES)
        return ticket

    async def async_redeem(
        self,
        ticket: str,
        device_id: str,
        kind: str,
        name: str,
        model: str | None,
        sw_version: str | None,
    ) -> Pairing | None:
        """Pairs a device that holds a live ticket of its kind, at once (the TV that asked for the ticket vouched for
        it); None when the ticket is unknown, used, expired or of another kind. The ticket is spent either way."""
        now = dt_util.utcnow()
        held = self._tickets.pop(hash_secret(ticket), None)
        if held is None or held.expires <= now or held.kind != kind or held.minted_by not in self.devices:
            return None
        for old in [p.pairing_id for p in self._pairings.values() if p.device_id == device_id]:
            del self._pairings[old]
        pairing = Pairing(
            pairing_id=secrets.token_urlsafe(16),
            code="",
            nonce_hash="",
            device_id=device_id,
            kind=kind,
            name=name,
            model=model,
            sw_version=sw_version,
            expires=now + APPROVED_EXPIRES,
        )
        self._pairings[pairing.pairing_id] = pairing
        by_name = self.devices[held.minted_by].get("name") or held.minted_by
        if not await self.async_approve(pairing.pairing_id, held.person):
            return None
        self.hass.bus.async_fire(
            EVENT_DEVICE_PAIRED,
            {"device_id": device_id, "name": name, "kind": kind, "person": held.person, "by": held.minted_by},
        )
        persistent_notification.async_create(
            self.hass,
            f"**{name}** paired with Hearth through **{by_name}**, which is already paired. If that wasn't you, delete "
            "it in [Devices & services](/config/integrations/integration/hearth).",
            title="A Hearth device paired",
            notification_id=f"hearth_paired_{device_id}",
        )
        return pairing

    def deny(self, pairing_id: str) -> None:
        pairing = self.pairing(pairing_id)
        if pairing is not None:
            pairing.denied = True
            async_dispatcher_send(self.hass, SIGNAL_PAIRINGS)

    def collect(self, pairing: Pairing) -> str | None:
        """The approved secret, once: the pairing ends with it."""
        secret = pairing.secret
        if secret is not None:
            self._pairings.pop(pairing.pairing_id, None)
        return secret
