"""Hearth's own page in Home Assistant's sidebar (frontend/hearth-panel.js) and the WebSocket commands it uses.

The page shows the household (websocket.py's summary) and sets everything the Configure menu does, in one place: who's
a kid and who's an adult, devices waiting to pair, TV profiles, screen time sources, groups, budgets, locks, other
parental controls, school days and parent PINs. Administrators only. Settings go to the entry's options as the
Configure menu writes them (the entry reloads); budgets and extra time go to the day's limits, as the services do.
The integration also serves hearth-family-card.js, a Lovelace card for a TV's dashboard (any adult's), and adds it to
every dashboard as noiwid's integrations add theirs. A kid's Switch has commands of its own (Nintendo's extra playing time, its cancel and the allow list), offered as the
installed Nintendo integration allows (nintendo.py), and the page shows how each parental control integration is doing.
"""

from __future__ import annotations

from pathlib import Path
from typing import Any

import voluptuous as vol

from homeassistant.components import frontend, panel_custom, websocket_api
from homeassistant.components.frontend import add_extra_js_url
from homeassistant.components.http import StaticPathConfig
from homeassistant.core import HomeAssistant, SupportsResponse, callback
from homeassistant.exceptions import HomeAssistantError
from homeassistant.helpers import config_validation as cv
from homeassistant.helpers import entity_registry as er

from .apps import CONF_APP_WATCH, CONF_ASK_NOTIFY
from .asks import AMOUNTS, CONF_OFFER_MORE
from .const import (
    CONF_GROUP_APPS,
    CONF_GROUPS,
    CONF_KIND,
    CONF_LOCKS,
    CONF_MEDIA_PLAYERS,
    CONF_OUTSIDE_ALL,
    CONF_PERSON,
    CONF_PROFILES,
    CONF_PUSH_SERVER,
    CONF_ROLES,
    CONF_TILE_EXCHANGE,
    CONF_VOICE_ASSISTANTS,
    DOMAIN,
    KIND_MOBILE,
)
from .counting import ALL
from .enforce import CONF_ENFORCE, FAMILY_LINK, FAMILY_SAFETY, NINTENDO, NINTENDO_DOMAIN, PLATFORMS
from .catalog import CONF_CATALOG_ASKED, CONF_CATALOG_FETCH, CONF_CATALOG_RELAY, CONF_CATALOG_SHARE, CONF_CATALOG_URL
from .limits import (
    BUILTIN_GROUPS,
    CATEGORY_VALUES,
    CONF_APP_GROUPS,
    CONF_CATALOG_POOLS,
    DETAIL_VALUES,
    CONF_INSIDE_ALL,
    DEFAULT_OUTSIDE_ALL,
    OTHER,
    OTHER_DAY,
    SCHOOL_DAY,
    one_pool_per_app,
    slug,
)
from .notifications import clear_pairing
from .places import CONF_PLACES, FAVORITES, MAX_FAVORITES, MAX_NAME, RESERVED, SCHOOLS, TRACKERS
from .schooldays import CONF_SCHOOL_DAYS
from .sources import CONF_SOURCES, CONF_TITLES
from .suggest_push import CONF_SUGGEST_PUSH, pairs as suggest_pairs
from .profiles import OPTION_KEY
from . import nintendo, parent_pin, phones
from .push import clean_server

URL_PATH = "hearth"
STATIC_URL = "/hearth_static"
FRONTEND = Path(__file__).parent / "frontend"
CARD = "hearth-family-card.js"
ROLES = ("kid", "adult")

