"""The household at a glance, for an adult's app on Home Assistant's WebSocket (docs/home-assistant-integration.md,
Household summary): people with their screen time and locks, the Hearth devices with what's on, and the devices waiting
to pair. `hearth/household` answers once; `hearth/household/subscribe` answers the same and sends it again whenever it
changes (at most every SEND_EVERY). Administrators and adults on Hearth's page (auth.py). Contract 2 adds each person's
headline, lines and actions and the household's (glance.py). Nothing here is needed for the entities and services, which
stay as they are.

A person's own Home Assistant user (a kid's, say) gets only their own: `hearth/me` (and `hearth/me/subscribe`) answers
the document a paired phone of theirs gets, and `hearth/ask` asks for more time for them, as their device would. Nothing
else here is open to them.
"""

from __future__ import annotations

from datetime import timedelta
import hashlib
import json
from typing import Any

import voluptuous as vol

from homeassistant.components import websocket_api
from homeassistant.core import HomeAssistant, callback
from homeassistant.helpers.dispatcher import async_dispatcher_connect
from homeassistant.helpers.event import async_call_later
from homeassistant.util import dt as dt_util

from .const import CONF_KIND, CONF_MEDIA_PLAYERS, CONF_PERSON, CONF_ROLES, CONTRACT, DOMAIN, SIGNAL_DEVICE_ADDED, KIND_TV, SIGNAL_PAIRINGS, SIGNAL_PEOPLE, SIGNAL_STATUS, SIGNAL_WATCH
from .counting import ALL
from . import parent_pin
from .asks import AMOUNTS, VIA_HOME_ASSISTANT, AskError
from .limits import OTHER
from .media import media_rooms
from .auth import is_adult_user
from .glance import household_glance, person_glance
from .places import SIGNAL_PLACES
from .targets import target_of_counted

SEND_EVERY = timedelta(seconds=2)


def _minutes(seconds: float) -> int:
    return int(round(seconds / 60))


