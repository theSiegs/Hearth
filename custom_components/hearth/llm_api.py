"""Hearth for assistants: an LLM API ("hearth") that Home Assistant's MCP Server and Assist (voice and chat) offer to
a language model. See docs/home-assistant-integration.md, MCP and voice.

Who may use it:
- A Home Assistant user who is an adult (an administrator, or an adult on Hearth's page, auth.py): the read tools
  answer, and the action tools act at once, as that user (Context(user_id)), and say exactly what changed (who, what,
  which device or pool, how many minutes, until when) so the adult can correct it.
- A call with no user (a voice satellite): only while Configure > Voice assistants is on. The read tools answer; an
  action doesn't run, it asks the adults' phones (an attention item with the action and "Don't allow", gone after
  VOICE_FOR) and runs as the adult who taps it, once. Off: no tools at all.
- Anyone else (a kid with a Home Assistant user of their own): no tools, and every tool refuses them.

What it never does: change a budget (no set_budget; lasting changes stay on Hearth's page), or let a kid use an app
or game a parent blocked in Family Link or Family Safety (hearth_allow of such an app, and approving a request for
one, are refused here in code, whatever the model is told), nor hearth_allow of a Switch game that isn't on its
Switch's allow list in the Nintendo app (its age rating may block it there).

Audit: every history event an action logs carries `via` (mcp or voice) and `user` (the Home Assistant user who acted
or tapped Allow); an action that logs nothing of its own (a pause, an allow, School time off) logs an `assist` event.
"""

from __future__ import annotations

from collections.abc import Awaitable, Callable
from dataclasses import dataclass, field
from datetime import datetime, timedelta
import logging
import secrets
from typing import TYPE_CHECKING, Any, TypeVar

import voluptuous as vol

from homeassistant.core import Context, HomeAssistant, SupportsResponse, callback
from homeassistant.exceptions import HomeAssistantError
from homeassistant.helpers import config_validation as cv
from homeassistant.helpers import device_registry as dr
from homeassistant.helpers import entity_registry as er
from homeassistant.helpers import llm
from homeassistant.helpers.event import async_call_later
from homeassistant.util import dt as dt_util
from homeassistant.util.json import JsonObjectType

from .asks import PENDING
from .attention import ADULTS, NOTICE, Action, Item, attention
from .auth import is_adult_user
from .const import CONF_VOICE_ASSISTANTS, DOMAIN
from .counting import ALL
from .enforce import FAMILY_SAFETY, enforcers_from_options, fs_account_of
from .exceptions import end_of_day
from .history import ACTOR, ASSIST
from .pause import pause_of

if TYPE_CHECKING:
    from .household import Household
    from .hub import HearthHub

_LOGGER = logging.getLogger(__name__)

API_ID = "hearth"
API_NAME = "Hearth"
# Where a call came from: Home Assistant's MCP Server, or Assist (a voice satellite, or a chat)
VIA_MCP = "mcp"
VIA_VOICE = "voice"
MCP_PLATFORM = "mcp_server"
# A voice action's approval waits this long for an adult's tap; its item key and phone tag
VOICE_FOR = timedelta(minutes=10)
VOICE_PREFIX = "voice:"
VOICE_TAG = "hearth_voice:"
SENT = "Sent to your phone for approval"

ADULT = "adult"
VOICE = "voice"
REFUSED = "refused"

# What the history keeps of an action that logs nothing of its own: never a reason or a note
_AUDIT_FIELDS = ("app", "group", "minutes", "device", "until", "date", "from", "id", "deny", "request_id")

T = TypeVar("T")


def _hub(hass: HomeAssistant) -> HearthHub | None:
    entries = hass.config_entries.async_loaded_entries(DOMAIN)
    return entries[0].runtime_data if entries else None


def voice_on(hub: HearthHub | None) -> bool:
    return bool(hub is not None and hub.entry.options.get(CONF_VOICE_ASSISTANTS))


@dataclass(frozen=True)
class Caller:
    kind: str
    user_id: str | None
    via: str
    device_id: str | None = None


async def caller_of(hass: HomeAssistant, hub: HearthHub | None, llm_context: llm.LLMContext) -> Caller:
    """Who is asking: an adult user, a call without a user (voice), or someone refused."""
    via = VIA_MCP if llm_context.platform == MCP_PLATFORM else VIA_VOICE
    user_id = llm_context.context.user_id if llm_context.context is not None else None
    if user_id is None:
        return Caller(VOICE, None, via, llm_context.device_id)
    user = await hass.auth.async_get_user(user_id)
    adult = user is not None and user.is_active and is_adult_user(hass, hub, user)
    return Caller(ADULT if adult else REFUSED, user_id, via, llm_context.device_id)


def _may_use(hub: HearthHub | None, caller: Caller) -> bool:
    if hub is None:
        return False
    return caller.kind == ADULT or (caller.kind == VOICE and voice_on(hub))


# Audit


async def run_audited(
    hub: HearthHub | None,
    via: str,
    user_id: str | None,
    tool: str | None,
    person: str | None,
    audit: dict[str, Any],
    run: Awaitable[T],
) -> tuple[T, list[dict[str, Any]]]:
    """Runs [run] with every history event it logs marked {via, user}; when it logs none (and didn't fail), an
    `assist` event says what was done. The events logged, for the tool's answer."""
    if hub is None:
        return await run, []
    history = hub.household.history
    before = len(history.events)
    token = ACTOR.set({"via": via, "user": user_id})
    try:
        result = await run
    finally:
        ACTOR.reset(token)
    logged = [e for e in history.events[before:] if e.get("via") == via and e.get("user") == user_id]
    if not logged and result is not False:
        logged = [history.log(ASSIST, person or "", via=via, user=user_id, tool=tool, **audit)]
    return result, logged


