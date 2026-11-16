"""Hearth on the released Microsoft Family Safety (upstream's 2.3.0) and on one that carries more (a fork with today-only
allowed hours and hold attributes): what each can do, allowed hours Hearth moves and puts back itself, and a parent's
own lock or extra time told from Hearth's without Family Safety saying whose."""

from datetime import timedelta

import voluptuous as vol

from homeassistant.core import HomeAssistant, ServiceCall, SupportsResponse
from homeassistant.exceptions import HomeAssistantError
from homeassistant.helpers import config_validation as cv
from homeassistant.helpers import entity_registry as er
from homeassistant.util import dt as dt_util
from pytest_homeassistant_custom_component.common import (
    MockConfigEntry,
    async_capture_events,
    async_fire_time_changed,
    async_mock_service,
)
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


def _upstream(hass: HomeAssistant, answers: dict | None = None, fail_bonus: bool = False) -> dict[str, list[ServiceCall]]:
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
            if _service == "add_time_bonus" and fail_bonus:
                raise HomeAssistantError("Microsoft did not confirm the Xbox extra time (HTTP 500 for 1234567890)")
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
            "set_screentime_intervals", "pause_app", "resume_app", "sync_site_list", "get_sites", "block_website",
            "remove_website",
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


PENDING = "sensor.sam_pending_requests"


def _pending(hass: HomeAssistant, requests: list[dict] | None, state: str | None = None) -> None:
    """Sam's Pending Requests sensor as upstream's has it: the count, and Microsoft's requests (None: no attribute)."""
    er.async_get(hass).async_get_or_create(
        "sensor", FS, f"entry_{ACCOUNT}_pending_requests", suggested_object_id="sam_pending_requests"
    )
    attrs = {"user_id": str(ACCOUNT)} if requests is None else {"user_id": str(ACCOUNT), "requests": requests}
    hass.states.async_set(PENDING, state if state is not None else str(len(requests or [])), attrs)


def _request(request_id: str, platform: str = "Xbox") -> dict:
    return {"puid": str(ACCOUNT), "id": request_id, "type": "ScreenTime", "platform": platform,
            "requestedTime": 3600, "displayName": "A Game"}


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
    for service in ("get_sites", "block_website", "remove_website"):
        async_mock_service(hass, FS, service)
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
        "request_events": False,
        "pending_requests": False,
        "site_list_sync": False,
        "website_lists": True,
    }
    _pending(hass, [])
    found["pending_requests"] = True
    ws = await hass_ws_client(hass)
    await ws.send_json({"id": 1, "type": "hearth/config"})
    config = (await ws.receive_json())["result"]
    assert config["capabilities"]["family_safety"] == found
    [row] = config["parental_controls"]
    assert len(row["reduced"]) == 4
    assert "puts them back after midnight" in row["reduced"][0]
    assert "by what Hearth asked for" in row["reduced"][1]
    assert "whole hours" in row["reduced"][2] and "unlocks them itself at midnight" in row["reduced"][2]
    assert "Pending Requests sensors" in row["reduced"][3] and "two of its updates" in row["reduced"][3]
    # Without get_sites, block_website and remove_website the website list doesn't reach it
    hass.services.async_remove(FS, "remove_website")
    assert fs_capabilities.reduced(fs_capabilities.capabilities(hass))[-1] == (
        "The website block list doesn't reach Family Safety."
    )


async def test_a_family_safety_with_today_only_and_hold_attributes_has_it_all(hass: HomeAssistant) -> None:
    from custom_components.hearth.fs_requests import EVENTS_SEEN

    _fork(hass)
    hass.data[EVENTS_SEEN] = True
    hass.states.async_set("sensor.sam_pending_requests", "0", {"user_id": ACCOUNT, "requests": []})
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


# Extra time whose write failed, applied by Microsoft anyway


