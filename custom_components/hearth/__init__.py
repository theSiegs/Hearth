"""Hearth: the household's Hearth devices (TVs, phones and tablets) in Home Assistant.

See docs/home-assistant-integration.md.
"""

from __future__ import annotations

import logging

from datetime import datetime, timedelta

import voluptuous as vol

from homeassistant.config_entries import ConfigEntry
from homeassistant.const import EVENT_STATE_CHANGED, Platform
from homeassistant.core import HomeAssistant, ServiceCall, ServiceResponse, SupportsResponse, callback
from homeassistant.exceptions import ServiceValidationError
from homeassistant.helpers import config_validation as cv
from homeassistant.helpers import device_registry as dr
from homeassistant.helpers import issue_registry as ir
from homeassistant.helpers.event import (
    async_track_state_change_event,
    async_track_time_change,
    async_track_time_interval,
)
from homeassistant.util import dt as dt_util

from .entry_tasks import async_wait_for_entry_tasks
from .entry_tasks import entry_task
from .api import async_register_views
from .auth import is_adult_user, register_service
from .websocket import async_register_commands
from .pause import end_app_pause, end_pause, set_app_pause, set_pause
from .places import ARRIVE, LEAVE
from . import panel, suggest_push
from .apps import ACTION_PREFIX
from .asks import ACTION_PREFIX as ASK_ACTION_PREFIX
from .commands import is_profile_id, what_to_play
from .const import CAP_PLAY, CAP_PUSH, CONF_DEVICES, CONF_PROFILES, CONF_PUSH_TOPIC, DOMAIN
from .profiles import ISSUE_PROFILE_KEYS, legacy_keys
from .push import new_topic
from .hub import HearthHub
from .attention import ACT_PREFIX
from .limits import DAY_TYPES
from .asks import EVENT_MORE_TIME_ANSWERED, EVENT_MORE_TIME_REQUESTED, AskError
from .const import EVENT_BUDGET_REACHED
from .counting import ALL
from .exceptions import END_OF_DAY, SCHOOL_TIME_END, at_time, end_of_day
from . import family_link as fl
from .enforce import FAMILY_SAFETY, enforcers_from_options, fs_account_of
from .sites import BLOCKED, BOTH, FROM_CHOICES, LIST_CHOICES, CopySites
from .watch import CHANNELS, MAX_BLOCKS, MAX_LOG, VIDEOS, WORDS, channel_id_of, clean_word, video_id_of

PLATFORMS = [Platform.BINARY_SENSOR, Platform.NUMBER, Platform.SENSOR]

type HearthConfigEntry = ConfigEntry[HearthHub]

CONFIG_SCHEMA = cv.config_entry_only_config_schema(DOMAIN)

_VIEWS_REGISTERED = f"{DOMAIN}_views"

# Microsoft Family Safety: a child asked for more time on an Xbox or a PC
EVENT_FS_REQUEST = "microsoft_family_safety_request"
EVENT_FS_RESOLVED = "microsoft_family_safety_request_resolved"
SERVICE_ADD_BONUS = "add_bonus"
SERVICE_SET_BUDGET = "set_budget"

ADD_BONUS_SCHEMA = vol.Schema(
    {
        vol.Required("person"): cv.entity_id,
        vol.Required("minutes"): vol.All(vol.Coerce(int), vol.Range(min=-1440, max=1440)),
        vol.Optional("group", default="all"): cv.string,
        # Only on this device of theirs (a target id: hearth:<id>, fl:<id>, fs:xbox, nintendo:<entity>)
        vol.Optional("device"): cv.string,
    }
)
SET_BUDGET_SCHEMA = vol.Schema(
    {
        vol.Required("person"): cv.entity_id,
        vol.Required("group"): cv.string,
        vol.Required("minutes"): vol.Any(None, vol.All(vol.Coerce(int), vol.Range(min=0, max=1440))),
        # School days and other days (weekday and weekend are their older names)
        vol.Optional("days", default="both"): vol.In(["school_days", "other_days", "weekday", "weekend", "both"]),
    }
)
# Ends sooner when the person's place says so: arriving at a place, or leaving one (places.py)
ENDS_ON_SCHEMA = vol.All(
    vol.Schema(
        {
            vol.Exclusive(ARRIVE, "ends_on"): vol.All(cv.string, vol.Length(min=1, max=40)),
            vol.Exclusive(LEAVE, "ends_on"): vol.All(cv.string, vol.Length(min=1, max=40)),
        }
    ),
    cv.has_at_least_one_key(ARRIVE, LEAVE),
)
PAUSE_SCHEMA = vol.All(
    vol.Schema(
        {
            vol.Exclusive("minutes", "how_long"): vol.All(vol.Coerce(int), vol.Range(min=1, max=720)),
            vol.Exclusive("until", "how_long"): vol.Any(cv.datetime, cv.time),
            vol.Optional("reason"): cv.string,
            vol.Optional("people"): vol.All(cv.ensure_list, [cv.entity_id]),
            # With no minutes or until, the end of the day is its cap
            vol.Optional("ends_on"): ENDS_ON_SCHEMA,
            # Only this app or group (the family pause holds everything)
            vol.Exclusive("app", "what"): cv.string,
            vol.Exclusive("group", "what"): cv.string,
        }
    ),
    cv.has_at_least_one_key("minutes", "until", "ends_on"),
)
PAUSE_END_SCHEMA = vol.Schema(
    {
        vol.Optional("people"): vol.All(cv.ensure_list, [cv.entity_id]),
        vol.Exclusive("app", "what"): cv.string,
        vol.Exclusive("group", "what"): cv.string,
    }
)

