"""Hearth's own writes and half-done calls (enforce.py): a put-back cut off by a reload or failing after the write
went out is never a parent's change; a resume that fails part-way is sorted out by Family Link's pause records; the
device lock and the pause of every app don't swap again and again; and apps with unlimited time aren't paused when
their list can't be read whole."""

from datetime import timedelta

from homeassistant.core import HomeAssistant, ServiceCall
from homeassistant.exceptions import HomeAssistantError
from homeassistant.util import dt as dt_util
from pytest_homeassistant_custom_component.common import async_capture_events, async_mock_service
from pytest_homeassistant_custom_component.typing import ClientSessionGenerator

from custom_components.hearth import enforce
from custom_components.hearth.const import DOMAIN
from test_away_messages import _call, _held, _opened
from test_enforce import (
    FAMILY_LINK,
    NINTENDO_LIMIT,
    _bonus,
    _budget,
    _nintendo_services,
    _nintendo_switch,
    settled,  # noqa: F401 - the fixture
)
from test_messaging import CHROME, GAME, LATE, MESSAGES
from test_native_sync import CHILD, _installed, _sam_with_family_link, _settle, _weekday_limit
from test_people import _household_with_sam
from test_presence import OUT, SAM, minutes, sam_out_of_time
from test_sources import _option

KEY = "family_link|person.sam"
SCHOOL_SENSOR = "binary_sensor.sam_phone_school_time_active"
APPS = ["com.example.a", "com.example.b", "com.example.c", "com.example.d"]
LIMITS_SENSOR = "sensor.sam_family_link_apps_with_time_limits"


def _household(hass: HomeAssistant):
    return hass.config_entries.async_entries(DOMAIN)[0].runtime_data.household


async def _later(hass: HomeAssistant, freezer, count: int) -> None:
    freezer.tick(timedelta(minutes=count))
    _household(hass).recompute()
    await hass.async_block_till_done()


# Hearth's own put-back is never a parent's change


async def test_a_put_back_that_failed_after_the_write_went_out_is_no_parent_s_grant(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator, freezer
) -> None:
    """Hearth holds the devices at 0 and has seen the 0. Its put-back of 120 reaches Google but the call doesn't come
    back (cut off by a reload, a timeout): the hold is still in Hearth's books and the limit reads 120. That's Hearth's
    own write: no grant, and the lock isn't lifted until midnight."""
    freezer.move_to(dt_util.now().replace(hour=12, minute=0))
    await _sam_with_family_link(hass, hass_client_no_auth)
    grants = async_capture_events(hass, "hearth_parent_grant")
    await _budget(hass, "all", 30)
    hass.states.async_set(_weekday_limit(), "0", {"child_id": CHILD})
    await _settle(hass, freezer)
    household = _household(hass)
    held = household.enforcement.held[KEY]
    assert held.restore["lock_seen_zero"] is True

    calls: list[dict] = []
    during: list[dict] = []
    fail = [True]

    async def set_daily_limit(call: ServiceCall) -> None:
        calls.append(dict(call.data))
        if call.data["daily_minutes"] != 0 and fail[0]:
            during.append(dict(held.restore))
            hass.states.async_set(_weekday_limit(), "120", {"child_id": CHILD})
            raise HomeAssistantError("timed out")

    hass.services.async_register("familylink", "set_daily_limit", set_daily_limit)
    await _bonus(hass, "all", 30)
    # Kept before the call went out
    assert enforce.LOCK_PUT_BACK_AT in during[0]
    assert household.enforcement.status_of(SAM)["family_link"]["error"] == "timed out"
    # Past the minute in which any change is Hearth's: still no parent's change
    await _later(hass, freezer, 2)
    assert grants == [] and household.grants.of(SAM) == []
    assert household.enforcement.parent_changes() == []
    assert "Devices" not in held.items and held.restore["lock_minutes"] == 120
    # Tried again: let go of, with nothing left
    fail[0] = False
    await _later(hass, freezer, 5)
    assert calls[-1]["daily_minutes"] == 120 and held.items == set() and held.restore == {}
    assert grants == []