# Finding what the model names


def _fold(text: Any) -> str:
    return " ".join(str(text or "").replace("_", " ").split()).casefold()


def find_person(household: Household, given: Any) -> str:
    """A person of the household by entity id or name ("person.sam", "Sam", "sam")."""
    people = household.people()
    wanted = _fold(given)
    for person in people:
        if wanted in (_fold(person), _fold(person.removeprefix("person.")), _fold(household.person_name(person))):
            return person
    names = ", ".join(household.person_name(p) for p in people) or "nobody yet"
    raise HomeAssistantError(f"No one called {given} in the household (people: {names})")


def find_group(household: Household, given: Any) -> str:
    """A group by id or name; "all", "screen time" and "all screen time" are the shared pool."""
    wanted = _fold(given)
    if wanted in ("all", "screen time", "all screen time", "everything"):
        return ALL
    for group in household.groups:
        if wanted in (_fold(group.id), _fold(group.name)):
            return group.id
    names = ", ".join(g.name for g in household.groups)
    raise HomeAssistantError(f"No group {given} (groups: {names})")


def group_name(household: Household, group: str) -> str:
    if group == ALL:
        return "All screen time"
    found = household.group(group)
    return found.name if found else group


def find_app(household: Household, person: str | None, given: Any) -> tuple[str, str]:
    """An app as (package, name), by its package or its name as Hearth knows it."""
    text = str(given or "").strip()
    if not text:
        raise HomeAssistantError("Name an app")
    known = household.known_apps()
    if text in known:
        return text, _app_label(household, person, text, known)
    wanted = _fold(text)
    for package, label in known.items():
        names = {_fold(label), _fold(label.split(" (", 1)[0])}
        entry = household.apps.apps.get(package)
        if entry is not None and entry.name:
            names.add(_fold(entry.name))
        if wanted in names:
            return package, _app_label(household, person, package, known)
    if "." in text or ":" in text:
        return text, text
    raise HomeAssistantError(f"Hearth doesn't know an app called {text}: give its package name (com.example.app)")


def _app_label(household: Household, person: str | None, package: str, known: dict[str, str]) -> str:
    return household.app_names({package}, person).get(package) or known.get(package) or package


def find_target(household: Household, person: str, given: Any) -> dict[str, Any]:
    """One of the person's devices (targets.py) by its id or name."""
    from .targets import targets_of

    targets = targets_of(household, person)
    wanted = _fold(given)
    for target in targets:
        if wanted in (_fold(target["id"]), _fold(target["name"])):
            return target
    names = ", ".join(t["name"] for t in targets) or "none"
    raise HomeAssistantError(f"{given} isn't one of {household.person_name(person)}'s devices ({names})")


# A parent's own blocks


def parent_blocks(household: Household, person: str) -> list[dict[str, str]]:
    """The apps and games a parent blocked for the person in Family Link (its Blocked Apps sensor) or Family Safety (an
    app it reports blocked that Hearth's own pause_app didn't block): [{app, name, in}]. Hearth's allows never lift
    these, and nothing here may ask to."""
    hass = household.hass
    found: list[dict[str, str]] = []
    if (child := household.family_link_child(person)) is not None:
        for state in hass.states.async_all("sensor"):
            if not state.entity_id.endswith("_blocked_apps") or str(state.attributes.get("child_id")) != str(child):
                continue
            for app in state.attributes.get("apps") or []:
                if isinstance(app, dict) and app.get("package"):
                    found.append({"app": str(app["package"]), "name": str(app.get("name") or app["package"]),
                                  "in": "Family Link"})
    enforcers = [e for e in enforcers_from_options(household.options) if e.kind == FAMILY_SAFETY and e.person == person]
    if not enforcers:
        return found
    accounts = {str(a) for e in enforcers if (a := fs_account_of(hass, e.entity_id))}
    registry = er.async_get(hass)
    devices = {entry.device_id for e in enforcers if (entry := registry.async_get(e.entity_id)) and entry.device_id}
    for state in hass.states.async_all("sensor"):
        attrs = state.attributes
        if str(attrs.get("user_id")) not in accounts:
            entry = registry.async_get(state.entity_id)
            if entry is None or entry.device_id not in devices:
                continue
        ours = {
            str(p.get("package"))
            for p in attrs.get("paused_apps") or []
            if isinstance(p, dict) and p.get("paused") == "ours"
        }
        apps = attrs.get("applications")
        rows = [a for a in apps if isinstance(a, dict)] if isinstance(apps, list) else []
        if attrs.get("app_id") is not None:
            rows.append({"app_id": attrs.get("app_id"), "app_name": attrs.get("app_name"), "blocked": attrs.get("blocked")})
        for app in rows:
            app_id = str(app.get("app_id") or "")
            if app_id and app.get("blocked") and app_id not in ours:
                found.append({"app": app_id, "name": str(app.get("app_name") or app_id), "in": "Family Safety"})
    return found


def parent_block_of(household: Household, person: str, *names: Any) -> dict[str, str] | None:
    """The parent's block of an app by any of [names] (its package or its name), else None."""
    wanted = {_fold(n) for n in names if n}
    for block in parent_blocks(household, person):
        if _fold(block["app"]) in wanted or _fold(block["name"]) in wanted:
            return block
    return None


