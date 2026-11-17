"""Glint agents through Hearth HA (glint_agent.py, glint_api.py; Glint's glint-agent-ha.md, contract 1): a Glint
phone's agent documents and who writes them (G-1), the inbox etags in hearth/me (G-2), the "glint" LLM API with its
eight tools, the 20-request inbox, pruning, glint_agent_done and the doorbell (G-3), and a kid phone's state document
listing its own inbox (G-4)."""

import asyncio
from datetime import timedelta

import pytest

from homeassistant.core import Context, HomeAssistant
from homeassistant.exceptions import HomeAssistantError
from homeassistant.helpers import device_registry as dr
from homeassistant.helpers import llm
from homeassistant.util import dt as dt_util
from pytest_homeassistant_custom_component.common import async_capture_events, async_mock_service
from pytest_homeassistant_custom_component.typing import ClientSessionGenerator

from custom_components.hearth import enforce, glint_agent
from custom_components.hearth.const import DOMAIN
from custom_components.hearth.glint_agent import (
    BELL_ACTION,
    BELL_CLASS,
    EVENT_AGENT_DONE,
    INBOX,
    MAX_REQUESTS,
    OUTBOX,
    STATE,
    parse_time,
)

from test_init import NONCE, _set_up
from test_parent_pin import _adults

GLINT = "com.thesiegs.glint"
CLIENT = {"id": GLINT, "version": "2026.11.15", "contract": 3, "companions": [f"{GLINT}.phone"]}
SAM_PHONE = "phone-sam-0123456789"
ALEX_PHONE = "phone-alex-012345678"
JORDAN_PHONE = "phone-jordan-0123456"
TOOLS = {
    "glint_get_start",
    "glint_change_start",
    "glint_set_look",
    "glint_notification_rules",
    "glint_undo",
    "glint_activity",
    "glint_dnd",
    "glint_system_setting",
}


@pytest.fixture(autouse=True)
def settled(monkeypatch):
    monkeypatch.setattr(enforce, "SETTLE", timedelta(0))


@pytest.fixture(autouse=True)
def short_wait(monkeypatch):
    """A write's call waits 20 s for the phone; here a moment, unless a test answers in time."""
    monkeypatch.setattr(glint_agent, "WAIT_FOR", 0.05)


async def _pair(hass, client, device_id: str, person: str, name: str) -> str:
    hass.data.get(f"{DOMAIN}_pairing", {}).get("asked_at", {}).clear()
    body = {"device_id": device_id, "kind": "mobile", "name": name, "nonce": NONCE, "client": CLIENT}
    response = await client.post("/api/hearth/pair", json=body)
    assert response.status == 200
    pairing_id = (await response.json())["pairing_id"]
    await hass.async_block_till_done()
    flow = next(
        f for f in hass.config_entries.flow.async_progress_by_handler(DOMAIN)
        if f["context"].get("title_placeholders", {}).get("name") == name
    )
    result = await hass.config_entries.flow.async_configure(flow["flow_id"], {"person": person})
    assert result["reason"] == "paired"
    await hass.async_block_till_done()
    answer = await (await client.get(f"/api/hearth/pair/{pairing_id}", headers={"X-Hearth-Nonce": NONCE})).json()
    return answer["secret"]


ON_STATE = {"format": "glint.state/1", "contract": 1, "updated": "2026-11-15T18:00:00Z", "channel": "on"}


def _publish(hass, device_id: str, data=None) -> None:
    """Glint on the phone publishes its state document (agents on, unless [data] says otherwise)."""
    _hub(hass).client_settings.put(GLINT, ("device", device_id), STATE, "glint.state/1", data or ON_STATE, "adult")


async def _household(hass: HomeAssistant, hass_client_no_auth, alex_user=None, states: bool = True):
    """Sam (a kid), Alex and Jordan (adults), each with a Glint phone paired to Hearth and a user of their own; with
    [states], each phone has published a state document with agents on."""
    alex_user = alex_user or await hass.auth.async_create_user("Alex")
    jordan_user = await hass.auth.async_create_user("Jordan")
    sam_user = await hass.auth.async_create_user("Sam")
    hass.states.async_set("person.sam", "home", {"friendly_name": "Sam", "user_id": sam_user.id})
    hass.states.async_set("person.alex", "home", {"friendly_name": "Alex", "user_id": alex_user.id})
    hass.states.async_set("person.jordan", "home", {"friendly_name": "Jordan", "user_id": jordan_user.id})
    entry = await _set_up(hass)
    hass.config_entries.async_update_entry(entry, options={**entry.options, "roles": {"person.sam": "kid"}})
    await hass.async_block_till_done()
    await _adults(hass, "person.alex", "person.jordan")
    client = await hass_client_no_auth()
    secrets = {
        "sam": await _pair(hass, client, SAM_PHONE, "person.sam", "Sam's phone"),
        "alex": await _pair(hass, client, ALEX_PHONE, "person.alex", "Alex's phone"),
        "jordan": await _pair(hass, client, JORDAN_PHONE, "person.jordan", "Jordan's phone"),
    }
    users = {"alex": alex_user, "jordan": jordan_user, "sam": sam_user}
    if states:
        for device_id in (SAM_PHONE, ALEX_PHONE, JORDAN_PHONE):
            _publish(hass, device_id)
    return entry, client, secrets, users


