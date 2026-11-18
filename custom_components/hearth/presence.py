"""Presence: who each kid is with, and whether they're out without an adult (docs/home-assistant-integration.md,
Presence).

Places (places.py) says which place a kid is at. Presence adds, per kid, facts every Hearth feature can share:

- `at`: their place key, read from Places unchanged;
- `with`: the household people they are with (adults and kids);
- `with_adult`: with at least one adult;
- `apart_from_adults`: away from home and apart from every located adult.

Each fact has a `value` (yes, no or unknown; a place key for `at`, a list of people for `with`), `since` (when the
confirmed value started), `as_of` (the reading it rests on) and `sure` (whether the readings support it now, or it is
only being kept through an unsure or unknown stretch).

Where the positions come from:

- A kid: their Family Link location tracker only, the one Places picks (Places.tracker_of), by its
  `location_timestamp`. A fix counts for KID_FIX_FOR; past that the kid is unknown.
- An adult (role `adult` on Hearth's page): their person entity's coordinates. Home Assistant gives no fix time for
  them, so a position's age runs from when Hearth first saw it. It counts for ADULT_FIX_FOR; an adult whose person
  is `home` stays located however old the position is (a phone lying still at home reports nothing for hours), and
  one at `home` without coordinates counts as the centre of the home zone with its radius as accuracy. A router's
  or Wi-Fi tracker is never read. An adult who can't be located is left out as long as another adult is; with no
  adult located, or the kid unknown, the facts are unknown.

How the facts are decided (hysteresis and dwell, so a fix at an edge doesn't flip them):

- **With** someone: the kid's latest fix is within NEAR_M plus both accuracies of that person's track around the
  fix's time (the line between their positions just before and after it). Fixes come minutes apart, and in a car an
  adult's latest position is kilometres past the kid's last fix: comparing latest to latest would call them apart.
- **Apart** from an adult: for the whole last DWELL, the kid and the adult were more than FAR_M apart after taking
  off both accuracies (the kid's fix in force at each moment against the adult's track then).
- Between the two is unsure, and unsure changes nothing: a fact keeps its value.
- **Away from home**: every fix of the last DWELL is surely outside the home zone (distance minus accuracy is more
  than its radius), and the kid's confirmed Place isn't `home`.

Unknown is never a change: a fact that goes unknown keeps the value it last confirmed (`known`) and fires nothing. A
confirmed change fires `hearth_presence` {person, fact, value}, with no coordinates and no accuracy, and calls
Household.presence_changed. Nothing is confirmed while the household is settling after a start
(Household._settling).

Privacy: coordinates are kept in memory only (each kid's fixes and each adult's track of the last TRACK_KEEP, gone
on a restart). The store `hearth.presence.<entry>` holds the facts (values, people's ids, times), the standing rules'
state (presence_rules.py) and, per adult, a short salted hash of their last position with when it was first seen: a
restart restores every tracker with a new change time, and a position whose hash matches the stored one keeps its
stored age, so stale can't look fresh. No history is kept, and coordinates are never logged.

The pure part (the functions and Core) takes readings and a clock; Presence reads Home Assistant and keeps the store.
"""

from __future__ import annotations

from dataclasses import dataclass, field
from datetime import datetime, timedelta
import hashlib
import math
import secrets
from typing import TYPE_CHECKING, Any

from homeassistant.const import STATE_HOME, STATE_UNAVAILABLE, STATE_UNKNOWN
from homeassistant.core import HomeAssistant, callback
from homeassistant.helpers.dispatcher import async_dispatcher_send
from homeassistant.helpers.storage import Store
from homeassistant.util import dt as dt_util

from .const import CONF_ROLES, DOMAIN
from .places import AWAY, HOME, HOME_ZONE, SIGNAL_PLACES, UNKNOWN, _number, _timestamp

if TYPE_CHECKING:
    from .household import Household

EVENT_PRESENCE = "hearth_presence"

YES = "yes"
NO = "no"

AT = "at"
WITH = "with"
WITH_ADULT = "with_adult"
APART = "apart_from_adults"
FACTS = (AT, WITH, WITH_ADULT, APART)

