"""Suggestions pushed to the adults' phones (docs/home-assistant-integration.md, Suggestions, Pushed to phones).

The household picks, per kid and group (or one device of theirs), which suggestions (glance.suggestions) also go to
the adults' phones, and how much each offers (option suggest_push: [{person, group | device, minutes?}], off for
everything by default, set in the Kids tab of Hearth's page). Once the household changes (debounced), each chosen
suggestion that's there now is pushed once a day (history PUSHED, so a restart doesn't push it again), with its own
buttons: two amounts (hearth.add_bonus) and "not today" (hearth.dismiss_suggestion), run as the adult who pressed one.
When the suggestion goes (more time given, put off, the group no longer out, a new day, the pair no longer chosen),
it comes off every phone. At most MAX_PER_HOUR are pushed an hour (every adult gets each one, so that's per adult);
one past that isn't pushed, and is still in the household summary.

This replaces the older "offer more time" (option offer_more), which made an offered request on the adults' phones
when a chosen group ran out: its pairs become pushed pairs with their amounts when the household loads (migrate), and
a group running out no longer makes an offered request, so the adults get one notification for it, not two.
"""

from __future__ import annotations

from collections.abc import Mapping
from datetime import datetime, timedelta
import logging
from typing import TYPE_CHECKING, Any

from homeassistant.core import CALLBACK_TYPE, HomeAssistant, callback
from homeassistant.helpers.dispatcher import async_dispatcher_connect
from homeassistant.helpers.event import async_call_later
from homeassistant.util import dt as dt_util

from .asks import CONF_OFFER_MORE
from .attention import ADULTS, NOTICE, Action, Item
from .const import SIGNAL_PAIRINGS, SIGNAL_PEOPLE
from .counting import ALL
from .history import PUSHED

if TYPE_CHECKING:
    from .hub import HearthHub

_LOGGER = logging.getLogger(__name__)

# Options: [{"person", "group" | "device", "minutes"?}]: these suggestions also go to the adults' phones; minutes is
# one of asks.AMOUNTS (as a request's), else the suggestion's own amount
CONF_SUGGEST_PUSH = "suggest_push"
# The household is looked at this long after it last changed
DEBOUNCE = timedelta(seconds=10)
# At most this many suggestion pushes an hour (each goes to every adult: per adult)
MAX_PER_HOUR = 6
# An item's key: suggest:<person>:<suggestion key>; its phone tag: hearth_<item key>
KEY_PREFIX = "suggest:"


def item_key(person: str, key: str) -> str:
    return f"{KEY_PREFIX}{person}:{key}"


def _target(raw: Mapping[str, Any]) -> str | None:
    """What a pair is about: its device (a target id) or its group."""
    return raw.get("device") or raw.get("group")


def pairs(options: Mapping[str, Any]) -> list[dict[str, Any]]:
    """The pushed pairs: suggest_push, then an older household's offer_more ones not there yet (until migrated, each
    with its amount, 30 when none was kept). Each once, by person and group or device."""
    found: list[dict[str, Any]] = []
    seen: set[tuple[str, str]] = set()
    legacy = [
        {"person": o.get("person"), "group": o.get("group"), "minutes": int(o.get("minutes") or 30)}
        for o in options.get(CONF_OFFER_MORE) or []
        if isinstance(o, Mapping)
    ]
    for raw in [*(options.get(CONF_SUGGEST_PUSH) or []), *legacy]:
        if not isinstance(raw, Mapping) or not raw.get("person") or not (target := _target(raw)):
            continue
        if (raw["person"], target) in seen:
            continue
        seen.add((raw["person"], target))
        pair: dict[str, Any] = {"person": raw["person"]}
        pair["device" if raw.get("device") else "group"] = target
        if raw.get("minutes"):
            pair["minutes"] = int(raw["minutes"])
        found.append(pair)
    return found


def migrated(options: Mapping[str, Any]) -> dict[str, Any] | None:
    """The options with offer_more's pairs moved into suggest_push (each pair keeps its amount; a pair already there
    keeps its own); None when there's nothing to move."""
    if CONF_OFFER_MORE not in options:
        return None
    moved = {k: v for k, v in options.items() if k != CONF_OFFER_MORE}
    moved[CONF_SUGGEST_PUSH] = pairs(options)
    return moved


def chosen_minutes(options: Mapping[str, Any], person: str) -> dict[str, int]:
    """The amounts the household chose for a person's suggestions, by group or device id (glance's hints)."""
    return {_target(p): p["minutes"] for p in pairs(options) if p["person"] == person and p.get("minutes")}