def _hub(hass):
    return hass.config_entries.async_entries(DOMAIN)[0].runtime_data


def _context(user=None, platform: str = "mcp_server") -> llm.LLMContext:
    return llm.LLMContext(
        platform=platform, context=Context(user_id=user.id if user else None), language="*",
        assistant="conversation", device_id=None,
    )


async def _api(hass, user=None, platform: str = "mcp_server") -> llm.APIInstance:
    return await llm.async_get_api(hass, "glint", _context(user, platform))


async def _call(api: llm.APIInstance, tool: str, **args):
    found = next(t for t in api.tools if t.name == tool)
    return await found.async_call(api.api.hass, llm.ToolInput(tool_name=tool, tool_args=args), api.llm_context)


def _url(device_id: str, name: str) -> str:
    return f"/api/hearth/device/{device_id}/settings/device:{device_id}/{name}"


async def _phone_puts(client, secret, device_id, name, data, schema="glint.state/1"):
    """The phone (Glint) writes one of its own documents over the device API."""
    return await client.put(
        _url(device_id, name), json={"schema": schema, "data": data}, headers={"X-Hearth-Secret": secret}
    )


def _outbox(hub, device_id: str, *results) -> None:
    """Glint writes its outbox (as over the WebSocket, signed in as the phone's owner)."""
    hub.client_settings.put(
        GLINT, ("device", device_id), OUTBOX, "glint.agent-outbox/1",
        {"format": "glint.agent-outbox/1", "contract": 1, "updated": "2026-11-15T18:06:02Z", "results": list(results)},
        "adult",
    )


async def _until_requested(hub, device_id: str, count: int = 1) -> list[dict]:
    for _ in range(100):
        pending = hub.glint_agent.pending(device_id)
        if len(pending) >= count:
            return pending
        await asyncio.sleep(0)
    raise AssertionError("no request reached the inbox")


STATE_DOC = {
    "format": "glint.state/1", "contract": 1, "updated": "2026-11-15T18:06:02Z", "glint": "2026.11.15",
    "kid_phone": True, "channel": "on",
    "start": {"pages": 2, "columns": 4, "tiles": [{"id": 12, "type": "clock", "name": "clock", "size": "2x2",
                                                    "page": 1, "column": 1, "row": 1}]},
    "look": {"values": {"motion": "lively"}},
    "notify": {"tiers": [], "hidden": []},
    "phone": {"ringer": "ring", "brightness": "102 of 255"},
    "activity": [{"at": "2026-11-15T18:06:01Z", "agent": "mcp", "via": "ha", "action": "start.change", "outcome": "ok"}],
}


# G-1: who writes and reads the agent documents


