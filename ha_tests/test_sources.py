"""Screen time sources (totals and live), titles, and playing together."""

from datetime import timedelta

from homeassistant.core import HomeAssistant
from homeassistant.data_entry_flow import FlowResultType
from homeassistant.util import dt as dt_util
from pytest_homeassistant_custom_component.common import async_capture_events, async_fire_time_changed
from pytest_homeassistant_custom_component.typing import ClientSessionGenerator

from custom_components.hearth.const import DOMAIN
from custom_components.hearth.sources import normalize
from test_init import TV_ID
from test_people import _household_with_sam

PHONE_SENSOR = "sensor.sam_phone_daily_screen_time"
SWITCH_SENSOR = "sensor.sam_switch_used_screen_time"
XBOX_SENSOR = "sensor.sam_now_playing"
ALEX_SWITCH = "sensor.alex_switch_game"


async def _option(hass: HomeAssistant, step: str, data: dict) -> None:
    entry = hass.config_entries.async_entries(DOMAIN)[0]
    result = await hass.config_entries.options.async_init(entry.entry_id)
    result = await hass.config_entries.options.async_configure(result["flow_id"], {"next_step_id": step})
    assert result["type"] is FlowResultType.FORM, result
    result = await hass.config_entries.options.async_configure(result["flow_id"], data)
    assert result["type"] is FlowResultType.CREATE_ENTRY, result
    await hass.async_block_till_done()


def _state(hass: HomeAssistant, entity_id: str) -> str:
    return hass.states.get(entity_id).state


async def test_a_totals_source_with_apps(hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator) -> None:
    await _household_with_sam(hass, hass_client_no_auth)
    hass.states.async_set(
        PHONE_SENSOR,
        "45",
        {"unit_of_measurement": "min", "apps": [{"package": "com.example.game", "name": "Game", "minutes": 30}]},
    )
    await _option(hass, "add_source", {"entity_id": PHONE_SENSOR, "person": "person.sam", "name": "Sam's phone"})

    # TV: 15 minutes (10 HearthTube, 5 game); phone: 45 (30 of them the same game)
    assert _state(hass, "sensor.hearth_sam_screen_time_today") == "60"
    assert _state(hass, "sensor.hearth_sam_games_today") == "35"
    devices = hass.states.get("sensor.hearth_sam_screen_time_today").attributes["devices"]
    assert devices["Sam's phone"]["minutes"] == 45

    # It follows the sensor
    hass.states.async_set(PHONE_SENSOR, "1.5", {"unit_of_measurement": "h"})
    await hass.async_block_till_done()
    assert _state(hass, "sensor.hearth_sam_screen_time_today") == "105"


async def test_the_same_device_counts_once(hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator) -> None:
    await _household_with_sam(hass, hass_client_no_auth)
    # Family Link's view of the TV profile: 12 minutes, less than Hearth's 15
    hass.states.async_set("sensor.sam_tv_daily_screen_time", "12", {"unit_of_measurement": "min"})
    await _option(
        hass,
        "add_source",
        {"entity_id": "sensor.sam_tv_daily_screen_time", "person": "person.sam", "same_as": f"hearth:{TV_ID}"},
    )
    assert _state(hass, "sensor.hearth_sam_screen_time_today") == "15"
    hass.states.async_set("sensor.sam_tv_daily_screen_time", "40", {"unit_of_measurement": "min"})
    await hass.async_block_till_done()
    assert _state(hass, "sensor.hearth_sam_screen_time_today") == "40"


async def test_a_switch_s_time_is_games(hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator) -> None:
    await _household_with_sam(hass, hass_client_no_auth)
    hass.states.async_set(SWITCH_SENSOR, "50", {"unit_of_measurement": "min"})
    await _option(hass, "add_source", {"entity_id": SWITCH_SENSOR, "person": "person.sam", "group": "games"})
    assert _state(hass, "sensor.hearth_sam_games_today") == "55"
    assert _state(hass, "sensor.hearth_sam_screen_time_today") == "65"


async def test_a_source_that_s_not_a_number_counts_nothing(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator
) -> None:
    await _household_with_sam(hass, hass_client_no_auth)
    hass.states.async_set(SWITCH_SENSOR, "unavailable")
    await _option(hass, "add_source", {"entity_id": SWITCH_SENSOR, "person": "person.sam", "group": "games"})
    assert _state(hass, "sensor.hearth_sam_screen_time_today") == "15"


