"""Who is playing a shared Switch, and the Switch's "caught" hold (docs/home-assistant-integration.md, A shared Switch).

Nintendo's limits are the console's, never a player's: one kid out of time can only be held by holding the whole
Switch. So on a Switch the family shares, Hearth holds it once that kid is caught playing, and keeps holding it until
the kid has time again (extra time, a new budget, a parent's grant in the Nintendo app, or midnight). An adult's
"Let someone else play" lifts the hold for a while (a turn) so a brother or sister can play; if the held kid shows up
playing during it, the Switch is held again at once and the adults are told.

Who is playing comes from what the installed Nintendo integration has:

- Home Assistant's own (core) has each player's minutes today (sensor "<nickname> used screen time", unique id
  <switch id>_<player id>_player_playing_time). Nintendo's servers take them from the console every 5 to 10 minutes,
  so a player whose minutes grew in the last WINDOW minutes is playing. Minutes that haven't been read lately (STALE),
  or aren't there, say nothing: unknown, never "not playing". "Not playing" is only said after the minutes have been
  watched, fresh, for a whole window without growing.
- A patched copy adds a binary sensor per player (<switch id>_<player id>_playing). It is the same minutes growing
  (on for 10 minutes after each growth, with an off and on again within milliseconds at each reading), so where the
  player's minutes sensor is there, the minutes alone are read: the flicker never reads as new play. Friend presence
  (or a playing sensor without minutes) is read as itself: "on" is playing; "off" counts only once it has stayed off
  for OFF_CONFIRM and is fresh; unavailable, unknown or stale is unknown.
- Someone else since: a player whose minutes grew, but after whom another player's minutes or the console's own
  minutes grew at a later reading (not the same one: SAME_UPLOAD) without theirs, isn't the one playing now. Nintendo
  takes every player's minutes in one upload, so the console moving on without them means they stopped and someone
  else (an adult, a brother or sister, a guest, or no user at all) started.

Any source saying "playing" wins; else any trusted "not playing"; else unknown. Nothing here ever lets a hold go:
a Switch is let go only when its kid has time again or an adult gives a turn (enforce.py). Unknown only means Hearth
doesn't catch anyone with it.

Play nobody's player counts (the console's minutes growing past all its players' together: software that needs no
user, or no user picked) can't be put on anyone. While a kid on the Switch would be held if caught, UNATTRIBUTED
minutes of it are told to the adults (ConsoleWatch) with a button to hold the Switch now; Hearth never holds it by
itself for play it can't put on the kid (it may be an adult's).
"""

from __future__ import annotations

from dataclasses import dataclass
from datetime import datetime, timedelta
import re
from typing import TYPE_CHECKING, Any

from homeassistant.core import HomeAssistant, State
from homeassistant.helpers import device_registry as dr
from homeassistant.helpers import entity_registry as er
from homeassistant.util import dt as dt_util

if TYPE_CHECKING:
    from .enforce import Enforcer

NINTENDO_DOMAIN = "nintendo_parental_controls"
PLAYER_PLAYED = "player_playing_time"
PLAYING = "playing"
# A player whose minutes grew this recently is playing (Nintendo takes them every 5 to 10 minutes; 15 keeps a game
# that's still on from flickering off between two uploads)
WINDOW = timedelta(minutes=15)
WINDOW_MIN, WINDOW_MAX = 5, 60
# A reading older than this says nothing (the integration reads Nintendo every minute)
STALE = timedelta(minutes=10)
# A playing sensor's "off" is believed once it has been off this long (two readings of the integration's)
OFF_CONFIRM = timedelta(minutes=2)
# After a hold starts, Nintendo's next upload may still carry play from before it: the first growth this soon after
# the hold isn't taken as playing again
UPLOAD_GRACE = timedelta(minutes=12)
# Let someone else play: how long by default, and at most
DEFAULT_TURN_MINUTES = 60
MAX_TURN_MINUTES = 240
# Two growths this close are one Nintendo upload (the integration reads every player's minutes and the console's in
# one poll): neither is "someone else since"
SAME_UPLOAD = timedelta(minutes=2)
# The console's own minutes (its "used screen time")
CONSOLE_PLAYED = "playing_time"
# Play on no player's minutes past this many minutes is told to the adults, at most once per UNATTRIBUTED_REPEAT.
# Nintendo counts the console in steps of 5 to 10 minutes and the players in their own, so less is rounding
UNATTRIBUTED_MIN = 15
UNATTRIBUTED_REPEAT = timedelta(minutes=60)
_UNKNOWN = ("unknown", "unavailable", "")


# The Nintendo integration's entities