async def nintendo_block_of(household: Household, person: str, *names: Any) -> dict[str, str] | None:
    """A game on one of the person's Switches, by its name or id, that isn't on that Switch's allow list in the
    Nintendo app (list_applications of a Nintendo integration that has it), else None. Nintendo blocks a game by its
    age rating unless a parent put it on the allow list, and Hearth can't see the rating: a game off the list is taken
    as one a parent may have blocked. A Switch that can't be asked is skipped."""
    from . import nintendo

    hass = household.hass
    wanted = {_fold(n) for n in names if n}
    if not wanted or not hass.services.has_service(nintendo.NINTENDO_DOMAIN, nintendo.LIST_APPS):
        return None
    for switch in nintendo.switches(household, person):
        try:
            response = await hass.services.async_call(
                nintendo.NINTENDO_DOMAIN,
                nintendo.LIST_APPS,
                {"device_id": switch["device_id"]},
                blocking=True,
                return_response=True,
            )
        except Exception as err:  # noqa: BLE001 - one Switch not answering mustn't stop the rest
            _LOGGER.debug("Couldn't list the games on %s: %s", switch["name"], err)
            continue
        for app in (response or {}).get("applications") or []:
            if not isinstance(app, dict) or app.get("allowed"):
                continue
            if _fold(app.get("name")) in wanted or _fold(app.get("application_id")) in wanted:
                return {
                    "app": str(app.get("application_id") or ""),
                    "name": str(app.get("name") or app.get("application_id")),
                    "in": "the Nintendo app",
                    "switch": switch["name"],
                }
    return None


def _refuse_nintendo(block: dict[str, str], who: str) -> HomeAssistantError:
    return HomeAssistantError(
        f"{block['name']} isn't on the allow list of {block['switch']} in the Nintendo app, so the Switch's own "
        f"restrictions may block it for {who}. Hearth won't open it: only a parent can, in the Nintendo app."
    )


def _refuse_blocked(block: dict[str, str], who: str) -> HomeAssistantError:
    return HomeAssistantError(
        f"A parent blocked {block['name']} for {who} in {block['in']}. Hearth won't unblock it: only a parent can, in "
        f"the {block['in']} app."
    )


# Reading the household


def _summary(hub: HearthHub) -> dict[str, Any]:
    from .websocket import summary

    return summary(hub)


_BRIEF = (
    "id", "name", "kind", "all", "groups", "locked", "locked_by", "pause", "lock", "next_lock", "held_by",
    "google_tv_limit", "school_time", "school_time_off", "place", "playing", "headline", "lines",
)
_DETAIL = _BRIEF + (
    "allows", "pauses", "grants", "device_extras", "devices_today", "apps_today", "first_party", "answered_elsewhere",
    "week",
)


def _person_view(row: dict[str, Any], keys: tuple[str, ...]) -> dict[str, Any]:
    out = {k: row[k] for k in keys if k in row and row[k] not in (None, [], {})}
    if "targets" in row and "week" in keys:
        out["devices"] = [{"id": t["id"], "name": t["name"], "kind": t.get("kind")} for t in row["targets"]]
    return out


def _requests(body: dict[str, Any]) -> list[dict[str, Any]]:
    """The requests for more time waiting for an answer (never a pairing: that's an administrator's, on the page)."""
    keep = ("id", "person", "person_name", "minutes", "group", "note", "asked", "expires", "offered", "source", "app",
            "platform", "app_name")
    return [{k: a[k] for k in keep if a.get(k) not in (None, "")} for a in body["approvals"] if a.get("type") == "more_time"]


def _suggestions(body: dict[str, Any], person: str | None = None) -> list[dict[str, Any]]:
    out = []
    for s in body["household"].get("suggestions") or []:
        if person is not None and s.get("person") != person:
            continue
        row = {k: v for k, v in s.items() if k != "actions"}
        row["amounts"] = [a["data"]["minutes"] for a in s.get("actions") or [] if "minutes" in (a.get("data") or {})]
        out.append(row)
    return out


# Tools


class HearthTool(llm.Tool):
    """A Hearth tool: checks the caller on every call (the API also offers no tools to one who may not use them)."""

    read_only = True

    async def async_call(
        self, hass: HomeAssistant, tool_input: llm.ToolInput, llm_context: llm.LLMContext
    ) -> JsonObjectType:
        hub = _hub(hass)
        caller = await caller_of(hass, hub, llm_context)
        if hub is None:
            raise HomeAssistantError("Hearth isn't set up")
        if not _may_use(hub, caller):
            raise HomeAssistantError(
                "Only an adult of the household may use Hearth"
                if caller.kind != VOICE
                else "Voice assistants are off for Hearth (Configure > Voice assistants)"
            )
        try:
            args = self.parameters(dict(tool_input.tool_args or {}))
        except vol.Invalid as err:
            raise HomeAssistantError(f"Invalid input: {err}") from err
        return await self.call(hass, hub, caller, args, llm_context)

    async def call(
        self, hass: HomeAssistant, hub: HearthHub, caller: Caller, args: dict[str, Any], llm_context: llm.LLMContext
    ) -> JsonObjectType:
        raise NotImplementedError