async def test_the_agent_documents_have_one_writer_each(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator, hass_ws_client, hass_admin_user
) -> None:
    # The WebSocket's user is Alex (an administrator too)
    entry, client, secrets, _users = await _household(hass, hass_client_no_auth, alex_user=hass_admin_user)
    ws = await hass_ws_client(hass)
    n = iter(range(1, 100))

    async def ws_call(kind, device_id, name, client_id=GLINT, **extra):
        await ws.send_json({"id": next(n), "type": f"hearth/client_settings/{kind}", "client": client_id,
                            "scope": f"device:{device_id}", "name": name, **extra})
        return await ws.receive_json()

    doc = {"schema": "glint.agent-outbox/1", "data": {"results": []}}
    # Alex's Glint, signed in as Alex: its own outbox and state, read back
    answer = await ws_call("set", ALEX_PHONE, OUTBOX, **doc, label="agent results")
    assert answer["success"] and answer["result"]["updated_by"] == "adult"
    assert (await ws_call("set", ALEX_PHONE, STATE, schema="glint.state/1", data={"channel": "on"}))["success"]
    assert (await ws_call("get", ALEX_PHONE, STATE))["result"]["data"] == {"channel": "on"}
    # The inbox is Hearth's alone: never written or deleted over the WebSocket
    assert (await ws_call("set", ALEX_PHONE, INBOX, schema="glint.agent-inbox/1", data={}))["error"]["code"] == "forbidden"
    assert (await ws_call("delete", ALEX_PHONE, INBOX))["error"]["code"] == "forbidden"
    # Another adult's phone: neither written nor read, administrator or not
    assert (await ws_call("set", JORDAN_PHONE, OUTBOX, **doc))["error"]["code"] == "forbidden"
    assert (await ws_call("get", JORDAN_PHONE, STATE))["error"]["code"] == "forbidden"
    # Only the client the phone locked at pairing
    assert (await ws_call("set", ALEX_PHONE, OUTBOX, client_id=f"{GLINT}.debug", **doc))["error"]["code"] == "forbidden"
    # A kid's phone: an adult reads its state, never writes it
    assert (await _phone_puts(client, secrets["sam"], SAM_PHONE, STATE, STATE_DOC)).status == 200
    assert (await ws_call("get", SAM_PHONE, STATE))["result"]["data"]["kid_phone"] is True
    assert (await ws_call("set", SAM_PHONE, OUTBOX, **doc))["error"]["code"] == "forbidden"
    # Other documents in a device scope are as before
    assert (await ws_call("set", JORDAN_PHONE, "layout", schema="example.layout/1", data={}))["success"]

    # The phone's own device API: its outbox and state, never its inbox
    assert (await _phone_puts(client, secrets["sam"], SAM_PHONE, OUTBOX, {"results": []})).status == 200
    assert (await _phone_puts(client, secrets["sam"], SAM_PHONE, INBOX, {"requests": []})).status == 403
    gone = await client.delete(_url(SAM_PHONE, INBOX), headers={"X-Hearth-Secret": secrets["sam"]})
    assert gone.status == 403


# G-3: the API, the caller and the phone


async def test_the_glint_api_is_registered_with_eight_tools(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator
) -> None:
    _entry, _client, _secrets, users = await _household(hass, hass_client_no_auth)
    assert {"hearth", "glint"} <= {api.id for api in llm.async_get_apis(hass)}
    api = await _api(hass, users["alex"])
    assert {t.name for t in api.tools} == TOOLS
    assert "said" in api.api_prompt and "cards" not in api.api_prompt
    try:
        from voluptuous_openapi import convert
    except ImportError:
        convert = None
    for tool in api.tools if convert else []:
        assert convert(tool.parameters, custom_serializer=llm.selector_serializer)["type"] == "object", tool.name
    # A kid gets nothing, and every tool refuses them
    kid = await _api(hass, users["sam"])
    assert kid.tools == []
    with pytest.raises(HomeAssistantError, match="Only an adult"):
        await _call(api.__class__(api=api.api, api_prompt="", llm_context=_context(users["sam"]), tools=api.tools),
                    "glint_get_start", phone="Sam's phone")
    # A voice call with no user gets the tools, and the voice prompt
    voice = await _api(hass, platform="conversation")
    assert {t.name for t in voice.tools} == TOOLS and "voice" in voice.api_prompt


async def test_change_start_names_the_ops_glint_has(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator
) -> None:
    _entry, _client, _secrets, users = await _household(hass, hass_client_no_auth)

    def described(api) -> str:
        return next(t for t in api.tools if t.name == "glint_change_start").description

    # Glint's own list when no phone published glint.hello
    text = described(await _api(hass, users["alex"]))
    for op in ("add", "duplicate", "take_out", "name_stack", "deals_at", "remove_page"):
        assert op in text
    for gone in ("add_page", "keep_clear", "tidy"):
        assert gone not in text
    # A phone's own glint.hello list, from its state document
    hello = {"actions": [{"id": "start.change", "class": "write", "about": "change start: add, move, fold",
                          "args": "{ops: [{op: fold, tile}]}"}]}
    _publish(hass, ALEX_PHONE, {**ON_STATE, "hello": hello})
    text = described(await _api(hass, users["alex"]))
    assert "change start: add, move, fold" in text and "{ops: [{op: fold, tile}]}" in text
    # A state document that hit its size cap drops args (args_cut): back to Glint's own list
    cut = {"actions": [{"id": "start.change", "class": "write", "about": "change start: add, move, fold",
                        "args_cut": True}]}
    _publish(hass, ALEX_PHONE, {**ON_STATE, "hello": cut})
    text = described(await _api(hass, users["alex"]))
    assert "change start: add, move, fold" not in text and "remove_page" in text