# Integrations whose entities Hearth knows how to read or hold, offered first on the page
SCREEN_TIME_PLATFORMS = ("familylink", "microsoft_family_safety", NINTENDO_DOMAIN, "xbox")
# The parental controls Hearth works through, as the page names them
PARENTAL_CONTROLS = (
    ("familylink", "Family Link"),
    ("microsoft_family_safety", "Microsoft Family Safety"),
    (NINTENDO_DOMAIN, "Nintendo Switch"),
)


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
    async_register_card(hass)
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
def async_register_card(hass: HomeAssistant) -> None:
    """The family card (frontend/hearth-family-card.js) on every dashboard, once per run (it stays through a reload,
    like the static path): its file date in the URL, so a changed card is fetched after the next restart."""
    if hass.data.get(f"{DOMAIN}_card"):
        return
    card = FRONTEND / CARD
    version = int(card.stat().st_mtime) if card.exists() else 0
    add_extra_js_url(hass, f"{STATIC_URL}/{CARD}?v={version}")
    hass.data[f"{DOMAIN}_card"] = True


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
    out["media_player"] = []
    out["nintendo_playing"] = []
    # Family Link's location trackers only (a router's or Wi-Fi tracker is never a place's source)
    out["location"] = []
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
        if entry.domain == "binary_sensor" and (entry.platform == NINTENDO_DOMAIN or "playing" in eid or "presence" in eid):
            out["nintendo_playing"].append(item)
        if entry.domain == "media_player":
            out["media_player"].append(item)
        if entry.domain == "device_tracker" and entry.platform == "familylink":
            out["location"].append(item)
    for found in out.values():
        found.sort(key=lambda i: i["name"].lower())
    return out


def _parental_controls(hass: HomeAssistant) -> list[dict[str, Any]]:
    """Each parental control integration that's installed, and whether it works now: its entries' states (loaded, a
    failed setup, waiting to retry) and, for Family Safety, its Connection sensor (connected, degraded, disconnected).
    The page tells a parent when one needs them, as the integrations' own dashboards do."""
    registry = er.async_get(hass)
    found = []
    for domain, name in PARENTAL_CONTROLS:
        entries = hass.config_entries.async_entries(domain)
        if not entries:
            continue
        row: dict[str, Any] = {
            "domain": domain,
            "name": name,
            "entries": [
                {"entry_id": e.entry_id, "title": e.title, "state": e.state.value, "reason": e.reason}
                for e in entries
            ],
        }
        connection = next(
            (
                e.entity_id
                for e in registry.entities.values()
                if e.platform == domain and e.domain == "sensor" and e.entity_id.endswith("_connection")
            ),
            None,
        )
        if connection is not None and (state := hass.states.get(connection)) is not None:
            row["connection"] = {
                "entity_id": connection,
                "state": state.state,
                "reauth_required": bool(state.attributes.get("reauth_required")),
            }
        found.append(row)
    return found