async def test_after_a_cut_off_put_back_devices_still_wanted_are_locked_again(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator, freezer
) -> None:
    freezer.move_to(dt_util.now().replace(hour=12, minute=0))
    limits = await _sam_with_family_link(hass, hass_client_no_auth)
    grants = async_capture_events(hass, "hearth_parent_grant")
    await _budget(hass, "all", 30)
    hass.states.async_set(_weekday_limit(), "0", {"child_id": CHILD})
    await _settle(hass, freezer)
    household = _household(hass)
    held = household.enforcement.held[KEY]
    # A reload cut the put-back off: what was stored comes back, and the limit reads what Hearth wrote
    held.restore[enforce.LOCK_PUT_BACK_AT] = dt_util.utcnow().isoformat()
    hass.states.async_set(_weekday_limit(), "120", {"child_id": CHILD})
    await hass.async_block_till_done()
    await _later(hass, freezer, 1)
    assert grants == []
    # Still out of time: locked again, the kept limit as it was
    assert [c.data["daily_minutes"] for c in limits] == [0, 0]
    assert "Devices" in held.items and held.restore["lock_minutes"] == 120
    assert enforce.LOCK_PUT_BACK_AT not in held.restore and "lock_seen_zero" not in held.restore

    # A parent's change is still one: the 0 shows again, then 150 from the Family Link app
    hass.states.async_set(_weekday_limit(), "0", {"child_id": CHILD})
    await _settle(hass, freezer)
    hass.states.async_set(_weekday_limit(), "150", {"child_id": CHILD})
    await hass.async_block_till_done()
    assert grants[0].data["target"] == {"kind": "device", "value": "Devices"}


async def test_an_old_put_back_mark_doesn_t_hide_a_parent_s_change(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator, freezer
) -> None:
    freezer.move_to(dt_util.now().replace(hour=12, minute=0))
    await _sam_with_family_link(hass, hass_client_no_auth)
    grants = async_capture_events(hass, "hearth_parent_grant")
    await _budget(hass, "all", 30)
    hass.states.async_set(_weekday_limit(), "0", {"child_id": CHILD})
    await _settle(hass, freezer)
    held = _household(hass).enforcement.held[KEY]
    held.restore[enforce.LOCK_PUT_BACK_AT] = (dt_util.utcnow() - timedelta(minutes=20)).isoformat()
    # The same minutes as before, set by a parent long after Hearth's try
    hass.states.async_set(_weekday_limit(), "120", {"child_id": CHILD})
    await hass.async_block_till_done()
    assert len(grants) == 1


async def test_the_quiet_minute_after_a_call_is_kept_over_a_reload(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator, freezer
) -> None:
    from custom_components.hearth import family_link as fl

    freezer.move_to(dt_util.now().replace(hour=12, minute=0))
    await _sam_with_family_link(hass, hass_client_no_auth)
    await _budget(hass, "all", 30)
    enforcement = _household(hass).enforcement
    assert KEY in enforcement._data()["quiet"]
    await enforcement._store.async_save(enforcement._data())
    fresh = enforce.Enforcement(hass, enforcement._entry_id)
    await fresh.async_load()
    fl.on_installed_changed(hass, enforcement._installed_changed)
    assert fresh._quiet(KEY)
    # A reading that isn't Hearth's 0 yet is no parent's change in that minute
    fresh.enforcers = enforcement.enforcers
    hass.states.async_set(_weekday_limit(), "140", {"child_id": CHILD})
    assert fresh.parent_changes() == []
    freezer.tick(timedelta(minutes=2))
    assert not fresh._quiet(KEY)
    # Stored long ago: not quiet
    await enforcement._store.async_save(enforcement._data())
    later = enforce.Enforcement(hass, enforcement._entry_id)
    await later.async_load()
    fl.on_installed_changed(hass, enforcement._installed_changed)
    assert not later._quiet(KEY)


