"""The kids' to-do lists (todos.py, todo.py): tasks and repeats, granting on check-off with no approval step, who may do
what by caller (the kid, a sibling, an adult, a shared screen), untick and re-tick, the daily cap, an adult's undo, a
restart, money, and the old Chores earn time brought in."""

from datetime import date, datetime, timedelta

import pytest

from homeassistant.auth.const import GROUP_ID_USER
from homeassistant.core import Context, HomeAssistant, SupportsResponse
from homeassistant.exceptions import HomeAssistantError, Unauthorized
from homeassistant.util import dt as dt_util
from pytest_homeassistant_custom_component.common import async_capture_events, async_mock_service
from pytest_homeassistant_custom_component.typing import ClientSessionGenerator, WebSocketGenerator

from custom_components.hearth.const import DOMAIN
from custom_components.hearth.history import BONUS
from custom_components.hearth.limits import MAX_BONUS, Limits
from custom_components.hearth.todos import ADULT, Actor, ChoreError
from test_attention import _household, _press
from test_phones import _options

SAM_LIST = "todo.hearth_sam"
ROBIN_LIST = "todo.hearth_robin"


def _hub(hass: HomeAssistant):
    return hass.config_entries.async_entries(DOMAIN)[0].runtime_data


def _book(hass: HomeAssistant):
    return _hub(hass).household.todos


async def _kids(hass: HomeAssistant, hass_client_no_auth):
    """Sam and Robin are kids with users of their own; Alex and Jordan adults; a wall tablet signs in as a household
    user with no person. Sam has 60 minutes of Games a day."""
    client, secret, users, sent = await _household(hass, hass_client_no_auth)
    users["robin"] = await hass.auth.async_create_user("Robin")
    users["tablet"] = await hass.auth.async_create_user("Tablet")
    # Ordinary (non-administrator) Home Assistant users, as the household's would be
    for user in users.values():
        await hass.auth.async_update_user(user, group_ids=[GROUP_ID_USER])
    hass.states.async_set("person.robin", "home", {"friendly_name": "Robin", "user_id": users["robin"].id})
    entry = hass.config_entries.async_entries(DOMAIN)[0]
    await _options(hass, roles={**entry.options.get("roles", {}), "person.sam": "kid", "person.robin": "kid"})
    await hass.services.async_call(DOMAIN, "set_budget", {"person": "person.sam", "group": "games", "minutes": 60}, blocking=True)
    await hass.async_block_till_done()
    return client, secret, users, sent


def _task(hass: HomeAssistant, title: str = "Feed the cat", person: str = "person.sam", **extra) -> dict:
    data = {"person": person, "title": title, "repeat": {"kind": "daily"}, "reward": {"pool": "games", "minutes": 15}}
    data.update(extra)
    return _book(hass).save_task(data, Actor(ADULT, user_id=None, via="test"))


async def _items(hass: HomeAssistant, entity_id: str = SAM_LIST) -> list[dict]:
    response = await hass.services.async_call(
        "todo", "get_items", {}, target={"entity_id": entity_id}, blocking=True, return_response=True
    )
    return response[entity_id]["items"]


async def _tick(hass: HomeAssistant, uid: str, user=None, done: bool = True, entity_id: str = SAM_LIST) -> None:
    await hass.services.async_call(
        "todo",
        "update_item",
        {"item": uid, "status": "completed" if done else "needs_action"},
        target={"entity_id": entity_id},
        blocking=True,
        context=Context(user_id=user.id if user else None),
    )
    await hass.async_block_till_done()


def _games(hass: HomeAssistant, person: str = "person.sam"):
    return _hub(hass).household.days[person].limits["games"]


def _live(hass: HomeAssistant, person: str = "person.sam") -> list[dict]:
    return [e for e in _book(hass).ledger if e["person"] == person and e["kind"] == "earned" and not e.get("reversed_at")]


async def test_each_kid_has_a_list_with_today_s_items(hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator) -> None:
    await _kids(hass, hass_client_no_auth)
    _task(hass)
    _task(hass, "Homework", repeat={"kind": "once"}, reward=None)
    await hass.async_block_till_done()
    state = hass.states.get(SAM_LIST)
    assert state is not None and state.name == "Sam's to-do" and state.state == "2"
    assert hass.states.get(ROBIN_LIST).state == "0"
    # Adults have no list
    assert hass.states.get("todo.hearth_alex") is None
    summaries = sorted(i["summary"] for i in await _items(hass))
    # The reward shows, so the kid can choose to earn it
    assert summaries == ["Feed the cat (+15 min Games)", "Homework"]


