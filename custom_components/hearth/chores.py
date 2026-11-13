"""Chores earn time (docs/home-assistant-integration.md, Chores): a kid's to-do list, where each item checked off adds
bonus minutes to one of their groups today.

Configure > Chores, per person: a to-do list, the group, and the minutes a chore is worth (15 by default). A chore's
text can say its own worth with a "+N" tag ("Dishes +30"). A checked-off item is added once and then removed from the
list, so it can't count twice; the adults are told (an event, and their phones, as for requests for more time).
"""

from __future__ import annotations

from dataclasses import dataclass
import logging
import re
from typing import TYPE_CHECKING, Any

from homeassistant.core import Event, HomeAssistant

if TYPE_CHECKING:
    from .household import Household

_LOGGER = logging.getLogger(__name__)

CONF_CHORES = "chores"
DEFAULT_MINUTES = 15
MAX_MINUTES = 240
EVENT_CHORE_DONE = "hearth_chore_done"
_TAG = re.compile(r"\+\s*(\d+)")


@dataclass(frozen=True)
class Chores:
    person: str
    todo: str
    group: str
    minutes: int = DEFAULT_MINUTES


def chores_from_options(options: dict[str, Any]) -> list[Chores]:
    found: list[Chores] = []
    for raw in options.get(CONF_CHORES, []):
        if raw.get("person") and raw.get("todo") and raw.get("group"):
            minutes = raw.get("minutes")
            found.append(
                Chores(
                    raw["person"],
                    raw["todo"],
                    raw["group"],
                    int(minutes) if isinstance(minutes, (int, float)) and 0 < minutes <= MAX_MINUTES else DEFAULT_MINUTES,
                )
            )
    return found


def worth(summary: str, default: int) -> int:
    """A chore's minutes: its "+N" tag, else the default."""
    match = _TAG.search(summary or "")
    if match:
        return max(1, min(MAX_MINUTES, int(match[1])))
    return default


class ChoreWatcher:
    def __init__(self, hass: HomeAssistant, household: Household) -> None:
        self.hass = hass
        self.household = household
        self._busy: set[str] = set()

    def lists(self) -> list[str]:
        return sorted({c.todo for c in chores_from_options(self.household.options)})

    async def async_changed(self, event: Event) -> None:
        todo = event.data.get("entity_id")
        for chores in chores_from_options(self.household.options):
            if chores.todo == todo:
                await self.async_collect(chores)

    async def async_collect(self, chores: Chores) -> None:
        """The checked-off items: each adds its minutes once, then goes from the list."""
        if chores.todo in self._busy or self.household.group(chores.group) is None:
            return
        self._busy.add(chores.todo)
        try:
            response = await self.hass.services.async_call(
                "todo",
                "get_items",
                {"status": "completed"},
                target={"entity_id": chores.todo},
                blocking=True,
                return_response=True,
            )
            items = ((response or {}).get(chores.todo) or {}).get("items") or []
            for item in items:
                uid, summary = item.get("uid"), str(item.get("summary") or "")
                if not uid:
                    continue
                # Removed first: if that fails, nothing is added (it would count again next time)
                await self.hass.services.async_call(
                    "todo", "remove_item", {"item": uid}, target={"entity_id": chores.todo}, blocking=True
                )
                minutes = worth(summary, chores.minutes)
                self.household.add_bonus(chores.person, chores.group, minutes)
                self.hass.bus.async_fire(
                    EVENT_CHORE_DONE,
                    {"person": chores.person, "chore": summary, "group": chores.group, "minutes": minutes},
                )
                self._tell(chores, uid, summary, minutes)
        except Exception as err:  # noqa: BLE001 - a list that can't be read is tried with its next change
            _LOGGER.warning("Hearth couldn't collect the chores of %s: %s", chores.todo, err)
        finally:
            self._busy.discard(chores.todo)

    def _tell(self, chores: Chores, uid: str, summary: str, minutes: int) -> None:
        """The adults' phones hear of it, as they hear of requests for more time (phones.py). Tagged by the to-do
        item, so each chore done is a notification of its own."""
        from .attention import ADULTS, Item

        group = self.household.group(chores.group)
        who = self.household.person_name(chores.person)
        self.household.hub.attention.notify(
            Item(
                f"hearth_chore_{uid}",
                f"{summary}: +{minutes} min of {group.name if group else chores.group} today",
                title=f"{who} finished a chore",
                audience=ADULTS,
                about={"person": chores.person, "group": chores.group},
            )
        )