async def test_a_switch_put_back_that_failed_after_the_write_is_no_parent_s_grant(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator, freezer
) -> None:
    freezer.move_to(dt_util.now().replace(hour=12, minute=0))
    _nintendo_switch(hass)
    await _household_with_sam(hass, hass_client_no_auth)
    _nintendo_services(hass)
    await _option(hass, "enforce", {"person": "person.sam", "nintendo": NINTENDO_LIMIT})
    grants = async_capture_events(hass, "hearth_parent_grant")
    await _budget(hass, "games", 5)
    hass.states.async_set(NINTENDO_LIMIT, "0")
    await _settle(hass, freezer)
    household = _household(hass)
    [held] = [h for k, h in household.enforcement.held.items() if k.startswith("nintendo|")]
    assert held.restore["seen_zero"] is True

    values: list = []
    fail = [True]

    async def set_value(call: ServiceCall) -> None:
        values.append(call.data["value"])
        if call.data["value"] != 0 and fail[0]:
            assert enforce.SWITCH_PUT_BACK_AT in held.restore
            hass.states.async_set(NINTENDO_LIMIT, "120")
            raise HomeAssistantError("timed out")

    hass.services.async_register("number", "set_value", set_value)
    await _bonus(hass, "games", 30)
    assert values and set(values) == {120}
    await _later(hass, freezer, 2)
    assert grants == [] and household.grants.of(SAM) == []
    assert "Switch" not in held.items and held.restore["max"] == 120
    fail[0] = False
    await _later(hass, freezer, 5)
    assert values[-1] == 120 and held.restore == {}
    assert grants == []


# A resume that fails part-way


async def _school_apps(hass: HomeAssistant, hass_client_no_auth, freezer, records: bool = True):
    """Sam's four School time apps paused through Family Link, whose resume_app resumes one app after the other and
    raises at the third while fail[0] (Family Link's pause records follow when [records])."""
    freezer.move_to(dt_util.now().replace(hour=12, minute=0))
    paused = async_mock_service(hass, "familylink", "pause_app")
    await _household_with_sam(hass, hass_client_no_auth)
    hass.states.async_set(FAMILY_LINK, "0", {"unit_of_measurement": "min", "child_id": CHILD})
    _installed(hass, APPS)
    resumed: list[list[str]] = []
    fail = [True]

    def show(packages) -> None:
        if records:
            hass.states.async_set(
                LIMITS_SENSOR,
                str(len(packages)),
                {
                    "child_id": CHILD,
                    "apps": [{"package": p, "limit_minutes": 1} for p in packages],
                    "paused_apps": [{"package": p, "pause_intact": True, "prior": -1} for p in packages],
                },
            )

    async def resume_app(call: ServiceCall) -> None:
        packages = sorted(call.data["packages"])
        resumed.append(packages)
        if fail[0] and len(packages) > 2:
            show(packages[2:])
            raise HomeAssistantError(f"Family Link did not take the app limit for {packages[2]}")
        show([])

    hass.services.async_register("familylink", "resume_app", resume_app)
    hass.states.async_set(SCHOOL_SENSOR, "on", {"child_id": CHILD, "schooltime_end": "2030-01-01T15:00:00"})
    await _option(
        hass,
        "enforce",
        {"person": "person.sam", "family_link": FAMILY_LINK, "fl_backstop": False, "school_time_apps": APPS},
    )
    assert sorted(paused[-1].data["packages"]) == APPS
    show(APPS)
    return paused, resumed, fail


async def _school(hass: HomeAssistant, on: bool) -> None:
    hass.states.async_set(SCHOOL_SENSOR, "on" if on else "off", {"child_id": CHILD})
    _household(hass).recompute()
    await hass.async_block_till_done()


