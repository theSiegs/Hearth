"""Hearth on the released Microsoft Family Safety (upstream's 2.3.0) and on one that carries more (a fork with today-only
allowed hours and hold attributes): what each can do, allowed hours Hearth moves and puts back itself, and a parent's
own lock or extra time told from Hearth's without Family Safety saying whose."""

from datetime import timedelta

import voluptuous as vol

from homeassistant.core import HomeAssistant, ServiceCall, SupportsResponse
from homeassistant.helpers import config_validation as cv
from homeassistant.helpers import entity_registry as er
from homeassistant.util import dt as dt_util
from pytest_homeassistant_custom_component.common import MockConfigEntry, async_capture_events, async_mock_service
from pytest_homeassistant_custom_component.typing import ClientSessionGenerator

from custom_components.hearth import enforce, fs_capabilities
from custom_components.hearth.const import DOMAIN
from custom_components.hearth.native_sync import FS_WEEKDAYS, fs_weekday
from test_enforce import FAMILY_SAFETY, _bonus, _budget, settled  # noqa: F401 - the fixture
from test_people import _household_with_sam
from test_sources import _option
from test_targets import _device_bonus, _windows

FS = "microsoft_family_safety"
ACCOUNT = 123456
XBOX_ALLOWED = "binary_sensor.sam_xbox_allowed_now"


def _household(hass: HomeAssistant):
    return hass.config_entries.async_entries(DOMAIN)[0].runtime_data.household


def _upstream(hass: HomeAssistant, answers: dict | None = None) -> dict[str, list[ServiceCall]]:
    """Family Safety's services as the 2.3.0 release has them (their schemas, so Hearth's probes see what it takes):
    no today_only, day_of_week required, lock_platform by whole hours, extra time on the Xbox and Windows."""
    target = {
        vol.Optional("account_id"): cv.string,
        vol.Optional("entity_id"): cv.entity_ids,
        vol.Optional("device_id"): vol.All(cv.ensure_list, [cv.string]),
    }
    platform = vol.In(["Windows", "Xbox", "Mobile"])
    schemas = {
        "lock_platform": {vol.Required("platform"): platform, vol.Optional("duration_hours", default=24): int},
        "unlock_platform": {vol.Required("platform"): platform},
        "add_time_bonus": {
            vol.Optional("platform", default="Xbox"): vol.In(["Xbox", "Windows"]),
            vol.Optional("minutes"): int,
            vol.Optional("until"): cv.datetime,
            vol.Optional("replace_lock", default=False): cv.boolean,
        },
        "cancel_time_bonus": {vol.Optional("platform", default="Xbox"): vol.In(["Xbox", "Windows"])},
        "set_screentime_limit": {
            vol.Required("day_of_week"): vol.All(int, vol.Range(min=0, max=6)),
            vol.Required("hours"): int,
            vol.Optional("minutes", default=0): int,
            vol.Optional("platform", default="Windows"): vol.In(["Windows", "Xbox"]),
        },
        "set_screentime_intervals": {
            vol.Required("day_of_week"): vol.All(int, vol.Range(min=0, max=6)),
            vol.Required("start_hour"): int,
            vol.Optional("start_minute", default=0): vol.In([0, 30]),
            vol.Required("end_hour"): int,
            vol.Optional("end_minute", default=0): vol.In([0, 30]),
            vol.Optional("platform", default="Windows"): vol.In(["Windows", "Xbox"]),
        },
        "pause_app": {vol.Required("apps"): [cv.string]},
        "resume_app": {vol.Optional("apps"): [cv.string]},
    }
    calls: dict[str, list[ServiceCall]] = {}
    for service, fields in schemas.items():
        calls[service] = []

        async def handle(call: ServiceCall, _service=service):
            calls[_service].append(call)
            if _service == "add_time_bonus":
                return {"added": True, "until": call.data["until"].isoformat(), "replaced_lock": False}
            return (answers or {}).get(_service)

        responds = service in ("add_time_bonus", "cancel_time_bonus", "pause_app", "resume_app")
        hass.services.async_register(
            FS, service, handle, schema=vol.Schema({**target, **fields}),
            supports_response=SupportsResponse.OPTIONAL if responds else SupportsResponse.NONE,
        )
    return calls