def _twin(hass: HomeAssistant, entity_id: str, domain: str, suffix_from: str, suffix_to: str) -> str | None:
    """The same player's other entity: <switch>_<player>_<suffix_from> -> <switch>_<player>_<suffix_to>."""
    registry = er.async_get(hass)
    entry = registry.async_get(entity_id)
    if entry is None or entry.platform != NINTENDO_DOMAIN or not entry.unique_id.endswith(f"_{suffix_from}"):
        return None
    stem = entry.unique_id.removesuffix(f"_{suffix_from}")
    # The Switch's own Playing sensor (<switch>_playing) is nobody's
    device = dr.async_get(hass).async_get(entry.device_id) if entry.device_id else None
    if device is not None and any(d == NINTENDO_DOMAIN and v == stem for d, v in device.identifiers):
        return None
    return registry.async_get_entity_id(domain, NINTENDO_DOMAIN, f"{stem}_{suffix_to}")


def minutes_of_binary(hass: HomeAssistant, binary: str) -> str | None:
    """The player's minutes sensor (core's) of a patched integration's player playing sensor."""
    return _twin(hass, binary, "sensor", PLAYING, PLAYER_PLAYED)


def binary_of_minutes(hass: HomeAssistant, minutes: str) -> str | None:
    """The patched integration's playing sensor of a player's minutes sensor, when it's installed."""
    return _twin(hass, minutes, "binary_sensor", PLAYER_PLAYED, PLAYING)


def own_signal(hass: HomeAssistant, binaries: list[str]) -> list[str]:
    """The playing sensors that say more than their player's minutes: friend presence, or a patched copy's sensor
    whose minutes sensor isn't there (missing, or without a state). A patched copy's sensor beside its minutes is the
    same growth, read from the minutes."""
    found = []
    for binary in binaries:
        twin = minutes_of_binary(hass, binary)
        if twin is None or hass.states.get(twin) is None:
            found.append(binary)
    return found


def console_entities(hass: HomeAssistant, switch_entity: str) -> tuple[list[str], str | None]:
    """Every player's minutes sensor on the Switch [switch_entity] is on (adults' and guests' too), and the console's
    own minutes sensor."""
    registry = er.async_get(hass)
    entry = registry.async_get(switch_entity)
    if entry is None or entry.device_id is None:
        return [], None
    device = dr.async_get(hass).async_get(entry.device_id)
    nintendo_id = next((v for d, v in device.identifiers if d == NINTENDO_DOMAIN), None) if device else None
    console = (
        registry.async_get_entity_id("sensor", NINTENDO_DOMAIN, f"{nintendo_id}_{CONSOLE_PLAYED}") if nintendo_id else None
    )
    return [p["entity_id"] for p in players(hass, switch_entity)], console


def sources_of(hass: HomeAssistant, enforcer: Enforcer) -> tuple[list[str], list[str]]:
    """(playing sensors, minutes sensors) that say whether the enforcer's person is playing their Switch: what the
    row names, with each player's other entity where the integration has it."""
    binaries = list(dict.fromkeys(enforcer.playing))
    minutes = list(dict.fromkeys(enforcer.player))
    for binary in list(binaries):
        if (found := minutes_of_binary(hass, binary)) and found not in minutes:
            minutes.append(found)
    for sensor in list(minutes):
        if (found := binary_of_minutes(hass, sensor)) and found not in binaries:
            binaries.append(found)
    return binaries, minutes


def nickname(hass: HomeAssistant, entity_id: str) -> str | None:
    """A player's nickname, from its minutes sensor's name ("Alex used screen time")."""
    registry = er.async_get(hass)
    entry = registry.async_get(entity_id)
    state = hass.states.get(entity_id)
    names = [entry.original_name if entry else None, entry.name if entry else None, state.name if state else None]
    for name in names:
        if not name:
            continue
        found = re.sub(r"\s*used screen time\s*$", "", str(name), flags=re.IGNORECASE).strip()
        # The friendly name starts with the Switch's name: its last word is the nickname then
        if state is not None and name == state.name and entry is not None and entry.device_id:
            device = dr.async_get(hass).async_get(entry.device_id)
            for prefix in (device.name_by_user, device.name) if device else ():
                if prefix and found.casefold().startswith(prefix.casefold()):
                    found = found[len(prefix):].strip()
        if found:
            return found
    return None


