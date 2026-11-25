"""An adult's extra time at bedtime lifts it while it lasts (bedtime_lift.py): Hearth's own Sleep and lock, and Family
Link's bedtime tonight through a today-only override, put back afterwards unless a parent changed it meanwhile. A
Family Link bedtime already under way is opened with bonus time on the device, reset when the lift ends."""

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


# A Family Link bedtime already under way: bonus time on the device ends it (moving its start doesn't)

PHONE = "switch.sam_phone"
DEVICE = "device-1"
KEY = "family_link|person.sam"


def _phone(hass: HomeAssistant, bonus: int = 0) -> None:
    """Family Link's device switch of Sam's phone, with the latest bonus Family Link shows on it."""
    hass.states.async_set(
        PHONE, "off", {"child_id": CHILD, "device_id": DEVICE, "device_name": "Phone", "bonus_minutes": bonus}
    )


def _phone_bedtime(hass: HomeAssistant, on: bool, start: str, end: str) -> None:
    """The phone's Bedtime active sensor as Family Link gives it: with the device's id."""
    hass.states.async_set(
        BEDTIME,
        "on" if on else "off",
        {"child_id": CHILD, "device_id": DEVICE, "bedtime_start": start, "bedtime_end": end},
    )


async def _sam_with_phone(hass: HomeAssistant, hass_client_no_auth, freezer, hour: int, minute: int, on: bool = True):
    """Sam as in _sam, the phone in Family Link's bedtime (or not yet), with Family Link's bonus services."""
    client, secret, set_bedtime = await _sam(hass, hass_client_no_auth, freezer, hour, minute)
    add_time = async_mock_service(hass, "familylink", "add_time_bonus")
    reset = async_mock_service(hass, "familylink", "reset_bonus")
    _phone(hass)
    _phone_bedtime(hass, on, _at("21:30"), _at("07:00", 1))
    await hass.async_block_till_done()
    return client, secret, set_bedtime, add_time, reset


async def test_extra_time_in_a_bedtime_under_way_gives_family_link_bonus_time(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator, freezer
) -> None:
    client, secret, set_bedtime, add_time, reset = await _sam_with_phone(hass, hass_client_no_auth, freezer, 21, 45)
    household = _household(hass)

    await _bonus(hass, 30)
    # The phone is in Family Link's bedtime: bonus time for as long as the lift lasts opens it
    assert [c.data for c in add_time] == [{"entity_id": PHONE, "bonus_minutes": 30}]
    # Tonight's start is moved as before, so the Family Link app shows when bedtime is back
    assert [c.data for c in set_bedtime] == [_call("22:15")]
    assert household.enforcement.last[KEY]["bedtime_bonus"] == {"Phone": 30}
    assert household.enforcement.last[KEY]["bedtime_moved"] == "22:15"
    # Hearth's own, so never read as a parent's bonus, and in the activity log as Hearth's call
    assert household.sync.own_bonus() == {DEVICE: 30}
    assert any(
        r.get("service") in ("add_time_bonus", "familylink.add_time_bonus")
        for r in household.activity.query(kind="call")
    )
    assert (await _sam_state(hass, client, secret))["locked"] is False

    # A recompute gives nothing more; more extra time gives the minutes more
    await _later(hass, freezer, 5)
    assert len(add_time) == 1
    await _bonus(hass, 15)
    assert [c.data for c in add_time][1:] == [{"entity_id": PHONE, "bonus_minutes": 15}]
    assert set_bedtime[-1].data == _call("22:30")

    # The lift ends: Hearth's bonus is reset (Family Link shows its latest, 15), and the start put back
    _phone(hass, bonus=15)
    _phone_bedtime(hass, True, _at("22:30"), _at("07:00", 1))
    await _later(hass, freezer, 41)
    assert [c.data for c in reset] == [{"entity_id": PHONE}]
    assert set_bedtime[-1].data == _call("21:30")
    last = household.enforcement.last[KEY]
    assert last["bedtime"] == "restored" and last["bedtime_bonus_reset"] == [PHONE]
    assert household.bedtime_lift.bonus == {} and household.sync.own_bonus() == {}
    assert (await _sam_state(hass, client, secret))["locked"] is True
    assert len(add_time) == 2


