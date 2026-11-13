"""A kid's to-do list with optional rewards (docs/home-assistant-integration.md, To-do lists).

Each kid has a list (todo.hearth_<kid>, todo.py) of tasks an adult or the kid added: one-off tasks (homework) and
repeating ones (daily, some weekdays, every N days, N days after last done). One day's instance of a task is an
occurrence; its id is the item's uid on the list.

An adult may attach a reward to a task they created: minutes in one of the kid's groups ("+15 Games") or money. There is
no approval step: the reward is granted when the item is checked off, by the kid themselves (their own Home Assistant
user, or later their TV profile) or by an adult. A sibling's user is refused; anyone else (a shared tablet's user, voice,
an automation) may check an item off, but nothing is granted. The adults are told of each grant, with an Undo button.

Every grant is one ledger entry keyed "<occurrence>#<n>": untick reverses it, a tick again makes the next n, so an
occurrence never has two live grants. Minutes aren't added to the day's bonus: Limits folds today's live chore minutes
into the bonus (bonus_chores), so a restart or a repeated event has nothing to add twice, and an undo takes them back at
once. All screen time minutes reach Family Link and Family Safety as hearth.add_bonus's do. Money is a balance per kid:
earned, paid and adjust entries; Hearth moves no money (a later integration could read earned and write paid, with its
own id in "ext").
"""

from __future__ import annotations

from dataclasses import dataclass
from datetime import date, datetime, time, timedelta
import logging
import re
from typing import TYPE_CHECKING, Any
import uuid

from homeassistant.core import HomeAssistant, callback
from homeassistant.exceptions import HomeAssistantError
from homeassistant.helpers.dispatcher import async_dispatcher_send
from homeassistant.helpers.storage import Store
from homeassistant.util import dt as dt_util

from .const import CONF_ROLES, SIGNAL_PEOPLE
from .counting import ALL

if TYPE_CHECKING:
    from .household import Household

_LOGGER = logging.getLogger(__name__)

# Options: {group id: minutes a day}: the most a kid earns by chores in that group a day (none: no cap)
CONF_CHORE_CAPS = "chore_caps"
# The old "Chores earn time" rows ({person, todo, group, minutes}); moved into this list once, then removed
CONF_CHORES = "chores"
EVENT_CHORE_DONE = "hearth_chore_done"
EVENT_CHORE_REVERSED = "hearth_chore_reversed"
SERVICE_CHORE_UNDO = "chore_undo"

# Who acts: an adult; the kid whose item it is (their own user); a TV acting for its profile's kid (phase 3); a
# sibling (another kid's user: refused); anyone else (a user with no person, voice, an automation: no reward)
ADULT = "adult"
KID = "kid"
DEVICE = "device"
SHARED = "shared"

ONCE = "once"
DAILY = "daily"
WEEKDAYS = "weekdays"
EVERY_N = "every_n"
AFTER_DONE = "after_done"
REPEATS = (ONCE, DAILY, WEEKDAYS, EVERY_N, AFTER_DONE)

EARNED = "earned"
PAID = "paid"
ADJUST = "adjust"

KEEP_DONE_DAYS = 14
KEEP_MINUTES_DAYS = 60
MAX_TASKS = 400
MAX_TITLE = 120
MAX_DESCRIPTION = 500
MAX_REWARD_MINUTES = 240
MAX_REWARD_CENTS = 100_00
MAX_MONEY_CENTS = 10_000_00
DONE_DAYS_KEPT = 5
_TAG = re.compile(r"\s*\+\s*(\d+)\s*")
_HHMM = re.compile(r"^([01]\d|2[0-3]):[0-5]\d$")


class ChoreError(HomeAssistantError):
    """A to-do change refused, with words for the person who tried."""

    def __init__(self, code: str, message: str) -> None:
        super().__init__(message)
        self.code = code


@dataclass(frozen=True)
class Actor:
    kind: str
    person: str | None = None
    user_id: str | None = None
    via: str = "todo"


@dataclass
class Occurrence:
    id: str
    task: dict[str, Any]
    # The day it is for (a one-off: None)
    day: date | None
    done: dict[str, Any] | None = None
    due: date | datetime | None = None

    @property
    def person(self) -> str:
        return self.task["person"]