async def test_a_resume_that_fails_at_the_third_app_resumes_only_the_rest_next(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator, freezer
) -> None:
    _paused, resumed, fail = await _school_apps(hass, hass_client_no_auth, freezer)
    await _school(hass, False)
    held = _household(hass).enforcement.held[KEY]
    assert resumed == [APPS]
    # None is held for sure, all four possibly
    assert held.items == set() and held.restore[enforce.MAYBE_PAUSED] == APPS
    assert held.restore[enforce.RESUME_UNSURE] == APPS
    assert _household(hass).enforcement.family_link_holding(SAM) == set(APPS)
    fail[0] = False
    await _later(hass, freezer, 6)
    # Family Link's records say which are still paused: only those are resumed
    assert resumed == [APPS, APPS[2:]]
    assert held.items == set() and held.restore == {}


async def test_a_hold_wanted_again_after_a_failed_resume_pauses_the_resumed_apps_again(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator, freezer
) -> None:
    """Before, Hearth's books still said all four were held, so nothing was paused again: two apps stayed open."""
    paused, resumed, _fail = await _school_apps(hass, hass_client_no_auth, freezer)
    await _school(hass, False)
    assert resumed == [APPS]
    await _school(hass, True)
    await _later(hass, freezer, 6)
    held = _household(hass).enforcement.held[KEY]
    assert sorted(paused[-1].data["packages"]) == APPS[:2] and len(paused) == 2
    assert held.items == set(APPS) and enforce.RESUME_UNSURE not in held.restore
    assert enforce.MAYBE_PAUSED not in held.restore
    assert resumed == [APPS]


async def test_a_failed_resume_without_pause_records_is_tried_again_whole(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator, freezer
) -> None:
    paused, resumed, fail = await _school_apps(hass, hass_client_no_auth, freezer, records=False)
    await _school(hass, False)
    held = _household(hass).enforcement.held[KEY]
    assert held.items == set() and held.restore[enforce.RESUME_UNSURE] == APPS
    # Wanted again: every one of them is paused again
    await _school(hass, True)
    await _later(hass, freezer, 6)
    assert sorted(paused[-1].data["packages"]) == APPS and held.items == set(APPS)
    assert enforce.RESUME_UNSURE not in held.restore
    fail[0] = False
    await _school(hass, False)
    assert resumed[-1] == APPS and held.restore == {}


async def test_a_hold_s_reason_is_the_one_it_had_when_the_call_started(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator, freezer
) -> None:
    """A pause of many apps takes minutes; what's wanted may have changed by the time it's logged."""
    freezer.move_to(dt_util.now().replace(hour=12, minute=0))
    await _household_with_sam(hass, hass_client_no_auth)
    async_mock_service(hass, "familylink", "resume_app")
    hass.states.async_set(FAMILY_LINK, "0", {"unit_of_measurement": "min", "child_id": CHILD})
    _installed(hass, APPS)

    async def pause_app(call: ServiceCall) -> None:
        _household(hass).enforcement._why[KEY] = {}

    hass.services.async_register("familylink", "pause_app", pause_app)
    hass.states.async_set(SCHOOL_SENSOR, "on", {"child_id": CHILD, "schooltime_end": "2030-01-01T15:00:00"})
    await _option(
        hass,
        "enforce",
        {"person": "person.sam", "family_link": FAMILY_LINK, "fl_backstop": False, "school_time_apps": APPS},
    )
    [record] = _household(hass).activity.query(SAM, "hold_start")
    assert record["reason"] == "school_time" and record["target"] == APPS


# Swapping between the device lock and pausing every app


async def _pause_messages(hass: HomeAssistant, on: bool) -> None:
    """An adult's pause of Messages closes the open app (the device lock is wanted); its end opens it again."""
    if on:
        await _call(hass, "pause", {"people": [SAM], "app": MESSAGES, "minutes": 600})
    else:
        await _call(hass, "pause_end", {"people": [SAM], "app": MESSAGES})