# How one person stands to another (relation)
R_WITH = "with"
R_APART = "apart"
R_UNSURE = "unsure"

# Within this many metres (plus both accuracies) of someone's track: with them
NEAR_M = 150
# More than this many metres (after taking off both accuracies) for the whole DWELL: apart
FAR_M = 300
DWELL = timedelta(minutes=5)
# A still phone repeats one Family Link fix for half an hour
KID_FIX_FOR = timedelta(minutes=45)
ADULT_FIX_FOR = timedelta(minutes=90)
# A fix stamped later than now by more than this isn't believed
CLOCK_SLACK = timedelta(minutes=5)
# Two kids' fixes this close in time can be set against each other
KIDS_FIX_GAP = timedelta(minutes=10)
TRACK_KEEP = timedelta(minutes=15)
_EARTH_M = 6371000.0


@dataclass(frozen=True)
class Fix:
    """One position: when it was taken (UTC), where, and how rough (metres). In memory only."""

    at: datetime
    lat: float
    lon: float
    accuracy: float = 0.0


@dataclass(frozen=True)
class AdultNow:
    """An adult's reading: their position (at: when it was first seen) and whether their person is `home`."""

    fix: Fix
    home: bool = False


@dataclass(frozen=True)
class KidNow:
    """A kid's reading: their Family Link fix (None: none usable) and their place as Places has it."""

    fix: Fix | None
    place: str = UNKNOWN
    known_place: str | None = None
    place_since: datetime | None = None
    place_as_of: datetime | None = None
    place_fresh: bool = False


@dataclass
class Fact:
    value: Any = UNKNOWN
    # The last confirmed value that wasn't unknown (a change is from this)
    known: Any = None
    since: datetime | None = None
    as_of: datetime | None = None
    sure: bool = False

    def data(self) -> dict[str, Any]:
        return {
            "value": self.value,
            "known": self.known,
            "since": self.since.isoformat() if self.since else None,
            "as_of": self.as_of.isoformat() if self.as_of else None,
            "sure": self.sure,
        }

    @classmethod
    def from_data(cls, raw: Any, a_list: bool = False) -> Fact:
        if not isinstance(raw, dict):
            return cls()

        def clean(value: Any) -> Any:
            if a_list:
                return sorted(str(v) for v in value) if isinstance(value, list) else None
            return value if isinstance(value, str) else None

        value, known = clean(raw.get("value")), clean(raw.get("known"))
        return cls(
            UNKNOWN if value is None else value,
            known,
            _when(raw.get("since")),
            _when(raw.get("as_of")),
            bool(raw.get("sure")),
        )


def _when(value: Any) -> datetime | None:
    parsed = dt_util.parse_datetime(value) if isinstance(value, str) else None
    return dt_util.as_utc(parsed) if parsed is not None else None


# Conditions (the seam for `ends_on` and for standing rules: presence_rules.py)

W_ARRIVE = "arrive"
W_LEAVE = "leave"
W_AT = "at"
W_WITH = "with"
W_APART = "apart"
ADULT = "adult"
ADULTS = "adults"


