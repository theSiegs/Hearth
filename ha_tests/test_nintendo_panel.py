"""A kid's Switch on Hearth's page: what it shows of it (nintendo.py, the summary's first_party), what the installed
Nintendo integration can do, found at runtime, and the page's commands for Nintendo's own extra time and allow list."""

from datetime import timedelta

import pytest
import voluptuous as vol

from homeassistant.core import HomeAssistant, ServiceCall, SupportsResponse
from homeassistant.helpers import device_registry as dr, entity_registry as er
from homeassistant.util import dt as dt_util
from pytest_homeassistant_custom_component.common import MockConfigEntry
from pytest_homeassistant_custom_component.typing import ClientSessionGenerator

from custom_components.hearth import enforce
from custom_components.hearth.glance import person_glance
from test_enforce import _add_enforcer, _budget, _nintendo_services
from test_people import _household_with_sam

N = "nintendo_parental_controls"
LIMIT = "number.sam_s_switch_max_screentime_today"
SUSPEND = "switch.sam_s_switch_suspend_software"
PLAYED = "sensor.sam_s_switch_used_screen_time"
LEFT = "sensor.sam_s_switch_screen_time_remaining"
EXTRA = "sensor.sam_s_switch_extended_screen_time"
PLAYING = "binary_sensor.sam_s_switch_playing"
SAM_PLAYED = "sensor.sam_s_switch_sam_used_screen_time"
SAM_PLAYING = "binary_sensor.sam_s_switch_sam_playing"
ALEX_PLAYED = "sensor.sam_s_switch_alex_used_screen_time"
BEDTIME = "time.sam_s_switch_bedtime_alarm"
LAST_SYNC = "sensor.sam_s_switch_last_synced"


@pytest.fixture(autouse=True)
def settled(monkeypatch):
    monkeypatch.setattr(enforce, "SETTLE", timedelta(0))


def _switch(hass: HomeAssistant, *, limit="120", left="45", extra="0", played="75", last_sync=True) -> str:
    """A Switch as the Nintendo integration makes it, two players on it; its Home Assistant device id."""
    entry = MockConfigEntry(domain=N, title="Nintendo")
    entry.add_to_hass(hass)
    device = dr.async_get(hass).async_get_or_create(
        config_entry_id=entry.entry_id, identifiers={(N, "abc123")}, name="Sam's Switch"
    )
    registry = er.async_get(hass)
    rows = [
        (LIMIT, "abc123_today_max_screentime", limit),
        (SUSPEND, "abc123_suspend_software", "off"),
        ("select.sam_s_switch_restriction_mode", "abc123_timer_mode", "daily"),
        (PLAYED, "abc123_playing_time", played),
        (LEFT, "abc123_time_remaining", left),
        (EXTRA, "abc123_time_extended", extra),
        (PLAYING, "abc123_playing", "on"),
        (SAM_PLAYED, "abc123_p1_player_playing_time", "50"),
        (SAM_PLAYING, "abc123_p1_playing", "off"),
        (ALEX_PLAYED, "abc123_p2_player_playing_time", "25"),
        (BEDTIME, "abc123_bedtime_alarm", "21:30:00"),
    ]
    if last_sync:
        rows.append((LAST_SYNC, "abc123_last_sync", "2026-11-12T17:00:00+00:00"))
    for entity_id, unique_id, state in rows:
        domain, object_id = entity_id.split(".")
        registry.async_get_or_create(domain, N, unique_id, device_id=device.id, suggested_object_id=object_id)
        hass.states.async_set(entity_id, state)
    return device.id


def _core_services(hass: HomeAssistant) -> list[ServiceCall]:
    """Home Assistant's own Nintendo integration: add_bonus_time takes 5 to 30 minutes, nothing to cancel it."""
    calls: list[ServiceCall] = []

    async def add(call: ServiceCall) -> None:
        calls.append(call)

    hass.services.async_register(
        N, "add_bonus_time", add,
        schema=vol.Schema({vol.Required("device_id"): str, vol.Required("bonus_time"): vol.All(int, vol.Range(min=5, max=30))}),
    )
    return calls


