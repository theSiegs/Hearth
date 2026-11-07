"""Places: where each kid is (a place's name from Home Assistant zones, never coordinates), and exceptions that end when
they arrive somewhere or leave."""

from datetime import date, timedelta

from homeassistant.core import HomeAssistant
from homeassistant.exceptions import ServiceValidationError
from homeassistant.util import dt as dt_util
from pytest_homeassistant_custom_component.common import async_capture_events, async_mock_service
from pytest_homeassistant_custom_component.typing import ClientSessionGenerator
import pytest

from custom_components.hearth.const import DOMAIN
from custom_components.hearth.pause import pause_of
from custom_components.hearth.sensor import PersonPlace
from test_native_sync import _phone, _remaining, _sam_with_family_link, settled  # noqa: F401 - the fixture
from test_people import _household_with_sam
from test_schedule import SWITCH, YEAR, _at as _clock, _set_up, _tick
from test_sources import _option

CHILD = "42"
TRACKER = "device_tracker.sam_family_link"
PLACE = "sensor.hearth_sam_place"
HOME = (40.0, -75.0)
SCHOOL = (40.02, -75.0)  # about 2 km from home
PRACTICE = (40.05, -75.0)
ELSEWHERE = (40.1, -75.1)


def _zones(hass: HomeAssistant) -> None:
    for entity_id, (lat, lon), radius, name in (
        ("zone.home", HOME, 100, "Home"),
        ("zone.school", SCHOOL, 150, "School"),
        ("zone.practice", PRACTICE, 200, "Practice"),
    ):
        hass.states.async_set(entity_id, "0", {"latitude": lat, "longitude": lon, "radius": radius, "friendly_name": name})


async def _reading(hass: HomeAssistant, freezer, where, accuracy: float = 10, age=timedelta(0)) -> None:
    """A new Family Link location (a moment later than the last, so it's a reading of its own)."""
    if freezer is not None:
        freezer.tick(timedelta(seconds=30))
    hass.states.async_set(
        TRACKER,
        "not_home",
        {
            "child_id": CHILD,
            "source_type": "gps",
            "latitude": where[0],
            "longitude": where[1],
            "gps_accuracy": accuracy,
            # As Family Link writes it: local time with no offset
            "location_timestamp": dt_util.as_local(dt_util.utcnow() - age).replace(tzinfo=None).isoformat(),
        },
    )
    await hass.async_block_till_done()


def _household(hass: HomeAssistant):
    return hass.config_entries.async_entries(DOMAIN)[0].runtime_data.household


async def _places(hass: HomeAssistant, **extra) -> None:
    await _option(
        hass,
        "places",
        {"person": "person.sam", "school": "zone.school", "favorite_zone": "zone.practice", "favorite_name": "Practice", **extra},
    )


async def _sam_at(hass: HomeAssistant, hass_client_no_auth, freezer, where) -> None:
    """Sam with Family Link (a tracker of his child) and places, at [where]."""
    if freezer is not None:
        freezer.move_to(dt_util.now().replace(hour=12, minute=0, second=0, microsecond=0))
    await _sam_with_family_link(hass, hass_client_no_auth)
    _zones(hass)
    await _reading(hass, freezer, where)
    await _places(hass)


async def _update(hass: HomeAssistant) -> None:
    _household(hass).places.update()
    await hass.async_block_till_done()


# The place sensor


async def test_a_fresh_family_link_reading_places_them_and_a_change_needs_two(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator, freezer
) -> None:
    await _sam_at(hass, hass_client_no_auth, freezer, HOME)
    moved = async_capture_events(hass, "hearth_place")
    state = hass.states.get(PLACE)
    assert state.state == "home"
    assert state.attributes["name"] == "Home"
    assert state.attributes["source"] == "family_link"
    assert state.attributes["fresh"] is True and state.attributes["accuracy"] == 10
    # No coordinates anywhere
    assert "latitude" not in state.attributes and "longitude" not in state.attributes

    # One reading at school isn't a change yet; the second is
    await _reading(hass, freezer, SCHOOL)
    assert hass.states.get(PLACE).state == "home"
    await _reading(hass, freezer, SCHOOL)
    state = hass.states.get(PLACE)
    assert state.state == "school" and state.attributes["name"] == "School"
    assert [e.data for e in moved] == [{"person": "person.sam", "from": "home", "to": "school"}]

    # Anywhere else is away; a favorite place by its key
    await _reading(hass, freezer, ELSEWHERE)
    await _reading(hass, freezer, ELSEWHERE)
    assert hass.states.get(PLACE).state == "away"
    await _reading(hass, freezer, PRACTICE)
    await _reading(hass, freezer, PRACTICE)
    state = hass.states.get(PLACE)
    assert state.state == "practice" and state.attributes["name"] == "Practice"
    assert moved[-1].data == {"person": "person.sam", "from": "away", "to": "practice"}

    # When it changed and how good each reading was stay out of the recorder
    assert {"since", "accuracy", "fresh", "as_of", "source"} <= PersonPlace._unrecorded_attributes


