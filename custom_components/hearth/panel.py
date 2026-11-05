"""Hearth's own page in Home Assistant's sidebar (frontend/hearth-panel.js) and the WebSocket commands it uses.

The page shows the household (websocket.py's summary) and sets everything the Configure menu does, in one place: who's
a kid and who's an adult, devices waiting to pair, TV profiles, screen time sources, groups, budgets, locks, other
parental controls, school days and parent PINs. Administrators only. Settings go to the entry's options as the
Configure menu writes them (the entry reloads); budgets and extra time go to the day's limits, as the services do.
"""

from __future__ import annotations

from pathlib import Path
from typing import Any

import voluptuous as vol

from homeassistant.components import frontend, panel_custom, persistent_notification, websocket_api
from homeassistant.components.http import StaticPathConfig
from homeassistant.core import HomeAssistant, callback
from homeassistant.helpers import config_validation as cv
from homeassistant.helpers import entity_registry as er

from .apps import CONF_APP_WATCH, CONF_ASK_NOTIFY
from .const import (
    CONF_GROUP_APPS,
    CONF_GROUPS,
    CONF_KIND,
    CONF_LOCKS,
    CONF_OUTSIDE_ALL,
    CONF_PERSON,
    CONF_PROFILES,
    CONF_ROLES,
    CONF_TILE_EXCHANGE,
    DOMAIN,
    KIND_MOBILE,
)
from .counting import ALL
from .enforce import CONF_ENFORCE, FAMILY_LINK, FAMILY_SAFETY, NINTENDO, NINTENDO_DOMAIN, PLATFORMS
from .limits import BUILTIN_GROUPS, OTHER_DAY, SCHOOL_DAY, slug
from .notifications import pairing_notification_id
from .schooldays import CONF_SCHOOL_DAYS
from .sources import CONF_SOURCES, CONF_TITLES
from . import parent_pin

URL_PATH = "hearth"
STATIC_URL = "/hearth_static"
FRONTEND = Path(__file__).parent / "frontend"
ROLES = ("kid", "adult")

# Integrations whose entities Hearth knows how to read or hold, offered first on the page
SCREEN_TIME_PLATFORMS = ("familylink", "microsoft_family_safety", NINTENDO_DOMAIN, "xbox")


def _hub(hass: HomeAssistant):
    entries = hass.config_entries.async_loaded_entries(DOMAIN)
    return entries[0].runtime_data if entries else None


async def async_register_panel(hass: HomeAssistant) -> None:
    """The sidebar entry, and the page's script (its version in the URL, so a new one isn't cached). Not without
    Home Assistant's frontend (a test, or a headless install): the WebSocket commands still work."""
    if "frontend" not in hass.config.components or hass.data.get(f"{DOMAIN}_panel"):
        return
    script = FRONTEND / "hearth-panel.js"
    version = int(script.stat().st_mtime) if script.exists() else 0
    if not hass.data.get(f"{DOMAIN}_static"):
        await hass.http.async_register_static_paths([StaticPathConfig(STATIC_URL, str(FRONTEND), False)])
        hass.data[f"{DOMAIN}_static"] = True
    await panel_custom.async_register_panel(
        hass,
        frontend_url_path=URL_PATH,
        webcomponent_name="hearth-panel",
        module_url=f"{STATIC_URL}/hearth-panel.js?v={version}",
        sidebar_title="Hearth",
        sidebar_icon="mdi:fireplace",
        require_admin=True,
        config={},
    )
    hass.data[f"{DOMAIN}_panel"] = True


@callback
def async_remove_panel(hass: HomeAssistant) -> None:
    if "frontend" in hass.config.components:
        frontend.async_remove_panel(hass, URL_PATH, warn_if_unknown=False)
    hass.data.pop(f"{DOMAIN}_panel", None)


