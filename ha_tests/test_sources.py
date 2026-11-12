"""Screen time sources (totals and live), titles, and playing together."""

from datetime import timedelta

from homeassistant.core import HomeAssistant
from homeassistant.data_entry_flow import FlowResultType
from homeassistant.helpers import device_registry as dr, entity_registry as er
from homeassistant.util import dt as dt_util
from pytest_homeassistant_custom_component.common import (
    MockConfigEntry,
    async_capture_events,
    async_fire_time_changed,
)
from pytest_homeassistant_custom_component.typing import ClientSessionGenerator

from custom_components.hearth.const import DOMAIN
from custom_components.hearth.sources import Source, normalize, totals_reading
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


def _family_safety_child(hass: HomeAssistant, account: str = "123456") -> tuple[str, str, str]:
    """A Family Safety child as upstream's integration has it: Screen Time, Xbox Screen Time and Applications sensors
    on the child's account device (no `apps` attribute anywhere)."""
    fs_entry = MockConfigEntry(domain="microsoft_family_safety")
    fs_entry.add_to_hass(hass)
    device = dr.async_get(hass).async_get_or_create(
        config_entry_id=fs_entry.entry_id, identifiers={("microsoft_family_safety", account)}
    )
    registry = er.async_get(hass)
    found = [
        registry.async_get_or_create(
            "sensor",
            "microsoft_family_safety",
            f"{fs_entry.entry_id}_{account}_{key}",
            suggested_object_id=name,
            config_entry=fs_entry,
            device_id=device.id,
        ).entity_id
        for key, name in (("screentime", "sam_screen_time"), ("xbox_screentime", "sam_xbox_screen_time"), ("app_count", "sam_applications"))
    ]
    return found[0], found[1], found[2]


def _applications(racing_minutes: float) -> list[dict]:
    return [
        {"app_id": "x:1111", "app_name": "Racing Game", "blocked": False, "icon": "https://example.com/r.png", "usage_minutes": racing_minutes},
        {"app_id": "appx:Example.Paint", "app_name": "Paint", "blocked": False, "icon": None, "usage_minutes": 5.0},
        {"app_id": "win32:notepad.exe", "app_name": "Notepad", "blocked": True, "icon": None, "usage_minutes": 0},
    ]


async def test_a_family_safety_screen_time_takes_its_apps_from_the_applications_sensor(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator
) -> None:
    await _household_with_sam(hass, hass_client_no_auth)
    screen, xbox, applications = _family_safety_child(hass)
    hass.states.async_set(applications, "3", {"blocked_count": 1, "applications": _applications(25.0)})
    hass.states.async_set(screen, "30", {"unit_of_measurement": "min", "user_id": "123456"})
    hass.states.async_set(xbox, "25", {"unit_of_measurement": "min", "user_id": "123456"})
    entry = hass.config_entries.async_entries(DOMAIN)[0]
    hass.config_entries.async_update_entry(entry, options={**entry.options, "app_groups": {"x:1111": "games"}})
    await hass.async_block_till_done()
    await _option(hass, "add_source", {"entity_id": screen, "person": "person.sam", "name": "Sam's PC and Xbox"})

    # TV: 15 minutes (5 of them a game); Family Safety: 30, 25 of them the racing game, by its Microsoft app id
    assert _state(hass, "sensor.hearth_sam_screen_time_today") == "45"
    assert _state(hass, "sensor.hearth_sam_games_today") == "30"
    reading = totals_reading(hass, Source("fs", screen, "person.sam", "Sam's PC and Xbox"))
    assert reading.items == {"x:1111": 1500.0, "appx:Example.Paint": 300.0}
    # The Xbox Screen Time sensor's: the Xbox's apps only
    assert totals_reading(hass, Source("x", xbox, "person.sam", "Xbox")).items == {"x:1111": 1500.0}

    # The Applications sensor's change counts at once
    hass.states.async_set(applications, "3", {"blocked_count": 1, "applications": _applications(28.0)})
    await hass.async_block_till_done()
    assert _state(hass, "sensor.hearth_sam_games_today") == "33"

    # An apps attribute (the fork's, Family Link's) still says it
    hass.states.async_set(
        screen, "30", {"unit_of_measurement": "min", "user_id": "123456", "apps": [{"package": "x:1111", "minutes": 10}]}
    )
    await hass.async_block_till_done()
    assert totals_reading(hass, Source("fs", screen, "person.sam", "n")).items == {"x:1111": 600.0}
    assert _state(hass, "sensor.hearth_sam_games_today") == "33"  # today's count never goes down

    # Another sensor without apps has no breakdown
    hass.states.async_set(SWITCH_SENSOR, "50", {"unit_of_measurement": "min"})
    assert totals_reading(hass, Source("sw", SWITCH_SENSOR, "person.sam", "n")).items == {}


async def test_the_app_pickers_offer_a_family_safety_child_s_applications(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator
) -> None:
    from test_enforce import _add_enforcer

    await _household_with_sam(hass, hass_client_no_auth)
    screen, _xbox, applications = _family_safety_child(hass)
    hass.states.async_set(screen, "30", {"unit_of_measurement": "min", "user_id": "123456"})
    hass.states.async_set(applications, "3", {"applications": _applications(25.0)})
    await _add_enforcer(
        hass, {"kind": "family_safety", "person": "person.sam", "entity_id": screen, "platforms": ["Xbox", "Windows"]}
    )
    known = hass.config_entries.async_entries(DOMAIN)[0].runtime_data.household.known_apps()
    assert known["x:1111"] == "Racing Game (Xbox)"
    assert known["win32:notepad.exe"] == "Notepad (Windows)"


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


async def test_a_parent_lets_a_person_share_with_the_tile_exchange(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator
) -> None:
    client, secret = await _household_with_sam(hass, hass_client_no_auth)
    from test_people import KID, _tv_status
    from test_init import _post

    body = await (await _post(client, secret, body=_tv_status(hearthtube_s=60))).json()
    assert body["state"]["profiles"][KID]["tile_exchange_share"] is False

    await _option(hass, "tile_exchange", {"people": ["person.sam"]})
    body = await (await _post(client, secret, body=_tv_status(hearthtube_s=60))).json()
    assert body["state"]["profiles"][KID]["tile_exchange_share"] is True
