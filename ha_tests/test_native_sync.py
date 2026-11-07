"""Keeping Hearth and the first-party apps (Family Link, Nintendo, Family Safety) in step: a parent's change in their
own app is an adult's decision, which Hearth adopts and never overwrites."""

from datetime import timedelta

from homeassistant.core import HomeAssistant, ServiceCall, SupportsResponse
from homeassistant.util import dt as dt_util
from pytest_homeassistant_custom_component.common import async_capture_events, async_mock_service
from pytest_homeassistant_custom_component.typing import ClientSessionGenerator

from custom_components.hearth import enforce
from custom_components.hearth.const import DOMAIN
from test_enforce import (
    FAMILY_LINK,
    NINTENDO_LIMIT,
    NINTENDO_SUSPEND,
    _bonus,
    _budget,
    _nintendo_services,
    _nintendo_switch,
    settled,  # noqa: F401 - the fixture
)
from test_people import _household_with_sam
from test_sources import _option

CHILD = "42"


def _weekday_limit() -> str:
    return f"number.sam_family_link_{enforce.WEEKDAYS[dt_util.now().weekday()]}_limit"


async def _sam_with_family_link(hass: HomeAssistant, hass_client_no_auth, limit: str = "120"):
    """Sam with a Family Link phone (its daily limit [limit]), held by Family Link when All screen time runs out."""
    limits = async_mock_service(hass, "familylink", "set_daily_limit")
    await _household_with_sam(hass, hass_client_no_auth)
    hass.states.async_set(
        FAMILY_LINK,
        "20",
        {"unit_of_measurement": "min", "child_id": CHILD, "apps": [{"package": "com.example.chat", "minutes": 20}]},
    )
    hass.states.async_set(_weekday_limit(), limit, {"child_id": CHILD})
    await _option(hass, "add_source", {"entity_id": FAMILY_LINK, "person": "person.sam"})
    await _option(hass, "enforce", {"person": "person.sam", "family_link": FAMILY_LINK})
    return limits


def _household(hass: HomeAssistant):
    return hass.config_entries.async_entries(DOMAIN)[0].runtime_data.household


# A. Compare and restore


async def test_a_daily_limit_a_parent_changed_while_held_is_kept(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator, freezer
) -> None:
    freezer.move_to(dt_util.now().replace(hour=12, minute=0))
    limits = await _sam_with_family_link(hass, hass_client_no_auth)
    events = async_capture_events(hass, "hearth_enforced")
    await _budget(hass, "all", 30)
    assert limits[-1].data["daily_minutes"] == 0

    # A parent sets 90 for today in the Family Link app (seen before Hearth's own 0 even showed)
    household = _household(hass)
    hass.states.async_set(_weekday_limit(), "90", {"child_id": CHILD})
    await _bonus(hass, "all", 30)
    assert len(limits) == 1  # 120 isn't written over the parent's 90
    assert events[-1].data["outcomes"] == {"Devices": "kept_current"}
    status = household.enforcement.status_of("person.sam")["family_link"]
    assert status["last"]["outcomes"] == {"Devices": "kept_current"} and status["last"]["ok"]


async def test_a_daily_limit_still_at_hearth_s_zero_is_put_back(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator, freezer
) -> None:
    freezer.move_to(dt_util.now().replace(hour=12, minute=0))
    limits = await _sam_with_family_link(hass, hass_client_no_auth)
    events = async_capture_events(hass, "hearth_enforced")
    await _budget(hass, "all", 30)
    hass.states.async_set(_weekday_limit(), "0", {"child_id": CHILD})
    await _bonus(hass, "all", 30)
    assert limits[-1].data["daily_minutes"] == 120
    assert events[-1].data["outcomes"] == {"Devices": "restored"}


async def test_a_switch_limit_a_parent_changed_while_held_is_kept(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator, freezer
) -> None:
    freezer.move_to(dt_util.now().replace(hour=12, minute=0))
    _nintendo_switch(hass)
    await _household_with_sam(hass, hass_client_no_auth)
    set_value, _turned_on, turned_off = _nintendo_services(hass)
    await _option(hass, "enforce", {"person": "person.sam", "nintendo": NINTENDO_LIMIT})
    await _budget(hass, "games", 5)
    assert set_value[-1].data["value"] == 0

    hass.states.async_set(NINTENDO_LIMIT, "45")
    hass.states.async_set(NINTENDO_SUSPEND, "on")
    await _bonus(hass, "games", 30)
    assert len(set_value) == 1 and turned_off == []


async def test_family_link_s_resume_answer_is_shown(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator
) -> None:
    """A newer Family Link says what resume_app did (kept_current: a parent's setting stayed)."""
    async_mock_service(hass, "familylink", "pause_app")

    async def resume(call: ServiceCall):
        return {"results": {p: "kept_current" for p in call.data["packages"]}, "kept_current": {}}

    hass.services.async_register("familylink", "resume_app", resume, supports_response=SupportsResponse.OPTIONAL)
    await _household_with_sam(hass, hass_client_no_auth)
    await _option(hass, "enforce", {"person": "person.sam", "family_link": FAMILY_LINK})
    events = async_capture_events(hass, "hearth_enforced")
    await _budget(hass, "video", 10)
    await _bonus(hass, "video", 15)
    assert set(events[-1].data["outcomes"].values()) == {"kept_current"}


# B. Parent grants


async def test_a_parent_grant_lifts_only_its_own_hold_until_ended(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator, freezer
) -> None:
    freezer.move_to(dt_util.now().replace(hour=12, minute=0))
    limits = await _sam_with_family_link(hass, hass_client_no_auth)
    await _budget(hass, "all", 30)
    assert limits[-1].data["daily_minutes"] == 0
    hass.states.async_set(_weekday_limit(), "0", {"child_id": CHILD})
    household = _household(hass)

    grant, new = household.grants.add(
        "person.sam", "family_link", "device", "Devices", dt_util.now() + timedelta(hours=1), "bonus time"
    )
    assert new
    await _bonus(hass, "all", 0)  # a recompute
    assert limits[-1].data["daily_minutes"] == 120  # let go: the lock is lifted
    # Budgets keep counting: All screen time is still out
    assert household.days["person.sam"].limits["all"].minutes_left == 0

    explained = await hass.services.async_call(
        DOMAIN, "explain", {"person": "person.sam", "group": "all"}, blocking=True, return_response=True
    )
    granted = [e for e in explained["exceptions"] if e.get("type") == "grant"]
    assert granted[0]["source"] == "from the Family Link app"
    assert granted[0]["target"] == {"kind": "device", "value": "Devices"}
    assert household.exceptions_of("person.sam")["grants"][0]["id"] == grant.id

    hass.states.async_set(_weekday_limit(), "120", {"child_id": CHILD})
    ended = await hass.services.async_call(
        DOMAIN, "allow_end", {"id": grant.id}, blocking=True, return_response=True
    )
    await hass.async_block_till_done()
    assert ended["ended"] == [grant.id]
    assert limits[-1].data["daily_minutes"] == 0  # held again


async def test_a_grant_ends_by_itself(hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator, freezer) -> None:
    freezer.move_to(dt_util.now().replace(hour=12, minute=0))
    await _sam_with_family_link(hass, hass_client_no_auth)
    household = _household(hass)
    household.grants.add("person.sam", "nintendo", "switch", "Switch", dt_util.utcnow() + timedelta(minutes=5), "x")
    assert household.grants.lifted("person.sam") == {"nintendo": {"Switch"}}
    freezer.tick(timedelta(minutes=6))
    assert household.grants.lifted("person.sam") == {}
    assert household.grants.prune()