@dataclass(frozen=True)
class When:
    """One condition on a person's presence: {arrive: place}, {leave: place}, {at: place}, {with: "adult" | person} or
    {apart: "adults"}. A superset of an exception's `ends_on` (arrive and leave are moments, decided by
    places.matches; the others hold or don't, decided here). The first build uses {apart: "adults"} only."""

    kind: str
    value: str

    @classmethod
    def parse(cls, raw: Any) -> When | None:
        """A condition from its saved form; None when it isn't one (an odd value leaves a rule idle)."""
        if not isinstance(raw, dict) or len(raw) != 1:
            return None
        (kind, value), = raw.items()
        if kind not in (W_ARRIVE, W_LEAVE, W_AT, W_WITH, W_APART) or not isinstance(value, str) or not value.strip():
            return None
        value = value.strip()
        if kind == W_APART and value != ADULTS:
            return None
        return cls(kind, value if kind == W_WITH else value.lower())

    def data(self) -> dict[str, str]:
        return {self.kind: self.value}

    def holds(self, facts: dict[str, Fact]) -> str:
        """yes, no or unknown, from a person's facts, and only on a value the readings support now. Arrive and leave
        are moments, never a state: unknown here."""
        if self.kind == W_APART:
            fact = facts.get(APART)
            return fact.value if fact is not None and fact.sure and fact.value in (YES, NO) else UNKNOWN
        if self.kind == W_AT:
            fact = facts.get(AT)
            if fact is None or not fact.sure or fact.value == UNKNOWN:
                return UNKNOWN
            return YES if fact.value == self.value else NO
        if self.kind == W_WITH:
            if self.value == ADULT:
                fact = facts.get(WITH_ADULT)
                return fact.value if fact is not None and fact.sure and fact.value in (YES, NO) else UNKNOWN
            fact = facts.get(WITH)
            if fact is None or not fact.sure or not isinstance(fact.value, list):
                return UNKNOWN
            return YES if self.value in fact.value else NO
        return UNKNOWN

    def text(self, name: str) -> str:
        """"while Sam is out without an adult"."""
        if self.kind == W_APART:
            return f"while {name} is out without an adult"
        if self.kind == W_WITH:
            return f"while {name} is with an adult" if self.value == ADULT else f"while {name} is with {self.value}"
        if self.kind == W_AT:
            return f"while {name} is at {self.value}"
        return f"when {name} {'gets to' if self.kind == W_ARRIVE else 'leaves'} {self.value}"


# Geometry, on a flat map around the point asked about (good to well under a metre at these distances)


def _flat(lat: float, lon: float, of: Fix) -> tuple[float, float]:
    return (
        math.radians(of.lon - lon) * _EARTH_M * math.cos(math.radians(lat)),
        math.radians(of.lat - lat) * _EARTH_M,
    )


def _to_segment(a: tuple[float, float], b: tuple[float, float]) -> float:
    """The distance from the origin to the segment a-b."""
    dx, dy = b[0] - a[0], b[1] - a[1]
    length = dx * dx + dy * dy
    along = 0.0 if length == 0 else max(0.0, min(1.0, -(a[0] * dx + a[1] * dy) / length))
    return math.hypot(a[0] + along * dx, a[1] + along * dy)


def track_distance(lat: float, lon: float, track: list[Fix]) -> float | None:
    """The metres from a point to a track: the line through its fixes in order (to the fix, when it has one)."""
    if not track:
        return None
    flat = [_flat(lat, lon, fix) for fix in track]
    if len(flat) == 1:
        return math.hypot(*flat[0])
    return min(_to_segment(a, b) for a, b in zip(flat, flat[1:]))


def track_reach(lat: float, lon: float, track: list[Fix]) -> float | None:
    """The metres from a point to the farthest part of a track."""
    return max(math.hypot(*_flat(lat, lon, fix)) for fix in track) if track else None


def position_at(track: list[Fix], when: datetime) -> Fix | None:
    """Where a track was at a time: on the line between the fixes around it, the last fix after it (they stayed);
    None before its first fix."""
    before: Fix | None = None
    for fix in track:
        if fix.at <= when:
            before = fix
            continue
        if before is None:
            return None
        span = (fix.at - before.at).total_seconds()
        part = (when - before.at).total_seconds() / span if span > 0 else 1.0
        return Fix(
            when,
            before.lat + (fix.lat - before.lat) * part,
            before.lon + (fix.lon - before.lon) * part,
            max(before.accuracy, fix.accuracy),
        )
    return before


def path(track: list[Fix], start: datetime, end: datetime) -> list[Fix] | None:
    """The part of a track between two times; None when the track starts later than [start]."""
    first = position_at(track, start)
    if first is None:
        return None
    found = [first, *(fix for fix in track if start < fix.at < end)]
    last = position_at(track, end)
    if last is not None and end > start:
        found.append(last)
    return found


def _in_force(track: list[Fix], start: datetime, end: datetime) -> list[tuple[Fix, datetime, datetime]] | None:
    """A kid's fixes in force between two times, each with the stretch it was the latest for; None when the first
    known fix is later than [start] (where they were before it isn't known)."""
    if not track or track[0].at > start:
        return None
    steps = [fix for fix in track if fix.at <= start][-1:] + [fix for fix in track if start < fix.at <= end]
    return [
        (fix, max(fix.at, start), steps[n + 1].at if n + 1 < len(steps) else end)
        for n, fix in enumerate(steps)
    ]


