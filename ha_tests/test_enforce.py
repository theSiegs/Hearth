"""Enforcing: a group out of time is held by Family Link, Family Safety and Nintendo too, and let go when it has time
again."""

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


NINTENDO_LIMIT = "number.sam_s_switch_max_screentime_today"
NINTENDO_SUSPEND = "switch.sam_s_switch_suspend_software"
NINTENDO_MODE = "select.sam_s_switch_restriction_mode"


def _nintendo_switch(hass: HomeAssistant, limit: str = "120", suspend: str = "off", mode: str = "daily") -> None:
    """A Switch as Nintendo Switch Parental Controls makes it: one device, its entities keyed by the device id."""
    from homeassistant.helpers import device_registry as dr, entity_registry as er
    from pytest_homeassistant_custom_component.common import MockConfigEntry

    nintendo = MockConfigEntry(domain="nintendo_parental_controls")
    nintendo.add_to_hass(hass)
    device = dr.async_get(hass).async_get_or_create(
        config_entry_id=nintendo.entry_id, identifiers={("nintendo_parental_controls", "abc123")}, name="Sam's Switch"
    )
    registry = er.async_get(hass)
    for entity_id, key, state in (
        (NINTENDO_LIMIT, "today_max_screentime", limit),
        (NINTENDO_SUSPEND, "suspend_software", suspend),
        (NINTENDO_MODE, "timer_mode", mode),
    ):
        domain, object_id = entity_id.split(".")
        registry.async_get_or_create(
            domain, "nintendo_parental_controls", f"abc123_{key}", device_id=device.id, suggested_object_id=object_id
        )
        hass.states.async_set(entity_id, state)


def _nintendo_services(hass: HomeAssistant):
    """After the household is set up: Hearth's number platform brings number.set_value of its own."""
    return (
        async_mock_service(hass, "number", "set_value"),
        async_mock_service(hass, "switch", "turn_on"),
        async_mock_service(hass, "switch", "turn_off"),
    )


async def test_nintendo_suspends_the_switch_while_games_are_out_of_time(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator, freezer
) -> None:
    freezer.move_to(dt_util.now().replace(hour=12, minute=0))
    _nintendo_switch(hass)
    await _household_with_sam(hass, hass_client_no_auth)
    set_value, turned_on, turned_off = _nintendo_services(hass)
    await _option(hass, "enforce", {"person": "person.sam", "nintendo": NINTENDO_LIMIT})
    events = async_capture_events(hass, "hearth_enforced")

    await _budget(hass, "video", 5)  # not a group Nintendo holds for
    assert set_value == []
    await _budget(hass, "games", 5)
    assert [c.data for c in turned_on] == [{"entity_id": NINTENDO_SUSPEND}]
    assert [c.data for c in set_value] == [{"entity_id": NINTENDO_LIMIT, "value": 0}]
    held = hass.states.get("sensor.hearth_sam_held_by_parental_controls")
    assert held.state == "1"
    assert held.attributes["nintendo"]["held"] == ["Switch"]
    assert events[-1].data["by"] == "nintendo"

    # What Nintendo then says: 0 minutes today. Letting go puts back what it was, not that
    hass.states.async_set(NINTENDO_LIMIT, "0")
    hass.states.async_set(NINTENDO_SUSPEND, "on")
    await _bonus(hass, "games", 30)
    assert set_value[-1].data == {"entity_id": NINTENDO_LIMIT, "value": 120}
    assert [c.data for c in turned_off] == [{"entity_id": NINTENDO_SUSPEND}]
    assert hass.states.get("sensor.hearth_sam_held_by_parental_controls").state == "0"


async def test_nintendo_leaves_suspend_software_on_when_it_was(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator, freezer
) -> None:
    freezer.move_to(dt_util.now().replace(hour=12, minute=0))
    _nintendo_switch(hass, limit="-1", suspend="on")
    await _household_with_sam(hass, hass_client_no_auth)
    set_value, turned_on, turned_off = _nintendo_services(hass)
    await _option(hass, "enforce", {"person": "person.sam", "nintendo": NINTENDO_LIMIT})
    await _budget(hass, "all", 5)  # All screen time holds it too
    assert turned_on == []
    assert set_value[-1].data["value"] == 0
    await _bonus(hass, "all", 30)
    assert set_value[-1].data["value"] == -1  # no limit, as it was
    assert turned_off == []