def _patched_services(hass: HomeAssistant) -> list[ServiceCall]:
    """The patched copy: 5 to 360 or -1, cancel, and the allow list."""
    calls: list[ServiceCall] = []

    async def add(call: ServiceCall):
        calls.append(call)
        return {"extra_playing_time": call.data["bonus_time"]}

    async def cancel(call: ServiceCall):
        calls.append(call)
        return {"cancelled": True, "previous_extra_playing_time": 30}

    async def listing(call: ServiceCall):
        calls.append(call)
        return {
            "applications": [
                {"application_id": "0100B", "name": "Racing Game", "allowed": False, "image": "x"},
                {"application_id": "0100A", "name": "a Puzzle", "allowed": True, "image": "y"},
            ]
        }

    async def allowed(call: ServiceCall):
        calls.append(call)
        return {"application_id": call.data["application_id"], "allowed": call.data["allowed"], "changed": True}

    bonus = vol.Any(-1, vol.All(int, vol.Range(min=5, max=360)))
    hass.services.async_register(
        N, "add_bonus_time", add, schema=vol.Schema({vol.Required("device_id"): str, vol.Required("bonus_time"): bonus}),
        supports_response=SupportsResponse.OPTIONAL,
    )
    hass.services.async_register(N, "cancel_bonus_time", cancel, supports_response=SupportsResponse.OPTIONAL)
    hass.services.async_register(N, "list_applications", listing, supports_response=SupportsResponse.ONLY)
    hass.services.async_register(N, "set_app_allowed", allowed, supports_response=SupportsResponse.OPTIONAL)
    return calls


async def _ws(ws, message: dict):
    _ws.n = getattr(_ws, "n", 0) + 1
    await ws.send_json({"id": _ws.n, **message})
    return await ws.receive_json()


async def _sam_on_the_switch(hass, hass_client_no_auth, **switch) -> str:
    device_id = _switch(hass, **switch)
    await _household_with_sam(hass, hass_client_no_auth)
    await _add_enforcer(hass, {"kind": "nintendo", "person": "person.sam", "entity_id": LIMIT, "playing": [SAM_PLAYING]})
    return device_id


async def _sam(ws) -> dict:
    answer = await _ws(ws, {"type": "hearth/household"})
    return next(p for p in answer["result"]["people"] if p["id"] == "person.sam")


async def test_the_summary_shows_the_switch_s_own_limit_and_play(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator, hass_ws_client
) -> None:
    device_id = await _sam_on_the_switch(hass, hass_client_no_auth)
    ws = await hass_ws_client(hass)

    [switch] = (await _sam(ws))["first_party"]["nintendo"]
    assert switch["device_id"] == device_id
    assert switch["name"] == "Sam's Switch"
    assert switch["target"] == f"nintendo:{LIMIT}"
    assert switch["available"] is True
    assert (switch["played_minutes"], switch["player_minutes"]) == (75, 50)  # Sam's own player, not Alex's
    assert (switch["limit_minutes"], switch["minutes_left"], switch["extra_minutes"]) == (120, 45, 0)
    assert switch["suspended"] is False
    assert switch["playing"] is False  # Sam's player isn't playing; someone else is
    assert switch["bedtime"] == "21:30"
    assert switch["last_synced"] == "2026-11-12T17:00:00+00:00"
    assert switch["held_by_hearth"] is False and switch["blocking"] is False
    assert switch["entities"]["suspend_software"] == SUSPEND

    # Out of the Switch's own time, and no hold of Hearth's: Nintendo's own limit stops it
    hass.states.async_set(LEFT, "0")
    switch = (await _sam(ws))["first_party"]["nintendo"][0]
    assert switch["blocking"] is True
    sam = await _sam(ws)
    assert any("nintendo's own limit" in i["text"] for i in [sam["headline"], *sam["lines"]])

    # No limit on the Switch (-1): nothing to stop it, nothing left to count
    hass.states.async_set(LIMIT, "-1")
    switch = (await _sam(ws))["first_party"]["nintendo"][0]
    assert (switch["limit_minutes"], switch["minutes_left"], switch["blocking"]) == (None, None, False)


