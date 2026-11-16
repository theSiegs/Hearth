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


async def test_messages_is_paused_when_its_limit_is_used_up(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator
) -> None:
    calls, household = await _sam_with_messages(hass, hass_client_no_auth, 40)
    await _budget(hass, "messaging", 30)
    assert any(MESSAGES in c.data["packages"] for c in calls["pause"])
