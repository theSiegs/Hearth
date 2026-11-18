"""Presence (presence.py): who a kid is with and whether they're out without an adult, from the kid's Family Link fix
and the adults' tracks; how sure and how fresh each fact is; hysteresis and dwell; unknown never a change; and never a
coordinate anywhere Hearth writes."""

from datetime import UTC, datetime, timedelta
import json
import logging
import math

from homeassistant.core import HomeAssistant
from homeassistant.util import dt as dt_util
from pytest_homeassistant_custom_component.common import async_capture_events
from pytest_homeassistant_custom_component.typing import ClientSessionGenerator

from custom_components.hearth.const import DOMAIN
from custom_components.hearth.places import AWAY, HOME, UNKNOWN
from custom_components.hearth.presence import (
    APART,
    WITH,
    WITH_ADULT,
    YES,
    NO,
    AdultNow,
    Core,
    Fix,
    KidNow,
    When,
    track_distance,
)
from test_messaging import CHROME, DIALER, GAME, LATE, MESSAGES, _out_of_time, settled  # noqa: F401 - the fixture
from test_places import TRACKER, _places, _zones

SAM = "person.sam"
ALEX = "person.alex"
ROBIN = "person.robin"
T0 = datetime(2026, 11, 17, 17, 0, tzinfo=UTC)
HOME_AT = (40.0, -75.0)
HOME_ZONE = (40.0, -75.0, 100.0)
_M_PER_DEG = 111195.0


def north(metres: float, east: float = 0.0) -> tuple[float, float]:
    """A point [metres] north (and [east] east) of home."""
    return (
        HOME_AT[0] + metres / _M_PER_DEG,
        HOME_AT[1] + east / (_M_PER_DEG * math.cos(math.radians(HOME_AT[0]))),
    )


# Out: about 2.6 km from home, with digits found nowhere else (the privacy checks look for them)
OUT = (40.0234567, -75.0198765)
# A favorite place far from both
FAR = (40.0567891, -75.0456789)


def _kid(at: datetime, metres: float, accuracy: float = 10, place: str = AWAY) -> KidNow:
    return KidNow(Fix(at, *north(metres), accuracy), place, place, at, at, True)


def _adult(at: datetime, metres: float, accuracy: float = 10, home: bool = False) -> AdultNow:
    return AdultNow(Fix(at, *north(metres), accuracy), home)


def _minute(m: float) -> datetime:
    return T0 + timedelta(minutes=m)


# The pure part


def test_track_distance_follows_the_line_between_fixes() -> None:
    track = [Fix(T0, *north(0)), Fix(_minute(1), *north(1000))]
    # Beside the line's middle: the distance to the line, not to either end
    assert abs(track_distance(*north(500, 100), track) - 100) < 1
    assert abs(track_distance(*north(1500), track) - 500) < 1
    assert track_distance(*north(0), []) is None


def test_apart_after_five_minutes_away_from_both_adults_not_at_four() -> None:
    core = Core({})
    adults = {ALEX: _adult(T0, 0, home=True), ROBIN: _adult(T0, 0, home=True)}
    for m in range(11):
        core.step(_minute(m), {SAM: _kid(_minute(m), 0, place=HOME)}, adults, HOME_ZONE)
    assert core.facts[SAM][APART].known == NO
    # Out from minute 11, 2 km from both
    seen = []
    for m in range(11, 18):
        seen += core.step(_minute(m), {SAM: _kid(_minute(m), 2000)}, adults, HOME_ZONE)
        apart = core.facts[SAM][APART]
        if m < 16:
            assert apart.known == NO, m
        else:
            assert apart.known == YES and apart.sure, m
    assert (SAM, APART, YES) in seen and seen.count((SAM, APART, YES)) == 1
    assert core.facts[SAM][WITH_ADULT].known == NO