async def test_a_switch_that_is_only_a_source_shows_too(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator, hass_ws_client
) -> None:
    from test_sources import _option

    _switch(hass, last_sync=False)
    await _household_with_sam(hass, hass_client_no_auth)
    hass.states.async_set(SAM_PLAYED, "50", {"unit_of_measurement": "min"})
    await _option(hass, "add_source", {"entity_id": SAM_PLAYED, "person": "person.sam", "name": "Switch"})
    ws = await hass_ws_client(hass)
    [switch] = (await _sam(ws))["first_party"]["nintendo"]
    assert switch["target"] is None  # Hearth doesn't hold it: no extra time of Hearth's on it
    assert switch["player_minutes"] == 50
    assert switch["last_synced"] is None


async def test_what_the_page_offers_follows_the_installed_integration(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator, hass_ws_client
) -> None:
    await _household_with_sam(hass, hass_client_no_auth)
    ws = await hass_ws_client(hass)
    config = (await _ws(ws, {"type": "hearth/config"}))["result"]
    assert config["capabilities"]["nintendo"] == {
        "installed": False, "add_bonus": False, "bonus_min": None, "bonus_max": None, "unlimited": False,
        "cancel_bonus": False, "list_apps": False, "set_app_allowed": False,
    }
    assert config["parental_controls"] == []

    _switch(hass)
    _core_services(hass)
    config = (await _ws(ws, {"type": "hearth/config"}))["result"]
    caps = config["capabilities"]["nintendo"]
    assert caps["installed"] and caps["add_bonus"]
    assert (caps["bonus_min"], caps["bonus_max"], caps["unlimited"], caps["cancel_bonus"]) == (5, 30, False, False)
    assert config["parental_controls"][0]["name"] == "Nintendo Switch"
    assert config["parental_controls"][0]["entries"][0]["state"] == "not_loaded"

    hass.services.async_remove(N, "add_bonus_time")
    _patched_services(hass)
    caps = (await _ws(ws, {"type": "hearth/config"}))["result"]["capabilities"]["nintendo"]
    assert (caps["bonus_max"], caps["unlimited"], caps["cancel_bonus"]) == (360, True, True)
    assert caps["list_apps"] and caps["set_app_allowed"]


async def test_family_safety_s_connection_shows(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator, hass_ws_client
) -> None:
    await _household_with_sam(hass, hass_client_no_auth)
    entry = MockConfigEntry(domain="microsoft_family_safety", title="Family Safety")
    entry.add_to_hass(hass)
    er.async_get(hass).async_get_or_create(
        "sensor", "microsoft_family_safety", "conn", suggested_object_id="microsoft_family_safety_connection"
    )
    hass.states.async_set("sensor.microsoft_family_safety_connection", "degraded", {"reauth_required": False})
    ws = await hass_ws_client(hass)
    [row] = (await _ws(ws, {"type": "hearth/config"}))["result"]["parental_controls"]
    assert row["domain"] == "microsoft_family_safety"
    assert row["connection"] == {
        "entity_id": "sensor.microsoft_family_safety_connection", "state": "degraded", "reauth_required": False
    }