def players(hass: HomeAssistant, switch_entity: str | None = None) -> list[dict[str, Any]]:
    """The players' minutes sensors, of the Switch [switch_entity] is on (any Switch without one):
    [{entity_id, nickname, device_id, playing (the patched sensor, when there is one)}]."""
    registry = er.async_get(hass)
    device_id = None
    if switch_entity is not None:
        entry = registry.async_get(switch_entity)
        device_id = entry.device_id if entry is not None else None
        if device_id is None:
            return []
    found = []
    for entry in registry.entities.values():
        if entry.platform != NINTENDO_DOMAIN or entry.domain != "sensor" or entry.disabled_by is not None:
            continue
        if not entry.unique_id.endswith(f"_{PLAYER_PLAYED}") or (device_id and entry.device_id != device_id):
            continue
        found.append(
            {
                "entity_id": entry.entity_id,
                "nickname": nickname(hass, entry.entity_id),
                "device_id": entry.device_id,
                "playing": binary_of_minutes(hass, entry.entity_id),
            }
        )
    return sorted(found, key=lambda p: (str(p["nickname"] or "").casefold(), p["entity_id"]))


def _words(text: str) -> set[str]:
    return {w for w in re.split(r"[^\w]+", text.casefold()) if w}


def guess_player(hass: HomeAssistant, switch_entity: str, person_name: str) -> str | None:
    """The player on this Switch whose nickname matches the person's name (their first name, or the whole name),
    when exactly one does."""
    wanted = person_name.strip().casefold()
    first = wanted.split()[0] if wanted else ""
    if not first:
        return None
    matches = [
        p["entity_id"]
        for p in players(hass, switch_entity)
        if p["nickname"] and (p["nickname"].casefold() == wanted or first in _words(p["nickname"]))
    ]
    return matches[0] if len(matches) == 1 else None


# Reading them


def _reported(state: State) -> datetime:
    return getattr(state, "last_reported", None) or state.last_updated


def _fresh(state: State | None, now: datetime) -> bool:
    return state is not None and state.state not in _UNKNOWN and now - _reported(state) <= STALE


def binary_verdict(state: State | None, now: datetime) -> bool | None:
    """A playing sensor: True on, False only after OFF_CONFIRM of off, else unknown (missing, stale, unavailable)."""
    if not _fresh(state, now):
        return None
    if state.state == "on":
        return True
    if state.state == "off" and now - state.last_changed >= OFF_CONFIRM:
        return False
    return None


def _number(state: State | None) -> float | None:
    if state is None:
        return None
    try:
        value = float(state.state)
    except (TypeError, ValueError):
        return None
    return value if value == value and value >= 0 else None


@dataclass
class MinutesTrack:
    """What Hearth has seen of one player's minutes today."""

    value: float | None = None
    day: str | None = None
    # When they last grew (as Home Assistant saw it)
    grew_at: datetime | None = None
    # Watched, fresh, without a gap since
    seen_since: datetime | None = None
    # The last fresh reading (not kept over a restart)
    last_seen: datetime | None = None

    def observe(self, state: State | None, now: datetime) -> None:
        value = _number(state)
        if value is None or not _fresh(state, now):
            # A gap: what isn't seen can't say "not playing" later
            self.seen_since = None
            return
        day = dt_util.as_local(now).date().isoformat()
        # Back after a gap longer than a window (or a restart): growth meanwhile is no sign of play now
        long_gap = self.last_seen is None or now - self.last_seen > WINDOW
        self.last_seen = now
        if self.value is None or self.day != day or value < self.value or (long_gap and value != self.value):
            # A first look, a new day, Nintendo's reset or a long gap: where growth counts from, not growth
            if self.day != day:
                self.grew_at = None
            self.value, self.day = value, day
        elif value > self.value:
            self.value = value
            changed = state.last_changed if state is not None else now
            self.grew_at = max(changed, self.grew_at) if self.grew_at else changed
        if self.seen_since is None:
            self.seen_since = now

    def verdict(self, now: datetime, window: timedelta, others: list[MinutesTrack] = ()) -> bool | None:
        """Playing (their minutes grew within [window] and nobody's since: [others], the console's and its other
        players' minutes), not playing (watched a whole window without growing, or someone else's grew since), or
        unknown."""
        if self.seen_since is None:
            return None
        if self.grew_at is not None and now - self.grew_at <= window:
            if any(
                o.grew_at is not None and o.seen_since is not None and o.grew_at - self.grew_at > SAME_UPLOAD
                for o in others
            ):
                return False
            return True
        if now - self.seen_since >= window:
            return False
        return None

    @property
    def known(self) -> float | None:
        """The minutes, when watched without a gap since they were last read fresh."""
        return self.value if self.seen_since is not None else None

    def to_dict(self) -> dict[str, Any]:
        return {
            "value": self.value,
            "day": self.day,
            "grew_at": self.grew_at.isoformat() if self.grew_at else None,
        }

    @classmethod
    def from_dict(cls, raw: dict[str, Any]) -> MinutesTrack:
        value = raw.get("value")
        return cls(
            float(value) if isinstance(value, (int, float)) else None,
            raw.get("day"),
            dt_util.parse_datetime(raw.get("grew_at") or ""),
            # Not across a restart: it has to be watched again
            None,
        )


