"""The Today redesign's rules for suggestions (glance.hold_back): none during a lock or a pause, none after bedtime
(or after 21:00 without one), a device's own limit only while that device is in use, at most one per kid (a request
first); the held ones come back with why. Also: device display names (targets.display_name), taking back a bonus
(hearth.remove_bonus), and a totals sensor still on yesterday's number after midnight (sources.totals_reading)."""

from datetime import datetime, timedelta
from types import SimpleNamespace

import pytest

from homeassistant.core import HomeAssistant
from homeassistant.exceptions import Unauthorized
from homeassistant.helpers import device_registry as dr, entity_registry as er
from homeassistant.util import dt as dt_util
from pytest_homeassistant_custom_component.common import MockConfigEntry, async_fire_time_changed
from pytest_homeassistant_custom_component.typing import ClientSessionGenerator

from custom_components.hearth.const import DOMAIN
from custom_components.hearth.glance import (
    HOLD_BEDTIME,
    HOLD_CUTOFF,
    HOLD_LOCK,
    HOLD_MORE,
    HOLD_NOT_IN_USE,
    HOLD_PAUSE,
    hold_back,
    household_glance,
    person_glance,
    suggestions,
)
from custom_components.hearth.history import BONUS
from custom_components.hearth.sources import Source, totals_reading
from custom_components.hearth.suggest_push import DEBOUNCE
from custom_components.hearth.targets import display_name
from test_glance import _person
from test_suggest_push import _pushes, _video_out
from test_attention import _household, _hub
from test_phones import _options


def _at(hour: int, minute: int = 0) -> datetime:
    return dt_util.now().replace(hour=hour, minute=minute, second=0, microsecond=0)


def _iso(hour: int, minute: int = 0, days: int = 0) -> str:
    return (_at(hour, minute) + timedelta(days=days)).isoformat()


XBOX = {"id": "fs:xbox", "name": "Xbox", "display_name": "Xbox", "kind": "xbox", "via": "family_safety"}


def _kid(**extra) -> dict:
    """Alex: Games out (YouTube too, when asked), an Xbox Microsoft's own limit stops."""
    person = {
        **_person(all=40, games=0),
        "targets": [XBOX],
        "first_party": {"family_safety": [{"platform": "Xbox", "blocking": True}]},
        "device_extras": [],
    }
    person.update(extra)
    return person


def _held(person, now, asks=()):
    shown, held = hold_back(person, suggestions(person, list(asks), []), list(asks), now)
    return [s["key"] for s in shown], {s["key"]: (s["held"], s["why"]) for s in held}


def test_a_lock_or_a_pause_holds_every_suggestion() -> None:
    bedtime = _kid(lock={"kind": "bedtime", "until": _iso(7, days=1)})
    shown, held = _held(bedtime, _at(16))
    assert shown == []
    assert held == {"more:games": (HOLD_LOCK, "in bedtime till 7:00"), "device:fs:xbox": (HOLD_LOCK, "in bedtime till 7:00")}
    school = _kid(lock={"kind": "school_time", "until": _iso(15, 15)})
    assert _held(school, _at(10))[1]["more:games"] == (HOLD_LOCK, "in School time till 3:15")
    paused = _kid(pause={"until": _iso(18, 30), "reason": "dinner"})
    assert _held(paused, _at(18))[1]["more:games"] == (HOLD_PAUSE, "paused till 6:30")


def test_after_bedtime_or_after_nine_without_one() -> None:
    with_bedtime = _kid(bedtime={"start": _iso(20, 30), "end": _iso(7)})
    assert _held(with_bedtime, _at(19))[0] == ["more:games"]
    assert _held(with_bedtime, _at(20, 45))[1]["more:games"] == (HOLD_BEDTIME, "after bedtime (8:30)")
    assert _held(with_bedtime, _at(6, 30))[1]["more:games"] == (HOLD_BEDTIME, "before wake-up (7:00)")
    without = _kid()
    assert _held(without, _at(20, 59))[0] == ["more:games"]
    assert _held(without, _at(21))[1]["more:games"] == (HOLD_CUTOFF, "after 9:00 pm")
    assert _held(without, _at(5, 30))[1]["more:games"] == (HOLD_CUTOFF, "after 9:00 pm")


