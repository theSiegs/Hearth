"""Glint for assistants: the "glint" LLM API that Home Assistant's MCP Server and Assist offer beside "hearth"
(llm_api.py), switchable on its own (Glint's docs/contracts/glint-agent-ha.md §8, contract 1).

Every tool takes `phone`: a Glint phone's name as Hearth's device list shows it (case does not matter), or the name of
the person whose only Glint phone it is; optional when the caller has exactly one. Reads answer from the phone's
`glint-state` document (with its age, "as of 6:02 pm"), so nothing wakes the phone; a write becomes a request in its
inbox (glint_agent.py), rings its doorbell when a companion app is linked, then waits up to WAIT_FOR for the phone's
result: `said` (Glint's own words, never paraphrased) and `undo`, or "queued", or "waiting for <owner> to allow it on
the phone".

Who may use it (§6):
- An adult in Home Assistant (llm_api.caller_of: an administrator, or an adult on Hearth's page): their own Glint
  phones and kids' phones; never another adult's phone. Their writes are `origin: text` through the MCP Server and
  `voice` through Assist (a typed Assist chat can't be told from a spoken one, so it counts as voice and asks).
- A voice call with no user (a satellite), wherever the voice agent has this API ticked: adults' phones only; its
  writes carry `origin: voice`, so Glint asks on the phone first.
- Anyone else: no tools, and every tool refuses them.

Hearth refuses up front what Glint would refuse anyway on a kid's phone: any voice write (`voice_on_kid_phone`), and
the changes that loosen it that Hearth can see (do not disturb off, every system setting or sound): `needs_parent`.
Each write is logged in Hearth's history as an `assist` event (tool, device, request id, via, user).

Linking a companion app as a phone's doorbell (`hearth/glint/phones`, `hearth/glint/bell`), and forgetting a stale
phone (`hearth/glint/forget`, the same removal as deleting its device): an adult, for their own phones and kids'
(an administrator, any phone).

A phone with no `glint-state` document counts as agents off: every tool refuses and nothing is queued (Glint publishes
`channel: "off"` once it's paired with agents off). Several phones with one name: the caller's own among them (the one
seen last), else the tool asks for the id, listing each as "name · person · last seen".
"""

from __future__ import annotations

from collections.abc import Callable
from dataclasses import dataclass
from datetime import datetime, timedelta
from typing import TYPE_CHECKING, Any

import voluptuous as vol

from homeassistant.components import websocket_api
from homeassistant.core import HomeAssistant, callback
from homeassistant.exceptions import HomeAssistantError
from homeassistant.helpers import config_validation as cv
from homeassistant.helpers import device_registry as dr
from homeassistant.helpers import llm
from homeassistant.util import dt as dt_util
from homeassistant.util.json import JsonObjectType

from .adult_offer import note_refused
from .auth import is_adult_user
from .client_settings import SettingsError
from .const import CONF_KIND, DOMAIN, KIND_TV
from .glint_agent import (
    APPLIED,
    ASKED,
    BELL_PREFIX,
    EXPIRED,
    ORIGIN_TEXT,
    ORIGIN_VOICE,
    REFUSED,
    GlintAgent,
    InboxFull,
    parse_time,
)
from .history import ASSIST
from .llm_api import ADULT, VIA_MCP, VOICE, Caller, _fold, caller_of
from .websocket import own_person

if TYPE_CHECKING:
    from .hub import HearthHub

API_ID = "glint"
API_NAME = "Glint"
# The agent a request names (Glint shows it, rate-limits by it and asks once per new one): Home Assistant's MCP
# Server can't say which client is behind it, Assist is Assist
AGENT_MCP = "mcp"
AGENT_ASSIST = "assist"
OFF = "home assistant access is off on that phone (its owner turns it on in Glint: settings › connections › agents)"
ACTIVITY_SHOWN = 20


def _hub(hass: HomeAssistant) -> HearthHub | None:
    entries = hass.config_entries.async_loaded_entries(DOMAIN)
    return entries[0].runtime_data if entries else None