async def test_the_kid_s_tick_grants_and_untick_takes_it_back(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator
) -> None:
    _client, _secret, users, sent = await _kids(hass, hass_client_no_auth)
    done_events = async_capture_events(hass, "hearth_chore_done")
    reversed_events = async_capture_events(hass, "hearth_chore_reversed")
    _task(hass)
    uid = (await _items(hass))[0]["uid"]
    before = _games(hass).minutes_left

    await _tick(hass, uid, users["sam"])
    games = _games(hass)
    assert games.bonus_chores == 15 and games.bonus_min == 15 and games.minutes_left == before + 15
    assert [e["key"] for e in _live(hass)] == [f"{uid}#1"]
    assert done_events[-1].data["minutes"] == 15 and done_events[-1].data["key"] == f"{uid}#1"
    # The adults are told, with an Undo; the kid's phone isn't
    item = _hub(hass).attention.item(f"hearth_chore_{uid}")
    assert item is not None and item.actions[0].service == "hearth.chore_undo"
    assert item.actions[0].data == {"key": f"{uid}#1"}
    assert sent["alex_phone"] and not sent["sam_phone"]
    # The history has it as a bonus from a chore
    assert any(e["kind"] == BONUS and e.get("via") == "chore" and e["minutes"] == 15 for e in _hub(hass).household.history.events)
    # The summary shows it beside the bonus
    games_row = next(g for g in _summary_person(hass, "person.sam")["groups"] if g["id"] == "games")
    assert games_row["bonus"] == 15 and games_row["bonus_chores"] == 15

    await _tick(hass, uid, users["sam"], done=False)
    assert _games(hass).bonus_chores == 0 and _games(hass).minutes_left == before
    assert _live(hass) == []
    assert reversed_events[-1].data["why"] == "untick"
    assert _hub(hass).attention.item(f"hearth_chore_{uid}") is None


def _summary_person(hass: HomeAssistant, person: str) -> dict:
    from custom_components.hearth.websocket import summary

    return next(p for p in summary(_hub(hass))["people"] if p["id"] == person)


async def test_tick_untick_tick_never_pays_twice(hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator) -> None:
    _client, _secret, users, _sent = await _kids(hass, hass_client_no_auth)
    _task(hass)
    uid = (await _items(hass))[0]["uid"]
    await _tick(hass, uid, users["sam"])
    await _tick(hass, uid, users["sam"])  # again: already done, nothing more
    await _tick(hass, uid, users["sam"], done=False)
    await _tick(hass, uid, users["sam"])
    assert _games(hass).bonus_chores == 15
    keys = [(e["key"], bool(e.get("reversed_at"))) for e in _book(hass).ledger]
    assert keys == [(f"{uid}#1", True), (f"{uid}#2", False)]


async def test_a_sibling_can_t_touch_another_kid_s_list(hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator) -> None:
    _client, _secret, users, _sent = await _kids(hass, hass_client_no_auth)
    _task(hass)
    _task(hass, "Robin's job", person="person.robin")
    uid = (await _items(hass))[0]["uid"]
    with pytest.raises(HomeAssistantError, match="Sam's list"):
        await _tick(hass, uid, users["robin"])
    assert (await _items(hass))[0]["status"] == "needs_action"
    assert _book(hass).ledger == [] and _games(hass).bonus_chores == 0
    with pytest.raises(HomeAssistantError, match="Sam's list"):
        await hass.services.async_call(
            "todo", "add_item", {"item": "Junk"}, target={"entity_id": SAM_LIST}, blocking=True,
            context=Context(user_id=users["robin"].id),
        )
    with pytest.raises(HomeAssistantError, match="Sam's list"):
        await hass.services.async_call(
            "todo", "remove_item", {"item": uid}, target={"entity_id": SAM_LIST}, blocking=True,
            context=Context(user_id=users["robin"].id),
        )
    # Their own list is theirs
    robin_uid = (await _items(hass, ROBIN_LIST))[0]["uid"]
    await _tick(hass, robin_uid, users["robin"], entity_id=ROBIN_LIST)
    assert [e["person"] for e in _live(hass, "person.robin")] == ["person.robin"]


