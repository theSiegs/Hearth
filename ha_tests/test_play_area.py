"""Playing's room and whether it's being played now (play_area.py, docs/contracts/people-entities.md): a Hearth TV's
own area, an Xbox's console's, a Switch's dock's only while its TV shows the dock's input; `person` on the sensor."""

from datetime import timedelta

import pytest

from homeassistant.core import Context, HomeAssistant
from homeassistant.exceptions import ServiceValidationError, Unauthorized
from homeassistant.helpers import area_registry as ar, device_registry as dr, entity_registry as er
import voluptuous as vol
from pytest_homeassistant_custom_component.common import MockConfigEntry
from pytest_homeassistant_custom_component.typing import ClientSessionGenerator

from custom_components.hearth import enforce
from custom_components.hearth.const import DOMAIN
from custom_components.hearth.play_area import PLAY_AREAS_SCHEMA, hearth_tv_active, play_areas
from test_init import TV_ID, _post
from test_now_playing import NINTENDO_LIMIT, SAM_PLAYING, _hub, _options, _recompute, _switch
from test_people import _household_with_sam, _tv_status
from test_sources import XBOX_SENSOR, _option

PLAYING = "sensor.hearth_sam_playing"
CONSOLE = "media_player.playroom_xbox"
DOCK_TV = "media_player.playroom_tv"
DOCK = "binary_sensor.switch_dock"
DOCK_PLUG = "sensor.switch_dock_power"


@pytest.fixture(autouse=True)
def settled(monkeypatch):
    monkeypatch.setattr(enforce, "SETTLE", timedelta(0))


def _area(hass: HomeAssistant, name: str = "Playroom") -> str:
    return ar.async_get(hass).async_get_or_create(name).id


def _entries(hass: HomeAssistant) -> list[dict]:
    return hass.states.get(PLAYING).attributes["playing"]


def _tv_device(hass: HomeAssistant):
    return dr.async_get(hass).async_get_device_by_identifier((DOMAIN, TV_ID), _hub(hass).entry.entry_id)


def _xbox_console(hass: HomeAssistant, area_id: str | None) -> str:
    """The Xbox integration's media player for a console, in [area_id]."""
    xbox = MockConfigEntry(domain="xbox")
    xbox.add_to_hass(hass)
    device = dr.async_get(hass).async_get_or_create(config_entry_id=xbox.entry_id, identifiers={("xbox", "console1")})
    if area_id:
        dr.async_get(hass).async_update_device(device.id, area_id=area_id)
    er.async_get(hass).async_get_or_create(
        "media_player", "xbox", "console1", device_id=device.id, suggested_object_id="playroom_xbox"
    )
    return device.id


async def test_a_tv_s_entry_is_in_the_tv_s_room_and_the_sensor_says_whose(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator
) -> None:
    client, secret = await _household_with_sam(hass, hass_client_no_auth)
    assert (await _post(client, secret, body=_tv_status(600, 300, playing="com.thesiegs.hearthtube"))).status == 200
    await hass.async_block_till_done()
    state = hass.states.get(PLAYING)
    assert state.attributes["person"] == "person.sam"
    # No room set for the TV: none
    assert _entries(hass)[0]["area_id"] is None and _entries(hass)[0]["active"] is True

    dr.async_get(hass).async_update_device(_tv_device(hass).id, area_id=_area(hass))
    await _recompute(hass)
    assert _entries(hass)[0]["area_id"] == _area(hass)
    # Still additive: the state is what's on, and the household's documents don't carry the new fields
    assert state.state == "HearthTube"
    own = _hub(hass).household.own_document("person.sam")["person"]["playing"]
    assert "area_id" not in own[0] and "active" not in own[0]


async def test_a_tv_app_s_active_follows_its_media() -> None:
    assert hearth_tv_active("playing", False) is True
    assert hearth_tv_active("paused", False) is False
    assert hearth_tv_active("playing", True) is False
    # An app with no media playing (a game, a menu) can't be told
    assert hearth_tv_active("idle", False) is None and hearth_tv_active(None, False) is None


