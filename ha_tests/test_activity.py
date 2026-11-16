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
