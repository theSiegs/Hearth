"""Messages is not exempt from limits: it counts toward daily time, is paused like any app, and the upgrade moves an
older household's "messaging outside daily time" once."""

from datetime import timedelta

import pytest

from homeassistant.core import HomeAssistant
from pytest_homeassistant_custom_component.common import async_mock_service
from pytest_homeassistant_custom_component.typing import ClientSessionGenerator

from custom_components.hearth import enforce
from custom_components.hearth.app_blocks import never_blocked
from custom_components.hearth.const import DOMAIN
from custom_components.hearth.enforce import essential
from custom_components.hearth.limits import CONF_MESSAGING_COUNTED, count_messaging, groups_from_options
from test_people import _household_with_sam
from test_sources import _option

FAMILY_LINK = "sensor.sam_family_link_daily_screen_time"
MESSAGES = "com.google.android.apps.messaging"


@pytest.fixture(autouse=True)
def settled(monkeypatch):
    monkeypatch.setattr(enforce, "SETTLE", timedelta(0))


def test_messages_apps_are_neither_essential_nor_never_blocked() -> None:
    for package in (MESSAGES, "com.samsung.android.messaging"):
        assert not essential(package) and not never_blocked(package)
    # Emergency calls still work: the dialer, contacts, Settings, Play services, Family Link and the Play Store stay
    for package in ("com.google.android.dialer", "com.google.android.contacts", "com.android.settings",
                    "com.google.android.gms", "com.google.android.apps.kids.familylink", "com.android.vending"):
        assert essential(package)


def test_messaging_counts_toward_daily_time_by_default() -> None:
    messaging = next(g for g in groups_from_options({}) if g.id == "messaging")
    assert messaging.in_all
    # An adult may still take it out
    assert not next(g for g in groups_from_options({"outside_all": ["messaging"]}) if g.id == "messaging").in_all


def test_the_upgrade_counts_messaging_once() -> None:
    older = {"outside_all": ["messaging", "music"], "inside_all": ["messaging"]}
    moved = count_messaging(older)
    assert moved["outside_all"] == ["music"] and moved["inside_all"] == [] and moved[CONF_MESSAGING_COUNTED] == 2
    # Done: an adult's own choice afterwards stays
    again = {**moved, "outside_all": ["music", "messaging"]}
    assert count_messaging(again) is None
    assert count_messaging({}) == {CONF_MESSAGING_COUNTED: 2}


async def _sam_with_messages(hass, hass_client_no_auth, minutes: int):
    calls = {
        "pause": async_mock_service(hass, "familylink", "pause_app"),
        "resume": async_mock_service(hass, "familylink", "resume_app"),
        "limit": async_mock_service(hass, "familylink", "set_daily_limit"),
    }
    await _household_with_sam(hass, hass_client_no_auth)
    hass.states.async_set(
        FAMILY_LINK, str(minutes),
        {"unit_of_measurement": "min", "child_id": "42", "apps": [{"package": MESSAGES, "minutes": minutes}]},
    )
    await _option(hass, "add_source", {"entity_id": FAMILY_LINK, "person": "person.sam"})
    await _option(hass, "enforce", {"person": "person.sam", "family_link": FAMILY_LINK, "fl_backstop": False})
    return calls, hass.config_entries.async_entries(DOMAIN)[0].runtime_data.household


async def _budget(hass, group: str, minutes: int) -> None:
    await hass.services.async_call(
        DOMAIN, "set_budget", {"person": "person.sam", "group": group, "minutes": minutes}, blocking=True
    )
    await hass.async_block_till_done()


