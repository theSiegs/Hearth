"""The weekly schedule's services and the panel's WebSocket commands (weekly.py; docs/home-assistant-integration.md,
Schedule).

Services: hearth.set_schedule, copy_schedule, change_today, resume_schedule and get_schedule (adults only, as every
Hearth service: auth.py). The panel's Schedule tab: hearth/schedule/get, set, copy, undo, today, resume, mode and
mode/remove (administrators only, as the rest of the panel). Each edit fires hearth_schedule_changed and recomputes at
once, so the devices and the other parental controls follow within the minute.
"""

from __future__ import annotations

from datetime import date, timedelta
from typing import Any

import voluptuous as vol

from homeassistant.components import websocket_api
from homeassistant.core import HomeAssistant, ServiceCall, ServiceResponse, SupportsResponse, callback
from homeassistant.exceptions import ServiceValidationError
from homeassistant.helpers import config_validation as cv
from homeassistant.util import dt as dt_util

from .auth import register_service
from .const import CONF_ROLES, DOMAIN
from .counting import ALL
from .enforce import enforcers_from_options
from .schooldays import DAY_OFF, HALF_DAY, SCHOOL
from .weekly import (
    ALLOWS,
    DAY_KEYS,
    DAY_SETS,
    EVENT_SCHEDULE_CHANGED,
    HALF_LIMITS,
    ScheduleError,
    describe_mode,
    hhmm,
    weekday_key,
)

_PERSON = cv.entity_domain("person")
_DAY = vol.In([*DAY_KEYS, *DAY_SETS])
_CHANGE = vol.Any(
    vol.Schema({vol.Required("at"): vol.Any(cv.string, cv.time), vol.Required("mode"): cv.string}),
    vol.All(vol.ExactSequence([cv.string, cv.string])),
)
_LIMITS = vol.Schema({cv.string: vol.Any(None, vol.All(vol.Coerce(int), vol.Range(min=0, max=1440)))})

SET_SCHEDULE_SCHEMA = vol.Schema(
    {
        vol.Required("people"): vol.All(cv.ensure_list, [_PERSON], vol.Length(min=1)),
        vol.Optional("days"): vol.All(cv.ensure_list, [_DAY]),
        vol.Optional("changes"): [_CHANGE],
        vol.Optional("limits"): _LIMITS,
        vol.Optional("half_day_ends"): vol.Any(cv.string, cv.time),
        vol.Optional("half_day_limits"): vol.In(HALF_LIMITS),
    }
)
COPY_SCHEDULE_SCHEMA = vol.All(
    vol.Schema(
        {
            vol.Required("from"): _PERSON,
            vol.Optional("day"): vol.In([*DAY_KEYS, "half_day"]),
            vol.Exclusive("to_people", "to"): vol.All(cv.ensure_list, [_PERSON], vol.Length(min=1)),
            vol.Exclusive("to_days", "to"): vol.All(cv.ensure_list, [_DAY], vol.Length(min=1)),
            vol.Optional("times", default=True): cv.boolean,
            vol.Optional("limits", default=True): cv.boolean,
        }
    ),
    cv.has_at_least_one_key("to_people", "to_days"),
)
CHANGE_TODAY_SCHEMA = vol.Schema(
    {
        vol.Required("people"): vol.All(cv.ensure_list, [_PERSON], vol.Length(min=1)),
        vol.Exclusive("bedtime", "what"): vol.Any(cv.string, cv.time),
        vol.Exclusive("mode", "what"): cv.string,
        vol.Exclusive("changes", "what"): [_CHANGE],
        vol.Optional("until"): vol.Any(cv.string, cv.time),
        vol.Optional("limits"): _LIMITS,
        vol.Optional("reason"): cv.string,
    }
)
RESUME_SCHEMA = vol.Schema({vol.Required("people"): vol.All(cv.ensure_list, [_PERSON], vol.Length(min=1))})
GET_SCHEDULE_SCHEMA = vol.Schema(
    {
        vol.Required("person"): _PERSON,
        vol.Exclusive("date", "when"): cv.date,
        vol.Exclusive("day", "when"): vol.In([*DAY_KEYS, "half_day"]),
    }
)
# How far ahead the panel's Coming up looks
COMING_UP_DAYS = 21


