"""hearth.notify: a message on Hearth's devices, a person's devices or the whole household's
(docs/home-assistant-integration.md, Pop-ups). Not named notify.py: that's a notify platform's name in Home Assistant.

It goes through attention.py like every other notice, so it reaches people the way Hearth's own notices do: on the
phones, a companion-app notification (phones.py, delivery/companion.py); on the TVs, a notice in the state document of a
TV that shows notices (cap "notices"), which pops it up in its adult profiles. It's announced as a hearth_notice of kind
"notify" too. No buttons in v1.

Targets: Hearth devices (a TV, or a paired phone: its person's companion apps), companion-app devices (that app), people
(each one's companion apps, and an adult's TV profiles), or the household (everyone on Hearth's page, and every TV that
shows notices). Every target is checked before anything is sent: an unknown device, a panel, or a TV whose Hearth
doesn't show notices is refused. Callers are checked as for every hearth service (auth.register_service).
"""

from __future__ import annotations

from datetime import timedelta
import secrets
from typing import TYPE_CHECKING, Any

import voluptuous as vol

from homeassistant.core import HomeAssistant, ServiceCall, ServiceResponse, SupportsResponse, callback
from homeassistant.exceptions import ServiceValidationError
from homeassistant.helpers import config_validation as cv
from homeassistant.helpers import device_registry as dr
from homeassistant.helpers.event import async_call_later
from homeassistant.util import dt as dt_util

from . import phones
from .attention import DEVICES, HOUSEHOLD, NOTICE, PERSON, Attention, Item, attention
from .auth import register_service
from .const import CAP_NOTICES, CONF_PERSON, DOMAIN, KIND_MOBILE, KIND_TV

if TYPE_CHECKING:
    from .hub import HearthHub

SERVICE = "notify"
KEY_PREFIX = "hearth_notify_"
KIND = "notify"
# Without a duration a message stays this long on the TVs (a phone keeps it until it's swiped away)
KEEP = timedelta(days=1)
# A TV that's offline drops it by itself this long after the duration (Home Assistant takes it off at the duration)
EXPIRY_GRACE = timedelta(minutes=1)
MAX_DURATION = 24 * 60 * 60
MAX_TITLE = 200
MAX_MESSAGE = 1000

SCHEMA = vol.Schema(
    {
        vol.Optional("devices"): vol.All(cv.ensure_list, [cv.string]),
        vol.Optional("people"): vol.All(cv.ensure_list, [cv.entity_domain("person")]),
        vol.Optional("household", default=False): cv.boolean,
        vol.Optional("title"): vol.All(cv.string, vol.Length(max=MAX_TITLE)),
        vol.Required("message"): vol.All(cv.string, vol.Length(min=1, max=MAX_MESSAGE)),
        vol.Optional("duration"): vol.All(vol.Coerce(int), vol.Range(min=1, max=MAX_DURATION)),
    }
)


def _hub(hass: HomeAssistant) -> HearthHub:
    entries = hass.config_entries.async_loaded_entries(DOMAIN)
    if not entries:
        raise ServiceValidationError("Hearth isn't set up")
    return entries[0].runtime_data