async def _failed_extra_time(hass: HomeAssistant, hass_client_no_auth, freezer, install) -> tuple[dict, str, str]:
    """Sam's Xbox about to run out (5 of 60 minutes left); an allow of All screen time until 13:00 whose Family Safety
    extra time write fails. (calls, the allow's id, the until asked for as local ISO)."""
    freezer.move_to(dt_util.now().replace(hour=12, minute=0, second=0, microsecond=0))
    calls = install(hass)
    _xbox(hass, used_minutes=55)
    await _sam_on_family_safety(hass, hass_client_no_auth)
    until = dt_util.now().replace(hour=13)
    response = await hass.services.async_call(
        DOMAIN, "allow", {"people": ["person.sam"], "group": "all", "until": until.isoformat()},
        blocking=True, return_response=True,
    )
    await hass.async_block_till_done()
    assert len(calls["add_time_bonus"]) == 1
    return calls, response["id"], until.isoformat()


async def test_extra_time_applied_although_its_write_failed_is_hearth_s_own(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator, freezer, caplog
) -> None:
    grants = async_capture_events(hass, "hearth_parent_grant")
    calls, allow_id, until = await _failed_extra_time(
        hass, hass_client_no_auth, freezer, lambda h: _upstream(h, fail_bonus=True)
    )
    sync = _household(hass).sync
    assert [e["platform"] for e in sync.possibly_given] == ["Xbox"]

    # Two minutes later Family Safety shows extra time on the Xbox ending when Hearth asked
    freezer.tick(timedelta(minutes=2))
    _xbox(hass, "on", reason="extra_time", override="allowUntil", override_until=until)
    await sync.async_pending_tick()
    assert sync.possibly_given == []
    [warning] = [r for r in caplog.records if r.levelname == "WARNING" and "write failed" in r.getMessage()]
    text = warning.getMessage()
    assert "Xbox" in text and "HTTP 500" in text and "didn't confirm was applied anyway" in text
    assert "123456" not in text and "1234567890" not in text and "Sam" not in text

    # Hearth's own: no parent's grant, and ending the allow cancels it
    await _bonus(hass, "all", 0)
    assert grants == []
    [row] = _household(hass).sync.first_party("person.sam")["family_safety"]
    assert row["hold"] == "bonus_ours"
    await hass.services.async_call(DOMAIN, "allow_end", {"id": allow_id}, blocking=True)
    await hass.async_block_till_done()
    assert [c.data["platform"] for c in calls["cancel_time_bonus"]] == ["Xbox"]


async def test_a_failed_write_that_never_shows_is_dropped(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator, freezer, caplog
) -> None:
    caplog.set_level("INFO")
    calls, _, _ = await _failed_extra_time(hass, hass_client_no_auth, freezer, lambda h: _upstream(h, fail_bonus=True))
    sync = _household(hass).sync
    freezer.tick(timedelta(minutes=5))
    await sync.async_pending_tick()
    assert len(sync.possibly_given) == 1
    freezer.tick(timedelta(minutes=6))
    await sync.async_pending_tick()
    assert sync.possibly_given == []
    assert any("was not applied" in r.getMessage() for r in caplog.records if r.levelname == "INFO")
    # Nothing is ever cancelled blind
    assert calls["cancel_time_bonus"] == []


async def test_a_failed_write_is_still_watched_after_a_restart(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator, freezer, caplog
) -> None:
    _, _, until = await _failed_extra_time(hass, hass_client_no_auth, freezer, lambda h: _upstream(h, fail_bonus=True))
    household = _household(hass)
    await household.async_flush()
    household.sync.possibly_given = []
    await household.sync.async_load()
    assert len(household.sync.possibly_given) == 1
    freezer.tick(timedelta(minutes=3))
    _xbox(hass, "on", reason="extra_time", override="allowUntil", override_until=until)
    await household.sync.async_pending_tick()
    assert household.sync.possibly_given == []
    assert any("write failed" in r.getMessage() for r in caplog.records if r.levelname == "WARNING")
    assert household.sync.fs_bonus_until("person.sam", "Xbox") is not None


async def test_applied_after_its_reason_ended_it_s_cancelled_as_hearth_s(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator, freezer
) -> None:
    calls, allow_id, until = await _failed_extra_time(
        hass, hass_client_no_auth, freezer, lambda h: _upstream(h, fail_bonus=True)
    )
    await hass.services.async_call(DOMAIN, "allow_end", {"id": allow_id}, blocking=True)
    await hass.async_block_till_done()
    assert calls["cancel_time_bonus"] == []
    _xbox(hass, "on", reason="extra_time", override="allowUntil", override_until=until)
    await _household(hass).sync.async_pending_tick()
    assert [c.data["platform"] for c in calls["cancel_time_bonus"]] == ["Xbox"]