async def test_two_phones_with_one_name_are_never_guessed(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator
) -> None:
    _entry, client, _secrets, users = await _household(hass, hass_client_no_auth)
    # Sam's second phone, still called by its model name; and a kid's phone named like Alex's
    await _pair(hass, client, "phone-sam-second-01", "person.sam", "Pixel 9")
    await _pair(hass, client, "phone-sam-third-001", "person.sam", "Pixel 9 (2)")
    hub = _hub(hass)
    devices = {**hub.devices}
    devices["phone-sam-third-001"] = {**devices["phone-sam-third-001"], "name": "Pixel 9"}
    devices[SAM_PHONE] = {**devices[SAM_PHONE], "name": "Alex's phone"}
    hass.config_entries.async_update_entry(hub.entry, data={**hub.entry.data, "devices": devices})
    await hass.async_block_till_done()
    _publish(hass, "phone-sam-second-01")
    _publish(hass, "phone-sam-third-001")
    api = await _api(hass, users["alex"])
    with pytest.raises(HomeAssistantError, match="More than one phone is called pixel 9: give its id"):
        await _call(api, "glint_dnd", phone="pixel 9", on=True)
    assert (await _call(api, "glint_dnd", phone="phone-sam-third-001", on=True))["status"] == "queued"
    # The caller's own among them
    await _call(api, "glint_dnd", phone="Alex's phone", on=True)
    assert len(_hub(hass).glint_agent.pending(ALEX_PHONE)) == 1 and _hub(hass).glint_agent.pending(SAM_PHONE) == []
    with pytest.raises(HomeAssistantError, match="more than one Glint phone"):
        await _call(api, "glint_dnd", phone="Sam", on=True)


async def test_the_caller_s_own_phone_seen_last_wins_and_a_stale_one_can_be_forgotten(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator, hass_ws_client, hass_admin_user, freezer,
    monkeypatch,
) -> None:
    # The clock moves by hand here: nothing waits for the phone
    monkeypatch.setattr(glint_agent, "WAIT_FOR", 0)
    _entry, client, secrets, users = await _household(hass, hass_client_no_auth, alex_user=hass_admin_user)
    # Alex paired again (a new install): two phones of theirs with one name, the old one stale
    new = "phone-alex-second-01"
    new_secret = await _pair(hass, client, new, "person.alex", "Alex's phone (new)")
    hub = _hub(hass)
    devices = {**hub.devices, new: {**hub.devices[new], "name": "Alex's phone"}}
    hass.config_entries.async_update_entry(hub.entry, data={**hub.entry.data, "devices": devices})
    await hass.async_block_till_done()
    _publish(hass, new)
    status = {"screen": "on", "day": dt_util.now().date().isoformat(), "seconds_today": 0, "client": CLIENT}
    for device_id, secret in ((ALEX_PHONE, secrets["alex"]), (new, new_secret)):
        response = await client.post(
            f"/api/hearth/device/{device_id}/status", json=status, headers={"X-Hearth-Secret": secret}
        )
        assert response.status == 200
        freezer.tick(timedelta(minutes=5))
    api = await _api(hass, users["alex"])
    await _call(api, "glint_dnd", phone="alex's phone", on=True)
    assert len(_hub(hass).glint_agent.pending(new)) == 1 and _hub(hass).glint_agent.pending(ALEX_PHONE) == []
    # With no phone named, the list says name · person · last seen
    listed = r"Name the phone \(Sam's phone · Sam · last seen [0-9:]+ [ap]m; Alex's phone · Alex · last seen [0-9:]+ [ap]m;"
    with pytest.raises(HomeAssistantError, match=listed):
        await _call(api, "glint_activity")

    # Never another adult's phone, for an adult who isn't an administrator
    refresh = await hass.auth.async_create_refresh_token(users["jordan"], "https://hearth.test/")
    jordan_ws = await hass_ws_client(hass, hass.auth.async_create_access_token(refresh))
    await jordan_ws.send_json({"id": 1, "type": "hearth/glint/forget", "device_id": ALEX_PHONE})
    assert not (await jordan_ws.receive_json())["success"]
    # A device Hearth doesn't know
    ws = await hass_ws_client(hass)
    await ws.send_json({"id": 3, "type": "hearth/glint/forget", "device_id": "no-such-device"})
    assert not (await ws.receive_json())["success"]
    # A phone paired and never seen (it never said it runs Glint) goes too, and an administrator may forget any
    # adult's
    stub = "firstrun-stub-01"
    await _pair(hass, client, stub, "person.jordan", "Stand-in phone")
    await ws.send_json({"id": 4, "type": "hearth/glint/forget", "device_id": stub})
    assert (await ws.receive_json())["success"]
    assert stub not in _hub(hass).devices
    # The stale one forgotten by an adult: gone from Hearth and from the device registry
    await ws.send_json({"id": 5, "type": "hearth/glint/forget", "device_id": ALEX_PHONE})
    answer = await ws.receive_json()
    assert answer["success"] and answer["result"]["forgotten"].startswith("Alex's phone · Alex · last seen")
    await hass.async_block_till_done()
    hub = _hub(hass)
    assert ALEX_PHONE not in hub.devices
    assert dr.async_get(hass).async_get_device_by_identifier((DOMAIN, ALEX_PHONE), hub.entry.entry_id) is None
    old = await client.post(
        f"/api/hearth/device/{ALEX_PHONE}/status", json=status, headers={"X-Hearth-Secret": secrets["alex"]}
    )
    assert old.status == 401
    # One Alex's phone now: no name needed
    assert (await _call(await _api(hass, users["alex"]), "glint_activity"))["phone"] == "Alex's phone"


