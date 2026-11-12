"""A person's devices for an adult's app: targets, minutes per device and per app, and extra time on one device."""

import pytest

from homeassistant.core import HomeAssistant, ServiceCall, SupportsResponse
from homeassistant.exceptions import ServiceValidationError
from homeassistant.util import dt as dt_util
from pytest_homeassistant_custom_component.common import async_mock_service
from pytest_homeassistant_custom_component.typing import ClientSessionGenerator

from custom_components.hearth.const import DOMAIN
from custom_components.hearth.websocket import summary
from test_enforce import (
    FAMILY_SAFETY,
    NINTENDO_LIMIT,
    _budget,
    _nintendo_services,
    _nintendo_switch,
    settled,  # noqa: F401 - the fixture
)
from test_init import TV_ID, _post
from test_native_sync import PHONE, _phone, _remaining, _sam_with_family_link
from test_people import KID, _household_with_sam, _tv_status
from test_sources import _option

FL_PHONE = "sensor.sam_pixel_daily_screen_time"
TV = f"hearth:{TV_ID}"


def _hub(hass: HomeAssistant):
    return hass.config_entries.async_entries(DOMAIN)[0].runtime_data


def _sam(hass: HomeAssistant) -> dict:
    return next(p for p in summary(_hub(hass))["people"] if p["id"] == "person.sam")


async def test_minutes_by_device_and_by_app(hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator) -> None:
    await _household_with_sam(hass, hass_client_no_auth)
    # A Family Link device's own Daily screen time sensor: that device
    hass.states.async_set(
        FL_PHONE,
        "45",
        {
            "unit_of_measurement": "min",
            "child_id": "42",
            "device_id": "d1",
            "device_name": "Pixel",
            "apps": [{"package": "com.example.game", "name": "Game", "minutes": 30}],
        },
    )
    await _option(hass, "add_source", {"entity_id": FL_PHONE, "person": "person.sam", "name": "Sam's phone"})

    sam = _sam(hass)
    assert sam["devices_today"] == [
        {"target": "fl:d1", "name": "Sam's phone", "minutes": 45},
        {"target": TV, "name": "Kitchen TV", "minutes": 15},
    ]
    apps = {a["package"]: a["minutes"] for a in sam["apps_today"]}
    assert apps == {"com.example.game": 35, "com.thesiegs.hearthtube": 10}


# Extra time on one device


async def _device_bonus(hass: HomeAssistant, device: str, minutes: int, group: str = "all") -> None:
    await hass.services.async_call(
        DOMAIN, "add_bonus", {"person": "person.sam", "minutes": minutes, "group": group, "device": device}, blocking=True
    )
    await hass.async_block_till_done()


def _all_left(document: dict) -> int:
    return next(g for g in document["groups"] if g["id"] == "all")["minutes_left"]


async def test_extra_time_on_a_hearth_tv_counts_down_there_and_nowhere_else(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator
) -> None:
    client, secret = await _household_with_sam(hass, hass_client_no_auth)
    household = _hub(hass).household
    await _budget(hass, "all", 15)  # 15 used: out
    assert {t["id"]: t["groups"] for t in _sam(hass)["targets"]} == {TV: True}

    await _device_bonus(hass, TV, 30)
    body = await (await _post(client, secret, body=_tv_status(hearthtube_s=600, game_s=300))).json()
    assert _all_left(body["state"]["profiles"][KID]) == 30
    # Any other device of Sam's reads the pool: out
    assert _all_left(household._person_document("person.sam")) == 0
    assert _sam(hass)["all"]["minutes_left"] == 0

    # Ten more minutes on the TV: 20 left there
    body = await (await _post(client, secret, body=_tv_status(hearthtube_s=1200, game_s=300))).json()
    assert _all_left(body["state"]["profiles"][KID]) == 20
    sam = _sam(hass)
    [extra] = sam["device_extras"]
    assert extra["target"] == TV and extra["kind"] == "bonus" and extra["minutes_left"] == 20
    assert any(
        line["key"] == f"device_bonus:{TV}" and line["text"] == "kitchen tv · 20 left there"
        for line in [sam["headline"], *sam["lines"]]
    )
    [end] = [a for a in sam["actions"] if a["id"] == f"device_bonus_end:{TV}"]
    assert end["service"] == "hearth.allow_end" and end["data"] == {"people": ["person.sam"], "device": TV}
    why = await hass.services.async_call(
        DOMAIN, "explain", {"person": "person.sam", "group": "all"}, blocking=True, return_response=True
    )
    assert [e["target"] for e in why["device_extras"]] == [TV]

    await hass.services.async_call(DOMAIN, "allow_end", end["data"], blocking=True)
    body = await (await _post(client, secret, body=_tv_status(hearthtube_s=1200, game_s=300))).json()
    assert _all_left(body["state"]["profiles"][KID]) == 0
    assert _sam(hass)["device_extras"] == []