def summary(hub) -> dict[str, Any]:
    """The whole household, as one JSON object."""
    household = hub.household
    roles: dict[str, str] = dict(hub.entry.options.get(CONF_ROLES, {}))
    adults = {p for p, r in roles.items() if r == "adult"}
    profiles = household.profile_people()  # option key (a household ref, or one TV's key) -> person
    now = dt_util.now()
    today = now.date().isoformat()
    asks = [ask.approval_view(household.person_name) for ask in hub.asks.pending()]
    people = []
    for person in sorted(set(household.people()) | adults | set(roles)):
        day = household.days.get(person)
        groups = []
        for group in household.groups:
            state = day.limits.get(group.id) if day else None
            used = day.groups.get(group.id, 0.0) if day else 0.0
            if (state is None or state.budget_min is None) and not used:
                continue
            groups.append(
                {
                    "id": group.id,
                    "name": group.name,
                    "used_minutes": _minutes(used),
                    "minutes_left": state.minutes_left if state else None,
                    # Today's budget (null: no limit) and the extra time given today, apart
                    "budget": state.budget_min if state else None,
                    "bonus": state.bonus_min if state else 0,
                }
            )
        limited = any(g["minutes_left"] is not None for g in groups)
        people.append(
            {
                "id": person,
                "name": household.person_name(person),
                # As set on Hearth's page (kind_set); else a kid when they have limits, anyone else a person
                "kind": roles.get(person) or ("kid" if limited else "person"),
                "kind_set": person in roles,
                "tv_profiles": sorted(p for p, who in profiles.items() if who == person),
                # The shared pool: All screen time across every device and source
                "all": next((g for g in groups if g["id"] == ALL), None),
                "groups": groups,
                "locked": bool(day and day.locked),
                "locked_by": list(day.locked_by) if day else [],
                # TVs where Google TV's own Kids daily limit holds them (Hearth can't lift it)
                "google_tv_limit": [
                    hub.devices[d].get("name") or d for d in household.google_tv_limits(person)
                ],
                # What other parental controls hold of theirs now (family_link, family_safety, nintendo)
                "held": bool(held := household.enforcement.held_for(person)),
                "held_by": sorted(k for k, v in held.items() if v.get("held")),
                # An adult's allows (hearth.allow), and a parent's changes in their own apps that lift one of
                # Hearth's holds (grants.py)
                "allows": household.allow_views(person),
                # An adult's pauses of one app or group (hearth.pause with app or group), apart from the family pause
                "pauses": household.app_pause_views(person),
                "grants": [g.view() for g in household.grants.of(person)],
                # Google's own daily limit per Family Link device, Microsoft's allowance per platform
                "first_party": household.sync.first_party(person),
                # Per parental control: what's held, the last error and what Hearth last did
                "sync": household.enforcement.status_of(person),
                # Requests answered in a first-party app lately
                "answered_elsewhere": hub.asks.answered_elsewhere(person),
                # pause, lock {by, until}, next_lock {at, by, kind}: as in the person's state document
                **household._locks_document(person, day),
                "playing": [
                    {"app": p.app, "package": p.package, "device": p.device, "state": p.state}
                    for p in (day.playing if day else [])
                ],
            }
        )
        # Today's minutes per counted device and per app or title (each device's time once, as counted)
        if day is not None:
            people[-1]["devices_today"], people[-1]["apps_today"] = _today_by_device_and_app(household, person, day)
        # Today's School time window, on a school or half day ({start, end}, local), for "no school time today"
        if (window := household.scheduler.window_today(person, now)) is not None:
            people[-1]["school_time"] = {"start": window[0].isoformat(), "end": window[1].isoformat()}
        # Where a kid is, by name only (no coordinates): every reader of the summary is an adult (_may_read)
        if (place := household.places.summary(person)) is not None:
            people[-1]["place"] = place
        if people[-1].get("pause") and (ends_on := household.pause_view(person)):
            people[-1]["pause"] = {**people[-1]["pause"], "ends_on": ends_on}
        # Contract 2: what an adult's app shows of them, by Hearth's rules (glance.py)
        people[-1].update(
            person_glance(
                people[-1],
                [a for a in asks if a["person"] == person],
                people[-1]["allows"],
                [o for o in household.off_views(person) if o["date"] == today],
                now,
                people[-1]["grants"],
                people[-1]["answered_elsewhere"],
            )
        )
    devices = []
    for device_id, device in sorted(hub.devices.items()):
        status = hub.state(device_id).status or {}
        tv = device.get(CONF_KIND) == KIND_TV
        devices.append(
            {
                "id": device_id,
                "name": device.get("name"),
                "kind": device.get(CONF_KIND),
                "connected": hub.connected(device_id),
                "screen": status.get("screen"),
                "app": status.get("app"),
                "media_title": status.get("media_title"),
                "media_app": status.get("media_app"),
                "profile": status.get("profile") if tv else None,
                "media_player": hub.entry.options.get(CONF_MEDIA_PLAYERS, {}).get(device_id),
                "kids_profile": status.get("kids_profile"),
                "person": household.profile_person(device_id, status["profile_id"])
                if tv and status.get("profile_id")
                else device.get(CONF_PERSON),
            }
        )
    approvals = asks + [
        {
            "type": "pairing",
            "device_name": p.name,
            "device_kind": p.kind,
            "code": p.code,
            "expires": p.expires.isoformat(),
        }
        for p in hub.pending_pairings()
    ]
    body = {
        "contract": CONTRACT,
        "people": people,
        "devices": devices,
        "approvals": approvals,
        "not_screen_time": sorted(household.outside_all()),
        # Every group, budget or not today, for an app that offers to pause or allow one
        "groups": [
            {"id": g.id, "name": g.name, "not_screen_time": g.id in household.outside_all()} for g in household.groups
        ],
        # The house's media players by room, twins put together (media.py)
        "media_rooms": media_rooms(household.hass),
        # Contract 2: the household's headline and actions (glance.py)
        "household": household_glance(people, approvals),
    }
    body["version"] = hashlib.sha256(json.dumps(body, sort_keys=True, default=str).encode()).hexdigest()[:16]
    return body


