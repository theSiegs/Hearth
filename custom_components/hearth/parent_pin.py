"""The household's parent PIN: set by an adult in Configure, kept as a salted scrypt hash (never the PIN), and checked
for a paired device that asks (a kid's phone turning its kids mode off, say). The hash never leaves Home Assistant.

Wrong guesses lock the asking device out for longer each time: FREE_TRIES free, then LOCKOUT_FIRST, doubling to
LOCKOUT_MAX. A right PIN clears the count.
"""

from __future__ import annotations

from datetime import datetime, timedelta
import hashlib
import hmac
import re
import secrets
from typing import Any

CONF_PARENT_PIN = "parent_pin"
EVENT_PARENT_PIN_LOCKED_OUT = "hearth_parent_pin_locked_out"

PIN = re.compile(r"^\d{4,8}$")
FREE_TRIES = 5
LOCKOUT_FIRST = timedelta(seconds=30)
LOCKOUT_MAX = timedelta(hours=1)

# scrypt: about 50 ms a try here, 16 MB; run it in the executor
_N, _R, _P = 2**14, 8, 1


def _scrypt(pin: str, salt: bytes) -> bytes:
    return hashlib.scrypt(pin.encode(), salt=salt, n=_N, r=_R, p=_P, dklen=32)


def make(pin: str) -> dict[str, str]:
    """What the options keep for [pin]: a fresh salt and the hash."""
    salt = secrets.token_bytes(16)
    return {"salt": salt.hex(), "hash": _scrypt(pin, salt).hex()}


def matches(stored: dict[str, Any] | None, pin: str) -> bool:
    if not stored or not isinstance(pin, str) or not PIN.match(pin):
        return False
    try:
        salt = bytes.fromhex(stored["salt"])
        expected = bytes.fromhex(stored["hash"])
    except (KeyError, TypeError, ValueError):
        return False
    return hmac.compare_digest(_scrypt(pin, salt), expected)


def lockout(failures: int) -> timedelta | None:
    """How long a device waits after its [failures]th wrong PIN in a row (none while tries are free)."""
    if failures < FREE_TRIES:
        return None
    return min(LOCKOUT_FIRST * (2 ** (failures - FREE_TRIES)), LOCKOUT_MAX)


def retry_in(locked_until: datetime | None, now: datetime) -> int:
    """Seconds left of a lockout (0: none)."""
    if locked_until is None or locked_until <= now:
        return 0
    return int((locked_until - now).total_seconds()) + 1