async def test_one_odd_reading_between_two_good_ones_doesn_t_move_them(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator, freezer
) -> None:
    await _sam_at(hass, hass_client_no_auth, freezer, HOME)
    moved = async_capture_events(hass, "hearth_place")
    await _reading(hass, freezer, ELSEWHERE)
    await _reading(hass, freezer, HOME)
    await _reading(hass, freezer, ELSEWHERE)
    assert hass.states.get(PLACE).state == "home"
    assert moved == []


async def test_a_stale_reading_falls_back_to_the_person_and_a_change_counts_after_dwelling(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator, freezer
) -> None:
    await _sam_at(hass, hass_client_no_auth, freezer, SCHOOL)
    assert hass.states.get(PLACE).state == "school"

    # Family Link's last location is 25 minutes old: the person entity (home) speaks; a change from school needs
    # two readings or three minutes
    await _reading(hass, freezer, SCHOOL, age=timedelta(minutes=25))
    state = hass.states.get(PLACE)
    assert state.attributes["source"] == "person"
    assert state.state == "school"
    freezer.tick(timedelta(minutes=3))
    await _update(hass)
    state = hass.states.get(PLACE)
    assert state.state == "home" and state.attributes["source"] == "person" and state.attributes["fresh"] is True

    # A person in a place's zone (by its name)
    hass.states.async_set("person.sam", "Practice", {"friendly_name": "Sam"})
    await hass.async_block_till_done()
    assert hass.states.get(PLACE).state == "home"
    freezer.tick(timedelta(minutes=3))
    await _update(hass)
    assert hass.states.get(PLACE).state == "practice"


async def test_a_reading_rougher_than_the_zone_is_ignored(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator, freezer
) -> None:
    await _sam_at(hass, hass_client_no_auth, freezer, HOME)
    hass.states.async_set("person.sam", "not_home", {"friendly_name": "Sam"})
    # 500 m around the school's 150 m zone: it says nothing about the school, so the person entity speaks
    await _reading(hass, freezer, SCHOOL, accuracy=500)
    await _reading(hass, freezer, SCHOOL, accuracy=500)
    state = hass.states.get(PLACE)
    assert state.attributes["source"] == "person"
    assert state.state != "school"


async def test_stale_or_nothing_is_unknown_and_no_source_is_no_location(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator, freezer
) -> None:
    await _sam_at(hass, hass_client_no_auth, freezer, HOME)
    hass.states.async_set("person.sam", "unavailable")
    await _reading(hass, freezer, HOME, age=timedelta(minutes=30))
    state = hass.states.get(PLACE)
    assert state.state == "unknown"
    assert state.attributes["name"] == "Unknown"
    assert state.attributes["fresh"] is False and state.attributes["source"] == "family_link"

    # A router's tracker is never read, even when picked
    hass.states.async_set(
        TRACKER, "home", {"child_id": CHILD, "source_type": "router", "latitude": HOME[0], "longitude": HOME[1]}
    )
    await hass.async_block_till_done()
    state = hass.states.get(PLACE)
    assert state.state == "unknown" and state.attributes["name"] == "No location"


async def test_no_tracker_and_no_person_state_is_no_location(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator
) -> None:
    await _household_with_sam(hass, hass_client_no_auth)
    _zones(hass)
    hass.states.async_set("person.sam", "unknown", {"friendly_name": "Sam"})
    await _places(hass)
    state = hass.states.get(PLACE)
    assert state.state == "unknown" and state.attributes["name"] == "No location"
    assert state.attributes["source"] is None