def test_a_device_limit_only_while_that_device_is_in_use() -> None:
    # Games out is the one shown; the Xbox waits behind it, and on its own only while someone's on the Xbox
    shown, held = _held(_kid(), _at(16))
    assert shown == ["more:games"] and held["device:fs:xbox"] == (HOLD_NOT_IN_USE, "not on the Xbox now")
    only_xbox = _kid(groups=_person(all=40, games=20)["groups"])
    assert _held(only_xbox, _at(16)) == ([], {"device:fs:xbox": (HOLD_NOT_IN_USE, "not on the Xbox now")})
    playing = {**only_xbox, "playing": [{"target": "fs:xbox", "app": "Minecraft"}]}
    assert _held(playing, _at(16))[0] == ["device:fs:xbox"]


def test_one_per_kid_and_a_request_comes_first() -> None:
    two = _person(all=40, games=0, youtube=0)
    shown, held = _held(two, _at(16))
    assert shown == ["more:games"] and held == {"more:youtube": (HOLD_MORE, "another for them shows first")}
    ask = {"id": "q1", "person": "person.alex", "minutes": 30, "group": "games"}
    shown, held = _held(two, _at(16), [ask])
    assert shown == [] and held == {"more:youtube": (HOLD_MORE, "a request from them comes first")}


def test_the_glance_and_the_household_carry_the_held_ones() -> None:
    alex = _kid(lock={"kind": "bedtime", "until": _iso(7, days=1)})
    alex.update(person_glance(alex, [], [], [], _at(22)))
    sam = {**_person(all=40, youtube=0), "id": "person.sam", "name": "Sam", "targets": [], "first_party": {}}
    sam.update(person_glance(sam, [], [], [], _at(16)))
    assert alex["suggestions"] == [] and [s["key"] for s in alex["suggestions_held"]] == ["more:games", "device:fs:xbox"]
    assert sam["suggestions"][0]["sentence"] == "Sam's Youtube time is up"
    assert sam["suggestions"][0]["detail"] == "Used 30 min of 1 h · 40 min of screen time left"
    house = household_glance([alex, sam], [])
    assert [(s["person"], s["key"]) for s in house["suggestions"]] == [("person.sam", "more:youtube")]
    assert [(s["person_name"], s["held"]) for s in house["suggestions_held"]] == [("Alex", "lock"), ("Alex", "lock")]
    assert house["counts"]["suggestions"] == 1 and house["counts"]["suggestions_held"] == 2
    assert house["counts"]["needs"] == 1


def test_a_device_suggestion_says_its_display_name() -> None:
    tablet = {"id": "fl:d1", "name": "SM-X230", "display_name": "Alex's tablet", "kind": "phone", "via": "family_link"}
    person = _kid(targets=[tablet], groups=_person(all=40)["groups"],
                  first_party={"family_link": [{"device_id": "d1", "device": "SM-X230", "blocking": True}]})
    [found] = suggestions(person, [], [])
    assert found["text"] == "alex's tablet · google's limit · give 15?"
    assert found["sentence"] == "Alex's tablet is stopped by Google's limit"
    _, held = _held(person, _at(16))
    assert held["device:fl:d1"] == (HOLD_NOT_IN_USE, "not on Alex's tablet now")
    [xbox] = suggestions(_kid(groups=_person(all=40)["groups"]), [], [])
    assert xbox["sentence"] == "Alex's Xbox is stopped by Microsoft's limit"