_LOGGER = logging.getLogger(__name__)


def _paused_what(household, data, group_id) -> tuple[str | None, str | None]:
    """A pause's app or group, (None, None) for the family pause; All screen time is the family pause too."""
    if data.get("group") is not None:
        given = data["group"].strip()
        if given.casefold() == ALL:
            return None, None
        found = group_id(household, given)
        if household.group(found) is None:
            raise ServiceValidationError(f"No group {given}")
        return (None, None) if found == ALL else (None, found)
    if data.get("app") is not None:
        app = data["app"].strip()
        if not app:
            raise ServiceValidationError("Give an app (its package name) or a group")
        return app, None
    return None, None
GET_WATCH_LOG_SCHEMA = vol.Schema(
    {
        vol.Required("person"): cv.entity_id,
        vol.Optional("days"): vol.All(vol.Coerce(int), vol.Range(min=1, max=366)),
        vol.Optional("limit", default=200): vol.All(vol.Coerce(int), vol.Range(min=1, max=MAX_LOG)),
    }
)
WATCH_DIGEST_SCHEMA = vol.Schema(
    {
        vol.Optional("person"): cv.entity_id,
        vol.Optional("days", default=7): vol.All(vol.Coerce(int), vol.Range(min=1, max=31)),
    }
)


def _place_ends_on(household, people: list[str], given: dict | None) -> dict[str, str] | None:
    """A service's ends_on, checked against each person's places."""
    if not given:
        return None
    try:
        return household.places.check(people, given)
    except ValueError as err:
        raise ServiceValidationError(str(err)) from err


async def async_setup(hass: HomeAssistant, config: dict) -> bool:
    def household(call: ServiceCall):
        entries = hass.config_entries.async_loaded_entries(DOMAIN)
        if not entries:
            raise ServiceValidationError("Hearth isn't set up")
        household = entries[0].runtime_data.household
        if call.data["person"] not in household.people():
            raise ServiceValidationError(f"{call.data['person']} isn't one of the household's people")
        if household.group(group_id(household, call.data["group"])) is None:
            raise ServiceValidationError(f"No group {call.data['group']}")
        return household

    def group_id(household, given: str) -> str:
        """A group's id, also from its name (an older app gives the name)."""
        if household.group(given) is not None:
            return given
        by_name = next((g.id for g in household.groups if g.name.casefold() == given.strip().casefold()), None)
        return by_name or given

    @callback
    def add_bonus(call: ServiceCall) -> ServiceResponse:
        """Minutes added to (or, negative, taken from) a person's group today: the one way to extend. With a device,
        minutes on that device only (device_extra.py)."""
        target = household(call)
        group = group_id(target, call.data["group"])
        if call.data.get("device"):
            if call.data["minutes"] <= 0:
                raise ServiceValidationError("Extra time on one device is a number of minutes more than 0")
            if group != ALL and target.group(group) is None:
                raise ServiceValidationError(f"No group {call.data['group']}")
            extra = target.add_device_extra(
                call.data["person"], call.data["device"].strip(), "bonus", group, call.data["minutes"]
            )
            # Its id, so an undo ends just this one (hearth.allow_end {id})
            return {"id": extra.id, "until": dt_util.as_local(extra.until).isoformat()}
        target.add_bonus(call.data["person"], group, call.data["minutes"])
        return {}

    @callback
    def set_budget(call: ServiceCall) -> None:
        target = household(call)
        names = {"school_days": "weekday", "other_days": "weekend", "weekday": "weekday", "weekend": "weekend"}
        days = DAY_TYPES if call.data["days"] == "both" else (names[call.data["days"]],)
        for kind in days:
            target.set_budget(call.data["person"], group_id(target, call.data["group"]), kind, call.data["minutes"])

    register_service(
        hass, DOMAIN, SERVICE_ADD_BONUS, add_bonus, schema=ADD_BONUS_SCHEMA, supports_response=SupportsResponse.OPTIONAL
    )
    register_service(hass, DOMAIN, SERVICE_SET_BUDGET, set_budget, schema=SET_BUDGET_SCHEMA)

    def loaded_household():
        entries = hass.config_entries.async_loaded_entries(DOMAIN)
        if not entries:
            raise ServiceValidationError("Hearth isn't set up")
        return entries[0].runtime_data.household

    @callback
    def pause(call: ServiceCall) -> None:
        """Holds the people (everyone by default) for some minutes or until a time (today's, or tomorrow's if it's
        passed): their Hearth devices stop and say why."""
        household = loaded_household()
        now = dt_util.now()
        if "minutes" in call.data:
            until = now + timedelta(minutes=call.data["minutes"])
        elif "until" not in call.data:
            until = end_of_day(now)
        elif isinstance(call.data["until"], datetime):
            until = dt_util.as_local(call.data["until"]) if call.data["until"].tzinfo else call.data["until"].replace(
                tzinfo=dt_util.get_default_time_zone()
            )
        else:
            until = now.replace(
                hour=call.data["until"].hour, minute=call.data["until"].minute, second=0, microsecond=0
            )
            if until <= now:
                until += timedelta(days=1)
        if until <= now:
            raise ServiceValidationError("That time has passed")
        people = call.data.get("people") or household.people()
        unknown = [p for p in people if p not in household.people()]
        if unknown:
            raise ServiceValidationError(f"Not the household's: {', '.join(unknown)}")
        app, group = _paused_what(household, call.data, group_id)
        if app is not None or group is not None:
            if call.data.get("ends_on"):
                raise ServiceValidationError("A pause of one app or group ends at a time, not at a place")
            set_app_pause(hass, people, until, call.data.get("reason"), app, group)
            household.recompute()
            return
        ends_on = _place_ends_on(household, people, call.data.get("ends_on"))
        set_pause(hass, people, until, call.data.get("reason"), ends_on)
        household.recompute()

    @callback
    def pause_end(call: ServiceCall) -> None:
        household = loaded_household()
        app, group = _paused_what(household, call.data, group_id)
        if app is None and group is None:
            # The family pause only: an adult's pause of one app or group ("youtube for homework") stays
            end_pause(hass, call.data.get("people"))
        else:
            end_app_pause(hass, call.data.get("people"), app, group)
        household.recompute()

    register_service(hass, DOMAIN, "pause", pause, schema=PAUSE_SCHEMA)
    register_service(hass, DOMAIN, "pause_end", pause_end, schema=PAUSE_END_SCHEMA)
    _register_answer_request(hass)
    _register_dismiss_suggestion(hass)
    _register_exception_services(hass, loaded_household, group_id)
    _register_watch_services(hass)
    _register_play_on_tv(hass)
    _register_copy_sites(hass, loaded_household)
    return True