def _hub(hass: HomeAssistant):
    entries = hass.config_entries.async_loaded_entries(DOMAIN)
    return entries[0].runtime_data if entries else None


def _household(hass: HomeAssistant):
    hub = _hub(hass)
    if hub is None:
        raise ServiceValidationError("Hearth isn't set up")
    return hub.household


def _people(household, given: list[str]) -> list[str]:
    unknown = [p for p in given if p not in household.people()]
    if unknown:
        raise ServiceValidationError(f"Not the household's: {', '.join(unknown)}")
    return list(dict.fromkeys(given))


def _limits(household, given: dict[str, Any] | None) -> dict[str, Any] | None:
    """Limits by group id (a group's name works too)."""
    if given is None:
        return None
    out: dict[str, Any] = {}
    for key, minutes in given.items():
        found = household.group(key) or next((g for g in household.groups if g.name.casefold() == str(key).strip().casefold()), None)
        if found is None:
            raise ServiceValidationError(f"No group {key}")
        out[found.id] = minutes
    return out


def _changes(given: list[Any] | None) -> list[list[str]] | None:
    if given is None:
        return None
    out = []
    for item in given:
        at, mode = (item["at"], item["mode"]) if isinstance(item, dict) else item
        out.append([at.strftime("%H:%M") if hasattr(at, "strftime") else at, mode])
    return out


def _changed(household, people: list[str], days: list[str] | None, today_only: bool, by: str) -> None:
    for person in people:
        household.hass.bus.async_fire(
            EVENT_SCHEDULE_CHANGED, {"person": person, "days": days or [], "today_only": today_only, "by": by}
        )
    household.recompute()


def _wrap(work):
    try:
        return work()
    except ScheduleError as err:
        raise ServiceValidationError(str(err)) from err


def day_view(household, person: str, *, on: date | None = None, day: str | None = None) -> dict[str, Any]:
    """A day resolved for [person]: by date (today's change and its day type count) or a day of the week."""
    week = household.week
    if on is None and day is not None:
        # The next date that uses it: this week's weekday; the day off and the half day by type
        today = dt_util.now().date()
        if day in DAY_KEYS[:7]:
            on = today + timedelta(days=(DAY_KEYS.index(day) - today.weekday()) % 7)
            resolved = week.resolve(person, on, SCHOOL if DAY_KEYS.index(day) < 5 else "weekend", with_today=False)
        else:
            base = today if today.weekday() < 5 else today + timedelta(days=7 - today.weekday())
            resolved = week.resolve(person, base, DAY_OFF if day == "day_off" else HALF_DAY, with_today=False)
            on = base
    else:
        on = on or dt_util.now().date()
        resolved = week.resolve(person, on)
    modes = week.data.modes
    out = {
        "person": person,
        "date": on.isoformat(),
        "day_type": household.day_type_on(on) if day is None else None,
        "uses": resolved.uses,
        "changed_today": resolved.changed_today,
        "changes": [{"at": hhmm(m), "mode": mode, "name": (modes.get(mode) or {}).get("name", mode)} for m, mode in resolved.changes],
        "limits": {g.id: resolved.limits.get(g.id) for g in household.groups},
        "bedtime": None,
        "wake": None,
    }
    if resolved.changes and (modes.get(resolved.changes[-1][1]) or {}).get("allows") == "nothing":
        out["bedtime"] = hhmm(resolved.changes[-1][0])
        following = week.resolve(person, on + timedelta(days=1))
        if following.changes:
            out["wake"] = hhmm(following.changes[0][0])
    if on == dt_util.now().date():
        out["now"] = household.schedule_view(person)
    return out