class HouseholdTool(HearthTool):
    name = "hearth_get_household"
    description = (
        "Overview of the household's screen time today: for each person, the shared pool (All screen time) and each "
        "group with minutes used, minutes left, budget and bonus; whether they're locked and by what (a pause, "
        "bedtime, School time, a parent's app); what they're playing; a short headline. Also the requests for more "
        "time waiting for an answer and the Hearth devices (TVs, phones) with what's on."
    )

    async def call(self, hass, hub, caller, args, llm_context):
        body = _summary(hub)
        return {
            "people": [_person_view(p, _BRIEF) for p in body["people"]],
            "requests": _requests(body),
            "headline": body["household"].get("headline"),
            "devices": [
                {k: d[k] for k in ("name", "kind", "connected", "screen", "app", "media_title", "person") if d.get(k)}
                for d in body["devices"]
            ],
            "groups": [{"id": g["id"], "name": g["name"]} for g in body["groups"]],
        }


class PersonTool(HearthTool):
    name = "hearth_get_person"
    description = (
        "One person's day in detail: pools and groups, minutes per device and per app today, allows, pauses, a "
        "parent's grants, extra time on one device, Google's and Microsoft's own limits, and the last 7 days "
        "(minutes per group, what ran out, bonus minutes, requests). Also their devices (ids for a bonus or an allow "
        "on one device)."
    )
    parameters = vol.Schema({vol.Required("person", description="The person's name or entity id"): str})

    async def call(self, hass, hub, caller, args, llm_context):
        person = find_person(hub.household, args["person"])
        row = next((p for p in _summary(hub)["people"] if p["id"] == person), None)
        if row is None:
            raise HomeAssistantError(f"Hearth has nothing for {hub.household.person_name(person)} yet")
        return _person_view(row, _DETAIL)


class ExplainTool(HearthTool):
    name = "hearth_explain"
    description = (
        "Why a person can or can't use an app or a group now: allowed, until when, what blocks it (budget, pause, "
        "bedtime, School time, Google's or Microsoft's own limit, a parent's lock) and the allows that apply. Says "
        "too when a parent blocked the app in Family Link or Family Safety (Hearth can't change that)."
    )
    parameters = vol.Schema(
        {
            vol.Required("person", description="The person's name or entity id"): str,
            vol.Exclusive("app", "what", description="An app's name or package"): str,
            vol.Exclusive("group", "what", description="A group's name or id, or 'all' for All screen time"): str,
        }
    )

    async def call(self, hass, hub, caller, args, llm_context):
        household = hub.household
        person = find_person(household, args["person"])
        if args.get("app"):
            if block := parent_block_of(household, person, args["app"]):
                return {"person": person, "app": block["app"], "app_name": block["name"], "allowed": False,
                        "parent_block": block}
            package, name = find_app(household, person, args["app"])
            answer = household.explain(person, package, None)
            answer["app_name"] = name
            if block := parent_block_of(household, person, package, name, args["app"]):
                answer["allowed"] = False
                answer["parent_block"] = block
            return answer
        if not args.get("group"):
            raise HomeAssistantError("Name an app or a group")
        group = find_group(household, args["group"])
        answer = household.explain(person, None, group)
        answer["group_name"] = group_name(household, group)
        return answer


class SuggestionsTool(HearthTool):
    name = "hearth_get_suggestions"
    description = (
        "Hearth's suggestions for the adults now (a group or a device ran out, a request): each with its key, text, "
        "reason, the minutes it suggests and the amounts offered. Accept one with hearth_add_bonus, put it off for "
        "today with hearth_dismiss_suggestion (its key)."
    )
    parameters = vol.Schema({vol.Optional("person", description="Only this person's"): str})

    async def call(self, hass, hub, caller, args, llm_context):
        person = find_person(hub.household, args["person"]) if args.get("person") else None
        return {"suggestions": _suggestions(_summary(hub), person)}


class RequestsTool(HearthTool):
    name = "hearth_get_requests"
    description = (
        "Requests for more time waiting for an answer (from a TV, a phone, an Xbox or Windows PC through Family "
        "Safety), each with its id for hearth_answer_request; and requests lately answered in a parent's own app."
    )

    async def call(self, hass, hub, caller, args, llm_context):
        body = _summary(hub)
        return {
            "requests": _requests(body),
            "answered_elsewhere": {
                p["name"]: p["answered_elsewhere"] for p in body["people"] if p.get("answered_elsewhere")
            },
        }


# Actions


@dataclass
class Plan:
    """An action as a hearth service call, and what to tell the adult."""

    service: str
    data: dict[str, Any]
    # "give Sam 30 more minutes of Video today": the phone approval's question and the result's summary
    text: str
    # The phone approval's button ("+30 min", "Allow", "Pause")
    label: str
    # The person it's about (None: everyone)
    person: str | None = None
    people: list[str] = field(default_factory=list)
    # The result after it ran, from the service's answer
    after: Callable[[Any], dict[str, Any]] | None = None
    undo: str | None = None

    @property
    def audit(self) -> dict[str, Any]:
        return {k: self.data[k] for k in _AUDIT_FIELDS if k in self.data and not isinstance(self.data[k], dict)}


class ActionTool(HearthTool):
    read_only = False

    async def call(self, hass, hub, caller, args, llm_context):
        plan = self.plan(hub.household, args)
        if caller.kind == ADULT:
            return await self._act(hass, hub, caller, plan)
        return _ask_phones(hass, hub, caller, self.name, plan)

    def plan(self, household: Household, args: dict[str, Any]) -> Plan:
        raise NotImplementedError

    async def _act(self, hass: HomeAssistant, hub: HearthHub, caller: Caller, plan: Plan) -> JsonObjectType:
        responds = hass.services.supports_response(DOMAIN, plan.service) != SupportsResponse.NONE
        try:
            response, logged = await run_audited(
                hub,
                caller.via,
                caller.user_id,
                self.name,
                plan.person,
                plan.audit,
                hass.services.async_call(
                    DOMAIN,
                    plan.service,
                    dict(plan.data),
                    blocking=True,
                    context=Context(user_id=caller.user_id),
                    return_response=responds,
                ),
            )
        except vol.Invalid as err:
            raise HomeAssistantError(f"Invalid input: {err}") from err
        result: dict[str, Any] = {"done": plan.text, "service": f"{DOMAIN}.{plan.service}", "data": plan.data}
        if plan.after is not None:
            result.update(plan.after(response))
        elif response:
            result["response"] = response
        if plan.undo:
            result["undo"] = plan.undo
        result["logged"] = logged
        return result


