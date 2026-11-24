"""A kid's own phone and their to-do list (docs/contracts/device-api.md, To-do): the items in the state document
(todo_lists) and the todo_item endpoint, which checks an item off as the kid (their reward granted)."""

from homeassistant.core import HomeAssistant
from pytest_homeassistant_custom_component.typing import ClientSessionGenerator

from test_chores import SAM_LIST, _book, _hub, _kids, _live, _task
from test_client_contract import _pair_phone

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
    status, _ = await _post(client, "sam-phone", sam, {"entity_id": SAM_LIST, "uid": uid, "status": "done"})
    assert status == 400
    status, _ = await _post(client, "sam-phone", "wrong", {"entity_id": SAM_LIST, "uid": uid, "status": "completed"})
    assert status == 401