# Ends on a place


async def _allow_all(hass: HomeAssistant, ends_on: dict, until: str = "21:00") -> dict:
    answer = await hass.services.async_call(
        DOMAIN,
        "allow",
        {"people": ["person.sam"], "group": "all", "until": until, "ends_on": ends_on},
        blocking=True,
        return_response=True,
    )
    await hass.async_block_till_done()
    return answer


async def test_arriving_home_ends_an_allow_and_takes_back_family_link_s_bonus(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator, freezer
) -> None:
    added = async_mock_service(hass, "familylink", "add_time_bonus")
    reset = async_mock_service(hass, "familylink", "reset_bonus")
    await _sam_at(hass, hass_client_no_auth, freezer, SCHOOL)
    _phone(hass)
    _remaining(hass, 10)
    told: list[tuple] = []
    _household(hass).hub.asks.tell = lambda *args: told.append(args)

    answer = await _allow_all(hass, {"arrive": "home"})
    assert answer["ends_on"] == {"arrive": "home"}
    assert len(added) == 1

    # Shown with the allow: on the sensor, in explain, in the summary; the kid's own device says only "you"
    sensor = hass.states.get("sensor.hearth_sam_screen_time_today")
    [allow] = sensor.attributes["exceptions"]["allows"]
    assert allow["ends_on"] == {
        "arrive": "home",
        "place": "Home",
        "text": "ends when Sam gets home, or 21:00",
    }
    why = await hass.services.async_call(
        DOMAIN, "explain", {"person": "person.sam", "group": "all"}, blocking=True, return_response=True
    )
    assert why["exceptions"][0]["ends_on"]["text"] == "ends when Sam gets home, or 21:00"
    document = _household(hass)._person_document("person.sam")
    assert [a["text"] for a in document["allow_ends"]] == ["ends when you get home"]
    assert "place" not in document and "school" not in str(document["allow_ends"])

    # One reading at home isn't enough; the second ends it, and Hearth's bonus goes back
    _phone(hass, bonus=50)
    await _reading(hass, freezer, HOME)
    assert _household(hass).allows.of("person.sam")
    await _reading(hass, freezer, HOME)
    assert _household(hass).allows.of("person.sam") == []
    assert [c.data for c in reset] == [{"entity_id": "switch.sam_s_phone"}]
    assert told == [("Sam: Home", "Sam got home; their allow (screen time) ended.", "hearth_place_person.sam")]


async def test_leaving_needs_a_confirmed_place_and_unknown_never_ends_it(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator, freezer
) -> None:
    async_mock_service(hass, "familylink", "add_time_bonus")
    await _sam_at(hass, hass_client_no_auth, freezer, SCHOOL)
    hass.states.async_set("person.sam", "unknown", {"friendly_name": "Sam"})
    await _allow_all(hass, {"leave": "school"}, until="13:00")

    # Stale: unknown, nothing ends
    freezer.tick(timedelta(minutes=25))
    await _update(hass)
    assert hass.states.get(PLACE).state == "unknown"
    assert _household(hass).allows.of("person.sam")
    # Back at school after it: still nothing (school to school isn't leaving)
    await _reading(hass, freezer, SCHOOL)
    await _reading(hass, freezer, SCHOOL)
    assert _household(hass).allows.of("person.sam")
    # Its time still caps it
    freezer.move_to(dt_util.now().replace(hour=13, minute=1))
    await _update(hass)
    assert _household(hass).allows.of("person.sam") == []


async def test_leaving_ends_an_allow(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator, freezer
) -> None:
    async_mock_service(hass, "familylink", "add_time_bonus")
    await _sam_at(hass, hass_client_no_auth, freezer, SCHOOL)
    await _allow_all(hass, {"leave": "school"})
    await _reading(hass, freezer, ELSEWHERE)
    await _reading(hass, freezer, ELSEWHERE)
    assert _household(hass).allows.of("person.sam") == []