async def test_a_shared_screen_or_voice_ticks_without_a_reward(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator, hass_ws_client: WebSocketGenerator
) -> None:
    _client, _secret, users, _sent = await _kids(hass, hass_client_no_auth)
    _task(hass)
    _task(hass, "Teeth")
    uids = {i["summary"].split(" (")[0]: i["uid"] for i in await _items(hass)}
    # A household user with no person (a wall tablet), and no user at all (Assist, an automation)
    await _tick(hass, uids["Feed the cat"], users["tablet"])
    await _tick(hass, uids["Teeth"], None)
    assert {i["status"] for i in await _items(hass)} == {"completed"}
    assert _book(hass).ledger == [] and _games(hass).bonus_chores == 0
    # An adult gives it from the panel
    ws = await hass_ws_client(hass)
    await ws.send_json({"id": 1, "type": "hearth/todo/give", "item": uids["Teeth"]})
    result = await ws.receive_json()
    assert result["success"], result
    assert _games(hass).bonus_chores == 15
    # Given once: a second Give is refused
    await ws.send_json({"id": 2, "type": "hearth/todo/give", "item": uids["Teeth"]})
    assert (await ws.receive_json())["error"]["code"] == "granted"
    # A shared screen can't untick what was granted (that would take Sam's reward), only what wasn't
    with pytest.raises(HomeAssistantError, match="Only Sam or an adult"):
        await _tick(hass, uids["Teeth"], users["tablet"], done=False)
    await _tick(hass, uids["Feed the cat"], users["tablet"], done=False)
    assert _games(hass).bonus_chores == 15


async def test_an_adult_s_tick_grants_too(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator, hass_ws_client: WebSocketGenerator
) -> None:
    _client, _secret, users, _sent = await _kids(hass, hass_client_no_auth)
    _task(hass)
    _task(hass, "Teeth")
    uids = [i["uid"] for i in await _items(hass)]
    await _tick(hass, uids[0], users["alex"])
    ws = await hass_ws_client(hass)
    await ws.send_json({"id": 1, "type": "hearth/todo/check", "item": uids[1], "done": True})
    assert (await ws.receive_json())["success"]
    assert _games(hass).bonus_chores == 30
    assert {e["actor"] for e in _live(hass)} == {"adult"}


async def test_the_daily_cap_per_pool(hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator) -> None:
    _client, _secret, users, _sent = await _kids(hass, hass_client_no_auth)
    await _options(hass, chore_caps={"games": 20})
    for title in ("One", "Two", "Three"):
        _task(hass, title)
    uids = {i["summary"].split(" (")[0]: i["uid"] for i in await _items(hass)}
    for title in ("One", "Two", "Three"):
        await _tick(hass, uids[title], users["sam"])
    granted = [(e["title"], e["asked"], e["minutes"]) for e in _live(hass)]
    assert granted == [("One", 15, 15), ("Two", 15, 5), ("Three", 15, 0)]
    assert _games(hass).bonus_chores == 20
    assert "cap for Games is reached" in _hub(hass).attention.item(f"hearth_chore_{uids['Two']}").text
    # Untick One: its 15 come back under the cap for the next tick
    await _tick(hass, uids["One"], users["sam"], done=False)
    assert _games(hass).bonus_chores == 5


