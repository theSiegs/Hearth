"""A person's devices as an adult's app can name them (docs/home-assistant-integration.md, Household summary): Hearth's
own TVs and phones, Family Link's devices, Family Safety's platforms and a Nintendo Switch, each with a stable id.

    hearth:<device_id>     a Hearth TV or phone        holds one group on that device alone (groups: true)
    fl:<FL device id>      a Family Link device        Family Link's app pauses are the child's, every device's
    fs:xbox, fs:windows    a Family Safety platform    Family Safety's app blocks are the account's
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
            for platform in enforcer.platforms:
                if platform in ("Xbox", "Windows"):
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