def test_in_a_car_together_never_apart_and_with_the_adult() -> None:
    """The kid's fix every 3 minutes, the adult's every 50 s, at 54 km/h: the kid's latest fix is kilometres behind
    the adult's latest position, but on the adult's track at its own time."""
    core = Core({})
    leave = _minute(5)
    speed = 15.0  # metres a second

    def where(t: datetime) -> float:
        return max(0.0, (t - leave).total_seconds() * speed)

    kid_fix: KidNow | None = None
    t = T0
    while t <= leave + timedelta(minutes=20):
        # The kid's fix is taken every 3 minutes and comes in as it's taken
        taken = T0 + timedelta(minutes=3 * ((t - T0) // timedelta(minutes=3)))
        place = HOME if where(taken) < 100 else AWAY
        if kid_fix is None or kid_fix.fix.at != taken:
            kid_fix = KidNow(Fix(taken, *north(where(taken)), 10), place, place, taken, taken, True)
        core.step(t, {SAM: kid_fix}, {ALEX: _adult(t, where(t), home=where(t) < 100)}, HOME_ZONE)
        assert core.facts[SAM][APART].known != YES, t
        t += timedelta(seconds=50)
    assert core.facts[SAM][WITH_ADULT].known == YES
    assert core.facts[SAM][WITH].known == [ALEX]


def test_a_drop_off_is_apart_five_minutes_after_the_adult_passes_300_m() -> None:
    core = Core({})
    for m in range(10):
        core.step(_minute(m), {SAM: _kid(_minute(m), 2000)}, {ALEX: _adult(_minute(m), 2000)}, HOME_ZONE)
    assert core.facts[SAM][WITH_ADULT].known == YES
    # Dropped off at minute 10: the kid's fix stays as it is, the adult drives home at 200 m a minute (past 300 m plus
    # both accuracies at 11.6)
    stays = _kid(_minute(10), 2000)
    for m in range(11, 19):
        core.step(_minute(m), {SAM: stays}, {ALEX: _adult(_minute(m), 2000 - 200 * (m - 10))}, HOME_ZONE)
        apart = core.facts[SAM][APART]
        if m <= 16:
            assert apart.known != YES, m
        else:
            assert apart.known == YES, m


def test_200_m_apart_with_100_m_accuracy_is_not_apart() -> None:
    core = Core({})
    for m in range(20):
        core.step(_minute(m), {SAM: _kid(_minute(m), 5200, accuracy=100)}, {ALEX: _adult(_minute(m), 5000)}, HOME_ZONE)
        assert core.facts[SAM][APART].known != YES


def test_a_stale_adult_is_left_out_and_with_no_adult_located_it_is_unknown() -> None:
    core = Core({})
    # Alex's position is 2 hours old (not home): left out, though it's right where Sam is. Robin is home
    stale = _adult(T0 - timedelta(hours=2), 2000)
    for m in range(8):
        core.step(_minute(m), {SAM: _kid(_minute(m), 2000)}, {ALEX: stale, ROBIN: _adult(T0, 0, home=True)}, HOME_ZONE)
    assert sorted(core.located(_minute(7))) == [ROBIN]
    assert core.facts[SAM][APART].known == YES
    # Nobody located: unknown, and that changes nothing
    changes = core.step(_minute(8), {SAM: _kid(_minute(8), 2000)}, {ALEX: stale, ROBIN: None}, HOME_ZONE)
    apart = core.facts[SAM][APART]
    assert apart.value == UNKNOWN and not apart.sure and apart.known == YES and changes == []


def test_an_adult_at_home_stays_located_however_old() -> None:
    core = Core({})
    old = _adult(T0 - timedelta(hours=8), 0, home=True)
    core.step(T0, {SAM: _kid(T0, 2000)}, {ALEX: old}, HOME_ZONE)
    assert list(core.located(T0)) == [ALEX]
    # The same position, no longer home: past 90 minutes it doesn't count
    core.step(T0, {SAM: _kid(T0, 2000)}, {ALEX: _adult(T0 - timedelta(hours=8), 0)}, HOME_ZONE)
    assert core.located(T0) == {}


def test_a_kid_fix_older_than_45_minutes_is_unknown_and_changes_nothing() -> None:
    core = Core({})
    adults = {ALEX: _adult(T0, 0, home=True)}
    for m in range(8):
        core.step(_minute(m), {SAM: _kid(_minute(m), 2000)}, adults, HOME_ZONE)
    assert core.facts[SAM][APART].known == YES
    old = _kid(_minute(7), 2000)
    for m in (30, 52, 53, 200):
        changes = core.step(_minute(m), {SAM: old}, adults, HOME_ZONE)
        assert changes == []
    facts = core.facts[SAM]
    assert facts[APART].value == UNKNOWN and facts[APART].known == YES
    assert facts[WITH_ADULT].value == UNKNOWN


def test_a_tablet_at_home_and_a_kid_without_a_tracker_are_never_apart() -> None:
    core = Core({})
    adults = {ALEX: _adult(T0, 3000)}
    tablet = KidNow(Fix(T0 - timedelta(hours=6), *north(0), 10), HOME, HOME, T0, T0, True)
    for m in range(30):
        core.step(_minute(m), {SAM: tablet, "person.jo": KidNow(None)}, adults, HOME_ZONE)
        assert core.facts[SAM][APART].known != YES
        assert core.facts["person.jo"][APART].known is None


def test_nothing_is_confirmed_while_settling() -> None:
    core = Core({})
    adults = {ALEX: _adult(T0, 0, home=True)}
    for m in range(10):
        assert core.step(_minute(m), {SAM: _kid(_minute(m), 2000)}, adults, HOME_ZONE, settling=True) == []
    assert SAM not in core.facts
    # The tracks were kept up meanwhile
    assert len(core.tracks["kids"][SAM]) > 1


def test_when_conditions() -> None:
    assert When.parse({"apart": "adults"}) == When("apart", "adults")
    assert When.parse({"apart": "kids"}) is None and When.parse({"at": ""}) is None and When.parse("x") is None
    core = Core({})
    for m in range(8):
        core.step(_minute(m), {SAM: _kid(_minute(m), 2000)}, {ALEX: _adult(T0, 0, home=True)}, HOME_ZONE)
    assert When("apart", "adults").holds(core.facts[SAM]) == YES
    assert When("with", "adult").holds(core.facts[SAM]) == NO
    assert When("apart", "adults").text("Sam") == "while Sam is out without an adult"


# In Home Assistant


def _household(hass: HomeAssistant):
    return hass.config_entries.async_entries(DOMAIN)[0].runtime_data.household


def set_adult(hass: HomeAssistant, where, person: str = ALEX, accuracy: float = 10) -> None:
    """An adult's person entity: at [where] (home's point counts as home), "home" with no coordinates, or away."""
    if where == "home":
        hass.states.async_set(person, "home", {"friendly_name": person.split(".")[1].title()})
        return
    state = "home" if where == HOME_AT else "not_home"
    hass.states.async_set(
        person, state,
        {"friendly_name": person.split(".")[1].title(), "latitude": where[0], "longitude": where[1], "gps_accuracy": accuracy},
    )


async def sam_out_of_time(hass: HomeAssistant, hass_client_no_auth, freezer, adult=HOME_AT, **options):
    """Sam at home with his daily time used up (Family Link holds his phone whole), Alex an adult at [adult], places
    set up (zone.home and the others of test_places)."""
    freezer.move_to(dt_util.now().replace(hour=12, minute=0, second=0, microsecond=0))
    calls, _ = await _out_of_time(hass, hass_client_no_auth)
    _zones(hass)
    set_adult(hass, adult)
    entry = hass.config_entries.async_entries(DOMAIN)[0]
    hass.config_entries.async_update_entry(
        entry, options={**entry.options, "roles": {**entry.options.get("roles", {}), ALEX: "adult"}, **options}
    )
    await hass.async_block_till_done()
    await fix(hass, freezer, HOME_AT)
    await _places(hass)
    await look(hass)
    return calls


async def fix(hass: HomeAssistant, freezer, where, accuracy: float = 10, source: str = "gps") -> None:
    """A new Family Link fix of Sam's, 30 seconds later."""
    freezer.tick(timedelta(seconds=30))
    hass.states.async_set(
        TRACKER,
        "not_home",
        {
            "child_id": "42",
            "source_type": source,
            "latitude": where[0],
            "longitude": where[1],
            "gps_accuracy": accuracy,
            "location_timestamp": dt_util.as_local(dt_util.utcnow()).replace(tzinfo=None).isoformat(),
        },
    )
    await hass.async_block_till_done()


async def look(hass: HomeAssistant) -> None:
    household = _household(hass)
    household.places.update()
    household.presence.update()
    await hass.async_block_till_done()


async def minutes(hass: HomeAssistant, freezer, count: int, sam=None, alex=None, accuracy: float = 10) -> None:
    """[count] minutes, a look each minute: Sam's fix at [sam] (none: no new fix), Alex at [alex] (none: as is)."""
    for _ in range(count):
        freezer.tick(timedelta(seconds=30))
        if alex is not None:
            set_adult(hass, alex)
        if sam is not None:
            await fix(hass, freezer, sam, accuracy)
        else:
            freezer.tick(timedelta(seconds=30))
        await look(hass)


async def test_an_adult_home_without_coordinates_is_the_home_zone(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator, freezer
) -> None:
    await sam_out_of_time(hass, hass_client_no_auth, freezer, adult="home")
    presence = _household(hass).presence
    # At home with Alex (home's centre): with an adult, not apart
    await minutes(hass, freezer, 3, HOME_AT)
    assert presence.fact(SAM, WITH_ADULT).known == YES and presence.fact(SAM, APART).known == NO
    # Out: apart from the home zone's centre
    await minutes(hass, freezer, 8, OUT)
    assert presence.fact(SAM, APART).known == YES
    assert presence.view(SAM) == {WITH: [], APART: True}


async def test_a_router_tracker_is_never_read(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator, freezer
) -> None:
    await sam_out_of_time(hass, hass_client_no_auth, freezer)
    presence = _household(hass).presence
    for _ in range(8):
        await fix(hass, freezer, OUT, source="router")
        freezer.tick(timedelta(seconds=30))
        await look(hass)
    assert SAM not in presence.core.tracks["kids"] or all(
        f.lat != OUT[0] for f in presence.core.tracks["kids"][SAM]
    )
    assert presence.fact(SAM, APART).known != YES


async def test_no_coordinate_in_the_store_the_event_the_sensor_or_the_log(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator, freezer, caplog
) -> None:
    caplog.set_level(logging.DEBUG, logger="custom_components.hearth")
    events = async_capture_events(hass, "hearth_presence")
    await sam_out_of_time(hass, hass_client_no_auth, freezer)
    set_adult(hass, FAR)
    await minutes(hass, freezer, 9, OUT)
    household = _household(hass)
    assert household.presence.fact(SAM, APART).known == YES
    assert {"person": SAM, "fact": APART, "value": YES} in [e.data for e in events]
    sensor = hass.states.get("sensor.hearth_sam_place")
    assert sensor.attributes[APART] is True and sensor.attributes[WITH] == []
    stored = json.dumps(household.presence._data())
    activity = json.dumps(household.activity.records)
    summary_presence = json.dumps(household.presence.page(SAM))
    for text in (stored, json.dumps([e.data for e in events]), json.dumps(dict(sensor.attributes)), caplog.text,
                 activity, summary_presence):
        for digits in ("0234567", "0198765", "0567891", "0456789"):
            assert digits not in text
    # Nor does a kid's own state document (or a TV's) say anything about where anyone is
    document = json.dumps(household._person_document(SAM))
    for word in ("apart", "with_adult", "latitude", "presence", "0234567"):
        assert word not in document