def coming_up(household, today: date, days: int = COMING_UP_DAYS) -> list[dict[str, Any]]:
    """The special days ahead: a day off or half day on a weekday, a school day on a weekend, with where each came
    from (dates typed in, or the school calendar for today)."""
    config = household.school.config
    out = []
    for n in range(days):
        on = today + timedelta(days=n)
        kind = household.day_type_on(on)
        if not ((kind in (DAY_OFF, HALF_DAY) and on.weekday() < 5) or (kind == SCHOOL and on.weekday() >= 5)):
            continue
        typed = on in config.days_off or on in config.half_days or on in config.extra_school_days
        source = "typed" if typed else household.school.reason if on == household.school.day else "rule"
        out.append({"date": on.isoformat(), "type": kind, "source": source})
    return out


def panel_view(household) -> dict[str, Any]:
    """What the Schedule tab shows: the modes, the groups, this week's dates and what each uses, the special days
    coming up, and each kid's schedule and now."""
    week = household.week
    today = dt_util.now().date()
    monday = today - timedelta(days=today.weekday())
    roles = household.options.get(CONF_ROLES, {})
    kids = sorted(p for p, role in roles.items() if role == "kid" and p in household.people())
    names = {g.id: g.name for g in household.groups}
    dates = []
    for n in range(7):
        on = monday + timedelta(days=n)
        dates.append({"date": on.isoformat(), "key": weekday_key(on), "type": household.day_type_on(on)})
    return {
        "today": today.isoformat(),
        "now": dt_util.now().isoformat(),
        "modes": {
            mode_id: {**mode, "description": describe_mode(mode, lambda g: names.get(g, g))}
            for mode_id, mode in week.data.modes.items()
        },
        "groups": [{"id": g.id, "name": g.name, "in_all": g.in_all} for g in household.groups],
        "week": dates,
        "coming_up": coming_up(household, today),
        "half_day_default": "12:00",
        "kids": [
            {
                "id": person,
                "name": household.person_name(person),
                **week.view(person),
                "this_week": [
                    {
                        "date": d["date"],
                        "uses": week.resolve(person, date.fromisoformat(d["date"])).uses,
                        "changed_today": week.resolve(person, date.fromisoformat(d["date"])).changed_today,
                    }
                    for d in dates
                ],
                "now": household.schedule_view(person),
                # The parental controls Hearth holds for them (Configure > Enforce)
                "controls": sorted({e.kind for e in enforcers_from_options(household.options) if e.person == person}),
            }
            for person in kids
        ],
    }


def async_register_services(hass: HomeAssistant) -> None:
    @callback
    def set_schedule(call: ServiceCall) -> ServiceResponse:
        """Replaces the days' changes and/or limits (limits merge: a group not given keeps its own)."""
        household = _household(hass)
        people = _people(household, call.data["people"])
        days = call.data.get("days") or []
        token = _wrap(
            lambda: household.week.set_days(
                people,
                days,
                _changes(call.data.get("changes")),
                _limits(household, call.data.get("limits")),
                call.data.get("half_day_ends"),
                call.data.get("half_day_limits"),
            )
        )
        _changed(household, people, days, False, "service")
        return {"undo": token, "people": {p: household.week.view(p) for p in people}}

    @callback
    def copy_schedule(call: ServiceCall) -> ServiceResponse:
        household = _household(hass)
        source = _people(household, [call.data["from"]])[0]
        to_people = _people(household, call.data["to_people"]) if call.data.get("to_people") else None
        token = _wrap(
            lambda: household.week.copy(
                source, call.data.get("day"), to_people, call.data.get("to_days"), call.data["times"], call.data["limits"]
            )
        )
        _changed(household, to_people or [source], call.data.get("to_days") or ([call.data["day"]] if call.data.get("day") else list(DAY_KEYS)), False, "service")
        return {"undo": token}

    @callback
    def change_today(call: ServiceCall) -> ServiceResponse:
        """Today only, ending at midnight: a bedtime, a mode from now until a time (the next change by default), the
        day's changes, and/or limits."""
        household = _household(hass)
        people = _people(household, call.data["people"])
        now = dt_util.now()
        if not any(k in call.data for k in ("bedtime", "mode", "changes", "limits")):
            raise ServiceValidationError("Give a bedtime, a mode, changes or limits")
        tokens = {}
        for person in people:
            tokens[person] = _wrap(
                lambda person=person: household.week.change_today(
                    person,
                    now.date(),
                    changes=_changes(call.data.get("changes")),
                    limits=_limits(household, call.data.get("limits")),
                    bedtime=call.data.get("bedtime"),
                    mode=call.data.get("mode"),
                    start=(now.hour * 60 + now.minute) // 15 * 15 if call.data.get("mode") else None,
                    until=call.data.get("until"),
                    by="service",
                    reason=call.data.get("reason"),
                )
            )
        _changed(household, people, [weekday_key(now.date())], True, "service")
        return {"undo": tokens}

    @callback
    def resume_schedule(call: ServiceCall) -> ServiceResponse:
        household = _household(hass)
        people = _people(household, call.data["people"])
        dropped = household.week.resume(people)
        _changed(household, dropped, [], True, "service")
        return {"resumed": dropped}

    @callback
    def get_schedule(call: ServiceCall) -> ServiceResponse:
        household = _household(hass)
        person = _people(household, [call.data["person"]])[0]
        return day_view(household, person, on=call.data.get("date"), day=call.data.get("day"))

    for name, handler, schema, response in (
        ("set_schedule", set_schedule, SET_SCHEDULE_SCHEMA, SupportsResponse.OPTIONAL),
        ("copy_schedule", copy_schedule, COPY_SCHEDULE_SCHEMA, SupportsResponse.OPTIONAL),
        ("change_today", change_today, CHANGE_TODAY_SCHEMA, SupportsResponse.OPTIONAL),
        ("resume_schedule", resume_schedule, RESUME_SCHEMA, SupportsResponse.OPTIONAL),
        ("get_schedule", get_schedule, GET_SCHEDULE_SCHEMA, SupportsResponse.ONLY),
    ):
        register_service(hass, DOMAIN, name, handler, schema=schema, supports_response=response)


