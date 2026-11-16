"""What the installed Microsoft Family Safety integration can do for Hearth, found now (its services' schemas and its
entities' attributes), and what that leaves Hearth doing with less. Shown with the integration's health on Hearth's
page (panel.py), so an adult can see what's reduced.

New families get the integration's released version (upstream's); a Family Safety that carries more (a fork, a later
release) is used for what it has:

- today_only: set_screentime_intervals changes today's allowed hours only (Family Safety puts the day back at
  midnight). Without it Hearth changes the weekday's setting and puts it back itself after midnight (native_sync.py).
- hold_attributes: its Allowed Now sensors and lock switches say whose a lock or extra time is (hold, override_until,
  allow_until). Without them Hearth tells its own from a parent's by what it asked for (enforce.fs_derived_hold).
- allowed_now: Allowed Now sensors with the override in force (what Hearth reads either way).
- lock_until: lock_platform takes an end. Without it Hearth's locks last whole hours (to just after midnight).
- xbox_extra_time, windows_extra_time, cancel_extra_time: add_time_bonus (Xbox, Windows) and cancel_time_bonus.
- pause_apps: pause_app and resume_app (single Xbox and Windows apps).
- request_events, pending_requests: it fires its own request events (a fork's), or Hearth reads requests from its
  Pending Requests sensors (fs_requests.py).
"""

from __future__ import annotations

from typing import Any

from homeassistant.core import HomeAssistant

from .enforce import FS_DOMAIN, fs_accepts, next_midnight
from .fs_requests import EVENTS_SEEN

# A child's entity, for asking a schema whether it takes a call (nothing is called)
_PROBE = {"entity_id": "sensor.hearth_probe"}
_WINDOW = {"start_hour": 7, "end_hour": 22}


def capabilities(hass: HomeAssistant) -> dict[str, Any]:
    """What the installed Family Safety can do, by name (all False when it isn't installed)."""
    has = hass.services.has_service
    installed = bool(hass.config_entries.async_entries(FS_DOMAIN)) or bool(
        hass.services.async_services_for_domain(FS_DOMAIN)
    )
    found = {
        "installed": installed,
        "today_only": fs_accepts(hass, "set_screentime_intervals", {**_PROBE, **_WINDOW, "today_only": True}),
        "weekday_hours": fs_accepts(hass, "set_screentime_intervals", {**_PROBE, **_WINDOW, "day_of_week": 0}),
        "hold_attributes": _any_attribute(hass, "hold"),
        "allowed_now": _any_attribute(hass, "override", ("binary_sensor",)),
        "lock_until": fs_accepts(
            hass, "lock_platform", {**_PROBE, "platform": "Xbox", "until": next_midnight().isoformat()}
        ),
        "xbox_extra_time": has(FS_DOMAIN, "add_time_bonus"),
        "windows_extra_time": fs_accepts(hass, "add_time_bonus", {**_PROBE, "platform": "Windows", "minutes": 30}),
        "cancel_extra_time": has(FS_DOMAIN, "cancel_time_bonus"),
        "pause_apps": has(FS_DOMAIN, "pause_app"),
        # It fired microsoft_family_safety_request / _resolved here (a fork's; kept once seen)
        "request_events": bool(hass.data.get(EVENTS_SEEN)),
        # Pending Requests sensors with their requests (read for new and resolved ones: fs_requests.py)
        "pending_requests": any(
            isinstance(state.attributes.get("requests"), list) and "user_id" in state.attributes
            for state in hass.states.async_all("sensor")
        ),
    }
    if not installed:
        return {key: False for key in found}
    return found


def _any_attribute(hass: HomeAssistant, attribute: str, domains: tuple[str, ...] = ("binary_sensor", "switch")) -> bool:
    """A Family Safety child's entity (one with a user_id and a platform) carries [attribute]."""
    return any(
        attribute in state.attributes and "user_id" in state.attributes and "platform" in state.attributes
        for domain in domains
        for state in hass.states.async_all(domain)
    )


def reduced(found: dict[str, Any]) -> list[str]:
    """What Hearth does with less on this Family Safety, for an adult, one line each; nothing when it has it all."""
    if not found.get("installed"):
        return []
    lines = []
    if not found["today_only"]:
        if found["weekday_hours"]:
            lines.append(
                "Extra time past today's allowed hours changes this weekday's hours; Hearth puts them back after "
                "midnight itself (unless a parent changed them since)."
            )
        else:
            lines.append("Extra time can't move today's allowed hours on Windows or the Xbox.")
    if not found["hold_attributes"]:
        if found["allowed_now"]:
            lines.append(
                "A parent's own lock or extra time is told from Hearth's by what Hearth asked for; a parent's "
                "Windows lock while Hearth holds Windows looks like Hearth's."
            )
        else:
            lines.append("A parent's own lock or extra time in the Family Safety app isn't seen.")
    if not found["lock_until"]:
        lines.append("Hearth's locks last whole hours, so they end up to an hour after midnight.")
    if not found["xbox_extra_time"]:
        lines.append("Hearth's extra time doesn't reach Windows or the Xbox.")
    elif not found["windows_extra_time"]:
        lines.append("Hearth's extra time reaches the Xbox only, not Windows.")
    if not found["cancel_extra_time"]:
        lines.append("Extra time Hearth gave can't be ended early in Family Safety.")
    if not found["pause_apps"]:
        lines.append("Hearth can't pause single Xbox or Windows apps, only lock the whole platform.")
    if not found.get("request_events"):
        if found.get("pending_requests"):
            lines.append(
                "Requests from an Xbox or PC are read from the Pending Requests sensors: one answered in the "
                "Family Safety app closes here a few minutes later."
            )
        else:
            lines.append("Requests for more time made on an Xbox or PC don't reach Hearth.")
    return lines