async def test_a_fork_s_hold_attributes_confirm_it(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator, freezer, caplog
) -> None:
    def fork_failing(h: HomeAssistant) -> dict:
        calls = _fork(h)
        given: list[ServiceCall] = []

        async def add_time_bonus(call: ServiceCall):
            given.append(call)
            raise HomeAssistantError("timed out")

        h.services.async_register(FS, "add_time_bonus", add_time_bonus, supports_response=SupportsResponse.OPTIONAL)
        return {**calls, "add_time_bonus": given}

    _, _, until = await _failed_extra_time(hass, hass_client_no_auth, freezer, fork_failing)
    _xbox(hass, "on", hold="bonus_ours", override="allowUntil", allow_until=until, override_until=until)
    await _household(hass).sync.async_pending_tick()
    assert _household(hass).sync.possibly_given == []
    [row] = _household(hass).sync.first_party("person.sam")["family_safety"]
    assert (row["hold"], row["hold_from"]) == ("bonus_ours", "attributes")
    assert any("write failed" in r.getMessage() for r in caplog.records if r.levelname == "WARNING")


# Requests from an Xbox or PC, read from the Pending Requests sensor


async def _sam_with_pending(hass: HomeAssistant, hass_client_no_auth, requests: list[dict]):
    """Sam with Family Safety, his Pending Requests sensor reading [requests] when Hearth starts. The hub."""
    _upstream(hass)
    _pending(hass, requests)
    await _sam_on_family_safety(hass, hass_client_no_auth)
    await hass.async_block_till_done()
    return hass.config_entries.async_entries(DOMAIN)[0].runtime_data


async def test_a_new_request_on_the_sensor_is_an_ask_as_the_event_makes(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator, freezer
) -> None:
    asked = async_capture_events(hass, "hearth_more_time_requested")
    answers = async_capture_events(hass, "hearth_more_time_answered")
    hub = await _sam_with_pending(hass, hass_client_no_auth, [_request("old")])
    # What was pending at the first reading is learned, not announced
    assert hub.asks.pending() == []

    _pending(hass, [_request("old"), _request("r1", "Windows")])
    await hass.async_block_till_done()
    [ask] = hub.asks.pending()
    assert (ask.person, ask.external_id, ask.platform, ask.app_name) == ("person.sam", "r1", "Windows", "A Game")
    assert len(asked) == 1

    # Gone from the list: resolved at the first fresh reading without it, once the rest of that poll had a moment
    # to land (extra time on Allowed Now would make it an approval)
    _pending(hass, [_request("old")])
    await hass.async_block_till_done()
    assert len(hub.asks.pending()) == 1
    freezer.tick(timedelta(seconds=6))
    async_fire_time_changed(hass)
    await hass.async_block_till_done()
    assert hub.asks.pending() == []
    assert answers[-1].data["status"] == "handled" and answers[-1].data["answered_in"] == "family_safety"


async def test_a_request_back_in_the_list_isn_t_resolved(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator, freezer
) -> None:
    hub = await _sam_with_pending(hass, hass_client_no_auth, [])
    _pending(hass, [_request("r1")])
    await hass.async_block_till_done()
    _pending(hass, [])
    await hass.async_block_till_done()
    # Back before it was resolved (within the grace): not resolved, also when the grace's check comes
    freezer.tick(timedelta(seconds=2))
    _pending(hass, [_request("r1")])
    await hass.async_block_till_done()
    freezer.tick(timedelta(minutes=6))
    async_fire_time_changed(hass)
    await hass.async_block_till_done()
    hub.fs_requests.check()
    assert len(hub.asks.pending()) == 1


async def test_unavailable_or_no_requests_resolves_nothing(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator, freezer
) -> None:
    hub = await _sam_with_pending(hass, hass_client_no_auth, [])
    _pending(hass, [_request("r1")])
    await hass.async_block_till_done()
    for state, requests in (("unavailable", []), ("unknown", []), ("0", None)):
        _pending(hass, requests, state)
        await hass.async_block_till_done()
        freezer.tick(timedelta(minutes=6))
        hub.fs_requests.check()
        assert len(hub.asks.pending()) == 1, state
        assert hub.fs_requests.known[str(ACCOUNT)] == {"r1": None}, state