async def test_an_adult_s_undo_takes_the_whole_reward_back(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator, hass_ws_client: WebSocketGenerator
) -> None:
    _client, _secret, users, _sent = await _kids(hass, hass_client_no_auth)
    # 10 minutes left of Games (5 used), so the 15 earned are partly spent once 20 more are used
    await hass.services.async_call(DOMAIN, "set_budget", {"person": "person.sam", "group": "games", "minutes": 10}, blocking=True)
    _task(hass)
    uid = (await _items(hass))[0]["uid"]
    await _tick(hass, uid, users["sam"])
    assert _games(hass).minutes_left == 20
    # Sam plays 15 of them
    _hub(hass).household.limits.set_bonus("person.sam", "games", -15)
    _hub(hass).household.recompute()
    assert _games(hass).minutes_left == 5
    # The Undo on Alex's phone runs hearth.chore_undo as Alex
    _press(hass, f"HEARTH_ACT|hearth_chore_{uid}|0", users["alex"])
    await hass.async_block_till_done()
    assert _games(hass).bonus_chores == 0 and _games(hass).minutes_left == 0
    entry = _book(hass).ledger[0]
    assert entry["reversed_why"] == "undo" and entry["reversed_by"] == users["alex"].id and entry["spent"] == 10
    # The item stays done; Sam's tick is a no-op, an adult's Give grants it again (#2)
    assert (await _items(hass))[0]["status"] == "completed"
    await _tick(hass, uid, users["sam"])
    assert _live(hass) == []
    ws = await hass_ws_client(hass)
    await ws.send_json({"id": 1, "type": "hearth/todo/give", "item": uid})
    assert (await ws.receive_json())["result"]["key"] == f"{uid}#2"
    # Undone twice: told it was already
    await ws.send_json({"id": 2, "type": "hearth/todo/undo", "key": f"{uid}#1"})
    assert (await ws.receive_json())["error"]["code"] == "reversed"


async def test_a_kid_can_t_undo(hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator) -> None:
    _client, _secret, users, _sent = await _kids(hass, hass_client_no_auth)
    _task(hass)
    uid = (await _items(hass))[0]["uid"]
    await _tick(hass, uid, users["sam"])
    with pytest.raises(Unauthorized):
        await hass.services.async_call(
            DOMAIN, "chore_undo", {"key": f"{uid}#1"}, blocking=True, context=Context(user_id=users["robin"].id)
        )
    assert len(_live(hass)) == 1


async def test_a_restart_keeps_grants_once_and_their_undo(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator
) -> None:
    _client, _secret, users, sent = await _kids(hass, hass_client_no_auth)
    _task(hass)
    uid = (await _items(hass))[0]["uid"]
    await _tick(hass, uid, users["sam"])
    pushed = len(sent["alex_phone"])
    # Home Assistant restarts: the attention items are gone with it; the store is kept
    entry = hass.config_entries.async_entries(DOMAIN)[0]
    hass.data.pop(f"{DOMAIN}_attention", None)
    assert await hass.config_entries.async_reload(entry.entry_id)
    await hass.async_block_till_done()
    assert _games(hass).bonus_chores == 15
    assert [i["status"] for i in await _items(hass)] == ["completed"]
    # The notice is back without a second push, and its Undo works
    assert _hub(hass).attention.item(f"hearth_chore_{uid}") is not None
    assert len(sent["alex_phone"]) == pushed
    _press(hass, f"HEARTH_ACT|hearth_chore_{uid}|0", users["alex"])
    await hass.async_block_till_done()
    assert _games(hass).bonus_chores == 0


async def test_what_a_kid_may_change(hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator) -> None:
    _client, _secret, users, _sent = await _kids(hass, hass_client_no_auth)
    sam = Context(user_id=users["sam"].id)
    _task(hass)
    adult_uid = (await _items(hass))[0]["uid"]
    # Sam adds homework: theirs, never rewarded
    await hass.services.async_call(
        "todo", "add_item", {"item": "Math sheet", "due_date": "2026-11-20"}, target={"entity_id": SAM_LIST},
        blocking=True, context=sam,
    )
    homework = next(t for t in _book(hass).tasks.values() if t["title"] == "Math sheet")
    assert homework["by"] == "kid" and homework["reward"] is None and homework["due_date"] == "2026-11-20"
    # Sam renames and removes it
    await hass.services.async_call(
        "todo", "update_item", {"item": homework["id"], "rename": "Math sheet p. 4"}, target={"entity_id": SAM_LIST},
        blocking=True, context=sam,
    )
    assert _book(hass).tasks[homework["id"]]["title"] == "Math sheet p. 4"
    await hass.services.async_call(
        "todo", "remove_item", {"item": homework["id"]}, target={"entity_id": SAM_LIST}, blocking=True, context=sam
    )
    assert homework["id"] not in _book(hass).tasks
    # An adult's item: tick and untick only
    with pytest.raises(HomeAssistantError, match="Only an adult can change"):
        await hass.services.async_call(
            "todo", "update_item", {"item": adult_uid, "rename": "Feed the cat (+120 min Games)"},
            target={"entity_id": SAM_LIST}, blocking=True, context=sam,
        )
    with pytest.raises(HomeAssistantError, match="Only an adult can remove"):
        await hass.services.async_call(
            "todo", "remove_item", {"item": adult_uid}, target={"entity_id": SAM_LIST}, blocking=True, context=sam
        )
    # Ticked, then Clear checked items: it leaves the list, the reward stays
    await _tick(hass, adult_uid, users["sam"])
    await hass.services.async_call("todo", "remove_completed_items", {}, target={"entity_id": SAM_LIST}, blocking=True, context=sam)
    await hass.async_block_till_done()
    assert await _items(hass) == []
    assert _games(hass).bonus_chores == 15


