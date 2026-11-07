"""Places: where each kid is, as a place name, from Home Assistant zones (docs/home-assistant-integration.md, Places).

Hearth keeps no coordinates and shows only place names. The places are Home Assistant zones the household picked in
Configure > Places: Home (always zone.home), each kid's School (a zone per kid) and any number of favorite places (a
zone and the name to show). A place's key is `home`, `school` or the favorite's slug; anywhere else is `away`, and no
fresh reading is `unknown`.

Where a kid is comes from, in order:

- their Family Link location tracker (device_tracker.<kid>_family_link: the one whose child is the child of their
  Family Link enforcer, or the tracker picked for them in Configure > Places) while its `location_timestamp` is at most
  FRESH_FOR old. Its latitude and longitude are set against the places' zones (their radius); a reading whose
  `gps_accuracy` is worse than the radius of a zone it could be in says nothing (it's ignored).
- else their person entity's state (home, not_home or a zone's name), as of when it changed.

A router's or Wi-Fi tracker is never read: only those two.

A change needs READINGS consecutive readings that agree, or DWELL of them agreeing, before it counts (a reading at a
zone's edge mustn't flip it). Going back to the place last confirmed counts at once. When a confirmed place changes to
another (unknown in between doesn't count as a place), the event `hearth_place` {person, from, to} fires and the kid's
exceptions that end on it end (hearth.allow, hearth.pause and hearth.school_time_off with `ends_on`).
"""

from __future__ import annotations

from dataclasses import dataclass, field
from datetime import datetime, timedelta
import re
from typing import TYPE_CHECKING, Any

from homeassistant.const import STATE_HOME, STATE_NOT_HOME, STATE_UNAVAILABLE, STATE_UNKNOWN
from homeassistant.core import HomeAssistant, callback
from homeassistant.helpers import entity_registry as er
from homeassistant.helpers.dispatcher import async_dispatcher_send
from homeassistant.util import dt as dt_util
from homeassistant.util.location import distance

from .const import CONF_ROLES

if TYPE_CHECKING:
    from .household import Household

CONF_PLACES = "places"
# Configure > Places: {"school": {person: zone}, "trackers": {person: device_tracker}, "favorites": [{key, zone, name}]}
SCHOOLS = "school"
TRACKERS = "trackers"
FAVORITES = "favorites"

HOME = "home"
SCHOOL = "school"
AWAY = "away"
UNKNOWN = "unknown"
RESERVED = (HOME, SCHOOL, AWAY, UNKNOWN)
HOME_ZONE = "zone.home"

SOURCE_FAMILY_LINK = "family_link"
SOURCE_PERSON = "person"

ARRIVE = "arrive"
LEAVE = "leave"
# The kind hearth.explain's vocabulary keeps for a place rule (none yet: a place only ends an exception so far)
KIND_PLACE = "place"

EVENT_PLACE = "hearth_place"
SIGNAL_PLACES = "hearth_places"

FRESH_FOR = timedelta(minutes=20)
DWELL = timedelta(minutes=3)
READINGS = 2
MAX_FAVORITES = 20
MAX_NAME = 40
FL_DOMAIN = "familylink"


def place_slug(name: str) -> str:
    return re.sub(r"[^a-z0-9]+", "_", name.lower()).strip("_")[:32]


def favorite_key(name: str, taken: set[str]) -> str:
    """A favorite's key from its name: never one of the reserved ones, and not one already taken."""
    base = place_slug(name) or "place"
    if base in RESERVED:
        base = f"{base}_place"
    key, n = base, 2
    while key in taken:
        key, n = f"{base}_{n}", n + 1
    return key


@dataclass(frozen=True)
class Favorite:
    key: str
    zone: str
    name: str


@dataclass
class PlacesConfig:
    schools: dict[str, str] = field(default_factory=dict)
    trackers: dict[str, str] = field(default_factory=dict)
    favorites: list[Favorite] = field(default_factory=list)

    @classmethod
    def from_options(cls, options: dict[str, Any]) -> PlacesConfig:
        raw = options.get(CONF_PLACES) or {}
        favorites = []
        for item in raw.get(FAVORITES) or []:
            if isinstance(item, dict) and item.get("key") and item.get("zone"):
                favorites.append(Favorite(str(item["key"]), str(item["zone"]), str(item.get("name") or item["key"])))
        return cls(dict(raw.get(SCHOOLS) or {}), dict(raw.get(TRACKERS) or {}), favorites)

    def places_of(self, person: str) -> dict[str, tuple[str, str]]:
        """The person's places: key -> (zone, name)."""
        found = {HOME: (HOME_ZONE, "Home")}
        if school := self.schools.get(person):
            found[SCHOOL] = (school, "School")
        for favorite in self.favorites:
            found.setdefault(favorite.key, (favorite.zone, favorite.name))
        return found