async def test_an_allow_of_one_group_on_a_hearth_tv(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator
) -> None:
    client, secret = await _household_with_sam(hass, hass_client_no_auth)
    await _budget(hass, "games", 5)
    answer = await hass.services.async_call(
        DOMAIN,
        "allow",
        {"people": ["person.sam"], "group": "games", "until": "23:59", "device": TV},
        blocking=True,
        return_response=True,
    )
    assert answer["id"].startswith("dx_")
    body = await (await _post(client, secret, body=_tv_status(hearthtube_s=600, game_s=300))).json()
    assert "games" not in {g["id"] for g in body["state"]["profiles"][KID]["groups"]}
    assert "games" in {g["id"] for g in _hub(hass).household._person_document("person.sam")["groups"]}


async def test_a_device_must_be_theirs_and_one_group_only_where_it_s_held_alone(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator
) -> None:
    _nintendo_switch(hass)
    await _household_with_sam(hass, hass_client_no_auth)
    _nintendo_services(hass)
    await _option(hass, "enforce", {"person": "person.sam", "nintendo": NINTENDO_LIMIT})
    with pytest.raises(ServiceValidationError):
        await _device_bonus(hass, "fs:xbox", 30)
    with pytest.raises(ServiceValidationError):
        await _device_bonus(hass, f"nintendo:{NINTENDO_LIMIT}", 30, group="games")
    with pytest.raises(ServiceValidationError):
        await _device_bonus(hass, TV, -5)


async def test_extra_time_on_a_family_link_phone_is_google_s_bonus_there(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator, freezer
) -> None:
    freezer.move_to(dt_util.now().replace(hour=12, minute=0, second=0, microsecond=0))
    added = async_mock_service(hass, "familylink", "add_time_bonus")
    reset = async_mock_service(hass, "familylink", "reset_bonus")
    await _sam_with_family_link(hass, hass_client_no_auth)
    _phone(hass)
    _remaining(hass, 0)
    assert "fl:dev1" in {t["id"] for t in _sam(hass)["targets"]}

    await _device_bonus(hass, "fl:dev1", 30)
    assert [c.data for c in added] == [{"entity_id": PHONE, "bonus_minutes": 30}]
    # Hearth's own bonus: no grant
    assert _hub(hass).household.grants.of("person.sam") == []
    [extra] = _sam(hass)["device_extras"]
    assert extra["via"] == "family_link" and extra["minutes_left"] == 30

    _phone(hass, bonus=30)
    await hass.services.async_call(DOMAIN, "allow_end", {"people": ["person.sam"], "device": "fl:dev1"}, blocking=True)
    await hass.async_block_till_done()
    assert [c.data for c in reset] == [{"entity_id": PHONE}]


async def test_extra_time_on_the_xbox_lets_go_of_hearth_s_lock_there_only(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator, freezer
) -> None:
    freezer.move_to(dt_util.now().replace(hour=12, minute=0, second=0, microsecond=0))
    locked = async_mock_service(hass, "microsoft_family_safety", "lock_platform")
    unlocked = async_mock_service(hass, "microsoft_family_safety", "unlock_platform")
    given: list[ServiceCall] = []

    async def add_time_bonus(call: ServiceCall):
        given.append(call)
        return {"platform": call.data["platform"], "applied_until": call.data["until"], "hold_kept": False}

    hass.services.async_register(
        "microsoft_family_safety", "add_time_bonus", add_time_bonus, supports_response=SupportsResponse.OPTIONAL
    )
    hass.states.async_set(FAMILY_SAFETY, "Sam", {"user_id": 123456})
    hass.states.async_set(
        "binary_sensor.sam_xbox_allowed_now",
        "on",
        {"user_id": 123456, "platform": "Xbox", "hold": "none", "allowance_minutes": 60, "used_minutes": 60,
         "remaining_minutes": 0},
    )
    await _household_with_sam(hass, hass_client_no_auth)
    await _option(hass, "enforce", {"person": "person.sam", "family_safety": FAMILY_SAFETY})
    await _budget(hass, "all", 15)
    await hass.async_block_till_done()
    assert [c.data["platform"] for c in locked] == ["Xbox"]

    await _device_bonus(hass, "fs:xbox", 30)
    assert [c.data["platform"] for c in unlocked] == ["Xbox"]
    assert [c.data["until"] for c in given] == [
        dt_util.now().replace(hour=12, minute=30).replace(tzinfo=None).isoformat()
    ]
    # The pool stays out
    assert _sam(hass)["all"]["minutes_left"] == 0

    # Its time up: Hearth locks the Xbox again
    freezer.move_to(dt_util.now().replace(hour=12, minute=31))
    _hub(hass).household.recompute()
    await hass.async_block_till_done()
    assert [c.data["platform"] for c in locked] == ["Xbox", "Xbox"]