@dataclass(frozen=True)
class Who:
    """The caller as the glint tools see them."""

    caller: Caller
    # Their person (None: no user, or a user without a person)
    person: str | None
    user_name: str | None

    @property
    def voice_only(self) -> bool:
        """A call with no user: adults' phones only."""
        return self.caller.kind == VOICE

    @property
    def origin(self) -> str:
        return ORIGIN_TEXT if self.caller.via == VIA_MCP else ORIGIN_VOICE

    @property
    def agent(self) -> str:
        return AGENT_MCP if self.caller.via == VIA_MCP else AGENT_ASSIST


async def who_of(hass: HomeAssistant, hub: HearthHub | None, llm_context: llm.LLMContext) -> Who:
    caller = await caller_of(hass, hub, llm_context)
    person = user_name = None
    if caller.user_id is not None and (user := await hass.auth.async_get_user(caller.user_id)) is not None:
        person = own_person(hass, user)
        user_name = user.name
    return Who(caller, person, user_name)


def _may_use(hub: HearthHub | None, who: Who) -> bool:
    return hub is not None and who.caller.kind in (ADULT, VOICE)


# Finding the phone


def find_phone(hub: HearthHub, who: Who, given: Any) -> str:
    """The Glint phone [given] names, among those [who] may reach; with none given, their only one."""
    agent: GlintAgent = hub.glint_agent
    household = hub.household
    reachable = agent.reachable(who.person, voice=who.voice_only)
    names = "; ".join(describe(hub, d) for d in reachable)
    if not reachable:
        raise HomeAssistantError(
            "No Glint phone here: a phone needs Glint paired with Hearth (an adult's own phone, or a kid's)"
            if not who.voice_only
            else "No adult's Glint phone paired with Hearth"
        )
    text = str(given or "").strip()
    if not text:
        own = [d for d in reachable if who.person is not None and agent.person_of(d) == who.person]
        pool = own or reachable
        if len(pool) == 1:
            return pool[0]
        raise HomeAssistantError(f"Name the phone ({names})")
    wanted = _fold(text)
    if any(wanted == _fold(d) for d in reachable):
        return next(d for d in reachable if wanted == _fold(d))
    named = [d for d in reachable if wanted == _fold(agent.name_of(d))]
    if len(named) > 1:
        # Two phones with one name (an unrenamed model name, say): the caller's own if it's among them (the one seen
        # last when several are, a stale pairing aside), else ask for the id
        own = [d for d in named if who.person is not None and agent.person_of(d) == who.person]
        if own:
            return max(own, key=lambda d: (agent.last_seen(d) or _NEVER, d))
        raise HomeAssistantError(
            f"More than one phone is called {text}: give its id ("
            + "; ".join(f"{describe(hub, d)} [{d}]" for d in sorted(named))
            + ")"
        )
    if named:
        return named[0]
    # A person's name, when they have one Glint phone
    by_person: dict[str, list[str]] = {}
    for device_id in reachable:
        if (person := agent.person_of(device_id)) is not None:
            by_person.setdefault(person, []).append(device_id)
    for person, devices in by_person.items():
        if wanted in (_fold(person), _fold(person.removeprefix("person.")), _fold(household.person_name(person))):
            if len(devices) == 1:
                return devices[0]
            raise HomeAssistantError(
                f"{household.person_name(person)} has more than one Glint phone ("
                + "; ".join(f"{describe(hub, d)} [{d}]" for d in devices)
                + ")"
            )
    if any(wanted in (_fold(d), _fold(agent.name_of(d))) for d in agent.phones()):
        raise HomeAssistantError(
            "That's another adult's phone: only they can reach it, with their own Home Assistant sign-in"
            if not who.voice_only
            else "A voice assistant can't reach that phone"
        )
    raise HomeAssistantError(f"No Glint phone called {text} ({names})")


_NEVER = datetime.min.replace(tzinfo=dt_util.UTC)


def _when(when: datetime) -> str:
    """'6:02 pm' (today), else 'Nov 14, 6:02 pm'."""
    local = dt_util.as_local(when)
    clock = f"{local.hour % 12 or 12}:{local.minute:02d} {'am' if local.hour < 12 else 'pm'}"
    if local.date() == dt_util.now().date():
        return clock
    return f"{local.strftime('%b')} {local.day}, {clock}"