def _entity_choices(hass: HomeAssistant) -> dict[str, list[dict[str, Any]]]:
    """Entities the page offers for sources, locks and other parental controls, by what they're likely for."""
    registry = er.async_get(hass)
    out: dict[str, list[dict[str, Any]]] = {"screen_time": [], "locks": [], "family_link": [], "family_safety": []}
    out["nintendo"] = []
    out["app_lists"] = []
    for entry in registry.entities.values():
        if entry.disabled_by is not None:
            continue
        state = hass.states.get(entry.entity_id)
        name = state.name if state else (entry.name or entry.original_name or entry.entity_id)
        item = {"entity_id": entry.entity_id, "name": name, "platform": entry.platform}
        eid = entry.entity_id
        unit = state.attributes.get("unit_of_measurement") if state else None
        if entry.domain == "sensor" and (
            entry.platform in SCREEN_TIME_PLATFORMS or (state and state.attributes.get("device_class") == "duration")
        ):
            if unit in ("s", "min", "h", "d") or "screen" in eid or "playing" in eid:
                out["screen_time"].append(item)
        if entry.domain in ("binary_sensor", "switch", "input_boolean") and (
            "bedtime" in eid or "school_time" in eid or "downtime" in eid
        ):
            out["locks"].append(item)
        if entry.platform == "familylink":
            out["family_link"].append(item)
            if entry.domain == "sensor" and ("allowed" in eid or "apps" in eid):
                out["app_lists"].append(item)
        if entry.platform == "microsoft_family_safety" and entry.domain == "sensor":
            out["family_safety"].append(item)
        if entry.platform == NINTENDO_DOMAIN and entry.domain == "number":
            out["nintendo"].append(item)
    for found in out.values():
        found.sort(key=lambda i: i["name"].lower())
    return out


def config_document(hass: HomeAssistant, hub) -> dict[str, Any]:
    """Everything the page sets, as it's set now."""
    household = hub.household
    options = hub.entry.options
    persons = sorted(
        ({"id": s.entity_id, "name": s.name} for s in hass.states.async_all("person")), key=lambda p: p["name"].lower()
    )
    roles: dict[str, str] = dict(options.get(CONF_ROLES, {}))
    kids = [p for p, r in roles.items() if r == "kid"]
    budgets = {
        person: {
            group.id: {
                "school": household.limits.budget(person, group.id, SCHOOL_DAY),
                "other": household.limits.budget(person, group.id, OTHER_DAY),
            }
            for group in household.groups
        }
        for person in sorted(set(kids) | set(household.people()))
    }
    membership = household.membership()
    groups = [
        {
            "id": g.id,
            "name": g.name,
            "builtin": g.builtin,
            "in_all": g.in_all,
            "apps": [] if g.id == ALL else household._group_apps(g, membership),
            "added_apps": list(options.get(CONF_GROUP_APPS, {}).get(g.id, [])),
        }
        for g in household.groups
    ]
    devices = [
        {
            "id": device_id,
            "name": device.get("name"),
            "kind": device.get(CONF_KIND),
            "person": device.get(CONF_PERSON),
            "connected": hub.connected(device_id),
        }
        for device_id, device in sorted(hub.devices.items())
    ]
    pairings = [
        {"pairing_id": p.pairing_id, "name": p.name, "kind": p.kind, "code": p.code, "expires": p.expires.isoformat()}
        for p in hub.pending_pairings()
    ]
    return {
        "title": hub.entry.title,
        "persons": persons,
        "roles": roles,
        "profiles": dict(options.get(CONF_PROFILES, {})),
        "seen_profiles": household.seen_profiles(),
        "devices": devices,
        "pairings": pairings,
        "groups": groups,
        "builtin_groups": [g.id for g in BUILTIN_GROUPS],
        "budgets": budgets,
        "sources": list(options.get(CONF_SOURCES, [])),
        "titles": list(options.get(CONF_TITLES, [])),
        "locks": list(options.get(CONF_LOCKS, [])),
        "enforce": list(options.get(CONF_ENFORCE, [])),
        "platforms": list(PLATFORMS),
        "outside_all": list(options.get(CONF_OUTSIDE_ALL, [])),
        "tile_exchange": list(options.get(CONF_TILE_EXCHANGE, [])),
        "parent_pins": sorted(parent_pin.stored_pins(options)),
        "school_days": dict(options.get(CONF_SCHOOL_DAYS) or {}),
        "app_watch": list(options.get(CONF_APP_WATCH, [])),
        "ask_notify": options.get(CONF_ASK_NOTIFY),
        "notify_services": sorted(
            f"notify.{name}" for name in hass.services.async_services().get("notify", {}) if name.startswith("mobile_app_")
        ),
        "known_apps": household.known_apps(),
        "choices": _entity_choices(hass),
    }


