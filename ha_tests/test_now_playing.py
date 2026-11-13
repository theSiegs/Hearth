"""Now playing for everyone: a kid's Switch, a TV's show from its media player, a phone's app from the companion app,
the household's `playing` list, a person's own documents, and the history's `played` events."""

from datetime import timedelta

import pytest

from homeassistant.core import HomeAssistant
from homeassistant.helpers import device_registry as dr, entity_registry as er
from homeassistant.util import dt as dt_util
from pytest_homeassistant_custom_component.common import MockConfigEntry, async_mock_service
from pytest_homeassistant_custom_component.typing import ClientSessionGenerator

from custom_components.hearth import enforce
from custom_components.hearth.const import DOMAIN
from custom_components.hearth.history import MAX_PLAYED, PLAYED, History
from custom_components.hearth.live import LiveTracker, Observation
from custom_components.hearth.websocket import summary
from test_init import TV_ID, _post
from test_people import KID, _household_with_sam, _tv_status
from test_sources import XBOX_SENSOR, _minutes_pass, _option, _state

NINTENDO_LIMIT = "number.sam_s_switch_max_screentime_today"
SAM_PLAYING = "binary_sensor.sam_s_switch_sam_playing"
ALEX_XBOX = "sensor.alex_now_playing"
TV_PLAYER = "media_player.kitchen_tv"
ALEX_APP = "sensor.alex_phone_last_used_app"
ALEX_SCREEN = "binary_sensor.alex_phone_interactive"


@pytest.fixture(autouse=True)
def settled(monkeypatch):
    monkeypatch.setattr(enforce, "SETTLE", timedelta(0))


def _hub(hass: HomeAssistant):
    return hass.config_entries.async_entries(DOMAIN)[0].runtime_data


async def _options(hass: HomeAssistant, **changes) -> None:
    entry = hass.config_entries.async_entries(DOMAIN)[0]
    hass.config_entries.async_update_entry(entry, options={**entry.options, **changes})
    await hass.async_block_till_done()


async def _recompute(hass: HomeAssistant) -> None:
    _hub(hass).household.recompute()
    await hass.async_block_till_done()


def _switch(hass: HomeAssistant) -> None:
    """Sam's Switch as Nintendo's integration makes it, with Sam's own player's playing sensor."""
    nintendo = MockConfigEntry(domain="nintendo_parental_controls")
    nintendo.add_to_hass(hass)
    device = dr.async_get(hass).async_get_or_create(
        config_entry_id=nintendo.entry_id, identifiers={("nintendo_parental_controls", "abc123")}, name="Sam's Switch"
    )
    registry = er.async_get(hass)
    for entity_id, key in ((NINTENDO_LIMIT, "today_max_screentime"), (SAM_PLAYING, "p1_playing")):
        domain, object_id = entity_id.split(".")
        registry.async_get_or_create(
            domain, "nintendo_parental_controls", f"abc123_{key}", device_id=device.id, suggested_object_id=object_id
        )
    hass.states.async_set(NINTENDO_LIMIT, "120")
    hass.states.async_set(SAM_PLAYING, "off")
    async_mock_service(hass, "number", "set_value")
    async_mock_service(hass, "switch", "turn_on")
    async_mock_service(hass, "switch", "turn_off")


async def _alex(hass: HomeAssistant, role: str = "kid") -> None:
    hass.states.async_set("person.alex", "home", {"friendly_name": "Alex"})
    await _options(hass, roles={"person.alex": role})