ANSWER_REQUEST_SCHEMA = vol.All(
    vol.Schema(
        {
            vol.Required("request_id"): cv.string,
            vol.Exclusive("minutes", "answer"): vol.All(vol.Coerce(int), vol.Range(min=1, max=600)),
            vol.Exclusive("deny", "answer"): vol.All(cv.boolean, True),
        }
    ),
    cv.has_at_least_one_key("minutes", "deny"),
)


def _register_answer_request(hass: HomeAssistant) -> None:
    """hearth.answer_request: an adult answers a request for more time, as hearth/approvals/answer does on the
    WebSocket. The first answer wins; a later one is refused."""

    @callback
    def answer_request(call: ServiceCall) -> ServiceResponse:
        entries = hass.config_entries.async_loaded_entries(DOMAIN)
        if not entries:
            raise ServiceValidationError("Hearth isn't set up")
        hub: HearthHub = entries[0].runtime_data
        minutes = None if call.data.get("deny") else call.data["minutes"]
        try:
            ask = hub.asks.answer(call.data["request_id"], minutes, call.context.user_id)
        except AskError as err:
            raise ServiceValidationError("That request isn't open any more (answered or expired)") from err
        return ask.device_view()

    register_service(
        hass,
        DOMAIN,
        "answer_request",
        answer_request,
        schema=ANSWER_REQUEST_SCHEMA,
        supports_response=SupportsResponse.OPTIONAL,
    )


DISMISS_SUGGESTION_SCHEMA = vol.Schema(
    {
        vol.Required("person"): cv.entity_id,
        vol.Required("key"): vol.All(cv.string, vol.Length(min=1, max=200)),
    }
)


def _register_dismiss_suggestion(hass: HomeAssistant) -> None:
    """hearth.dismiss_suggestion: an adult puts a suggestion off for the rest of the day ("not today")."""

    @callback
    def dismiss_suggestion(call: ServiceCall) -> None:
        from .history import DISMISS

        entries = hass.config_entries.async_loaded_entries(DOMAIN)
        if not entries:
            raise ServiceValidationError("Hearth isn't set up")
        household = entries[0].runtime_data.household
        if call.data["person"] not in household.people():
            raise ServiceValidationError(f"{call.data['person']} isn't one of the household's people")
        household.history.log(DISMISS, call.data["person"], key=call.data["key"].strip())
        household.recompute()

    register_service(hass, DOMAIN, "dismiss_suggestion", dismiss_suggestion, schema=DISMISS_SUGGESTION_SCHEMA)