async def test_a_pause_ends_for_each_person_as_they_leave(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator, freezer
) -> None:
    await _sam_at(hass, hass_client_no_auth, freezer, HOME)
    hass.states.async_set("person.alex", "home", {"friendly_name": "Alex"})
    hass.states.async_set("binary_sensor.alex_bedtime", "off")
    await _option(hass, "locks", {"person": "person.alex", "entities": ["binary_sensor.alex_bedtime"]})
    _household(hass).hub.asks.tell = lambda *args: None

    # No minutes or until: the end of the day is the cap
    await hass.services.async_call(
        DOMAIN,
        "pause",
        {"people": ["person.sam", "person.alex"], "reason": "Chores", "ends_on": {"leave": "home"}},
        blocking=True,
    )
    await hass.async_block_till_done()
    paused = pause_of(hass, "person.sam")
    assert paused is not None and dt_util.parse_datetime(paused["until"]).hour == 0
    explained = await hass.services.async_call(
        DOMAIN, "explain", {"person": "person.sam", "group": "all"}, blocking=True, return_response=True
    )
    assert explained["blocked_by"][0]["ends_on"]["text"].startswith("ends when Sam leaves home, or ")

    await _reading(hass, freezer, ELSEWHERE)
    await _reading(hass, freezer, ELSEWHERE)
    assert pause_of(hass, "person.sam") is None
    assert pause_of(hass, "person.alex") is not None  # Alex hasn't left


async def test_a_place_must_be_one_of_theirs(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator, freezer
) -> None:
    await _sam_at(hass, hass_client_no_auth, freezer, HOME)
    hass.states.async_set("person.alex", "home", {"friendly_name": "Alex"})
    hass.states.async_set("binary_sensor.alex_bedtime", "off")
    await _option(hass, "locks", {"person": "person.alex", "entities": ["binary_sensor.alex_bedtime"]})
    with pytest.raises(ServiceValidationError, match="Alex has no school place"):
        await hass.services.async_call(
            DOMAIN,
            "allow",
            {"people": ["person.sam", "person.alex"], "group": "all", "ends_on": {"arrive": "school"}},
            blocking=True,
            return_response=True,
        )
    with pytest.raises(ServiceValidationError, match="No place gym"):
        await _allow_all(hass, {"arrive": "gym"})
    # A favorite's key works
    assert (await _allow_all(hass, {"arrive": "Practice"}))["ends_on"] == {"arrive": "practice"}
    # An adult's place isn't followed: no Place sensor, and nothing of theirs ends on one
    entry = hass.config_entries.async_entries(DOMAIN)[0]
    hass.config_entries.async_update_entry(entry, options={**entry.options, "roles": {"person.alex": "adult"}})
    await hass.async_block_till_done()
    # (its old entity stays in the registry, unavailable, like any entity an integration stops providing)
    assert hass.states.get("sensor.hearth_alex_place").state == "unavailable"
    with pytest.raises(ServiceValidationError, match="Alex is an adult"):
        await hass.services.async_call(
            DOMAIN, "pause", {"people": ["person.alex"], "ends_on": {"arrive": "home"}}, blocking=True
        )


async def test_arriving_at_school_puts_school_time_back(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator, freezer
) -> None:
    off = async_mock_service(hass, "switch", "turn_off")
    on = async_mock_service(hass, "switch", "turn_on")
    async_mock_service(hass, "familylink", "set_school_time")
    monday = date(2026, 11, 9)
    household = await _set_up(hass, hass_client_no_auth, freezer, _clock(monday, 9), YEAR, {})
    _zones(hass)
    await _reading(hass, freezer, HOME)
    await _places(hass)
    household = _household(hass)
    household.hub.asks.tell = lambda *args: None

    await hass.services.async_call(
        DOMAIN,
        "school_time_off",
        {"people": ["person.sam"], "reason": "Late start", "ends_on": {"arrive": "school"}},
        blocking=True,
    )
    await _tick(hass, household, freezer, _clock(monday, 9, 1))
    assert [c.data for c in off] == [{"entity_id": SWITCH}]
    hass.states.async_set(SWITCH, "off")
    [view] = household.exceptions_of("person.sam")["school_time_off"]
    assert view["ends_on"]["text"] == "ends when Sam gets to school"

    freezer.move_to(_clock(monday, 9, 30))
    await _reading(hass, freezer, SCHOOL)
    await _reading(hass, freezer, SCHOOL)
    await hass.async_block_till_done()
    assert [c.data for c in on] == [{"entity_id": SWITCH}]

    # Only today's
    with pytest.raises(ServiceValidationError):
        await hass.services.async_call(
            DOMAIN,
            "school_time_off",
            {"people": ["person.sam"], "date": "2026-11-10", "ends_on": {"arrive": "school"}},
            blocking=True,
        )