def _screen_time_sensors(hass: HomeAssistant, hub) -> dict[str, str]:
    """{person: entity id} of each person's Screen time today sensor (sensor.py's PersonScreenTime), by unique id."""
    registry = er.async_get(hass)
    found = {}
    for person in hub.household.people():
        entity_id = registry.async_get_entity_id("sensor", DOMAIN, f"{hub.entry.entry_id}_{person}_screen_time_today")
        if entity_id is not None:
            found[person] = entity_id
    return found


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
            "apps": [] if g.id == ALL else household._group_apps(g, membership, with_fs=True),
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
        "inside_all": list(options.get(CONF_INSIDE_ALL, [])),
        "default_outside_all": sorted(DEFAULT_OUTSIDE_ALL),
        "app_groups": dict(options.get(CONF_APP_GROUPS, {})),
        "media_players": dict(options.get(CONF_MEDIA_PLAYERS, {})),
        **household.apps_overview(),
        "tile_exchange": list(options.get(CONF_TILE_EXCHANGE, [])),
        # The shared app catalog (catalog.py): the copy in use, Hearth's own tile exchange setting (fetching on by
        # default; sending asked once, off until turned on), and what each value goes to here
        "catalog": {
            **household.catalog.page(),
            "asked": bool(options.get(CONF_CATALOG_ASKED)),
            "pools": household.pools(),
            "own_pools": dict(options.get(CONF_CATALOG_POOLS) or {}),
            "values": [*DETAIL_VALUES, *CATEGORY_VALUES],
        },
        # Voice assistants may use Hearth (llm_api.py): off unless chosen
        "voice_assistants": bool(options.get(CONF_VOICE_ASSISTANTS)),
        "push_server": options.get(CONF_PUSH_SERVER),
        "parent_pins": sorted(parent_pin.stored_pins(options)),
        "school_days": dict(options.get(CONF_SCHOOL_DAYS) or {}),
        "app_watch": list(options.get(CONF_APP_WATCH, [])),
        "ask_notify": options.get(CONF_ASK_NOTIFY),
        # Each adult's phones, and whether they get requests (and open hearth://ask/<id> on Android)
        "ask_phones": phones.page_view(hass, options),
        # Which kids' suggestions also go to the adults' phones, and the amount each offers (suggest_push.py)
        "suggest_push": suggest_pairs(options),
        "notify_services": sorted(
            f"notify.{name}" for name in hass.services.async_services().get("notify", {}) if name.startswith("mobile_app_")
        ),
        "known_apps": household.known_apps(),
        "choices": _entity_choices(hass),
        # Configure > Places, the zones to pick from, and where each kid is now (a place's name, never coordinates)
        "places": dict(options.get(CONF_PLACES) or {}),
        "zones": sorted(
            ({"entity_id": s.entity_id, "name": s.name} for s in hass.states.async_all("zone")),
            key=lambda z: z["name"].lower(),
        ),
        "places_now": {person: household.places.page(person) for person in household.places.people()},
        # Each person's Screen time today sensor, whose hourly statistics draw Today's hour-by-hour chart
        "screen_time_sensors": _screen_time_sensors(hass, hub),
        # What the installed integrations can do, found now: the page offers only those (nintendo.py)
        "capabilities": {"nintendo": nintendo.capabilities(hass)},
        "parental_controls": _parental_controls(hass),
    }


def _unique_keys(favorites: list[dict[str, Any]]) -> list[dict[str, Any]]:
    keys = [f["key"] for f in favorites]
    if len(set(keys)) != len(keys):
        raise vol.Invalid("Each favorite place needs its own key")
    return favorites


def _raise(message: str):
    raise vol.Invalid(message)


def _one_pair_each(found: list[dict[str, Any]]) -> list[dict[str, Any]]:
    """A suggest_push list: each kid and group (or device) once."""
    keys = [(p["person"], p.get("device") or p.get("group")) for p in found]
    if len(set(keys)) != len(keys):
        raise vol.Invalid("Each kid and group is listed once")
    return found


# A pushed pair: a kid's group or one device of theirs (a target id), and maybe the amount it offers
_SUGGEST_PAIR = vol.All(
    vol.Schema(
        {
            vol.Required("person"): cv.entity_domain("person"),
            vol.Exclusive("group", "what"): vol.All(cv.string, vol.Match(r"^[a-z0-9_]{1,64}$")),
            vol.Exclusive("device", "what"): vol.All(cv.string, vol.Length(min=1, max=200)),
            vol.Optional("minutes"): vol.In(AMOUNTS),
        }
    ),
    lambda pair: pair if ("group" in pair) != ("device" in pair) else _raise("A group or a device"),
)