def _fork(hass: HomeAssistant) -> dict[str, list[ServiceCall]]:
    """A Family Safety that takes anything Hearth sends (today_only, lock until): its services without schemas."""
    return {
        service: async_mock_service(hass, FS, service)
        for service in (
            "lock_platform", "unlock_platform", "add_time_bonus", "cancel_time_bonus", "set_screentime_limit",
            "set_screentime_intervals", "pause_app", "resume_app",
        )
    }


def _xbox(hass: HomeAssistant, state: str = "on", **attrs) -> None:
    """Sam's Xbox Allowed Now sensor as upstream's has it: the override in force, no hold."""
    hass.states.async_set(
        XBOX_ALLOWED,
        state,
        {"user_id": ACCOUNT, "platform": "Xbox", "reason": "within_limits", "allowance_minutes": 60,
         "used_minutes": 50, "in_allowed_hours": True, "override": None, "override_until": None, **attrs},
    )


async def _sam_on_family_safety(hass: HomeAssistant, hass_client_no_auth, platforms=("Xbox",)) -> None:
    hass.states.async_set(FAMILY_SAFETY, "Sam", {"user_id": ACCOUNT})
    await _household_with_sam(hass, hass_client_no_auth)
    await _option(
        hass, "enforce", {"person": "person.sam", "family_safety": FAMILY_SAFETY, "platforms": list(platforms)}
    )
    await hass.async_block_till_done()


def _weekday_entities(hass: HomeAssistant, weekday: str, start: str, end: str) -> None:
    """The integration's Start and End entities of a Windows weekday."""
    registry = er.async_get(hass)
    for which, value in (("start", start), ("end", end)):
        entry = registry.async_get_or_create(
            "time", FS, f"entry_{ACCOUNT}_interval_{weekday}_{which}", suggested_object_id=f"sam_{weekday}_{which}"
        )
        hass.states.async_set(entry.entity_id, value)


# What each can do


async def test_upstream_s_capabilities_and_what_hearth_does_with_less(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator, hass_ws_client
) -> None:
    _upstream(hass)
    await _sam_on_family_safety(hass, hass_client_no_auth)
    _xbox(hass)
    MockConfigEntry(domain=FS, title="Family Safety").add_to_hass(hass)

    found = fs_capabilities.capabilities(hass)
    assert found == {
        "installed": True,
        "today_only": False,
        "weekday_hours": True,
        "hold_attributes": False,
        "allowed_now": True,
        "lock_until": False,
        "xbox_extra_time": True,
        "windows_extra_time": True,
        "cancel_extra_time": True,
        "pause_apps": True,
    }
    ws = await hass_ws_client(hass)
    await ws.send_json({"id": 1, "type": "hearth/config"})
    config = (await ws.receive_json())["result"]
    assert config["capabilities"]["family_safety"] == found
    [row] = config["parental_controls"]
    assert len(row["reduced"]) == 3
    assert "puts them back after midnight" in row["reduced"][0]
    assert "by what Hearth asked for" in row["reduced"][1]
    assert "whole hours" in row["reduced"][2]


async def test_a_family_safety_with_today_only_and_hold_attributes_has_it_all(hass: HomeAssistant) -> None:
    _fork(hass)
    hass.states.async_set(XBOX_ALLOWED, "on", {"user_id": ACCOUNT, "platform": "Xbox", "hold": "none", "override": None})
    found = fs_capabilities.capabilities(hass)
    assert all(found.values()), found
    assert fs_capabilities.reduced(found) == []
    # None installed: nothing to say
    assert fs_capabilities.reduced({"installed": False}) == []


# Allowed hours moved for extra time


async def _windows_extra_time_at(hass: HomeAssistant, hass_client_no_auth, freezer, install) -> dict:
    freezer.move_to(dt_util.now().replace(hour=21, minute=46, second=0, microsecond=0))
    calls = install(hass)
    _windows(hass)
    await _sam_on_family_safety(hass, hass_client_no_auth)
    await _device_bonus(hass, "fs:windows", 30)
    return calls


async def test_a_fork_moves_today_s_allowed_hours_today_only(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator, freezer
) -> None:
    calls = await _windows_extra_time_at(hass, hass_client_no_auth, freezer, _fork)
    [moved] = calls["set_screentime_intervals"]
    assert moved.data["today_only"] is True and "day_of_week" not in moved.data
    # Family Safety puts it back at midnight: Hearth keeps nothing to put back
    assert _household(hass).sync.windows == {}