async def test_a_restart_doesn_t_announce_requests_again(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator
) -> None:
    asked = async_capture_events(hass, "hearth_more_time_requested")
    hub = await _sam_with_pending(hass, hass_client_no_auth, [])
    _pending(hass, [_request("r1")])
    await hass.async_block_till_done()
    assert len(asked) == 1
    await hub.fs_requests.async_flush()
    # A restart: the asks are kept, the tracker comes back from storage; a request that came meanwhile is new
    hub.fs_requests.known = {}
    await hub.fs_requests.async_load()
    _pending(hass, [_request("r1"), _request("r2")])
    await hass.async_block_till_done()
    assert [e.data.get("platform") for e in asked] == ["Xbox", "Xbox"]
    assert {a.external_id for a in hub.asks.pending()} == {"r1", "r2"}


async def test_the_fork_s_event_and_the_sensor_are_handled_once(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator, freezer
) -> None:
    asked = async_capture_events(hass, "hearth_more_time_requested")
    answers = async_capture_events(hass, "hearth_more_time_answered")
    hub = await _sam_with_pending(hass, hass_client_no_auth, [])
    # The event first, then the sensor
    hass.bus.async_fire(FS + "_request", {"account_id": str(ACCOUNT), "request_id": "r1", "platform": "Xbox"})
    await hass.async_block_till_done()
    _pending(hass, [_request("r1")])
    await hass.async_block_till_done()
    # The sensor first, then the event
    _pending(hass, [_request("r1"), _request("r2")])
    await hass.async_block_till_done()
    hass.bus.async_fire(FS + "_request", {"account_id": str(ACCOUNT), "request_id": "r2", "platform": "Xbox"})
    await hass.async_block_till_done()
    assert len(asked) == 2 and len(hub.asks.pending()) == 2

    # Resolved by the event; the sensor catching up later changes nothing
    hass.bus.async_fire(
        FS + "_request_resolved", {"account_id": str(ACCOUNT), "request_id": "r1", "outcome": "denied", "via": "app"}
    )
    await hass.async_block_till_done()
    _pending(hass, [_request("r1"), _request("r2")])
    _pending(hass, [_request("r2")])
    await hass.async_block_till_done()
    freezer.tick(timedelta(minutes=6))
    hub.fs_requests.check()
    assert [a.data["status"] for a in answers] == ["denied"]
    assert len(asked) == 2
    assert hub.fs_requests.known[str(ACCOUNT)] == {"r2": None}


# Locks by whole hours ended at midnight by Hearth


async def _locked_by_hours(hass: HomeAssistant, hass_client_no_auth, freezer) -> tuple[dict, object, str]:
    """Sam's Xbox locked by Hearth at 12:10 through upstream's Family Safety: 12 whole hours, to 00:10. (calls, the
    enforcement, the lock's end as Family Safety shows it.)"""
    freezer.move_to(dt_util.now().replace(hour=12, minute=10, second=0, microsecond=0))
    calls = _upstream(hass)
    _xbox(hass)
    await _sam_on_family_safety(hass, hass_client_no_auth)
    await _budget(hass, "games", 5)
    [locked] = calls["lock_platform"]
    assert locked.data["duration_hours"] == 12
    enforcement = _household(hass).enforcement
    held = enforcement.held[f"{enforce.FAMILY_SAFETY}|person.sam"]
    assert dt_util.parse_datetime(held.restore["fs_unlock_at"]["Xbox"]) == enforce.next_midnight()
    until = dt_util.as_local(dt_util.parse_datetime(held.restore["fs_lock_until"]["Xbox"])).isoformat()
    _xbox(hass, "off", reason="locked", override="blockUntil", override_until=until)
    return calls, enforcement, until


