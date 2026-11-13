"""A person's devices as an adult's app can name them (docs/home-assistant-integration.md, Household summary): Hearth's
own TVs and phones, Family Link's devices, Family Safety's platforms and a Nintendo Switch, each with a stable id.

    hearth:<device_id>     a Hearth TV or phone        holds one group on that device alone (groups: true)
    fl:<FL device id>      a Family Link device        Family Link's app pauses are the child's, every device's
    fs:xbox, fs:windows    a Family Safety platform    Family Safety's app blocks are the account's (any platform
                                                       their Family Safety reports, held by Hearth or not)
    nintendo:<entity_id>   a Switch (Hearth's Nintendo enforcer entity)

The ids are what hearth.add_bonus and hearth.allow take as `device`, and what devices_today names.
"""

from __future__ import annotations

from typing import TYPE_CHECKING, Any

from homeassistant.helpers import entity_registry as er

from . import family_link as fl
from .const import CONF_KIND, CONF_PERSON, KIND_TV
from .enforce import FAMILY_SAFETY, NINTENDO

if TYPE_CHECKING:
    from .household import Household

HEARTH = "hearth"
VIA_FAMILY_LINK = "family_link"
VIA_FAMILY_SAFETY = "family_safety"
VIA_NINTENDO = "nintendo"


def targets_of(household: Household, person: str) -> list[dict[str, Any]]:
    """[{id, name, kind (tv | phone | xbox | windows | switch), via, groups}], Hearth's own first."""
    hass = household.hass
    found: list[dict[str, Any]] = []
    for device_id, device in sorted(household.hub.devices.items()):
        tv = device.get(CONF_KIND) == KIND_TV
        mine = person in household.device_profile_people(device_id).values() if tv else device.get(CONF_PERSON) == person
        if mine:
            found.append(
                {
                    "id": f"{HEARTH}:{device_id}",
                    "name": _shown(device.get("name") or device_id, tv),
                    "kind": "tv" if tv else "phone",
                    "via": HEARTH,
                    "groups": True,
                }
            )
    if (child := household.family_link_child(person)) is not None:
        for state in fl.devices(hass, child):
            device_id = str(state.attributes.get("device_id"))
            found.append(
                {
                    "id": f"fl:{device_id}",
                    "name": state.attributes.get("device_name") or state.attributes.get("friendly_name") or device_id,
                    "kind": "phone",
                    "via": VIA_FAMILY_LINK,
                    "groups": False,
                }
            )
            # The same handset as a Hearth phone of theirs (by name): one device, shown once
            twin = next(
                (t for t in found if t["via"] == HEARTH and t["kind"] == "phone"
                 and t["name"].casefold() == found[-1]["name"].casefold()),
                None,
            )
            if twin is not None:
                found[-1]["same_as"] = twin["id"]
                twin.setdefault("also", []).append(found[-1]["id"])
    for enforcer in household.enforcement.enforcers:
        if enforcer.person != person:
            continue
        if enforcer.kind == FAMILY_SAFETY:
            from .native_sync import fs_platform_state

            for platform in ("Xbox", "Windows"):
                # A platform Hearth doesn't hold still takes extra time (Microsoft's, and its allowed hours moved)
                if platform in enforcer.platforms or fs_platform_state(hass, enforcer.entity_id, platform) is not None:
                    found.append(
                        {
                            "id": f"fs:{platform.lower()}",
                            "name": platform,
                            "kind": platform.lower(),
                            "via": VIA_FAMILY_SAFETY,
                            "groups": False,
                        }
                    )
        elif enforcer.kind == NINTENDO:
            found.append(
                {
                    "id": f"nintendo:{enforcer.entity_id}",
                    "name": _device_name(household, enforcer.entity_id) or "Switch",
                    "kind": "switch",
                    "via": VIA_NINTENDO,
                    "groups": False,
                }
            )
    return found


# Who sets a device's own limit, as `left_by` says it
LEFT_BY_HEARTH = "hearth"
_LEFT_BY = {VIA_FAMILY_LINK: "google", VIA_FAMILY_SAFETY: "microsoft", VIA_NINTENDO: "nintendo"}


