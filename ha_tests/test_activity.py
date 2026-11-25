"""The action log (activity.py), hearth.get_activity, hearth/activity and diagnostics."""

from datetime import timedelta
import json
import pathlib
import re

import pytest

from homeassistant.core import Context, HomeAssistant
from homeassistant.exceptions import HomeAssistantError, Unauthorized
from pytest_homeassistant_custom_component.common import async_mock_service
from pytest_homeassistant_custom_component.typing import ClientSessionGenerator

from custom_components.hearth import enforce
from custom_components.hearth.activity import call_service, safe_args
from custom_components.hearth.const import DOMAIN
from test_people import _household_with_sam
from test_sources import _option

FAMILY_LINK = "sensor.sam_family_link_daily_screen_time"
CHILD = "424242424242424242424"


@pytest.fixture(autouse=True)
def settled(monkeypatch):
    monkeypatch.setattr(enforce, "SETTLE", timedelta(0))


def test_every_outbound_call_goes_through_the_action_log() -> None:
    """No module calls hass.services.async_call itself: Family Link, Family Safety, Nintendo and every other call
    is recorded by activity.call_service."""
    root = pathlib.Path(__file__).resolve().parent.parent / "custom_components" / "hearth"
    offenders = [
        f"{path.name}:{n}"
        for path in root.glob("*.py")
        if path.name != "activity.py"
        for n, line in enumerate(path.read_text(encoding="utf-8").splitlines(), 1)
        if re.search(r"services\.async_call\(", line)
    ]
    assert offenders == []


def test_only_ids_and_numbers_are_kept_of_a_call() -> None:
    assert safe_args(
        {"entity_id": "switch.x", "message": "Sam asks", "pin": "1234", "daily_minutes": 90, "packages": ["a.b"]}
    ) == {"entity_id": "switch.x", "daily_minutes": 90, "packages": ["a.b"]}


def _household(hass):
    return hass.config_entries.async_entries(DOMAIN)[0].runtime_data.household


async def _sam(hass, hass_client_no_auth):
    async_mock_service(hass, "familylink", "set_daily_limit")
    await _household_with_sam(hass, hass_client_no_auth)
    hass.states.async_set(FAMILY_LINK, "0", {"unit_of_measurement": "min", "child_id": CHILD})
    await _option(hass, "enforce", {"person": "person.sam", "family_link": FAMILY_LINK})
    await hass.services.async_call(
        DOMAIN, "set_budget", {"person": "person.sam", "group": "all", "minutes": 120}, blocking=True
    )
    await hass.async_block_till_done()
    return _household(hass)


async def test_calls_and_holds_are_recorded(hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator) -> None:
    household = await _sam(hass, hass_client_no_auth)
    # The backstop's write, with its person (found from the child), why and result
    [write] = [r for r in household.activity.records if r.get("service") == "familylink.set_daily_limit"]
    assert write["kind"] == "call" and write["person"] == "person.sam" and write["why"] == "backstop"
    # No Family Link device sensor: Hearth's 15 counted + 105 left + 30
    assert write["result"] == "ok" and write["args"] == {"child_id": CHILD, "daily_minutes": 150}
    assert isinstance(write["duration_ms"], int)
    # Daily time used up (15 counted): Hearth's hold starts; bonus time ends it
    await hass.services.async_call(DOMAIN, "set_budget", {"person": "person.sam", "group": "all", "minutes": 10}, blocking=True)
    await hass.async_block_till_done()
    start = [r for r in household.activity.records if r["kind"] == "hold_start"]
    assert start[-1]["person"] == "person.sam" and start[-1]["target"] == ["all"] and start[-1]["reason"] == "daily_time"
    await hass.services.async_call(DOMAIN, "add_time", {"person": "person.sam", "minutes": 30}, blocking=True)
    await hass.async_block_till_done()
    end = [r for r in household.activity.records if r["kind"] == "hold_end"]
    assert end[-1]["target"] == ["all"] and end[-1]["reason"] == "time_given"
    # Pause screens: a hold too
    await hass.services.async_call(DOMAIN, "pause", {"people": ["person.sam"], "minutes": 10}, blocking=True)
    assert household.activity.records[-1]["kind"] == "hold_start" or any(
        r["kind"] == "hold_start" and r.get("reason") == "pause" for r in household.activity.records
    )


async def test_a_failed_call_is_recorded_with_its_error(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator
) -> None:
    household = await _sam(hass, hass_client_no_auth)

    async def fail(call):
        raise HomeAssistantError("Google said no")

    hass.services.async_register("familylink", "block_app", fail)
    with pytest.raises(HomeAssistantError):
        await call_service(hass, "familylink", "block_app", {"entity_id": FAMILY_LINK, "package_name": "a.b"}, blocking=True)
    record = household.activity.records[-1]
    assert record["result"] == "failed" and record["error"] == "Google said no" and record["person"] == "person.sam"
    # A notification's text never reaches the log
    async_mock_service(hass, "notify", "mobile_app_x")
    await call_service(hass, "notify", "mobile_app_x", {"message": "Sam asks for 30 min"}, blocking=True)
    assert "args" not in household.activity.records[-1]


