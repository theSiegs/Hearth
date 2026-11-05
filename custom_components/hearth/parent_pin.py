"""The adults' parent PINs, one each: set in Configure, kept as salted hashes (never the PIN), and checked for a paired
device that asks (a kid's phone turning its kids mode off, say). Any adult's PIN is a parent PIN; the answer says whose.

The hashes are in the TV's form (Hearth's ParentPinHash, `v2$<iterations>$<salt>$<hash>`, PBKDF2-HMAC-SHA256), because a
paired TV takes them in its state document and checks PINs itself: it needs its Parent PIN with Home Assistant down. A
phone never gets them; it asks (verify_pin).

Wrong guesses lock the asking device out for longer each time: FREE_TRIES free, then LOCKOUT_FIRST, doubling to
LOCKOUT_MAX. A right PIN clears the count. A TV keeps its own lockout and reports each one in its status.
"""

from __future__ import annotations

from datetime import datetime, timedelta
import hashlib
import hmac
import re
import secrets

# Options: {person entity id: stored hash}
CONF_PARENT_PINS = "parent_pins"
EVENT_PARENT_PIN_LOCKED_OUT = "hearth_parent_pin_locked_out"
EVENT_PARENT_PIN_USED = "hearth_parent_pin_used"

# Four digits: the TV's PIN pad, and Google TV's profile lock, take four
PIN = re.compile(r"^\d{4}$")
STORED = re.compile(r"^v2\$([0-9]{1,7})\$([0-9a-f]{32})\$([0-9a-f]{64})$")
ITERATIONS = 10000
FREE_TRIES = 5
LOCKOUT_FIRST = timedelta(seconds=30)
LOCKOUT_MAX = timedelta(hours=1)


def _derive(pin: str, salt: bytes, iterations: int) -> bytes:
    return hashlib.pbkdf2_hmac("sha256", pin.encode(), salt, iterations, 32)


def make(pin: str) -> str:
    """What the options keep for [pin]: the TV's form, with a fresh salt."""
    salt = secrets.token_bytes(16)
    return f"v2${ITERATIONS}${salt.hex()}${_derive(pin, salt, ITERATIONS).hex()}"


def valid(stored: object) -> bool:
    return isinstance(stored, str) and STORED.match(stored) is not None


def matches(stored: object, pin: object) -> bool:
    if not isinstance(pin, str) or not PIN.match(pin) or not isinstance(stored, str):
        return False
    found = STORED.match(stored)
    if not found:
        return False
    iterations = int(found.group(1))
    if not 1 <= iterations <= 200000:
        return False
    derived = _derive(pin, bytes.fromhex(found.group(2)), iterations)
    return hmac.compare_digest(derived.hex(), found.group(3))


def stored_pins(options) -> dict[str, str]:
    """The valid parent PINs in [options], by person."""
    pins = options.get(CONF_PARENT_PINS)
    return {p: h for p, h in pins.items() if valid(h)} if isinstance(pins, dict) else {}


def whose(pins: dict[str, str], pin: object) -> str | None:
    """The person whose parent PIN [pin] is (every one is checked, so the time doesn't tell how many come first)."""
    found = None
    for person, stored in sorted(pins.items()):
        if matches(stored, pin) and found is None:
            found = person
    return found


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