# What the page may write to the options, each checked as the Configure menu would leave it
_PERSON = cv.entity_domain("person")
_ID = vol.All(cv.string, vol.Match(r"^[a-z0-9_]{1,64}$"))
OPTION_SCHEMAS: dict[str, Any] = {
    CONF_ROLES: vol.Schema({_PERSON: vol.In(ROLES)}),
    CONF_PROFILES: vol.Schema({vol.Match(OPTION_KEY): _PERSON}),
    CONF_GROUPS: [
        vol.Schema({vol.Required("id"): _ID, vol.Required("name"): cv.string, "apps": [cv.string], "category": cv.string})
    ],
    CONF_GROUP_APPS: vol.Schema({_ID: [cv.string]}),
    CONF_OUTSIDE_ALL: [_ID],
    CONF_TILE_EXCHANGE: [_PERSON],
    CONF_CATALOG_FETCH: bool,
    CONF_CATALOG_SHARE: bool,
    CONF_CATALOG_ASKED: bool,
    CONF_CATALOG_POOLS: vol.Schema({vol.In((*DETAIL_VALUES, *CATEGORY_VALUES)): vol.Any(OTHER, _ID)}),
    CONF_CATALOG_URL: vol.Any(None, vol.All(cv.url, vol.Match(r"^https://"))),
    CONF_CATALOG_RELAY: vol.Any(None, vol.All(cv.url, vol.Match(r"^https://"))),
    CONF_VOICE_ASSISTANTS: bool,
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
                # A companion app's Last used app: now playing only while [screen] (its Interactive sensor) is on
                vol.Optional("phone_app"): bool,
                vol.Optional("screen"): vol.Any(None, cv.entity_domain("binary_sensor")),
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
                vol.Optional("playing"): [cv.entity_id],
                vol.Optional("school_time_apps"): [cv.string],
            }
        )
    ],
    CONF_SCHOOL_DAYS: vol.Schema({cv.string: vol.Any(None, cv.string)}),
    CONF_APP_WATCH: [cv.entity_id],
    CONF_APP_GROUPS: vol.Schema({cv.string: vol.Any(OTHER, _ID)}),
    CONF_INSIDE_ALL: [_ID],
    CONF_MEDIA_PLAYERS: vol.Schema({cv.string: cv.entity_domain("media_player")}),
    CONF_ASK_NOTIFY: vol.Any(None, cv.string),
    phones.CONF_ASK_NOTIFY_OFF: [_PERSON],
    phones.CONF_ASK_DEEP_LINK: [_PERSON],
    CONF_PUSH_SERVER: clean_server,
    CONF_SUGGEST_PUSH: vol.All([_SUGGEST_PAIR], vol.Length(max=200), _one_pair_each),
    CONF_PLACES: vol.Schema(
        {
            vol.Optional(SCHOOLS): vol.Schema({_PERSON: cv.entity_domain("zone")}),
            vol.Optional(TRACKERS): vol.Schema({_PERSON: cv.entity_domain("device_tracker")}),
            vol.Optional(FAVORITES): vol.All(
                [
                    vol.Schema(
                        {
                            vol.Required("key"): vol.All(_ID, vol.NotIn(RESERVED)),
                            vol.Required("zone"): cv.entity_domain("zone"),
                            vol.Required("name"): vol.All(cv.string, vol.Length(min=1, max=MAX_NAME)),
                        }
                    )
                ],
                vol.Length(max=MAX_FAVORITES),
                _unique_keys,
            ),
        }
    ),
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
        # vol.Schema: a list ([_PERSON]) is a schema too, but not a callable
        value = vol.Schema(OPTION_SCHEMAS[key])(msg.get("value"))
    except vol.Invalid as err:
        connection.send_error(msg["id"], "invalid", str(err))
        return
    options = {**hub.entry.options, key: value}
    if key == CONF_GROUPS:
        # A pool's category (the Video pool retire_video kept) stays when the page sends the pool without it
        categories = {g["id"]: g["category"] for g in hub.entry.options.get(CONF_GROUPS, []) if g.get("category")}
        options[CONF_GROUPS] = [
            {**g, "category": categories[g["id"]]} if g["id"] in categories and "category" not in g else g
            for g in options[CONF_GROUPS]
        ]
    if key in (CONF_GROUPS, CONF_GROUP_APPS):
        # An app is in one pool: one just put in a pool's list leaves the others
        options = one_pool_per_app(hub.entry.options, options)
    if key == CONF_SUGGEST_PUSH:
        # The older offer_more (moved into suggest_push when the household loads) mustn't come back with it
        options.pop(CONF_OFFER_MORE, None)
    hass.config_entries.async_update_entry(hub.entry, options=options)
    connection.send_result(msg["id"])