async def test_get_activity_and_the_websocket(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator, hass_ws_client, hass_read_only_user
) -> None:
    household = await _sam(hass, hass_client_no_auth)
    answer = await hass.services.async_call(
        DOMAIN, "get_activity", {"person": "person.sam", "kind": "call"}, blocking=True, return_response=True
    )
    assert answer["records"] and all(r["person"] == "person.sam" and r["kind"] == "call" for r in answer["records"])
    with pytest.raises(Unauthorized):
        await hass.services.async_call(
            DOMAIN, "get_activity", {}, blocking=True, return_response=True,
            context=Context(user_id=hass_read_only_user.id),
        )
    ws = await hass_ws_client(hass)
    await ws.send_json({"id": 1, "type": "hearth/activity", "person": "person.sam", "limit": 5})
    result = await ws.receive_json()
    assert result["success"] and len(result["result"]["records"]) <= 5
    assert result["result"]["records"][0]["at"] >= result["result"]["records"][-1]["at"]


async def test_diagnostics_redact_names_and_child_ids(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator
) -> None:
    from custom_components.hearth.diagnostics import async_get_config_entry_diagnostics

    await _sam(hass, hass_client_no_auth)
    await hass.services.async_call(DOMAIN, "add_time", {"person": "person.sam", "minutes": 30}, blocking=True)
    entry = hass.config_entries.async_entries(DOMAIN)[0]
    body = await async_get_config_entry_diagnostics(hass, entry)
    text = json.dumps(body)
    assert body["activity"] and "kids" in body and "options" in body
    assert CHILD not in text and "Sam" not in text and "person.sam" not in text and "sam_" not in text


async def test_diagnostics_redact_pin_hashes_errors_and_named_devices(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator
) -> None:
    from custom_components.hearth.diagnostics import async_get_config_entry_diagnostics

    household = await _sam(hass, hass_client_no_auth)
    hass.states.async_set("person.sam", "home", {"friendly_name": "Sam Rivera"})
    pin_hash = "v2$100000$" + "a" * 32 + "$" + "b" * 64
    entry = hass.config_entries.async_entries(DOMAIN)[0]
    hass.config_entries.async_update_entry(
        entry,
        options={
            **entry.options,
            "parent_pins": {"person.alex": pin_hash},
            "push_server": "https://ntfy.example.org",
            "ask_notify": "mobile_app_sams_phone",
            "extra": [pin_hash],
        },
    )
    await hass.async_block_till_done()
    household = _household(hass)
    async_mock_service(hass, "notify", "mobile_app_rivera_sam_tablet")
    await call_service(hass, "notify", "mobile_app_rivera_sam_tablet", {"message": "x"}, blocking=True)
    household.activity.add("call", person="person.sam", service="familylink.pause_app", result="failed",
                           error="Sam's phone (Sam Rivera) didn't answer", target=["switch.sams_pixel"])
    body = await async_get_config_entry_diagnostics(hass, entry)
    text = json.dumps(body)
    assert pin_hash not in text and "ntfy.example.org" not in text and "didn't answer" not in text
    for name in ("Sam", "sam", "Rivera", "rivera"):
        assert name not in text, name


async def test_backstop_leaves_a_switched_off_daily_limit_alone(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator
) -> None:
    """With the child's daily limit switched off, Family Link writes the weekday's own limit (every week): nothing is
    written then."""
    from homeassistant.helpers import entity_registry as er

    er.async_get(hass).async_get_or_create(
        "switch", "familylink", f"familylink_{CHILD}_daily_limit", suggested_object_id="sam_family_link_daily_limit"
    )
    hass.states.async_set("switch.sam_family_link_daily_limit", "off")
    household = await _sam(hass, hass_client_no_auth)
    assert not [r for r in household.activity.records if r.get("service") == "familylink.set_daily_limit"]
    # Switched on: the backstop writes
    hass.states.async_set("switch.sam_family_link_daily_limit", "on")
    household.backstop.check()
    await hass.async_block_till_done()
    assert [r for r in household.activity.records if r.get("service") == "familylink.set_daily_limit"]