def _devices(hass: HomeAssistant, hub: HearthHub, given: list[str]) -> tuple[list[phones.Phone], list[str]]:
    """The phones and TVs (Hearth device ids) of [given]: Hearth device ids, or Home Assistant device ids (a device
    selector's) of a Hearth device or a companion app. Raises for one that can't be told."""
    registry = dr.async_get(hass)
    apps = {e.entry_id: e for e in hass.config_entries.async_entries(phones.MOBILE_APP)}
    found: list[phones.Phone] = []
    tvs: list[str] = []
    for one in given:
        device_id = one if one in hub.devices else None
        if device_id is None:
            device = registry.async_get(one)
            if device is None:
                raise ServiceValidationError(f"{one} isn't a device")
            device_id = next(
                (ident for domain, ident in device.identifiers if domain == DOMAIN and ident in hub.devices), None
            )
            if device_id is None:
                # A companion app: its own notify service
                entry = next((apps[e] for e in device.config_entries if e in apps), None)
                service = phones.service_of(entry) if entry is not None else None
                if service is None:
                    raise ServiceValidationError(f"{device.name_by_user or device.name} isn't a Hearth device or a phone")
                found.append(phones.Phone(service, None, phones._os(entry)))
                continue
        name = hub.devices[device_id].get("name") or device_id
        kind = hub.kind(device_id)
        if kind == KIND_TV:
            if not hub.has_cap(device_id, CAP_NOTICES):
                raise ServiceValidationError(f"{name} can't show messages: its Hearth doesn't show notices")
            tvs.append(device_id)
        elif kind == KIND_MOBILE:
            # A paired phone has no message channel of its own: its person's companion apps
            person = hub.devices[device_id].get(CONF_PERSON)
            if not person:
                raise ServiceValidationError(f"{name} isn't anyone's yet: choose whose phone it is on Hearth's page")
            found += [phones.Phone(service, person, os) for service, os in phones.person_phones(hass, person)]
        else:
            raise ServiceValidationError(f"{name} isn't a TV or a phone")
    unique: dict[str, phones.Phone] = {}
    for phone in found:
        unique.setdefault(phone.service, phone)
    return list(unique.values()), list(dict.fromkeys(tvs))


def _tvs_showing(hub: HearthHub, item: Item) -> list[str]:
    """The TVs whose state document would have [item] (a TV that shows notices)."""
    if not item.tv:
        return []
    return sorted(
        device_id
        for device_id in hub.devices
        if hub.kind(device_id) == KIND_TV
        and hub.has_cap(device_id, CAP_NOTICES)
        and Attention.on_tv(
            item, {p for p in hub.household.device_profile_people(device_id).values() if p}, device_id
        )
    )


def async_register_service(hass: HomeAssistant) -> None:
    """hearth.notify {devices, people, household, title, message, duration}: answers the keys of the items sent, the
    notify services told and the TVs that show it."""

    @callback
    def notify(call: ServiceCall) -> ServiceResponse:
        hub = _hub(hass)
        devices = call.data.get("devices") or []
        people = list(dict.fromkeys(call.data.get("people") or []))
        household = call.data["household"]
        if not (devices or people or household):
            raise ServiceValidationError("Say who to tell: devices, people or the household")
        for person in people:
            if hass.states.get(person) is None:
                raise ServiceValidationError(f"{person} isn't a person")
        adults = set(phones.adults(hub.entry.options))
        duration = call.data.get("duration")
        expires = dt_util.utcnow() + (timedelta(seconds=duration) + EXPIRY_GRACE if duration else KEEP)
        common: dict[str, Any] = {
            "title": call.data.get("title"),
            "urgency": NOTICE,
            "kind": KIND,
            "expires": expires,
        }
        base = f"{KEY_PREFIX}{secrets.token_hex(6)}"
        message = call.data["message"]
        items: list[Item] = []
        if household:
            items.append(Item(f"{base}_household", message, audience=HOUSEHOLD, tv=True, **common))
        for n, person in enumerate(people):
            # A TV shows notices in its adult profiles only
            items.append(Item(f"{base}_p{n}", message, audience=f"{PERSON}{person}", tv=person in adults, **common))
        if devices:
            to, tvs = _devices(hass, hub, devices)
            items.append(
                Item(
                    f"{base}_devices", message, audience=DEVICES, to=tuple(to), tvs=frozenset(tvs), phone=bool(to),
                    tv=bool(tvs), **common,
                )
            )
        place = attention(hass)
        told = sorted({p.service for item in items if item.phone for p in place.item_targets(item)})
        shown = sorted({tv for item in items for tv in _tvs_showing(hub, item)})
        if not told and not shown:
            raise ServiceValidationError("Nobody to tell: no companion app or TV that shows notices was found for them")
        for item in items:
            place.notify(item)
        if duration:
            keys = [item.key for item in items]

            @callback
            def take_off(_now) -> None:
                current = attention(hass)
                for key in keys:
                    current.clear(key)

            async_call_later(hass, duration, take_off)
        return {"keys": [item.key for item in items], "phones": [f"notify.{s}" for s in told], "tvs": shown}

    register_service(
        hass, DOMAIN, SERVICE, notify, schema=SCHEMA, supports_response=SupportsResponse.OPTIONAL
    )
