"""Share Bluetooth with Home Assistant (bt_proxy.py, docs/contracts/hearth-tv.md "Bluetooth sharing"): a TV's switch,
off by default; the setting going both ways by revision; what the TV says it comes to; the proxy's key kept out of
the status, the entities and everyone but administrators; and Hearth adding the TV to ESPHome through ESPHome's own
setup steps."""

from datetime import timedelta
from unittest.mock import AsyncMock, MagicMock, patch

import pytest
from homeassistant.core import Context, HomeAssistant
from homeassistant.data_entry_flow import FlowResultType, UnknownHandler
from homeassistant.exceptions import ServiceValidationError, Unauthorized
from homeassistant.helpers import area_registry as ar, device_registry as dr, entity_registry as er
from pytest_homeassistant_custom_component.common import MockConfigEntry
from pytest_homeassistant_custom_component.typing import ClientSessionGenerator

from custom_components.hearth.bt_proxy import clean_report
from custom_components.hearth.const import DOMAIN

from test_init import STATUS, TV_ID, _pair, _post, _set_up

KEY = "AAECAwQFBgcICQoLDA0ODxAREhMUFRYXGBkaGxwdHh8="
MAC = "02:00:5e:10:00:01"
CAPS = ["events", "notices", "bluetooth_proxy"]


def _report(on: bool, rev: int = 0, changed: bool = False, state: str = "off", **more) -> dict:
    report = {"on": on, "rev": rev, "changed": changed, "state": state}
    if on:
        report.update(
            name="the-tv-bluetooth", friendly_name="The TV Bluetooth", mac=MAC, host="192.0.2.10", port=6053, key=KEY
        )
    report.update(more)
    return report


async def _tv(hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator, capable: bool = True):
    """A paired TV; [capable]: it said it can share its Bluetooth (off), so its switch is there."""
    entry = await _set_up(hass)
    client = await hass_client_no_auth()
    secret = await _pair(hass, client, name="The TV")
    await hass.async_block_till_done()
    if capable:
        await _say(client, secret, _report(False))
        await hass.async_block_till_done()
    return entry, client, secret


async def _say(client, secret: str, report: dict | None = None, caps: list[str] = CAPS) -> dict:
    body = {**STATUS, "caps": caps, **({"bluetooth_proxy": report} if report is not None else {})}
    answer = await _post(client, secret, body=body)
    assert answer.status == 200
    state = (await answer.json())["state"]
    return state


def _ids(hass: HomeAssistant) -> tuple[str, str]:
    registry = er.async_get(hass)
    switch = registry.async_get_entity_id("switch", DOMAIN, f"{TV_ID}_share_bluetooth")
    sensor = registry.async_get_entity_id("sensor", DOMAIN, f"{TV_ID}_bluetooth_sharing")
    assert switch and sensor
    return switch, sensor


async def _switch(hass: HomeAssistant, on: bool, context: Context | None = None) -> None:
    switch, _ = _ids(hass)
    await hass.services.async_call(
        "switch", "turn_on" if on else "turn_off", {"entity_id": switch}, blocking=True, context=context
    )
    await hass.async_block_till_done()


async def test_off_by_default_and_only_for_a_tv_that_can(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator
) -> None:
    _entry, client, secret = await _tv(hass, hass_client_no_auth, capable=False)
    # A Hearth TV from before: no cap, no key in its document, no switch platform loaded for it
    state = await _say(client, secret, caps=["events", "notices"])
    await hass.async_block_till_done()
    assert "bluetooth_proxy" not in state
    assert "switch" not in hass.config.components
    # One that can: its switch, off, at revision 0
    state = await _say(client, secret, _report(False))
    await hass.async_block_till_done()
    switch, sensor = _ids(hass)
    assert state["bluetooth_proxy"] == {"on": False, "rev": 0, "area": None}
    assert hass.states.get(switch).state == "off"
    assert hass.states.get(sensor).state == "off"


async def test_home_assistant_turns_a_tv_on_and_the_tv_says_what_it_comes_to(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator
) -> None:
    entry, client, secret = await _tv(hass, hass_client_no_auth)
    area = ar.async_get(hass).async_create("Upstairs")
    device = dr.async_get(hass).async_get_device_by_identifier((DOMAIN, TV_ID), entry.entry_id)
    dr.async_get(hass).async_update_device(device.id, area_id=area.id)
    await _say(client, secret, _report(False))
    switch, sensor = _ids(hass)

    await _switch(hass, True)
    assert hass.states.get(switch).state == "on"
    # The TV hears it with its area, for ESPHome's suggested area; it has no permissions yet and says so
    with patch("custom_components.hearth.bt_proxy.BluetoothProxies._maybe_add_to_esphome"):
        state = await _say(client, secret, _report(False, 0))
        assert state["bluetooth_proxy"] == {"on": True, "rev": 1, "area": "Upstairs"}
        state = await _say(client, secret, {"on": True, "rev": 1, "changed": False, "state": "needs_permission"})
        await hass.async_block_till_done()
    assert hass.states.get(sensor).state == "needs_permission"
    assert hass.states.get(switch).state == "on"
    assert state["bluetooth_proxy"]["rev"] == 1


