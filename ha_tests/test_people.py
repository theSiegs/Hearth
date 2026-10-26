"""People: who each TV profile and phone is, their screen time today, budgets, bonuses, and what devices are told."""

from homeassistant.core import HomeAssistant
from homeassistant.data_entry_flow import FlowResultType
from homeassistant.util import dt as dt_util
from pytest_homeassistant_custom_component.common import async_capture_events
from pytest_homeassistant_custom_component.typing import ClientSessionGenerator

from custom_components.hearth.const import DOMAIN
from test_init import NONCE, PHONE_ID, _pair, _post, _set_up

KID = "user:10"


def _today() -> str:
    return dt_util.now().date().isoformat()


def _tv_status(hearthtube_s: int = 0, game_s: int = 0, playing: str | None = None) -> dict:
    apps = {}
    if hearthtube_s:
        apps["com.thesiegs.hearthtube"] = hearthtube_s
    if game_s:
        apps["com.example.game"] = game_s
    return {
        "screen": "on",
        "state": "playing" if playing else "idle",
        "app": "HearthTube" if playing else None,
        "app_package": playing,
        "profile": "Sam",
        "profile_id": KID,
        "kids_profile": True,
        "day": _today(),
        "seconds_today": hearthtube_s + game_s,
        "app_categories": {"com.example.game": "game"},
        "usage_today": {
            KID: {"profile_name": "Sam", "seconds": hearthtube_s + game_s, "apps": apps},
            "user:0": {"profile_name": "Owner", "seconds": 60, "apps": {"com.example.news": 60}},
        },
    }


async def _household_with_sam(hass: HomeAssistant, hass_client_no_auth):
    hass.states.async_set("person.sam", "home", {"friendly_name": "Sam"})
    entry = await _set_up(hass)
    client = await hass_client_no_auth()
    secret = await _pair(hass, client)
    assert (await _post(client, secret, body=_tv_status(hearthtube_s=600, game_s=300))).status == 200
    await hass.async_block_till_done()

    result = await hass.config_entries.options.async_init(entry.entry_id)
    assert result["type"] is FlowResultType.MENU
    result = await hass.config_entries.options.async_configure(result["flow_id"], {"next_step_id": "people"})
    assert result["type"] is FlowResultType.FORM
    labels = [str(key) for key in result["data_schema"].schema]
    assert "Sam (user:10)" in labels and "Owner (user:0)" in labels
    result = await hass.config_entries.options.async_configure(result["flow_id"], {"Sam (user:10)": "person.sam"})
    assert result["type"] is FlowResultType.CREATE_ENTRY
    await hass.async_block_till_done()
    return client, secret


async def test_a_profile_s_time_counts_for_its_person(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator
) -> None:
    await _household_with_sam(hass, hass_client_no_auth)

    total = hass.states.get("sensor.hearth_sam_screen_time_today")
    assert total.state == "15"
    assert total.attributes["devices"]["Kitchen"]["minutes"] == 15
    assert hass.states.get("sensor.hearth_sam_video_today").state == "10"
    assert hass.states.get("sensor.hearth_sam_games_today").state == "5"
    # Unmapped profiles count for nobody
    assert hass.states.get("sensor.hearth_owner_screen_time_today") is None


async def test_budget_minutes_left_and_reached(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator
) -> None:
    client, secret = await _household_with_sam(hass, hass_client_no_auth)
    reached = async_capture_events(hass, "hearth_budget_reached")

    await hass.services.async_call(
        DOMAIN, "set_budget", {"person": "person.sam", "group": "video", "minutes": 30}, blocking=True
    )
    await hass.async_block_till_done()
    assert hass.states.get("sensor.hearth_sam_video_minutes_left").state == "20"

    response = await _post(client, secret, body=_tv_status(hearthtube_s=1900, playing="com.thesiegs.hearthtube"))
    body = await response.json()
    await hass.async_block_till_done()
    assert hass.states.get("sensor.hearth_sam_video_minutes_left").state == "0"
    assert len(reached) == 1
    assert reached[0].data["person"] == "person.sam"
    assert reached[0].data["group"] == "video"
    assert hass.states.get("sensor.hearth_sam_playing").state == "HearthTube"

    # The TV is told, per profile
    video = body["state"]["profiles"][KID]["groups"]
    assert video[0]["id"] == "video"
    assert video[0]["minutes_left"] == 0
    assert "com.thesiegs.hearthtube" in video[0]["apps"]
    assert "user:0" not in body["state"]["profiles"]

    # Posting again doesn't fire it again
    await _post(client, secret, body=_tv_status(hearthtube_s=1950))
    await hass.async_block_till_done()
    assert len(reached) == 1

    # A bonus opens it again
    await hass.services.async_call(
        DOMAIN, "add_bonus", {"person": "person.sam", "group": "video", "minutes": 15}, blocking=True
    )
    await hass.async_block_till_done()
    assert hass.states.get("sensor.hearth_sam_video_minutes_left").state == "12"
    assert hass.states.get("number.hearth_sam_video_bonus_today").state == "15"