@websocket_api.require_admin
@websocket_api.websocket_command(
    {
        vol.Required("type"): "hearth/catalog/correct",
        vol.Required("app"): vol.All(cv.string, vol.Length(min=1, max=200)),
        vol.Required("group"): vol.Any(OTHER, _ID),
    }
)
@callback
def ws_catalog_correct(hass: HomeAssistant, connection: websocket_api.ActiveConnection, msg: dict[str, Any]) -> None:
    """An adult's move, shared with the shared app catalog too (the catalog's key and value, never the pool): queued
    for the weekly send while the tile exchange's sending is on."""
    hub = _hub(hass)
    if hub is None:
        connection.send_error(msg["id"], "not_set_up", "Hearth isn't set up")
        return
    connection.send_result(msg["id"], {"queued": hub.household.correct_app(msg["app"], msg["group"])})


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
    clear_pairing(hass, msg["pairing_id"])
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


def _switch_or_error(hass: HomeAssistant, connection, msg: dict[str, Any], service: str) -> dict[str, Any] | None:
    """The kid's Switch the message names, when the Nintendo integration has [service]; else an error is sent."""
    hub = _hub(hass)
    if hub is None:
        connection.send_error(msg["id"], "not_set_up", "Hearth isn't set up")
        return None
    if not hass.services.has_service(NINTENDO_DOMAIN, service):
        connection.send_error(msg["id"], "not_supported", "The installed Nintendo integration can't do that")
        return None
    switch = nintendo.switch_of(hub.household, msg["person"], msg["device_id"])
    if switch is None:
        connection.send_error(msg["id"], "not_found", "That isn't one of their Switches")
        return None
    return switch


async def _call_nintendo(hass: HomeAssistant, service: str, data: dict[str, Any]) -> dict[str, Any] | None:
    responds = hass.services.supports_response(NINTENDO_DOMAIN, service) != SupportsResponse.NONE
    return await hass.services.async_call(NINTENDO_DOMAIN, service, data, blocking=True, return_response=responds)


@websocket_api.require_admin
@websocket_api.websocket_command(
    {
        vol.Required("type"): "hearth/nintendo/bonus",
        vol.Required("person"): _PERSON,
        vol.Required("device_id"): cv.string,
        vol.Required("minutes"): vol.All(
            int, vol.Any(nintendo.UNLIMITED, vol.All(int, vol.Range(min=nintendo.BONUS_MIN, max=1440)))
        ),
    }
)
@websocket_api.async_response
async def ws_nintendo_bonus(hass: HomeAssistant, connection: websocket_api.ActiveConnection, msg: dict[str, Any]) -> None:
    """Nintendo's own extra playing time on a kid's Switch (add_bonus_time), past the Switch's own limit. Not while
    Hearth holds the Switch: Hearth's extra time on it (hearth.add_bonus with its device) lets the hold go instead, and
    Nintendo's extra on a held Switch would read as a parent's change in the Nintendo app."""
    switch = _switch_or_error(hass, connection, msg, nintendo.ADD_BONUS)
    if switch is None:
        return
    if switch["held_by_hearth"]:
        connection.send_error(msg["id"], "held", "Hearth holds this Switch: give Hearth's extra time on it instead")
        return
    data = {"device_id": msg["device_id"], "bonus_time": msg["minutes"]}
    if not nintendo.accepts(hass, nintendo.ADD_BONUS, data):
        connection.send_error(
            msg["id"], "not_supported", "The installed Nintendo integration doesn't take that many minutes"
        )
        return
    try:
        response = await _call_nintendo(hass, nintendo.ADD_BONUS, data)
    except (HomeAssistantError, vol.Invalid) as err:
        connection.send_error(msg["id"], "failed", str(err))
        return
    connection.send_result(msg["id"], response or {})


