"""Enforcing: a group out of time is held by Family Link and Family Safety too, and let go when it has time again."""

from datetime import datetime, timedelta

import pytest

from homeassistant.core import HomeAssistant, ServiceCall
from homeassistant.exceptions import HomeAssistantError
from homeassistant.util import dt as dt_util
from pytest_homeassistant_custom_component.common import async_capture_events, async_mock_service
from pytest_homeassistant_custom_component.typing import ClientSessionGenerator

from custom_components.hearth import enforce
from custom_components.hearth.const import DOMAIN
from custom_components.hearth.enforce import essential, hours_to_midnight
from test_people import _household_with_sam
from test_sources import _option

FAMILY_LINK = "sensor.sam_family_link_daily_screen_time"
FAMILY_SAFETY = "sensor.sam_family_safety_account_info"


@pytest.fixture(autouse=True)
def settled(monkeypatch):
    """Tests don't wait out the minutes after a start in which nothing is let go."""
    monkeypatch.setattr(enforce, "SETTLE", timedelta(0))


async def _budget(hass: HomeAssistant, group: str, minutes: int) -> None:
    await hass.services.async_call(
        DOMAIN, "set_budget", {"person": "person.sam", "group": group, "minutes": minutes}, blocking=True
    )
    await hass.async_block_till_done()


async def _bonus(hass: HomeAssistant, group: str, minutes: int) -> None:
    await hass.services.async_call(
        DOMAIN, "add_bonus", {"person": "person.sam", "group": group, "minutes": minutes}, blocking=True
    )
    await hass.async_block_till_done()


def _family_link(hass: HomeAssistant):
    return async_mock_service(hass, "familylink", "pause_app"), async_mock_service(hass, "familylink", "resume_app")


async def test_family_link_pauses_the_group_s_apps_and_resumes_them(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator
) -> None:
    paused, resumed = _family_link(hass)
    await _household_with_sam(hass, hass_client_no_auth)
    await _option(hass, "enforce", {"person": "person.sam", "family_link": FAMILY_LINK})
    events = async_capture_events(hass, "hearth_enforced")

    await _budget(hass, "video", 10)  # 10 watched: none left
    assert len(paused) == 1
    assert paused[0].data["entity_id"] == FAMILY_LINK
    assert "com.thesiegs.hearthtube" in paused[0].data["packages"]
    held = hass.states.get("sensor.hearth_sam_held_by_parental_controls")
    assert int(held.state) == len(paused[0].data["packages"])
    assert events[0].data["by"] == "family_link"

    await _bonus(hass, "video", 15)
    assert len(resumed) == 1
    assert sorted(resumed[0].data["packages"]) == sorted(paused[0].data["packages"])
    await _bonus(hass, "video", 15)  # nothing more to do
    assert len(paused) == 1 and len(resumed) == 1


async def test_family_safety_locks_xbox_while_games_are_out_of_time(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator
) -> None:
    locked = async_mock_service(hass, "microsoft_family_safety", "lock_platform")
    unlocked = async_mock_service(hass, "microsoft_family_safety", "unlock_platform")
    hass.states.async_set(FAMILY_SAFETY, "Sam", {"user_id": 123456})
    await _household_with_sam(hass, hass_client_no_auth)
    await _option(hass, "enforce", {"person": "person.sam", "family_safety": FAMILY_SAFETY})

    await _budget(hass, "video", 5)  # not a group Family Safety holds for
    assert locked == []
    await _budget(hass, "games", 5)
    assert len(locked) == 1
    assert locked[0].data["account_id"] == "123456"
    assert locked[0].data["platform"] == "Xbox"
    assert 1 <= locked[0].data["duration_hours"] <= 24

    await _bonus(hass, "games", 30)
    assert [c.data["platform"] for c in unlocked] == ["Xbox"]


async def test_nothing_is_let_go_right_after_a_start(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator, monkeypatch
) -> None:
    paused, resumed = _family_link(hass)
    await _household_with_sam(hass, hass_client_no_auth)
    await _option(hass, "enforce", {"person": "person.sam", "family_link": FAMILY_LINK})
    await _budget(hass, "video", 10)
    assert len(paused) == 1

    monkeypatch.setattr(enforce, "SETTLE", timedelta(hours=1))
    await _bonus(hass, "video", 15)
    assert resumed == []
    monkeypatch.setattr(enforce, "SETTLE", timedelta(0))
    await _bonus(hass, "video", 1)
    assert len(resumed) == 1


async def test_stopping_lets_go_of_what_was_held(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator
) -> None:
    paused, resumed = _family_link(hass)
    await _household_with_sam(hass, hass_client_no_auth)
    await _option(hass, "enforce", {"person": "person.sam", "family_link": FAMILY_LINK})
    await _budget(hass, "video", 10)
    assert len(paused) == 1

    await _option(hass, "enforce", {"person": "person.sam"})
    assert len(resumed) == 1
    assert resumed[0].data["entity_id"] == FAMILY_LINK
    assert hass.states.get("sensor.hearth_sam_held_by_parental_controls").state == "0"


async def test_a_failure_is_shown_and_tried_again(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator, monkeypatch
) -> None:
    calls: list[ServiceCall] = []

    async def failing(call: ServiceCall) -> None:
        calls.append(call)
        raise HomeAssistantError("Google said no")

    hass.services.async_register("familylink", "pause_app", failing)
    async_mock_service(hass, "familylink", "resume_app")
    await _household_with_sam(hass, hass_client_no_auth)
    await _option(hass, "enforce", {"person": "person.sam", "family_link": FAMILY_LINK})
    await _budget(hass, "video", 10)
    assert len(calls) == 1
    held = hass.states.get("sensor.hearth_sam_held_by_parental_controls")
    assert held.attributes["family_link"]["error"] == "Google said no"

    await _bonus(hass, "video", -1)  # a recompute: too soon to try again
    assert len(calls) == 1
    monkeypatch.setattr(enforce, "RETRY", timedelta(0))
    await _bonus(hass, "video", -1)
    assert len(calls) == 2


def test_essential_apps_are_never_held():
    assert essential("com.google.android.apps.messaging")
    assert essential("com.android.phone")
    assert not essential("com.netflix.mediaclient")


def test_a_lock_lasts_until_midnight():
    zone = dt_util.get_default_time_zone()
    assert hours_to_midnight(datetime(2026, 10, 26, 20, 30, tzinfo=zone)) == 4
    assert hours_to_midnight(datetime(2026, 10, 26, 23, 50, tzinfo=zone)) == 1
    assert hours_to_midnight(datetime(2026, 10, 26, 0, 0, 1, tzinfo=zone)) == 24