def relation(kid: list[Fix], other: list[Fix], now: datetime) -> str:
    """How a kid stands to someone with a track (an adult): with, apart or unsure."""
    if not kid or not other:
        return R_UNSURE
    fix = kid[-1]
    # With: near their track around the fix's time...
    before = next((p for p in reversed(other) if p.at <= fix.at), None)
    after = next((p for p in other if p.at > fix.at), None)
    around = [p for p in (before, after) if p is not None]
    gap = track_distance(fix.lat, fix.lon, around) - fix.accuracy - max(p.accuracy for p in around)
    if gap <= NEAR_M:
        if now - fix.at <= DWELL:
            return R_WITH
        # ...and, the fix being an older one, they haven't gone off since
        since = path(other, fix.at, now) or around
        if track_reach(fix.lat, fix.lon, since) - fix.accuracy - max(p.accuracy for p in since) <= FAR_M:
            return R_WITH
    # Apart: far from them at every moment of the last DWELL
    start = now - DWELL
    steps = _in_force(kid, start, now)
    if steps is None:
        return R_UNSURE
    for step, begins, ends in steps:
        there = path(other, begins, ends)
        if there is None:
            return R_UNSURE
        if track_distance(step.lat, step.lon, there) - step.accuracy - max(p.accuracy for p in there) <= FAR_M:
            return R_UNSURE
    return R_APART


def kids_together(one: Fix, other: Fix) -> bool:
    """Two kids' latest fixes put them together: taken close in time, and within NEAR_M plus both accuracies."""
    if abs(one.at - other.at) > KIDS_FIX_GAP:
        return False
    return track_distance(one.lat, one.lon, [other]) - one.accuracy - other.accuracy <= NEAR_M


def outside(fix: Fix, zone: tuple[float, float, float]) -> bool:
    """The fix is surely outside the zone (lat, lon, radius): its distance minus its accuracy is more than the radius."""
    return track_distance(zone[0], zone[1], [fix]) - fix.accuracy > zone[2]


def _keep(track: list[Fix], now: datetime) -> list[Fix]:
    """The fixes of the last TRACK_KEEP, and the one in force when that started."""
    start = now - TRACK_KEEP
    return [fix for fix in track if fix.at <= start][-1:] + [fix for fix in track if fix.at > start]


