"""Attention items: one place every notice goes through, out to the companion app and the bell as before, with phone
buttons that run their action as the adult who pressed them."""

from homeassistant.components import persistent_notification
from homeassistant.core import Context, HomeAssistant
from pytest_homeassistant_custom_component.common import async_mock_service
from pytest_homeassistant_custom_component.typing import ClientSessionGenerator

from custom_components.hearth.apps import AppEntry
from custom_components.hearth.attention import (
    ADMINS,
    ADULTS,
    CHOSEN_PHONE,
    PERSON,
    SCHEDULE_PHONE,
    Action,
    Item,
)
from custom_components.hearth.chores import Chores
from custom_components.hearth.const import DOMAIN
from custom_components.hearth.phones import phones
from test_asks import _ask
from test_parent_pin import _adults
from test_people import _household_with_sam
from test_phones import _companion_app, _options


def _hub(hass: HomeAssistant):
    return hass.config_entries.async_entries(DOMAIN)[0].runtime_data


async def _household(hass: HomeAssistant, hass_client_no_auth):
    """Sam is a kid with a phone of their own; Alex and Jordan adults, each with a phone and a user of their own."""
    client, secret = await _household_with_sam(hass, hass_client_no_auth)
    alex_user = await hass.auth.async_create_user("Alex")
    jordan_user = await hass.auth.async_create_user("Jordan")
    sam_user = await hass.auth.async_create_user("Sam")
    _companion_app(hass, "Alex Phone", "Android", user_id=alex_user.id)
    _companion_app(hass, "Jordan iPhone", "iOS", user_id=jordan_user.id)
    _companion_app(hass, "Sam Phone", "Android", user_id=sam_user.id)
    hass.states.async_set("person.alex", "home", {"friendly_name": "Alex", "user_id": alex_user.id})
    hass.states.async_set("person.jordan", "home", {"friendly_name": "Jordan", "user_id": jordan_user.id})
    hass.states.async_set("person.sam", "home", {"friendly_name": "Sam", "user_id": sam_user.id})
    await _adults(hass, "person.alex", "person.jordan")
    sent = {
        name: async_mock_service(hass, "notify", f"mobile_app_{name}")
        for name in ("alex_phone", "jordan_iphone", "sam_phone", "kitchen_tablet")
    }
    return client, secret, {"alex": alex_user, "jordan": jordan_user, "sam": sam_user}, sent


def _press(hass: HomeAssistant, action: str, user) -> None:
    hass.bus.async_fire("mobile_app_notification_action", {"action": action}, context=Context(user_id=user.id))


def _bell(hass: HomeAssistant) -> dict:
    return persistent_notification._async_get_or_create_notifications(hass)


async def test_audiences_resolve_as_before(hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator) -> None:
    await _household(hass, hass_client_no_auth)
    attention = _hub(hass).attention
    await _options(hass, ask_notify="notify.mobile_app_kitchen_tablet")
    options = _hub(hass).entry.options
    # The adults: exactly the phones requests always went to (each adult's, and the chosen one once)
    assert [p.service for p in attention.targets(ADULTS)] == [p.service for p in phones(hass, options)]
    assert {p.service for p in attention.targets(ADULTS)} == {
        "mobile_app_alex_phone", "mobile_app_jordan_iphone", "mobile_app_kitchen_tablet"
    }
    assert [p.service for p in attention.targets(CHOSEN_PHONE)] == ["mobile_app_kitchen_tablet"]
    # The schedule's own phone, else the chosen one
    assert [p.service for p in attention.targets(SCHEDULE_PHONE)] == ["mobile_app_kitchen_tablet"]
    await _options(hass, schedule={"notify": "notify.mobile_app_jordan_iphone"})
    assert [p.service for p in attention.targets(SCHEDULE_PHONE)] == ["mobile_app_jordan_iphone"]
    assert [p.service for p in attention.targets(f"{PERSON}person.sam")] == ["mobile_app_sam_phone"]
    assert attention.targets(ADMINS) == []


