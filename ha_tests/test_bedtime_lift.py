"""An adult's extra time at bedtime lifts it while it lasts (bedtime_lift.py): Hearth's own Sleep and lock, and Family
Link's bedtime tonight through a today-only override, put back afterwards unless a parent changed it meanwhile."""

from datetime import timedelta

import pytest

from homeassistant.core import HomeAssistant
from homeassistant.util import dt as dt_util
from pytest_homeassistant_custom_component.common import async_capture_events, async_mock_service
from pytest_homeassistant_custom_component.typing import ClientSessionGenerator

from custom_components.hearth import enforce
from custom_components.hearth.bedtime_lift import moved_start
from custom_components.hearth.const import DOMAIN
from test_init import _post
from test_people import KID, _household_with_sam, _tv_status
from test_phones import _options
from test_sources import _option
from test_weekly import SCHOOL_DAY, _schedule

CHILD = "42"
FAMILY_LINK = "sensor.sam_family_link_daily_screen_time"
BEDTIME = "binary_sensor.sam_phone_bedtime_active"


@pytest.fixture(autouse=True)
def settled(monkeypatch):
    monkeypatch.setattr(enforce, "SETTLE", timedelta(0))


def _household(hass: HomeAssistant):
    return hass.config_entries.async_entries(DOMAIN)[0].runtime_data.household


def _bedtime_sensor(hass: HomeAssistant, on: bool, start: str, end: str) -> None:
    """Family Link's Bedtime active sensor of Sam's phone: tonight's window as local times without an offset."""
    hass.states.async_set(
        BEDTIME, "on" if on else "off", {"child_id": CHILD, "bedtime_start": start, "bedtime_end": end}
    )


def _at(clock: str, days: int = 0) -> str:
    return f"{dt_util.now().date() + timedelta(days=days)}T{clock}:00"


async def _sam(hass: HomeAssistant, hass_client_no_auth, freezer, hour: int, minute: int, budget: int = 60):
    """Sam on the TV (15 minutes today), with a Family Link phone whose bedtime is 21:30 to 07:00 and is one of Sam's
    locks, a weekly schedule with Sleep from 21:30, and All screen time [budget]."""
    freezer.move_to(dt_util.now().replace(hour=hour, minute=minute, second=0, microsecond=0))
    set_bedtime = async_mock_service(hass, "familylink", "set_bedtime")
    for service in ("set_daily_limit", "pause_app", "resume_app"):
        async_mock_service(hass, "familylink", service)
    client, secret = await _household_with_sam(hass, hass_client_no_auth)
    await _options(hass, roles={"person.sam": "kid"})
    hass.states.async_set(FAMILY_LINK, "0", {"unit_of_measurement": "min", "child_id": CHILD})
    await _option(hass, "enforce", {"person": "person.sam", "family_link": FAMILY_LINK})
    _bedtime_sensor(hass, hour >= 21 and minute >= 30 or hour >= 22, _at("21:30"), _at("07:00", 1))
    await _option(hass, "locks", {"person": "person.sam", "entities": [BEDTIME]})
    await _schedule(hass, days=["every_day"], changes=SCHOOL_DAY)
    await hass.services.async_call(
        DOMAIN, "set_budget", {"person": "person.sam", "group": "all", "minutes": budget}, blocking=True
    )
    await hass.async_block_till_done()
    return client, secret, set_bedtime


async def _bonus(hass: HomeAssistant, minutes: int) -> None:
    await hass.services.async_call(
        DOMAIN, "add_bonus", {"person": "person.sam", "group": "all", "minutes": minutes}, blocking=True
    )
    await hass.async_block_till_done()


async def _later(hass: HomeAssistant, freezer, minutes: int) -> None:
    freezer.tick(timedelta(minutes=minutes))
    # A bonus of 0 only recomputes, as the minute's timer does
    await hass.services.async_call(DOMAIN, "add_bonus", {"person": "person.sam", "minutes": 0}, blocking=True)
    await hass.async_block_till_done()
    await hass.async_block_till_done()