def _today_by_device_and_app(household, person: str, day) -> tuple[list[dict[str, Any]], list[dict[str, Any]]]:
    devices: dict[str, dict[str, Any]] = {}
    apps: dict[str, float] = {}
    for key, usage in day.devices.items():
        target, name = target_of_counted(household, person, key)
        row = devices.setdefault(target, {"target": target, "name": name, "seconds": 0.0})
        row["seconds"] += usage.total_s
        for item, seconds in usage.items.items():
            apps[item] = apps.get(item, 0.0) + seconds
    by_device = [
        {"target": r["target"], "name": r["name"], "minutes": _minutes(r["seconds"])}
        for r in sorted(devices.values(), key=lambda r: -r["seconds"])
        if _minutes(r["seconds"]) > 0
    ]
    by_app = []
    for item, seconds in sorted(apps.items(), key=lambda kv: -kv[1])[:50]:
        if _minutes(seconds) <= 0:
            continue
        known = household.apps.apps.get(item)
        name = household._label(item, known.name if known else None)
        by_app.append({"package": item, "name": name, "minutes": _minutes(seconds)})
    return by_device, by_app


def _hub(hass: HomeAssistant):
    entries = hass.config_entries.async_loaded_entries(DOMAIN)
    return entries[0].runtime_data if entries else None


def _may_read(hass: HomeAssistant, hub, user) -> bool:
    """An administrator, or a user whose person is an adult on Hearth's page (auth.py)."""
    return is_adult_user(hass, hub, user)


def _for_reader(body: dict[str, Any], user) -> dict[str, Any]:
    """An adult who isn't an administrator doesn't see pairing codes (pairing is an administrator's)."""
    if user.is_admin:
        return body
    approvals = [a for a in body["approvals"] if a.get("type") != "pairing"]
    return {**body, "approvals": approvals, "household": household_glance(body["people"], approvals)}


@websocket_api.websocket_command({vol.Required("type"): "hearth/household"})
@callback
def ws_household(hass: HomeAssistant, connection: websocket_api.ActiveConnection, msg: dict[str, Any]) -> None:
    hub = _hub(hass)
    if hub is not None and not _may_read(hass, hub, connection.user):
        connection.send_error(msg["id"], websocket_api.ERR_UNAUTHORIZED, "Unauthorized")
        return
    if hub is None:
        connection.send_error(msg["id"], "not_set_up", "Hearth isn't set up")
        return
    connection.send_result(msg["id"], _for_reader(summary(hub), connection.user))


@websocket_api.websocket_command({vol.Required("type"): "hearth/household/subscribe"})
@callback
def ws_household_subscribe(
    hass: HomeAssistant, connection: websocket_api.ActiveConnection, msg: dict[str, Any]
) -> None:
    hub = _hub(hass)
    if hub is not None and not _may_read(hass, hub, connection.user):
        connection.send_error(msg["id"], websocket_api.ERR_UNAUTHORIZED, "Unauthorized")
        return
    if hub is None:
        connection.send_error(msg["id"], "not_set_up", "Hearth isn't set up")
        return
    sent = {"version": None}
    waiting: dict[str, Any] = {"cancel": None}

    @callback
    def send(_now=None) -> None:
        waiting["cancel"] = None
        current = _hub(hass)
        if current is None:
            return
        body = _for_reader(summary(current), connection.user)
        if body["version"] != sent["version"]:
            sent["version"] = body["version"]
            connection.send_message(websocket_api.event_message(msg["id"], body))

    @callback
    def changed(*_args) -> None:
        # Many changes come together (a status post recomputes everyone): one message for them
        if waiting["cancel"] is None:
            waiting["cancel"] = async_call_later(hass, SEND_EVERY, send)

    @callback
    def device_added(device_id: str) -> None:
        unsubs.append(async_dispatcher_connect(hass, SIGNAL_STATUS.format(device_id), changed))
        changed()

    unsubs = [
        async_dispatcher_connect(hass, SIGNAL_PEOPLE, changed),
        async_dispatcher_connect(hass, SIGNAL_PLACES, changed),
        async_dispatcher_connect(hass, SIGNAL_PAIRINGS, changed),
        async_dispatcher_connect(hass, SIGNAL_DEVICE_ADDED, device_added),
    ]
    unsubs += [async_dispatcher_connect(hass, SIGNAL_STATUS.format(d), changed) for d in hub.devices]

    @callback
    def unsubscribe() -> None:
        for unsub in unsubs:
            unsub()
        if waiting["cancel"] is not None:
            waiting["cancel"]()

    connection.subscriptions[msg["id"]] = unsubscribe
    connection.send_result(msg["id"])
    send()