def _ask_phones(hass: HomeAssistant, hub: HearthHub, caller: Caller, tool: str, plan: Plan) -> JsonObjectType:
    """A voice action: the adults' phones are asked (the action and "Don't allow"); an adult's tap runs it as them,
    once, within VOICE_FOR. Nothing runs here."""
    approval = secrets.token_hex(4)
    key = f"{VOICE_PREFIX}{approval}"
    tag = f"{VOICE_TAG}{approval}"
    where = None
    if caller.device_id and (device := dr.async_get(hass).async_get(caller.device_id)) is not None:
        where = device.name_by_user or device.name
    item = Item(
        key,
        f"Asked by voice{f' on {where}' if where else ''}. Allow runs it as you.",
        title=f"Approve: {plan.text}?",
        urgency=NOTICE,
        audience=ADULTS,
        actions=(
            Action("allow", plan.label, f"{DOMAIN}.{plan.service}", dict(plan.data)),
            Action("dont_allow", "Don't allow", dismiss=True),
        ),
        tag=tag,
        # About a kid: never on Home Assistant's bell
        bell=False,
        expires=dt_util.utcnow() + VOICE_FOR,
        about={"person": plan.person, "via": caller.via, "tool": tool, "audit": plan.audit},
        once=True,
    )

    @callback
    def expired(_now: datetime) -> None:
        item.on_clear = None
        layer = attention(hass)
        if layer.item(key) is not None:
            layer.clear(key)
        else:
            layer.clear(tag, phone=True)

    hub.attention.notify(item)
    if not item.reached:
        hub.attention.clear(key)
        raise HomeAssistantError("No adult's phone to ask: add an adult's companion app first")
    item.on_clear = async_call_later(hass, VOICE_FOR, expired)
    return {
        "message": SENT,
        "asked": f"{plan.text}?",
        "runs_when": "an adult taps the button on their phone",
        "expires": dt_util.as_local(item.expires).isoformat(),
    }


_PERSON = vol.Required("person", description="The person's name or entity id")
_UNTIL_HELP = "'end_of_day' (default), 'school_time_end', or a local time HH:MM"


def _until(given: Any) -> str:
    text = str(given or "").strip().lower().replace(" ", "_")
    if text in ("", "end_of_day", "tonight", "midnight"):
        return "end_of_day"
    if text == "school_time_end":
        return text
    try:
        return cv.time(str(given).strip()).strftime("%H:%M")
    except vol.Invalid as err:
        raise HomeAssistantError(f"Until: {_UNTIL_HELP}") from err


def _until_word(until: str) -> str:
    return {"end_of_day": "the end of the day", "school_time_end": "School time ends"}.get(until, until)


def _state_of(household: Household, person: str, group: str) -> dict[str, Any]:
    day = household.days.get(person)
    state = day.limits.get(group) if day else None
    if state is None:
        return {"minutes_left_now": None}
    return {"minutes_left_now": state.minutes_left, "budget_today": state.budget_min, "bonus_today": state.bonus_min}


class AddBonusTool(ActionTool):
    name = "hearth_add_bonus"
    description = (
        "Give a person more minutes today, in the shared pool (All screen time, the default) or one group; with a "
        "device, minutes on that device only. A negative number takes minutes back (to correct a bonus). Today only."
    )
    parameters = vol.Schema(
        {
            _PERSON: str,
            vol.Required("minutes", description="Minutes to add today (negative takes back), -240 to 240"): vol.All(
                vol.Coerce(int), vol.Range(min=-240, max=240)
            ),
            vol.Optional("group", description="A group's name or id; 'all' (default) is All screen time"): str,
            vol.Optional("device", description="Only on this device of theirs (its name or id, hearth_get_person)"): str,
        }
    )

    def plan(self, household, args):
        person = find_person(household, args["person"])
        who = household.person_name(person)
        minutes = args["minutes"]
        if minutes == 0:
            raise HomeAssistantError("Give a number of minutes other than 0")
        group = find_group(household, args.get("group") or ALL)
        data: dict[str, Any] = {"person": person, "minutes": minutes, "group": group}
        what = group_name(household, group)
        device = None
        if args.get("device"):
            if minutes < 0:
                raise HomeAssistantError("Extra time on one device can't be taken back by minutes: end it with hearth_allow_end")
            device = find_target(household, person, args["device"])
            data["device"] = device["id"]
        if minutes > 0:
            text = f"give {who} {minutes} more minutes of {what} today" + (f" on {device['name']}" if device else "")
        else:
            text = f"take {-minutes} minutes of {what} back from {who} today"

        def after(response: Any) -> dict[str, Any]:
            out = {"person": who, "group": what, "minutes": minutes}
            if device is not None:
                out["device"] = device["name"]
                out.update({k: v for k, v in (response or {}).items() if k in ("id", "until")})
            out.update(_state_of(household.hub.household, person, group))
            return out

        return Plan(
            "add_bonus",
            data,
            text,
            f"+{minutes} min" if minutes > 0 else f"{minutes} min",
            person,
            [person],
            after,
            undo=(
                "hearth_allow_end with the id" if device else f"hearth_add_bonus with minutes {-minutes} (same group)"
            ),
        )