async def test_a_bedtime_that_has_not_started_only_has_its_start_moved(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator, freezer
) -> None:
    """Sleep (21:30) holds Sam at 21:45, Family Link's own bedtime starts at 22:00: no bonus, the start moves."""
    _client, _secret, set_bedtime, add_time, reset = await _sam_with_phone(
        hass, hass_client_no_auth, freezer, 21, 45, on=False
    )
    _phone_bedtime(hass, False, _at("22:00"), _at("07:00", 1))
    await hass.async_block_till_done()
    await _bonus(hass, 30)
    assert [c.data for c in set_bedtime] == [_call("22:15")]
    assert add_time == []

    # Family Link shows Hearth's start; the lift ends with nothing to reset
    _phone_bedtime(hass, False, _at("22:15"), _at("07:00", 1))
    await _later(hass, freezer, 31)
    assert set_bedtime[-1].data == _call("22:00")
    assert add_time == [] and reset == []


async def test_a_phone_that_enters_bedtime_during_the_lift_gets_the_rest_as_bonus_time(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator, freezer
) -> None:
    """The moved start didn't hold the bedtime off (Family Link's bedtime is on at 22:00 all the same)."""
    _client, _secret, _set_bedtime, add_time, _reset = await _sam_with_phone(
        hass, hass_client_no_auth, freezer, 21, 45, on=False
    )
    _phone_bedtime(hass, False, _at("22:00"), _at("07:00", 1))
    await hass.async_block_till_done()
    await _bonus(hass, 30)
    assert add_time == []
    freezer.tick(timedelta(minutes=15))
    _phone_bedtime(hass, True, _at("22:00"), _at("07:00", 1))
    await _later(hass, freezer, 0)
    assert [c.data for c in add_time] == [{"entity_id": PHONE, "bonus_minutes": 15}]


async def test_without_family_link_s_bonus_service_only_the_start_is_moved(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator, freezer
) -> None:
    """An older Family Link (no add_time_bonus): as before, and nothing fails."""
    client, secret, set_bedtime = await _sam(hass, hass_client_no_auth, freezer, 21, 45)
    _phone(hass)
    _phone_bedtime(hass, True, _at("21:30"), _at("07:00", 1))
    await hass.async_block_till_done()
    household = _household(hass)
    await _bonus(hass, 30)
    assert [c.data for c in set_bedtime] == [_call("22:15")]
    assert household.bedtime_lift.bonus == {}
    assert "error" not in household.enforcement.last[KEY]
    assert (await _sam_state(hass, client, secret))["locked"] is False
    _phone_bedtime(hass, False, _at("22:15"), _at("07:00", 1))
    await _later(hass, freezer, 31)
    assert household.enforcement.last[KEY]["bedtime"] == "restored"


async def test_a_parent_s_bonus_on_top_is_not_reset_when_the_lift_ends(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator, freezer
) -> None:
    _client, _secret, _set_bedtime, add_time, reset = await _sam_with_phone(hass, hass_client_no_auth, freezer, 21, 45)
    await _bonus(hass, 30)
    assert len(add_time) == 1
    # A parent adds 10 minutes in the Family Link app: the device's latest bonus isn't one Hearth gave
    _phone(hass, bonus=10)
    await _later(hass, freezer, 31)
    assert reset == []
    household = _household(hass)
    assert household.enforcement.last[KEY]["bedtime_bonus_kept"] == [PHONE]
    assert household.bedtime_lift.bonus == {}


async def test_a_phone_a_bonus_already_keeps_open_gets_none(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator, freezer
) -> None:
    _client, _secret, _set_bedtime, add_time, reset = await _sam_with_phone(hass, hass_client_no_auth, freezer, 21, 45)
    _phone(hass, bonus=60)
    await hass.async_block_till_done()
    await _bonus(hass, 30)
    assert add_time == []
    await _later(hass, freezer, 31)
    assert reset == []