@websocket_api.websocket_command(
    {
        vol.Required("type"): "hearth/approvals/answer",
        # Not "id": that's the WebSocket message's own
        vol.Required("request_id"): str,
        vol.Optional("minutes"): vol.All(int, vol.Range(min=1, max=600)),
        vol.Optional("deny"): bool,
    }
)
@callback
def ws_answer(hass: HomeAssistant, connection: websocket_api.ActiveConnection, msg: dict[str, Any]) -> None:
    """An adult answers a request for more time: minutes (any amount) or deny. The first answer wins. Administrators and
    the adults on Hearth's page may."""
    hub = _hub(hass)
    if hub is not None and not _may_read(hass, hub, connection.user):
        connection.send_error(msg["id"], websocket_api.ERR_UNAUTHORIZED, "Unauthorized")
        return
    if hub is None:
        connection.send_error(msg["id"], "not_set_up", "Hearth isn't set up")
        return
    if msg.get("deny") == bool(msg.get("minutes")):
        connection.send_error(msg["id"], "invalid", "Give minutes or deny")
        return
    try:
        ask = hub.asks.answer(msg["request_id"], None if msg.get("deny") else msg["minutes"], connection.user.id)
    except AskError as err:
        connection.send_error(msg["id"], err.code, "That request isn't open any more")
        return
    connection.send_result(msg["id"], ask.device_view())


def own_person(hass: HomeAssistant, user) -> str | None:
    """The person whose Home Assistant user is [user]: hearth/me and hearth/ask are theirs only."""
    if user is None:
        return None
    return next((s.entity_id for s in hass.states.async_all("person") if s.attributes.get("user_id") == user.id), None)


def _me(hass: HomeAssistant, connection, msg) -> tuple[Any, str | None]:
    """The hub and the caller's person, or (None, None) after an error was sent."""
    hub = _hub(hass)
    if hub is None:
        connection.send_error(msg["id"], "not_set_up", "Hearth isn't set up")
        return None, None
    person = own_person(hass, connection.user)
    if person is None:
        connection.send_error(msg["id"], websocket_api.ERR_NOT_FOUND, "This user has no person in Home Assistant")
        return None, None
    return hub, person


@websocket_api.websocket_command({vol.Required("type"): "hearth/me"})
@callback
def ws_me(hass: HomeAssistant, connection: websocket_api.ActiveConnection, msg: dict[str, Any]) -> None:
    """The caller's own person's document (household.own_document), whoever they are: a kid, an adult, anyone with a
    person. Nothing about anyone else."""
    hub, person = _me(hass, connection, msg)
    if hub is not None:
        connection.send_result(msg["id"], hub.household.own_document(person))