async def async_actor(hass: HomeAssistant, hub, user_id: str | None, via: str = "todo") -> Actor:
    """Who a Home Assistant user is to the lists: an adult (auth.is_adult_user), a person's own user (a kid's, or a
    sibling's: Actor.person tells), or shared (no user, or a user with no person)."""
    from .auth import is_adult_user

    if user_id is None:
        return Actor(SHARED, via=via)
    user = await hass.auth.async_get_user(user_id)
    if user is None:
        return Actor(SHARED, via=via)
    if is_adult_user(hass, hub, user):
        return Actor(ADULT, user_id=user_id, via=via)
    person = next((s.entity_id for s in hass.states.async_all("person") if s.attributes.get("user_id") == user_id), None)
    return Actor(KID, person, user_id, via) if person else Actor(SHARED, user_id=user_id, via=via)


def worth(summary: str, default: int) -> int:
    """The old lists' "+N" tag, else the default."""
    match = _TAG.search(summary or "")
    return max(1, min(MAX_REWARD_MINUTES, int(match[1]))) if match else default


def _clean_title(text: Any) -> str:
    title = " ".join(str(text or "").split())[:MAX_TITLE]
    if not title:
        raise ChoreError("invalid", "An item needs a name")
    return title


def _clean_repeat(raw: Any) -> dict[str, Any]:
    raw = raw if isinstance(raw, dict) else {"kind": raw or ONCE}
    kind = raw.get("kind", ONCE)
    if kind not in REPEATS:
        raise ChoreError("invalid", f"Unknown repeat {kind}")
    if kind == WEEKDAYS:
        days = sorted({int(d) for d in raw.get("days", []) if str(d).isdigit() and 0 <= int(d) <= 6})
        if not days:
            raise ChoreError("invalid", "Pick at least one day")
        return {"kind": kind, "days": days}
    if kind in (EVERY_N, AFTER_DONE):
        n = raw.get("n")
        if not isinstance(n, int) or not 1 <= n <= 365:
            raise ChoreError("invalid", "Every 1 to 365 days")
        repeat: dict[str, Any] = {"kind": kind, "n": n}
        if kind == EVERY_N:
            start = raw.get("start") or dt_util.now().date().isoformat()
            repeat["start"] = date.fromisoformat(str(start)).isoformat()
        return repeat
    return {"kind": kind}