async def test_the_adults_phones_get_no_suggestion_after_nine(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator, freezer
) -> None:
    freezer.move_to(_at(21, 30))
    _client, _secret, _users, sent = await _household(hass, hass_client_no_auth)
    await _options(hass, suggest_push=[{"person": "person.sam", "group": "video", "minutes": 30}])
    await _video_out(hass)
    async_fire_time_changed(hass, dt_util.utcnow() + DEBOUNCE + timedelta(seconds=1))
    await hass.async_block_till_done()
    assert not _pushes(sent)
    from custom_components.hearth.websocket import summary

    sam = next(p for p in summary(_hub(hass))["people"] if p["id"] == "person.sam")
    assert sam["suggestions"] == []
    assert [(s["key"], s["held"]) for s in sam["suggestions_held"]] == [("more:video", HOLD_CUTOFF)]


# Device names


def _household_stub(hass: HomeAssistant, sources=(), child=None):
    return SimpleNamespace(hass=hass, sources=list(sources), family_link_child=lambda _person: child)


async def test_a_device_reads_by_the_name_given_in_home_assistant_else_its_source(hass: HomeAssistant) -> None:
    entry = MockConfigEntry(domain="test")
    entry.add_to_hass(hass)
    devices, entities = dr.async_get(hass), er.async_get(hass)
    # A Family Link tablet: the model id as its label, a source counting it by name
    fl_device = devices.async_get_or_create(config_entry_id=entry.entry_id, identifiers={("familylink", "d1")}, name="SM-X230")
    switch = entities.async_get_or_create("switch", "familylink", "c1_d1", device_id=fl_device.id)
    hass.states.async_set(switch.entity_id, "on", {"child_id": "c1", "device_id": "d1"})
    hass.states.async_set("sensor.alex_tablet_screen_time", "30", {"child_id": "c1", "device_id": "d1"})
    tablet = Source("tablet", "sensor.alex_tablet_screen_time", "person.alex", "Alex's tablet")
    household = _household_stub(hass, [tablet], child="c1")
    target = {"id": "fl:d1", "name": "SM-X230", "kind": "phone"}
    assert display_name(household, "person.alex", target) == "Alex's tablet"
    # A name given to its device in Home Assistant comes first
    devices.async_update_device(fl_device.id, name_by_user="Blue tablet")
    assert display_name(household, "person.alex", target) == "Blue tablet"
    # Someone else's source never names it; nothing known: the label
    assert display_name(_household_stub(hass, [tablet]), "person.sam", {"id": "fs:xbox", "name": "Xbox"}) == "Xbox"
    # A Switch: its enforcer entity's device, or a source on the same device
    console = devices.async_get_or_create(config_entry_id=entry.entry_id, identifiers={("nintendo", "s1")}, name="Home Switch")
    number = entities.async_get_or_create("number", "nintendo_parental_controls", "s1_max", device_id=console.id)
    game = entities.async_get_or_create("sensor", "nintendo_parental_controls", "s1_game", device_id=console.id)
    switch_source = Source("switch", game.entity_id, "person.alex", "Switch 2")
    target = {"id": f"nintendo:{number.entity_id}", "name": "Home Switch", "kind": "switch"}
    assert display_name(_household_stub(hass, [switch_source]), "person.alex", target) == "Switch 2"


async def test_a_hearth_tv_reads_by_its_device_of_hearth_s_entry(hass: HomeAssistant) -> None:
    """Hearth's own TV: its device found by identifier in Hearth's entry (async_get_device_by_identifier where Home
    Assistant has it, the older lookup otherwise)."""
    entry = MockConfigEntry(domain=DOMAIN)
    entry.add_to_hass(hass)
    devices = dr.async_get(hass)
    tv = devices.async_get_or_create(config_entry_id=entry.entry_id, identifiers={(DOMAIN, "tv1")}, name="Hearth")
    devices.async_update_device(tv.id, name_by_user="Den")
    target = {"id": "hearth:tv1", "name": "Hearth", "kind": "tv"}
    household = SimpleNamespace(hass=hass, sources=[], family_link_child=lambda _p: None,
                                hub=SimpleNamespace(entry=SimpleNamespace(entry_id=entry.entry_id)))
    assert display_name(household, "person.alex", target) == "Den TV"
    # No entry to look in: the older lookup still finds it
    assert display_name(_household_stub(hass), "person.alex", target) == "Den TV"
    # Another TV of Hearth's: no device, its label
    assert display_name(household, "person.alex", {"id": "hearth:tv2", "name": "Kitchen TV", "kind": "tv"}) == "Kitchen TV"


