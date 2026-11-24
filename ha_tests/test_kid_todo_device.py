"""A kid's own phone and their to-do list (docs/contracts/device-api.md, To-do): the items in the state document
(todo_lists) and the todo_item endpoint, which checks an item off as the kid (their reward granted)."""

from datetime import datetime
from unittest.mock import patch

import pytest

from homeassistant.core import HomeAssistant
from homeassistant.exceptions import HomeAssistantError
from homeassistant.util import dt as dt_util
from pytest_homeassistant_custom_component.typing import ClientSessionGenerator

from custom_components.hearth.const import DOMAIN, MAX_TODO_POSTS
from custom_components.hearth.todos import ADULT, MAX_KID_GRANTS, Actor
from test_chores import ROBIN_LIST, SAM_LIST, _book, _hub, _kids, _live, _options, _task, _tick
from test_client_contract import CLIENT, NONCE, _pair_phone
from test_init import TV_ID

URL = "/api/hearth/device/{}/todo_item"


async def _post(client, device_id: str, secret: str, body: dict):
    response = await client.post(URL.format(device_id), json=body, headers={"X-Hearth-Secret": secret})
    return response.status, await response.json()


async def test_a_kid_s_phone_sees_and_checks_off_their_own_list(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator
) -> None:
    client, _secret, _users, _sent = await _kids(hass, hass_client_no_auth)
    _task(hass)
    _task(hass, "Homework", repeat={"kind": "once"}, reward=None)
    _task(hass, "Robin's chore", person="person.robin")
    await hass.async_block_till_done()
    sam = await _pair_phone(hass, client, "sam-phone", "person.sam")
    robin = await _pair_phone(hass, client, "robin-phone", "person.robin")
    alex = await _pair_phone(hass, client, "alex-phone", "person.alex")

    household = _hub(hass).household
    [lists] = [household.document_for("sam-phone")["todo_lists"]]
    assert [(entry["entity_id"], entry["name"]) for entry in lists] == [(SAM_LIST, "Sam's to-do")]
    items = {i["summary"]: i for i in lists[0]["items"]}
    assert items["Feed the cat"]["reward"] == "+15 min Games" and items["Homework"]["reward"] is None
    assert {i["status"] for i in items.values()} == {"needs_action"}
    # An adult's phone has no lists
    assert "todo_lists" not in household.document_for("alex-phone")

    uid = items["Feed the cat"]["uid"]
    status, answer = await _post(client, "sam-phone", sam, {"entity_id": SAM_LIST, "uid": uid, "status": "completed"})
    await hass.async_block_till_done()
    assert status == 200
    assert answer == {"ok": True, "entity_id": SAM_LIST, "uid": uid, "status": "completed", "granted": True}
    # Granted as the kid's own tick, through the phone
    assert [e["key"] for e in _live(hass)] == [f"{uid}#1"]
    assert _book(hass).done[uid]["via"] == "phone"
    assert next(
        i for i in household.document_for("sam-phone")["todo_lists"][0]["items"] if i["uid"] == uid
    )["status"] == "completed"

    # Back again: the reward is taken back
    status, answer = await _post(client, "sam-phone", sam, {"entity_id": SAM_LIST, "uid": uid, "status": "needs_action"})
    await hass.async_block_till_done()
    assert status == 200 and answer["granted"] is False and _live(hass) == []

    # A sibling's phone, an adult's phone, an item of another list
    status, answer = await _post(client, "robin-phone", robin, {"entity_id": SAM_LIST, "uid": uid, "status": "completed"})
    assert status == 403 and answer["code"] == "not_yours" and answer["message"]
    status, answer = await _post(client, "alex-phone", alex, {"entity_id": SAM_LIST, "uid": uid, "status": "completed"})
    assert status == 403 and answer["code"] == "not_yours"
    robin_uid = household.document_for("robin-phone")["todo_lists"][0]["items"][0]["uid"]
    status, answer = await _post(client, "sam-phone", sam, {"entity_id": SAM_LIST, "uid": robin_uid, "status": "completed"})
    assert status == 404 and answer["code"] == "unknown_item"
    status, answer = await _post(client, "sam-phone", sam, {"entity_id": SAM_LIST, "uid": uid, "status": "done"})
    assert status == 400 and answer["error"] == answer["code"] == "bad_request" and answer["message"]
    status, _ = await _post(client, "sam-phone", "wrong", {"entity_id": SAM_LIST, "uid": uid, "status": "completed"})
    assert status == 401


async def _sam_s_phone(hass: HomeAssistant, hass_client_no_auth, **task):
    """Sam's paired phone and one item on Sam's list (Feed the cat, +15 min Games, unless said otherwise)."""
    client, tv_secret, users, _sent = await _kids(hass, hass_client_no_auth)
    uid = f"{_task(hass, **task)['id']}:{dt_util.now().date().isoformat()}"
    await hass.async_block_till_done()
    secret = await _pair_phone(hass, client, "sam-phone", "person.sam")
    assert uid in [i["uid"] for i in _hub(hass).household.document_for("sam-phone")["todo_lists"][0]["items"]]
    return client, secret, users, uid, tv_secret