class SuggestPush:
    """Pushes the chosen suggestions, and takes them off the phones when they go."""

    def __init__(self, hass: HomeAssistant, hub: HearthHub) -> None:
        self.hass = hass
        self.hub = hub
        self._unsubs: list[CALLBACK_TYPE] = []
        self._pending: CALLBACK_TYPE | None = None
        # Item keys pushed or taken back after a restart in this run, by day: one that went and came back the same day
        # isn't taken back again (its notification was cleared)
        self._handled: tuple[Any, set[str]] = (None, set())
        # Past the hourly cap today: not pushed later either
        self._capped: tuple[Any, set[str]] = (None, set())

    def start(self) -> None:
        for signal in (SIGNAL_PEOPLE, SIGNAL_PAIRINGS):
            self._unsubs.append(async_dispatcher_connect(self.hass, signal, self._changed))
        self.schedule()

    @callback
    def stop(self) -> None:
        for unsub in self._unsubs:
            unsub()
        self._unsubs.clear()
        if self._pending is not None:
            self._pending()
            self._pending = None

    @callback
    def _changed(self, *_args: Any) -> None:
        self.schedule()

    @callback
    def schedule(self) -> None:
        """A look in DEBOUNCE, unless one is already due."""
        if self._pending is not None:
            return

        @callback
        def due(_now: datetime) -> None:
            self._pending = None
            self.check()

        self._pending = async_call_later(self.hass, DEBOUNCE, due)

    def _today(self, kept: tuple[Any, set[str]], day) -> set[str]:
        return kept[1] if kept[0] == day else set()

    @callback
    def check(self) -> None:
        """Every chosen suggestion there now is on the phones (once a day); every one that went comes off."""
        attention = self.hub.attention
        options = self.hub.entry.options
        chosen = {(p["person"], _target(p)) for p in pairs(options)}
        shown = [i for i in attention.items() if i.key.startswith(KEY_PREFIX)]
        if not chosen and not shown:
            return
        from .websocket import summary  # the household summary the suggestions come from

        now = dt_util.utcnow()
        day = dt_util.as_local(now).date()
        handled = self._today(self._handled, day)
        capped = self._today(self._capped, day)
        self._handled, self._capped = (day, handled), (day, capped)
        history = self.hub.household.history
        wanted: set[str] = set()
        people = summary(self.hub)["people"] if chosen else []
        for person in people:
            pushed = None
            for suggestion in person.get("suggestions") or []:
                if (person["id"], suggestion.get("device") or suggestion.get("group")) not in chosen:
                    continue
                key = item_key(person["id"], suggestion["key"])
                wanted.add(key)
                if attention.item(key) is not None:
                    continue
                if pushed is None:
                    pushed = history.pushed(person["id"], day)
                item = self._item(person, suggestion)
                if suggestion["key"] in pushed:
                    # Pushed today, before a restart: the phones still show it, so its buttons work again and it can
                    # be taken off; not sent again
                    if key not in handled:
                        attention.adopt(item)
                        handled.add(key)
                    continue
                if key in capped:
                    continue
                hour_ago = (now - timedelta(hours=1)).isoformat()
                if len([e for e in history.of(kinds=(PUSHED,)) if str(e.get("at", "")) >= hour_ago]) >= MAX_PER_HOUR:
                    _LOGGER.debug("Hearth didn't push %s: %s suggestions went out this hour", key, MAX_PER_HOUR)
                    capped.add(key)
                    continue
                attention.notify(item)
                history.log(PUSHED, person["id"], key=suggestion["key"])
                handled.add(key)
        for item in shown:
            if item.key not in wanted:
                attention.clear(item.key)

    def _item(self, person: Mapping[str, Any], suggestion: Mapping[str, Any]) -> Item:
        who = person.get("name") or person["id"]
        minutes = suggestion["minutes"]
        if suggestion.get("device"):
            target = next((t for t in person.get("targets") or [] if t.get("id") == suggestion["device"]), {})
            device = target.get("name") or "a device"
            title = f"{who}'s {device} reached its own limit"
            text = f"Give {minutes} more minutes on it today?"
        else:
            group = suggestion.get("group")
            name = (
                "screen time"
                if group == ALL
                else next((g["name"] for g in person.get("groups") or [] if g["id"] == group), group)
            )
            title = f"{who}'s {name} ran out"
            text = f"Give {minutes} more minutes today?"
        actions = tuple(
            Action(
                a["id"],
                "Not today" if a["service"] == "hearth.dismiss_suggestion" else f"{a['label']} min",
                a["service"],
                dict(a.get("data") or {}),
            )
            for a in suggestion.get("actions") or []
        )
        key = item_key(person["id"], suggestion["key"])
        about = {"person": person["id"]}
        if suggestion.get("group"):
            about["group"] = suggestion["group"]
        if suggestion.get("device"):
            about["device"] = suggestion["device"]
        return Item(
            key,
            text,
            title=title,
            urgency=NOTICE,
            audience=ADULTS,
            actions=actions,
            tag=f"hearth_{key}",
            # About a kid: never on Home Assistant's bell
            bell=False,
            about=about,
        )
