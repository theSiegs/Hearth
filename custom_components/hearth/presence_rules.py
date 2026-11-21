"""Standing presence rules (docs/home-assistant-integration.md, Messages when away from adults).

The first and only rule is built in: **Messages when away** (`away_messages`, on by default). While a kid is away from
home and apart from every adult (presence.py's `apart_from_adults`), their text app isn't held by time limits: daily
time and Messaging's own limit. It opens once that fact is confirmed (5 minutes apart, presence.DWELL) and goes back
after BACK_AFTER of continuous time with an adult or at home. Unknown changes nothing: a kid whose location is unknown
keeps what they had (the countdown to going back starts over), and after UNKNOWN_FOR of unknown the rule goes off, so a
phone with location off can't keep Messages open for good. Nothing changes while the household settles after a start.

The rule writes nothing of its own (never an allow): Household.budget_lifted adds its apps while it's on, so only what
it lifted comes back when it ends, and an adult's hearth.allow or hearth.pause made meanwhile is untouched. It lifts
time limits only, never something an adult scheduled or switched on: School time's apps, the weekly schedule, bedtime,
a pause and a block all still hold (Household.open_apps).

The apps: Google Messages, else Samsung Messages, whichever the kid's Family Link lists show installed and not blocked
(Google Messages when the lists aren't known), plus the apps an adult added for the kid (`away_messages_apps`).

The state ({on, since, back_since, unknown_since, closed_at} per kid) is kept in presence.py's store: facts and times,
never a position.
"""

from __future__ import annotations

from datetime import datetime, timedelta
from typing import TYPE_CHECKING, Any

from homeassistant.util import dt as dt_util

from . import family_link as fl
from .places import HOME
from .presence import APART, AT, DWELL, UNKNOWN, WITH_ADULT, YES, When, _when

if TYPE_CHECKING:
    from .household import Household
    from .presence import Presence

RULE_ID = "away_messages"
EXCEPTION_ID = f"rule:{RULE_ID}"
CONF_AWAY_MESSAGES = "away_messages"
CONF_AWAY_MESSAGES_APPS = "away_messages_apps"
GOOGLE_MESSAGES = "com.google.android.apps.messaging"
SAMSUNG_MESSAGES = "com.samsung.android.messaging"
SMS_APPS = (GOOGLE_MESSAGES, SAMSUNG_MESSAGES)
WHILE = When("apart", "adults")
# Back to normal after this long with an adult or at home, without a break
BACK_AFTER = timedelta(minutes=10)
# Off after this long with the kid's location unknown
UNKNOWN_FOR = timedelta(hours=6)
# The minutes an open app counts for in Family Link's backstop (backstop._open_limit)
OPEN_LEFT = 120
MAX_APPS = 10
# Hearth's built-in Messaging category: the apps offered to add
MESSAGING = "messaging"