async def _set(hass: HomeAssistant, client, secret: str, uid: str, done: bool = True, device_id: str = "sam-phone"):
    answer = await _post(
        client, device_id, secret,
        {"entity_id": SAM_LIST, "uid": uid, "status": "completed" if done else "needs_action"},
    )
    await hass.async_block_till_done()
    return answer


async def test_an_undone_reward_is_an_adult_s_to_untick(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator
) -> None:
    client, secret, users, uid, _tv = await _sam_s_phone(hass, hass_client_no_auth)
    assert (await _set(hass, client, secret, uid))[0] == 200
    _book(hass).undo(f"{uid}#1", users["alex"].id)
    await hass.async_block_till_done()
    status, answer = await _set(hass, client, secret, uid, done=False)
    assert status == 409 and answer["error"] == answer["code"] == "undone" and "adult" in answer["message"]
    # Still done, with no reward; checking it off again says so and grants nothing
    assert uid in _book(hass).done and _live(hass) == []
    status, answer = await _set(hass, client, secret, uid)
    assert status == 200 and answer["granted"] is False and len(_book(hass).ledger) == 1


async def test_checking_off_twice_grants_once(hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator) -> None:
    client, secret, _users, uid, _tv = await _sam_s_phone(hass, hass_client_no_auth)
    first = await _set(hass, client, secret, uid)
    again = await _set(hass, client, secret, uid)
    assert first == again == (200, {"ok": True, "entity_id": SAM_LIST, "uid": uid, "status": "completed", "granted": True})
    assert [e["key"] for e in _book(hass).ledger] == [f"{uid}#1"]
    # Checking back twice is as quiet
    assert (await _set(hass, client, secret, uid, done=False))[0] == 200
    assert (await _set(hass, client, secret, uid, done=False))[0] == 200
    assert len(_book(hass).ledger) == 1 and _live(hass) == []


async def test_a_tick_untick_loop_stops_earning(hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator) -> None:
    client, secret, users, uid, _tv = await _sam_s_phone(hass, hass_client_no_auth)
    plain = f"{_task(hass, 'Homework', reward=None)['id']}:{dt_util.now().date().isoformat()}"
    assert MAX_KID_GRANTS == 3
    for _ in range(MAX_KID_GRANTS):
        status, answer = await _set(hass, client, secret, uid)
        assert status == 200 and answer["granted"] is True
        assert (await _set(hass, client, secret, uid, done=False))[0] == 200
    # The fourth check-off of the day is refused: nothing is marked, nothing more is written
    status, answer = await _set(hass, client, secret, uid)
    assert status == 409 and answer["error"] == answer["code"] == "too_often" and "adult" in answer["message"]
    book = _book(hass)
    assert [e["key"] for e in book.ledger] == [f"{uid}#1", f"{uid}#2", f"{uid}#3"]
    assert uid not in book.done and _live(hass) == []
    # The kid's own Home Assistant user is refused the same way (the to-do card)
    with pytest.raises(HomeAssistantError):
        await _tick(hass, uid, users["sam"])
    assert len(book.ledger) == 3 and uid not in book.done
    # An item with no reward is never refused so
    for _ in range(MAX_KID_GRANTS + 1):
        assert (await _set(hass, client, secret, plain))[0] == 200
        assert (await _set(hass, client, secret, plain, done=False))[0] == 200
    # An adult still ticks it, with its reward
    assert book.check(uid, True, Actor(ADULT, user_id=users["alex"].id, via="test")) == f"{uid}#4"
    await hass.async_block_till_done()
    assert [e["key"] for e in _live(hass)] == [f"{uid}#4"]


async def test_check_offs_have_a_budget_of_their_own(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator, freezer
) -> None:
    client, secret, _users, uid, _tv = await _sam_s_phone(hass, hass_client_no_auth, reward=None)
    for n in range(MAX_TODO_POSTS):
        assert (await _set(hass, client, secret, uid, done=n % 2 == 0))[0] == 200
    status, answer = await _set(hass, client, secret, uid)
    assert status == 429 and answer["error"] == answer["code"] == "too_often" and answer["message"]
    assert uid not in _book(hass).done
    # The phone's asks aren't used up by them
    asked = await client.post(
        "/api/hearth/device/sam-phone/ask", json={"minutes": 15, "group": "games"}, headers={"X-Hearth-Secret": secret}
    )
    assert asked.status == 200, await asked.text()
    # A minute on, it checks off again
    freezer.tick(61)
    status, answer = await _set(hass, client, secret, uid)
    assert status == 200 and uid in _book(hass).done