@websocket_api.websocket_command({vol.Required("type"): "hearth/me/subscribe"})
@callback
def ws_me_subscribe(hass: HomeAssistant, connection: websocket_api.ActiveConnection, msg: dict[str, Any]) -> None:
    """hearth/me, and again whenever it changes (at most every SEND_EVERY)."""
    hub, person = _me(hass, connection, msg)
    if hub is None:
        return
    sent = {"version": None}
    waiting: dict[str, Any] = {"cancel": None}

    @callback
    def send(_now=None) -> None:
        waiting["cancel"] = None
        current = _hub(hass)
        # Their person is looked up again: a user moved to another person stops hearing the old one's
        if current is None or own_person(hass, connection.user) != person:
            return
        body = current.household.own_document(person)
        if body["version"] != sent["version"]:
            sent["version"] = body["version"]
            connection.send_message(websocket_api.event_message(msg["id"], body))

    @callback
    def changed(*_args) -> None:
        if waiting["cancel"] is None:
            waiting["cancel"] = async_call_later(hass, SEND_EVERY, send)

    unsubs = [
        async_dispatcher_connect(hass, signal, changed)
        for signal in (SIGNAL_PEOPLE, SIGNAL_PAIRINGS, SIGNAL_PLACES, SIGNAL_WATCH)
    ]

    @callback
    def unsubscribe() -> None:
        for unsub in unsubs:
            unsub()
        if waiting["cancel"] is not None:
            waiting["cancel"]()

    connection.subscriptions[msg["id"]] = unsubscribe
    connection.send_result(msg["id"])
    send()


@websocket_api.websocket_command(
    {
        vol.Required("type"): "hearth/ask",
        vol.Optional("minutes", default=15): int,
        vol.Optional("group"): vol.Any(None, str),
        vol.Optional("app"): vol.Any(None, str),
        vol.Optional("note"): vol.Any(None, str),
    }
)
@callback
def ws_ask(hass: HomeAssistant, connection: websocket_api.ActiveConnection, msg: dict[str, Any]) -> None:
    """More time for the caller's own person, as their device asks (api.py AskView): the same checks, one open
    request, the cooldown after "not now", and the same rate limit, counted per user. The result is AskView's body:
    {"ok": true, "request"}, or {"ok": false, "error": "already_open", "request": the open one} or {"ok": false,
    "error": "cooldown", "retry_in": seconds}. Errors: not_found (no person), too_often, bad_request, not_set_up.
    """
    hub, person = _me(hass, connection, msg)
    if hub is None:
        return
    if hub.too_many_user_asks(connection.user.id):
        connection.send_error(msg["id"], "too_often", "Too many requests: try again in a minute")
        return
    app = (msg.get("app") or "").strip()[:200] or None
    group = (msg.get("group") or "").strip()[:64] or None
    if group is None and app is not None:
        # An app's own group, else All screen time
        found = hub.household.app_group(app)
        group = found if found != OTHER else None
    note = (msg.get("note") or "").strip()[:200] or None
    try:
        ask = hub.asks.ask(
            person,
            msg["minutes"],
            group or "all",
            note,
            "",
            via=VIA_HOME_ASSISTANT,
            user_id=connection.user.id,
            app=app,
        )
    except AskError as err:
        # As AskView answers them (409 and 429 there): the open request, or how long until they may ask again
        if err.code == "already_open":
            connection.send_result(msg["id"], {"ok": False, "error": "already_open", "request": err.detail.device_view()})
        elif err.code == "cooldown":
            connection.send_result(msg["id"], {"ok": False, "error": "cooldown", "retry_in": err.detail})
        else:
            connection.send_error(msg["id"], err.code, f"minutes is one of {list(AMOUNTS)}, group a known group")
        return
    connection.send_result(msg["id"], {"ok": True, "request": ask.device_view()})


@callback
def async_register_commands(hass: HomeAssistant) -> None:
    websocket_api.async_register_command(hass, ws_household)
    websocket_api.async_register_command(hass, ws_household_subscribe)
    websocket_api.async_register_command(hass, ws_answer)
    websocket_api.async_register_command(hass, ws_me)
    websocket_api.async_register_command(hass, ws_me_subscribe)
    websocket_api.async_register_command(hass, ws_ask)