async def test_holds_outlive_a_flood_of_calls_for_14_days(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator
) -> None:
    """Calls are capped by their own count: a week of them never pushes a hold record out (the stray-pause release
    reads a week of holds). Only age does, at 14 days."""
    from homeassistant.util import dt as dt_util

    from custom_components.hearth import activity as activity_module

    household = await _sam(hass, hass_client_no_auth)
    log = household.activity
    log.records.clear()
    old = log.add("hold_start", person="person.sam", target=["com.example.game"], reason="limit", by="family_link")
    old["at"] = (dt_util.utcnow() - timedelta(days=13, hours=23)).isoformat()
    older = log.add("hold_start", person="person.sam", target=["com.example.old"], reason="limit", by="family_link")
    older["at"] = (dt_util.utcnow() - timedelta(days=14, hours=1)).isoformat()
    log.records.sort(key=lambda r: r["at"])
    for n in range(activity_module.MAX_RECORDS + 1500):
        log.add("call", person="person.sam", service="familylink.pause_app", args={"n": n}, result="ok")
    calls = [r for r in log.records if r["kind"] == "call"]
    assert activity_module.MAX_RECORDS <= len(calls) <= activity_module.MAX_RECORDS + activity_module.TRIM_EVERY
    # The newest calls are the ones kept
    assert calls[-1]["args"] == {"n": activity_module.MAX_RECORDS + 1499}
    holds = log.query("person.sam", "hold_start", since=dt_util.utcnow() - timedelta(days=14), limit=5000)
    assert [r["target"] for r in holds] == [["com.example.game"]]
    assert older not in log.records

    # Each other kind has its own room too: the oldest of that kind go first, the calls stay
    for n in range(activity_module.MAX_OTHER + 250):
        log.add("hold_end", person="person.sam", target=[f"app{n}"], reason="time_given", by="hearth")
    log._trim()
    ends = [r for r in log.records if r["kind"] == "hold_end"]
    assert len(ends) == activity_module.MAX_OTHER and ends[-1]["target"] == [f"app{activity_module.MAX_OTHER + 249}"]
    assert old in log.records
    assert len([r for r in log.records if r["kind"] == "call"]) >= activity_module.MAX_RECORDS


async def test_a_quiet_read_is_recorded_only_when_it_fails(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator
) -> None:
    """The Nintendo applications list is read every 10 minutes (about 850 records a day): it no longer fills the
    log."""
    from homeassistant.core import SupportsResponse

    household = await _sam(hass, hass_client_no_auth)
    fail = False

    async def listing(call):
        if fail:
            raise HomeAssistantError("console not found")
        return {"applications": []}

    hass.services.async_register("nintendo_parental_controls", "list_applications", listing,
                                 supports_response=SupportsResponse.ONLY)
    listed = lambda: [  # noqa: E731
        r for r in household.activity.records if r.get("service") == "nintendo_parental_controls.list_applications"
    ]
    response = await call_service(hass, "nintendo_parental_controls", "list_applications", {"device_id": "d"},
                                  blocking=True, return_response=True, why="outside_apps", quiet=True)
    assert response == {"applications": []} and listed() == []
    fail = True
    with pytest.raises(HomeAssistantError):
        await call_service(hass, "nintendo_parental_controls", "list_applications", {"device_id": "d"},
                           blocking=True, return_response=True, why="outside_apps", quiet=True)
    [record] = listed()
    assert record["result"] == "failed" and record["why"] == "outside_apps"
    # A read that isn't marked quiet is recorded as before
    fail = False
    await call_service(hass, "nintendo_parental_controls", "list_applications", {"device_id": "d"},
                       blocking=True, return_response=True)
    assert len(listed()) == 2


async def test_every_app_of_a_call_is_hearths_from_the_moment_it_starts(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator
) -> None:
    """own_call: a call's whole app list (a record keeps the first 50), while it runs and after, kept over a
    restart."""
    import asyncio

    from homeassistant.util import dt as dt_util

    from custom_components.hearth.activity import ActivityLog

    household = await _sam(hass, hass_client_no_auth)
    log = household.activity
    packages = [f"com.example.app{n:03d}" for n in range(150)]
    started, release = asyncio.Event(), asyncio.Event()

    async def resume(call):
        started.set()
        await release.wait()

    hass.services.async_register("familylink", "resume_app", resume)
    task = asyncio.create_task(
        call_service(hass, "familylink", "resume_app", {"entity_id": FAMILY_LINK, "packages": packages}, blocking=True)
    )
    await started.wait()
    own = {"familylink.resume_app"}
    later = dt_util.utcnow() + timedelta(hours=1)
    # Still running: no record yet, and every app is known as Hearth's, whatever the window
    assert not [r for r in log.records if r.get("service") == "familylink.resume_app"]
    assert log.own_call(own, packages[0], later) and log.own_call(own, packages[149], later)
    assert not log.own_call(own, "com.example.never", later)
    assert not log.own_call({"familylink.block_app"}, packages[149], later)
    release.set()
    await task
    [record] = [r for r in log.records if r.get("service") == "familylink.resume_app"]
    assert len(record["args"]["packages"]) == 50
    # Ended: Hearth's since any time up to the call's end, not after it
    assert log.own_call(own, packages[149], dt_util.utcnow() - timedelta(minutes=30))
    assert not log.own_call(own, packages[149], later)

    # Kept over a restart
    await log.async_flush()
    again = ActivityLog(hass, household, log._store.key.removeprefix("hearth.activity."))
    await again.async_load()
    assert again.own_call(own, packages[149], dt_util.utcnow() - timedelta(minutes=30))

    # A failed call's apps are Hearth's too (it may have changed some before it failed)
    async def boom(call):
        raise HomeAssistantError("Family Link did not take the app limit")

    hass.services.async_register("familylink", "pause_app", boom)
    with pytest.raises(HomeAssistantError):
        await call_service(hass, "familylink", "pause_app", {"packages": packages}, blocking=True)
    assert log.own_call({"familylink.pause_app"}, packages[100], dt_util.utcnow() - timedelta(minutes=1))
    assert log._running == {}