# The panel's commands


def _run(hass: HomeAssistant, connection, msg, work, people: list[str] | None = None, days=None, today_only=False) -> None:
    hub = _hub(hass)
    if hub is None:
        connection.send_error(msg["id"], "not_set_up", "Hearth isn't set up")
        return
    household = hub.household
    try:
        result = work(household)
    except (ScheduleError, ServiceValidationError) as err:
        connection.send_error(msg["id"], "invalid", str(err))
        return
    if people is not None:
        _changed(household, people, days, today_only, "panel")
    connection.send_result(msg["id"], {**(result or {}), "schedule": panel_view(household)})


@websocket_api.require_admin
@websocket_api.websocket_command({vol.Required("type"): "hearth/schedule/get"})
@callback
def ws_get(hass: HomeAssistant, connection: websocket_api.ActiveConnection, msg: dict[str, Any]) -> None:
    _run(hass, connection, msg, lambda household: {})


@websocket_api.require_admin
@websocket_api.websocket_command(
    {
        vol.Required("type"): "hearth/schedule/set",
        vol.Required("person"): _PERSON,
        vol.Required("days"): vol.All(cv.ensure_list, [_DAY]),
        vol.Optional("changes"): [_CHANGE],
        vol.Optional("limits"): _LIMITS,
        vol.Optional("half_day_ends"): vol.Any(None, cv.string),
        vol.Optional("half_day_limits"): vol.In(HALF_LIMITS),
    }
)
@callback
def ws_set(hass: HomeAssistant, connection: websocket_api.ActiveConnection, msg: dict[str, Any]) -> None:
    def work(household):
        person = _people(household, [msg["person"]])[0]
        token = household.week.set_days(
            [person],
            msg["days"],
            _changes(msg.get("changes")),
            _limits(household, msg.get("limits")),
            msg.get("half_day_ends"),
            msg.get("half_day_limits"),
        )
        return {"undo": token}

    _run(hass, connection, msg, work, [msg["person"]], msg["days"])