class Core:
    """The facts, from readings and a clock: no Home Assistant here. Tracks are in memory only."""

    def __init__(self, tracks: dict[str, dict[str, list[Fix]]] | None = None) -> None:
        # {"kids": {person: [Fix]}, "adults": {person: [Fix]}}: handed in so a reload of the entry keeps them
        self.tracks = tracks if tracks is not None else {}
        self.tracks.setdefault("kids", {})
        self.tracks.setdefault("adults", {})
        self.facts: dict[str, dict[str, Fact]] = {}
        # The adults whose person is `home` (they stay located however old their position is)
        self._home: set[str] = set()

    def facts_of(self, person: str) -> dict[str, Fact]:
        return self.facts.setdefault(person, {name: Fact() for name in FACTS})

    def load(self, raw: Any) -> None:
        self.facts = {}
        for person, facts in (raw if isinstance(raw, dict) else {}).items():
            if isinstance(person, str) and isinstance(facts, dict):
                self.facts[person] = {name: Fact.from_data(facts.get(name), name == WITH) for name in FACTS}

    def data(self) -> dict[str, Any]:
        return {person: {name: fact.data() for name, fact in facts.items()} for person, facts in self.facts.items()}

    def located(self, now: datetime) -> dict[str, list[Fix]]:
        """The adults who can be located now, with their tracks."""
        return {
            person: track
            for person, track in self.tracks["adults"].items()
            if track and (person in self._home or now - track[-1].at <= ADULT_FIX_FOR)
        }

    def kid_fix(self, person: str, now: datetime) -> Fix | None:
        """The kid's latest fix while it counts."""
        track = self.tracks["kids"].get(person)
        return track[-1] if track and now - track[-1].at <= KID_FIX_FOR else None

    def _see(self, now: datetime, kids: dict[str, KidNow], adults: dict[str, AdultNow | None]) -> None:
        kid_tracks, adult_tracks = self.tracks["kids"], self.tracks["adults"]
        for person in [p for p in kid_tracks if p not in kids]:
            del kid_tracks[person]
        for person in [p for p in adult_tracks if adults.get(p) is None]:
            del adult_tracks[person]
        self._home = {person for person, seen in adults.items() if seen is not None and seen.home}
        for person, seen in kids.items():
            fix = seen.fix
            if fix is None or fix.at - now > CLOCK_SLACK:
                continue
            if fix.at > now:
                fix = Fix(now, fix.lat, fix.lon, fix.accuracy)
            track = kid_tracks.setdefault(person, [])
            # A fix older than the last one says nothing new
            if not track or fix.at > track[-1].at:
                track.append(fix)
            kid_tracks[person] = _keep(track, now)
        for person, seen in adults.items():
            if seen is None:
                continue
            fix = seen.fix if seen.fix.at <= now else Fix(now, seen.fix.lat, seen.fix.lon, seen.fix.accuracy)
            track = adult_tracks.setdefault(person, [])
            last = track[-1] if track else None
            if last is None or (
                (fix.lat, fix.lon, fix.accuracy) != (last.lat, last.lon, last.accuracy) and fix.at >= last.at
            ):
                track.append(fix)
            adult_tracks[person] = _keep(track, now)

    def _read(
        self, person: str, kid: KidNow, now: datetime, home: tuple[float, float, float] | None
    ) -> dict[str, Any]:
        """What the readings say of the kid's facts now: a value, UNKNOWN, or None for unsure (the fact is kept)."""
        fix = self.kid_fix(person, now)
        if fix is None:
            return {WITH: UNKNOWN, WITH_ADULT: UNKNOWN, APART: UNKNOWN}
        track = self.tracks["kids"][person]
        adults = self.located(now)
        how = {adult: relation(track, other, now) for adult, other in adults.items()}
        together = [adult for adult, found in how.items() if found == R_WITH]
        for other in self.tracks["kids"]:
            theirs = self.kid_fix(other, now) if other != person else None
            if theirs is not None and kids_together(fix, theirs):
                together.append(other)
        if not adults:
            return {WITH: sorted(together), WITH_ADULT: UNKNOWN, APART: UNKNOWN}
        with_adult = any(found == R_WITH for found in how.values())
        all_apart = all(found == R_APART for found in how.values())
        steps = _in_force(track, now - DWELL, now)
        away = (
            home is not None
            and steps is not None
            and all(outside(step, home) for step, _begins, _ends in steps)
            and HOME not in (kid.place, kid.known_place)
        )
        if away and all_apart:
            apart: str | None = YES
        elif with_adult or kid.place == HOME:
            apart = NO
        else:
            apart = None
        return {
            WITH: sorted(together),
            WITH_ADULT: YES if with_adult else NO if all_apart else None,
            APART: apart,
        }

    def step(
        self,
        now: datetime,
        kids: dict[str, KidNow],
        adults: dict[str, AdultNow | None],
        home: tuple[float, float, float] | None,
        settling: bool = False,
    ) -> list[tuple[str, str, Any]]:
        """One look at everyone's readings. The confirmed changes: (person, fact, value). The tracks are kept up while
        [settling], but no fact changes then."""
        self._see(now, kids, adults)
        for person in [p for p in self.facts if p not in kids]:
            del self.facts[person]
        if settling:
            return []
        changes: list[tuple[str, str, Any]] = []
        for person, kid in kids.items():
            facts = self.facts_of(person)
            # The place is Places' own (already debounced there): read as it is
            at = facts[AT]
            came_from = at.known
            at.value, at.since, at.as_of, at.sure = kid.place, kid.place_since, kid.place_as_of, kid.place_fresh
            if kid.known_place is not None:
                at.known = kid.known_place
            if came_from is not None and at.known != came_from:
                changes.append((person, AT, at.known))
            fix = self.kid_fix(person, now)
            for name, found in self._read(person, kid, now, home).items():
                fact = facts[name]
                if found == UNKNOWN:
                    # Unknown is never a change: what was confirmed stays known
                    fact.value, fact.sure = UNKNOWN, False
                    continue
                if found is None:
                    # Unsure: the fact keeps the value it had
                    fact.sure = False
                    continue
                fact.value, fact.sure = found, True
                fact.as_of = fix.at if fix is not None else now
                if found != fact.known:
                    first = fact.known is None
                    fact.known, fact.since = found, now
                    if not first:
                        changes.append((person, name, found))
        return changes


