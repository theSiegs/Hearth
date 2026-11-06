"""Exceptions: an adult's allow lifts Hearth's holds for a while, School time pauses its apps through the one hold,
and explain says why."""

from datetime import timedelta

import pytest

from homeassistant.core import HomeAssistant
from homeassistant.exceptions import ServiceValidationError
from homeassistant.util import dt as dt_util
from pytest_homeassistant_custom_component.common import async_mock_service
from pytest_homeassistant_custom_component.typing import ClientSessionGenerator

from custom_components.hearth import enforce
from custom_components.hearth.const import DOMAIN
from test_init import _post
from test_people import KID, _household_with_sam, _tv_status
from test_sources import _option

FAMILY_LINK = "sensor.sam_family_link_daily_screen_time"
SCHOOL_SENSOR = "binary_sensor.sam_phone_school_time_active"
MESSAGES = "com.google.android.apps.messaging"


@pytest.fixture(autouse=True)
def settled(monkeypatch):
    monkeypatch.setattr(enforce, "SETTLE", timedelta(0))


async def _sam_with_family_link(hass: HomeAssistant, hass_client_no_auth, school_apps=None):
    paused = async_mock_service(hass, "familylink", "pause_app")
    resumed = async_mock_service(hass, "familylink", "resume_app")
    client, secret = await _household_with_sam(hass, hass_client_no_auth)
    hass.states.async_set(FAMILY_LINK, "0", {"unit_of_measurement": "min", "child_id": "42"})
    hass.states.async_set(SCHOOL_SENSOR, "off", {"child_id": "42"})
    data = {"person": "person.sam", "family_link": FAMILY_LINK}
    if school_apps is not None:
        data["school_time_apps"] = school_apps
    await _option(hass, "enforce", data)
    return client, secret, paused, resumed


async def _call(hass: HomeAssistant, service: str, data: dict, response: bool = False):
    result = await hass.services.async_call(DOMAIN, service, data, blocking=True, return_response=response)
    await hass.async_block_till_done()
    return result


async def test_an_allowed_group_isn_t_held_until_it_ends(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator, freezer
) -> None:
    freezer.move_to(dt_util.now().replace(hour=12, minute=0))
    client, secret, paused, resumed = await _sam_with_family_link(hass, hass_client_no_auth)
    await _call(hass, "set_budget", {"person": "person.sam", "group": "video", "minutes": 10})
    assert len(paused) == 1 and "com.thesiegs.hearthtube" in paused[0].data["packages"]

    answer = await _call(
        hass, "allow", {"people": ["person.sam"], "group": "video", "until": "15:00", "reason": "Homework"}, True
    )
    assert answer["id"]
    assert len(resumed) == 1
    body = await (await _post(client, secret, body=_tv_status(hearthtube_s=600))).json()
    assert "video" not in [g["id"] for g in body["state"]["profiles"][KID]["groups"]]
    sensor = hass.states.get("sensor.hearth_sam_screen_time_today")
    [allow] = sensor.attributes["exceptions"]["allows"]
    assert allow["group"] == "video" and allow["reason"] == "Homework"

    why = await _call(hass, "explain", {"person": "person.sam", "group": "video"}, True)
    assert why["allowed"] is True
    assert why["lifted"][0]["kind"] == "budget"
    assert why["exceptions"][0]["id"] == answer["id"]

    # It ends by itself, and the hold comes back
    freezer.tick(timedelta(hours=3, minutes=1))
    await _call(hass, "add_bonus", {"person": "person.sam", "group": "video", "minutes": 0})
    assert len(paused) == 2
    why = await _call(hass, "explain", {"person": "person.sam", "group": "video"}, True)
    assert why["allowed"] is False
    assert why["blocked_by"] == [
        {"kind": "budget", "by": "video", "until": why["blocked_by"][0]["until"]}
    ]