async def test_an_adult_s_delete_on_the_list(hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator) -> None:
    _client, _secret, users, _sent = await _kids(hass, hass_client_no_auth)
    daily = _task(hass)
    once = _task(hass, "Library book", repeat={"kind": "once"}, reward=None)
    alex = Context(user_id=users["alex"].id)
    uids = {i["summary"].split(" (")[0]: i["uid"] for i in await _items(hass)}
    await hass.services.async_call(
        "todo", "remove_item", {"item": [uids["Feed the cat"], uids["Library book"]]}, target={"entity_id": SAM_LIST},
        blocking=True, context=alex,
    )
    # The repeating task skips today; the one-off is gone
    assert daily["id"] in _book(hass).tasks and once["id"] not in _book(hass).tasks
    assert await _items(hass) == []


async def test_repeats_and_the_day_roll(hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator, freezer) -> None:
    monday = datetime(2026, 11, 16, 9, 0, tzinfo=dt_util.get_default_time_zone())
    freezer.move_to(monday)
    _client, _secret, users, _sent = await _kids(hass, hass_client_no_auth)
    book = _book(hass)
    _task(hass, "Daily", reward=None)
    _task(hass, "School days", repeat={"kind": "weekdays", "days": [0, 1, 2, 3, 4]}, reward=None)
    _task(hass, "Every 3", repeat={"kind": "every_n", "n": 3, "start": "2026-11-16"}, reward=None)
    _task(hass, "After 2", repeat={"kind": "after_done", "n": 2}, reward=None)
    _task(hass, "One-off", repeat={"kind": "once"}, reward=None, due_date="2026-11-17", due_time="18:00")

    def titles(day: date) -> list[str]:
        return sorted(o.task["title"] for o in book.items("person.sam", day))

    assert titles(date(2026, 11, 16)) == ["After 2", "Daily", "Every 3", "One-off", "School days"]
    assert titles(date(2026, 11, 17)) == ["After 2", "Daily", "One-off", "School days"]
    assert titles(date(2026, 11, 19)) == ["After 2", "Daily", "Every 3", "One-off", "School days"]
    assert titles(date(2026, 11, 21)) == ["After 2", "Daily", "One-off"]
    one_off = next(o for o in book.items("person.sam") if o.task["title"] == "One-off")
    assert one_off.due == datetime(2026, 11, 17, 18, 0, tzinfo=dt_util.get_default_time_zone())

    # Done today: shown done today, gone tomorrow; "after 2" comes back two days after
    for occ in book.items("person.sam"):
        if occ.task["title"] in ("Daily", "After 2", "One-off"):
            book.check(occ.id, True, Actor("kid", "person.sam", users["sam"].id))
    done_today = {o.task["title"] for o in book.items("person.sam") if o.done}
    assert done_today == {"Daily", "After 2", "One-off"}
    freezer.move_to(monday + timedelta(days=1))
    assert titles(date(2026, 11, 17)) == ["Daily", "School days"]
    assert not any(o.done for o in book.items("person.sam"))
    assert titles(date(2026, 11, 18)) == ["After 2", "Daily", "School days"]