async def test_nintendo_s_limit_is_put_back_after_a_restart(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator, freezer
) -> None:
    freezer.move_to(dt_util.now().replace(hour=12, minute=0))
    _nintendo_switch(hass, limit="90")
    await _household_with_sam(hass, hass_client_no_auth)
    set_value, _turned_on, turned_off = _nintendo_services(hass)
    await _option(hass, "enforce", {"person": "person.sam", "nintendo": NINTENDO_LIMIT})
    await _budget(hass, "games", 5)
    assert set_value[-1].data["value"] == 0
    hass.states.async_set(NINTENDO_LIMIT, "0")

    entry = hass.config_entries.async_entries(DOMAIN)[0]
    assert await hass.config_entries.async_reload(entry.entry_id)
    await hass.async_block_till_done()
    await _bonus(hass, "games", 30)
    assert set_value[-1].data == {"entity_id": NINTENDO_LIMIT, "value": 90}
    assert len(turned_off) == 1


async def test_nintendo_lets_go_just_before_midnight(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator, freezer
) -> None:
    """A Switch's limit is a setting of every day (or of this weekday): it's put back while it's still today's."""
    freezer.move_to(dt_util.now().replace(hour=23, minute=50))
    _nintendo_switch(hass, mode="each_day_of_the_week")
    await _household_with_sam(hass, hass_client_no_auth)
    set_value, _turned_on, _turned_off = _nintendo_services(hass)
    await _option(hass, "enforce", {"person": "person.sam", "nintendo": NINTENDO_LIMIT})
    await _budget(hass, "games", 5)
    assert set_value[-1].data["value"] == 0

    freezer.move_to(dt_util.now().replace(hour=23, minute=59))
    await _bonus(hass, "games", 0)  # a recompute
    assert set_value[-1].data["value"] == 120


async def test_a_failed_nintendo_hold_keeps_the_limit_it_found_first(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator, freezer, monkeypatch
) -> None:
    freezer.move_to(dt_util.now().replace(hour=12, minute=0))
    calls: list[ServiceCall] = []

    async def failing(call: ServiceCall) -> None:
        calls.append(call)
        raise HomeAssistantError("Nintendo said no")

    _nintendo_switch(hass)
    await _household_with_sam(hass, hass_client_no_auth)
    hass.services.async_register("number", "set_value", failing)
    async_mock_service(hass, "switch", "turn_on")
    async_mock_service(hass, "switch", "turn_off")
    await _option(hass, "enforce", {"person": "person.sam", "nintendo": NINTENDO_LIMIT})
    await _budget(hass, "games", 5)
    held = hass.states.get("sensor.hearth_sam_held_by_parental_controls")
    assert held.attributes["nintendo"]["error"] == "Nintendo said no"

    # Half done, as if the 0 had reached Nintendo: the retry and the let-go still use the 120 found first
    hass.states.async_set(NINTENDO_LIMIT, "0")
    hass.services.async_remove("number", "set_value")
    set_value = async_mock_service(hass, "number", "set_value")
    monkeypatch.setattr(enforce, "RETRY", timedelta(0))
    await _bonus(hass, "games", 30)
    assert [c.data["value"] for c in set_value] == [120]


async def test_a_switch_s_used_screen_time_is_games_by_itself(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator
) -> None:
    from homeassistant.helpers import entity_registry as er

    used = "sensor.sam_s_switch_used_screen_time"
    er.async_get(hass).async_get_or_create(
        "sensor", "nintendo_parental_controls", "abc123_playing_time", suggested_object_id="sam_s_switch_used_screen_time"
    )
    hass.states.async_set(used, "40", {"unit_of_measurement": "min"})
    await _household_with_sam(hass, hass_client_no_auth)
    await _option(hass, "add_source", {"entity_id": used, "person": "person.sam"})
    entry = hass.config_entries.async_entries(DOMAIN)[0]
    assert entry.options["sources"][0]["group"] == "games"
    assert hass.states.get("sensor.hearth_sam_games_today").state == "45"  # 5 on the TV, 40 on the Switch