class ChoreBook:
    """The household's to-do lists: tasks, what's done, what's hidden, and the reward ledger, kept across restarts."""

    def __init__(self, hass: HomeAssistant, household: Household, entry_id: str) -> None:
        self.hass = hass
        self.household = household
        self._store: Store[dict[str, Any]] = Store(hass, 1, f"hearth.todo.{entry_id}")
        self.tasks: dict[str, dict[str, Any]] = {}
        # Occurrence id -> {person, task, day, at, user, via, actor, granted (ledger key or None)}
        self.done: dict[str, dict[str, Any]] = {}
        # Occurrence id -> the day it was taken off the list (Clear checked items, an adult's delete of a repeat)
        self.hidden: dict[str, str] = {}
        self.ledger: list[dict[str, Any]] = []
        # Old "Chores earn time" rows still to bring in (moved from the options at setup)
        self.imports: list[dict[str, Any]] = []

    # Storage

    def _data(self) -> dict[str, Any]:
        return {
            "tasks": self.tasks,
            "done": self.done,
            "hidden": self.hidden,
            "ledger": self.ledger,
            "imports": self.imports,
        }

    async def async_load(self) -> None:
        stored = await self._store.async_load() or {}
        self.tasks = dict(stored.get("tasks", {}))
        self.done = dict(stored.get("done", {}))
        self.hidden = dict(stored.get("hidden", {}))
        self.ledger = list(stored.get("ledger", []))
        self.imports = list(stored.get("imports", []))
        self._prune()

    def _save(self) -> None:
        self._store.async_delay_save(self._data, 2)

    async def async_flush(self) -> None:
        await self._store.async_save(self._data())

    def _today(self) -> date:
        return dt_util.now().date()

    def _prune(self) -> None:
        today = self._today()
        keep_done = (today - timedelta(days=KEEP_DONE_DAYS)).isoformat()
        keep_minutes = (today - timedelta(days=KEEP_MINUTES_DAYS)).isoformat()
        for occ, mark in list(self.done.items()):
            if str(mark.get("day", "")) < keep_done:
                del self.done[occ]
                task = self.tasks.get(mark.get("task", ""))
                # A one-off done long ago leaves with its mark (else it would show again, open)
                if task is not None and task["repeat"]["kind"] == ONCE:
                    del self.tasks[task["id"]]
        self.hidden = {k: v for k, v in self.hidden.items() if v >= keep_done}
        self.ledger = [e for e in self.ledger if e.get("cents") is not None or str(e.get("day", "")) >= keep_minutes]

    # Settings

    def kids(self) -> list[str]:
        """The people marked kid on Hearth's page: each has a list."""
        return sorted(p for p, role in self.household.options.get(CONF_ROLES, {}).items() if role == "kid")

    def caps(self) -> dict[str, int]:
        caps = self.household.options.get(CONF_CHORE_CAPS) or {}
        return {g: int(m) for g, m in caps.items() if isinstance(m, (int, float)) and m >= 0}

    # Occurrences

    @staticmethod
    def _applies(task: dict[str, Any], day: date) -> bool:
        repeat = task["repeat"]
        kind = repeat["kind"]
        if kind == DAILY:
            return True
        if kind == WEEKDAYS:
            return day.weekday() in repeat["days"]
        if kind == EVERY_N:
            start = date.fromisoformat(repeat["start"])
            return day >= start and (day - start).days % repeat["n"] == 0
        return False

    @staticmethod
    def _due(task: dict[str, Any], day: date | None) -> date | datetime | None:
        due_time = task.get("due_time")
        on = day or (date.fromisoformat(task["due_date"]) if task.get("due_date") else None)
        if on is None:
            return None
        if due_time:
            hour, minute = (int(x) for x in due_time.split(":"))
            return datetime.combine(on, time(hour, minute), tzinfo=dt_util.get_default_time_zone())
        return on if task.get("due_date") else None

    def items(self, person: str, today: date | None = None) -> list[Occurrence]:
        """The person's list today: today's occurrences of their repeating tasks, their open one-off tasks, and what
        they did today (done items stay on the list until the day ends)."""
        today = today or self._today()
        iso = today.isoformat()
        found: list[Occurrence] = []
        for task in self.tasks.values():
            if task["person"] != person:
                continue
            kind = task["repeat"]["kind"]
            occs: list[tuple[str, date | None]] = []
            if kind == ONCE:
                occs.append((task["id"], None))
            elif kind == AFTER_DONE:
                done_days = sorted(task.get("done_days", []))
                # What was done today stays shown, done
                occs += [(occ, today) for occ, mark in self.done.items() if mark.get("task") == task["id"] and mark.get("day") == iso]
                start = (
                    date.fromisoformat(done_days[-1]) + timedelta(days=task["repeat"]["n"])
                    if done_days
                    else date.fromisoformat(task.get("created", iso))
                )
                if today >= start:
                    occs.append((f"{task['id']}:{start.isoformat()}", start))
            elif self._applies(task, today):
                occs.append((f"{task['id']}:{iso}", today))
            for occ, day in dict.fromkeys(occs):
                if occ in self.hidden:
                    continue
                mark = self.done.get(occ)
                if mark is not None and mark.get("day") != iso:
                    continue
                found.append(Occurrence(occ, task, day, mark, self._due(task, day if kind != ONCE else None)))
        return sorted(found, key=lambda o: (o.due is None, str(o.due or ""), o.task.get("order", 0), o.task["title"]))

    def occurrence(self, occ_id: str, person: str | None = None) -> Occurrence:
        """One of today's items, by its uid; ChoreError gone when it isn't on a list now."""
        task = self.tasks.get(occ_id.split(":", 1)[0])
        if task is not None and (person is None or task["person"] == person):
            for occ in self.items(task["person"]):
                if occ.id == occ_id:
                    return occ
        raise ChoreError("gone", "That item isn't on the list any more")

    def reward_label(self, task: dict[str, Any]) -> str | None:
        reward = task.get("reward")
        if not reward:
            return None
        if "cents" in reward:
            return f"+${reward['cents'] / 100:.2f}"
        group = self.household.group(reward["pool"])
        return f"+{reward['minutes']} min {group.name if group else reward['pool']}"

    def summary_of(self, task: dict[str, Any]) -> str:
        """The item's text on the list: its title, and its reward so the kid can choose to earn it."""
        label = self.reward_label(task)
        return f"{task['title']} ({label})" if label else task["title"]

    def _title_from(self, task: dict[str, Any], summary: str) -> str:
        """A summary edited on a list, back to the title (the reward's words the list shows taken off)."""
        label = self.reward_label(task)
        if label and summary.endswith(f"({label})"):
            summary = summary[: -len(f"({label})")]
        return _clean_title(summary)

    # Who may

    def _check_person(self, actor: Actor, person: str) -> None:
        if actor.kind in (KID, DEVICE) and actor.person != person:
            raise ChoreError("not_yours", f"That's on {self.household.person_name(person)}'s list")

    @staticmethod
    def _may_edit(actor: Actor, task: dict[str, Any]) -> bool:
        """Adults change anything; the kid and a shared screen only what a kid added."""
        return actor.kind == ADULT or task.get("by") == KID

    @staticmethod
    def _grants(actor: Actor) -> bool:
        return actor.kind in (ADULT, KID, DEVICE)

    # Tasks

    def save_task(self, data: dict[str, Any], actor: Actor) -> dict[str, Any]:
        """A task from the panel's editor (an adult): new without an id, else that task changed. Only here are the
        person, the repeat and the reward set."""
        if actor.kind != ADULT:
            raise ChoreError("unauthorized", "Only an adult can set up the list")
        person = data["person"]
        if person not in self.kids():
            raise ChoreError("invalid", f"{person} isn't a kid on Hearth's page")
        task = dict(self.tasks[data["id"]]) if data.get("id") in self.tasks else None
        if data.get("id") and task is None:
            raise ChoreError("gone", "That task isn't there any more")
        if task is None:
            if len(self.tasks) >= MAX_TASKS:
                raise ChoreError("too_many", "The lists are full")
            task = {"id": uuid.uuid4().hex[:10], "created": self._today().isoformat(), "by": ADULT, "order": len(self.tasks)}
        task.update(
            {
                "person": person,
                "title": _clean_title(data.get("title")),
                "description": str(data.get("description") or "")[:MAX_DESCRIPTION] or None,
                "repeat": _clean_repeat(data.get("repeat")),
                "due_time": self._clean_time(data.get("due_time")),
                "due_date": self._clean_date(data.get("due_date")),
                "reward": self._clean_reward(data.get("reward")),
            }
        )
        if task["by"] == KID and task["reward"]:
            # A kid's own item never carries one; an adult who wants one makes it theirs
            task["by"] = ADULT
        self.tasks[task["id"]] = task
        self._changed()
        return task

    @staticmethod
    def _clean_time(value: Any) -> str | None:
        if value in (None, ""):
            return None
        if not _HHMM.match(str(value)[:5]):
            raise ChoreError("invalid", "A time is HH:MM")
        return str(value)[:5]

    @staticmethod
    def _clean_date(value: Any) -> str | None:
        if value in (None, ""):
            return None
        try:
            return date.fromisoformat(str(value)[:10]).isoformat()
        except ValueError as err:
            raise ChoreError("invalid", "A date is YYYY-MM-DD") from err

    def _clean_reward(self, reward: Any) -> dict[str, Any] | None:
        if not reward:
            return None
        if "cents" in reward:
            cents = reward["cents"]
            if not isinstance(cents, int) or not 1 <= cents <= MAX_REWARD_CENTS:
                raise ChoreError("invalid", "A money reward is 1 cent to $100")
            return {"cents": cents}
        minutes, pool = reward.get("minutes"), reward.get("pool")
        if not isinstance(minutes, int) or not 1 <= minutes <= MAX_REWARD_MINUTES:
            raise ChoreError("invalid", f"A reward is 1 to {MAX_REWARD_MINUTES} minutes")
        if pool != ALL and self.household.group(pool) is None:
            raise ChoreError("invalid", f"No group {pool}")
        return {"pool": pool, "minutes": minutes}

    def delete_task(self, task_id: str, actor: Actor) -> None:
        if actor.kind != ADULT:
            raise ChoreError("unauthorized", "Only an adult can remove a task")
        if self.tasks.pop(task_id, None) is None:
            raise ChoreError("gone", "That task isn't there any more")
        self._changed()

    def add_item(self, person: str, title: str, actor: Actor, description: str | None = None,
                 due: date | datetime | None = None) -> dict[str, Any]:
        """An item added on the list itself (the to-do card, voice): a one-off task with no reward. The kid's own unless
        an adult added it (rewards are set in the panel)."""
        self._check_person(actor, person)
        if len(self.tasks) >= MAX_TASKS:
            raise ChoreError("too_many", "The lists are full")
        task = {
            "id": uuid.uuid4().hex[:10],
            "person": person,
            "title": _clean_title(title),
            "description": (description or "")[:MAX_DESCRIPTION] or None,
            "repeat": {"kind": ONCE},
            "due_date": due.date().isoformat() if isinstance(due, datetime) else due.isoformat() if due else None,
            "due_time": due.strftime("%H:%M") if isinstance(due, datetime) else None,
            "reward": None,
            "by": ADULT if actor.kind == ADULT else KID,
            "created": self._today().isoformat(),
            "order": len(self.tasks),
        }
        self.tasks[task["id"]] = task
        self._changed()
        return task

    def edit_item(self, occ_id: str, person: str, actor: Actor, *, summary: str | None = None,
                  description: str | None = None, due: Any = ..., done: bool | None = None) -> None:
        """A change made on the list: its text, description or due date (when this caller may change the item) and
        whether it's done. A field given as it is now isn't a change (the to-do card sends the whole item)."""
        self._check_person(actor, person)
        occ = self.occurrence(occ_id, person)
        task = occ.task
        changes: dict[str, Any] = {}
        if summary is not None and summary != self.summary_of(task):
            changes["title"] = self._title_from(task, summary)
        if description is not None and (description or None) != task.get("description"):
            changes["description"] = description[:MAX_DESCRIPTION] or None
        if due is not ... and due != occ.due:
            if task["repeat"]["kind"] != ONCE:
                raise ChoreError("invalid", "A repeating item's time is set in Hearth's page")
            changes["due_date"] = due.date().isoformat() if isinstance(due, datetime) else due.isoformat() if due else None
            changes["due_time"] = due.strftime("%H:%M") if isinstance(due, datetime) else None
        if changes:
            if not self._may_edit(actor, task):
                raise ChoreError("adult_item", "Only an adult can change that item; it can be ticked off")
            self.tasks[task["id"]] = {**task, **changes}
            self._changed()
        if done is not None:
            self.check(occ_id, done, actor)

    def delete_items(self, person: str, occ_ids: list[str], actor: Actor) -> None:
        """Items taken off the list. A done item is only hidden (Clear checked items): its reward stays. An open one-off
        goes (an adult's, or one a kid added); an adult's delete of a repeating item skips it today."""
        self._check_person(actor, person)
        occs = [self.occurrence(occ_id, person) for occ_id in occ_ids]
        refused = [o for o in occs if o.done is None and not self._may_edit(actor, o.task)]
        if refused:
            raise ChoreError("adult_item", "Only an adult can remove that item; it can be ticked off")
        today = self._today().isoformat()
        for occ in occs:
            if occ.done is not None or occ.task["repeat"]["kind"] != ONCE:
                self.hidden[occ.id] = today
            else:
                self.tasks.pop(occ.task["id"], None)
        self._changed()

    # Ticks and grants

    def check(self, occ_id: str, done: bool, actor: Actor) -> str | None:
        """Ticks or unticks an item. A tick by the kid, their TV or an adult grants the item's reward; untick reverses
        what it granted. Returns the live grant's ledger key, if any."""
        occ = self.occurrence(occ_id)
        self._check_person(actor, occ.person)
        if done:
            if occ.done is not None:
                return occ.done.get("granted")
            now = dt_util.now()
            mark = {
                "person": occ.person,
                "task": occ.task["id"],
                "day": now.date().isoformat(),
                "at": now.isoformat(),
                "user": actor.user_id,
                "via": actor.via,
                "actor": actor.kind,
                "granted": None,
            }
            self.done[occ.id] = mark
            self._note_done_day(occ.task, mark["day"], add=True)
            entry = self._grant(occ, actor) if self._grants(actor) else None
            self._changed(recompute=entry is not None)
            if entry is not None:
                self._granted(entry)
            return mark["granted"]
        if occ.done is None:
            return None
        key = occ.done.get("granted")
        if key and not self._grants(actor):
            raise ChoreError("granted", f"Only {self.household.person_name(occ.person)} or an adult can untick that")
        del self.done[occ.id]
        self._note_done_day(occ.task, occ.done["day"], add=False)
        if key:
            self._reverse(key, "untick", actor.user_id)
        else:
            self._changed()
        return None

    def _note_done_day(self, task: dict[str, Any], day: str, add: bool) -> None:
        if task["repeat"]["kind"] != AFTER_DONE:
            return
        days = [d for d in task.get("done_days", []) if d != day]
        if add:
            days = sorted(days + [day])[-DONE_DAYS_KEPT:]
        self.tasks[task["id"]] = {**task, "done_days": days}

    def give(self, occ_id: str, actor: Actor) -> dict[str, Any]:
        """An adult gives the reward of a done item that has none live (a shared screen's tick, or after an undo)."""
        if actor.kind != ADULT:
            raise ChoreError("unauthorized", "Only an adult can give a reward")
        occ = self.occurrence(occ_id)
        if occ.done is None:
            raise ChoreError("open", "Tick it off to give its reward")
        if occ.done.get("granted"):
            raise ChoreError("granted", "Its reward was given already")
        if not occ.task.get("reward"):
            raise ChoreError("no_reward", "It has no reward")
        entry = self._grant(occ, actor)
        self._changed(recompute=True)
        self._granted(entry)
        return entry

    def _next_key(self, occ_id: str) -> str:
        n = max((int(e["key"].rsplit("#", 1)[1]) for e in self.ledger if e.get("occurrence") == occ_id), default=0)
        return f"{occ_id}#{n + 1}"

    def _grant(self, occ: Occurrence, actor: Actor) -> dict[str, Any] | None:
        """The ledger entry for the item's reward (none without one), as the done mark's live grant."""
        reward = occ.task.get("reward")
        if not reward:
            return None
        now = dt_util.now()
        entry: dict[str, Any] = {
            "key": self._next_key(occ.id),
            "occurrence": occ.id,
            "task": occ.task["id"],
            "title": occ.task["title"],
            "person": occ.person,
            "kind": EARNED,
            "day": now.date().isoformat(),
            "at": now.isoformat(),
            "by": actor.user_id,
            "via": actor.via,
            "actor": actor.kind,
        }
        if "cents" in reward:
            entry["cents"] = reward["cents"]
        else:
            pool, asked = reward["pool"], reward["minutes"]
            minutes = asked
            if (cap := self.caps().get(pool)) is not None:
                minutes = max(0, min(asked, cap - self.minutes_today(occ.person, pool)))
            entry.update({"pool": pool, "asked": asked, "minutes": minutes})
            entry["had_none"] = self._had_none(occ.person)
        self.ledger.append(entry)
        self.done[occ.id]["granted"] = entry["key"]
        return entry

    def _had_none(self, person: str) -> bool:
        day = self.household.days.get(person)
        state = day.limits.get(ALL) if day else None
        return bool(state and state.minutes_left == 0)

    def _granted(self, entry: dict[str, Any]) -> None:
        """What a grant does beyond the ledger: history, Google's and Microsoft's own limits, the adults told."""
        from .history import BONUS

        person, pool, minutes = entry["person"], entry.get("pool"), entry.get("minutes") or 0
        had_none = entry.pop("had_none", False)
        if minutes:
            self.household.history.log(BONUS, person, group=pool, minutes=minutes, via="chore")
            if pool == ALL:
                self.household.sync.mirror_bonus(person, had_none)
        self.hass.bus.async_fire(
            EVENT_CHORE_DONE,
            {
                "person": person,
                "chore": entry["title"],
                "group": pool,
                "minutes": minutes if pool else None,
                "cents": entry.get("cents"),
                "key": entry["key"],
                "by": entry["by"],
            },
        )
        self.household.hub.attention.notify(self._notice(entry))
        self._save()

    def _notice(self, entry: dict[str, Any]):
        from .attention import ADULTS, Action, Item

        who = self.household.person_name(entry["person"])
        if entry.get("cents") is not None:
            what = f"+${entry['cents'] / 100:.2f}"
        else:
            group = self.household.group(entry["pool"])
            name = group.name if group else entry["pool"]
            what = f"+{entry['minutes']} min of {name} today"
            if entry["minutes"] < entry["asked"]:
                what += f" (today's cap for {name} is reached)"
        return Item(
            f"hearth_chore_{entry['occurrence']}",
            f"{entry['title']}: {what}",
            title=f"{who} finished a chore",
            audience=ADULTS,
            actions=(Action("undo", "Undo", f"hearth.{SERVICE_CHORE_UNDO}", {"key": entry["key"]}),),
            about={"person": entry["person"], "group": entry.get("pool"), "chore": entry["key"]},
            once=True,
        )

    def undo(self, key: str, user_id: str | None) -> dict[str, Any]:
        """An adult takes a grant back, whole (decision 7): the pool's minutes drop at once, clamped at 0 (and locked if
        none are left). The item stays done; Give grants it again."""
        self._reverse(key, "undo", user_id)
        return next(e for e in self.ledger if e["key"] == key)

    def _reverse(self, key: str, why: str, user_id: str | None) -> None:
        from .history import BONUS

        entry = next((e for e in self.ledger if e["key"] == key and e["kind"] == EARNED), None)
        if entry is None:
            raise ChoreError("not_found", "No such reward")
        if entry.get("reversed_at"):
            raise ChoreError("reversed", "That reward was undone already")
        today = self._today().isoformat()
        minutes = entry.get("minutes") or 0
        if minutes and entry["day"] == today:
            day = self.household.days.get(entry["person"])
            state = day.limits.get(entry["pool"]) if day else None
            if state is not None and state.minutes_left is not None:
                entry["spent"] = max(0, minutes - state.minutes_left)
        entry.update({"reversed_at": dt_util.now().isoformat(), "reversed_by": user_id, "reversed_why": why})
        mark = self.done.get(entry["occurrence"])
        if mark is not None and mark.get("granted") == key:
            mark["granted"] = None
        if minutes and entry["day"] == today:
            self.household.history.log(BONUS, entry["person"], group=entry["pool"], minutes=-minutes, via="chore")
        self._changed(recompute=bool(minutes))
        self.household.hub.attention.clear(f"hearth_chore_{entry['occurrence']}")
        self.hass.bus.async_fire(
            EVENT_CHORE_REVERSED,
            {"person": entry["person"], "chore": entry["title"], "key": key, "why": why, "by": user_id},
        )

    # The numbers

    def minutes_today(self, person: str, group: str) -> int:
        """The chore minutes live today in [group] (Limits folds them into the bonus: bonus_chores)."""
        today = self._today().isoformat()
        return sum(
            e.get("minutes") or 0
            for e in self.ledger
            if e["kind"] == EARNED and e["person"] == person and e.get("pool") == group and e["day"] == today
            and not e.get("reversed_at")
        )

    def balance_cents(self, person: str) -> int:
        total = 0
        for e in self.ledger:
            if e["person"] != person or e.get("cents") is None or e.get("reversed_at"):
                continue
            total += -e["cents"] if e["kind"] == PAID else e["cents"]
        return total

    def money(self, person: str, kind: str, cents: int, actor: Actor, note: str | None = None,
              ext: str | None = None) -> dict[str, Any]:
        """Paid out (cents taken off the balance) or an adjust (+ or -). [ext]: another system's id for it."""
        if actor.kind != ADULT:
            raise ChoreError("unauthorized", "Only an adult can change a balance")
        if kind not in (PAID, ADJUST) or not isinstance(cents, int) or not 0 < abs(cents) <= MAX_MONEY_CENTS:
            raise ChoreError("invalid", "An amount up to $10,000")
        if kind == PAID and cents < 0:
            raise ChoreError("invalid", "Paid out is more than 0")
        now = dt_util.now()
        entry = {
            "key": f"money:{uuid.uuid4().hex[:12]}",
            "person": person,
            "kind": kind,
            "cents": cents,
            "day": now.date().isoformat(),
            "at": now.isoformat(),
            "by": actor.user_id,
            "via": actor.via,
            "actor": actor.kind,
        }
        if note:
            entry["note"] = str(note)[:120]
        if ext:
            entry["ext"] = str(ext)[:120]
        self.ledger.append(entry)
        self._changed()
        return entry

    def counts(self, person: str) -> dict[str, int]:
        items = self.items(person)
        done = sum(1 for o in items if o.done is not None)
        return {"left": len(items) - done, "done": done, "total": len(items)}

    def view(self, person: str) -> dict[str, Any]:
        """The panel's view of one kid's list."""
        today = self._today().isoformat()
        return {
            "person": person,
            "tasks": sorted(
                (t for t in self.tasks.values() if t["person"] == person),
                key=lambda t: (t["repeat"]["kind"] == ONCE, t.get("due_time") or "", t.get("order", 0)),
            ),
            "today": [
                {
                    "id": o.id,
                    "task": o.task["id"],
                    "title": o.task["title"],
                    "reward": self.reward_label(o.task),
                    "due": o.due.isoformat() if o.due else None,
                    "by": o.task.get("by"),
                    "done": o.done is not None,
                    "granted": (o.done or {}).get("granted"),
                    "done_by": (o.done or {}).get("actor"),
                }
                for o in self.items(person)
            ],
            "ledger": [e for e in reversed(self.ledger) if e["person"] == person][:50],
            "balance_cents": self.balance_cents(person),
            "minutes_today": {
                g.id: m for g in self.household.groups if (m := self.minutes_today(person, g.id))
            },
            "day": today,
        }

    # After a change

    def _changed(self, recompute: bool = False) -> None:
        self._save()
        if recompute:
            self.household.recompute()
        else:
            async_dispatcher_send(self.hass, SIGNAL_PEOPLE, False)

    @callback
    def start(self) -> None:
        """After a restart: today's live grants' notices are put back (not sent again), so their Undo still works."""
        today = self._today().isoformat()
        for entry in self.ledger:
            if entry["kind"] == EARNED and entry["day"] == today and not entry.get("reversed_at"):
                self.household.hub.attention.adopt(self._notice(entry))

    @callback
    def new_day(self) -> None:
        """Midnight: yesterday's items leave the lists (items() goes by the day), old marks and entries go."""
        self._prune()
        self._changed()

    # The old "Chores earn time"

    def queue_imports(self, rows: list[dict[str, Any]]) -> None:
        self.imports += [r for r in rows if r.get("person") and r.get("todo") and r.get("group")]
        self._save()

    async def async_import(self) -> None:
        """Each old row's open items become one-off tasks of the row's kid, rewarded by their "+N" (else the row's
        minutes) in the row's group. The old list is left as it is. A list that can't be read now is tried at the next
        start; one that's gone is passed over."""
        for row in list(self.imports):
            todo = row["todo"]
            if self.hass.states.get(todo) is None:
                _LOGGER.warning("Hearth's old chores list %s is gone; its items weren't brought in", todo)
                self.imports.remove(row)
                continue
            try:
                response = await self.hass.services.async_call(
                    "todo", "get_items", {"status": "needs_action"}, target={"entity_id": todo}, blocking=True,
                    return_response=True,
                )
            except Exception as err:  # noqa: BLE001 - tried again at the next start
                _LOGGER.warning("Hearth couldn't read the old chores list %s: %s", todo, err)
                continue
            default = row.get("minutes") if isinstance(row.get("minutes"), int) and row.get("minutes") > 0 else 15
            for item in ((response or {}).get(todo) or {}).get("items") or []:
                summary = str(item.get("summary") or "")
                title = _TAG.sub(" ", summary).strip() or summary
                try:
                    task = {
                        "id": uuid.uuid4().hex[:10],
                        "person": row["person"],
                        "title": _clean_title(title),
                        "description": None,
                        "repeat": {"kind": ONCE},
                        "due_date": None,
                        "due_time": None,
                        "reward": {"pool": row["group"], "minutes": worth(summary, min(default, MAX_REWARD_MINUTES))},
                        "by": ADULT,
                        "created": self._today().isoformat(),
                        "order": len(self.tasks),
                    }
                except ChoreError:
                    continue
                self.tasks[task["id"]] = task
            self.imports.remove(row)
        self._changed()


def migrated_options(options: dict[str, Any]) -> tuple[dict[str, Any], list[dict[str, Any]]] | None:
    """The options without the old "Chores earn time" rows, and the rows; None when there are none."""
    if CONF_CHORES not in options:
        return None
    rows = [dict(r) for r in options.get(CONF_CHORES) or [] if isinstance(r, dict)]
    return {k: v for k, v in options.items() if k != CONF_CHORES}, rows