async def test_an_xbox_game_is_in_its_console_s_room_while_the_console_shows_it(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator
) -> None:
    await _household_with_sam(hass, hass_client_no_auth)
    room = _area(hass)
    console = _xbox_console(hass, room)
    hass.states.async_set(CONSOLE, "on", {"media_title": "Minecraft"})
    hass.states.async_set(XBOX_SENSOR, "")
    await _option(hass, "add_source", {"entity_id": XBOX_SENSOR, "person": "person.sam", "live": True, "name": "Xbox"})
    hass.states.async_set(XBOX_SENSOR, "Minecraft")
    await hass.async_block_till_done()

    xbox = next(p for p in _entries(hass) if p["title"] == "Minecraft")
    # Found: the one Xbox on with the same game; a game shows "on", so whether it's played can't be told
    assert xbox["area_id"] == room and xbox["active"] is None

    # Another game on that console: played somewhere else (a PC, the cloud)
    hass.states.async_set(CONSOLE, "on", {"media_title": "Forza Horizon 5"})
    await _recompute(hass)
    assert next(p for p in _entries(hass) if p["title"] == "Minecraft")["area_id"] is None

    # The console off: no room
    hass.states.async_set(CONSOLE, "off")
    await _recompute(hass)
    assert next(p for p in _entries(hass) if p["title"] == "Minecraft")["area_id"] is None

    # A console with no room: none, never a guess
    hass.states.async_set(CONSOLE, "on", {"media_title": "Minecraft"})
    er.async_get(hass).async_update_entity(CONSOLE, area_id=None)
    dr.async_get(hass).async_update_device(console, area_id=None)
    await _recompute(hass)
    assert next(p for p in _entries(hass) if p["title"] == "Minecraft")["area_id"] is None


async def test_a_set_console_and_the_service_that_sets_it(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator, hass_admin_user, hass_read_only_user
) -> None:
    await _household_with_sam(hass, hass_client_no_auth)
    room = _area(hass)
    # Any media player in a room, not the Xbox integration's: only used once it's set
    er.async_get(hass).async_get_or_create("media_player", "other", "c1", suggested_object_id="playroom_xbox")
    er.async_get(hass).async_update_entity(CONSOLE, area_id=room)
    hass.states.async_set(CONSOLE, "playing", {"media_title": "Minecraft"})
    hass.states.async_set(XBOX_SENSOR, "")
    await _option(hass, "add_source", {"entity_id": XBOX_SENSOR, "person": "person.sam", "live": True, "name": "Xbox"})
    source_id = next(s["id"] for s in _hub(hass).entry.options["sources"] if s["entity_id"] == XBOX_SENSOR)
    hass.states.async_set(XBOX_SENSOR, "Minecraft")
    await hass.async_block_till_done()
    assert _entries(hass)[0]["area_id"] is None

    data = {"source": source_id, "console": CONSOLE}
    for context in (Context(), Context(user_id=hass_read_only_user.id)):
        with pytest.raises(Unauthorized):
            await hass.services.async_call(DOMAIN, "set_play_area", data, blocking=True, context=context)
    admin = Context(user_id=hass_admin_user.id)
    answer = await hass.services.async_call(
        DOMAIN, "set_play_area", data, blocking=True, context=admin, return_response=True
    )
    assert answer == {"play_areas": [data]}
    await hass.async_block_till_done()
    await _recompute(hass)
    assert _entries(hass)[0]["area_id"] == room
    # The console's media player playing says it's played
    assert _entries(hass)[0]["active"] is True
    hass.states.async_set(CONSOLE, "paused", {"media_title": "Minecraft"})
    await _recompute(hass)
    assert _entries(hass)[0]["active"] is False and _entries(hass)[0]["area_id"] == room

    # Neither or both of switch and source are refused; remove takes it out
    with pytest.raises(ServiceValidationError):
        await hass.services.async_call(DOMAIN, "set_play_area", {"console": CONSOLE}, blocking=True, context=admin)
    await hass.services.async_call(
        DOMAIN, "set_play_area", {"source": source_id, "remove": True}, blocking=True, context=admin
    )
    await hass.async_block_till_done()
    assert _hub(hass).entry.options["play_areas"] == []