async def test_an_adult_reaches_their_own_phones_and_kids_never_another_adult_s(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator
) -> None:
    _entry, client, secrets, users = await _household(hass, hass_client_no_auth)
    assert (await _phone_puts(client, secrets["sam"], SAM_PHONE, STATE, STATE_DOC)).status == 200
    api = await _api(hass, users["alex"])

    # No phone named: their own, the only one
    assert (await _call(api, "glint_activity"))["phone"] == "Alex's phone"
    # By name (any case), or by the person whose only Glint phone it is
    assert (await _call(api, "glint_get_start", phone="SAM'S PHONE"))["start"]["tiles"][0]["id"] == 12
    assert (await _call(api, "glint_get_start", phone="sam"))["phone"] == "Sam's phone"
    with pytest.raises(HomeAssistantError, match="another adult's phone"):
        await _call(api, "glint_get_start", phone="Jordan's phone")
    with pytest.raises(HomeAssistantError, match="No Glint phone called"):
        await _call(api, "glint_get_start", phone="the kitchen tablet")

    # A voice call with no user: adults' phones only
    voice = await _api(hass, platform="conversation")
    with pytest.raises(HomeAssistantError, match="can't reach"):
        await _call(voice, "glint_get_start", phone="Sam's phone")
    with pytest.raises(HomeAssistantError, match="Name the phone"):
        await _call(voice, "glint_activity")
    assert (await _call(voice, "glint_activity", phone="Jordan's phone"))["phone"] == "Jordan's phone"


# G-3: requests, results, waiting


async def test_a_write_waits_for_the_phone_and_returns_glint_s_words(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator, monkeypatch
) -> None:
    _entry, _client, _secrets, users = await _household(hass, hass_client_no_auth)
    monkeypatch.setattr(glint_agent, "WAIT_FOR", 5)
    hub = _hub(hass)
    done = async_capture_events(hass, EVENT_AGENT_DONE)
    api = await _api(hass, users["alex"])
    ops = [{"op": "resize", "tile": 12, "size": "2x2"}]

    call = asyncio.create_task(_call(api, "glint_change_start", ops=ops))
    [request] = await _until_requested(hub, ALEX_PHONE)
    assert {k: request[k] for k in ("agent", "user", "user_name", "origin", "action", "args")} == {
        "agent": "mcp", "user": users["alex"].id, "user_name": "Alex", "origin": "text", "action": "start.change",
        "args": {"ops": ops},
    }
    assert request["id"].startswith("r-") and 6 <= len(request["id"]) <= 40
    assert parse_time(request["expires"]) - parse_time(request["created"]) == timedelta(hours=24)
    inbox = hub.glint_agent.doc(ALEX_PHONE, INBOX)
    assert (inbox["schema"], inbox["label"], inbox["updated_by"]) == ("glint.agent-inbox/1", "agent requests", "hearth")
    assert inbox["data"]["format"] == "glint.agent-inbox/1" and inbox["data"]["contract"] == 1

    said = ["clock tile: 1×1 → 2×2, page 1, column 1, row 1"]
    _outbox(hub, ALEX_PHONE, {"id": request["id"], "status": "applied", "action": "start.change", "agent": "mcp",
                              "said": said, "undo": "u-3f9c1", "at": "2026-11-15T18:06:01Z"})
    answer = await call
    assert answer == {"phone": "Alex's phone", "status": "applied", "request": request["id"], "said": said,
                      "undo": "u-3f9c1"}
    await hass.async_block_till_done()
    # Told once; gone from the inbox
    assert [e.data for e in done] == [{
        "device_id": ALEX_PHONE, "request": request["id"], "agent": "mcp", "action": "start.change",
        "status": "applied", "said": said, "undo": "u-3f9c1", "code": None,
    }]
    assert hub.glint_agent.pending(ALEX_PHONE) == []
    _outbox(hub, ALEX_PHONE, {"id": request["id"], "status": "applied", "action": "start.change", "agent": "mcp",
                              "said": said, "undo": "u-3f9c1", "at": "2026-11-15T18:06:01Z"})
    await hass.async_block_till_done()
    assert len(done) == 1
    # In Hearth's history, as the assistant's
    event = hub.household.history.events[-1]
    assert (event["kind"], event["tool"], event["device"], event["via"], event["user"]) == (
        "assist", "glint_change_start", ALEX_PHONE, "mcp", users["alex"].id
    )


