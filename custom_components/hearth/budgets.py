"""A person's budgets as an adult's app reads them (the household summary's `budgets`, docs/home-assistant-integration.md,
Household summary) and as hearth.set_budget answers them (before and after, for an undo).

Every group of the household is listed, with a budget or not (null: no limit), so an app can offer to switch one on.
`school_days` and `other_days` are the two numbers hearth.set_budget sets (Monday's and Saturday's limits in the weekly
schedule). When an adult gave some weekdays limits of their own on the Schedule tab (weekly.py), the row says
`per_weekday` and lists `weekdays` {mon..sun, day_off}: setting the two numbers then writes every day of their kind again.
"""

from __future__ import annotations

from typing import Any

from .limits import OTHER_DAY, SCHOOL_DAY, never_held_group
from .weekly import DAY_OFF_KEY, DAYS

# hearth.set_budget's days, and the kinds each writes
SCHOOL_DAYS = "school_days"
OTHER_DAYS = "other_days"
KIND_OF = {SCHOOL_DAYS: SCHOOL_DAY, OTHER_DAYS: OTHER_DAY}


def _weekdays(household, person: str, group: str) -> dict[str, int | None] | None:
    """{mon..sun, day_off: minutes or None} from the person's weekly schedule; None while an adult never edited it (it
    follows the two budgets then)."""
    week = getattr(household, "week", None)
    if week is None or not week.is_set(person):
        return None
    days = week.schedule_of(person).get("days") or {}
    return {key: ((days.get(key) or {}).get("limits") or {}).get(group) for key in (*DAYS, DAY_OFF_KEY)}


def budget_values(household, person: str, group: str) -> dict[str, Any]:
    """{school_days, other_days (minutes, None: no limit), per_weekday, weekdays (only when per_weekday)}."""
    school = household.limits.budget(person, group, SCHOOL_DAY)
    other = household.limits.budget(person, group, OTHER_DAY)
    out: dict[str, Any] = {SCHOOL_DAYS: school, OTHER_DAYS: other, "per_weekday": False}
    days = _weekdays(household, person, group)
    if days is not None and (
        any(days[k] != school for k in DAYS[:5]) or any(days[k] != other for k in (*DAYS[5:], DAY_OFF_KEY))
    ):
        out["per_weekday"] = True
        out["weekdays"] = days
    return out


def budget_rows(household, person: str) -> list[dict[str, Any]]:
    """Every group of the household, in its order: {group, name, school_days, other_days, per_weekday, weekdays?,
    limitable} (limitable false: a group nothing holds, the Accessibility pool, so a budget would do nothing)."""
    return [
        {
            "group": group.id,
            "name": group.name,
            **budget_values(household, person, group.id),
            "limitable": not never_held_group(group),
        }
        for group in household.groups
    ]


def half_day_budget(household, person: str | None = None) -> str:
    """Which budget a half day uses: "school_days" or "other_days". The household's (Configure > School days), or a
    person's own once their weekly schedule was edited (its half day's limits: a school day's or the Day off's)."""
    week = getattr(household, "week", None)
    if person is not None and week is not None and week.is_set(person):
        limits = (week.schedule_of(person).get("half_day") or {}).get("limits", DAY_OFF_KEY)
        return OTHER_DAYS if limits == DAY_OFF_KEY else SCHOOL_DAYS
    return SCHOOL_DAYS if household.school.config.half_day_budget == SCHOOL_DAYS else OTHER_DAYS
