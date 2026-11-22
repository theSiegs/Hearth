"""Setting a panel up over its socket (<domain>/panel/hello): which panel a hello is, whether it may be approved at once,
and each panel's proxy MAC. Pure: no Home Assistant state, so every rule is tested on its own.

How a hello is matched (first rule that fits):

1. its id is a panel's id or one of its tablet ids: that panel, with a new secret (the old one stops);
2. it names an area HA has, `replaces` isn't false, and exactly one panel in that area isn't connected: this tablet takes
   that panel's place (its id joins the panel's tablet ids);
3. it names an area HA has: a new panel in it;
4. anything else waits for an approval in HA.

Rules 1 to 3 are approved at once on any Home Assistant login but a kid's own (the owner's choice: a setup command
that names a room needs no step in HA); rule 4, and any hello on a kid's login, waits.
"""

from __future__ import annotations

import hashlib
import re
from collections.abc import Callable, Mapping
from dataclasses import dataclass
from typing import Any

KNOWN, TAKES_PLACE, NEW, WAITS = 1, 2, 3, 4

_MAC = re.compile(r"^[0-9a-f]{2}([:-]?)[0-9a-f]{2}(\1[0-9a-f]{2}){4}$")


def clean_mac(value: Any) -> str | None:
    """A unicast MAC as "aa:bb:cc:dd:ee:ff" (given with colons, dashes or none, any case); None for anything else."""
    if not isinstance(value, str) or not _MAC.match(value.strip().casefold()):
        return None
    digits = re.sub(r"[^0-9a-f]", "", value.casefold())
    if int(digits[:2], 16) & 0x01:
        # Multicast: never a device's
        return None
    return ":".join(digits[i : i + 2] for i in range(0, 12, 2))


def mac_from_id(device_id: str) -> str:
    """A new panel's proxy MAC: the first 6 bytes of SHA-256 of its device id, locally administered and unicast (the
    first byte's low two bits are 10)."""
    raw = bytearray(hashlib.sha256(device_id.encode()).digest()[:6])
    raw[0] = (raw[0] & 0xFC) | 0x02
    return ":".join(f"{b:02x}" for b in raw)


def esphome_name(value: Any) -> str:
    """An ESPHome entry's name, host or title as a proxy name compares: "kitchen-panel.local" -> "kitchen-panel"."""
    if not isinstance(value, str):
        return ""
    name = value.strip().casefold()
    if name.endswith(".local"):
        name = name[: -len(".local")]
    return re.sub(r"[^a-z0-9]+", "-", name).strip("-")


def adopted_mac(proxy_name: str, entries: list[tuple[Any, list[Any]]]) -> str | None:
    """The MAC of the one ESPHome entry ([unique_id, [title, name, host]]) whose name, title or host is [proxy_name];
    None when none is, or more than one with different MACs (never a guess)."""
    want = esphome_name(proxy_name)
    if not want:
        return None
    found = {
        mac
        for unique_id, names in entries
        if (mac := clean_mac(unique_id)) and any(esphome_name(n) == want for n in names)
    }
    return found.pop() if len(found) == 1 else None


@dataclass(frozen=True)
class Match:
    """What a hello is: [rule] (KNOWN, TAKES_PLACE, NEW or WAITS) and the panel it matched (KNOWN, TAKES_PLACE)."""

    rule: int
    device_id: str | None = None


def panel_of(device_id: str, panels: Mapping[str, Mapping[str, Any]]) -> str | None:
    """The panel whose id, or one of whose tablet ids, [device_id] is."""
    if device_id in panels:
        return device_id
    return next((d for d, record in panels.items() if device_id in (record.get("tablet_ids") or ())), None)


def match(
    device_id: str,
    area_id: str | None,
    replaces: bool | None,
    panels: Mapping[str, Mapping[str, Any]],
    area_of: Callable[[str], str | None],
    connected: Callable[[str], bool],
) -> Match:
    """The first rule that fits a hello from [device_id] naming [area_id] (an area HA has, else None)."""
    if (known := panel_of(device_id, panels)) is not None:
        return Match(KNOWN, known)
    if area_id is None:
        return Match(WAITS)
    if replaces is not False:
        offline = sorted(d for d in panels if area_of(d) == area_id and not connected(d))
        if len(offline) == 1:
            return Match(TAKES_PLACE, offline[0])
    return Match(NEW)


def at_once(found: Match) -> bool:
    """Whether [found] is approved without an approval in HA: rules 1 to 3, on any login."""
    return found.rule != WAITS