async def test_queued_asked_and_refused(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator, monkeypatch
) -> None:
    _entry, _client, _secrets, users = await _household(hass, hass_client_no_auth)
    hub = _hub(hass)
    done = async_capture_events(hass, EVENT_AGENT_DONE)
    api = await _api(hass, users["alex"])

    # The phone doesn't answer in time: queued, and it waits in the inbox
    queued = await _call(api, "glint_set_look", values={"motion": "calm"})
    assert queued["status"] == "queued"
    assert queued["message"] == (
        f"queued for Alex's phone: glint applies it the next time Start is open (request {queued['request']})"
    )
    assert [r["id"] for r in hub.glint_agent.pending(ALEX_PHONE)] == [queued["request"]]

    # Asked on the phone: the call says so, the request stays until its final result
    monkeypatch.setattr(glint_agent, "WAIT_FOR", 5)
    call = asyncio.create_task(_call(api, "glint_undo", undo="u-1"))
    pending = await _until_requested(hub, ALEX_PHONE, 2)
    undo = pending[-1]
    assert undo["action"] == "undo" and undo["args"] == {"undo": "u-1"}
    _outbox(hub, ALEX_PHONE, {"id": undo["id"], "status": "asked_on_phone", "action": "undo", "agent": "mcp",
                              "at": "2026-11-15T18:06:02Z"})
    asked = await call
    assert asked["status"] == "asked_on_phone" and asked["message"] == "waiting for Alex to allow it on the phone"
    await hass.async_block_till_done()
    assert done == [] and len(hub.glint_agent.pending(ALEX_PHONE)) == 2

    # Refused, and the look applied: both told, both gone
    _outbox(
        hub, ALEX_PHONE,
        {"id": queued["request"], "status": "applied", "action": "look.set", "agent": "mcp", "said": ["motion: lively → calm"],
         "undo": "u-2", "at": "2026-11-15T18:07:00Z"},
        {"id": undo["id"], "status": "refused", "action": "undo", "agent": "mcp", "code": "declined",
         "message": "not now", "at": "2026-11-15T18:07:01Z"},
    )
    await hass.async_block_till_done()
    assert sorted((e.data["status"], e.data["code"]) for e in done) == [("applied", None), ("refused", "declined")]
    assert hub.glint_agent.pending(ALEX_PHONE) == []

    # A refused result in time comes back with its code and words
    call = asyncio.create_task(_call(api, "glint_notification_rules", ops=[{"op": "hide", "app": "com.example.game"}]))
    [request] = await _until_requested(hub, ALEX_PHONE)
    _outbox(hub, ALEX_PHONE, {"id": request["id"], "status": "refused", "action": "notify.change", "agent": "mcp",
                              "code": "too_often", "message": "too many changes", "retry_after_ms": 30000,
                              "at": "2026-11-15T18:08:00Z"})
    refused = await call
    assert (refused["status"], refused["code"], refused["retry_after_ms"]) == ("refused", "too_often", 30000)