async def test_a_lock_by_whole_hours_is_ended_at_midnight(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator, freezer
) -> None:
    grants = async_capture_events(hass, "hearth_parent_grant")
    calls, enforcement, _ = await _locked_by_hours(hass, hass_client_no_auth, freezer)
    midnight = enforce.next_midnight()
    freezer.move_to(midnight - timedelta(minutes=1))
    await enforcement.async_lock_ends_tick()
    assert calls["unlock_platform"] == []
    freezer.move_to(midnight + timedelta(seconds=30))
    await enforcement.async_lock_ends_tick()
    [unlocked] = calls["unlock_platform"]
    assert unlocked.data["platform"] == "Xbox"
    held = enforcement.held[f"{enforce.FAMILY_SAFETY}|person.sam"]
    assert "fs_unlock_at" not in held.restore and "Xbox" in held.restore["fs_lock_ended"]
    # Ended as a lock with an end would end: nothing in force now is no parent's unlock
    _xbox(hass, "on")
    await _bonus(hass, "games", 0)
    assert grants == []
    # Once: a new day lets go as before (finding nothing locked), the tick has nothing more to end
    sent = len(calls["unlock_platform"])
    await enforcement.async_lock_ends_tick()
    assert len(calls["unlock_platform"]) == sent


async def test_a_parent_s_change_cancels_the_unlock_at_midnight(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator, freezer
) -> None:
    calls, enforcement, until = await _locked_by_hours(hass, hass_client_no_auth, freezer)
    # A parent locks the Xbox longer in the Family Safety app
    later = (dt_util.parse_datetime(until) + timedelta(hours=7)).isoformat()
    _xbox(hass, "off", reason="locked", override="blockUntil", override_until=later)
    freezer.tick(timedelta(minutes=5))
    await enforcement.async_lock_ends_tick()
    held = enforcement.held[f"{enforce.FAMILY_SAFETY}|person.sam"]
    assert "fs_unlock_at" not in held.restore
    freezer.move_to(enforce.next_midnight() + timedelta(seconds=30))
    await enforcement.async_lock_ends_tick()
    assert calls["unlock_platform"] == []


async def test_a_midnight_missed_while_off_is_caught_up_after_a_restart(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator, freezer
) -> None:
    calls, enforcement, _ = await _locked_by_hours(hass, hass_client_no_auth, freezer)
    midnight = enforce.next_midnight()
    await enforcement._store.async_save(enforcement._data())
    enforcement.held = {}
    await enforcement.async_load()
    freezer.move_to(midnight + timedelta(minutes=5))
    await enforcement.async_lock_ends_tick()
    assert [c.data["platform"] for c in calls["unlock_platform"]] == ["Xbox"]


async def test_a_lock_that_ended_by_itself_isn_t_unlocked_later(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator, freezer
) -> None:
    calls, enforcement, until = await _locked_by_hours(hass, hass_client_no_auth, freezer)
    # Home Assistant was off past the lock's own end: it's over, nothing to unlock
    _xbox(hass, "on")
    freezer.move_to(dt_util.parse_datetime(until) + timedelta(minutes=5))
    await enforcement.async_lock_ends_tick()
    assert calls["unlock_platform"] == []
    held = enforcement.held[f"{enforce.FAMILY_SAFETY}|person.sam"]
    assert "fs_unlock_at" not in held.restore


async def test_letting_go_drops_the_unlock_at_midnight(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator, freezer
) -> None:
    calls, enforcement, _ = await _locked_by_hours(hass, hass_client_no_auth, freezer)
    await _budget(hass, "games", 600)
    await hass.async_block_till_done()
    assert len(calls["unlock_platform"]) == 1
    held = enforcement.held.get(f"{enforce.FAMILY_SAFETY}|person.sam")
    assert held is None or "fs_unlock_at" not in held.restore


async def test_a_lock_with_an_end_needs_no_unlock_at_midnight(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator, freezer
) -> None:
    freezer.move_to(dt_util.now().replace(hour=12, minute=10, second=0, microsecond=0))
    calls = _fork(hass)
    _xbox(hass)
    await _sam_on_family_safety(hass, hass_client_no_auth)
    await _budget(hass, "games", 5)
    [locked] = calls["lock_platform"]
    assert "until" in locked.data and "duration_hours" not in locked.data
    held = _household(hass).enforcement.held[f"{enforce.FAMILY_SAFETY}|person.sam"]
    assert "fs_unlock_at" not in held.restore