async def test_a_late_tick_counts_on_its_own_day(hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator, freezer) -> None:
    late = datetime(2026, 11, 16, 23, 58, tzinfo=dt_util.get_default_time_zone())
    freezer.move_to(late)
    _client, _secret, users, _sent = await _kids(hass, hass_client_no_auth)
    _task(hass)
    uid = (await _items(hass))[0]["uid"]
    await _tick(hass, uid, users["sam"])
    assert _book(hass).ledger[0]["day"] == "2026-11-16" and _games(hass).bonus_chores == 15
    freezer.move_to(late + timedelta(minutes=5))
    _hub(hass).household.recompute()
    assert _games(hass).bonus_chores == 0
    assert _book(hass).minutes_today("person.sam", "games") == 0


async def test_all_screen_time_is_mirrored_as_add_bonus_is(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator, monkeypatch
) -> None:
    _client, _secret, users, _sent = await _kids(hass, hass_client_no_auth)
    mirrored = []
    monkeypatch.setattr(_hub(hass).household.sync, "mirror_bonus", lambda person, had_none: mirrored.append((person, had_none)))
    await hass.services.async_call(DOMAIN, "set_budget", {"person": "person.sam", "group": "all", "minutes": 15}, blocking=True)
    _task(hass, reward={"pool": "all", "minutes": 20})
    _task(hass, "Games one")
    uids = {i["summary"].split(" (")[0]: i["uid"] for i in await _items(hass)}
    await _tick(hass, uids["Feed the cat"], users["sam"])
    await _tick(hass, uids["Games one"], users["sam"])
    # All screen time had run out (15 of 15 used): Google's and Microsoft's own limits get it; Games isn't mirrored
    assert mirrored == [("person.sam", True)]
    assert _hub(hass).household.days["person.sam"].limits["all"].minutes_left == 20


async def test_money_is_a_balance(hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator, hass_ws_client: WebSocketGenerator) -> None:
    _client, _secret, users, _sent = await _kids(hass, hass_client_no_auth)
    _task(hass, "Mow", reward={"cents": 500})
    _task(hass, "Rake", reward={"cents": 200})
    uids = {i["summary"].split(" (")[0]: i["uid"] for i in await _items(hass)}
    assert {i["summary"] for i in await _items(hass)} >= {"Mow (+$5.00)"}
    await _tick(hass, uids["Mow"], users["sam"])
    await _tick(hass, uids["Rake"], users["sam"])
    ws = await hass_ws_client(hass)
    await ws.send_json({"id": 1, "type": "hearth/todo/money", "person": "person.sam", "kind": "paid", "cents": 300})
    assert (await ws.receive_json())["success"]
    await ws.send_json({"id": 2, "type": "hearth/todo/money", "person": "person.sam", "kind": "adjust", "cents": -50})
    assert (await ws.receive_json())["success"]
    assert _book(hass).balance_cents("person.sam") == 350
    await ws.send_json({"id": 3, "type": "hearth/todo/undo", "key": f"{uids['Rake']}#1"})
    assert (await ws.receive_json())["success"]
    assert _book(hass).balance_cents("person.sam") == 150
    assert _summary_person(hass, "person.sam")["balance_cents"] == 150
    assert _summary_person(hass, "person.sam")["todo"] == {"left": 0, "done": 2, "total": 2}
    # No minutes moved
    assert _games(hass).bonus_chores == 0


