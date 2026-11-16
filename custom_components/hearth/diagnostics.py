"""Download diagnostics: the household's settings, each kid's state now and the last 200 activity records.

Tokens, PINs, names, Family Link child ids, emails, Wi-Fi names and the like are redacted (async_redact_data), and
each person's entity id (which carries a name) is replaced by person_1, person_2, ... everywhere, keys included.
"""

from __future__ import annotations

import re
from typing import Any

from homeassistant.components.diagnostics import async_redact_data
from homeassistant.config_entries import ConfigEntry
from homeassistant.core import HomeAssistant

TO_REDACT = {
    "token", "access_token", "refresh_token", "secret", "password", "pin", "pins", "pin_hash", "hash", "salt",
    "name", "names", "friendly_name", "person_name", "user_name", "title", "by", "reason", "detail", "text",
    "adult_text", "child_id", "account_id", "user_id", "email", "emails", "ssid", "ssids", "wifi", "server", "topic",
    "push_topic", "address", "latitude", "longitude", "zone", "places", "note", "message",
}
RECORDS = 200


_ENTITY_ID = re.compile(r"^[a-z_]+\.[a-z0-9_]+$")


def _alias_str(value: str, people: dict[str, str]) -> str:
    if value in people:
        return people[value]
    if _ENTITY_ID.match(value):
        # Another entity named after a person (sensor.sam_family_link_daily_screen_time): the name goes too
        for person, alias in people.items():
            slug = person.split(".", 1)[-1]
            if slug and re.search(rf"(^|[._]){re.escape(slug)}(_|$)", value):
                value = re.sub(rf"(^|[._]){re.escape(slug)}(?=_|$)", rf"\g<1>{alias}", value)
    return value


def _alias(value: Any, people: dict[str, str]) -> Any:
    if isinstance(value, dict):
        return {_alias_str(k, people) if isinstance(k, str) else k: _alias(v, people) for k, v in value.items()}
    if isinstance(value, list):
        return [_alias(v, people) for v in value]
    if isinstance(value, str):
        return _alias_str(value, people)
    return value


async def async_get_config_entry_diagnostics(hass: HomeAssistant, entry: ConfigEntry) -> dict[str, Any]:
    hub = entry.runtime_data
    household = hub.household
    persons = sorted({s.entity_id for s in hass.states.async_all("person")} | set(household.people()))
    people = {p: f"person_{i}" for i, p in enumerate(persons, 1)}
    kids = {}
    for person in household.people():
        view = household.time_view(person)
        kids[person] = {
            "time": view,
            "locked": bool(household.days.get(person) and household.days[person].locked),
            "enforcement": household.enforcement.status_of(person),
            "backstop": household.backstop.view(person),
        }
    body = {
        "options": dict(entry.options),
        "kids": kids,
        "activity": household.activity.query(limit=RECORDS),
    }
    return async_redact_data(_alias(body, people), TO_REDACT)