async def test_twenty_requests_at_most_and_expired_ones_go(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator, freezer, monkeypatch
) -> None:
    # The clock is frozen: nothing waits for the phone
    monkeypatch.setattr(glint_agent, "WAIT_FOR", 0)
    _entry, _client, _secrets, users = await _household(hass, hass_client_no_auth)
    hub = _hub(hass)
    api = await _api(hass, users["alex"])
    for n in range(MAX_REQUESTS):
        hub.glint_agent.add(ALEX_PHONE, "look.set", {"values": {"n": n}}, agent="mcp", origin="text", user=None,
                            user_name=None)
    with pytest.raises(HomeAssistantError, match="inbox_full: Alex's phone has 20 requests waiting"):
        await _call(api, "glint_dnd", on=True, minutes=30)
    # Too big for a request
    with pytest.raises(HomeAssistantError, match="bad_args"):
        await _call(api, "glint_set_look", values={"x": "y" * 9000})

    # A day later they're past their time: pruned when the next one comes
    freezer.tick(timedelta(hours=24, seconds=1))
    answer = await _call(api, "glint_dnd", on=True, minutes=30)
    assert answer["status"] == "queued"
    [dnd] = hub.glint_agent.pending(ALEX_PHONE)
    assert dnd["args"] == {"on": True, "minutes": 30}
    # Not worth running after the half hour it was for
    assert parse_time(dnd["expires"]) - parse_time(dnd["created"]) == timedelta(minutes=30)


async def test_the_doorbell_rings_the_linked_companion_app(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator, hass_ws_client, hass_admin_user
) -> None:
    _entry, _client, _secrets, users = await _household(hass, hass_client_no_auth, alex_user=hass_admin_user)
    rung = async_mock_service(hass, "notify", "mobile_app_alex_phone")
    hub = _hub(hass)
    ws = await hass_ws_client(hass)
    await ws.send_json({"id": 1, "type": "hearth/glint/phones"})
    phones = (await ws.receive_json())["result"]["phones"]
    assert {p["device_id"] for p in phones} == {ALEX_PHONE, SAM_PHONE}
    await ws.send_json({"id": 2, "type": "hearth/glint/bell", "device_id": ALEX_PHONE, "notify": "notify.mobile_app_none"})
    assert (await ws.receive_json())["error"]["code"] == "invalid"
    await ws.send_json({"id": 3, "type": "hearth/glint/bell", "device_id": JORDAN_PHONE,
                        "notify": "notify.mobile_app_alex_phone"})
    assert not (await ws.receive_json())["success"]
    await ws.send_json({"id": 4, "type": "hearth/glint/bell", "device_id": ALEX_PHONE,
                        "notify": "notify.mobile_app_alex_phone"})
    assert (await ws.receive_json())["result"]["bell"] == "notify.mobile_app_alex_phone"

    api = await _api(hass, users["alex"])
    await _call(api, "glint_dnd", on=True)
    [call] = rung
    assert call.data == {
        "message": "command_broadcast_intent",
        "data": {"intent_package_name": GLINT, "intent_action": BELL_ACTION, "intent_class_name": BELL_CLASS},
    }
    # The phone leaves: its link goes
    await hub.async_remove_device(ALEX_PHONE)
    assert ALEX_PHONE not in hub.glint_agent.bells


# G-3: reads, kids' phones, voice


async def test_reads_come_from_the_state_document(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator
) -> None:
    _entry, client, secrets, users = await _household(hass, hass_client_no_auth, states=False)
    hub = _hub(hass)
    api = await _api(hass, users["alex"])
    # None published: agents count as off there; every tool says so and nothing goes to the phone
    for tool, args in (
        ("glint_get_start", {}), ("glint_activity", {}), ("glint_dnd", {"on": True}),
        ("glint_change_start", {"ops": [{"op": "move", "tile": 1}]}), ("glint_system_setting", {}),
    ):
        with pytest.raises(HomeAssistantError, match="home assistant access is off"):
            await _call(api, tool, phone="Sam's phone", **args)
    assert hub.glint_agent.pending(SAM_PHONE) == []
    assert hub.glint_agent.doc(SAM_PHONE, INBOX) is None

    assert (await _phone_puts(client, secrets["sam"], SAM_PHONE, STATE, STATE_DOC)).status == 200
    start = await _call(api, "glint_get_start", phone="Sam's phone")
    assert start["start"] == STATE_DOC["start"] and start["kid_phone"] is True
    assert start["as_of"].startswith("as of ") and start["updated"] == STATE_DOC["updated"]
    assert (await _call(api, "glint_set_look", phone="sam"))["look"] == {"values": {"motion": "lively"}}
    assert (await _call(api, "glint_notification_rules", phone="sam"))["notify"] == STATE_DOC["notify"]
    assert (await _call(api, "glint_system_setting", phone="sam"))["phone"] == STATE_DOC["phone"]
    activity = await _call(api, "glint_activity", phone="sam")
    assert activity["activity"] == STATE_DOC["activity"]
    assert activity["waiting"] == []
    await _call(api, "glint_dnd", phone="sam", on=True)

    # The owner turned agents through Home Assistant off: reads and writes say so, nothing is queued
    off = {"format": "glint.state/1", "contract": 1, "updated": "2026-11-15T18:10:00Z", "channel": "off"}
    assert (await _phone_puts(client, secrets["sam"], SAM_PHONE, STATE, off)).status == 200
    for tool, args in (("glint_get_start", {}), ("glint_dnd", {"on": True}), ("glint_activity", {})):
        with pytest.raises(HomeAssistantError, match="home assistant access is off"):
            await _call(api, tool, phone="sam", **args)
    assert len(hub.glint_agent.pending(SAM_PHONE)) == 1