async def test_upstream_s_weekday_hours_are_moved_and_put_back_after_midnight(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator, freezer
) -> None:
    calls = await _windows_extra_time_at(hass, hass_client_no_auth, freezer, _upstream)
    weekday = fs_weekday(dt_util.now())
    [moved] = calls["set_screentime_intervals"]
    assert moved.data == {
        "entity_id": [FAMILY_SAFETY], "platform": "Windows", "day_of_week": FS_WEEKDAYS.index(weekday),
        "start_hour": 7, "start_minute": 0, "end_hour": 22, "end_minute": 30,
    }
    sync = _household(hass).sync
    [record] = sync.windows.values()
    assert (record["begin"], record["end"], record["target"]) == (420, 1320, 1350)
    assert record["written_at"] is not None

    # Today it reads Hearth's: watched
    _windows(hass, end="22:30:00")
    await sync.async_windows_tick()
    assert record["seen"] == "hearth"
    assert len(calls["set_screentime_intervals"]) == 1

    # Past midnight the weekday's own entities still read Hearth's window: it goes back
    freezer.move_to(dt_util.now().replace(hour=0, minute=1) + timedelta(days=1))
    _weekday_entities(hass, weekday, "07:00:00", "22:30:00")
    await sync.async_windows_tick()
    back = calls["set_screentime_intervals"][-1].data
    assert back["day_of_week"] == FS_WEEKDAYS.index(weekday)
    assert (back["end_hour"], back["end_minute"]) == (22, 0)
    assert sync.windows == {}
    status = _household(hass).enforcement.status_of("person.sam")["family_safety"]
    assert status["last"]["allowed_hours_back"] == ["Windows"]


async def test_a_parent_s_change_of_the_moved_hours_stays_after_midnight(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator, freezer
) -> None:
    calls = await _windows_extra_time_at(hass, hass_client_no_auth, freezer, _upstream)
    sync = _household(hass).sync
    # A parent set 23:00 in the Family Safety app since; after midnight the weekday can't be read
    freezer.tick(timedelta(minutes=5))
    _windows(hass, end="23:00:00")
    await sync.async_windows_tick()
    freezer.move_to(dt_util.now().replace(hour=0, minute=1) + timedelta(days=1))
    await sync.async_windows_tick()
    assert len(calls["set_screentime_intervals"]) == 1
    assert sync.windows == {}


async def test_a_missed_midnight_is_put_back_after_a_restart(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator, freezer
) -> None:
    calls = await _windows_extra_time_at(hass, hass_client_no_auth, freezer, _upstream)
    weekday = fs_weekday(dt_util.now())
    household = _household(hass)
    await household.async_flush()
    household.sync.windows = {}
    # Home Assistant was off over midnight
    freezer.move_to(dt_util.now().replace(hour=7, minute=0) + timedelta(days=1))
    await household.sync.async_load()
    assert len(household.sync.windows) == 1
    _weekday_entities(hass, weekday, "07:00:00", "22:30:00")
    await household.sync.async_windows_tick()
    assert (calls["set_screentime_intervals"][-1].data["end_hour"], len(household.sync.windows)) == (22, 0)


async def test_extra_time_ended_early_puts_the_weekday_back_at_once(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator, freezer
) -> None:
    calls = await _windows_extra_time_at(hass, hass_client_no_auth, freezer, _upstream)
    _windows(hass, end="22:30:00")
    await hass.services.async_call(DOMAIN, "allow_end", {"people": ["person.sam"], "device": "fs:windows"}, blocking=True)
    await hass.async_block_till_done()
    back = calls["set_screentime_intervals"][-1].data
    assert "today_only" not in back and (back["end_hour"], back["end_minute"]) == (22, 0)
    assert _household(hass).sync.windows == {}