async def test_messages_counts_and_is_paused_when_daily_time_runs_out(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator
) -> None:
    calls, household = await _sam_with_messages(hass, hass_client_no_auth, 40)
    day = household.days["person.sam"]
    # 15 on the TV + 40 of Messages on the phone
    assert int(day.groups["all"] // 60) == 55 and int(day.groups["messaging"] // 60) == 40
    await _budget(hass, "all", 50)
    # Daily time used up: the state document holds every app, Messages included (not spared in "except")
    document = household._person_document("person.sam")
    whole = next(g for g in document["groups"] if g["id"] == "all")
    assert whole["minutes_left"] == 0 and MESSAGES not in whole.get("except", [])
    assert MESSAGES not in document.get("never_held", [])


def _fl_total(hass, minutes: int, games: int = 0) -> None:
    apps = [{"package": MESSAGES, "minutes": minutes}] + ([{"package": "com.example.game", "minutes": games}] if games else [])
    hass.states.async_set(
        FAMILY_LINK, str(minutes + games), {"unit_of_measurement": "min", "child_id": "42", "apps": apps}
    )


async def test_a_messaging_bonus_when_daily_time_is_used_up(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator
) -> None:
    """Out of daily time, "+15 min Messaging bonus" lets 15 minutes of Messaging run, then holds; games stay held."""
    calls, household = await _sam_with_messages(hass, hass_client_no_auth, 40)
    await _budget(hass, "all", 50)  # 55 used: out
    assert household.days["person.sam"].limits["all"].minutes_left == 0
    await hass.services.async_call(
        DOMAIN, "add_time", {"person": "person.sam", "minutes": 15, "category": "messaging"}, blocking=True
    )
    await hass.async_block_till_done()
    view = household.time_view("person.sam")
    [row] = view["category_bonuses"]
    assert (row["bonus"], row["bonus_left"], row["text"]) == (15, 10, "Messaging: 10 min bonus left")
    # (5 of the 55 were already past daily time: Messaging's bonus paid them)
    assert view["today_left"] == 0 and view["bonus_left"] == 0
    assert view["origins"][0]["detail"] == "Messaging bonus +15"
    # Messages runs (daily time's hold leaves it out), games doesn't
    document = household._person_document("person.sam")
    whole = next(g for g in document["groups"] if g["id"] == "all")
    assert MESSAGES in whole.get("except", []) and "com.example.game" not in whole.get("except", [])
    explained = await hass.services.async_call(
        DOMAIN, "explain", {"person": "person.sam", "app": MESSAGES}, blocking=True, return_response=True
    )
    assert explained["allowed"] is True
    game = await hass.services.async_call(
        DOMAIN, "explain", {"person": "person.sam", "app": "com.example.game"}, blocking=True, return_response=True
    )
    assert game["allowed"] is False
    # 10 more minutes of Messages: its bonus is used up, held again
    _fl_total(hass, 50)
    await hass.async_block_till_done()
    household.recompute()
    await hass.async_block_till_done()
    assert household.time_view("person.sam")["category_bonuses"][0]["bonus_left"] == 0
    document = household._person_document("person.sam")
    whole = next(g for g in document["groups"] if g["id"] == "all")
    assert MESSAGES not in whole.get("except", [])
    # Taken back: never below 0
    removed = await hass.services.async_call(
        DOMAIN, "remove_time", {"person": "person.sam", "minutes": 30, "category": "messaging"},
        blocking=True, return_response=True,
    )
    assert removed["removed"] == {"person.sam": 15}


async def test_the_backstop_counts_a_category_bonus(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator
) -> None:
    calls, household = await _sam_with_messages(hass, hass_client_no_auth, 40)
    await _option(hass, "enforce", {"person": "person.sam", "family_link": FAMILY_LINK, "fl_backstop": True})
    household = hass.config_entries.async_entries(DOMAIN)[0].runtime_data.household
    phone = "sensor.sam_phone_daily_screen_time"
    hass.states.async_set(phone, "40", {"child_id": "42", "device_id": "p1", "capabilities": ["capabilityBedtime"]})
    await _budget(hass, "all", 100)
    # 45 left: 40 + 45 + 30
    assert calls["limit"][-1].data["daily_minutes"] == 115
    await hass.services.async_call(
        DOMAIN, "add_time", {"person": "person.sam", "minutes": 20, "category": "messaging"}, blocking=True
    )
    await hass.async_block_till_done()
    assert calls["limit"][-1].data["daily_minutes"] == 135
    # Daily time used up, the Messaging bonus still left: no whole-device hold, the backstop stays
    await _budget(hass, "all", 55)
    assert all(c.data.get("daily_minutes") != 0 for c in calls["limit"])


async def test_messages_is_paused_when_its_limit_is_used_up(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator
) -> None:
    calls, household = await _sam_with_messages(hass, hass_client_no_auth, 40)
    await _budget(hass, "messaging", 30)
    assert any(MESSAGES in c.data["packages"] for c in calls["pause"])