async def test_after_midnight_the_night_under_way_gets_bonus_time(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator, freezer
) -> None:
    """The night that started yesterday can't have its start moved, but bonus time is the device's, not a night's."""
    _client, _secret, set_bedtime, add_time, reset = await _sam_with_phone(hass, hass_client_no_auth, freezer, 0, 30)
    _phone_bedtime(hass, True, _at("21:30", -1), _at("07:00"))
    await hass.async_block_till_done()
    await _bonus(hass, 30)
    assert set_bedtime == []
    assert [c.data for c in add_time] == [{"entity_id": PHONE, "bonus_minutes": 30}]
    _phone(hass, bonus=30)
    await _later(hass, freezer, 31)
    assert [c.data for c in reset] == [{"entity_id": PHONE}]


async def test_a_bedtime_bonus_is_reset_after_a_restart(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator, freezer
) -> None:
    _client, _secret, _set_bedtime, add_time, reset = await _sam_with_phone(hass, hass_client_no_auth, freezer, 21, 45)
    await _bonus(hass, 30)
    _phone(hass, bonus=30)
    entry = hass.config_entries.async_entries(DOMAIN)[0]
    assert await hass.config_entries.async_reload(entry.entry_id)
    await hass.async_block_till_done()
    household = _household(hass)
    assert household.bedtime_lift.bonus["person.sam"]["devices"][DEVICE]["given"] == [30]
    # Nothing is given twice
    await _later(hass, freezer, 5)
    assert len(add_time) == 1
    await _later(hass, freezer, 26)
    assert [c.data for c in reset] == [{"entity_id": PHONE}]
    assert household.bedtime_lift.bonus == {}


async def test_a_bonus_family_link_refuses_is_tried_again_and_the_start_still_moves(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator, freezer
) -> None:
    """Refused before it went out (a schema, a validation): not given, tried again after the retry wait."""
    from homeassistant.exceptions import ServiceValidationError

    _client, _secret, set_bedtime = await _sam(hass, hass_client_no_auth, freezer, 21, 45)
    calls: list[dict] = []

    async def refuse(call) -> None:
        calls.append(dict(call.data))
        if len(calls) == 1:
            raise ServiceValidationError("Family Link did not take the bonus")

    hass.services.async_register("familylink", "add_time_bonus", refuse)
    _phone(hass)
    _phone_bedtime(hass, True, _at("21:30"), _at("07:00", 1))
    await hass.async_block_till_done()
    await _bonus(hass, 30)
    household = _household(hass)
    assert len(calls) == 1 and household.bedtime_lift.bonus == {}
    assert household.sync.own_bonus() == {} and household.sync.fl_pending == []
    assert [c.data for c in set_bedtime] == [_call("22:15")]
    assert household.enforcement.last[KEY]["bedtime_error"] is True
    # Not hammered: a minute later nothing; after the retry wait the rest of the lift is given
    await _later(hass, freezer, 1)
    assert len(calls) == 1
    await _later(hass, freezer, 5)
    assert calls[1] == {"entity_id": PHONE, "bonus_minutes": 24}


async def test_a_bonus_whose_call_failed_is_hearth_s_while_watched_then_given_again(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator, freezer
) -> None:
    """Family Link's errors are plain Exceptions: the bonus may have gone through all the same. It's Hearth's own
    while watched (reset when the lift ends, never a parent's), not given twice, and given again once 10 minutes pass
    without the phone showing it. The start still moves."""
    from homeassistant.exceptions import HomeAssistantError

    _client, _secret, set_bedtime = await _sam(hass, hass_client_no_auth, freezer, 21, 45)
    calls: list[dict] = []

    async def fail(call) -> None:
        calls.append(dict(call.data))
        if len(calls) == 1:
            raise HomeAssistantError("Family Link did not add the time bonus")

    hass.services.async_register("familylink", "add_time_bonus", fail)
    _phone(hass)
    _phone_bedtime(hass, True, _at("21:30"), _at("07:00", 1))
    await hass.async_block_till_done()
    await _bonus(hass, 30)
    household = _household(hass)
    assert len(calls) == 1
    assert household.bedtime_lift.bonus["person.sam"]["devices"][DEVICE]["given"] == [30]
    assert household.sync.own_bonus() == {DEVICE: 30}
    assert [c.data for c in set_bedtime] == [_call("22:15")]
    assert household.enforcement.last[KEY]["bedtime_error"] is True
    # Watched: past the retry wait it isn't given a second time
    for minutes in (1, 5):
        await _later(hass, freezer, minutes)
        await household.sync.async_pending_tick()
        assert len(calls) == 1
    # Not shown within 10 minutes: it wasn't given, and the rest of the lift is given now
    await _later(hass, freezer, 5)
    await household.sync.async_pending_tick()
    await _later(hass, freezer, 0)
    assert calls[1] == {"entity_id": PHONE, "bonus_minutes": 19}
    # Only the bonus that went through is Hearth's
    assert household.sync.own_bonus() == {DEVICE: 19} and household.sync.fl_pending == []
    assert household.bedtime_lift.bonus["person.sam"]["devices"][DEVICE]["given"] == [19]