def _what(household: Household, person: str | None, args: dict[str, Any]) -> tuple[dict[str, Any], str]:
    """An app or a group from the tool's input: the service's data, and its name."""
    if args.get("app"):
        package, name = find_app(household, person, args["app"])
        return {"app": package}, name
    if args.get("group"):
        group = find_group(household, args["group"])
        return {"group": group}, group_name(household, group)
    return {}, ""


class PauseTool(ActionTool):
    name = "hearth_pause"
    description = (
        "Pause people (everyone by default) now, for some minutes or until a time today: their devices stop and say "
        "why. With an app or a group, only that is paused. Without minutes or until, until the end of the day."
    )
    parameters = vol.Schema(
        {
            vol.Optional("people", description="Names or entity ids; none: everyone"): [str],
            vol.Exclusive("minutes", "how_long", description="For this many minutes, 1 to 720"): vol.All(
                vol.Coerce(int), vol.Range(min=1, max=720)
            ),
            vol.Exclusive("until", "how_long", description="Until this local time, HH:MM"): str,
            vol.Exclusive("app", "what", description="Only this app (name or package)"): str,
            vol.Exclusive("group", "what", description="Only this group (name or id)"): str,
            vol.Optional("reason", description="Shown on their devices (dinner, homework)"): str,
        }
    )

    def plan(self, household, args):
        people = [find_person(household, p) for p in args.get("people") or []]
        people = list(dict.fromkeys(people))
        whats, name = _what(household, people[0] if len(people) == 1 else None, args)
        data: dict[str, Any] = {**whats}
        if people:
            data["people"] = people
        if args.get("minutes"):
            data["minutes"] = args["minutes"]
            how_long = f"for {args['minutes']} minutes"
        elif args.get("until") and (until := _until(args["until"])) != "end_of_day":
            if until == "school_time_end":
                raise HomeAssistantError("A pause lasts some minutes or until a time (HH:MM)")
            data["until"] = until
            how_long = f"until {until}"
        else:
            data["until"] = dt_util.as_local(end_of_day(dt_util.now())).isoformat()
            how_long = "until the end of the day"
        if args.get("reason"):
            data["reason"] = args["reason"]
        who = ", ".join(household.person_name(p) for p in people) if people else "everyone"
        text = f"pause {name + ' for ' if name else ''}{who} {how_long}"
        everyone = people or household.people()

        def after(_response: Any) -> dict[str, Any]:
            current = household.hub.household
            now: dict[str, Any] = {}
            for p in everyone:
                if whats:
                    now[current.person_name(p)] = current.app_pause_views(p)
                else:
                    now[current.person_name(p)] = pause_of(current.hass, p)
            return {"people": who, "what": name or "everything", "paused_now": now}

        return Plan("pause", data, text, "Pause", people[0] if len(people) == 1 else None, people, after,
                    undo="hearth_pause_end with the same people (and app or group)")


class PauseEndTool(ActionTool):
    name = "hearth_pause_end"
    description = (
        "End a pause now: the family pause of these people (everyone by default), or with an app or a group, only "
        "that app's or group's pause."
    )
    parameters = vol.Schema(
        {
            vol.Optional("people", description="Names or entity ids; none: everyone"): [str],
            vol.Exclusive("app", "what", description="That app's pause only"): str,
            vol.Exclusive("group", "what", description="That group's pause only"): str,
        }
    )

    def plan(self, household, args):
        people = list(dict.fromkeys(find_person(household, p) for p in args.get("people") or []))
        whats, name = _what(household, people[0] if len(people) == 1 else None, args)
        data: dict[str, Any] = {**whats}
        if people:
            data["people"] = people
        who = ", ".join(household.person_name(p) for p in people) if people else "everyone"
        text = f"end the pause of {name + ' for ' if name else ''}{who}"

        def after(_response: Any) -> dict[str, Any]:
            current = household.hub.household
            return {
                "people": who,
                "what": name or "the family pause",
                "still_paused": {
                    current.person_name(p): pause_of(current.hass, p) if not whats else current.app_pause_views(p)
                    for p in people or current.people()
                },
            }

        return Plan("pause_end", data, text, "End pause", people[0] if len(people) == 1 else None, people, after)


