"""Download diagnostics: the household's settings, each kid's state now and the last 200 activity records.

Tokens, PINs and their hashes, names, Family Link child ids, emails, Wi-Fi names, the push server, errors (free text
that may quote a device's name) and the like are redacted (async_redact_data, and any string that is a stored parent
PIN). Each person is replaced by person_1, person_2, ... everywhere, keys included: their entity id, and any id or
service name made from their entity id, their name or first name, or those with an "s" (a possessive: alexs_phone).
"""

from __future__ import annotations

import re
from typing import Any

from homeassistant.components.diagnostics import async_redact_data
from homeassistant.config_entries import ConfigEntry
from homeassistant.core import HomeAssistant
from homeassistant.util import slugify

from . import parent_pin

REDACTED = "**REDACTED**"
TO_REDACT = {
    "token", "access_token", "refresh_token", "secret", "password", "pin", "pins", "pin_hash", "hash", "salt",
    "parent_pins", "push_server", "push_topic", "server", "topic",
    "name", "names", "friendly_name", "person_name", "user_name", "title", "by", "reason", "detail", "text",
    "adult_text", "limit_text", "child_id", "account_id", "user_id", "email", "emails", "ssid", "ssids", "wifi",
    "address", "latitude", "longitude", "zone", "places", "note", "message", "error", "errors", "device_name",
}
RECORDS = 200
# An id, entity id or service name (no spaces)
_ID = re.compile(r"^[A-Za-z0-9_.:@/-]+$")


def _slugs(hass: HomeAssistant, person: str) -> set[str]:
    """What a person's ids may be made from: the entity's object id, their name and each word of it (slugs)."""
    found = {person.split(".", 1)[-1]}
    state = hass.states.get(person)
    name = str(state.name) if state is not None else ""
    if name:
        found.add(slugify(name))
        # Each word of it too (a first name, a family name: rivera_sam_tablet)
        found |= {slugify(word) for word in name.split()}
    return {s for s in found if s and len(s) > 1}


def _alias_str(value: str, people: dict[str, str], slugs: dict[str, set[str]]) -> str:
    if value in people:
        return people[value]
    if parent_pin.STORED.match(value):
        return REDACTED
    if _ID.match(value):
        for person, alias in people.items():
            for slug in slugs[person]:
                # As a whole word of the id, or with a possessive s (alexs_phone)
                value = re.sub(rf"(?<![a-z0-9]){re.escape(slug)}s?(?![a-z0-9])", alias, value, flags=re.IGNORECASE)
    return value


def _alias(value: Any, people: dict[str, str], slugs: dict[str, set[str]]) -> Any:
    if isinstance(value, dict):
        return {
            _alias_str(k, people, slugs) if isinstance(k, str) else k: _alias(v, people, slugs) for k, v in value.items()
        }
    if isinstance(value, list):
        return [_alias(v, people, slugs) for v in value]
    if isinstance(value, str):
        return _alias_str(value, people, slugs)
    return value


async def async_get_config_entry_diagnostics(hass: HomeAssistant, entry: ConfigEntry) -> dict[str, Any]:
    hub = entry.runtime_data
    household = hub.household
    persons = sorted({s.entity_id for s in hass.states.async_all("person")} | set(household.people()))
    people = {p: f"person_{i}" for i, p in enumerate(persons, 1)}
    slugs = {p: _slugs(hass, p) for p in persons}
    kids = {}
    for person in household.people():
        kids[person] = {
            "time": household.time_view(person),
            "locked": bool(household.days.get(person) and household.days[person].locked),
            "enforcement": household.enforcement.status_of(person),
            "backstop": household.backstop.view(person),
        }
    body = {
        "options": dict(entry.options),
        "kids": kids,
        "activity": household.activity.query(limit=RECORDS),
    }
    return async_redact_data(_alias(async_redact_data(body, TO_REDACT), people, slugs), TO_REDACT)