class AwayMessages:
    """The built-in rule, per kid."""

    def __init__(self, household: Household, presence: Presence) -> None:
        self.household = household
        self.presence = presence

    # Settings

    def enabled(self) -> bool:
        return self.household.options.get(CONF_AWAY_MESSAGES, True) is not False

    def added(self, person: str) -> list[str]:
        """The apps an adult added for the kid (an odd value is ignored)."""
        raw = self.household.options.get(CONF_AWAY_MESSAGES_APPS)
        found = raw.get(person) if isinstance(raw, dict) else None
        if not isinstance(found, list):
            return []
        return [p for p in found if isinstance(p, str) and "." in p][:MAX_APPS]

    def sms_apps(self, person: str) -> set[str]:
        """The kid's text app (the first of SMS_APPS installed and not blocked; Google Messages when that isn't
        known) and the apps added for them."""
        found = set(self.added(person))
        child = self.household.family_link_child(person)
        listed, blocked = fl.app_lists(self.household.hass, child) if child else (set(), None)
        if not listed:
            found.add(GOOGLE_MESSAGES)
            return found
        pick = next((p for p in SMS_APPS if p in listed and p not in (blocked or set())), None)
        if pick is not None:
            found.add(pick)
        return found

    # State

    def _people(self) -> dict[str, dict[str, Any]]:
        return self.presence.rules.setdefault(RULE_ID, {})

    def on(self, person: str) -> bool:
        return bool((self._people().get(person) or {}).get("on"))

    def since(self, person: str) -> datetime | None:
        state = self._people().get(person) or {}
        return _when(state.get("since")) if state.get("on") else None

    def lifted_apps(self, person: str) -> set[str]:
        """The apps the rule lifts time limits for now (none while it's off or switched off)."""
        if not self.enabled() or not self.on(person):
            return set()
        return self.sms_apps(person)

    # The minute's work

    def check(self, now: datetime) -> list[tuple[str, bool]]:
        """After presence.py's facts: each kid's rule on or off. The changes: (person, opened)."""
        people = self._people()
        kids = self.presence.kids()
        for person in [p for p in people if p not in kids]:
            del people[person]
        changes: list[tuple[str, bool]] = []
        enabled = self.enabled()
        for person in kids:
            state = people.setdefault(person, {"on": False})
            before = dict(state)
            if not enabled:
                if state.get("on"):
                    self._close(state, now)
                    changes.append((person, False))
            elif state.get("on"):
                if self._goes_back(person, state, now):
                    self._close(state, now)
                    changes.append((person, False))
            elif self._opens(person, state, now):
                state.update(on=True, since=now.isoformat(), back_since=None, unknown_since=None)
                changes.append((person, True))
            if state != before:
                self.presence.save()
        return changes

    def _opens(self, person: str, state: dict[str, Any], now: datetime) -> bool:
        apart = self.presence.fact(person, APART)
        if not (apart.sure and apart.value == YES):
            return False
        closed = _when(state.get("closed_at"))
        # Never back within a dwell of going back (the facts already make it so: a guard)
        if closed is not None and now - closed < DWELL:
            return False
        return bool(self.sms_apps(person))

    def _goes_back(self, person: str, state: dict[str, Any], now: datetime) -> bool:
        at = self.presence.fact(person, AT)
        with_adult = self.presence.fact(person, WITH_ADULT)
        apart = self.presence.fact(person, APART)
        home = at.sure and at.value == HOME
        back = home or (with_adult.sure and with_adult.value == YES)
        if back:
            start = _when(state.get("back_since"))
            if start is None:
                state["back_since"] = now.isoformat()
                start = now
            state["unknown_since"] = None
            return now - start >= BACK_AFTER
        # Unsure, apart or unknown: the countdown starts over
        state["back_since"] = None
        if apart.value == UNKNOWN:
            start = _when(state.get("unknown_since"))
            if start is None:
                state["unknown_since"] = now.isoformat()
                start = now
            return now - start >= UNKNOWN_FOR
        state["unknown_since"] = None
        return False

    @staticmethod
    def _close(state: dict[str, Any], now: datetime) -> None:
        state.update(on=False, since=None, back_since=None, unknown_since=None, closed_at=now.isoformat())

    # Views

    def choices(self, person: str) -> list[dict[str, str]]:
        """The apps an adult may add for the kid: their installed Messaging apps (as Family Link lists them) and the
        ones already added, by name."""
        found = set(self.added(person))
        child = self.household.family_link_child(person)
        if child:
            membership = self.household.membership()
            listed, _blocked = fl.app_lists(self.household.hass, child)
            found |= {p for p in listed if MESSAGING in membership(p)}
        names = self.household.app_names(found, person)
        return sorted(({"package": p, "name": names.get(p) or p} for p in found), key=lambda a: a["name"].lower())

    def view(self, person: str, app: str | None = None) -> dict[str, Any] | None:
        """The rule as an exception of the person's ({id, apps, since, until: null, while}); None while it lifts
        nothing (or not [app])."""
        apps = self.lifted_apps(person)
        if not apps or (app is not None and app not in apps):
            return None
        since = self.since(person)
        return {
            "id": EXCEPTION_ID,
            "app": app if app is not None else None,
            "apps": sorted(apps),
            "since": dt_util.as_local(since).isoformat() if since else None,
            "until": None,
            "while": {**WHILE.data(), "text": WHILE.text(self.household.person_name(person))},
        }


__all__ = [
    "AwayMessages", "BACK_AFTER", "CONF_AWAY_MESSAGES", "CONF_AWAY_MESSAGES_APPS", "EXCEPTION_ID", "GOOGLE_MESSAGES",
    "OPEN_LEFT", "RULE_ID", "SAMSUNG_MESSAGES", "UNKNOWN_FOR",
]