def with_time_left(household: Household, person: str, view: dict[str, Any]) -> list[dict[str, Any]]:
    """The person's targets (view["targets"]) each with the time actually left on it, worked out once for every
    surface (the panel, the TV, Glint):

        left         minutes, the smaller of Hearth's and the device's own limit (null: neither limits it)
        left_by      hearth | google | microsoft | nintendo: whose limit that is (null with left null)
        left_pool    with left_by hearth, the pool that binds there (all, or games on an Xbox or Switch Hearth holds
                     to games)
        locked       nothing runs there now: a lock or pause of theirs, no time left, or the device's own limit or a
                     parent's own lock
        locked_kind  bedtime | school_time | pause | other (a lock), out (no time left), device_limit, parent_lock

    Hearth's limit on a device is All screen time's minutes left, and on an Xbox or Switch also each pool its enforcer
    holds there; extra time on that one device (device_extras) adds to it, or lifts it till its end. The device's own
    is Family Link's daily limit, Microsoft's allowance, or the Switch's own limit, from view["first_party"], unless
    that number is Hearth's own hold."""
    groups = {g["id"]: g for g in view.get("groups") or []}
    first = view.get("first_party") or {}
    extras = view.get("device_extras") or []
    lock = view.get("lock") or {}
    enforced: dict[str, tuple[str, ...]] = {}
    for enforcer in household.enforcement.enforcers:
        if enforcer.person != person:
            continue
        if enforcer.kind == FAMILY_SAFETY:
            for platform in ("xbox", "windows"):
                enforced[f"fs:{platform}"] = enforcer.groups
        elif enforcer.kind == NINTENDO:
            enforced[f"nintendo:{enforcer.entity_id}"] = enforcer.groups
    out = []
    for target in view.get("targets") or []:
        tid = target["id"]
        # Hearth's: All, and the pools held on this device
        hearth: tuple[int, str] | None = None
        for gid in ("all", *(g for g in enforced.get(tid, ()) if g != "all")):
            left = (groups.get(gid) or {}).get("minutes_left")
            if left is not None and (hearth is None or max(0, left) < hearth[0]):
                hearth = (max(0, left), gid)
        for extra in extras:
            if extra.get("target") != tid or extra.get("group") not in (None, "all"):
                continue
            if extra.get("kind") == "allow":
                hearth = None
                break
            if hearth is not None and extra.get("minutes_left"):
                hearth = (hearth[0] + extra["minutes_left"], hearth[1])
        # The device's own
        own, own_blocking, parent_lock = None, False, False
        via = target.get("via")
        row = _own_row(first, target)
        if row is not None and not row.get("held_by_hearth"):
            own = row.get("minutes_left")
            own_blocking = bool(row.get("blocking") or row.get("suspended"))
            parent_lock = bool(row.get("parent_lock"))
        left, by, pool = None, None, None
        if hearth is not None:
            left, by, pool = hearth[0], LEFT_BY_HEARTH, hearth[1]
        if own is not None and (left is None or max(0, own) < left):
            left, by, pool = max(0, own), _LEFT_BY.get(via), None
        if view.get("locked") or view.get("pause"):
            kind = lock.get("kind") or ("pause" if view.get("pause") else "other")
        elif parent_lock:
            kind = "parent_lock"
        elif left == 0:
            kind = "out" if by == LEFT_BY_HEARTH else "device_limit"
        elif own_blocking:
            kind = "device_limit"
        else:
            kind = None
        out.append(
            {**target, "left": left, "left_by": by, "left_pool": pool, "locked": kind is not None, "locked_kind": kind}
        )
    return out


def _own_row(first: dict[str, Any], target: dict[str, Any]) -> dict[str, Any] | None:
    """The first-party row (native_sync.first_party) of a target: its Family Link device, Family Safety platform or
    Switch."""
    via, _, rest = target["id"].partition(":")
    if via == "fl":
        return next((r for r in first.get(VIA_FAMILY_LINK) or [] if str(r.get("device_id")) == rest), None)
    if via == "fs":
        return next((r for r in first.get(VIA_FAMILY_SAFETY) or [] if str(r.get("platform")).lower() == rest), None)
    if via == "nintendo":
        return next((r for r in first.get(VIA_NINTENDO) or [] if r.get("target") == target["id"]), None)
    return None


# A source's integration, for the kind of device it counts
_SOURCE_KINDS = {"xbox": "xbox", "nintendo_parental_controls": "switch", "mobile_app": "phone", "familylink": "phone"}


def kind_of_target(household: Household, target: str) -> str | None:
    """tv, phone, xbox, windows or switch for a target id (or a counted source:<id>), from what it is; None when Hearth
    can't tell (a sensor of another integration)."""
    via, _, rest = target.partition(":")
    if via == HEARTH:
        device = household.hub.devices.get(rest) or {}
        return "tv" if device.get(CONF_KIND) == KIND_TV else "phone"
    if via == "fl":
        return "phone"
    if via == "fs":
        return rest if rest in ("xbox", "windows") else None
    if via == "nintendo":
        return "switch"
    if via == "source":
        source = next((s for s in household.sources if s.id == rest), None)
        if source is None:
            return None
        if source.phone_app:
            return "phone"
        entry = er.async_get(household.hass).async_get(source.entity_id)
        return _SOURCE_KINDS.get(entry.platform) if entry is not None else None
    return None


def _shown(name: str, tv: bool) -> str:
    """A TV's name as shown: "Kitchen" is "Kitchen TV"; a name that says TV already stays."""
    if tv and "tv" not in name.casefold().replace("-", " ").split():
        return f"{name} TV"
    return name


def _device_name(household: Household, entity_id: str) -> str | None:
    from homeassistant.helpers import device_registry as dr

    entry = er.async_get(household.hass).async_get(entity_id)
    if entry is None or entry.device_id is None:
        return None
    device = dr.async_get(household.hass).async_get(entry.device_id)
    return (device.name_by_user or device.name) if device else None


def target_of_counted(household: Household, person: str, key: str) -> tuple[str, str]:
    """A counted device of the person's day (a Hearth device id, or source:<id>) as (target id, name): a Family Link
    device's own Daily screen time sensor is fl:<device>, a source on the Switch's device nintendo:<entity>, any other
    source source:<id>."""
    if key in household.hub.devices:
        device = household.hub.devices[key]
        return f"{HEARTH}:{key}", _shown(device.get("name") or key, device.get(CONF_KIND) == KIND_TV)
    source = next((s for s in household.sources if f"source:{s.id}" == key), None)
    if source is None:
        return key, key
    state = household.hass.states.get(source.entity_id)
    if state is not None and state.attributes.get("device_id") and state.attributes.get("child_id") is not None:
        return f"fl:{state.attributes['device_id']}", source.name
    registry = er.async_get(household.hass)
    entry = registry.async_get(source.entity_id)
    if entry is not None and entry.device_id:
        for enforcer in household.enforcement.enforcers:
            if enforcer.person == person and enforcer.kind == NINTENDO:
                other = registry.async_get(enforcer.entity_id)
                if other is not None and other.device_id == entry.device_id:
                    return f"nintendo:{enforcer.entity_id}", source.name
    return key, source.name