async def test_the_panel_editor(hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator, hass_ws_client: WebSocketGenerator) -> None:
    await _kids(hass, hass_client_no_auth)
    ws = await hass_ws_client(hass)
    await ws.send_json(
        {
            "id": 1, "type": "hearth/todo/task/save", "person": "person.sam", "title": "Feed the cat",
            "repeat": {"kind": "weekdays", "days": [0, 2]}, "due_time": "07:30", "reward": {"pool": "games", "minutes": 15},
        }
    )
    saved = (await ws.receive_json())["result"]
    assert saved["by"] == "adult" and saved["repeat"] == {"kind": "weekdays", "days": [0, 2]}
    # Bad input is refused with words
    await ws.send_json({"id": 2, "type": "hearth/todo/task/save", "person": "person.sam", "title": "x", "due_time": "7pm"})
    assert (await ws.receive_json())["error"]["code"] == "invalid"
    await ws.send_json({"id": 3, "type": "hearth/todo/task/save", "person": "person.alex", "title": "x"})
    assert (await ws.receive_json())["error"]["code"] == "invalid"
    await ws.send_json({"id": 4, "type": "hearth/todo/task/save", "person": "person.sam", "title": "x", "reward": {"pool": "nope", "minutes": 5}})
    assert (await ws.receive_json())["error"]["code"] == "invalid"
    # A kid's item given a reward by an adult becomes the adult's (a kid can't then change it)
    kid_task = _book(hass).add_item("person.sam", "Practice piano", Actor("kid", "person.sam"))
    await ws.send_json(
        {"id": 5, "type": "hearth/todo/task/save", "task_id": kid_task["id"], "person": "person.sam", "title": "Practice piano",
         "reward": {"pool": "games", "minutes": 10}}
    )
    assert (await ws.receive_json())["result"]["by"] == "adult"
    await ws.send_json({"id": 6, "type": "hearth/todo/list", "person": "person.sam"})
    view = (await ws.receive_json())["result"]
    assert {t["title"] for t in view["tasks"]} == {"Feed the cat", "Practice piano"}
    assert view["balance_cents"] == 0 and view["caps"] == {}
    await ws.send_json({"id": 7, "type": "hearth/todo/task/delete", "task_id": saved["id"]})
    assert (await ws.receive_json())["success"]
    assert saved["id"] not in _book(hass).tasks
    await ws.send_json({"id": 8, "type": "hearth/todo/caps", "caps": {"games": 30, "video": None}})
    assert (await ws.receive_json())["result"] == {"games": 30}
    await hass.async_block_till_done()
    assert _book(hass).caps() == {"games": 30}


async def test_the_old_chores_lists_are_brought_in(hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator) -> None:
    await _kids(hass, hass_client_no_auth)
    # After the to-do integration loaded with Hearth's lists: the old list's items, as its own integration answers
    async_mock_service(
        hass,
        "todo",
        "get_items",
        response={
            "todo.sam_chores": {
                "items": [
                    {"uid": "1", "summary": "Dishes +30", "status": "needs_action"},
                    {"uid": "2", "summary": "Bed", "status": "needs_action"},
                ]
            }
        },
        supports_response=SupportsResponse.ONLY,
    )
    hass.states.async_set("todo.sam_chores", "2")
    await _options(hass, chores=[{"person": "person.sam", "todo": "todo.sam_chores", "group": "video", "minutes": 10}])
    await hass.async_block_till_done()
    entry = hass.config_entries.async_entries(DOMAIN)[0]
    assert "chores" not in entry.options
    tasks = sorted((t["title"], t["reward"]["minutes"], t["reward"]["pool"], t["repeat"]["kind"]) for t in _book(hass).tasks.values())
    assert tasks == [("Bed", 10, "video", "once"), ("Dishes", 30, "video", "once")]
    assert _book(hass).imports == []


def test_chore_minutes_fold_into_the_bonus_and_are_capped(hass: HomeAssistant) -> None:
    limits = Limits(hass, "x")
    limits.set_bonus("person.sam", "games", 10)
    assert limits.state("person.sam", "games", 0, "weekday").bonus_chores == 0
    limits.chore_minutes = lambda person, group: 25 if group == "games" else 0
    state = limits.state("person.sam", "games", 0, "weekday")
    assert (state.bonus_min, state.bonus_chores) == (35, 25)
    limits.chore_minutes = lambda person, group: MAX_BONUS
    assert limits.state("person.sam", "games", 0, "weekday").bonus_min == MAX_BONUS


def test_a_kid_s_item_never_carries_a_reward(hass: HomeAssistant) -> None:
    """The book alone: an item added on the list has none, and only an adult sets the list up."""
    from custom_components.hearth.todos import ChoreBook

    class _Household:
        options = {"roles": {"person.sam": "kid"}}

        def person_name(self, person):
            return "Sam"

        def group(self, group_id):
            return None

    book = ChoreBook(hass, _Household(), "x")
    book._changed = lambda recompute=False: None
    task = book.add_item("person.sam", "Read 20 pages", Actor("kid", "person.sam"))
    assert task["reward"] is None and task["by"] == "kid"
    with pytest.raises(ChoreError):
        book.save_task({"person": "person.sam", "title": "x"}, Actor("kid", "person.sam"))