# Configure > Places, and the views


async def test_configure_places(hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator) -> None:
    await _household_with_sam(hass, hass_client_no_auth)
    _zones(hass)
    await _places(hass)
    entry = hass.config_entries.async_entries(DOMAIN)[0]
    assert entry.options["places"] == {
        "school": {"person.sam": "zone.school"},
        "trackers": {},
        "favorites": [{"key": "practice", "zone": "zone.practice", "name": "Practice"}],
    }
    # The same name again gets a key of its own; a reserved name isn't taken as is
    await _option(hass, "places", {"favorite_zone": "zone.practice", "favorite_name": "Practice"})
    await _option(hass, "places", {"favorite_zone": "zone.home", "favorite_name": "Home"})
    keys = [f["key"] for f in hass.config_entries.async_entries(DOMAIN)[0].options["places"]["favorites"]]
    assert keys == ["practice", "practice_2", "home_place"]
    # Removing, and a kid chosen again with no school clears theirs
    await _option(hass, "places", {"person": "person.sam", "remove_favorites": ["practice_2", "home_place"]})
    places = hass.config_entries.async_entries(DOMAIN)[0].options["places"]
    assert places["school"] == {} and [f["key"] for f in places["favorites"]] == ["practice"]

    # A name with no zone
    result = await hass.config_entries.options.async_init(entry.entry_id)
    result = await hass.config_entries.options.async_configure(result["flow_id"], {"next_step_id": "places"})
    result = await hass.config_entries.options.async_configure(result["flow_id"], {"favorite_name": "Beach house"})
    assert result["errors"] == {"favorite_zone": "no_favorite_zone"}


async def test_the_summary_and_the_page_show_the_place_by_name(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator, hass_ws_client
) -> None:
    # No frozen clock: the WebSocket's sign-in needs the real one
    await _sam_at(hass, hass_client_no_auth, None, PRACTICE)
    ws = await hass_ws_client(hass)
    await ws.send_json({"id": 1, "type": "hearth/household"})
    answer = await ws.receive_json()
    assert answer["success"], answer
    sam = next(p for p in answer["result"]["people"] if p["id"] == "person.sam")
    assert sam["place"] == {"name": "Practice", "fresh": True}

    await ws.send_json({"id": 2, "type": "hearth/config"})
    config = (await ws.receive_json())["result"]
    assert config["places_now"]["person.sam"]["name"] == "Practice"
    assert config["places_now"]["person.sam"]["source"] == "family_link"
    assert {z["entity_id"] for z in config["zones"]} >= {"zone.home", "zone.school", "zone.practice"}

    # The page writes the places as the Configure menu does, checked
    value = {"school": {"person.sam": "zone.school"}, "favorites": [{"key": "home", "zone": "zone.practice", "name": "X"}]}
    await ws.send_json({"id": 3, "type": "hearth/config/set", "key": "places", "value": value})
    assert not (await ws.receive_json())["success"]
    value["favorites"] = [{"key": "beach_house", "zone": "zone.practice", "name": "Beach house"}]
    await ws.send_json({"id": 4, "type": "hearth/config/set", "key": "places", "value": value})
    assert (await ws.receive_json())["success"]
    await hass.async_block_till_done()
    assert hass.config_entries.async_entries(DOMAIN)[0].options["places"]["favorites"][0]["key"] == "beach_house"


async def test_the_family_link_tracker_is_found_by_its_child_without_a_child_id(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator, freezer
) -> None:
    """Family Link's tracker carries no child_id attribute; its unique id names the child."""
    from homeassistant.helpers import entity_registry as er
    from pytest_homeassistant_custom_component.common import MockConfigEntry

    await _sam_with_family_link(hass, hass_client_no_auth)
    entry = MockConfigEntry(domain="familylink")
    entry.add_to_hass(hass)
    tracker = er.async_get(hass).async_get_or_create(
        "device_tracker", "familylink", f"familylink_{CHILD}_location", suggested_object_id="sam_fl", config_entry=entry
    )
    assert _household(hass).places.tracker_of("person.sam") == tracker.entity_id