class AllowTool(ActionTool):
    name = "hearth_allow"
    description = (
        "Let one person use an app or a group until a time (the end of the day by default) whatever Hearth holds "
        "(budget, pause). It lifts Hearth's own holds only: never an app or game a parent blocked in Family Link, "
        "Family Safety or the Nintendo app (refused). With a device (a group only), only on that device."
    )
    parameters = vol.Schema(
        {
            _PERSON: str,
            vol.Exclusive("app", "what", description="An app's name or package"): str,
            vol.Exclusive("group", "what", description="A group's name or id, or 'all'"): str,
            vol.Optional("until", description=_UNTIL_HELP): str,
            vol.Optional("device", description="Only on this device of theirs (a group only)"): str,
            vol.Optional("reason"): str,
        }
    )

    async def call(self, hass, hub, caller, args, llm_context):
        # A game a parent may have blocked in the Nintendo app (off its Switch's allow list): asked of the Switch,
        # so before the plan (which only reads states)
        if args.get("app"):
            household = hub.household
            person = find_person(household, args["person"])
            if (block := await nintendo_block_of(household, person, args["app"])) is not None:
                raise _refuse_nintendo(block, household.person_name(person))
        return await super().call(hass, hub, caller, args, llm_context)

    def plan(self, household, args):
        person = find_person(household, args["person"])
        who = household.person_name(person)
        if not args.get("app") and not args.get("group"):
            raise HomeAssistantError("Name an app or a group")
        if args.get("app") and (block := parent_block_of(household, person, args["app"])):
            raise _refuse_blocked(block, who)
        whats, name = _what(household, person, args)
        if "app" in whats and (block := parent_block_of(household, person, whats["app"], name, args["app"])):
            raise _refuse_blocked(block, who)
        until = _until(args.get("until"))
        data: dict[str, Any] = {"people": [person], **whats, "until": until}
        device = None
        if args.get("device"):
            if "app" in whats:
                raise HomeAssistantError("On one device, allow a group (an app goes with every device)")
            device = find_target(household, person, args["device"])
            data["device"] = device["id"]
        if args.get("reason"):
            data["reason"] = args["reason"]
        text = f"let {who} use {name} until {_until_word(until)}" + (f" on {device['name']}" if device else "")

        def after(response: Any) -> dict[str, Any]:
            current = household.hub.household
            out = {"person": who, "what": name, **{k: v for k, v in (response or {}).items() if k in ("id", "until")}}
            if device is not None:
                out["device"] = device["name"]
            # Whether it's open now, or what else still holds it (a parent's limit, Google TV's own)
            now = current.explain(person, whats.get("app"), whats.get("group"))
            out["now"] = {k: now[k] for k in ("allowed", "until", "blocked_by") if k in now}
            return out

        return Plan("allow", data, text, "Allow", person, [person], after, undo="hearth_allow_end with the id")


class AllowEndTool(ActionTool):
    name = "hearth_allow_end"
    description = (
        "End an allow early: by its id (from hearth_allow, or a parent's grant or extra time on one device), or a "
        "person's allows of an app or a group (all of theirs without one)."
    )
    parameters = vol.Schema(
        {
            vol.Optional("id", description="The allow's id"): str,
            vol.Optional("person", description="The person's name or entity id"): str,
            vol.Exclusive("app", "what"): str,
            vol.Exclusive("group", "what"): str,
        }
    )

    def plan(self, household, args):
        if not args.get("id") and not args.get("person"):
            raise HomeAssistantError("Give the allow's id or a person")
        person = find_person(household, args["person"]) if args.get("person") else None
        whats, name = _what(household, person, args)
        data: dict[str, Any] = {**whats}
        if args.get("id"):
            data["id"] = args["id"]
        if person:
            data["people"] = [person]
        who = household.person_name(person) if person else None
        text = "end " + (f"{who}'s allow" if who else "the allow") + (f" of {name}" if name else "") + (
            f" ({args['id']})" if args.get("id") else ""
        )

        def after(response: Any) -> dict[str, Any]:
            return {"ended": (response or {}).get("ended", [])}

        return Plan("allow_end", data, text, "End allow", person, [person] if person else [], after)


class AnswerRequestTool(ActionTool):
    name = "hearth_answer_request"
    description = (
        "Answer a request for more time (its id from hearth_get_requests): minutes to give, or deny. The first answer "
        "wins. Approving a Family Safety request for a particular game or app is refused here: answer it in the "
        "Family Safety app."
    )
    parameters = vol.Schema(
        {
            vol.Required("request_id"): str,
            vol.Exclusive("minutes", "answer", description="Minutes to give, 1 to 600"): vol.All(
                vol.Coerce(int), vol.Range(min=1, max=600)
            ),
            vol.Exclusive("deny", "answer", description="true to say no"): bool,
        }
    )

    def plan(self, household, args):
        hub = household.hub
        ask = hub.asks.get(args["request_id"])
        if ask is None or ask.status != PENDING:
            raise HomeAssistantError("That request isn't open any more (answered or expired)")
        who = household.person_name(ask.person)
        if not args.get("deny") and not args.get("minutes"):
            raise HomeAssistantError("Give minutes or deny")
        if args.get("deny"):
            data: dict[str, Any] = {"request_id": ask.id, "deny": True}
            text, label = f"say no to {who}'s request", "Say no"
        else:
            if ask.external and (ask.app_name or ask.app):
                raise HomeAssistantError(
                    f"{who}'s request is for {ask.app_name or ask.app} in Family Safety: approving it there could let "
                    "them into a game or app a parent blocked. Answer it in the Family Safety app (or deny it here)."
                )
            if ask.app and (block := parent_block_of(household, ask.person, ask.app)):
                raise _refuse_blocked(block, who)
            data = {"request_id": ask.id, "minutes": args["minutes"]}
            text = f"give {who} {args['minutes']} more minutes of {group_name(household, ask.group)} (their request)"
            label = f"+{args['minutes']} min"

        def after(response: Any) -> dict[str, Any]:
            out = {"person": who, "group": group_name(household, ask.group), **(response or {})}
            if not args.get("deny") and not ask.external:
                out.update(_state_of(household.hub.household, ask.person, ask.group))
            return out

        return Plan("answer_request", data, text, label, ask.person, [ask.person], after)