async def test_windows_hours_aren_t_moved_while_family_safety_keeps_a_saved_schedule(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator, freezer
) -> None:
    """Upstream's account lock (and its limits-off fallback) keeps the schedule it found as a restore point, and
    writes every Windows day changed meanwhile into it: Hearth's window would come back with the unlock for good."""
    freezer.move_to(dt_util.now().replace(hour=21, minute=46, second=0, microsecond=0))
    calls = _upstream(hass)
    _windows(hass)
    hass.states.async_set("switch.sam_lock", "on", {"user_id": ACCOUNT, "has_saved_policy": True})
    await _sam_on_family_safety(hass, hass_client_no_auth)
    await _device_bonus(hass, "fs:windows", 30)
    assert calls["set_screentime_intervals"] == []
    status = _household(hass).enforcement.status_of("person.sam")["family_safety"]
    assert "saved schedule" in status["last"]["error"]


async def test_putting_back_waits_while_family_safety_keeps_a_saved_schedule(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator, freezer
) -> None:
    calls = await _windows_extra_time_at(hass, hass_client_no_auth, freezer, _upstream)
    weekday = fs_weekday(dt_util.now())
    sync = _household(hass).sync
    # A parent locks the account after Hearth moved the hours: the lock's restore point holds Hearth's window
    hass.states.async_set("switch.sam_lock", "on", {"user_id": ACCOUNT, "has_saved_policy": True})
    _weekday_entities(hass, weekday, "00:00:00", "00:00:00")
    freezer.move_to(dt_util.now().replace(hour=0, minute=1) + timedelta(days=1))
    await sync.async_windows_tick()
    assert len(calls["set_screentime_intervals"]) == 1 and len(sync.windows) == 1

    # Unlocked: the restore point wrote Hearth's window back, which Hearth now puts back
    hass.states.async_set("switch.sam_lock", "off", {"user_id": ACCOUNT, "has_saved_policy": False})
    _weekday_entities(hass, weekday, "07:00:00", "23:59:00")
    record = next(iter(sync.windows.values()))
    record["target"] = 1440  # moved until midnight (23:59 is how the integration shows it)
    await sync.async_windows_tick()
    assert (calls["set_screentime_intervals"][-1].data["end_hour"], sync.windows) == (22, {})


# A parent's lock or extra time, told without hold attributes


async def _held_on_upstream(hass: HomeAssistant, hass_client_no_auth, freezer) -> tuple[dict, str]:
    """Sam's Xbox locked by Hearth through upstream's Family Safety (by whole hours); its Allowed Now shows the lock."""
    freezer.move_to(dt_util.now().replace(hour=12, minute=0, second=0, microsecond=0))
    calls = _upstream(hass)
    _xbox(hass)
    await _sam_on_family_safety(hass, hass_client_no_auth)
    await _budget(hass, "games", 5)
    [locked] = calls["lock_platform"]
    assert locked.data == {"account_id": str(ACCOUNT), "platform": "Xbox", "duration_hours": 12}
    held = _household(hass).enforcement.held[f"{enforce.FAMILY_SAFETY}|person.sam"]
    until = dt_util.as_local(dt_util.parse_datetime(held.restore["fs_lock_until"]["Xbox"])).isoformat()
    _xbox(hass, "off", reason="locked", override="blockUntil", override_until=until)
    freezer.tick(timedelta(minutes=2))
    await hass.async_block_till_done()
    return calls, until


async def test_hearth_s_own_lock_reads_as_its_own(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator, freezer
) -> None:
    grants = async_capture_events(hass, "hearth_parent_grant")
    await _held_on_upstream(hass, hass_client_no_auth, freezer)
    await _bonus(hass, "games", 0)
    assert grants == []
    [row] = _household(hass).sync.first_party("person.sam")["family_safety"]
    assert (row["hold"], row["hold_from"], row["parent_lock"]) == ("ours", "hearth", False)


async def test_a_parent_s_unlock_is_a_grant(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator, freezer
) -> None:
    grants = async_capture_events(hass, "hearth_parent_grant")
    calls, _ = await _held_on_upstream(hass, hass_client_no_auth, freezer)
    _xbox(hass, "on")
    await _bonus(hass, "games", 0)
    assert grants[0].data["target"] == {"kind": "platform", "value": "Xbox"}
    assert grants[0].data["reason"] == "unlocked in the Family Safety app"


