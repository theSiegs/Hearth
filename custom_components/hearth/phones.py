"""The adults' phones: where requests for more time, offers and other news for the adults go.

Every adult on Hearth's page gets them on each of their Home Assistant companion apps (a mobile_app device of theirs:
one whose device tracker their person follows, or one registered by their Home Assistant user), unless they're
switched off (CONF_ASK_NOTIFY_OFF). The phone chosen in Configure > Watch for new apps (CONF_ASK_NOTIFY) gets them too,
once. A notify service that isn't there is skipped.

A request's notification opens Hearth's page at that request (/hearth?ask=<id>) when tapped; an adult can have their
Android phones open hearth://ask/<id> instead (CONF_ASK_DEEP_LINK), for an app of their own that handles it. iOS always
gets the page.
"""

from __future__ import annotations

from collections.abc import Mapping
from dataclasses import dataclass
from typing import Any

from homeassistant.core import HomeAssistant
from homeassistant.helpers import entity_registry as er
from homeassistant.util import slugify

from .const import CONF_ROLES

# Options: adults (person entity ids) whose phones don't get requests, and adults whose Android phones open the deep link
CONF_ASK_NOTIFY_OFF = "ask_notify_off"
CONF_ASK_DEEP_LINK = "ask_deep_link"
MOBILE_APP = "mobile_app"
ANDROID = "android"
IOS = "ios"


def page_link(ask_id: str) -> str:
    return f"/hearth?ask={ask_id}"


def deep_link(ask_id: str) -> str:
    return f"hearth://ask/{ask_id}"


@dataclass(frozen=True)
class Phone:
    service: str  # the notify service's name, mobile_app_<device>
    person: str | None  # None: the chosen phone, not found as an adult's
    os: str | None  # android, ios, or None when unknown
    deep_link: bool = False

    def click(self, ask_id: str) -> dict[str, str]:
        """What a tap on a request's notification opens: Android's clickAction, iOS's url."""
        page = page_link(ask_id)
        android = deep_link(ask_id) if self.deep_link else page
        if self.os == IOS:
            return {"url": page}
        if self.os == ANDROID:
            return {"clickAction": android}
        return {"clickAction": android, "url": page}


def _os(entry) -> str | None:
    name = str(entry.data.get("os_name") or "").lower()
    if "android" in name:
        return ANDROID
    if name in ("ios", "ipados", "macos") or "ios" in name:
        return IOS
    return None


def _service(entry) -> str | None:
    name = entry.data.get("device_name")
    return f"mobile_app_{slugify(name)}" if name else None


def person_phones(hass: HomeAssistant, person: str) -> list[tuple[str, str | None]]:
    """A person's companion apps: (notify service name, os), from the device trackers their person follows and the
    apps their Home Assistant user registered."""
    state = hass.states.get(person)
    if state is None:
        return []
    entries = {e.entry_id: e for e in hass.config_entries.async_entries(MOBILE_APP)}
    found: list[str] = []
    registry = er.async_get(hass)
    for tracker in state.attributes.get("device_trackers") or []:
        entity = registry.async_get(tracker)
        if entity is not None and entity.platform == MOBILE_APP and entity.config_entry_id in entries:
            found.append(entity.config_entry_id)
    user_id = state.attributes.get("user_id")
    if user_id:
        found += [e.entry_id for e in entries.values() if e.data.get("user_id") == user_id]
    out: list[tuple[str, str | None]] = []
    for entry_id in dict.fromkeys(found):
        entry = entries[entry_id]
        service = _service(entry)
        if service and all(service != s for s, _ in out):
            out.append((service, _os(entry)))
    return out


def adults(options: Mapping[str, Any]) -> list[str]:
    return sorted(p for p, role in (options.get(CONF_ROLES) or {}).items() if role == "adult")


def phones(hass: HomeAssistant, options: Mapping[str, Any]) -> list[Phone]:
    """Everyone who gets requests, each notify service once, only ones that are there."""
    from .apps import CONF_ASK_NOTIFY

    off = set(options.get(CONF_ASK_NOTIFY_OFF) or [])
    linked = set(options.get(CONF_ASK_DEEP_LINK) or [])
    out: list[Phone] = []
    seen: set[str] = set()
    for person in adults(options):
        if person in off:
            continue
        for service, os in person_phones(hass, person):
            if service not in seen:
                seen.add(service)
                out.append(Phone(service, person, os, person in linked))
    chosen = options.get(CONF_ASK_NOTIFY)
    if chosen and chosen.startswith("notify."):
        service = chosen.split(".", 1)[1]
        if service not in seen:
            seen.add(service)
            entry = next((e for e in hass.config_entries.async_entries(MOBILE_APP) if _service(e) == service), None)
            out.append(Phone(service, None, _os(entry) if entry else None))
    return [p for p in out if hass.services.has_service("notify", p.service)]


def send(
    hass: HomeAssistant,
    options: Mapping[str, Any],
    title: str | None,
    message: str,
    data: dict[str, Any] | None = None,
    ask_id: str | None = None,
) -> list[str]:
    """The same notification on every adult's phone; with [ask_id], a tap opens that request. The services told."""
    told = []
    for phone in phones(hass, options):
        payload: dict[str, Any] = {"message": message}
        if title is not None:
            payload["title"] = title
        extra = {**(data or {}), **(phone.click(ask_id) if ask_id else {})}
        if extra:
            payload["data"] = extra
        hass.async_create_task(hass.services.async_call("notify", phone.service, payload, blocking=False))
        told.append(phone.service)
    return told


def clear(hass: HomeAssistant, options: Mapping[str, Any], tag: str) -> None:
    """Takes the notification with [tag] off every adult's phone."""
    send(hass, options, None, "clear_notification", {"tag": tag})


def page_view(hass: HomeAssistant, options: Mapping[str, Any]) -> dict[str, Any]:
    """For Hearth's page: each adult's phones and whether they get requests."""
    off = set(options.get(CONF_ASK_NOTIFY_OFF) or [])
    linked = set(options.get(CONF_ASK_DEEP_LINK) or [])
    return {
        person: {
            "phones": [
                {"service": f"notify.{s}", "os": os, "there": hass.services.has_service("notify", s)}
                for s, os in person_phones(hass, person)
            ],
            "on": person not in off,
            "deep_link": person in linked,
        }
        for person in adults(options)
    }