async def _gone_once(hass: HomeAssistant, hass_client_no_auth, freezer, platform: str = "Xbox"):
    """Sam's Xbox (no extra time) and a request r1 on [platform], then a reading without it. The hub."""
    _xbox(hass)
    hub = await _sam_with_pending(hass, hass_client_no_auth, [])
    _pending(hass, [_request("r1", platform)])
    await hass.async_block_till_done()
    freezer.tick(timedelta(minutes=1))
    _pending(hass, [])
    await hass.async_block_till_done()
    return hub


async def test_extra_time_showing_as_a_request_goes_is_its_approval(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator, freezer
) -> None:
    answers = async_capture_events(hass, "hearth_more_time_answered")
    hub = await _gone_once(hass, hass_client_no_auth, freezer)
    assert len(hub.asks.pending()) == 1
    until = (dt_util.now() + timedelta(minutes=60)).replace(microsecond=0)
    _xbox(hass, "on", reason="extra_time", override="allowUntil", override_until=until.isoformat())
    await hass.async_block_till_done()
    assert hub.asks.pending() == []
    assert (answers[-1].data["status"], answers[-1].data["minutes"]) == ("approved", 60)


async def test_extra_time_before_the_request_goes_counts_too(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator, freezer
) -> None:
    answers = async_capture_events(hass, "hearth_more_time_answered")
    _xbox(hass)
    hub = await _sam_with_pending(hass, hass_client_no_auth, [])
    _pending(hass, [_request("r1")])
    await hass.async_block_till_done()
    # The same poll: Allowed Now written before the Pending Requests sensor
    until = (dt_util.now() + timedelta(minutes=30)).replace(microsecond=0)
    _xbox(hass, "on", reason="extra_time", override="allowUntil", override_until=until.isoformat())
    await hass.async_block_till_done()
    _pending(hass, [])
    await hass.async_block_till_done()
    assert answers[-1].data["status"] == "approved"


async def test_extra_time_on_another_platform_or_hearth_s_own_isn_t_an_approval(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator, freezer
) -> None:
    answers = async_capture_events(hass, "hearth_more_time_answered")
    hub = await _gone_once(hass, hass_client_no_auth, freezer, "Windows")
    until = (dt_util.now() + timedelta(minutes=60)).replace(microsecond=0)
    _xbox(hass, "on", reason="extra_time", override="allowUntil", override_until=until.isoformat())
    await hass.async_block_till_done()
    assert len(hub.asks.pending()) == 1
    freezer.tick(timedelta(minutes=1))
    _pending(hass, [])
    hub.fs_requests.check()
    assert hub.asks.pending() == [] and answers[-1].data["status"] == "handled"


async def test_hearth_s_own_extra_time_isn_t_a_parent_s_approval(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator, freezer
) -> None:
    hub = await _gone_once(hass, hass_client_no_auth, freezer)
    until = (dt_util.now() + timedelta(minutes=60)).replace(microsecond=0)
    hub.household.enforcement.fs_bonus_until = lambda person, platform: until if platform == "Xbox" else None
    answers = async_capture_events(hass, "hearth_more_time_answered")
    _xbox(hass, "on", reason="extra_time", override="allowUntil", override_until=until.isoformat())
    await hass.async_block_till_done()
    assert len(hub.asks.pending()) == 1
    # Once the grace has passed: handled, not approved
    freezer.tick(timedelta(seconds=6))
    async_fire_time_changed(hass)
    await hass.async_block_till_done()
    assert hub.asks.pending() == [] and answers[-1].data["status"] == "handled"


async def test_an_older_record_of_a_gone_request_reads_as_one_reading(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator, freezer
) -> None:
    hub = await _sam_with_pending(hass, hass_client_no_auth, [])
    _pending(hass, [_request("r1")])
    await hass.async_block_till_done()
    await hub.fs_requests.async_flush()
    # An older Hearth kept when it went, as a time
    await hub.fs_requests._store.async_save(
        {"known": {str(ACCOUNT): {"r1": dt_util.utcnow().isoformat()}}, "resolved": []}
    )
    await hub.fs_requests.async_load()
    assert hub.fs_requests.known[str(ACCOUNT)]["r1"]["readings"] == 1
    freezer.tick(timedelta(minutes=1))
    _pending(hass, [])
    await hass.async_block_till_done()
    assert hub.asks.pending() == []