async def test_extra_time_on_the_switch_lets_go_of_hearth_s_hold(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator, freezer
) -> None:
    freezer.move_to(dt_util.now().replace(hour=12, minute=0, second=0, microsecond=0))
    _nintendo_switch(hass)
    await _household_with_sam(hass, hass_client_no_auth)
    set_value, _, _ = _nintendo_services(hass)
    await _option(hass, "enforce", {"person": "person.sam", "nintendo": NINTENDO_LIMIT})
    await _budget(hass, "games", 5)
    assert [c.data for c in set_value] == [{"entity_id": NINTENDO_LIMIT, "value": 0}]
    hass.states.async_set(NINTENDO_LIMIT, "0")

    await _device_bonus(hass, f"nintendo:{NINTENDO_LIMIT}", 20)
    assert set_value[-1].data == {"entity_id": NINTENDO_LIMIT, "value": 120}
    [extra] = _sam(hass)["device_extras"]
    assert extra["name"] == "Sam's Switch" and extra["minutes_left"] == 20


async def test_a_device_bonus_answers_its_id_and_playing_names_its_target(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator
) -> None:
    client, secret = await _household_with_sam(hass, hass_client_no_auth)
    await _budget(hass, "all", 15)
    [target] = _sam(hass)["targets"]
    # A TV's name as shown: the TV is "Kitchen", shown "Kitchen TV"
    assert target["name"] == "Kitchen TV"

    first = await hass.services.async_call(
        DOMAIN, "add_bonus", {"person": "person.sam", "minutes": 15, "device": TV}, blocking=True, return_response=True
    )
    second = await hass.services.async_call(
        DOMAIN, "add_bonus", {"person": "person.sam", "minutes": 10, "device": TV}, blocking=True, return_response=True
    )
    assert first["id"].startswith("dx_") and first["id"] != second["id"]
    # Undo ends just that one
    await hass.services.async_call(DOMAIN, "allow_end", {"id": second["id"]}, blocking=True)
    assert [e["id"] for e in _sam(hass)["device_extras"]] == [first["id"]]

    await _post(client, secret, body=_tv_status(hearthtube_s=600))
    await hass.async_block_till_done()
    assert {p["target"] for p in _sam(hass)["playing"]} <= {TV}


async def test_one_handset_as_a_hearth_phone_and_a_family_link_device_is_marked(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator, freezer
) -> None:
    from datetime import timedelta

    from test_init import NONCE, PHONE_ID

    await _sam_with_family_link(hass, hass_client_no_auth)
    _phone(hass)
    client = await hass_client_no_auth()
    # One address may ask to pair every 10 seconds
    freezer.tick(timedelta(seconds=11))
    await client.post(
        "/api/hearth/pair", json={"device_id": PHONE_ID, "kind": "mobile", "name": "Sam's phone", "nonce": NONCE}
    )
    await hass.async_block_till_done()
    flow = hass.config_entries.flow.async_progress_by_handler(DOMAIN)[0]
    await hass.config_entries.flow.async_configure(flow["flow_id"], {"person": "person.sam"})
    await hass.async_block_till_done()

    targets = {t["id"]: t for t in _sam(hass)["targets"]}
    assert targets["fl:dev1"]["same_as"] == f"hearth:{PHONE_ID}"
    assert targets[f"hearth:{PHONE_ID}"]["also"] == ["fl:dev1"]