async def test_a_change_made_on_the_tv_is_taken_and_a_later_one_here_wins(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator
) -> None:
    _entry, client, secret = await _tv(hass, hass_client_no_auth)
    switch, _ = _ids(hass)
    with patch("custom_components.hearth.bt_proxy.BluetoothProxies._maybe_add_to_esphome"):
        # Turned on on the TV, against revision 0: taken, revision 1
        state = await _say(client, secret, _report(True, 0, changed=True, state="running"))
        await hass.async_block_till_done()
        assert state["bluetooth_proxy"]["on"] is True and state["bluetooth_proxy"]["rev"] == 1
        assert hass.states.get(switch).state == "on"
        # Turned off here (2) while the TV, not having heard, says off against 1 as its own change: Home Assistant's
        # later change stands
        await _switch(hass, False)
        state = await _say(client, secret, _report(True, 1, changed=True, state="running"))
        await hass.async_block_till_done()
        assert state["bluetooth_proxy"] == {"on": False, "rev": 2, "area": None}
        assert hass.states.get(switch).state == "off"
        # A TV whose value is from a revision Home Assistant no longer has (its record started again): the TV's
        state = await _say(client, secret, _report(True, 7, state="running"))
        assert state["bluetooth_proxy"]["on"] is True and state["bluetooth_proxy"]["rev"] == 8


async def test_the_key_stays_out_of_the_status_and_the_entities(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator, hass_admin_user, hass_read_only_user
) -> None:
    entry, client, secret = await _tv(hass, hass_client_no_auth)
    with patch("custom_components.hearth.bt_proxy.BluetoothProxies._maybe_add_to_esphome"):
        await _say(client, secret, _report(True, 0, changed=True, state="running"))
    await hass.async_block_till_done()
    hub = entry.runtime_data
    assert "key" not in hub.state(TV_ID).status["bluetooth_proxy"]
    assert KEY not in repr(hub._data_to_save())
    for entity_id in _ids(hass):
        assert KEY not in repr(hass.states.get(entity_id).as_dict())

    # An administrator reads it, for ESPHome by hand
    answer = await hass.services.async_call(
        DOMAIN, "get_tv_bluetooth", {}, blocking=True, return_response=True,
        context=Context(user_id=hass_admin_user.id),
    )
    tv = answer["tvs"][TV_ID]
    assert tv["noise_psk"] == KEY and tv["host"] == "192.0.2.10" and tv["mac"] == MAC and tv["port"] == 6053
    assert tv["name"] == "the-tv-bluetooth" and tv["on"] is True and tv["state"] == "running"
    # Nobody else, and no automation
    for context in (Context(user_id=hass_read_only_user.id), Context()):
        with pytest.raises(Unauthorized):
            await hass.services.async_call(
                DOMAIN, "get_tv_bluetooth", {}, blocking=True, return_response=True, context=context
            )


async def test_only_an_adult_switches_it(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator, hass_admin_user
) -> None:
    entry, client, secret = await _tv(hass, hass_client_no_auth)
    await _say(client, secret, _report(False))
    bt_proxy = entry.runtime_data.bt_proxy
    # A user who may control entities but isn't an adult on Hearth's page (a kid's own login, say): refused
    kid = await hass.auth.async_create_user("Sam", group_ids=["system-users"])
    with pytest.raises(ServiceValidationError):
        await _switch(hass, True, Context(user_id=kid.id))
    assert not bt_proxy.wanted(TV_ID)
    # An administrator, and an automation (no user)
    await _switch(hass, True, Context(user_id=hass_admin_user.id))
    assert bt_proxy.wanted(TV_ID)
    await _switch(hass, False)
    assert not bt_proxy.wanted(TV_ID)