async def test_a_tag_replaces_and_clears(hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator) -> None:
    _client, _secret, _users, sent = await _household(hass, hass_client_no_auth)
    attention = _hub(hass).attention
    attention.notify(Item("hearth_news_1", "First", title="News", tag="hearth_news", bell=True))
    attention.notify(Item("hearth_news_2", "Second", title="News", tag="hearth_news", bell=True))
    await hass.async_block_till_done()
    # One item, one bell notification: the second replaced the first
    assert [i.key for i in attention.items() if i.channel_tag == "hearth_news"] == ["hearth_news_2"]
    assert _bell(hass)["hearth_news"]["message"] == "Second"
    assert sent["alex_phone"][-1].data == {"title": "News", "message": "Second", "data": {"tag": "hearth_news"}}

    attention.clear("hearth_news")
    await hass.async_block_till_done()
    assert attention.item("hearth_news_2") is None
    assert "hearth_news" not in _bell(hass)
    for phone in ("alex_phone", "jordan_iphone"):
        assert sent[phone][-1].data == {"message": "clear_notification", "data": {"tag": "hearth_news"}}
    assert not sent["sam_phone"]


async def test_a_button_runs_its_action_as_the_adult(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator
) -> None:
    _client, _secret, users, sent = await _household(hass, hass_client_no_auth)
    ran = async_mock_service(hass, "hearth", "give_more_test")
    attention = _hub(hass).attention
    attention.notify(
        Item(
            "hearth_offer_sam",
            "Give Sam 15 more minutes?",
            actions=(Action("give", "+15 min", "hearth.give_more_test", {"minutes": 15}),),
        )
    )
    await hass.async_block_till_done()
    # The phone holds the key and the button's number, never the service
    assert sent["alex_phone"][-1].data["data"]["actions"] == [{"action": "HEARTH_ACT|hearth_offer_sam|0", "title": "+15 min"}]

    _press(hass, "HEARTH_ACT|hearth_offer_sam|0", users["alex"])
    await hass.async_block_till_done()
    assert len(ran) == 1
    assert ran[0].data == {"minutes": 15}
    assert ran[0].context.user_id == users["alex"].id


async def test_a_press_from_a_kid_or_someone_it_wasn_t_for_is_refused(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator
) -> None:
    _client, _secret, users, _sent = await _household(hass, hass_client_no_auth)
    ran = async_mock_service(hass, "hearth", "give_more_test")
    attention = _hub(hass).attention
    action = (Action("give", "+15 min", "hearth.give_more_test"),)
    attention.notify(Item("hearth_for_adults", "For the adults", actions=action))
    attention.notify(Item("hearth_for_jordan", "For Jordan", audience=f"{PERSON}person.jordan", actions=action))
    await hass.async_block_till_done()

    # A kid with the companion app fires the same action: not an adult
    _press(hass, "HEARTH_ACT|hearth_for_adults|0", users["sam"])
    # An adult the item didn't reach
    _press(hass, "HEARTH_ACT|hearth_for_jordan|0", users["alex"])
    # Unknown keys, a button that isn't there, a malformed one
    for bad in ("HEARTH_ACT|hearth_gone|0", "HEARTH_ACT|hearth_for_adults|3", "HEARTH_ACT|hearth_for_adults|x", "HEARTH_ACT|"):
        _press(hass, bad, users["alex"])
    await hass.async_block_till_done()
    assert not ran

    _press(hass, "HEARTH_ACT|hearth_for_jordan|0", users["jordan"])
    await hass.async_block_till_done()
    assert len(ran) == 1


async def test_items_survive_the_entry_reloading(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator
) -> None:
    _client, _secret, users, _sent = await _household(hass, hass_client_no_auth)
    ran = async_mock_service(hass, "hearth", "give_more_test")
    _hub(hass).attention.notify(Item("hearth_kept", "Kept", actions=(Action("give", "+15", "hearth.give_more_test"),)))
    entry = hass.config_entries.async_entries(DOMAIN)[0]
    assert await hass.config_entries.async_reload(entry.entry_id)
    await hass.async_block_till_done()

    assert _hub(hass).attention.item("hearth_kept") is not None
    _press(hass, "HEARTH_ACT|hearth_kept|0", users["alex"])
    await hass.async_block_till_done()
    assert len(ran) == 1