ALLOW_SCHEMA = vol.All(
    vol.Schema(
        {
            vol.Required("people"): vol.All(cv.ensure_list, [cv.entity_id], vol.Length(min=1)),
            vol.Exclusive("app", "what"): cv.string,
            vol.Exclusive("group", "what"): cv.string,
            vol.Optional("until", default=END_OF_DAY): vol.Any(vol.In((END_OF_DAY, SCHOOL_TIME_END)), cv.time, cv.datetime),
            vol.Optional("reason"): cv.string,
            vol.Optional("ends_on"): ENDS_ON_SCHEMA,
            # Only on this device of theirs (a target id): a group, open there until the time
            vol.Optional("device"): cv.string,
        }
    ),
    cv.has_at_least_one_key("app", "group"),
)
ALLOW_END_SCHEMA = vol.All(
    vol.Schema(
        {
            vol.Optional("id"): cv.string,
            vol.Optional("people"): vol.All(cv.ensure_list, [cv.entity_id]),
            vol.Exclusive("app", "what"): cv.string,
            vol.Exclusive("group", "what"): cv.string,
            # Extra time on this device ends (a bonus or an allow there)
            vol.Optional("device"): cv.string,
        }
    ),
    cv.has_at_least_one_key("id", "people"),
)
EXPLAIN_SCHEMA = vol.All(
    vol.Schema(
        {
            vol.Required("person"): cv.entity_id,
            vol.Exclusive("app", "what"): cv.string,
            vol.Exclusive("group", "what"): cv.string,
        }
    ),
    cv.has_at_least_one_key("app", "group"),
)
SCHOOL_TIME_OFF_SCHEMA = vol.Schema(
    {
        vol.Required("people"): vol.All(cv.ensure_list, [cv.entity_id], vol.Length(min=1)),
        vol.Optional("date"): cv.date,
        vol.Optional("from"): cv.time,
        vol.Optional("reason"): cv.string,
        vol.Optional("ends_on"): ENDS_ON_SCHEMA,
    }
)
SCHOOL_TIME_OFF_CANCEL_SCHEMA = vol.Schema(
    {
        vol.Optional("people"): vol.All(cv.ensure_list, [cv.entity_id]),
        vol.Optional("date"): cv.date,
    }
)


def _register_exception_services(hass: HomeAssistant, loaded_household, group_id) -> None:
    """hearth.allow / allow_end / explain, and hearth.school_time_off / school_time_off_cancel."""

    def people_of(household, given: list[str]) -> list[str]:
        unknown = [p for p in given if p not in household.people()]
        if unknown:
            raise ServiceValidationError(f"Not the household's: {', '.join(unknown)}")
        return list(dict.fromkeys(given))

    def what(household, data) -> tuple[str | None, str | None]:
        if data.get("group") is not None:
            given = data["group"].strip()
            if given.casefold() == ALL:
                return None, ALL
            found = group_id(household, given)
            if household.group(found) is None:
                raise ServiceValidationError(f"No group {given}")
            return None, found
        app = (data.get("app") or "").strip()
        if not app:
            raise ServiceValidationError("Give an app (its package name) or a group")
        return app, None

    def until_for(household, person: str, until, now: datetime) -> datetime:
        if until == END_OF_DAY:
            return end_of_day(now)
        if until == SCHOOL_TIME_END:
            child = household.family_link_child(person)
            end = fl.school_time_end(hass, child) if child else None
            if end is None or end <= now:
                raise ServiceValidationError(f"{household.person_name(person)} has no School time left today")
            return end
        if isinstance(until, datetime):
            at = until if until.tzinfo else until.replace(tzinfo=dt_util.get_default_time_zone())
            if at <= now:
                raise ServiceValidationError("That time has passed")
            return at
        return at_time(now, until)

    @callback
    def allow(call: ServiceCall) -> ServiceResponse:
        """People may use an app or a group until a time: nothing Hearth holds holds it for them meanwhile."""
        household = loaded_household()
        people = people_of(household, call.data["people"])
        app, group = what(household, call.data)
        now = dt_util.now()
        until = {p: until_for(household, p, call.data["until"], now) for p in people}
        if call.data.get("device"):
            if app is not None:
                raise ServiceValidationError("On one device, allow a group (an app goes with every device)")
            if call.data.get("ends_on"):
                raise ServiceValidationError("An allow on one device ends at a time, not at a place")
            extras = [
                household.add_device_extra(p, call.data["device"].strip(), "allow", group, until=until[p],
                                           reason=call.data.get("reason"))
                for p in people
            ]
            return {
                "id": extras[0].id if len(extras) == 1 else [e.id for e in extras],
                "until": {p: dt_util.as_local(u).isoformat() for p, u in until.items()},
            }
        ends_on = _place_ends_on(household, people, call.data.get("ends_on"))
        allowed = household.allows.add(until, app, group, call.data.get("reason"), ends_on)
        household.recompute()
        answer = {"id": allowed.id, "until": {p: dt_util.as_local(u).isoformat() for p, u in until.items()}}
        if ends_on:
            answer["ends_on"] = ends_on
        return answer

    @callback
    def allow_end(call: ServiceCall) -> ServiceResponse:
        household = loaded_household()
        app = group = None
        if call.data.get("app") is not None or call.data.get("group") is not None:
            app, group = what(household, call.data)
        # A parent's grant (grants.py) ends by its id too
        grant = household.end_grant(call.data["id"]) if call.data.get("id") else None
        ended = [grant.id] if grant is not None else []
        # Extra time on one device: by its id, or the people's on that device
        if call.data.get("device") or (call.data.get("id") or "").startswith("dx_"):
            ended += household.end_device_extras(
                call.data.get("id"), call.data.get("people"), (call.data.get("device") or "").strip() or None
            )
            if call.data.get("device"):
                return {"ended": ended}
        ended += household.allows.end(call.data.get("id"), call.data.get("people"), app, group)
        household.recompute()
        # Extra time Hearth gave in Family Link or Family Safety for an allow that ended goes too
        household.sync.allow_ended()
        return {"ended": ended}

    @callback
    def explain(call: ServiceCall) -> ServiceResponse:
        household = loaded_household()
        person = people_of(household, [call.data["person"]])[0]
        app, group = what(household, call.data)
        return household.explain(person, app, group)

    async def school_time_off(call: ServiceCall) -> ServiceResponse:
        """School time off for the people on a date (today by default), from a time if given; Hearth puts it back
        on their next school day, inside each one's window."""
        household = loaded_household()
        people = people_of(household, call.data["people"])
        missing = [household.person_name(p) for p in people if household.family_link_child(p) is None]
        if missing:
            raise ServiceValidationError(f"No Family Link for {', '.join(missing)} (Configure > Enforce)")
        today = dt_util.now().date()
        day = call.data.get("date") or today
        if day < today:
            raise ServiceValidationError("That day has passed")
        ends_on = _place_ends_on(household, people, call.data.get("ends_on"))
        if ends_on and day != today:
            raise ServiceValidationError("ends_on works for today's School time off only")
        ids = household.scheduler.take_off(people, day, call.data.get("from"), call.data.get("reason"), ends_on)
        entry_task(hass, household.hub.entry.entry_id, household.scheduler.async_tick(), "hearth school time off")
        return {"ids": ids}

    async def school_time_off_cancel(call: ServiceCall) -> ServiceResponse:
        household = loaded_household()
        people = people_of(household, call.data["people"]) if call.data.get("people") else None
        changed = household.scheduler.cancel(people, call.data.get("date"))
        entry_task(hass, household.hub.entry.entry_id, household.scheduler.async_tick(), "hearth school time back")
        return {"ids": changed}

    register_service(
        hass, DOMAIN, "allow", allow, schema=ALLOW_SCHEMA, supports_response=SupportsResponse.OPTIONAL
    )
    register_service(
        hass, DOMAIN, "allow_end", allow_end, schema=ALLOW_END_SCHEMA, supports_response=SupportsResponse.OPTIONAL
    )
    register_service(
        hass, DOMAIN, "explain", explain, schema=EXPLAIN_SCHEMA, supports_response=SupportsResponse.ONLY
    )
    register_service(
        hass,
        DOMAIN,
        "school_time_off",
        school_time_off,
        schema=SCHOOL_TIME_OFF_SCHEMA,
        supports_response=SupportsResponse.OPTIONAL,
    )
    register_service(
        hass,
        DOMAIN,
        "school_time_off_cancel",
        school_time_off_cancel,
        schema=SCHOOL_TIME_OFF_CANCEL_SCHEMA,
        supports_response=SupportsResponse.OPTIONAL,
    )