def _as_of(updated: Any) -> str | None:
    """'as of 6:02 pm' (today), else 'as of Nov 14, 6:02 pm'."""
    when = parse_time(updated)
    return None if when is None else f"as of {_when(when)}"


def describe(hub: HearthHub, device_id: str) -> str:
    """'Pixel 9 · Sam · last seen 6:02 pm': a phone as the tools list it."""
    agent: GlintAgent = hub.glint_agent
    person = agent.person_of(device_id)
    seen = agent.last_seen(device_id)
    return " · ".join(
        (
            agent.name_of(device_id),
            hub.household.person_name(person) if person else "no one",
            f"last seen {_when(seen)}" if seen else "never seen",
        )
    )


# Tools


class GlintTool(llm.Tool):
    """A glint tool: checks the caller and finds the phone on every call."""

    read_only = True
    parameters = vol.Schema({vol.Optional("phone", description="The phone's name (or its person's)"): str})

    async def async_call(
        self, hass: HomeAssistant, tool_input: llm.ToolInput, llm_context: llm.LLMContext
    ) -> JsonObjectType:
        hub = _hub(hass)
        if hub is None:
            raise HomeAssistantError("Hearth isn't set up")
        who = await who_of(hass, hub, llm_context)
        if not _may_use(hub, who):
            raise HomeAssistantError("Only an adult of the household may use Glint's tools")
        try:
            args = self.parameters(dict(tool_input.tool_args or {}))
        except vol.Invalid as err:
            raise HomeAssistantError(f"Invalid input: {err}") from err
        phone = find_phone(hub, who, args.get("phone"))
        return await self.call(hass, hub, who, phone, args)

    async def call(self, hass: HomeAssistant, hub: HearthHub, who: Who, phone: str, args: dict[str, Any]) -> JsonObjectType:
        raise NotImplementedError

    # Reads

    async def read(
        self, hass: HomeAssistant, hub: HearthHub, who: Who, phone: str, section: str, action: str
    ) -> JsonObjectType:
        """The state document's [section]. No state document means agents are off there (Glint publishes one,
        `channel: "off"` included, once it's paired): refused, and nothing is sent to the phone."""
        agent: GlintAgent = hub.glint_agent
        state = agent.state(phone)
        _not_off(state)
        out = {**_heading(agent, phone, state), section: state.get(section)}
        if section not in state:
            out["note"] = f"glint on that phone didn't publish its {section} ({action} answers it there)"
        return out


def _not_off(state: dict[str, Any] | None) -> None:
    """Refuses unless the phone published a state document with agents on: none at all counts as off."""
    if state is None or state.get("channel") == "off":
        raise HomeAssistantError(OFF)


def _heading(agent: GlintAgent, phone: str, state: dict[str, Any]) -> dict[str, Any]:
    out: dict[str, Any] = {"phone": agent.name_of(phone)}
    if (as_of := _as_of(state.get("updated"))) is not None:
        out["as_of"] = as_of
    for key in ("updated", "glint", "kid_phone"):
        if key in state:
            out[key] = state[key]
    return out


# Writes


def _answer(agent: GlintAgent, phone: str, request: dict[str, Any], result: dict[str, Any] | None) -> dict[str, Any]:
    """What the tool says of one request: the phone's result in its own words, or that it's queued or asked."""
    name = agent.name_of(phone)
    request_id = request["id"]
    if result is None:
        return {
            "status": "queued",
            "request": request_id,
            "message": f"queued for {name}: glint applies it the next time Start is open (request {request_id})",
        }
    status = result.get("status")
    out: dict[str, Any] = {"status": status, "request": request_id}
    if status == APPLIED:
        out["said"] = result.get("said") or []
        for key in ("undo", "result", "result_cut"):
            if key in result:
                out[key] = result[key]
    elif status == ASKED:
        person = agent.person_of(phone)
        owner = agent.hub.household.person_name(person) if person else "its owner"
        out["message"] = f"waiting for {owner} to allow it on the phone"
    elif status in (REFUSED, EXPIRED):
        for key in ("code", "message", "retry_after_ms"):
            if key in result:
                out[key] = result[key]
    return out