async def test_budget_numbers(hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator) -> None:
    await _household_with_sam(hass, hass_client_no_auth)
    weekday = "number.hearth_sam_games_budget_on_weekdays"
    assert hass.states.get(weekday).state == "-1"
    await hass.services.async_call("number", "set_value", {"entity_id": weekday, "value": 90}, blocking=True)
    await hass.services.async_call(
        "number", "set_value", {"entity_id": "number.hearth_sam_games_budget_at_weekends", "value": 120}, blocking=True
    )
    await hass.async_block_till_done()
    assert hass.states.get(weekday).state == "90"
    expected = "85" if dt_util.now().weekday() < 5 else "115"
    assert hass.states.get("sensor.hearth_sam_games_minutes_left").state == expected


async def test_unknown_person_or_group_is_refused(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator
) -> None:
    import pytest
    from homeassistant.exceptions import ServiceValidationError

    await _household_with_sam(hass, hass_client_no_auth)
    with pytest.raises(ServiceValidationError):
        await hass.services.async_call(
            DOMAIN, "add_bonus", {"person": "person.nobody", "minutes": 15}, blocking=True
        )
    with pytest.raises(ServiceValidationError):
        await hass.services.async_call(
            DOMAIN, "add_bonus", {"person": "person.sam", "group": "nope", "minutes": 15}, blocking=True
        )


async def test_a_group_of_one_s_own(hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator) -> None:
    await _household_with_sam(hass, hass_client_no_auth)
    entry = hass.config_entries.async_entries(DOMAIN)[0]

    result = await hass.config_entries.options.async_init(entry.entry_id)
    result = await hass.config_entries.options.async_configure(result["flow_id"], {"next_step_id": "add_group"})
    result = await hass.config_entries.options.async_configure(
        result["flow_id"], {"name": "YouTube", "apps": ["com.thesiegs.hearthtube"]}
    )
    assert result["type"] is FlowResultType.CREATE_ENTRY
    await hass.async_block_till_done()

    assert hass.states.get("sensor.hearth_sam_youtube_today").state == "10"
    # The same name again is refused
    result = await hass.config_entries.options.async_init(entry.entry_id)
    result = await hass.config_entries.options.async_configure(result["flow_id"], {"next_step_id": "add_group"})
    result = await hass.config_entries.options.async_configure(result["flow_id"], {"name": "youtube"})
    assert result["errors"] == {"name": "name_taken"}


async def test_a_phone_counts_for_its_person(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator
) -> None:
    hass.states.async_set("person.sam", "home", {"friendly_name": "Sam"})
    await _set_up(hass)
    client = await hass_client_no_auth()
    response = await client.post(
        "/api/hearth/pair", json={"device_id": PHONE_ID, "kind": "mobile", "name": "Sam's phone", "nonce": NONCE}
    )
    pairing_id = (await response.json())["pairing_id"]
    await hass.async_block_till_done()
    flow = hass.config_entries.flow.async_progress_by_handler(DOMAIN)[0]
    result = await hass.config_entries.flow.async_configure(flow["flow_id"], {"person": "person.sam"})
    assert result["reason"] == "paired"
    await hass.async_block_till_done()
    secret = (await (await client.get(f"/api/hearth/pair/{pairing_id}", headers={"X-Hearth-Nonce": NONCE})).json())[
        "secret"
    ]

    status = {"screen": "on", "day": _today(), "seconds_today": 1200, "app_seconds_today": {"com.example.game": 1200},
              "app_categories": {"com.example.game": "game"}}
    response = await _post(client, secret, body=status, device_id=PHONE_ID)
    body = await response.json()
    await hass.async_block_till_done()
    assert hass.states.get("sensor.hearth_sam_games_today").state == "20"
    assert body["state"]["person"]["person"] == "person.sam"


async def test_yesterday_s_counts_don_t_count_today(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator
) -> None:
    client, secret = await _household_with_sam(hass, hass_client_no_auth)
    stale = {**_tv_status(hearthtube_s=3000), "day": "2000-01-01"}
    await _post(client, secret, body=stale)
    await hass.async_block_till_done()
    assert hass.states.get("sensor.hearth_sam_screen_time_today").state == "0"



async def test_the_bonus_ends_at_midnight(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator, freezer
) -> None:
    from datetime import timedelta

    from pytest_homeassistant_custom_component.common import async_fire_time_changed

    await _household_with_sam(hass, hass_client_no_auth)
    await hass.services.async_call(
        DOMAIN, "add_bonus", {"person": "person.sam", "group": "games", "minutes": 30}, blocking=True
    )
    await hass.async_block_till_done()
    assert hass.states.get("number.hearth_sam_games_bonus_today").state == "30"

    tomorrow = (dt_util.now() + timedelta(days=1)).replace(hour=0, minute=0, second=5)
    freezer.move_to(tomorrow)
    async_fire_time_changed(hass, tomorrow)
    await hass.async_block_till_done()
    assert hass.states.get("number.hearth_sam_games_bonus_today").state == "0"
    # Yesterday's TV counts are yesterday's
    assert hass.states.get("sensor.hearth_sam_screen_time_today").state == "0"