# Taking back a bonus


async def test_remove_bonus_takes_back_only_what_was_given(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator, hass_read_only_user
) -> None:
    await _household(hass, hass_client_no_auth)
    household = _hub(hass).household
    await hass.services.async_call(DOMAIN, "add_bonus", {"person": "person.sam", "group": "video", "minutes": 20}, blocking=True)
    response = await hass.services.async_call(
        DOMAIN, "remove_bonus", {"person": "person.sam", "group": "video", "minutes": 15}, blocking=True, return_response=True
    )
    assert response == {"removed": 15}
    assert household.limits.bonus("person.sam", "video") == 5
    # Never below what was given: their own budget stays
    response = await hass.services.async_call(
        DOMAIN, "remove_bonus", {"person": "person.sam", "group": "video", "minutes": 30}, blocking=True, return_response=True
    )
    assert response == {"removed": 5} and household.limits.bonus("person.sam", "video") == 0
    response = await hass.services.async_call(
        DOMAIN, "remove_bonus", {"person": "person.sam", "group": "video", "minutes": 30}, blocking=True, return_response=True
    )
    assert response == {"removed": 0}
    logged = [(e["minutes"], e.get("undo")) for e in household.history.of("person.sam", kinds=(BONUS,))]
    assert logged == [(20, None), (-15, True), (-5, True)]
    # Adults only
    from homeassistant.core import Context

    with pytest.raises(Unauthorized):
        await hass.services.async_call(
            DOMAIN, "remove_bonus", {"person": "person.sam", "minutes": 5}, blocking=True,
            context=Context(user_id=hass_read_only_user.id),
        )


async def test_remove_bonus_takes_back_what_family_link_got(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator
) -> None:
    await _household(hass, hass_client_no_auth)
    household = _hub(hass).household
    sync = household.sync
    taken: list = []

    async def take_back(person, record):
        taken.append((person, dict(record["devices"])))

    sync._take_back = take_back
    today = dt_util.now().date().isoformat()
    sync._given[("person.sam", f"bonus:{dt_util.now().isoformat()}")] = {"day": today, "devices": {"d1": 15}, "platforms": []}
    # All screen time still has time left once taken back: Family Link's extra time stays
    await hass.services.async_call(DOMAIN, "add_bonus", {"person": "person.sam", "minutes": 15}, blocking=True)
    await hass.services.async_call(DOMAIN, "remove_bonus", {"person": "person.sam", "minutes": 15}, blocking=True)
    await hass.async_block_till_done()
    state = household.days["person.sam"].limits["all"]
    if state.minutes_left == 0:
        assert taken == [("person.sam", {"d1": 15})]
    else:
        assert taken == [] and sync.take_back_bonus("person.sam") is True
        await hass.async_block_till_done()
        assert taken == [("person.sam", {"d1": 15})]
    assert sync.take_back_bonus("person.sam") is False


# A totals sensor after midnight


async def test_a_totals_sensor_not_updated_since_midnight_doesn_t_count(hass: HomeAssistant, freezer) -> None:
    freezer.move_to(_at(23, 50))
    hass.states.async_set("sensor.alex_phone_screen_time", "75", {"unit_of_measurement": "min"})
    source = Source("phone", "sensor.alex_phone_screen_time", "person.alex", "Phone")
    today = dt_util.now().date()
    assert totals_reading(hass, source, today).total_s == 75 * 60
    freezer.move_to(_at(23, 50) + timedelta(minutes=15))
    tomorrow = dt_util.now().date()
    # Still yesterday's 75 minutes: not today's
    assert totals_reading(hass, source, tomorrow) is None
    assert totals_reading(hass, source).total_s == 75 * 60
    hass.states.async_set("sensor.alex_phone_screen_time", "2", {"unit_of_measurement": "min"})
    assert totals_reading(hass, source, tomorrow).total_s == 120