async def send(
    hass: HomeAssistant,
    hub: HearthHub,
    who: Who,
    phone: str,
    tool: str,
    requests: list[tuple[str, dict[str, Any], datetime | None]],
) -> JsonObjectType:
    """Adds [requests] (action, args, expires) to the phone's inbox, rings its doorbell, waits for the results."""
    agent: GlintAgent = hub.glint_agent
    name = agent.name_of(phone)
    if agent.is_kid_phone(phone) and who.origin == ORIGIN_VOICE:
        raise HomeAssistantError(
            "voice_on_kid_phone: a kid's phone takes no changes by voice (the ask would land on the kid's screen); "
            "use the app or type instead"
        )
    added: list[dict[str, Any]] = []
    futures = {}
    for action, args, expires in requests:
        try:
            request = agent.add(
                phone,
                action,
                args,
                agent=who.agent,
                origin=who.origin,
                user=who.caller.user_id,
                user_name=who.user_name,
                expires=expires,
            )
        except InboxFull as err:
            raise HomeAssistantError(
                f"inbox_full: {name} has {err.waiting} requests waiting; it applies them when Glint next opens"
            ) from err
        except ValueError as err:
            raise HomeAssistantError("bad_args: the change is too big (8 KiB at most)") from err
        except SettingsError as err:
            raise HomeAssistantError(f"Hearth couldn't keep the request for {name} ({err.code})") from err
        futures[request["id"]] = agent.watch(phone, request["id"])
        added.append(request)
        hub.household.history.log(
            ASSIST,
            agent.person_of(phone) or "",
            via=who.caller.via,
            user=who.caller.user_id,
            tool=tool,
            device=phone,
            request_id=request["id"],
        )
    await agent.ring(phone)
    results = await agent.wait(phone, futures)
    answers = [_answer(agent, phone, r, results.get(r["id"])) for r in added]
    if len(answers) == 1:
        return {"phone": name, **answers[0]}
    return {"phone": name, "results": answers}


def _needs_parent(hub: HearthHub, phone: str, what: str) -> None:
    if hub.glint_agent.is_kid_phone(phone):
        raise HomeAssistantError(
            f"needs_parent: a kid's phone takes only tightening changes, and {what} isn't one; a parent changes it on "
            "the phone with the parent PIN"
        )


def _ensure_on(hub: HearthHub, phone: str) -> None:
    _not_off(hub.glint_agent.state(phone))


_PHONE = vol.Optional("phone", description="The phone's name (or its person's); optional with one phone")


class GetStartTool(GlintTool):
    name = "glint_get_start"
    description = (
        "A phone's Start in Glint: its pages and columns, and each tile placed there (id, type, name, size, page, "
        "column, row; stacks with their tiles), as Glint last published it."
    )

    async def call(self, hass, hub, who, phone, args):
        return await self.read(hass, hub, who, phone, "start", "start.get")


# start.change's ops when no phone published its glint.hello list (Glint's AgentActions)
START_OPS = (
    "add", "duplicate", "move", "resize", "remove", "restyle", "stack", "unstack", "take_out", "name_stack", "deals_at",
    "remove_page",
)
MAX_OPS_TEXT = 1500


def hello_action(state: dict[str, Any] | None, action_id: str) -> dict[str, Any] | None:
    """An action of the phone's glint.hello list ({id, class, about, args}) as its state document carries it (under
    `hello`, or `actions` at the top), else None."""
    if not isinstance(state, dict):
        return None
    hello = state.get("hello") if isinstance(state.get("hello"), dict) else state
    actions = hello.get("actions")
    for action in actions if isinstance(actions, list) else []:
        if isinstance(action, dict) and action.get("id") == action_id:
            return action
    return None