async def test_a_sensor_is_added_once(hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator) -> None:
    await _household_with_sam(hass, hass_client_no_auth)
    hass.states.async_set(SWITCH_SENSOR, "5", {"unit_of_measurement": "min"})
    await _option(hass, "add_source", {"entity_id": SWITCH_SENSOR, "person": "person.sam"})
    entry = hass.config_entries.async_entries(DOMAIN)[0]
    result = await hass.config_entries.options.async_init(entry.entry_id)
    result = await hass.config_entries.options.async_configure(result["flow_id"], {"next_step_id": "add_source"})
    result = await hass.config_entries.options.async_configure(
        result["flow_id"], {"entity_id": SWITCH_SENSOR, "person": "person.sam"}
    )
    assert result["errors"] == {"entity_id": "already_added"}


async def _minutes_pass(hass: HomeAssistant, freezer, minutes: int) -> None:
    for _ in range(minutes):
        freezer.tick(timedelta(minutes=1))
        async_fire_time_changed(hass, dt_util.utcnow())
        await hass.async_block_till_done()


async def test_live_play_is_timed(hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator, freezer) -> None:
    freezer.move_to(dt_util.now().replace(hour=12, minute=0))
    await _household_with_sam(hass, hass_client_no_auth)
    hass.states.async_set(XBOX_SENSOR, "")
    await _option(
        hass, "add_source", {"entity_id": XBOX_SENSOR, "person": "person.sam", "live": True, "group": "games"}
    )
    hass.states.async_set(XBOX_SENSOR, "Minecraft")
    await hass.async_block_till_done()
    assert _state(hass, "sensor.hearth_sam_playing") in ("Minecraft", "HearthTube")
    await _minutes_pass(hass, freezer, 10)
    assert _state(hass, "sensor.hearth_sam_games_today") == "15"  # 5 on the TV, 10 on the Xbox
    hass.states.async_set(XBOX_SENSOR, "")
    await _minutes_pass(hass, freezer, 5)
    assert _state(hass, "sensor.hearth_sam_games_today") == "15"


async def test_playing_together(hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator, freezer) -> None:
    freezer.move_to(dt_util.now().replace(hour=12, minute=0))
    await _household_with_sam(hass, hass_client_no_auth)
    hass.states.async_set("person.alex", "home", {"friendly_name": "Alex"})
    hass.states.async_set(XBOX_SENSOR, "")
    hass.states.async_set(ALEX_SWITCH, "")
    await _option(hass, "add_source", {"entity_id": XBOX_SENSOR, "person": "person.sam", "live": True})
    await _option(hass, "add_source", {"entity_id": ALEX_SWITCH, "person": "person.alex", "live": True})
    await _option(
        hass, "add_title", {"name": "Minecraft", "matches": ["Minecraft for Nintendo Switch", "com.mojang.minecraftpe"]}
    )
    events = async_capture_events(hass, "hearth_playing_together")
    assert _state(hass, "binary_sensor.hearth_home_playing_together") == "off"

    hass.states.async_set(XBOX_SENSOR, "Minecraft")
    hass.states.async_set(ALEX_SWITCH, "Minecraft for Nintendo Switch")
    await hass.async_block_till_done()
    together = hass.states.get("binary_sensor.hearth_home_playing_together")
    assert together.state == "on"
    assert together.attributes["together"][0]["title"] == "Minecraft"
    assert together.attributes["together"][0]["people"] == ["Alex", "Sam"]
    assert [e.data["event"] for e in events] == ["started"]

    await _minutes_pass(hass, freezer, 20)
    assert _state(hass, "sensor.hearth_sam_playing_together_today") == "20"
    assert _state(hass, "sensor.hearth_alex_playing_together_today") == "20"

    hass.states.async_set(ALEX_SWITCH, "")
    await hass.async_block_till_done()
    assert _state(hass, "binary_sensor.hearth_home_playing_together") == "off"
    assert [e.data["event"] for e in events] == ["started", "ended"]


def test_names_match_across_stores():
    assert normalize("Minecraft: Java Edition") == normalize("Minecraft™")
    assert normalize("Minecraft for Nintendo Switch") == "minecraft"


async def test_a_lock_holds_the_person(hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator) -> None:
    client, secret = await _household_with_sam(hass, hass_client_no_auth)
    hass.states.async_set("binary_sensor.sam_tablet_bedtime_active", "off")
    hass.states.async_set("binary_sensor.sam_phone_school_time_active", "off")
    await _option(
        hass,
        "locks",
        {
            "person": "person.sam",
            "entities": ["binary_sensor.sam_tablet_bedtime_active", "binary_sensor.sam_phone_school_time_active"],
        },
    )
    assert _state(hass, "binary_sensor.hearth_sam_locked") == "off"

    hass.states.async_set("binary_sensor.sam_tablet_bedtime_active", "on")
    await hass.async_block_till_done()
    locked = hass.states.get("binary_sensor.hearth_sam_locked")
    assert locked.state == "on"
    assert locked.attributes["locked_by"] == ["binary_sensor.sam_tablet_bedtime_active"]

    from test_people import KID, _tv_status
    from test_init import _post

    body = await (await _post(client, secret, body=_tv_status(hearthtube_s=60))).json()
    assert body["state"]["profiles"][KID]["locked"] is True