async def test_nintendo_s_own_extra_time_from_the_page(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator, hass_ws_client
) -> None:
    device_id = await _sam_on_the_switch(hass, hass_client_no_auth)
    calls = _core_services(hass)
    ws = await hass_ws_client(hass)
    sam = {"person": "person.sam", "device_id": device_id}

    answer = await _ws(ws, {"type": "hearth/nintendo/bonus", **sam, "minutes": 15})
    assert answer["success"], answer
    assert calls[-1].data == {"device_id": device_id, "bonus_time": 15}
    # Core takes 30 at most: refused before calling
    answer = await _ws(ws, {"type": "hearth/nintendo/bonus", **sam, "minutes": 60})
    assert answer["error"]["code"] == "not_supported"
    assert len(calls) == 1
    # Core can't cancel
    answer = await _ws(ws, {"type": "hearth/nintendo/bonus_cancel", **sam})
    assert answer["error"]["code"] == "not_supported"
    # Not Sam's Switch
    answer = await _ws(ws, {"type": "hearth/nintendo/bonus", "person": "person.sam", "device_id": "nope", "minutes": 15})
    assert answer["error"]["code"] == "not_found"

    hass.services.async_remove(N, "add_bonus_time")
    calls = _patched_services(hass)
    answer = await _ws(ws, {"type": "hearth/nintendo/bonus", **sam, "minutes": -1})
    assert answer["success"] and answer["result"] == {"extra_playing_time": -1}
    answer = await _ws(ws, {"type": "hearth/nintendo/bonus_cancel", **sam})
    assert answer["result"] == {"cancelled": True, "previous_extra_playing_time": 30}
    assert calls[-1].data == {"device_id": device_id}


async def test_no_nintendo_extra_while_hearth_holds_the_switch(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator, hass_ws_client, monkeypatch
) -> None:
    # Not the minutes before midnight, in which Hearth lets a Switch go (no frozen clock: the WebSocket's token)
    monkeypatch.setattr(enforce, "NINTENDO_LET_GO_BEFORE_MIDNIGHT", timedelta(0))
    device_id = _switch(hass)
    await _household_with_sam(hass, hass_client_no_auth)
    _nintendo_services(hass)
    await _add_enforcer(hass, {"kind": "nintendo", "person": "person.sam", "entity_id": LIMIT})
    calls = _patched_services(hass)
    await _budget(hass, "games", 5)  # Sam's games are out: Hearth holds the Switch
    ws = await hass_ws_client(hass)
    assert (await _sam(ws))["first_party"]["nintendo"][0]["held_by_hearth"] is True

    answer = await _ws(ws, {"type": "hearth/nintendo/bonus", "person": "person.sam", "device_id": device_id, "minutes": 15})
    assert answer["error"]["code"] == "held"
    assert calls == []


async def test_the_switch_s_allow_list_from_the_page(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator, hass_ws_client
) -> None:
    device_id = await _sam_on_the_switch(hass, hass_client_no_auth)
    ws = await hass_ws_client(hass)
    sam = {"person": "person.sam", "device_id": device_id}

    answer = await _ws(ws, {"type": "hearth/nintendo/apps", **sam})
    assert answer["error"]["code"] == "not_supported"

    calls = _patched_services(hass)
    answer = await _ws(ws, {"type": "hearth/nintendo/apps", **sam})
    assert answer["result"]["applications"] == [
        {"application_id": "0100A", "name": "a Puzzle", "allowed": True},
        {"application_id": "0100B", "name": "Racing Game", "allowed": False},
    ]
    answer = await _ws(ws, {"type": "hearth/nintendo/app_allowed", **sam, "application_id": "0100B", "allowed": True})
    assert answer["success"] and answer["result"]["changed"] is True
    assert calls[-1].data == {"device_id": device_id, "application_id": "0100B", "allowed": True}


def test_a_switch_s_own_limit_is_a_line_of_its_own() -> None:
    person = {
        "id": "person.sam", "groups": [], "first_party": {"nintendo": [{"name": "Sam's Switch", "blocking": True,
                                                                         "device_id": "d1"}]},
    }
    glance = person_glance(person, [], [], [], dt_util.now(), [], [])
    assert any(i["text"] == "sam's switch · nintendo's own limit" for i in [glance["headline"], *glance["lines"]])