async def test_a_kid_on_their_switch_is_playing_and_together(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator, freezer
) -> None:
    freezer.move_to(dt_util.now().replace(hour=12, minute=0))
    await _household_with_sam(hass, hass_client_no_auth)
    _switch(hass)
    await _options(
        hass, enforce=[{"kind": "nintendo", "person": "person.sam", "entity_id": NINTENDO_LIMIT, "playing": [SAM_PLAYING]}]
    )
    await _alex(hass)
    hass.states.async_set(ALEX_XBOX, "")
    await _option(hass, "add_source", {"entity_id": ALEX_XBOX, "person": "person.alex", "live": True})
    games = _state(hass, "sensor.hearth_sam_games_today")

    # Nintendo doesn't name the game: it's "Switch", on the Switch as a target
    hass.states.async_set(SAM_PLAYING, "on")
    await hass.async_block_till_done()
    assert _state(hass, "sensor.hearth_sam_playing") == "Switch"
    sam = next(p for p in summary(_hub(hass))["people"] if p["id"] == "person.sam")
    switch = next(p for p in sam["playing"] if p["target"] == f"nintendo:{NINTENDO_LIMIT}")
    assert switch["device"] == "Sam's Switch" and switch["title"] is None and switch["since"]

    # A patched integration names it: together with Alex on the same title
    hass.states.async_set(SAM_PLAYING, "on", {"title": "Mario Kart 8 Deluxe"})
    hass.states.async_set(ALEX_XBOX, "Mario Kart 8 Deluxe")
    await hass.async_block_till_done()
    assert _state(hass, "sensor.hearth_sam_playing") == "Mario Kart 8 Deluxe"
    together = hass.states.get("binary_sensor.hearth_home_playing_together")
    assert together.state == "on" and together.attributes["together"][0]["people"] == ["Alex", "Sam"]

    # Not timed: Nintendo's own minutes count a Switch
    await _minutes_pass(hass, freezer, 5)
    assert _state(hass, "sensor.hearth_sam_games_today") == games
    hass.states.async_set(SAM_PLAYING, "off")
    await hass.async_block_till_done()
    sam = next(p for p in summary(_hub(hass))["people"] if p["id"] == "person.sam")
    assert all(p["target"] != f"nintendo:{NINTENDO_LIMIT}" for p in sam["playing"])


async def test_a_tv_s_media_player_says_the_show(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator
) -> None:
    client, secret = await _household_with_sam(hass, hass_client_no_auth)
    await _options(hass, media_players={TV_ID: TV_PLAYER})
    hass.states.async_set(TV_PLAYER, "playing", {"media_series_title": "Bluey", "media_title": "Sleepytime"})
    assert (await _post(client, secret, body=_tv_status(600, 300, playing="com.thesiegs.hearthtube"))).status == 200
    await hass.async_block_till_done()

    assert _state(hass, "sensor.hearth_sam_playing") == "Bluey"
    attributes = hass.states.get("sensor.hearth_sam_playing").attributes["playing"][0]
    assert attributes["app"] == "HearthTube" and attributes["title"] == "Bluey" and attributes["episode"] == "Sleepytime"

    # "Together" goes by the show: Alex watching it elsewhere
    await _alex(hass)
    hass.states.async_set(ALEX_XBOX, "")
    await _option(hass, "add_source", {"entity_id": ALEX_XBOX, "person": "person.alex", "live": True})
    hass.states.async_set(ALEX_XBOX, "Bluey")
    await hass.async_block_till_done()
    together = hass.states.get("binary_sensor.hearth_home_playing_together")
    assert together.state == "on" and together.attributes["together"][0]["title"] == "Bluey"

    # The player off: just the app again
    hass.states.async_set(TV_PLAYER, "off")
    await _recompute(hass)
    assert _state(hass, "sensor.hearth_sam_playing") == "HearthTube"
    assert _state(hass, "binary_sensor.hearth_home_playing_together") == "off"


async def test_an_adult_s_phone_app_while_the_screen_is_on(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator
) -> None:
    await _household_with_sam(hass, hass_client_no_auth)
    await _alex(hass, "adult")
    hass.states.async_set(ALEX_SCREEN, "off")
    hass.states.async_set(ALEX_APP, "com.example.reader")
    await _option(hass, "add_source", {"entity_id": ALEX_APP, "person": "person.alex", "name": "Alex's phone"})
    source = next(s for s in _hub(hass).entry.options["sources"] if s["entity_id"] == ALEX_APP)
    assert source["phone_app"] and source["live"]

    # The last app used, but the screen is off: not playing
    assert _state(hass, "sensor.hearth_alex_playing") == "unknown"
    hass.states.async_set(ALEX_SCREEN, "on")
    await hass.async_block_till_done()
    playing = hass.states.get("sensor.hearth_alex_playing")
    assert playing.state == "com.example.reader"
    assert playing.attributes["playing"][0]["device"] == "Alex's phone"
    household = summary(_hub(hass))["playing"]
    assert [(p["person"], p["item"]) for p in household] == [("person.alex", "com.example.reader")]

    # The home screen isn't an app being used
    hass.states.async_set(ALEX_APP, "com.google.android.apps.nexuslauncher")
    await hass.async_block_till_done()
    assert _state(hass, "sensor.hearth_alex_playing") == "unknown"

    # Not timed: nothing counts toward Alex's screen time
    alex = next(p for p in summary(_hub(hass))["people"] if p["id"] == "person.alex")
    assert not alex["devices_today"]