async def _sam_state(hass: HomeAssistant, client, secret) -> dict:
    body = await (await _post(client, secret, body=_tv_status(hearthtube_s=600, game_s=300))).json()
    return body["state"]["profiles"][KID]


def _call(start: str, end: str = "07:00") -> dict:
    return {
        "child_id": CHILD,
        "start_time": start,
        "end_time": end,
        "day": dt_util.now().isoweekday(),
        "scope": "today",
    }


async def test_ending_the_bonus_grant_given_at_bedtime_brings_bedtime_back(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator, freezer
) -> None:
    """+30 during bedtime, then its grant is ended (hearth.end_grant): the lift goes, bedtime holds again."""
    client, secret, _set_bedtime = await _sam(hass, hass_client_no_auth, freezer, 21, 45)
    household = _household(hass)
    await _bonus(hass, 30)
    assert (await _sam_state(hass, client, secret))["locked"] is False
    origin = next(o for o in household.time_view("person.sam")["origins"] if o["kind"] == "bonus")
    await hass.services.async_call(DOMAIN, "end_grant", {"origin_id": origin["id"]}, blocking=True)
    await hass.async_block_till_done()
    assert household.bedtime_lift.until("person.sam") is None
    sam = await _sam_state(hass, client, secret)
    assert sam["locked"] is True and sam["lock"]["kind"] == "bedtime"


async def test_extra_time_at_bedtime_lifts_it_and_bedtime_comes_back(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator, freezer
) -> None:
    client, secret, set_bedtime = await _sam(hass, hass_client_no_auth, freezer, 21, 45)
    household = _household(hass)
    lifted = async_capture_events(hass, "hearth_bedtime_lifted")
    sam = await _sam_state(hass, client, secret)
    assert sam["locked"] is True and sam["lock"]["kind"] == "bedtime"
    assert "all" in household.schedule_holds("person.sam")

    await _bonus(hass, 30)
    # Family Link's bedtime tonight starts when the extra time ends; the weekly schedule is left alone
    assert [c.data for c in set_bedtime] == [_call("22:15")]
    # Hearth's own Sleep and Sam's bedtime lock let go: the TV, the phone, Family Safety and the Switch
    sam = await _sam_state(hass, client, secret)
    assert sam["locked"] is False and "lock" not in sam
    assert dt_util.parse_datetime(sam["bedtime_lifted"]["until"]).strftime("%H:%M") == "22:15"
    assert "all" not in household.schedule_holds("person.sam")
    assert lifted[-1].data["person"] == "person.sam"

    # More extra time moves it again
    await _bonus(hass, 15)
    assert set_bedtime[-1].data == _call("22:30")

    # Family Link shows Hearth's start; the extra time runs out and the start Hearth found is put back
    _bedtime_sensor(hass, False, _at("22:30"), _at("07:00", 1))
    await _later(hass, freezer, 46)
    assert set_bedtime[-1].data == _call("21:30") and len(set_bedtime) == 3
    sam = await _sam_state(hass, client, secret)
    assert sam["locked"] is True and "bedtime_lifted" not in sam
    assert "all" in household.schedule_holds("person.sam")
    assert household.enforcement.last["family_link|person.sam"]["bedtime"] == "restored"


async def test_a_bedtime_a_parent_changed_meanwhile_is_kept(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator, freezer
) -> None:
    _client, _secret, set_bedtime = await _sam(hass, hass_client_no_auth, freezer, 21, 45)
    await _bonus(hass, 30)
    assert len(set_bedtime) == 1
    # A parent sets tonight's bedtime to 22:45 in the Family Link app
    _bedtime_sensor(hass, False, _at("22:45"), _at("07:00", 1))
    await _later(hass, freezer, 31)
    assert len(set_bedtime) == 1
    assert _household(hass).enforcement.last["family_link|person.sam"]["bedtime"] == "kept_current"


