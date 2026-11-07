"""The household at a glance, for an adult's app on Home Assistant's WebSocket (docs/home-assistant-integration.md,
Household summary): people with their screen time and locks, the Hearth devices with what's on, and the devices waiting
to pair. `hearth/household` answers once; `hearth/household/subscribe` answers the same and sends it again whenever it
changes (at most every SEND_EVERY). Administrators and adults on Hearth's page (auth.py). Contract 2 adds each person's
headline, lines and actions and the household's (glance.py). Nothing here is needed for the entities and services, which
stay as they are.
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

from .const import CONF_KIND, CONF_MEDIA_PLAYERS, CONF_PERSON, CONF_ROLES, CONTRACT, DOMAIN, SIGNAL_DEVICE_ADDED, KIND_TV, SIGNAL_PAIRINGS, SIGNAL_PEOPLE, SIGNAL_STATUS
from .counting import ALL
from . import parent_pin
from .asks import AskError
from .media import media_rooms
from .auth import is_adult_user
from .glance import household_glance, person_glance

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
                # What other parental controls hold of theirs now (family_link, family_safety, nintendo)
                "held": bool(held := household.enforcement.held_for(person)),
                "held_by": sorted(k for k, v in held.items() if v.get("held")),
                # pause, lock {by, until}, next_lock {at, by, kind}: as in the person's state document
                **household._locks_document(person, day),
                "playing": [
                    {"app": p.app, "package": p.package, "device": p.device, "state": p.state}
                    for p in (day.playing if day else [])
                ],
            }
        )
        # Contract 2: what an adult's app shows of them, by Hearth's rules (glance.py)
        people[-1].update(
            person_glance(
                people[-1],
                [a for a in asks if a["person"] == person],
                [a.view(person) for a in household.allows.of(person)],
                [o for o in household.scheduler.offs_of(person) if o["date"] == today],
                now,
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
        # The house's media players by room, twins put together (media.py)
        "media_rooms": media_rooms(household.hass),
        # Contract 2: the household's headline and actions (glance.py)
        "household": household_glance(people, approvals),
    }
    body["version"] = hashlib.sha256(json.dumps(body, sort_keys=True, default=str).encode()).hexdigest()[:16]
    return body


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


@callback
def async_register_commands(hass: HomeAssistant) -> None:
    websocket_api.async_register_command(hass, ws_household)
    websocket_api.async_register_command(hass, ws_household_subscribe)
    websocket_api.async_register_command(hass, ws_answer)