COPY_SITES_SCHEMA = vol.Schema(
    {
        vol.Optional("people"): vol.All(cv.ensure_list, [cv.entity_id]),
        vol.Optional("from", default=BOTH): vol.In(FROM_CHOICES),
        vol.Optional("lists", default=BLOCKED): vol.In(LIST_CHOICES),
        vol.Optional("dry_run", default=False): cv.boolean,
    }
)


def _register_copy_sites(hass: HomeAssistant, loaded_household) -> None:
    """hearth.copy_sites: websites copied between Family Link and Family Safety, only ever added (sites.py)."""

    async def copy_sites(call: ServiceCall) -> ServiceResponse:
        household = loaded_household()
        copier = CopySites(hass, household.options)
        given = call.data.get("people")
        if given:
            unknown = [p for p in given if p not in household.people() and p not in copier.targets]
            if unknown:
                raise ServiceValidationError(f"Not the household's: {', '.join(unknown)}")
            people = list(dict.fromkeys(given))
        else:
            people = copier.people_with_both()
        return {
            person: await copier.person(person, call.data["from"], call.data["lists"], call.data["dry_run"])
            for person in people
        }

    register_service(
        hass, DOMAIN, "copy_sites", copy_sites, schema=COPY_SITES_SCHEMA, supports_response=SupportsResponse.OPTIONAL
    )


PLAY_ON_TV_SCHEMA = vol.Schema(
    {
        vol.Required("device_id"): vol.Any(cv.string, vol.All(cv.ensure_list, vol.Length(min=1, max=1), [cv.string])),
        vol.Required("what"): cv.string,
        vol.Optional("profile"): vol.Any(None, cv.string),
    }
)