def start_ops_text(states: list[dict[str, Any] | None]) -> str:
    """What glint_change_start says of its ops: the phone's own start.change from glint.hello, else START_OPS."""
    for state in states:
        action = hello_action(state, "start.change")
        # A state document near its size cap drops args (args_cut): then the fixed list says more
        if action is not None and not action.get("args_cut") and (action.get("about") or action.get("args")):
            about = str(action.get("about") or "").strip()
            args = str(action.get("args") or "").strip()
            text = f"Glint's start.change: {about}" + (f". Args: {args}" if args else "")
            return text[:MAX_OPS_TEXT]
    return f"Ops: {', '.join(START_OPS)}"


class ChangeStartTool(GlintTool):
    read_only = False
    name = "glint_change_start"
    description = (
        "Change a phone's Start: a batch of ops on tiles and pages, by tile id from glint_get_start. Glint places or "
        "deals the tiles and says exactly what changed, with an undo. Removing more than 4 tiles or a page asks on the "
        "phone first. "
    )

    def __init__(self, ops_text: str | None = None) -> None:
        self.description = ChangeStartTool.description + (ops_text or start_ops_text([]))
    parameters = vol.Schema(
        {_PHONE: str, vol.Required("ops", description="The ops, as Glint's start.change takes them"): vol.All([dict], vol.Length(min=1))}
    )

    async def call(self, hass, hub, who, phone, args):
        _ensure_on(hub, phone)
        return await send(hass, hub, who, phone, self.name, [("start.change", {"ops": args["ops"]}, None)])


class SetLookTool(GlintTool):
    name = "glint_set_look"
    description = (
        "A phone's look in Glint (motion, clarity, accent and the rest of its settings by name). Without values it "
        "reads them; with values it sets those, with an undo."
    )
    parameters = vol.Schema({_PHONE: str, vol.Optional("values", description="Settings by name to set"): dict})

    async def call(self, hass, hub, who, phone, args):
        if not args.get("values"):
            return await self.read(hass, hub, who, phone, "look", "settings.get")
        _ensure_on(hub, phone)
        return await send(hass, hub, who, phone, self.name, [("look.set", {"values": args["values"]}, None)])


class NotificationRulesTool(GlintTool):
    name = "glint_notification_rules"
    description = (
        "A phone's notification rules in Glint: tiers, hidden notifications, apps shown only on their own tile. "
        "Without ops it reads them (never any notification's text); with ops it changes them, with an undo. On a "
        "kid's phone only tightening changes (hiding, a quieter tier) are taken."
    )
    parameters = vol.Schema(
        {_PHONE: str, vol.Optional("ops", description="The ops, as Glint's notify.change takes them"): [dict]}
    )

    async def call(self, hass, hub, who, phone, args):
        if not args.get("ops"):
            return await self.read(hass, hub, who, phone, "notify", "notify.get")
        _ensure_on(hub, phone)
        return await send(hass, hub, who, phone, self.name, [("notify.change", {"ops": args["ops"]}, None)])


class UndoTool(GlintTool):
    read_only = False
    name = "glint_undo"
    description = (
        "Undo a change this assistant made on a phone through Glint: by the undo id a change returned, or the last "
        "one without it."
    )
    parameters = vol.Schema({_PHONE: str, vol.Optional("undo", description="The undo id (u-…), or 'last'"): str})

    async def call(self, hass, hub, who, phone, args):
        _ensure_on(hub, phone)
        undo = {"undo": args["undo"]} if args.get("undo") else {}
        return await send(hass, hub, who, phone, self.name, [("undo", undo, None)])


class ActivityTool(GlintTool):
    name = "glint_activity"
    description = (
        "What agents did on a phone through Glint: its latest activity (who, what, the result, the undo), the results "
        "of requests sent from here, and the requests still waiting for the phone."
    )

    async def call(self, hass, hub, who, phone, args):
        agent: GlintAgent = hub.glint_agent
        state = agent.state(phone)
        _not_off(state)
        out: dict[str, Any] = _heading(agent, phone, state)
        out["activity"] = state.get("activity") or []
        results = sorted(agent.results(phone).values(), key=lambda r: str(r.get("at") or ""))
        out["results"] = results[-ACTIVITY_SHOWN:]
        now = dt_util.utcnow()
        out["waiting"] = [
            {k: r[k] for k in ("id", "action", "agent", "origin", "created", "expires") if k in r}
            for r in agent.pending(phone)
            if (r.get("id") not in agent.results(phone) or agent.results(phone)[r["id"]].get("status") == ASKED)
            and (until := parse_time(r.get("expires"))) is not None
            and until > now
        ]
        return out