@websocket_api.require_admin
@websocket_api.websocket_command(
    {
        vol.Required("type"): "hearth/nintendo/bonus_cancel",
        vol.Required("person"): _PERSON,
        vol.Required("device_id"): cv.string,
    }
)
@websocket_api.async_response
async def ws_nintendo_bonus_cancel(
    hass: HomeAssistant, connection: websocket_api.ActiveConnection, msg: dict[str, Any]
) -> None:
    """Cancels today's extra playing time on a kid's Switch (cancel_bonus_time, a patched Nintendo integration's)."""
    if _switch_or_error(hass, connection, msg, nintendo.CANCEL_BONUS) is None:
        return
    try:
        response = await _call_nintendo(hass, nintendo.CANCEL_BONUS, {"device_id": msg["device_id"]})
    except HomeAssistantError as err:
        connection.send_error(msg["id"], "failed", str(err))
        return
    connection.send_result(msg["id"], response or {})


@websocket_api.require_admin
@websocket_api.websocket_command(
    {vol.Required("type"): "hearth/nintendo/apps", vol.Required("person"): _PERSON, vol.Required("device_id"): cv.string}
)
@websocket_api.async_response
async def ws_nintendo_apps(hass: HomeAssistant, connection: websocket_api.ActiveConnection, msg: dict[str, Any]) -> None:
    """The games on a kid's Switch and whether each is on its allow list (list_applications), by name."""
    if _switch_or_error(hass, connection, msg, nintendo.LIST_APPS) is None:
        return
    try:
        response = await _call_nintendo(hass, nintendo.LIST_APPS, {"device_id": msg["device_id"]})
    except HomeAssistantError as err:
        connection.send_error(msg["id"], "failed", str(err))
        return
    apps = [
        {"application_id": a.get("application_id"), "name": a.get("name"), "allowed": bool(a.get("allowed"))}
        for a in (response or {}).get("applications") or []
        if isinstance(a, dict) and a.get("application_id")
    ]
    apps.sort(key=lambda a: str(a["name"] or a["application_id"]).casefold())
    connection.send_result(msg["id"], {"applications": apps})


@websocket_api.require_admin
@websocket_api.websocket_command(
    {
        vol.Required("type"): "hearth/nintendo/app_allowed",
        vol.Required("person"): _PERSON,
        vol.Required("device_id"): cv.string,
        vol.Required("application_id"): cv.string,
        vol.Required("allowed"): bool,
    }
)
@websocket_api.async_response
async def ws_nintendo_app_allowed(
    hass: HomeAssistant, connection: websocket_api.ActiveConnection, msg: dict[str, Any]
) -> None:
    """Puts a game on a kid's Switch's allow list, or takes it off (set_app_allowed): an allowed game starts past the
    Switch's age rating restriction."""
    if _switch_or_error(hass, connection, msg, nintendo.SET_APP_ALLOWED) is None:
        return
    data = {"device_id": msg["device_id"], "application_id": msg["application_id"], "allowed": msg["allowed"]}
    try:
        response = await _call_nintendo(hass, nintendo.SET_APP_ALLOWED, data)
    except HomeAssistantError as err:
        connection.send_error(msg["id"], "failed", str(err))
        return
    connection.send_result(msg["id"], response or {})


@callback
def new_group_id(name: str, taken: set[str]) -> str:
    base = slug(name) or "group"
    group_id, n = base, 2
    while group_id in taken:
        group_id, n = f"{base}_{n}", n + 1
    return group_id


@callback
def async_register_commands(hass: HomeAssistant) -> None:
    for command in (
        ws_config,
        ws_config_set,
        ws_catalog_correct,
        ws_budget,
        ws_pairing,
        ws_parent_pin,
        ws_nintendo_bonus,
        ws_nintendo_bonus_cancel,
        ws_nintendo_apps,
        ws_nintendo_app_allowed,
    ):
        websocket_api.async_register_command(hass, command)