@dataclass
class Reading:
    place: str  # a place key, or AWAY
    source: str
    as_of: datetime
    accuracy: float | None = None
    # Two readings are the same one when their stamp is (a tracker's timestamp, a person's last change)
    stamp: str = ""


@dataclass
class Where:
    """A person's place as Hearth has it: the confirmed place, and the change it's waiting to confirm."""

    place: str = UNKNOWN
    # The last confirmed place that wasn't unknown (a change is from this)
    known: str | None = None
    since: datetime | None = None
    source: str | None = None
    accuracy: float | None = None
    as_of: datetime | None = None
    fresh: bool = False
    located: bool = False
    candidate: str | None = None
    candidate_at: datetime | None = None
    candidate_as_of: datetime | None = None
    count: int = 0
    stamp: str | None = None


def _number(value: Any) -> float | None:
    try:
        number = float(value)
    except (TypeError, ValueError):
        return None
    return number if number == number else None  # not NaN


def _timestamp(value: Any) -> datetime | None:
    """A tracker's location time: a datetime, an ISO string, or seconds (or milliseconds) since 1970."""
    if isinstance(value, datetime):
        return value if value.tzinfo else value.replace(tzinfo=dt_util.UTC)
    if isinstance(value, (int, float)) or (isinstance(value, str) and re.fullmatch(r"\d+(\.\d+)?", value.strip())):
        seconds = float(value)
        if seconds > 1e11:
            seconds /= 1000
        try:
            return dt_util.utc_from_timestamp(seconds)
        except (OverflowError, OSError, ValueError):
            return None
    if isinstance(value, str):
        parsed = dt_util.parse_datetime(value)
        if parsed is not None and parsed.tzinfo is None:
            parsed = parsed.replace(tzinfo=dt_util.UTC)
        return parsed
    return None


def describe(ends_on: dict[str, str], place_name: str, who: str | None) -> str:
    """"Sam gets home", "you leave school", "Sam gets to Beach house"."""
    you = who is None
    name = place_name if place_name not in ("Home", "School") else place_name.lower()
    subject = "you" if you else who
    if ARRIVE in ends_on:
        verb = "get" if you else "gets"
        return f"{subject} {verb} home" if ends_on[ARRIVE] == HOME else f"{subject} {verb} to {name}"
    verb = "leave" if you else "leaves"
    return f"{subject} {verb} {name}"


def happened(ends_on: dict[str, str], person_name: str, place_name: str) -> str:
    """"Sam got home", "Sam left school"."""
    name = place_name if place_name not in ("Home", "School") else place_name.lower()
    if ARRIVE in ends_on:
        return f"{person_name} got home" if ends_on[ARRIVE] == HOME else f"{person_name} got to {name}"
    return f"{person_name} left {name}"


def matches(ends_on: dict[str, str] | None, came_from: str | None, went_to: str) -> bool:
    """Arrive X: the confirmed place became X. Leave X: a confirmed X became something else (known, not unknown)."""
    if not ends_on:
        return False
    if ARRIVE in ends_on:
        return went_to == ends_on[ARRIVE] and came_from != went_to
    if LEAVE in ends_on:
        return came_from == ends_on[LEAVE] and went_to != ends_on[LEAVE]
    return False