def _next_time(text: str) -> tuple[str, datetime]:
    """'HH:MM' and its next local occurrence."""
    try:
        clock = cv.time(text.strip())
    except vol.Invalid as err:
        raise HomeAssistantError("until: a local time, HH:MM") from err
    now = dt_util.now()
    when = now.replace(hour=clock.hour, minute=clock.minute, second=0, microsecond=0)
    if when <= now:
        when += timedelta(days=1)
    return clock.strftime("%H:%M"), when


class DndTool(GlintTool):
    read_only = False
    name = "glint_dnd"
    description = (
        "Glint's own do not disturb mode on a phone, \"glint quiet\": on for some minutes or until a time, or off. "
        "Glint can't turn off a do not disturb the person or another app turned on, and says so. On a kid's phone "
        "only turning it on is taken."
    )
    parameters = vol.Schema(
        {
            _PHONE: str,
            vol.Required("on", description="true: on; false: off"): bool,
            vol.Exclusive("minutes", "how_long", description="For this many minutes, 1 to 1440"): vol.All(
                vol.Coerce(int), vol.Range(min=1, max=1440)
            ),
            vol.Exclusive("until", "how_long", description="Until this local time, HH:MM"): str,
        }
    )

    async def call(self, hass, hub, who, phone, args):
        _ensure_on(hub, phone)
        expires = None
        if not args["on"]:
            _needs_parent(hub, phone, "turning do not disturb off")
            request = {"on": False}
        elif args.get("minutes"):
            request = {"on": True, "minutes": args["minutes"]}
            # Not worth running once the time it was for has passed
            expires = dt_util.utcnow() + timedelta(minutes=args["minutes"])
        elif args.get("until"):
            until, when = _next_time(args["until"])
            request = {"on": True, "until": until}
            expires = dt_util.as_utc(when)
        else:
            request = {"on": True}
        return await send(hass, hub, who, phone, self.name, [("phone.dnd", request, expires)])


class SystemSettingTool(GlintTool):
    name = "glint_system_setting"
    description = (
        "A phone's own settings through Glint. With no values, ringer or volume it reads them (do not disturb, "
        "ringer, volumes, brightness, auto-brightness, auto-rotate, screen timeout, sounds). values sets brightness "
        "(0-100), auto_brightness, auto_rotate, screen_timeout_s (15-1800), ringtone, notification_sound or "
        "alarm_sound (a sound's title from the phone's own list); ringer is ring, vibrate or silent; volume sets "
        "media, ring, alarm, notification or call by index. Each change says old → new with an undo. Never Wi-Fi, "
        "Bluetooth, mobile data, airplane mode, location or battery saver. Not on a kid's phone."
    )
    parameters = vol.Schema(
        {
            _PHONE: str,
            vol.Optional("values", description="Settings by name: brightness, auto_brightness, auto_rotate, "
                         "screen_timeout_s, ringtone, notification_sound, alarm_sound"): dict,
            vol.Optional("ringer", description="ring, vibrate or silent"): vol.In(("ring", "vibrate", "silent")),
            vol.Optional("volume", description="Streams by name (media, ring, alarm, notification, call): index"): dict,
        }
    )

    async def call(self, hass, hub, who, phone, args):
        requests: list[tuple[str, dict[str, Any], datetime | None]] = []
        if args.get("values"):
            requests.append(("phone.settings", {"values": args["values"]}, None))
        sound = {k: args[k] for k in ("ringer", "volume") if args.get(k)}
        if sound:
            requests.append(("phone.sound", sound, None))
        if not requests:
            return await self.read(hass, hub, who, phone, "phone", "phone.get")
        _ensure_on(hub, phone)
        _needs_parent(hub, phone, "a change to its settings or sounds")
        return await send(hass, hub, who, phone, self.name, requests)