async def test_a_phone_app_source_without_a_screen_sensor_is_never_playing(hass: HomeAssistant) -> None:
    from custom_components.hearth.sources import Source, phone_app_playing, screen_entity

    source = Source("p", "sensor.sam_tablet_last_used_app", "person.sam", "Tablet", live=True, phone_app=True)
    assert screen_entity(hass, source) == "binary_sensor.sam_tablet_interactive"
    hass.states.async_set(source.entity_id, "com.example.game")
    assert phone_app_playing(hass, source) is None
    hass.states.async_set("binary_sensor.sam_tablet_interactive", "on")
    assert phone_app_playing(hass, source) == "com.example.game"
    # Its own screen sensor, when chosen
    own = Source("p", source.entity_id, "person.sam", "Tablet", live=True, phone_app=True, screen="binary_sensor.other")
    assert phone_app_playing(hass, own) is None


async def test_a_person_s_own_documents_say_what_they_play(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator
) -> None:
    client, secret = await _household_with_sam(hass, hass_client_no_auth)
    assert (await _post(client, secret, body=_tv_status(600, 300, playing="com.thesiegs.hearthtube"))).status == 200
    await hass.async_block_till_done()
    household = _hub(hass).household

    own = household.own_document("person.sam")["person"]["playing"]
    assert [(p["app"], p["target"]) for p in own] == [("HearthTube", f"hearth:{TV_ID}")]
    assert own[0]["since"]
    assert household.document_for(TV_ID)["profiles"][KID]["playing"] == own
    rows = summary(_hub(hass))["playing"]
    assert rows[0]["person"] == "person.sam" and rows[0]["name"] == "Sam" and rows[0]["item"] == "HearthTube"


async def test_a_play_that_ends_is_in_the_history(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator, freezer
) -> None:
    freezer.move_to(dt_util.now().replace(hour=12, minute=0))
    await _household_with_sam(hass, hass_client_no_auth)
    hass.states.async_set(XBOX_SENSOR, "")
    await _option(hass, "add_source", {"entity_id": XBOX_SENSOR, "person": "person.sam", "live": True, "name": "Xbox"})
    history = _hub(hass).household.history

    hass.states.async_set(XBOX_SENSOR, "Minecraft")
    await hass.async_block_till_done()
    await _minutes_pass(hass, freezer, 10)
    hass.states.async_set(XBOX_SENSOR, "")
    await hass.async_block_till_done()
    played = history.of("person.sam", kinds=(PLAYED,))
    assert [(e["item"], e["minutes"]) for e in played] == [("Minecraft", 10)]
    assert played[0]["device"].startswith("source:")

    # Again the same day: the same event grows
    hass.states.async_set(XBOX_SENSOR, "Minecraft")
    await hass.async_block_till_done()
    await _minutes_pass(hass, freezer, 3)
    hass.states.async_set(XBOX_SENSOR, "")
    await hass.async_block_till_done()
    assert [(e["item"], e["minutes"]) for e in history.of("person.sam", kinds=(PLAYED,))] == [("Minecraft", 13)]


async def test_played_events_are_bounded(hass: HomeAssistant) -> None:
    history = History(hass, "test")
    assert not history.log_played("person.alex", "Blink", "tv", 0)
    for n in range(MAX_PLAYED + 5):
        history.log_played("person.alex", f"Game {n}", "tv", 2)
    assert len(history.of("person.alex", kinds=(PLAYED,))) == MAX_PLAYED
    # One already logged today still grows
    assert history.log_played("person.alex", "Game 0", "tv", 3)
    assert history.of("person.alex", kinds=(PLAYED,))[0]["minutes"] == 5


async def test_a_play_ends_at_the_last_look_that_saw_it(hass: HomeAssistant) -> None:
    live = LiveTracker(hass, "test")
    start = dt_util.now().replace(hour=12, minute=0, second=0, microsecond=0)
    seen = [Observation("person.sam", "tv", "Bluey", None, "Bluey")]
    for minute in range(6):
        live.look(start + timedelta(minutes=minute), start.date(), seen)
    assert live.since_of("person.sam", "tv", "Bluey") == dt_util.as_utc(start).isoformat()
    live.look(start + timedelta(minutes=6), start.date(), [])
    assert [(p.label, p.minutes) for p in live.ended_plays] == [("Bluey", 5)]
    # After a long gap (Home Assistant stopped), a play still on is a new one
    live.look(start + timedelta(minutes=7), start.date(), seen)
    live.look(start + timedelta(minutes=30), start.date(), seen)
    assert [p.minutes for p in live.ended_plays] == [0]
    assert live.since_of("person.sam", "tv", "Bluey") == dt_util.as_utc(start + timedelta(minutes=30)).isoformat()