# What the page may write to the options, each checked as the Configure menu would leave it
_PERSON = cv.entity_domain("person")
_ID = vol.All(cv.string, vol.Match(r"^[a-z0-9_]{1,64}$"))
OPTION_SCHEMAS: dict[str, Any] = {
    CONF_ROLES: vol.Schema({_PERSON: vol.In(ROLES)}),
    CONF_PROFILES: vol.Schema({vol.Match(r"^user:\d+(:[a-z0-9._-]+)?$"): _PERSON}),
    CONF_GROUPS: [vol.Schema({vol.Required("id"): _ID, vol.Required("name"): cv.string, "apps": [cv.string]})],
    CONF_GROUP_APPS: vol.Schema({_ID: [cv.string]}),
    CONF_OUTSIDE_ALL: [_ID],
    CONF_TILE_EXCHANGE: [_PERSON],
    CONF_SOURCES: [
        vol.Schema(
            {
                vol.Required("id"): _ID,
                vol.Required("entity_id"): cv.entity_id,
                vol.Required("person"): _PERSON,
                vol.Optional("name"): cv.string,
                vol.Optional("live"): bool,
                vol.Optional("same_as"): vol.Any(None, cv.string),
                vol.Optional("group"): vol.Any(None, _ID),
            }
        )
    ],
    CONF_TITLES: [vol.Schema({vol.Required("id"): _ID, vol.Required("name"): cv.string, "matches": [cv.string]})],
    CONF_LOCKS: [vol.Schema({vol.Required("entity_id"): cv.entity_id, vol.Required("person"): _PERSON})],
    CONF_ENFORCE: [
        vol.Schema(
            {
                vol.Required("kind"): vol.In((FAMILY_LINK, FAMILY_SAFETY, NINTENDO)),
                vol.Required("person"): _PERSON,
                vol.Required("entity_id"): cv.entity_id,
                vol.Optional("groups"): [_ID],
                vol.Optional("platforms"): [vol.In(PLATFORMS)],
            }
        )
    ],
    CONF_SCHOOL_DAYS: vol.Schema({cv.string: vol.Any(None, cv.string)}),
    CONF_APP_WATCH: [cv.entity_id],
    CONF_ASK_NOTIFY: vol.Any(None, cv.string),
}


@websocket_api.require_admin
@websocket_api.websocket_command({vol.Required("type"): "hearth/config"})
@callback
def ws_config(hass: HomeAssistant, connection: websocket_api.ActiveConnection, msg: dict[str, Any]) -> None:
    hub = _hub(hass)
    if hub is None:
        connection.send_error(msg["id"], "not_set_up", "Hearth isn't set up")
        return
    connection.send_result(msg["id"], config_document(hass, hub))


@websocket_api.require_admin
@websocket_api.websocket_command(
    {vol.Required("type"): "hearth/config/set", vol.Required("key"): vol.In(tuple(OPTION_SCHEMAS)), "value": object}
)
@callback
def ws_config_set(hass: HomeAssistant, connection: websocket_api.ActiveConnection, msg: dict[str, Any]) -> None:
    """One setting; the entry reloads with it, as after the Configure menu."""
    hub = _hub(hass)
    if hub is None:
        connection.send_error(msg["id"], "not_set_up", "Hearth isn't set up")
        return
    key = msg["key"]
    try:
        value = OPTION_SCHEMAS[key](msg.get("value"))
    except vol.Invalid as err:
        connection.send_error(msg["id"], "invalid", str(err))
        return
    hass.config_entries.async_update_entry(hub.entry, options={**hub.entry.options, key: value})
    connection.send_result(msg["id"])


