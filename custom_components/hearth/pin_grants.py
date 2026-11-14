"""PIN grants: what a parent PIN typed on a device lets that device write (contract 3, docs/contracts/device-api.md).

A right PIN at verify_pin (api.py, an adult's Parent PIN checked here) answers a grant along with whose PIN it was. The
grant is for the device that asked only, lasts GRANT_SECONDS and allows GRANT_WRITES client-settings writes outside
what the device may write alone (client_settings.py); each is kept with updated_by "pin". A device holds one grant at a
time: a new one replaces it. A PIN a device checks on its own (a TV's copy of the hashes, a phone's local PIN) never
makes one: only Home Assistant's check does.

Grants live outside the entry, like the PIN lockout, so an options change (which reloads the entry) doesn't void one; a
restart does. Only the grant's hash is kept.
"""

from __future__ import annotations

from dataclasses import dataclass
from datetime import datetime, timedelta
import hashlib
import hmac
import secrets

from homeassistant.core import HomeAssistant
from homeassistant.util import dt as dt_util

from .const import DOMAIN

GRANT_SECONDS = 120
GRANT_WRITES = 8


def _hash(grant: str) -> str:
    return hashlib.sha256(grant.encode()).hexdigest()


@dataclass
class Grant:
    grant_hash: str
    person: str
    expires: datetime
    writes_left: int = GRANT_WRITES


class PinGrants:
    """The live grant of each device, by device id."""

    def __init__(self, hass: HomeAssistant) -> None:
        self._grants: dict[str, Grant] = hass.data.setdefault(f"{DOMAIN}_pin_grants", {})

    def mint(self, device_id: str, person: str) -> str:
        """A new grant for [device_id], from [person]'s PIN; the device's earlier one ends."""
        grant = secrets.token_urlsafe(24)
        self._grants[device_id] = Grant(_hash(grant), person, dt_util.utcnow() + timedelta(seconds=GRANT_SECONDS))
        return grant

    def valid(self, device_id: str, grant: str | None) -> Grant | None:
        """The device's grant when [grant] is it, unexpired, with writes left; else None."""
        held = self._grants.get(device_id)
        if held is None or not isinstance(grant, str) or not grant:
            return None
        if held.expires <= dt_util.utcnow() or held.writes_left <= 0:
            self._grants.pop(device_id, None)
            return None
        if not hmac.compare_digest(held.grant_hash, _hash(grant)):
            return None
        return held

    def spend(self, device_id: str, held: Grant) -> None:
        """One write made with the grant."""
        held.writes_left -= 1
        if held.writes_left <= 0:
            self._grants.pop(device_id, None)

    def forget(self, device_id: str) -> None:
        self._grants.pop(device_id, None)