async def test_a_kid_s_phone_takes_tightening_only_and_nothing_by_voice(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator
) -> None:
    _entry, _client, _secrets, users = await _household(hass, hass_client_no_auth)
    hub = _hub(hass)
    api = await _api(hass, users["alex"])
    for tool, args in (
        ("glint_dnd", {"on": False}),
        ("glint_system_setting", {"values": {"brightness": 70}}),
        ("glint_system_setting", {"ringer": "ring"}),
    ):
        with pytest.raises(HomeAssistantError, match="needs_parent"):
            await _call(api, tool, phone="Sam's phone", **args)
    assert hub.glint_agent.pending(SAM_PHONE) == []
    assert (await _call(api, "glint_dnd", phone="Sam's phone", on=True, until="21:30"))["status"] == "queued"
    [dnd] = hub.glint_agent.pending(SAM_PHONE)
    assert dnd["args"] == {"on": True, "until": "21:30"}
    assert parse_time(dnd["expires"]) <= parse_time(dnd["created"]) + timedelta(hours=24)

    # Alex through Assist: voice, so never on a kid's phone
    assist = await _api(hass, users["alex"], platform="conversation")
    with pytest.raises(HomeAssistantError, match="voice_on_kid_phone"):
        await _call(assist, "glint_dnd", phone="Sam's phone", on=True)
    # ...and on their own phone the request says voice, so Glint asks first
    await _call(assist, "glint_dnd", on=True)
    [request] = hub.glint_agent.pending(ALEX_PHONE)
    assert (request["origin"], request["agent"]) == ("voice", "assist")

    # A satellite with no user: an adult's phone, voice, no user
    voice = await _api(hass, platform="conversation")
    await _call(voice, "glint_system_setting", phone="Jordan's phone", values={"brightness": 40}, ringer="vibrate")
    requests = hub.glint_agent.pending(JORDAN_PHONE)
    assert [(r["action"], r["args"]) for r in requests] == [
        ("phone.settings", {"values": {"brightness": 40}}), ("phone.sound", {"ringer": "vibrate"})
    ]
    assert all(r["origin"] == "voice" and r["user"] is None for r in requests)


# G-2 and G-4: where the phones see the inbox move


async def test_hearth_me_and_the_kid_s_state_document_carry_the_inbox_etag(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator, hass_ws_client, hass_admin_user
) -> None:
    _entry, client, secrets, users = await _household(hass, hass_client_no_auth, alex_user=hass_admin_user)
    hub = _hub(hass)
    ws = await hass_ws_client(hass)
    await ws.send_json({"id": 1, "type": "hearth/me"})
    before = (await ws.receive_json())["result"]
    assert before["client_settings"] == {}

    api = await _api(hass, users["alex"])
    await _call(api, "glint_dnd", on=True)
    await _call(api, "glint_dnd", phone="Sam's phone", on=True)
    await ws.send_json({"id": 2, "type": "hearth/me"})
    after = (await ws.receive_json())["result"]
    etag = hub.glint_agent.doc(ALEX_PHONE, INBOX)["etag"]
    # Alex's own Glint phone only: not a kid's, not another adult's
    assert after["client_settings"] == {f"device:{ALEX_PHONE}/{INBOX}": etag}
    assert after["version"] != before["version"]
    # A kid's own document has none
    assert "client_settings" not in hub.household.own_document("person.sam")

    # G-4: the kid's phone sees its own inbox's etag in its state document
    response = await client.post(
        f"/api/hearth/device/{SAM_PHONE}/status",
        json={"screen": "on", "day": dt_util.now().date().isoformat(), "seconds_today": 0, "client": CLIENT},
        headers={"X-Hearth-Secret": secrets["sam"]},
    )
    state = (await response.json())["state"]
    assert state["client_settings"][f"device:{SAM_PHONE}/{INBOX}"] == hub.glint_agent.doc(SAM_PHONE, INBOX)["etag"]
    assert not any(k.startswith(f"device:{ALEX_PHONE}") for k in state["client_settings"])