class Places:
    """Each kid's place, debounced, and what a confirmed change ends."""

    def __init__(self, hass: HomeAssistant, household: Household) -> None:
        self.hass = hass
        self.household = household
        self.where: dict[str, Where] = {}

    @property
    def config(self) -> PlacesConfig:
        return PlacesConfig.from_options(self.household.options)

    def people(self) -> list[str]:
        """Whose place Hearth shows: the household's people but its adults."""
        roles = self.household.options.get(CONF_ROLES, {})
        return [p for p in self.household.people() if roles.get(p) != "adult"]

    def place_keys(self, person: str) -> list[str]:
        return list(self.config.places_of(person))

    def place_name(self, person: str, key: str) -> str:
        if key == AWAY:
            return "Away"
        if key == UNKNOWN:
            return "Unknown"
        return self.config.places_of(person).get(key, (None, key))[1]

    # Where the readings come from

    def tracker_of(self, person: str) -> str | None:
        """The person's Family Link location tracker: picked in Configure > Places, else their Family Link child's."""
        if picked := self.config.trackers.get(person):
            return picked
        child = self.household.family_link_child(person)
        if child is None:
            return None
        for state in self.hass.states.async_all("device_tracker"):
            if str(state.attributes.get("child_id")) == child:
                return state.entity_id
        registry = er.async_get(self.hass)
        for entry in registry.entities.values():
            if (
                entry.domain == "device_tracker"
                and entry.platform == FL_DOMAIN
                and entry.unique_id.startswith(f"{FL_DOMAIN}_{child}")
            ):
                return entry.entity_id
        return None

    def watched_entities(self) -> list[str]:
        """Entities whose change can move someone: their trackers, their person entities and the places' zones."""
        config = self.config
        found: set[str] = {HOME_ZONE, *config.schools.values(), *(f.zone for f in config.favorites)}
        for person in self.people():
            found.add(person)
            if tracker := self.tracker_of(person):
                found.add(tracker)
        return sorted(found)

    def _zone(self, entity_id: str) -> tuple[float, float, float] | None:
        state = self.hass.states.get(entity_id)
        if state is None:
            return None
        lat, lon = _number(state.attributes.get("latitude")), _number(state.attributes.get("longitude"))
        radius = _number(state.attributes.get("radius"))
        if lat is None or lon is None or radius is None:
            return None
        return lat, lon, radius

    def _from_tracker(self, person: str, tracker: str, now: datetime) -> tuple[Reading | None, bool]:
        """The tracker's reading, and whether the tracker is there at all. None: stale, or not good enough."""
        state = self.hass.states.get(tracker)
        if state is not None and state.attributes.get("source_type") not in (None, "gps"):
            # A router's, Wi-Fi or Bluetooth tracker: never read
            return None, False
        if state is None or state.state in (STATE_UNAVAILABLE, STATE_UNKNOWN):
            return None, state is not None
        at = _timestamp(state.attributes.get("location_timestamp"))
        lat, lon = _number(state.attributes.get("latitude")), _number(state.attributes.get("longitude"))
        if at is None or lat is None or lon is None or now - at > FRESH_FOR or at - now > FRESH_FOR:
            return None, True
        accuracy = _number(state.attributes.get("gps_accuracy"))
        inside: list[tuple[float, str]] = []
        unsure = False
        for key, (zone_id, _name) in self.config.places_of(person).items():
            zone = self._zone(zone_id)
            if zone is None:
                continue
            away = distance(lat, lon, zone[0], zone[1])
            if away is None:
                continue
            if accuracy is not None and accuracy > zone[2]:
                # Too rough to say for this zone: unsure if it could be in it
                if away - accuracy <= zone[2]:
                    unsure = True
                continue
            if away <= zone[2]:
                inside.append((zone[2], key))
        if inside:
            place = min(inside)[1]  # the smallest zone it's in: the most particular place
        elif unsure:
            return None, True
        else:
            place = AWAY
        return Reading(place, SOURCE_FAMILY_LINK, at, accuracy, f"fl:{at.isoformat()}"), True

    def _from_person(self, person: str) -> Reading | None:
        state = self.hass.states.get(person)
        if state is None or state.state in (STATE_UNAVAILABLE, STATE_UNKNOWN, ""):
            return None
        if state.state == STATE_HOME:
            place = HOME
        elif state.state == STATE_NOT_HOME:
            place = AWAY
        else:
            # A zone's name: a place's zone, else somewhere else
            place = AWAY
            for key, (zone_id, _name) in self.config.places_of(person).items():
                zone = self.hass.states.get(zone_id)
                if zone is not None and (zone.name == state.state or zone_id.split(".", 1)[1] == place_slug(state.state)):
                    place = key
                    break
        accuracy = _number(state.attributes.get("gps_accuracy"))
        return Reading(place, SOURCE_PERSON, state.last_changed, accuracy, f"person:{state.last_changed.isoformat()}")

    def reading(self, person: str, now: datetime) -> tuple[Reading | None, bool, str | None]:
        """The person's reading now, whether they can be located at all, and the source that's stale (if one is)."""
        tracker = self.tracker_of(person)
        has_tracker = False
        if tracker is not None:
            found, has_tracker = self._from_tracker(person, tracker, now)
            if found is not None:
                return found, True, None
        from_person = self._from_person(person)
        if from_person is not None:
            return from_person, True, None
        # No Family Link tracker and no usable person state: no location at all
        return None, has_tracker, SOURCE_FAMILY_LINK if has_tracker else None

    # The minute's work, and every change

    @callback
    def update(self, now: datetime | None = None) -> None:
        now = now or dt_util.utcnow()
        changed = False
        moves: list[tuple[str, str | None, str]] = []
        people = self.people()
        for person in list(self.where):
            if person not in people:
                del self.where[person]
                changed = True
        for person in people:
            where = self.where.setdefault(person, Where())
            before = (where.place, where.source, where.fresh, where.as_of, where.accuracy, where.located)
            move = self._step(where, *self.reading(person, now), now)
            if move is not None:
                moves.append((person, *move))
            if before != (where.place, where.source, where.fresh, where.as_of, where.accuracy, where.located):
                changed = True
        for person, came_from, went_to in moves:
            self.hass.bus.async_fire(EVENT_PLACE, {"person": person, "from": came_from, "to": went_to})
        if changed:
            async_dispatcher_send(self.hass, SIGNAL_PLACES)
        for person, came_from, went_to in moves:
            self.household.place_changed(person, came_from, went_to)

    @staticmethod
    def _step(
        where: Where, reading: Reading | None, located: bool, stale: str | None, now: datetime
    ) -> tuple[str | None, str] | None:
        """One look at a person's reading; a confirmed change (from, to) when there is one."""
        where.located = located
        if reading is None:
            # Stale or nothing: unknown at once (unknown never ends anything), and a change waiting starts over
            where.place, where.fresh, where.source, where.accuracy = UNKNOWN, False, stale, None
            where.candidate = None
            return None
        where.source, where.accuracy, where.as_of, where.fresh = reading.source, reading.accuracy, reading.as_of, True
        if where.known is None or reading.place == where.known:
            # The first reading, or back where they were: no change to confirm
            if where.place != reading.place:
                where.place = reading.place
                if where.known is None or where.since is None:
                    where.since = reading.as_of
            where.known = reading.place
            where.candidate = None
            return None
        if where.candidate != reading.place:
            where.candidate, where.candidate_at, where.candidate_as_of = reading.place, now, reading.as_of
            where.count, where.stamp = 1, reading.stamp
        elif reading.stamp != where.stamp:
            where.count += 1
            where.stamp = reading.stamp
        if where.count < READINGS and now - (where.candidate_at or now) < DWELL:
            return None
        came_from = where.known
        where.place = where.known = reading.place
        where.since = where.candidate_as_of or reading.as_of
        where.candidate = None
        return came_from, reading.place

    # Views

    def view(self, person: str) -> dict[str, Any]:
        """The place sensor: state and attributes."""
        where = self.where.get(person) or Where()
        if not where.located:
            name = "No location"
        else:
            name = self.place_name(person, where.place)
        return {
            "state": where.place,
            "name": name,
            "since": dt_util.as_local(where.since).isoformat() if where.since and where.place != UNKNOWN else None,
            "source": where.source,
            "accuracy": round(where.accuracy) if where.accuracy is not None else None,
            "fresh": where.fresh,
            "as_of": dt_util.as_local(where.as_of).isoformat() if where.as_of else None,
        }

    def summary(self, person: str) -> dict[str, Any] | None:
        """What an adult's app shows: the place's name and whether it's fresh. No coordinates, ever."""
        if person not in self.people():
            return None
        view = self.view(person)
        return {"name": view["name"], "fresh": view["fresh"]}

    def page(self, person: str) -> dict[str, Any]:
        """Hearth's page: the place's key and name, freshness and source."""
        view = self.view(person)
        return {k: view[k] for k in ("state", "name", "fresh", "source", "since")}

    # Ends on

    def check(self, people: list[str], ends_on: dict[str, str]) -> dict[str, str]:
        """An ends_on for these people, cleaned; a ValueError says what's wrong."""
        (how, key), = ends_on.items()
        key = key.strip().lower()
        followed = self.people()
        for person in people:
            if person not in followed:
                raise ValueError(f"{self.household.person_name(person)} is an adult: Hearth doesn't follow their place")
            if key not in self.config.places_of(person):
                name = self.household.person_name(person)
                if key == SCHOOL:
                    raise ValueError(f"{name} has no school place (Configure > Places)")
                raise ValueError(f"No place {key} (home, school, or a favorite place's key)")
        return {how: key}

    def ends_on_view(
        self, person: str, ends_on: dict[str, str] | None, until: datetime | None = None, you: bool = False
    ) -> dict[str, Any] | None:
        """{arrive|leave, place, text: "ends when Sam gets home, or 21:00"}."""
        if not ends_on:
            return None
        key = next(iter(ends_on.values()))
        place = self.place_name(person, key)
        text = f"ends when {describe(ends_on, place, None if you else self.household.person_name(person))}"
        if until is not None:
            text += f", or {dt_util.as_local(until).strftime('%H:%M')}"
        return {**ends_on, "place": place, "text": text}