@websocket_api.require_admin
@websocket_api.websocket_command(
    {
        vol.Required("type"): "hearth/budget",
        vol.Required("person"): _PERSON,
        vol.Required("group"): _ID,
        vol.Required("days"): vol.In(("both", "school_days", "other_days")),
        vol.Required("minutes"): vol.Any(None, vol.All(int, vol.Range(min=0, max=1440))),
    }
)
@callback
def ws_budget(hass: HomeAssistant, connection: websocket_api.ActiveConnection, msg: dict[str, Any]) -> None:
    """A person's budget for a group (null: no limit), for school days, other days or both."""
    hub = _hub(hass)
    if hub is None or hub.household.group(msg["group"]) is None:
        connection.send_error(msg["id"], "not_found", "No such group")
        return
    kinds = {"both": (SCHOOL_DAY, OTHER_DAY), "school_days": (SCHOOL_DAY,), "other_days": (OTHER_DAY,)}[msg["days"]]
    for kind in kinds:
        hub.household.set_budget(msg["person"], msg["group"], kind, msg["minutes"])
    connection.send_result(msg["id"])


@websocket_api.require_admin
@websocket_api.websocket_command(
    {
        vol.Required("type"): "hearth/pairing",
        vol.Required("pairing_id"): cv.string,
        vol.Required("answer"): vol.In(("approve", "deny")),
        vol.Optional("person"): vol.Any(None, _PERSON),
    }
)
@websocket_api.async_response
async def ws_pairing(hass: HomeAssistant, connection: websocket_api.ActiveConnection, msg: dict[str, Any]) -> None:
    """Approves (the code was checked on the page) or denies a device waiting to pair."""
    hub = _hub(hass)
    pairing = hub.pairing(msg["pairing_id"]) if hub else None
    if pairing is None:
        connection.send_error(msg["id"], "expired", "That request has expired")
        return
    if msg["answer"] == "deny":
        hub.deny(msg["pairing_id"])
    elif not await hub.async_approve(msg["pairing_id"], msg.get("person") if pairing.kind == KIND_MOBILE else None):
        connection.send_error(msg["id"], "expired", "That request has expired")
        return
    persistent_notification.async_dismiss(hass, pairing_notification_id(msg["pairing_id"]))
    # The discovered device in Settings > Devices & services goes too
    for flow in hass.config_entries.flow.async_progress_by_handler(DOMAIN):
        if flow.get("context", {}).get("unique_id") == pairing.device_id or (
            flow.get("context", {}).get("title_placeholders", {}).get("name") == pairing.name
        ):
            hass.config_entries.flow.async_abort(flow["flow_id"])
    connection.send_result(msg["id"])


@websocket_api.require_admin
@websocket_api.websocket_command(
    {
        vol.Required("type"): "hearth/parent_pin",
        vol.Required("person"): _PERSON,
        vol.Optional("pin"): vol.Any(None, cv.string),
    }
)
@websocket_api.async_response
async def ws_parent_pin(hass: HomeAssistant, connection: websocket_api.ActiveConnection, msg: dict[str, Any]) -> None:
    """Sets an adult's parent PIN (4 digits), or removes it (no pin). Kept as a hash only."""
    hub = _hub(hass)
    if hub is None:
        connection.send_error(msg["id"], "not_set_up", "Hearth isn't set up")
        return
    pins = parent_pin.stored_pins(hub.entry.options)
    pin = msg.get("pin")
    if pin is not None and hub.entry.options.get(CONF_ROLES, {}).get(msg["person"]) != "adult":
        connection.send_error(msg["id"], "not_adult", "Mark them as an adult first")
        return
    if pin is None:
        pins.pop(msg["person"], None)
    elif not parent_pin.PIN.match(pin):
        connection.send_error(msg["id"], "bad_pin", "Give 4 digits")
        return
    else:
        pins[msg["person"]] = await hass.async_add_executor_job(parent_pin.make, pin)
    hass.config_entries.async_update_entry(
        hub.entry, options={**hub.entry.options, parent_pin.CONF_PARENT_PINS: pins}
    )
    connection.send_result(msg["id"])


@callback
def new_group_id(name: str, taken: set[str]) -> str:
    base = slug(name) or "group"
    group_id, n = base, 2
    while group_id in taken:
        group_id, n = f"{base}_{n}", n + 1
    return group_id


@callback
def async_register_commands(hass: HomeAssistant) -> None:
    for command in (ws_config, ws_config_set, ws_budget, ws_pairing, ws_parent_pin):
        websocket_api.async_register_command(hass, command)