def _register_play_on_tv(hass: HomeAssistant) -> None:
    """hearth.play_on_tv: a URL, a video or an app on a paired Hearth TV, handed over with its next status answer."""

    def tv_of(hub: HearthHub, given: str) -> str:
        """The TV's Hearth device id, also from its Home Assistant device id (a device selector gives that)."""
        if given in hub.devices:
            device_id = given
        else:
            device = dr.async_get(hass).async_get(given)
            device_id = next(
                (
                    ident
                    for domain, ident in (device.identifiers if device else ())
                    if domain == DOMAIN and ident in hub.devices
                ),
                None,
            )
        if device_id is None:
            raise ServiceValidationError(f"{given} isn't one of the household's Hearth devices")
        if not hub.has_cap(device_id, CAP_PLAY):
            raise ServiceValidationError(f"{hub.devices[device_id].get('name') or device_id} isn't a TV")
        return device_id

    def profile_of(hub: HearthHub, device_id: str, given: str | None) -> str | None:
        """A TV profile id as Hearth reports it (user:10), also from a person mapped to one."""
        if not given:
            return None
        given = given.strip()
        if is_profile_id(given):
            return given
        household = hub.household
        if given not in household.people():
            raise ServiceValidationError(f"{given} is neither a TV profile id (user:10) nor one of the household's people")
        # This TV's own keys: the same person is user 10 on one TV and user 12 on another
        theirs = sorted(p for p, who in household.device_profile_people(device_id).items() if who == given)
        if len(theirs) > 1:
            reported = household.tv_profiles(device_id)
            theirs = [p for p in theirs if p in reported] or theirs
        if len(theirs) != 1:
            raise ServiceValidationError(
                f"{given} has {'no' if not theirs else 'more than one'} TV profile here: give the profile id"
            )
        return theirs[0]

    @callback
    def play_on_tv(call: ServiceCall) -> ServiceResponse:
        entries = hass.config_entries.async_loaded_entries(DOMAIN)
        if not entries:
            raise ServiceValidationError("Hearth isn't set up")
        hub: HearthHub = entries[0].runtime_data
        given = call.data["device_id"]
        device_id = tv_of(hub, given[0] if isinstance(given, list) else given)
        target = what_to_play(call.data["what"])
        if target is None:
            raise ServiceValidationError("Give a link, a YouTube video (an id or a link) or an app's package name")
        profile_id = profile_of(hub, device_id, call.data.get("profile"))
        if not hub.connected(device_id):
            raise ServiceValidationError(f"{hub.devices[device_id].get('name') or device_id} isn't connected")
        # In the TV's state document from now on: its next status answer carries it
        command = hub.commands.play(device_id, target, profile_id)
        return {"id": command.id, "device_id": device_id, "expires": command.expires.isoformat()}

    register_service(
        hass, DOMAIN, "play_on_tv", play_on_tv, schema=PLAY_ON_TV_SCHEMA, supports_response=SupportsResponse.OPTIONAL
    )


def _register_watch_services(hass: HomeAssistant) -> None:
    """A kids profile's YouTube: its started videos, the weekly digest, and the parent's blocks (watch.py)."""

    def household_of(person: str | None):
        entries = hass.config_entries.async_loaded_entries(DOMAIN)
        if not entries:
            raise ServiceValidationError("Hearth isn't set up")
        household = entries[0].runtime_data.household
        if person is not None and person not in household.youtube_people():
            raise ServiceValidationError(f"{person} has no TV profile in Hearth")
        return household

    @callback
    def get_watch_log(call: ServiceCall) -> ServiceResponse:
        person = call.data["person"]
        household = household_of(person)
        days = call.data.get("days")
        since = dt_util.now() - timedelta(days=days) if days else None
        return {
            "person": person,
            "entries": household.watch.recent(person, call.data["limit"], since),
            "blocked": household.watch.blocked(person),
        }

    @callback
    def watch_digest(call: ServiceCall) -> ServiceResponse:
        person = call.data.get("person")
        household = household_of(person)
        people = [person] if person else household.youtube_people()
        digests = [household.watch.digest(p, household.person_name(p), call.data["days"]) for p in people]
        return {
            "days": call.data["days"],
            "people": digests,
            "summary": "\n\n".join(d["summary"] for d in digests) or "No one has a TV profile in Hearth.",
        }

    def blocking(kind: str, field: str, parse, add: bool):
        @callback
        def handle(call: ServiceCall) -> None:
            household = household_of(call.data["person"])
            item = parse(call.data[field])
            if item is None:
                raise ServiceValidationError(f"Not a YouTube {field.replace('_', ' ')}: {call.data[field]}")
            if add:
                if not household.watch.block(call.data["person"], kind, item, call.data.get("label")):
                    if len(household.watch.blocked(call.data["person"])[kind]) >= MAX_BLOCKS:
                        raise ServiceValidationError(f"The list is full ({MAX_BLOCKS})")
            else:
                household.watch.unblock(call.data["person"], kind, item)

        return handle

    register_service(
        hass, DOMAIN, "get_watch_log", get_watch_log, schema=GET_WATCH_LOG_SCHEMA, supports_response=SupportsResponse.ONLY
    )
    register_service(
        hass, DOMAIN, "watch_digest", watch_digest, schema=WATCH_DIGEST_SCHEMA, supports_response=SupportsResponse.ONLY
    )
    for kind, field, parse in (
        (VIDEOS, "video", video_id_of),
        (CHANNELS, "channel", channel_id_of),
        (WORDS, "word", clean_word),
    ):
        name = kind.rstrip("s")
        schema = vol.Schema(
            {
                vol.Required("person"): cv.entity_id,
                vol.Required(field): cv.string,
                **({vol.Optional("label"): cv.string} if kind != WORDS else {}),
            }
        )
        unschema = vol.Schema({vol.Required("person"): cv.entity_id, vol.Required(field): cv.string})
        register_service(hass, DOMAIN, f"block_{name}", blocking(kind, field, parse, True), schema=schema)
        register_service(hass, DOMAIN, f"unblock_{name}", blocking(kind, field, parse, False), schema=unschema)


