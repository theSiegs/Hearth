"""The client app a device runs, and the checks it reports (contract 3, docs/contracts/device-api.md).

A device says which app it is in `client` ({"id", "version", "contract", "companions"}), in its pair body and in each
status post. `id` is the app's Android package (or a reverse-DNS id for another kind of client); `companions` are at most
MAX_COMPANIONS more packages of the same app family, each `<id>.` plus a suffix, so a client can't name anything outside
its own family. The id and companions are locked when an adult approves the pairing (the adult sees them there): they
route the client's settings (client_settings.py) and keep the client's own packages from being paused for the device's
person (enforce.py). A later status that names another id changes neither: Hearth raises its own check until the
device pairs again.

`checks` ([{"id", "ok", "label"}], at most MAX_CHECKS) are the device's own health checks, shown as given. Hearth knows
none of their ids; it only tells (hearth_device_check_failed) when one turns false.
"""

from __future__ import annotations

import re
from typing import Any

from .status import number, text

MAX_CLIENT_ID = 128
MAX_COMPANIONS = 4
MAX_CHECKS = 10
MAX_CHECK_LABEL = 40
# A reverse-DNS id: two or more dot-separated parts of letters, digits and underscores (an Android package)
_CLIENT_ID = re.compile(r"^[A-Za-z][A-Za-z0-9_]*(\.[A-Za-z0-9_]+)+$")
# A build of the app with a suffix (`<app>.debug`) may name its companions with the same suffix at the end
# (`<app>.phone.debug`): the suffix family, for these suffixes only
BUILD_SUFFIXES = ("debug", "nightly")
_CHECK_ID = re.compile(r"^[a-z0-9_]{1,32}$")
# Checks Hearth adds itself; a device's own with this prefix are dropped
HEARTH_CHECK_PREFIX = "hearth_"
CHECK_CLIENT = "hearth_client"
# The device posted a status for another day than Home Assistant's (its clock moved): its counts stay as they were
CHECK_CLOCK = "hearth_clock"


def client_id(value: Any) -> str | None:
    """[value] when it's a client id (reverse-DNS, at most MAX_CLIENT_ID long); else None."""
    if not isinstance(value, str) or len(value) > MAX_CLIENT_ID or not _CLIENT_ID.match(value):
        return None
    return value


def in_family(client: str, companion: str) -> bool:
    """[companion] is in [client]'s own family: `<client>.` plus a suffix, or, for a build id ending in one of
    BUILD_SUFFIXES (`<app>.debug`), `<app>.` plus a part plus that same suffix (`<app>.phone.debug`)."""
    if companion.startswith(client + "."):
        return True
    base, _, suffix = client.rpartition(".")
    if suffix not in BUILD_SUFFIXES or not base:
        return False
    middle = companion[len(base) + 1:-(len(suffix) + 1)] if companion.endswith("." + suffix) else ""
    return companion.startswith(base + ".") and bool(middle) and client_id(base + "." + middle) is not None


def clean_client(raw: Any) -> dict[str, Any] | None:
    """{"id", "version", "contract", "companions"} from a device's `client`; None when it's absent or not valid (no
    id, a bad id, more than MAX_COMPANIONS companions, or a companion outside the id's family)."""
    if not isinstance(raw, dict):
        return None
    found = client_id(raw.get("id"))
    if found is None:
        return None
    companions = raw.get("companions", [])
    if companions is None:
        companions = []
    if not isinstance(companions, list) or len(companions) > MAX_COMPANIONS:
        return None
    kept: list[str] = []
    for companion in companions:
        if client_id(companion) is None or not in_family(found, companion):
            return None
        if companion not in kept:
            kept.append(companion)
    return {
        "id": found,
        "version": text(raw.get("version"), 32),
        "contract": number(raw.get("contract"), 0, 1000),
        "companions": kept,
    }


def locked(client: dict[str, Any] | None) -> dict[str, Any] | None:
    """What's kept of a client at pairing: its id and companions."""
    if not client:
        return None
    return {"id": client["id"], "companions": list(client.get("companions") or [])}


def clean_checks(raw: Any) -> list[dict[str, Any]] | None:
    """[{"id", "ok", "label"}], at most MAX_CHECKS, each id once; None when the device sent none (not a list)."""
    if not isinstance(raw, list):
        return None
    out: list[dict[str, Any]] = []
    seen: set[str] = set()
    for item in raw[:MAX_CHECKS]:
        if not isinstance(item, dict):
            continue
        check_id, ok = item.get("id"), item.get("ok")
        if (
            not isinstance(check_id, str)
            or not _CHECK_ID.match(check_id)
            or check_id.startswith(HEARTH_CHECK_PREFIX)
            or check_id in seen
            or not isinstance(ok, bool)
        ):
            continue
        seen.add(check_id)
        out.append({"id": check_id, "ok": ok, "label": text(item.get("label"), MAX_CHECK_LABEL) or check_id})
    return out


def client_matches(device: dict[str, Any], status: dict[str, Any] | None) -> bool | None:
    """Whether the client a device last reported is the one locked at pairing: None when either is missing (nothing
    to compare), False for another id."""
    pinned = (device or {}).get("client")
    reported = (status or {}).get("client")
    if not pinned or not reported:
        return None
    return reported.get("id") == pinned.get("id")


def checks_of(device: dict[str, Any], status: dict[str, Any] | None) -> list[dict[str, Any]]:
    """What a device's row shows: its own checks as given, then Hearth's client check when the client it reports isn't
    the one it paired with, and its clock check when its last status was for another day than Hearth's."""
    found = list((status or {}).get("checks") or [])
    if client_matches(device, status) is False:
        found.append({"id": CHECK_CLIENT, "ok": False, "label": "App differs from pairing"})
    if (status or {}).get("clock_off"):
        found.append({"id": CHECK_CLOCK, "ok": False, "label": "Its date differs from Home Assistant's"})
    return found


def exempt_packages(device: dict[str, Any]) -> list[str]:
    """The packages the client locked at pairing keeps from being paused for the device's person: its id and its
    companions (household.py takes out any the household or the catalog put in a pool)."""
    pinned = (device or {}).get("client")
    if not pinned or not pinned.get("id"):
        return []
    return [pinned["id"], *(pinned.get("companions") or [])]