def combine(verdicts: list[bool | None]) -> bool | None:
    """Playing when any source says so; not playing when any trusted source says so (and none says playing);
    else unknown."""
    if any(v is True for v in verdicts):
        return True
    if any(v is False for v in verdicts):
        return False
    return None


@dataclass
class SwitchWatch:
    """A Switch enforcer's hold state for today: caught, someone else's turn, or armed since a time."""

    day: str | None = None
    # When the kid was caught playing while out of time (the hold stays until they have time again)
    caught_at: datetime | None = None
    # Catching again needs play after this (after a turn); with it, the minutes then and the grace for the upload
    # that may still carry play from before the hold
    since: datetime | None = None
    baseline: float | None = None
    absorb_until: datetime | None = None
    # Someone else's turn: {started, until, for_person, by}
    turn: dict[str, Any] | None = None

    def to_dict(self) -> dict[str, Any]:
        def iso(value: datetime | None) -> str | None:
            return value.isoformat() if value else None

        turn = None
        if self.turn:
            turn = {**self.turn, "started": iso(self.turn["started"]), "until": iso(self.turn["until"])}
        return {
            "day": self.day,
            "caught_at": iso(self.caught_at),
            "since": iso(self.since),
            "baseline": self.baseline,
            "absorb_until": iso(self.absorb_until),
            "turn": turn,
        }

    @classmethod
    def from_dict(cls, raw: dict[str, Any]) -> SwitchWatch:
        def when(value: Any) -> datetime | None:
            return dt_util.parse_datetime(value) if isinstance(value, str) else None

        turn = raw.get("turn") if isinstance(raw.get("turn"), dict) else None
        if turn is not None:
            started, until = when(turn.get("started")), when(turn.get("until"))
            turn = {**turn, "started": started, "until": until} if started and until else None
        baseline = raw.get("baseline")
        return cls(
            raw.get("day"),
            when(raw.get("caught_at")),
            when(raw.get("since")),
            float(baseline) if isinstance(baseline, (int, float)) else None,
            when(raw.get("absorb_until")),
            turn,
        )

    def arm(self, now: datetime, minutes: float | None, absorb: bool = False) -> None:
        """Not held; held again only for play after [now] (the first upload within UPLOAD_GRACE is forgiven when
        [absorb]: a hold that just started)."""
        self.caught_at = None
        self.since, self.baseline = now, minutes
        self.absorb_until = now + UPLOAD_GRACE if absorb else None

    def played_since(self, minutes: float | None, binaries: list[State | None], now: datetime) -> bool:
        """The kid played after [since]: their minutes grew past the baseline (but the forgiven upload), or a playing
        sensor turned on after it."""
        if self.since is None:
            return False
        for state in binaries:
            if _fresh(state, now) and state.state == "on" and state.last_changed > self.since:
                return True
        if minutes is None:
            return False
        if self.baseline is None:
            self.baseline = minutes
            return False
        if minutes <= self.baseline:
            return False
        if self.absorb_until is not None and now <= self.absorb_until:
            # Play from before the hold, uploaded late: once
            self.baseline, self.absorb_until = minutes, None
            return False
        return True


@dataclass
class ConsoleWatch:
    """Play on a Switch that no player's minutes count, while a kid on it would be held if caught (in memory: after a
    restart it starts again from what it reads then)."""

    day: str | None = None
    console: float | None = None
    players: float | None = None
    told_at: datetime | None = None

    def reset(self) -> None:
        self.console = self.players = None

    def update(self, console: float | None, players: float | None, now: datetime) -> float | None:
        """The minutes to tell the adults about now (None: nothing), from the console's minutes and all its players'
        together, as fresh readings (None when one isn't)."""
        day = dt_util.as_local(now).date().isoformat()
        if console is None or players is None:
            # A gap: what happened in it isn't counted against anyone
            self.reset()
            return None
        if self.day != day:
            self.day, self.told_at = day, None
            self.reset()
        if self.console is None or self.players is None:
            self.console, self.players = console, players
            return None
        unattributed = (console - self.console) - (players - self.players)
        if console < self.console or players < self.players or unattributed < 0:
            # Nintendo's reset, or players counted past the console (two playing together): from here
            self.console, self.players = console, players
            return None
        if unattributed < UNATTRIBUTED_MIN:
            return None
        if self.told_at is not None and now - self.told_at < UNATTRIBUTED_REPEAT:
            return None
        self.told_at = now
        self.console, self.players = console, players
        return unattributed


def window_of(raw: Any) -> timedelta:
    """A row's own window in minutes, within bounds; the default otherwise."""
    if isinstance(raw, (int, float)) and not isinstance(raw, bool):
        return timedelta(minutes=max(WINDOW_MIN, min(WINDOW_MAX, int(raw))))
    return WINDOW