async def async_setup_entry(hass: HomeAssistant, entry: HearthConfigEntry) -> bool:
    _check_profile_keys(hass, entry)
    _migrate_offer_more(hass, entry)
    hub = HearthHub(hass, entry)
    await hub.async_load()
    _give_push_topics(hass, entry, hub)
    entry.runtime_data = hub
    await hub.household.school.async_refresh()
    hub.household.recompute()
    # The views stay registered for Home Assistant's lifetime (aiohttp can't take one away); with no entry
    # loaded they answer that Hearth isn't set up
    if not hass.data.get(_VIEWS_REGISTERED):
        async_register_views(hass)
        async_register_commands(hass)
        panel.async_register_commands(hass)
        hass.data[_VIEWS_REGISTERED] = True
    # Hearth's page in the sidebar, while the household is set up
    await panel.async_register_panel(hass)
    await hass.config_entries.async_forward_entry_setups(entry, PLATFORMS)

    @callback
    def recompute(_now) -> None:
        hub.household.recompute()

    async def school_then_recompute(_now=None) -> None:
        """Today's school-day answer again (the calendar is asked once a day), then everyone's limits."""
        await hub.household.school.async_refresh()
        hub.household.recompute()

    # A new day starts at midnight; budgets, bonuses and quiet devices are looked at again every minute
    entry.async_on_unload(async_track_time_change(hass, school_then_recompute, hour=0, minute=0, second=1))
    entry.async_on_unload(async_track_time_interval(hass, school_then_recompute, timedelta(hours=1)))
    if school := hub.household.school.watched_entities():
        entry.async_on_unload(async_track_state_change_event(hass, school, school_then_recompute))
    entry.async_on_unload(async_track_time_interval(hass, recompute, timedelta(minutes=1)))

    # Where the kids are (places.py): whenever a tracker, a person or a place's zone changes, and every minute (a
    # reading goes stale without a change)
    @callback
    def places_update(_event_or_now=None) -> None:
        hub.household.places.update()

    entry.async_on_unload(async_track_time_interval(hass, places_update, timedelta(minutes=1)))
    if watched := hub.household.places.watched_entities():
        entry.async_on_unload(async_track_state_change_event(hass, watched, places_update))
    places_update()

    # The schedule (day types, School time off and back, the website list): every minute, and once now
    async def schedule_tick(_now=None) -> None:
        await hub.household.scheduler.async_tick()

    entry.async_on_unload(async_track_time_interval(hass, schedule_tick, timedelta(minutes=1)))
    entry.async_create_background_task(hass, schedule_tick(), "hearth schedule")
    # Chores: a to-do list changed
    if lists := hub.household.chores.lists():
        entry.async_on_unload(async_track_state_change_event(hass, lists, hub.household.chores.async_changed))

    # A group running out no longer makes an offered request: where the household chose it, its suggestion goes to
    # the adults' phones instead (suggest_push.py), so one run-out is one notification
    hub.suggest_push.start()
    entry.async_on_unload(hub.suggest_push.stop)
    # The history log (history.py): what ran out, what was asked and offered, and the answers
    history = hub.household.history
    entry.async_on_unload(hass.bus.async_listen(EVENT_BUDGET_REACHED, history.on_budget_reached))
    entry.async_on_unload(hass.bus.async_listen(EVENT_MORE_TIME_REQUESTED, history.on_requested))
    entry.async_on_unload(hass.bus.async_listen(EVENT_MORE_TIME_ANSWERED, history.on_answered))

    @callback
    def family_safety_request(event) -> None:
        """A request made on an Xbox or a PC: an ask for the person whose Family Safety account it is."""
        account = event.data.get("account_id")
        if account in (None, ""):
            return
        for enforcer in enforcers_from_options(hub.entry.options):
            if enforcer.kind == FAMILY_SAFETY and fs_account_of(hass, enforcer.entity_id) == str(account):
                hub.asks.from_family_safety(enforcer.person, dict(event.data))
                return

    entry.async_on_unload(hass.bus.async_listen(EVENT_FS_REQUEST, family_safety_request))

    @callback
    def family_safety_resolved(event) -> None:
        """A Family Safety request answered: in the Family Safety app (via app), its ask closes as answered there;
        answered by Hearth itself (via service), nothing more to do."""
        if event.data.get("via") == "service" or not event.data.get("request_id"):
            return
        hub.asks.resolved_elsewhere(str(event.data["request_id"]), event.data.get("outcome"), event.data.get("minutes"))

    entry.async_on_unload(hass.bus.async_listen(EVENT_FS_RESOLVED, family_safety_resolved))

    @callback
    def parent_change_filter(event_data) -> bool:
        return event_data.get("entity_id") in hub.household.sync.watched

    @callback
    def parent_change(event) -> None:
        """An entity of a held app, device, Switch or platform changed: maybe a parent's change in their own app."""
        hub.household.recompute()

    entry.async_on_unload(
        hass.bus.async_listen(EVENT_STATE_CHANGED, parent_change, event_filter=parent_change_filter)
    )
    # And whenever a screen time source changes
    if entities := hub.household.source_entities():
        entry.async_on_unload(async_track_state_change_event(hass, entities, recompute))
    async def phone_answer(event) -> None:
        """A button on a phone notification: an attention item's (HEARTH_ACT|<key>|<n>), a request's
        (HEARTH_MORE|<id>|<minutes>) or a new app's Sort (HEARTH_APP|<group>|<package>)."""
        action = str(event.data.get("action") or "")
        if not action.startswith((ASK_ACTION_PREFIX, ACTION_PREFIX, ACT_PREFIX)):
            return
        # Only an adult's (or an administrator's) phone answers or sorts: a kid with Home Assistant on their own phone
        # can fire the same action, for their own ask
        user = await hass.auth.async_get_user(event.context.user_id) if event.context.user_id else None
        if not is_adult_user(hass, hub, user):
            _LOGGER.warning("A Hearth notification action from someone who isn't an adult was ignored")
            return
        # An item's action, run as that adult when the item reached them
        if await hub.attention.act(action, user):
            return
        # A request for more time: the first adult's answer decides
        if hub.asks.phone_answer(action, event.context.user_id):
            return
        if not action.startswith(ACTION_PREFIX):
            return
        parts = action.split("|", 2)
        if len(parts) == 3:
            hub.household.sort_app(parts[2], parts[1])

    entry.async_on_unload(hass.bus.async_listen("mobile_app_notification_action", phone_answer))
    # "Something changed" pings to the phones, when a push server is set
    hub.push.start()
    entry.async_on_unload(hub.push.stop)
    hub.waits.start()
    entry.async_on_unload(hub.waits.stop)
    # People and groups come from the entry: when it changes (options, a phone paired), its entities are made again
    entry.async_on_unload(entry.add_update_listener(_async_entry_updated))
    return True