def _tracks(hass: HomeAssistant, entry_id: str) -> dict[str, dict[str, list[Fix]]]:
    """The positions in memory (never saved): they outlive a reload of the entry, not a restart."""
    return hass.data.setdefault(f"{DOMAIN}_presence_tracks", {}).setdefault(entry_id, {})


class Presence:
    """Each kid's facts from Home Assistant's trackers, kept across restarts (the facts, never a position)."""

    def __init__(self, hass: HomeAssistant, household: Household, entry_id: str) -> None:
        self.hass = hass
        self.household = household
        self._store: Store[dict[str, Any]] = Store(hass, 1, f"hearth.presence.{entry_id}")
        self.core = Core(_tracks(hass, entry_id))
        # Per adult: {"hash": of their last position, "at": when it was first seen}
        self.seen: dict[str, dict[str, Any]] = {}
        # The standing rules' state, by rule id then person (presence_rules.py keeps it here: one store)
        self.rules: dict[str, dict[str, dict[str, Any]]] = {}
        self._salt = secrets.token_hex(8)

    async def async_load(self) -> None:
        stored = await self._store.async_load() or {}
        if isinstance(stored.get("salt"), str) and stored["salt"]:
            self._salt = stored["salt"]
        self.core.load(stored.get("facts"))
        for person, seen in (stored.get("adults") or {}).items():
            at = _when(seen.get("at")) if isinstance(seen, dict) else None
            if at is not None and isinstance(seen.get("hash"), str):
                self.seen[person] = {"hash": seen["hash"], "at": at}
        for rule, people in (stored.get("rules") or {}).items():
            if isinstance(people, dict):
                self.rules[rule] = {p: dict(s) for p, s in people.items() if isinstance(s, dict)}

    def _data(self) -> dict[str, Any]:
        return {
            "salt": self._salt,
            "facts": self.core.data(),
            "adults": {p: {"hash": s["hash"], "at": s["at"].isoformat()} for p, s in self.seen.items()},
            "rules": self.rules,
        }

    @callback
    def save(self) -> None:
        self._store.async_delay_save(self._data, 5)

    async def async_flush(self) -> None:
        await self._store.async_save(self._data())

    # Who

    def kids(self) -> list[str]:
        return self.household.places.people()

    def adults(self) -> list[str]:
        roles = self.household.options.get(CONF_ROLES, {})
        return sorted(p for p, role in roles.items() if role == "adult" and isinstance(p, str))

    def watched_entities(self) -> list[str]:
        """The adults' person entities (the kids' trackers and the zones are Places' to watch)."""
        return self.adults()

    # Readings

    def _hash(self, person: str, *parts: Any) -> str:
        text = "|".join([self._salt, person, *(repr(part) for part in parts)])
        # Short on purpose: enough to tell a position from the next one, too little to find one from
        return hashlib.sha256(text.encode()).hexdigest()[:8]

    def _adult(self, person: str, now: datetime, home: tuple[float, float, float] | None) -> AdultNow | None:
        state = self.hass.states.get(person)
        if state is None or state.state in (STATE_UNAVAILABLE, STATE_UNKNOWN, ""):
            return None
        at_home = state.state == STATE_HOME
        lat, lon = _number(state.attributes.get("latitude")), _number(state.attributes.get("longitude"))
        if lat is None or lon is None:
            if not at_home or home is None:
                return None
            lat, lon, accuracy = home
            key = self._hash(person, HOME)
        else:
            accuracy = max(0.0, _number(state.attributes.get("gps_accuracy")) or 0.0)
            key = self._hash(person, lat, lon, accuracy)
        seen = self.seen.get(person)
        if seen is None or seen["hash"] != key:
            # A new position: as old as the person's last change. One seen before (a restart restored it) keeps the
            # age it had
            at = min(now, dt_util.as_utc(state.last_updated))
            seen = self.seen[person] = {"hash": key, "at": max(at, seen["at"]) if seen else at}
            self.save()
        return AdultNow(Fix(seen["at"], lat, lon, accuracy), at_home)

    def _kid(self, person: str, now: datetime) -> KidNow:
        where = self.household.places.where.get(person)
        fix = None
        tracker = self.household.places.tracker_of(person)
        state = self.hass.states.get(tracker) if tracker else None
        # A router's, Wi-Fi or Bluetooth tracker is never read
        if (
            state is not None
            and state.state not in (STATE_UNAVAILABLE, STATE_UNKNOWN)
            and state.attributes.get("source_type") in (None, "gps")
        ):
            at = _timestamp(state.attributes.get("location_timestamp"))
            lat, lon = _number(state.attributes.get("latitude")), _number(state.attributes.get("longitude"))
            if at is not None and lat is not None and lon is not None:
                accuracy = max(0.0, _number(state.attributes.get("gps_accuracy")) or 0.0)
                fix = Fix(dt_util.as_utc(at), lat, lon, accuracy)
        if where is None:
            return KidNow(fix)
        return KidNow(fix, where.place, where.known, where.since, where.as_of, where.fresh)

    # The minute's work, and every change

    @callback
    def update(self, now: datetime | None = None) -> None:
        """After Places.update: each minute, and whenever a tracker or an adult's person changes."""
        now = dt_util.as_utc(now) if now is not None else dt_util.utcnow()
        home = self.household.places._zone(HOME_ZONE)
        kids = {person: self._kid(person, now) for person in self.kids()}
        adults = {person: self._adult(person, now, home) for person in self.adults()}
        for person in [p for p in self.seen if p not in adults]:
            del self.seen[person]
        before = self.core.data()
        changes = self.core.step(now, kids, adults, home, self.household._settling(now))
        if self.core.data() != before:
            self.save()
            async_dispatcher_send(self.hass, SIGNAL_PLACES)
        for person, fact, value in changes:
            self.hass.bus.async_fire(EVENT_PRESENCE, {"person": person, "fact": fact, "value": value})
        for person, fact, value in changes:
            self.household.presence_changed(person, fact, value)
        self.household.presence_checked(now)

    # Views

    def fact(self, person: str, name: str) -> Fact:
        return self.core.facts.get(person, {}).get(name) or Fact()

    def view(self, person: str) -> dict[str, Any]:
        """The place sensor's extra attributes: who they're with (people's ids) and whether they're apart from the
        adults. Never a position."""
        together = self.fact(person, WITH)
        apart = self.fact(person, APART)
        return {
            WITH: list(together.value) if isinstance(together.value, list) else None,
            APART: None if apart.value == UNKNOWN else apart.value == YES,
        }

    def page(self, person: str) -> dict[str, Any] | None:
        """What an adult's page shows of a kid: their place's name, who they're with (names) and, when they're out
        without an adult, since when. Never a position."""
        if person not in self.kids():
            return None
        at, together, apart = self.fact(person, AT), self.fact(person, WITH), self.fact(person, APART)
        people = together.value if isinstance(together.value, list) else []
        adults = set(self.adults())
        return {
            "at": at.value if at.value != UNKNOWN else None,
            "place": self.household.places.place_name(person, at.value),
            "away": at.value not in (HOME, UNKNOWN),
            "with": [self.household.person_name(p) for p in people],
            "with_adult": any(p in adults for p in people),
            "apart": apart.value == YES,
            "apart_since": dt_util.as_local(apart.since).isoformat() if apart.value == YES and apart.since else None,
            "fresh": bool(at.sure),
        }


__all__ = [
    "ADULT_FIX_FOR", "APART", "AT", "AWAY", "AdultNow", "Core", "DWELL", "EVENT_PRESENCE", "FACTS", "FAR_M", "Fact",
    "Fix", "KID_FIX_FOR", "KidNow", "NEAR_M", "NO", "Presence", "WITH", "WITH_ADULT", "When", "YES", "track_distance",
]