async def test_a_parent_s_extra_time_is_a_grant_until_it_ends(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator, freezer
) -> None:
    grants = async_capture_events(hass, "hearth_parent_grant")
    await _held_on_upstream(hass, hass_client_no_auth, freezer)
    until = (dt_util.now() + timedelta(hours=1)).replace(microsecond=0)
    _xbox(hass, "on", reason="extra_time", override="allowUntil", override_until=until.isoformat())
    await _bonus(hass, "games", 0)
    assert grants[0].data["end_with"] == "family_safety_cancel_bonus"
    assert dt_util.parse_datetime(grants[0].data["until"]) == until


async def test_a_parent_s_longer_lock_is_their_own(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator, freezer
) -> None:
    grants = async_capture_events(hass, "hearth_parent_grant")
    _, until = await _held_on_upstream(hass, hass_client_no_auth, freezer)
    later = (dt_util.parse_datetime(until) + timedelta(hours=7)).isoformat()
    _xbox(hass, "off", reason="locked", override="blockUntil", override_until=later)
    await _bonus(hass, "games", 0)
    assert grants == []
    [lock] = _household(hass).enforcement.fs_parent_locks("person.sam")
    assert lock["until"] == later


async def test_a_parent_s_lock_shows_when_hearth_holds_nothing(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator
) -> None:
    _upstream(hass)
    _xbox(hass, "off", reason="locked", override="blockUntil", override_until="2026-11-08T07:00:00-05:00")
    await _sam_on_family_safety(hass, hass_client_no_auth)
    explained = await hass.services.async_call(
        DOMAIN, "explain", {"person": "person.sam", "group": "games"}, blocking=True, return_response=True
    )
    lock = next(b for b in explained["blocked_by"] if b["kind"] == "parent_lock")
    assert lock["platform"] == "Xbox" and dt_util.parse_datetime(lock["until"]) == dt_util.parse_datetime(
        "2026-11-08T07:00:00-05:00"
    )


async def test_unknown_locks_are_no_parent_s_change(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator, freezer
) -> None:
    grants = async_capture_events(hass, "hearth_parent_grant")
    await _held_on_upstream(hass, hass_client_no_auth, freezer)
    _xbox(hass, "unknown", reason="unknown")
    await _bonus(hass, "games", 0)
    assert grants == []


async def test_hearth_s_own_extra_time_is_its_own_and_is_cancelled(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator, freezer
) -> None:
    freezer.move_to(dt_util.now().replace(hour=12, minute=0, second=0, microsecond=0))
    calls = _upstream(hass)
    _xbox(hass, used_minutes=55)
    await _sam_on_family_safety(hass, hass_client_no_auth)
    grants = async_capture_events(hass, "hearth_parent_grant")
    response = await hass.services.async_call(
        DOMAIN, "allow", {"people": ["person.sam"], "group": "all", "until": dt_util.now().replace(hour=13).isoformat()},
        blocking=True, return_response=True,
    )
    await hass.async_block_till_done()
    [given] = calls["add_time_bonus"]
    ends = dt_util.as_local(given.data["until"].replace(tzinfo=dt_util.get_default_time_zone())).isoformat()
    _xbox(hass, "on", reason="extra_time", override="allowUntil", override_until=ends)
    [row] = _household(hass).sync.first_party("person.sam")["family_safety"]
    assert row["hold"] == "bonus_ours"

    await hass.services.async_call(DOMAIN, "allow_end", {"id": response["id"]}, blocking=True)
    await hass.async_block_till_done()
    assert [c.data["platform"] for c in calls["cancel_time_bonus"]] == ["Xbox"]
    assert grants == []


async def test_hold_attributes_still_win_where_family_safety_has_them(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator, freezer
) -> None:
    """A fork's own hold attribute says a lock is a parent's even when it ends when Hearth's would."""
    freezer.move_to(dt_util.now().replace(hour=12, minute=0, second=0, microsecond=0))
    _fork(hass)
    _xbox(hass, hold="none")
    await _sam_on_family_safety(hass, hass_client_no_auth)
    await _budget(hass, "games", 5)
    _xbox(hass, "off", hold="parent", override="blockUntil", override_until=enforce.next_midnight().isoformat())
    [row] = _household(hass).sync.first_party("person.sam")["family_safety"]
    assert (row["hold"], row["hold_from"], row["parent_lock"]) == ("parent", "attributes", True)
