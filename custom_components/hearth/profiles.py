"""Which person a TV profile is: the keys the options map to people.

A TV names a profile by its own key ("user:10", "user:0:sam"), but the serial in it is that TV's: the same Google TV
profile is user 10 on one TV and user 12 on the next. So the options never map a bare key. They map either

- a profile's household ref ("name:sam-lee"), which every TV reports beside its key (the profile's name in Google TV's
  chooser, the same on every TV): one choice covers the profile on all the TVs, or
- one TV's key, qualified by the device ("<device_id>/user:10"): for a TV whose Hearth is too old to report refs, or
  a profile that TV hasn't learned the name of.

A bare "user:10" (what the options held before) is ambiguous and matches nothing: Home Assistant raises a repair
issue until it's re-picked.
"""

from __future__ import annotations

import re

REF_PREFIX = "name:"
# The repair issue while the options still map bare keys
ISSUE_PROFILE_KEYS = "tv_profile_keys"
_REF = re.compile(r"^name:[\w.-]{1,64}$")
_LOCAL = re.compile(r"^user:\d+(:[\w.-]{1,64})?$")
_DEVICE_KEY = re.compile(r"^[A-Za-z0-9_-]{8,64}/user:\d+(:[\w.-]{1,64})?$")

# An option key, as the Configure menu and Hearth's page accept it (the legacy bare key too, so a page that still
# lists one can save; it matches nothing)
OPTION_KEY = r"^(name:[\w.-]{1,64}|[A-Za-z0-9_-]{8,64}/user:\d+(:[\w.-]{1,64})?|user:\d+(:[\w.-]{1,64})?)$"


def is_ref(value: str | None) -> bool:
    return bool(value) and bool(_REF.match(value))


def is_local_key(value: str | None) -> bool:
    """A TV's own profile key ("user:10", "user:0:sam"); in the options, the ambiguous legacy form."""
    return bool(value) and bool(_LOCAL.match(value))


def is_tv_key(value: str | None) -> bool:
    return bool(value) and bool(_DEVICE_KEY.match(value))


def tv_key(device_id: str, profile_id: str) -> str:
    """One TV's profile, for the options: "<device_id>/user:10"."""
    return f"{device_id}/{profile_id}"


def split_tv_key(key: str) -> tuple[str, str] | None:
    """(device_id, profile_id) of a TV key, else None."""
    if not is_tv_key(key):
        return None
    device_id, profile_id = key.split("/", 1)
    return device_id, profile_id


def legacy_keys(mapping: dict[str, str]) -> list[str]:
    """The options' bare TV keys ("user:10"): which TV's they were is unknown, so they match nothing."""
    return sorted(key for key in mapping if is_local_key(key))