async def test_every_phone_push_is_tagged_hearth(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator
) -> None:
    client, secret, _users, sent = await _household(hass, hass_client_no_auth)
    await _options(hass, ask_notify="notify.mobile_app_kitchen_tablet")
    hub = _hub(hass)
    household = hub.household
    # A request, news for the adults, the schedule's check, a chore done, a new app's question
    request = (await (await _ask(client, secret, minutes=30, profile_id="user:10")).json())["request"]
    hub.asks.tell("Sam: School", "Sam got to school.", "hearth_place_person.sam")
    household.scheduler.tell("Today's schedule", "Check Family Link.", "hearth_schedule_check")
    household.chores._tell(Chores("person.sam", "todo.sam", "all", 15), "chore-uid-1", "Dishes", 15)
    household._ask_on_phone(AppEntry("com.example.game", "Example Game", "2026-11-13", "new", who="Sam"))
    await hass.async_block_till_done()

    calls = [call for phone in sent.values() for call in phone]
    tags = {call.data["data"]["tag"] for call in calls}
    assert all(call.data.get("data", {}).get("tag", "").startswith("hearth_") for call in calls)
    assert tags == {
        f"hearth_more_{request['id']}",
        "hearth_place_person.sam",
        "hearth_schedule_check",
        "hearth_chore_chore-uid-1",
        "hearth_app_com.example.game",
    }


async def test_news_about_a_kid_stays_off_the_bell(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator
) -> None:
    """The bell shows to everyone who uses Home Assistant: a kid's request (with its note), place news and chores go
    to the adults' phones only; the household's own business (the schedule's checks, a pairing) stays on the bell."""
    from custom_components.hearth.notifications import notify_pairing

    client, secret, _users, sent = await _household(hass, hass_client_no_auth)
    hub = _hub(hass)
    household = hub.household
    request = (await (await _ask(client, secret, minutes=30, profile_id="user:10")).json())["request"]
    hub.asks.tell("Sam: School", "Sam got to school.", "hearth_place_person.sam")
    household.chores._tell(Chores("person.sam", "todo.sam", "all", 15), "chore-uid-1", "Dishes", 15)
    household.scheduler.tell("Today's schedule", "Check Family Link.", "hearth_schedule_check")
    notify_pairing(hass, "p-1", "Kitchen TV")
    await hass.async_block_till_done()

    bell = _bell(hass)
    assert f"hearth_more_{request['id']}" not in bell
    assert "hearth_place_person.sam" not in bell
    assert "hearth_chore_chore-uid-1" not in bell
    assert not any("Sam" in n["message"] or "Sam" in (n.get("title") or "") for n in bell.values())
    assert {"hearth_schedule_check", "hearth_pairing_p-1"} <= set(bell)
    # The adults' phones still hear of the request, with its buttons, and of the place news
    tags = {call.data["data"]["tag"] for call in sent["alex_phone"]}
    assert {f"hearth_more_{request['id']}", "hearth_place_person.sam"} <= tags
    # Still answerable: the request is waiting for an adult
    assert hub.asks.get(request["id"]).status == "pending"


async def test_a_button_runs_only_hearth_services(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator
) -> None:
    """Defence in depth: an item's button runs a hearth service only, whatever an item was given."""
    _client, _secret, users, _sent = await _household(hass, hass_client_no_auth)
    script = async_mock_service(hass, "script", "give_more")
    lock = async_mock_service(hass, "lock", "unlock")
    attention = _hub(hass).attention
    attention.notify(
        Item(
            "hearth_not_ours",
            "Not ours",
            actions=(Action("s", "Script", "script.give_more"), Action("l", "Unlock", "lock.unlock", {"entity_id": "lock.front"})),
        )
    )
    await hass.async_block_till_done()
    _press(hass, "HEARTH_ACT|hearth_not_ours|0", users["alex"])
    _press(hass, "HEARTH_ACT|hearth_not_ours|1", users["alex"])
    await hass.async_block_till_done()
    assert not script
    assert not lock