def _give_push_topics(hass: HomeAssistant, entry: HearthConfigEntry, hub: HearthHub) -> None:
    """Devices that get pings but have no topic (phones paired before push existed) get one now: after the hub
    loaded what each device last said (its caps), before the update listener, so it doesn't reload."""
    devices = entry.data.get(CONF_DEVICES, {})
    missing = {d for d, device in devices.items() if not device.get(CONF_PUSH_TOPIC) and hub.has_cap(d, CAP_PUSH)}
    if not missing:
        return
    hass.config_entries.async_update_entry(
        entry,
        data={
            **entry.data,
            CONF_DEVICES: {
                device_id: ({**d, CONF_PUSH_TOPIC: new_topic()} if device_id in missing else d)
                for device_id, d in devices.items()
            },
        },
    )


def _migrate_offer_more(hass: HomeAssistant, entry: HearthConfigEntry) -> None:
    """Configure > Offer more time's pairs (offer_more) become pushed suggestions with their amounts (suggest_push):
    before the update listener, so it doesn't reload."""
    if (options := suggest_push.migrated(entry.options)) is not None:
        hass.config_entries.async_update_entry(entry, options=options)


def _check_profile_keys(hass: HomeAssistant, entry: HearthConfigEntry) -> None:
    """TV profiles mapped by a bare key ("user:10", before 2026.11.07) match nothing: the serial is each TV's own, so
    the same key was a different kid on each TV. A repair issue asks an adult to pick them again (by name) until the
    options hold none."""
    old = legacy_keys(entry.options.get(CONF_PROFILES, {}))
    if not old:
        ir.async_delete_issue(hass, DOMAIN, ISSUE_PROFILE_KEYS)
        return
    ir.async_create_issue(
        hass,
        DOMAIN,
        ISSUE_PROFILE_KEYS,
        is_fixable=False,
        is_persistent=False,
        severity=ir.IssueSeverity.WARNING,
        translation_key=ISSUE_PROFILE_KEYS,
        translation_placeholders={"keys": ", ".join(old)},
    )


async def _async_entry_updated(hass: HomeAssistant, entry: HearthConfigEntry) -> None:
    hass.config_entries.async_schedule_reload(entry.entry_id)


async def async_unload_entry(hass: HomeAssistant, entry: HearthConfigEntry) -> bool:
    # Work under way (a Family Link write, a store write) finishes first, so the flush saves what it did
    await async_wait_for_entry_tasks(hass, entry.entry_id)
    await entry.runtime_data.async_flush()
    return await hass.config_entries.async_unload_platforms(entry, PLATFORMS)


async def async_remove_entry(hass: HomeAssistant, entry: HearthConfigEntry) -> None:
    """The household is deleted: Hearth's page goes from the sidebar. (A reload keeps it, so changing a setting there
    doesn't send you away.)"""
    panel.async_remove_panel(hass)


async def async_remove_config_entry_device(
    hass: HomeAssistant, entry: HearthConfigEntry, device: dr.DeviceEntry
) -> bool:
    """Deleting a Hearth device removes it from the household: its secret stops working at once. A person's device
    goes with their mapping, so it can only be removed there."""
    for domain, device_id in device.identifiers:
        if domain == DOMAIN:
            if device_id.startswith("person:"):
                return False
            await entry.runtime_data.async_remove_device(device_id)
    return True