async def test_a_switch_is_in_its_dock_s_room_only_while_its_dock_signal_says_docked(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator, hass_admin_user, monkeypatch
) -> None:
    await _household_with_sam(hass, hass_client_no_auth)
    _switch(hass)
    await _options(
        hass, enforce=[{"kind": "nintendo", "person": "person.sam", "entity_id": NINTENDO_LIMIT, "playing": [SAM_PLAYING]}]
    )
    room = _area(hass)
    er.async_get(hass).async_get_or_create("binary_sensor", "other", "dock1", suggested_object_id="switch_dock")
    er.async_get(hass).async_update_entity(DOCK, area_id=room)
    hass.states.async_set(DOCK, "on")
    # A TV that's on says nothing about the Switch (a Hearth TV puck reads off while another input shows)
    hass.states.async_set(DOCK_TV, "on", {"source": "HDMI 2"})
    hass.states.async_set(SAM_PLAYING, "on")
    await hass.async_block_till_done()

    def switch() -> dict:
        return next(p for p in _entries(hass) if p["device"] == "Sam's Switch")

    # No dock signal set: a Switch may be handheld anywhere
    assert switch()["area_id"] is None
    # Only its playing sensor, no player's minutes: whether it's played now can't be told
    assert switch()["active"] is None

    admin = Context(user_id=hass_admin_user.id)
    await hass.services.async_call(
        DOMAIN, "set_play_area", {"switch": NINTENDO_LIMIT, "dock": DOCK}, blocking=True, context=admin
    )
    await hass.async_block_till_done()
    hass.states.async_set(SAM_PLAYING, "on", {"title": "Mario Kart 8 Deluxe"})
    await hass.async_block_till_done()
    # The dock signal's own area
    assert switch()["area_id"] == room

    # Off (handheld), unknown or unavailable: no room
    for state in ("off", "unknown", "unavailable"):
        hass.states.async_set(DOCK, state)
        await _recompute(hass)
        assert switch()["area_id"] is None, state

    # A power sensor of the dock's plug, with a room of its own: docked above the watts set
    other = _area(hass, "Attic")
    await hass.services.async_call(
        DOMAIN, "set_play_area", {"switch": NINTENDO_LIMIT, "dock": DOCK_PLUG, "above": 3, "area_id": other},
        blocking=True, context=admin,
    )
    await hass.async_block_till_done()
    for watts, unit, area in (("1.5", "W", None), ("7.2", "W", other), ("0.01", "kW", other), ("x", "W", None)):
        hass.states.async_set(DOCK_PLUG, watts, {"unit_of_measurement": unit})
        await _recompute(hass)
        assert switch()["area_id"] == area, (watts, unit)

    # Their player's minutes growing (or watched still) say it's played or not
    hass.states.async_set(DOCK_PLUG, "12", {"unit_of_measurement": "W"})
    for minutes in (True, False):
        monkeypatch.setattr(_hub(hass).household.enforcement, "playing", lambda enforcer, m=minutes: m)
        await _recompute(hass)
        assert switch()["area_id"] == other and switch()["active"] is minutes

    # A power sensor without the watts is refused
    with pytest.raises(ServiceValidationError):
        await hass.services.async_call(
            DOMAIN, "set_play_area", {"switch": NINTENDO_LIMIT, "dock": DOCK_PLUG}, blocking=True, context=admin
        )


def test_play_areas_are_checked_and_a_bad_one_is_left_out() -> None:
    dock = {"switch": "number.a_switch", "dock": "binary_sensor.dock"}
    plug = {"switch": "number.b_switch", "dock": "sensor.dock_power", "above": 3.0, "area_id": "playroom"}
    console = {"source": "xbox", "console": "media_player.xbox"}
    assert PLAY_AREAS_SCHEMA([dock, plug, console]) == [dock, plug, console]
    for bad in (
        [dock, {**dock, "dock": "switch.dock"}],  # one Switch twice
        [{**dock, "dock": "media_player.tv"}],  # no TV or input: a TV can't tell a docked Switch
        [{**dock, "above": 3}],  # watts only for a power sensor
        [{**plug, "above": None}],
        [{"switch": "number.b_switch", "dock": "sensor.dock_power"}],
        [{"source": "xbox"}],
    ):
        with pytest.raises(vol.Invalid):
            PLAY_AREAS_SCHEMA(bad)
    # Stored options that don't fit are never in the way
    assert play_areas({"play_areas": [dock, {"switch": 3}, "x", console]}) == [dock, console]
    assert play_areas({}) == []