async def test_a_bonus_whose_answer_was_lost_is_reset_with_the_lift(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator, freezer
) -> None:
    """The call failed after Family Link took it: the phone shows the bonus. It's Hearth's (confirmed), and reset when
    the lift ends, not kept as a parent's."""
    from homeassistant.exceptions import HomeAssistantError

    _client, _secret, _set_bedtime = await _sam(hass, hass_client_no_auth, freezer, 21, 45)
    reset = async_mock_service(hass, "familylink", "reset_bonus")

    async def lost(call) -> None:
        raise HomeAssistantError("timed out")

    hass.services.async_register("familylink", "add_time_bonus", lost)
    _phone(hass)
    _phone_bedtime(hass, True, _at("21:30"), _at("07:00", 1))
    await hass.async_block_till_done()
    await _bonus(hass, 30)
    household = _household(hass)
    _phone(hass, bonus=30)
    await household.sync.async_pending_tick()
    assert household.sync.fl_pending == [] and household.sync.own_bonus() == {DEVICE: 30}
    assert household.grants.of("person.sam") == []
    _phone_bedtime(hass, True, _at("22:15"), _at("07:00", 1))
    await _later(hass, freezer, 31)
    assert [c.data for c in reset] == [{"entity_id": PHONE}]



async def test_a_reset_that_fails_still_puts_the_start_back_and_is_tried_again(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator, freezer
) -> None:
    from homeassistant.exceptions import HomeAssistantError

    _client, _secret, set_bedtime = await _sam(hass, hass_client_no_auth, freezer, 21, 45)
    async_mock_service(hass, "familylink", "add_time_bonus")
    resets: list[dict] = []

    async def refuse(call) -> None:
        resets.append(dict(call.data))
        if len(resets) == 1:
            raise HomeAssistantError("Failed to cancel time bonus")

    hass.services.async_register("familylink", "reset_bonus", refuse)
    _phone(hass)
    _phone_bedtime(hass, True, _at("21:30"), _at("07:00", 1))
    await hass.async_block_till_done()
    await _bonus(hass, 30)
    _phone(hass, bonus=30)
    _phone_bedtime(hass, True, _at("22:15"), _at("07:00", 1))
    await _later(hass, freezer, 31)
    household = _household(hass)
    assert len(resets) == 1 and set_bedtime[-1].data == _call("21:30")
    assert household.bedtime_lift.moved == {} and DEVICE in household.bedtime_lift.bonus["person.sam"]["devices"]
    # Tried again once the wait is over, not before
    await _later(hass, freezer, 1)
    assert len(resets) == 1
    await _later(hass, freezer, 5)
    assert resets == [{"entity_id": PHONE}] * 2
    assert household.bedtime_lift.bonus == {}


# Bedtime lifted on one device (device_extra.py, kind bedtime): hearth.allow with a device and bedtime: true


async def _lift_on_tv(hass: HomeAssistant, until: str) -> dict:
    from test_init import TV_ID

    answer = await hass.services.async_call(
        DOMAIN,
        "allow",
        {"people": ["person.sam"], "device": f"hearth:{TV_ID}", "bedtime": True, "until": until},
        blocking=True,
        return_response=True,
    )
    await hass.async_block_till_done()
    return answer