class DismissSuggestionTool(ActionTool):
    name = "hearth_dismiss_suggestion"
    description = "Put one of Hearth's suggestions off for the rest of today ('not today'), by the person and its key."
    parameters = vol.Schema({_PERSON: str, vol.Required("key", description="The suggestion's key"): str})

    def plan(self, household, args):
        person = find_person(household, args["person"])
        who = household.person_name(person)
        return Plan(
            "dismiss_suggestion",
            {"person": person, "key": args["key"]},
            f"put off the suggestion {args['key']} for {who} today",
            "Not today",
            person,
            [person],
            lambda _r: {"person": who, "key": args["key"], "until": "the end of the day"},
        )


class SchoolTimeOffTool(ActionTool):
    name = "hearth_school_time_off"
    description = (
        "No School time for a person on a day (today by default), from a time if given: Hearth turns Family Link's "
        "School time off and puts it back on their next school day."
    )
    parameters = vol.Schema(
        {
            _PERSON: str,
            vol.Optional("date", description="YYYY-MM-DD, today by default"): str,
            vol.Optional("from", description="From this local time, HH:MM"): str,
        }
    )

    def plan(self, household, args):
        person = find_person(household, args["person"])
        who = household.person_name(person)
        data: dict[str, Any] = {"people": [person]}
        try:
            if args.get("date"):
                data["date"] = cv.date(args["date"]).isoformat()
            if args.get("from"):
                data["from"] = cv.time(args["from"]).strftime("%H:%M")
        except vol.Invalid as err:
            raise HomeAssistantError(f"Invalid date or time: {err}") from err
        text = f"no School time for {who} {data.get('date', 'today')}" + (f" from {data['from']}" if "from" in data else "")

        def after(response: Any) -> dict[str, Any]:
            return {"person": who, **(response or {}), "school_time_off": household.hub.household.off_views(person)}

        return Plan("school_time_off", data, text, "No School time", person, [person], after,
                    undo="hearth_school_time_off_cancel with the person and date")


class SchoolTimeOffCancelTool(ActionTool):
    name = "hearth_school_time_off_cancel"
    description = "Put School time back: a person's School time off (everyone's without a person), on a date or every one."
    parameters = vol.Schema(
        {
            vol.Optional("person", description="The person's name or entity id"): str,
            vol.Optional("date", description="YYYY-MM-DD"): str,
        }
    )

    def plan(self, household, args):
        person = find_person(household, args["person"]) if args.get("person") else None
        data: dict[str, Any] = {}
        if person:
            data["people"] = [person]
        if args.get("date"):
            try:
                data["date"] = cv.date(args["date"]).isoformat()
            except vol.Invalid as err:
                raise HomeAssistantError(f"Invalid date: {err}") from err
        who = household.person_name(person) if person else "everyone"
        text = f"put School time back for {who}" + (f" on {data['date']}" if "date" in data else "")
        return Plan("school_time_off_cancel", data, text, "School time back", person, [person] if person else [],
                    lambda response: {"person": who, **(response or {})})


READ_TOOLS: tuple[type[HearthTool], ...] = (HouseholdTool, PersonTool, ExplainTool, SuggestionsTool, RequestsTool)
ACTION_TOOLS: tuple[type[ActionTool], ...] = (
    AddBonusTool,
    PauseTool,
    PauseEndTool,
    AllowTool,
    AllowEndTool,
    AnswerRequestTool,
    DismissSuggestionTool,
    SchoolTimeOffTool,
    SchoolTimeOffCancelTool,
)

PROMPT = (
    "Hearth is this household's screen time: kids' minutes per day across TVs, phones, Xbox, Switch and PCs, pooled "
    "as All screen time and groups. The data is about children and is for the adult asking. Use the hearth_get tools "
    "and hearth_explain to answer. Make the narrowest change asked for (one person, one app or group, today). Each "
    "action acts at once and returns exactly what changed (who, what, device or pool, minutes, until): tell the adult, "
    "and offer to correct it (each result says how to undo). Budgets can't be changed here, and Hearth never unblocks "
    "an app or game a parent blocked: say so instead of looking for another way."
)
VOICE_PROMPT = (
    " This is a voice assistant, and the speaker may be a child: an action doesn't run here, it's sent to the adults' "
    "phones and runs when an adult taps it. Tell the speaker it was sent to a phone for approval; never say it's done."
)


class HearthAPI(llm.API):
    """The "hearth" LLM API: tools for an adult (or for voice, while it's on); none for anyone else."""

    def __init__(self, hass: HomeAssistant) -> None:
        super().__init__(hass=hass, id=API_ID, name=API_NAME)

    async def async_get_api_instance(self, llm_context: llm.LLMContext) -> llm.APIInstance:
        hub = _hub(self.hass)
        caller = await caller_of(self.hass, hub, llm_context)
        if not _may_use(hub, caller):
            prompt = (
                "Hearth isn't available here."
                if caller.kind != VOICE
                else "Hearth is off for voice assistants (an adult can turn it on: Configure > Voice assistants)."
            )
            return llm.APIInstance(api=self, api_prompt=prompt, llm_context=llm_context, tools=[])
        tools: list[llm.Tool] = [tool() for tool in (*READ_TOOLS, *ACTION_TOOLS)]
        return llm.APIInstance(
            api=self,
            api_prompt=PROMPT + (VOICE_PROMPT if caller.kind == VOICE else ""),
            llm_context=llm_context,
            tools=tools,
        )


@callback
def async_register(hass: HomeAssistant) -> Callable[[], None] | None:
    """Registers the API once (it reads the loaded household on every call, so an options reload doesn't matter)."""
    if any(api.id == API_ID for api in llm.async_get_apis(hass)):
        return None
    return llm.async_register_api(hass, HearthAPI(hass))