async def test_hearth_adds_a_running_tv_to_esphome(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator
) -> None:
    _entry, client, secret = await _tv(hass, hass_client_no_auth)
    _, sensor = _ids(hass)
    flows = hass.config_entries.flow
    init = AsyncMock(return_value={"type": FlowResultType.FORM, "step_id": "encryption_key", "flow_id": "f1"})
    made: list[MockConfigEntry] = []

    async def created(*_args):
        # ESPHome's entry, as its flow makes it
        made.append(MockConfigEntry(domain="esphome", unique_id=MAC, data={"host": "192.0.2.10", "noise_psk": KEY}))
        made[-1].add_to_hass(hass)
        return {"type": FlowResultType.CREATE_ENTRY, "flow_id": "f1"}

    configure = AsyncMock(side_effect=created)
    abort = MagicMock()
    with patch.object(flows, "async_init", init), patch.object(flows, "async_configure", configure), patch.object(
        flows, "async_abort", abort
    ):
        # Asking for permission: not yet
        await _say(client, secret, _report(True, 0, changed=True, state="needs_permission"))
        await hass.async_block_till_done()
        init.assert_not_called()
        await _say(client, secret, _report(True, 1, state="running"))
        await hass.async_block_till_done()
    init.assert_awaited_once()
    assert init.await_args.args == ("esphome",)
    assert init.await_args.kwargs["context"] == {"source": "user"}
    assert init.await_args.kwargs["data"] == {"host": "192.0.2.10", "port": 6053}
    configure.assert_awaited_once_with("f1", {"noise_psk": KEY})
    abort.assert_not_called()
    assert hass.states.get(sensor).attributes["esphome"] == "added"

    # The owner deletes it in ESPHome (as if: removing it here would load ESPHome): not added back on its own, even
    # later...
    with patch.object(flows, "async_init", init), patch.object(flows, "async_configure", configure), patch(
        "custom_components.hearth.bt_proxy.RETRY_AFTER", timedelta(0)
    ), patch("custom_components.hearth.bt_proxy.BluetoothProxies.esphome_entry", return_value=None):
        await _say(client, secret, _report(True, 1, state="running"))
        await hass.async_block_till_done()
        assert init.await_count == 1
        assert hass.states.get(sensor).attributes["esphome"] == "removed"
        # ...until the switch is turned off and on again
        await _switch(hass, False)
        await _switch(hass, True)
        await _say(client, secret, _report(True, 3, state="running"))
        await hass.async_block_till_done()
        assert init.await_count == 2


async def test_an_esphome_entry_already_there_is_left_alone(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator
) -> None:
    _entry, client, secret = await _tv(hass, hass_client_no_auth)
    _, sensor = _ids(hass)
    MockConfigEntry(domain="esphome", unique_id=MAC, data={"host": "192.0.2.99"}).add_to_hass(hass)
    init = AsyncMock()
    with patch.object(hass.config_entries.flow, "async_init", init):
        await _say(client, secret, _report(True, 0, changed=True, state="running"))
        await hass.async_block_till_done()
    init.assert_not_called()
    assert hass.states.get(sensor).attributes["esphome"] == "exists"


async def test_a_step_hearth_does_not_answer_ends_the_flow_and_esphome_missing_is_said(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator
) -> None:
    entry, client, secret = await _tv(hass, hass_client_no_auth)
    _, sensor = _ids(hass)
    flows = hass.config_entries.flow
    init = AsyncMock(return_value={"type": FlowResultType.FORM, "step_id": "encryption_key", "flow_id": "f2"})
    # A wrong key (or a name conflict): ESPHome shows its form again
    configure = AsyncMock(
        return_value={
            "type": FlowResultType.FORM, "step_id": "encryption_key", "flow_id": "f2", "errors": {"base": "invalid_psk"}
        }
    )
    abort = MagicMock()
    with patch.object(flows, "async_init", init), patch.object(flows, "async_configure", configure), patch.object(
        flows, "async_abort", abort
    ):
        await _say(client, secret, _report(True, 0, changed=True, state="running"))
        await hass.async_block_till_done()
        abort.assert_called_once_with("f2")
        attributes = hass.states.get(sensor).attributes
        assert attributes["esphome"] == "failed" and attributes["esphome_detail"] == "invalid_psk"
        # Not tried again at once
        await _say(client, secret, _report(True, 1, state="running"))
        await hass.async_block_till_done()
        assert init.await_count == 1

    # ESPHome not installed: said, nothing else
    entry.runtime_data.bt_proxy._setup.clear()
    with patch.object(flows, "async_init", AsyncMock(side_effect=UnknownHandler("esphome"))):
        await _say(client, secret, _report(True, 1, state="running"))
        await hass.async_block_till_done()
    assert hass.states.get(sensor).attributes["esphome"] == "esphome_unavailable"


def test_a_report_is_made_safe() -> None:
    assert clean_report(None) is None
    assert clean_report({"on": "yes"}) is None
    cleaned = clean_report(
        {"on": True, "rev": -3, "changed": "yes", "state": "exploded", "name": "Not A Name!",
         "mac": "03:00:00:00:00:01", "host": "8.8.8.8", "port": 99999, "key": "short"}
    )
    assert cleaned == {
        "on": True, "rev": 0, "changed": False, "state": None, "name": None, "friendly_name": None, "mac": None,
        "host": None, "port": 6053, "key": None,
    }
    good = clean_report(_report(True, 4, True, "running"))
    assert good["key"] == KEY and good["mac"] == MAC and good["host"] == "192.0.2.10"
    assert good["name"] == "the-tv-bluetooth"


async def test_a_removed_tv_takes_its_key_with_it(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator
) -> None:
    entry, client, secret = await _tv(hass, hass_client_no_auth)
    with patch("custom_components.hearth.bt_proxy.BluetoothProxies._maybe_add_to_esphome"):
        await _say(client, secret, _report(True, 0, changed=True, state="running"))
    hub = entry.runtime_data
    assert hub.bt_proxy.details(TV_ID)["noise_psk"] == KEY
    await hub.async_remove_device(TV_ID)
    await hub.bt_proxy.async_flush()
    assert TV_ID not in hub.bt_proxy._tvs