@websocket_api.require_admin
@websocket_api.websocket_command(
    {
        vol.Required("type"): "hearth/schedule/copy",
        vol.Required("from"): _PERSON,
        vol.Optional("day"): vol.Any(None, vol.In([*DAY_KEYS, "half_day"])),
        vol.Optional("to_people"): [_PERSON],
        vol.Optional("to_days"): [_DAY],
        vol.Optional("times", default=True): bool,
        vol.Optional("limits", default=True): bool,
    }
)
@callback
def ws_copy(hass: HomeAssistant, connection: websocket_api.ActiveConnection, msg: dict[str, Any]) -> None:
    def work(household):
        to_people = _people(household, msg["to_people"]) if msg.get("to_people") else None
        return {
            "undo": household.week.copy(
                msg["from"], msg.get("day"), to_people, msg.get("to_days"), msg["times"], msg["limits"]
            )
        }

    _run(hass, connection, msg, work, msg.get("to_people") or [msg["from"]], msg.get("to_days") or [])


@websocket_api.require_admin
@websocket_api.websocket_command({vol.Required("type"): "hearth/schedule/undo", vol.Required("token"): cv.string})
@callback
def ws_undo(hass: HomeAssistant, connection: websocket_api.ActiveConnection, msg: dict[str, Any]) -> None:
    people: list[str] = []

    def work(household):
        people.extend(household.week.undo(msg["token"]))
        household.recompute()
        return {"people": people}

    _run(hass, connection, msg, work)


@websocket_api.require_admin
@websocket_api.websocket_command(
    {
        vol.Required("type"): "hearth/schedule/today",
        vol.Required("person"): _PERSON,
        vol.Optional("changes"): [_CHANGE],
        vol.Optional("limits"): _LIMITS,
    }
)
@callback
def ws_today(hass: HomeAssistant, connection: websocket_api.ActiveConnection, msg: dict[str, Any]) -> None:
    def work(household):
        person = _people(household, [msg["person"]])[0]
        token = household.week.change_today(
            person,
            dt_util.now().date(),
            changes=_changes(msg.get("changes")),
            limits=_limits(household, msg.get("limits")),
            by="panel",
        )
        return {"undo": token}

    _run(hass, connection, msg, work, [msg["person"]], [weekday_key(dt_util.now().date())], True)


@websocket_api.require_admin
@websocket_api.websocket_command({vol.Required("type"): "hearth/schedule/resume", vol.Required("person"): _PERSON})
@callback
def ws_resume(hass: HomeAssistant, connection: websocket_api.ActiveConnection, msg: dict[str, Any]) -> None:
    _run(hass, connection, msg, lambda household: {"resumed": household.week.resume([msg["person"]])}, [msg["person"]], [], True)


@websocket_api.require_admin
@websocket_api.websocket_command(
    {
        vol.Required("type"): "hearth/schedule/mode",
        vol.Optional("mode_id"): vol.Any(None, cv.string),
        vol.Required("name"): cv.string,
        vol.Required("allows"): vol.In(ALLOWS),
        vol.Optional("closed"): [cv.string],
        vol.Optional("keep_not_screen_time"): bool,
    }
)
@callback
def ws_mode(hass: HomeAssistant, connection: websocket_api.ActiveConnection, msg: dict[str, Any]) -> None:
    def work(household):
        closed = [g for g in msg.get("closed") or [] if g != ALL]
        mode_id = household.week.set_mode(
            msg.get("mode_id"), msg["name"], msg["allows"], closed, msg.get("keep_not_screen_time")
        )
        household.recompute()
        return {"mode_id": mode_id}

    _run(hass, connection, msg, work)


@websocket_api.require_admin
@websocket_api.websocket_command({vol.Required("type"): "hearth/schedule/mode/remove", vol.Required("mode_id"): cv.string})
@callback
def ws_mode_remove(hass: HomeAssistant, connection: websocket_api.ActiveConnection, msg: dict[str, Any]) -> None:
    def work(household):
        people = household.week.remove_mode(msg["mode_id"])
        household.recompute()
        return {"people": people}

    _run(hass, connection, msg, work)


def async_register_commands(hass: HomeAssistant) -> None:
    for command in (ws_get, ws_set, ws_copy, ws_undo, ws_today, ws_resume, ws_mode, ws_mode_remove):
        websocket_api.async_register_command(hass, command)