async def test_swaps_between_the_device_lock_and_app_pauses_wait_and_then_stop(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator, freezer
) -> None:
    calls = await sam_out_of_time(hass, hass_client_no_auth, freezer)
    household = _household(hass)
    assert "Devices" in _held(hass)
    # The first swap is at once: Messages opens when the kid is away
    await _opened(hass, freezer)
    assert "Devices" not in _held(hass) and {CHROME, LATE, GAME} <= set(_held(hass))
    # Back to the device lock at once (it holds more, in one call)
    await _pause_messages(hass, True)
    assert "Devices" in _held(hass)
    pauses = len(calls["pause"])
    # ... but not to the pauses again within the dwell time
    await _pause_messages(hass, False)
    assert household.open_apps(SAM) == {MESSAGES}
    assert "Devices" in _held(hass) and len(calls["pause"]) == pauses
    await minutes(hass, freezer, 5, OUT)
    assert "Devices" in _held(hass) and len(calls["pause"]) == pauses
    await minutes(hass, freezer, 6, OUT)
    assert "Devices" not in _held(hass) and {CHROME, LATE, GAME} <= set(_held(hass))

    # A fourth swap, and then the breaker: the device lock stays for an hour, said once
    await _pause_messages(hass, True)
    assert "Devices" in _held(hass)
    pauses = len(calls["pause"])
    await _pause_messages(hass, False)
    await minutes(hass, freezer, 11, OUT)
    assert "Devices" in _held(hass) and len(calls["pause"]) == pauses
    assert household.enforcement._swaps[KEY]["until"]
    assert len([r for r in household.activity.query(SAM, "hold_start") if r["reason"] == "swap_breaker"]) == 1
    await minutes(hass, freezer, 30, OUT)
    assert "Devices" in _held(hass) and len(calls["pause"]) == pauses
    assert len([r for r in household.activity.query(SAM, "hold_start") if r["reason"] == "swap_breaker"]) == 1
    # Kept over a reload
    assert household.enforcement._data()["swaps"][KEY]["until"]
    # After the hour, every app is paused again
    await minutes(hass, freezer, 31, OUT)
    assert household.open_apps(SAM) == {MESSAGES}
    assert "Devices" not in _held(hass) and {CHROME, LATE, GAME} <= set(_held(hass))


# Apps with unlimited time


async def test_every_app_isn_t_paused_while_the_always_allowed_apps_can_t_be_told(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator, freezer
) -> None:
    calls = await sam_out_of_time(hass, hass_client_no_auth, freezer)
    household = _household(hass)
    # The Always allowed list cut short, and never read whole (as after a first start)
    household.enforcement._always_last.clear()
    hass.states.async_set(
        "sensor.sam_always_allowed_apps", "3", {"child_id": "42", "apps": [{"package": LATE}], "truncated": True}
    )
    pauses = len(calls["pause"])
    await _opened(hass, freezer)
    assert household.open_apps(SAM) == {MESSAGES}
    # The device lock stays: it spares the apps with unlimited time by itself
    assert "Devices" in _held(hass) and len(calls["pause"]) == pauses


async def test_a_cut_short_always_allowed_list_reads_as_the_last_whole_one(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator, freezer
) -> None:
    calls = await sam_out_of_time(hass, hass_client_no_auth, freezer)
    household = _household(hass)
    hass.states.async_set(
        "sensor.sam_always_allowed_apps", "2", {"child_id": "42", "apps": [{"package": GAME}, {"package": LATE}]}
    )
    household.recompute()
    await hass.async_block_till_done()
    assert household.enforcement._data()["fl_always_allowed"] == {"42": sorted([GAME, LATE])}
    hass.states.async_set(
        "sensor.sam_always_allowed_apps", "2", {"child_id": "42", "apps": [{"package": GAME}], "truncated": True}
    )
    await _opened(hass, freezer)
    held = set(_held(hass))
    assert "Devices" not in held and CHROME in held
    assert GAME not in held and LATE not in held
    assert not any({GAME, LATE} & set(c.data["packages"]) for c in calls["pause"])
