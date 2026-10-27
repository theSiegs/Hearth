"""Groups and budgets (see docs/home-assistant-integration.md, Limits).

A budget is set on a group of apps and titles; a minute counts toward every group its app is in. Budgets (weekday and
weekend) and today's bonus are kept with Home Assistant's storage helper; the bonus and the "reached" marks start again
each local day.
"""

from __future__ import annotations

from dataclasses import dataclass, field
from datetime import date
import re
from typing import Any

from homeassistant.core import HomeAssistant
from homeassistant.helpers.storage import Store

from .counting import ALL

VIDEO = "video"
GAMES = "games"

# Video apps Android doesn't mark as video, or that TVs and phones commonly have; an adult adds the rest
STARTER_VIDEO_APPS = frozenset(
    {
        "com.thesiegs.hearthtube",
        "com.thesiegs.hearthtube.mobile",
        "com.google.android.youtube",
        "com.google.android.youtube.tv",
        "com.google.android.apps.youtube.kids",
        "com.netflix.ninja",
        "com.netflix.mediaclient",
        "com.disney.disneyplus",
        "com.wbd.stream",
        "com.hulu.livingroomplus",
        "com.hulu.plus",
        "com.amazon.amazonvideo.livingroom",
        "com.amazon.avod.thirdpartyclient",
        "com.cbs.ott",
        "com.cbs.app",
        "com.peacocktv.peacockandroid",
        "com.apple.atve.androidtv.appletv",
        "com.apple.atve.amazon.appletv",
        "com.tubitv",
        "tv.pluto.android",
    }
)

# The two budgets: on school days ("weekday", its stored name from before school days) and on other days ("weekend")
DAY_TYPES = ("weekday", "weekend")
SCHOOL_DAY = "weekday"
OTHER_DAY = "weekend"


@dataclass(frozen=True)
class Group:
    id: str
    name: str
    apps: frozenset[str] = frozenset()
    # Apps whose Android category is this are in it too ("video", "game")
    category: str | None = None
    builtin: bool = False


BUILTIN_GROUPS = (
    Group(ALL, "All screen time", builtin=True),
    Group(VIDEO, "Video", STARTER_VIDEO_APPS, "video", builtin=True),
    Group(GAMES, "Games", frozenset(), "game", builtin=True),
)


def slug(name: str) -> str:
    return re.sub(r"[^a-z0-9]+", "_", name.lower()).strip("_")[:32] or "group"


def groups_from_options(options: dict[str, Any]) -> list[Group]:
    """The built-in groups (with apps an adult added to them) and the adult's own groups."""
    added: dict[str, list[str]] = options.get("group_apps", {})
    groups = [
        Group(g.id, g.name, g.apps | frozenset(added.get(g.id, [])), g.category, True) for g in BUILTIN_GROUPS
    ]
    for custom in options.get("groups", []):
        groups.append(Group(custom["id"], custom["name"], frozenset(custom.get("apps", []))))
    return groups


def groups_of(groups: list[Group], categories: dict[str, str]):
    """The function counting needs: an app's groups, from the lists and its Android category."""

    def of(item: str) -> set[str]:
        found = {ALL}
        category = categories.get(item)
        for group in groups:
            if item in group.apps or (group.category is not None and category == group.category):
                found.add(group.id)
        return found

    return of


def day_type(day: date) -> str:
    return "weekend" if day.weekday() >= 5 else "weekday"


@dataclass
class GroupState:
    counted_min: float
    budget_min: int | None
    bonus_min: int

    @property
    def minutes_left(self) -> int | None:
        if self.budget_min is None:
            return None
        return max(0, int(self.budget_min + self.bonus_min - self.counted_min))


@dataclass
class LimitsData:
    # person -> group -> {"weekday": minutes | None, "weekend": minutes | None}
    budgets: dict[str, dict[str, dict[str, int | None]]] = field(default_factory=dict)
    # Today's: the day they're for, person -> group -> minutes
    day: str | None = None
    bonus: dict[str, dict[str, int]] = field(default_factory=dict)
    reached: dict[str, list[str]] = field(default_factory=dict)


class Limits:
    """The household's budgets and today's bonuses, kept across restarts."""

    def __init__(self, hass: HomeAssistant, entry_id: str) -> None:
        self._store: Store[dict[str, Any]] = Store(hass, 1, f"hearth.limits.{entry_id}")
        self.data = LimitsData()

    async def async_load(self) -> None:
        stored = await self._store.async_load() or {}
        self.data = LimitsData(
            budgets=stored.get("budgets", {}),
            day=stored.get("day"),
            bonus=stored.get("bonus", {}),
            reached=stored.get("reached", {}),
        )

    def _save(self) -> None:
        self._store.async_delay_save(
            lambda: {
                "budgets": self.data.budgets,
                "day": self.data.day,
                "bonus": self.data.bonus,
                "reached": self.data.reached,
            },
            5,
        )

    async def async_flush(self) -> None:
        await self._store.async_save(
            {"budgets": self.data.budgets, "day": self.data.day, "bonus": self.data.bonus, "reached": self.data.reached}
        )

    def new_day(self, today: date) -> bool:
        """Starts today's bonus and marks afresh when the day changed; says whether it did."""
        if self.data.day == today.isoformat():
            return False
        self.data.day = today.isoformat()
        self.data.bonus = {}
        self.data.reached = {}
        self._save()
        return True

    def budget(self, person: str, group: str, kind: str) -> int | None:
        return self.data.budgets.get(person, {}).get(group, {}).get(kind)

    def set_budget(self, person: str, group: str, kind: str, minutes: int | None) -> None:
        self.data.budgets.setdefault(person, {}).setdefault(group, {})[kind] = minutes
        self._save()

    def bonus(self, person: str, group: str) -> int:
        return self.data.bonus.get(person, {}).get(group, 0)

    def set_bonus(self, person: str, group: str, minutes: int) -> None:
        self.data.bonus.setdefault(person, {})[group] = max(0, minutes)
        self._save()

    def mark_reached(self, person: str, group: str) -> bool:
        """Notes that the person's group reached 0 today; False if it was noted already."""
        marks = self.data.reached.setdefault(person, [])
        if group in marks:
            return False
        marks.append(group)
        self._save()
        return True

    def clear_reached(self, person: str, group: str) -> None:
        """A bonus reopened the group: reaching 0 again fires again."""
        marks = self.data.reached.get(person, [])
        if group in marks:
            marks.remove(group)
            self._save()

    def state(self, person: str, group: str, counted_min: float, kind: str) -> GroupState:
        """The group's state today, with the budget for [kind] of day (SCHOOL_DAY or OTHER_DAY)."""
        return GroupState(counted_min, self.budget(person, group, kind), self.bonus(person, group))