async def test_an_allowed_app_leaves_its_group_and_can_end_early(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator
) -> None:
    client, secret, paused, resumed = await _sam_with_family_link(hass, hass_client_no_auth)
    await _call(hass, "set_budget", {"person": "person.sam", "group": "all", "minutes": 10})
    await _call(hass, "set_budget", {"person": "person.sam", "group": "video", "minutes": 5})
    answer = await _call(hass, "allow", {"people": ["person.sam"], "app": "com.thesiegs.hearthtube"}, True)

    body = await (await _post(client, secret, body=_tv_status(hearthtube_s=600))).json()
    groups = {g["id"]: g for g in body["state"]["profiles"][KID]["groups"]}
    assert "com.thesiegs.hearthtube" not in groups["video"]["apps"]
    assert "com.thesiegs.hearthtube" in groups["all"]["except"]
    assert all("com.thesiegs.hearthtube" not in c.data["packages"] for c in paused)

    ended = await _call(hass, "allow_end", {"id": answer["id"]}, True)
    assert ended == {"ended": [answer["id"]]}
    body = await (await _post(client, secret, body=_tv_status(hearthtube_s=600))).json()
    groups = {g["id"]: g for g in body["state"]["profiles"][KID]["groups"]}
    assert "com.thesiegs.hearthtube" in groups["video"]["apps"]


async def test_school_time_pauses_its_apps_through_the_one_hold(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator
) -> None:
    _client, _secret, paused, resumed = await _sam_with_family_link(hass, hass_client_no_auth, [MESSAGES])
    await _call(hass, "set_budget", {"person": "person.sam", "group": "video", "minutes": 10})
    budget_held = set(paused[-1].data["packages"])
    assert MESSAGES not in budget_held  # a budget never holds Messages

    hass.states.async_set(SCHOOL_SENSOR, "on", {"child_id": "42", "schooltime_end": "2030-01-01T15:00:00"})
    await hass.async_block_till_done()
    assert paused[-1].data["packages"] == [MESSAGES]
    why = await _call(hass, "explain", {"person": "person.sam", "app": MESSAGES}, True)
    assert [b["kind"] for b in why["blocked_by"]] == ["school_time_apps"]

    # The budget gets time again: only its apps are resumed, Messages stays paused for School time
    await _call(hass, "add_bonus", {"person": "person.sam", "group": "video", "minutes": 30})
    assert MESSAGES not in resumed[-1].data["packages"]
    assert set(resumed[-1].data["packages"]) == budget_held

    # An adult lets Messages through until School time ends
    await _call(hass, "allow", {"people": ["person.sam"], "app": MESSAGES, "until": "school_time_end"})
    assert resumed[-1].data["packages"] == [MESSAGES]
    await _call(hass, "allow_end", {"people": ["person.sam"], "app": MESSAGES})
    assert paused[-1].data["packages"] == [MESSAGES]

    hass.states.async_set(SCHOOL_SENSOR, "off", {"child_id": "42"})
    await hass.async_block_till_done()
    assert resumed[-1].data["packages"] == [MESSAGES]
    assert hass.states.get("sensor.hearth_sam_held_by_parental_controls").state == "0"


async def test_school_time_apps_never_include_hearth_or_family_link() -> None:
    found = enforce.enforcers_from_options(
        {
            "enforce": [
                {
                    "kind": "family_link",
                    "person": "person.sam",
                    "entity_id": FAMILY_LINK,
                    "school_time_apps": [MESSAGES, "com.thesiegs.hearth", "com.google.android.apps.kids.familylink"],
                }
            ]
        }
    )
    assert found[0].school_apps == (MESSAGES,)


async def test_allow_checks_what_it_is_given(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator
) -> None:
    await _sam_with_family_link(hass, hass_client_no_auth)
    with pytest.raises(ServiceValidationError):
        await _call(hass, "allow", {"people": ["person.nobody"], "group": "video"})
    with pytest.raises(ServiceValidationError):
        await _call(hass, "allow", {"people": ["person.sam"], "group": "nothing"})
    with pytest.raises(ServiceValidationError):
        # No School time today
        await _call(hass, "allow", {"people": ["person.sam"], "group": "video", "until": "school_time_end"})
    answer = await _call(hass, "allow", {"people": ["person.sam"], "group": "all"}, True)
    why = await _call(hass, "explain", {"person": "person.sam", "app": "com.example.game"}, True)
    assert why["allowed"] is True and why["exceptions"][0]["id"] == answer["id"]