async def test_all_screen_time_is_every_device_and_source(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator, freezer
) -> None:
    """The TV (HearthTube among its apps), a Family Link phone, Family Safety, a Switch and a live Xbox: added up."""
    freezer.move_to(dt_util.now().replace(hour=12, minute=0))
    await _household_with_sam(hass, hass_client_no_auth)
    hass.states.async_set(
        PHONE_SENSOR, "45", {"unit_of_measurement": "min", "apps": [{"package": "com.example.chat", "minutes": 45}]}
    )
    hass.states.async_set("sensor.sam_screen_time", "20", {"unit_of_measurement": "min"})
    hass.states.async_set(SWITCH_SENSOR, "30", {"unit_of_measurement": "min"})
    hass.states.async_set(XBOX_SENSOR, "")
    await _option(hass, "add_source", {"entity_id": PHONE_SENSOR, "person": "person.sam"})
    await _option(hass, "add_source", {"entity_id": "sensor.sam_screen_time", "person": "person.sam"})
    await _option(hass, "add_source", {"entity_id": SWITCH_SENSOR, "person": "person.sam", "group": "games"})
    await _option(
        hass, "add_source", {"entity_id": XBOX_SENSOR, "person": "person.sam", "live": True, "group": "games"}
    )
    hass.states.async_set(XBOX_SENSOR, "Halo")
    await hass.async_block_till_done()
    await _minutes_pass(hass, freezer, 10)

    # 15 + 45 + 20 + 30 + 10
    assert _state(hass, "sensor.hearth_sam_screen_time_today") == "120"
    assert _state(hass, "sensor.hearth_sam_games_today") == "45"  # 5 on the TV, the Switch, the Xbox
    assert len(hass.states.get("sensor.hearth_sam_screen_time_today").attributes["devices"]) == 5


async def test_screen_time_today_never_goes_down_during_the_day(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator
) -> None:
    """Total increasing: a source's number corrected down a minute isn't a reset for the recorder."""
    await _household_with_sam(hass, hass_client_no_auth)
    hass.states.async_set(PHONE_SENSOR, "45", {"unit_of_measurement": "min"})
    await _option(hass, "add_source", {"entity_id": PHONE_SENSOR, "person": "person.sam", "group": "games"})
    assert _state(hass, "sensor.hearth_sam_screen_time_today") == "60"
    assert _state(hass, "sensor.hearth_sam_games_today") == "50"

    hass.states.async_set(PHONE_SENSOR, "44", {"unit_of_measurement": "min"})
    await hass.async_block_till_done()
    total = hass.states.get("sensor.hearth_sam_screen_time_today")
    assert total.state == "60"
    assert total.attributes["groups"]["all"] == 59  # what's counted
    assert _state(hass, "sensor.hearth_sam_games_today") == "50"

    hass.states.async_set(PHONE_SENSOR, "50", {"unit_of_measurement": "min"})
    await hass.async_block_till_done()
    assert _state(hass, "sensor.hearth_sam_screen_time_today") == "65"


async def test_an_unavailable_source_keeps_its_last_count_today(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator
) -> None:
    await _household_with_sam(hass, hass_client_no_auth)
    hass.states.async_set(SWITCH_SENSOR, "30", {"unit_of_measurement": "min"})
    await _option(hass, "add_source", {"entity_id": SWITCH_SENSOR, "person": "person.sam", "group": "games"})
    hass.states.async_set(SWITCH_SENSOR, "unavailable")
    await hass.async_block_till_done()
    total = hass.states.get("sensor.hearth_sam_screen_time_today")
    assert total.attributes["groups"]["all"] == 45
    assert total.attributes["groups"]["games"] == 35


async def test_screen_time_today_is_kept_over_a_restart(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator
) -> None:
    await _household_with_sam(hass, hass_client_no_auth)
    hass.states.async_set(SWITCH_SENSOR, "30", {"unit_of_measurement": "min"})
    await _option(hass, "add_source", {"entity_id": SWITCH_SENSOR, "person": "person.sam", "group": "games"})
    assert _state(hass, "sensor.hearth_sam_screen_time_today") == "45"

    # Back with the Switch's sensor not reporting yet: what was shown today stays
    hass.states.async_set(SWITCH_SENSOR, "unavailable")
    entry = hass.config_entries.async_entries(DOMAIN)[0]
    assert await hass.config_entries.async_reload(entry.entry_id)
    await hass.async_block_till_done()
    total = hass.states.get("sensor.hearth_sam_screen_time_today")
    assert total.attributes["groups"]["all"] < 45
    assert total.state == "45"