TOOLS: tuple[type[GlintTool], ...] = (
    GetStartTool,
    ChangeStartTool,
    SetLookTool,
    NotificationRulesTool,
    UndoTool,
    ActivityTool,
    DndTool,
    SystemSettingTool,
)

PROMPT = (
    "Glint is the home screen (Start) on this household's phones. These tools read a phone's Start, look, "
    "notification rules and phone settings as Glint last published them (each answer says how old: 'as of'), and send "
    "changes to the phone: Glint applies each when Start is next open (often at once), keeps an undo, and returns "
    "what it did in `said`. Tell the person `said` as it is, and offer the undo. 'queued' means the phone hasn't "
    "picked the change up yet; 'asked_on_phone' means its owner must allow it on the phone; 'refused' says why. "
    "Use Glint's words: tiles are placed or dealt on pages, and can be stacked. Make the narrowest change asked for. "
    "A kid's phone takes only tightening changes. Glint never changes Wi-Fi, Bluetooth, mobile data, airplane mode, "
    "location or battery saver, and never reads texts, calls or notification text: say so instead of looking for "
    "another way."
)
VOICE_PROMPT = (
    " This is a voice assistant: every change asks on the phone first, so say it was sent to the phone to allow, never "
    "that it's done. A kid's phone takes no changes by voice."
)


class GlintAPI(llm.API):
    """The "glint" LLM API: tools for an adult or a voice call; none for anyone else."""

    def __init__(self, hass: HomeAssistant) -> None:
        super().__init__(hass=hass, id=API_ID, name=API_NAME)

    async def async_get_api_instance(self, llm_context: llm.LLMContext) -> llm.APIInstance:
        hub = _hub(self.hass)
        who = await who_of(self.hass, hub, llm_context)
        if not _may_use(hub, who):
            return llm.APIInstance(api=self, api_prompt="Glint isn't available here.", llm_context=llm_context, tools=[])
        return llm.APIInstance(
            api=self,
            api_prompt=PROMPT + (VOICE_PROMPT if who.origin == ORIGIN_VOICE else ""),
            llm_context=llm_context,
            tools=[
                # What Glint says it can change, from adults' phones only: a kid's phone writes its own state, and its
                # words in a tool's description would read as more trusted than a tool's answer
                tool(
                    start_ops_text(
                        [
                            hub.glint_agent.state(d)
                            for d in hub.glint_agent.reachable(who.person, voice=who.voice_only)
                            if not hub.glint_agent.is_kid_phone(d)
                        ]
                    )
                )
                if tool is ChangeStartTool
                else tool()
                for tool in TOOLS
            ],
        )


@callback
def async_register(hass: HomeAssistant) -> Callable[[], None] | None:
    """Registers the API once (it reads the loaded household on every call)."""
    if any(api.id == API_ID for api in llm.async_get_apis(hass)):
        return None
    return llm.async_register_api(hass, GlintAPI(hass))


# The doorbell, on Hearth's WebSocket


def _adult(hass: HomeAssistant, connection, msg):
    """(hub, the caller's reachable Glint phones) for an adult, or None after an error was sent."""
    hub = _hub(hass)
    if hub is None:
        connection.send_error(msg["id"], "not_set_up", "Hearth isn't set up")
        return None
    if not is_adult_user(hass, hub, connection.user):
        # Maybe an adult nobody marked yet: the administrators are asked once (adult_offer.py)
        note_refused(hass, hub, connection.user)
        connection.send_error(msg["id"], websocket_api.ERR_UNAUTHORIZED, "Unauthorized")
        return None
    return hub, hub.glint_agent.reachable(own_person(hass, connection.user))