async def test_a_lift_is_put_back_after_a_restart(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator, freezer
) -> None:
    _client, _secret, set_bedtime = await _sam(hass, hass_client_no_auth, freezer, 21, 45)
    await _bonus(hass, 30)
    entry = hass.config_entries.async_entries(DOMAIN)[0]
    assert await hass.config_entries.async_reload(entry.entry_id)
    await hass.async_block_till_done()
    household = _household(hass)
    assert household.bedtime_lift.moved["person.sam"]["start"] == "21:30"
    assert household.days["person.sam"].locked is False

    await _later(hass, freezer, 31)
    assert set_bedtime[-1].data == _call("21:30") and len(set_bedtime) == 2
    assert household.days["person.sam"].locked is True


async def test_bedtime_comes_back_when_all_screen_time_is_used_up(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator, freezer
) -> None:
    client, secret, set_bedtime = await _sam(hass, hass_client_no_auth, freezer, 21, 45, budget=15)
    await _bonus(hass, 20)
    assert set_bedtime[-1].data == _call("22:05")
    # 20 minutes more on the TV: none left
    await _post(client, secret, body=_tv_status(hearthtube_s=1800, game_s=300))
    await hass.async_block_till_done()
    await hass.async_block_till_done()
    assert set_bedtime[-1].data == _call("21:30")
    assert _household(hass).bedtime_lift.view("person.sam") is None


async def test_taking_extra_time_back_ends_the_lift(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator, freezer
) -> None:
    _client, _secret, set_bedtime = await _sam(hass, hass_client_no_auth, freezer, 21, 45)
    await _bonus(hass, 30)
    await hass.services.async_call(
        DOMAIN, "remove_bonus", {"person": "person.sam", "group": "all", "minutes": 30}, blocking=True
    )
    await hass.async_block_till_done()
    await hass.async_block_till_done()
    assert set_bedtime[-1].data == _call("21:30")
    assert _household(hass).days["person.sam"].locked is True


async def test_extra_time_outside_bedtime_changes_no_bedtime(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator, freezer
) -> None:
    client, secret, set_bedtime = await _sam(hass, hass_client_no_auth, freezer, 18, 0)
    await _bonus(hass, 30)
    assert set_bedtime == []
    assert "bedtime_lifted" not in await _sam_state(hass, client, secret)


async def test_after_midnight_only_hearth_s_own_bedtime_is_lifted(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator, freezer
) -> None:
    """Family Link's night under way started yesterday: a today-only override would move tonight's instead."""
    client, secret, set_bedtime = await _sam(hass, hass_client_no_auth, freezer, 0, 30)
    _bedtime_sensor(hass, True, _at("21:30", -1), _at("07:00"))
    await _bonus(hass, 30)
    assert set_bedtime == []
    sam = await _sam_state(hass, client, secret)
    assert sam["locked"] is False and "bedtime_lifted" in sam


def test_the_moved_start_is_never_past_midnight() -> None:
    now = dt_util.now().replace(hour=23, minute=40, second=0, microsecond=0)
    assert moved_start(now + timedelta(minutes=10), now) == "23:50"
    assert moved_start(now + timedelta(minutes=10, seconds=5), now) == "23:51"
    assert moved_start(now + timedelta(minutes=30), now) == "23:59"


async def test_a_lifted_bedtime_is_the_next_lock_when_its_extra_time_ends(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator, freezer
) -> None:
    """While extra time lifts bedtime, the TV is told bedtime comes back when it ends (next_lock), so a TV that loses
    Home Assistant meanwhile brings bedtime back by itself."""
    client, secret, _set_bedtime = await _sam(hass, hass_client_no_auth, freezer, 21, 45)
    await _bonus(hass, 30)
    sam = await _sam_state(hass, client, secret)
    assert sam["locked"] is False
    back = dt_util.now().replace(hour=22, minute=15, second=0, microsecond=0)
    # With the bedtime's own end (Family Link's bedtime_end) for a TV that starts it by itself
    wake = (back + timedelta(days=1)).replace(hour=7, minute=0)
    assert sam["next_lock"] == {"at": back.isoformat(), "by": BEDTIME, "kind": "bedtime", "until": wake.isoformat()}