async def _pair_nobody_s_phone(hass: HomeAssistant, client, device_id: str) -> str:
    """A phone paired with no person chosen."""
    hass.data.get(f"{DOMAIN}_pairing", {}).get("asked_at", {}).clear()
    body = {"device_id": device_id, "kind": "mobile", "name": "Spare phone", "nonce": NONCE, "client": CLIENT}
    pairing_id = (await (await client.post("/api/hearth/pair", json=body)).json())["pairing_id"]
    await hass.async_block_till_done()
    flow = next(
        f for f in hass.config_entries.flow.async_progress_by_handler(DOMAIN)
        if f["context"].get("title_placeholders", {}).get("name") == "Spare phone"
    )
    result = await hass.config_entries.flow.async_configure(flow["flow_id"], {})
    assert result["reason"] == "paired"
    await hass.async_block_till_done()
    answer = await (await client.get(f"/api/hearth/pair/{pairing_id}", headers={"X-Hearth-Nonce": NONCE})).json()
    return answer["secret"]


async def test_only_a_kid_s_own_phone_checks_off(hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator) -> None:
    client, secret, _users, uid, tv_secret = await _sam_s_phone(hass, hass_client_no_auth)
    household = _hub(hass).household
    # A TV, whoever is on it
    status, answer = await _set(hass, client, tv_secret, uid, device_id=TV_ID)
    assert status == 403 and answer["code"] == "not_yours"
    # A phone of nobody's
    spare = await _pair_nobody_s_phone(hass, client, "spare-phone")
    assert household.device_person("spare-phone") is None
    status, answer = await _set(hass, client, spare, uid, device_id="spare-phone")
    assert status == 403 and answer["code"] == "not_yours"
    # Sam's own item under another list's name, a sibling's or one that doesn't exist
    for entity_id in (ROBIN_LIST, "todo.shopping"):
        status, answer = await _post(client, "sam-phone", secret, {"entity_id": entity_id, "uid": uid, "status": "completed"})
        assert status == 403 and answer["code"] == "not_yours"
    # Not from the home network: as every device route says it
    with patch("custom_components.hearth.api.is_local", return_value=False):
        status, answer = await _set(hass, client, secret, uid)
    assert status == 403 and answer == {"error": "not_local"}
    # A uid that's no uid
    status, answer = await _set(hass, client, secret, "x" * 65)
    assert status == 400 and answer["code"] == "bad_request"
    assert _book(hass).done == {} and _book(hass).ledger == []

    # Sam is made an adult after the phone was paired: the phone no longer has a list
    await _options(hass, roles={**household.options.get("roles", {}), "person.sam": "adult"})
    household = _hub(hass).household
    assert "todo_lists" not in household.document_for("sam-phone")
    status, answer = await _set(hass, client, secret, uid)
    assert status == 403 and answer["code"] == "not_yours"
    assert _book(hass).done == {} and _book(hass).ledger == []


async def test_money_and_capped_minutes(hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator) -> None:
    client, secret, _users, mow, _tv = await _sam_s_phone(hass, hass_client_no_auth, title="Mow", reward={"cents": 500})
    await _options(hass, chore_caps={"games": 15})
    today = dt_util.now().date().isoformat()
    one, two = (f"{_task(hass, title)['id']}:{today}" for title in ("One", "Two"))
    status, answer = await _set(hass, client, secret, mow)
    assert status == 200 and answer["granted"] is True and _book(hass).balance_cents("person.sam") == 500
    status, answer = await _set(hass, client, secret, mow, done=False)
    assert status == 200 and answer["granted"] is False and _book(hass).balance_cents("person.sam") == 0
    # Minutes past the group's daily cap: done, with nothing granted
    assert (await _set(hass, client, secret, one))[1]["granted"] is True
    status, answer = await _set(hass, client, secret, two)
    assert status == 200 and answer["granted"] is False
    assert [(e["title"], e["minutes"]) for e in _live(hass)] == [("One", 15), ("Two", 0)]


async def test_yesterday_s_item_is_gone(hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator, freezer) -> None:
    freezer.move_to(datetime(2026, 11, 16, 9, 0, tzinfo=dt_util.get_default_time_zone()))
    client, secret, _users, uid, _tv = await _sam_s_phone(hass, hass_client_no_auth)
    assert uid.endswith(":2026-11-16")
    freezer.move_to(datetime(2026, 11, 17, 9, 0, tzinfo=dt_util.get_default_time_zone()))
    status, answer = await _set(hass, client, secret, uid)
    assert status == 404 and answer["error"] == answer["code"] == "unknown_item" and answer["message"]
    assert _book(hass).done == {} and _book(hass).ledger == []
    # Today's is there to check off
    status, answer = await _set(hass, client, secret, uid.replace("-16", "-17"))
    assert status == 200 and answer["granted"] is True