async def test_bedtime_lifted_on_one_tv_only(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator, freezer
) -> None:
    from custom_components.hearth.websocket import summary
    from test_init import TV_ID

    client, secret, set_bedtime = await _sam(hass, hass_client_no_auth, freezer, 21, 45)
    household = _household(hass)
    written = len(set_bedtime)
    assert (await _sam_state(hass, client, secret))["locked"] is True

    answer = await _lift_on_tv(hass, "22:45")
    assert answer["id"].startswith("dx_")
    # The TV: not locked by bedtime till 22:45, and bedtime is its next lock then (it relocks by itself offline)
    sam = await _sam_state(hass, client, secret)
    assert sam["locked"] is False and "lock" not in sam
    assert dt_util.parse_datetime(sam["bedtime_lifted"]["until"]).strftime("%H:%M") == "22:45"
    assert sam["next_lock"]["kind"] == "bedtime"
    assert dt_util.parse_datetime(sam["next_lock"]["at"]).strftime("%H:%M") == "22:45"
    # Everywhere else bedtime holds: Family Link's bedtime isn't moved, no extra time at bedtime, the schedule holds
    assert len(set_bedtime) == written
    assert household.bedtime_lift.until("person.sam") is None
    assert "all" in household.schedule_holds("person.sam")
    other = household._person_document("person.sam")
    assert other["locked"] is True and other["lock"]["kind"] == "bedtime" and "bedtime_lifted" not in other
    # The page: the TV isn't locked, the extra says so
    person = next(p for p in summary(household.hub)["people"] if p["id"] == "person.sam")
    [extra] = person["device_extras"]
    assert extra["kind"] == "bedtime" and extra["target"] == f"hearth:{TV_ID}"
    tv = next(t for t in person["targets"] if t["id"] == f"hearth:{TV_ID}")
    assert tv["locked"] is False

    # At 22:45 bedtime is back on the TV too
    await _later(hass, freezer, 61)
    sam = await _sam_state(hass, client, secret)
    assert sam["locked"] is True and sam["lock"]["kind"] == "bedtime" and "bedtime_lifted" not in sam


async def test_a_tv_bedtime_lift_given_before_bedtime_moves_the_tv_s_next_lock(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator, freezer
) -> None:
    client, secret, _set_bedtime = await _sam(hass, hass_client_no_auth, freezer, 21, 0)
    before = await _sam_state(hass, client, secret)
    assert dt_util.parse_datetime(before["next_lock"]["at"]).strftime("%H:%M") == "21:30"

    await _lift_on_tv(hass, "22:30")
    sam = await _sam_state(hass, client, secret)
    assert sam["locked"] is False
    assert sam["next_lock"]["kind"] == "bedtime"
    assert dt_util.parse_datetime(sam["next_lock"]["at"]).strftime("%H:%M") == "22:30"
    # Past bedtime, the TV still plays
    await _later(hass, freezer, 40)
    assert (await _sam_state(hass, client, secret))["locked"] is False
    assert _household(hass)._person_document("person.sam")["locked"] is True


async def test_a_bedtime_lift_needs_a_hearth_device_and_nothing_else(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator, freezer
) -> None:
    from homeassistant.exceptions import ServiceValidationError
    from test_init import TV_ID

    await _sam(hass, hass_client_no_auth, freezer, 21, 45)
    household = _household(hass)
    for data in (
        {"bedtime": True, "until": "22:30"},
        {"bedtime": True, "until": "22:30", "device": f"hearth:{TV_ID}", "group": "games"},
    ):
        with pytest.raises(ServiceValidationError):
            await hass.services.async_call(
                DOMAIN, "allow", {"people": ["person.sam"], **data}, blocking=True, return_response=True
            )
    with pytest.raises(ServiceValidationError):
        household.add_device_extra("person.sam", "fs:xbox", "bedtime", "all", until=dt_util.now() + timedelta(hours=1))
    assert household.device_extras.of("person.sam") == []