@websocket_api.websocket_command({vol.Required("type"): "hearth/glint/phones"})
@callback
def ws_phones(hass: HomeAssistant, connection: websocket_api.ActiveConnection, msg: dict[str, Any]) -> None:
    """The Glint phones the caller may reach (their own and kids'), each with its linked doorbell."""
    if (started := _adult(hass, connection, msg)) is None:
        return
    hub, reachable = started
    agent: GlintAgent = hub.glint_agent
    connection.send_result(
        msg["id"],
        {
            "phones": [
                {
                    "device_id": d,
                    "name": agent.name_of(d),
                    "person": agent.person_of(d),
                    "kid_phone": agent.is_kid_phone(d),
                    "client": agent.client_of(d),
                    "bell": agent.bells.get(d),
                    "last_seen": seen.isoformat() if (seen := agent.last_seen(d)) else None,
                    "described": describe(hub, d),
                }
                for d in sorted(reachable)
            ]
        },
    )


@websocket_api.websocket_command(
    {
        vol.Required("type"): "hearth/glint/bell",
        vol.Required("device_id"): vol.All(str, vol.Length(min=1, max=64)),
        vol.Required("notify"): vol.Any(None, vol.All(str, vol.Length(min=1, max=200))),
    }
)
@callback
def ws_bell(hass: HomeAssistant, connection: websocket_api.ActiveConnection, msg: dict[str, Any]) -> None:
    """Links a companion app (its notify.mobile_app_* service) as a Glint phone's doorbell, or unlinks it (null)."""
    if (started := _adult(hass, connection, msg)) is None:
        return
    hub, reachable = started
    if msg["device_id"] not in reachable:
        connection.send_error(msg["id"], websocket_api.ERR_NOT_FOUND, "No such Glint phone of yours or a kid's")
        return
    service = msg["notify"]
    if service is not None:
        domain, _, name = service.partition(".")
        if not service.startswith(BELL_PREFIX) or not hass.services.has_service(domain, name):
            connection.send_error(msg["id"], "invalid", "A companion app's notify service: notify.mobile_app_<name>")
            return
    hub.glint_agent.set_bell(msg["device_id"], service)
    connection.send_result(msg["id"], {"device_id": msg["device_id"], "bell": service})


def _may_forget(hub: HearthHub, user, person: str | None, device_id: str) -> bool:
    """A paired phone (not a TV) that's the caller's own or a kid's, or any phone for an administrator."""
    device = hub.devices.get(device_id)
    if device is None or device.get(CONF_KIND) == KIND_TV:
        return False
    if user is not None and user.is_admin:
        return True
    agent: GlintAgent = hub.glint_agent
    owner = agent.person_of(device_id)
    # A phone with no person is nobody's to say: an administrator's to forget
    if owner is None:
        return False
    return agent.is_kid_phone(device_id) or owner == person


@websocket_api.websocket_command(
    {vol.Required("type"): "hearth/glint/forget", vol.Required("device_id"): vol.All(str, vol.Length(min=1, max=64))}
)
@websocket_api.async_response
async def ws_forget(hass: HomeAssistant, connection: websocket_api.ActiveConnection, msg: dict[str, Any]) -> None:
    """Forgets a stale phone (an adult's own, or a kid's; an administrator's any): the same removal as deleting its
    device in Home Assistant (hub.async_remove_device: its secret stops working, its documents and doorbell go), and
    its device entry goes too. A phone that never said it runs Glint (paired, then never seen) can go too. Never a TV,
    and never another adult's phone unless the caller is an administrator (who could delete its device anyway)."""
    if (started := _adult(hass, connection, msg)) is None:
        return
    hub, _reachable = started
    device_id = msg["device_id"]
    if not _may_forget(hub, connection.user, own_person(hass, connection.user), device_id):
        connection.send_error(msg["id"], websocket_api.ERR_NOT_FOUND, "No such phone of yours or a kid's")
        return
    described = describe(hub, device_id)
    registry = dr.async_get(hass)
    if (device := registry.async_get_device_by_identifier((DOMAIN, device_id), hub.entry.entry_id)) is not None:
        registry.async_remove_device(device.id)
    await hub.async_remove_device(device_id)
    connection.send_result(msg["id"], {"device_id": device_id, "forgotten": described})


@callback
def async_register_commands(hass: HomeAssistant) -> None:
    for command in (ws_phones, ws_bell, ws_forget):
        websocket_api.async_register_command(hass, command)
