"""The household's Hearth devices as Home Assistant knows them: their secrets, what each last said, and pairing."""

from __future__ import annotations

from dataclasses import dataclass, field
import hashlib
import hmac
import secrets
from datetime import datetime
from typing import Any

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
    CONF_SECRET_HASH,
    CONF_SW_VERSION,
    CONNECTED_WITHIN,
    MAX_PENDING_PAIRINGS,
    MAX_STATUS_POSTS,
    PAIRING_EXPIRES,
    PAIRING_INTERVAL_PER_ADDRESS,
    SIGNAL_DEVICE_ADDED,
    SIGNAL_STATUS,
    STATUS_WINDOW,
    STORAGE_KEY,
    STORAGE_VERSION,
)
from .household import Household


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
    denied: bool = False


@dataclass
class DeviceState:
    status: dict[str, Any] | None = None
    seen: datetime | None = None
    posts: list[datetime] = field(default_factory=list)


class HearthHub:
    """One per config entry (the household)."""

    def __init__(self, hass: HomeAssistant, entry: ConfigEntry) -> None:
        self.hass = hass
        self.entry = entry
        self._store: Store[dict[str, Any]] = Store(hass, STORAGE_VERSION, f"{STORAGE_KEY}.{entry.entry_id}")
        self._states: dict[str, DeviceState] = {}
        # Kept outside the entry, so a pairing waiting to be collected survives the entry reloading
        shared = hass.data.setdefault(f"{DOMAIN}_pairing", {"pairings": {}, "asked_at": {}})
        self._pairings: dict[str, Pairing] = shared["pairings"]
        self._asked_at: dict[str, datetime] = shared["asked_at"]
        self.household = Household(hass, self)

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

    @callback
    def update_status(self, device_id: str, status: dict[str, Any]) -> None:
        state = self.state(device_id)
        state.status = status
        state.seen = dt_util.utcnow()
        self._store.async_delay_save(self._data_to_save, 30)
        async_dispatcher_send(self.hass, SIGNAL_STATUS.format(device_id))
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
        await self.household.limits.async_flush()

    async def async_remove_device(self, device_id: str) -> None:
        """Forgets a device: its secret stops working at once."""
        devices = {k: v for k, v in self.devices.items() if k != device_id}
        self.hass.config_entries.async_update_entry(self.entry, data={**self.entry.data, CONF_DEVICES: devices})
        self._states.pop(device_id, None)
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
        return pairing

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
        devices = {
            **self.devices,
            pairing.device_id: {
                "name": pairing.name,
                CONF_KIND: pairing.kind,
                CONF_MODEL: pairing.model,
                CONF_SW_VERSION: pairing.sw_version,
                CONF_SECRET_HASH: hash_secret(secret),
                CONF_PERSON: person,
            },
        }
        self.hass.config_entries.async_update_entry(self.entry, data={**self.entry.data, CONF_DEVICES: devices})
        pairing.secret = secret
        pairing.expires = dt_util.utcnow() + APPROVED_EXPIRES
        async_dispatcher_send(self.hass, SIGNAL_DEVICE_ADDED, pairing.device_id)
        return True

    def deny(self, pairing_id: str) -> None:
        pairing = self.pairing(pairing_id)
        if pairing is not None:
            pairing.denied = True

    def collect(self, pairing: Pairing) -> str | None:
        """The approved secret, once: the pairing ends with it."""
        secret = pairing.secret
        if secret is not None:
            self._pairings.pop(pairing.pairing_id, None)
        return secret
