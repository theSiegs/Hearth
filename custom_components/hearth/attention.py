"""What the adults (or a kid) should see: one place every notice goes through (docs/home-assistant-integration.md,
Attention).

An item says what it is about and who it is for (its audience); the delivery adapters (delivery/) take it to a channel:
the companion app on the audience's phones, and Home Assistant's bell when the item asks for it; an item for TVs
(Item.tv) is also in the state document of every TV that shows notices. Each policy stays
with the item's source (when a request is told, when an offer is made); here is only the generic work: an item with
the same key or tag replaces the one before, and clearing a key or tag takes it off every channel it went to.

A phone button on an item runs a Hearth service (only the hearth domain) as the adult who pressed it: the phone sends
HEARTH_ACT|<item key>|<n>, and the service and its data are looked up here, never carried in the string. The adult check
comes first (in the action handler), then the presser must be someone the item reached. The older HEARTH_MORE| and
HEARTH_APP| buttons are passed through as they are (phones already hold them).

Items are kept outside the entry (an options change reloads it, and a button pressed meanwhile must still find its
item), not across a restart: each source puts its items back then (asks have their own store; suggestions are
worked out again).

Each item shown, replaced or cleared is also announced on Home Assistant's bus as a hearth_notice event
(docs/contracts/notice-event.md), read-only: its words, who it's for and its buttons' labels, never a button's service
or data. Announcing never stops or slows a delivery: a failure is logged.
"""

from __future__ import annotations

from collections.abc import Callable, Mapping
from dataclasses import dataclass, field
from datetime import datetime
import logging
from typing import TYPE_CHECKING, Any

from homeassistant.core import Context, HomeAssistant
from homeassistant.helpers.dispatcher import async_dispatcher_send
from homeassistant.util import dt as dt_util

from . import phones
from .const import CONF_ROLES, DOMAIN, SIGNAL_NOTICES
from .delivery import bell, companion
from .activity import call_service

if TYPE_CHECKING:
    from .hub import HearthHub

_LOGGER = logging.getLogger(__name__)

INFO = "info"
NOTICE = "notice"
URGENT = "urgent"
URGENCIES = (INFO, NOTICE, URGENT)

# Who an item is for. adults: every adult's companion apps, as phones.py finds them (with the chosen phone, once);
# chosen_phone: the phone chosen in Configure > Watch for new apps (ask_notify); schedule_phone: the schedule's own
# phone, else the chosen one; admins: the administrators (the bell, and their companion apps as last looked up:
# async_note_admins); person:<entity id>: that person's
# companion apps
ADULTS = "adults"
CHOSEN_PHONE = "chosen_phone"
SCHEDULE_PHONE = "schedule_phone"
ADMINS = "admins"
PERSON = "person:"

# hearth.notify's (notify_service.py): everyone on Hearth's page (their companion apps), and every TV that shows notices
HOUSEHOLD = "household"
# hearth.notify's to chosen devices: the phones in Item.to, the TVs in Item.tvs
DEVICES = "devices"

# The read-only announcement of an item shown, updated or cleared (docs/contracts/notice-event.md)
EVENT_NOTICE = "hearth_notice"
NOTICE_EVENT_VERSION = 1
SHOWN = "shown"
UPDATED = "updated"
CLEARED = "cleared"
# An item's kind in the event, by its key's or tag's start (the sources keep their own keys); "other" when none fits.
# An item that names its own (Item.kind) goes by that.
KINDS_BY_PREFIX = (
    ("hearth_more_fs_", "ask_failed"),
    ("hearth_more_", "ask"),
    ("hearth_adult_offer_", "adult_offer"),
    ("outside_app_", "outside_change"),
    ("ai_companion_", "app_check"),
    ("hearth_check_", "device_check"),
    ("hearth_clock_", "device_clock"),
    ("hearth_pairing_", "pairing"),
    ("hearth_paired_", "pairing"),
    ("hearth_panel_hello_", "pairing"),
    ("hearth_bedtime_", "bedtime"),
    ("hearth_native_limit_", "native_limit"),
    ("hearth_new_apps", "new_app"),
    ("hearth_app_", "new_app"),
    ("hearth_rules_", "rules"),
    ("hearth_place_", "place"),
    ("hearth_chore_", "chore"),
    ("hearth_schedule_check", "schedule"),
    ("hearth_school_time_watchdog", "schedule"),
    ("hearth_unlimited_", "unlimited"),
    ("hearth_suggest", "suggestion"),
    ("approve:", "approval"),
    ("hearth_approve:", "approval"),
    ("voice:", "approval"),
    ("hearth_voice:", "approval"),
    ("hearth_notify_", "notify"),
    ("hearth_switch_", "switch"),
)

# A phone button that runs an item's action: HEARTH_ACT|<item key>|<n>
ACT_PREFIX = "HEARTH_ACT|"
# Items without an expiry are kept until cleared or replaced: the oldest go past this many
MAX_ITEMS = 200
# Every companion-app push carries a tag with this prefix (a phone app that shows Hearth's notices goes by it)
TAG_PREFIX = "hearth_"


@dataclass(frozen=True)
class Action:
    """A button. With a service ("domain.service" and its data), it runs that as the adult who pressed it; without,
    [id] is the phone action as it goes out (HEARTH_MORE|..., HEARTH_APP|...), handled where it always was."""

    id: str
    label: str
    service: str | None = None
    data: Mapping[str, Any] = field(default_factory=dict)
    # Takes the item off every phone, and runs nothing ("Don't allow"); goes out as HEARTH_ACT too
    dismiss: bool = False


@dataclass
class Item:
    key: str
    text: str
    title: str | None = None
    urgency: str = INFO
    audience: str = ADULTS
    actions: tuple[Action, ...] = ()
    # What replaces or clears it on a channel (the phone's tag, the bell's id); the key when not given
    tag: str | None = None
    # Home Assistant's bell too (shown to every user of Home Assistant, so only the household's own business: a
    # pairing, a failure to fix, the new apps' list, the schedule's checks; never a kid's request, place or chore);
    # and the audience's phones
    bell: bool = False
    phone: bool = True
    expires: datetime | None = None
    # {"person", "group"} it is about, for the views that read items
    about: Mapping[str, Any] = field(default_factory=dict)
    # The bell's own text, when it should say more than the phone
    bell_text: str | None = None
    # A request for more time a tap on the phone opens (phones.Phone.click)
    opens: str | None = None
    # Otherwise the page a tap opens, a path on Home Assistant ("/hearth"): relative, so the companion app uses the
    # address it reaches Home Assistant on (at home or away)
    link: str | None = None
    sent: datetime = field(default_factory=dt_util.utcnow)
    # The Home Assistant users it reached on the companion app: the ones whose buttons count
    reached: frozenset[str] = frozenset()
    # On the TVs too: in the state document of a TV that shows notices (cap "notices"), which shows it in its adult
    # profiles (its audience's: every adult's, or one person's), as `notices`
    tv: bool = False
    # The key of the item this one belongs to (a phone approval of a TV notice's button): cleared with it
    follows: str | None = None
    # Done once a button is pressed: taken off every phone then
    once: bool = False
    # Called once it's cleared or replaced (its source's own timer, say)
    on_clear: Callable[[], None] | None = field(default=None, repr=False, compare=False)
    # The phones it goes to, in place of its audience's (hearth.notify's chosen devices)
    to: tuple[phones.Phone, ...] | None = None
    # Only these TVs (Hearth device ids) show it (tv); None: every TV that shows notices
    tvs: frozenset[str] | None = None
    # What it is, for the hearth_notice event; None: told by its key (KINDS_BY_PREFIX)
    kind: str | None = None

    @property
    def channel_tag(self) -> str:
        return self.tag or self.key

    def notice(self) -> dict[str, Any]:
        """The item as a TV's state document has it: stable fields only (no times counting, no service or data), so
        an unchanged item doesn't wake the TVs' waits. A button's id is its number, as a press sends it."""
        notice: dict[str, Any] = {
            "key": self.key,
            "tag": self.channel_tag,
            "title": self.title or "",
            "message": self.text,
            "urgency": self.urgency if self.urgency in URGENCIES else INFO,
            # Only buttons a press can run (a hearth service)
            "actions": [{"id": str(n), "title": a.label} for n, a in enumerate(self.actions) if Attention.runs(a)],
        }
        if self.audience.startswith(PERSON):
            notice["for"] = self.audience[len(PERSON):]
        if self.expires is not None:
            notice["expires"] = self.expires.isoformat()
        return notice


def _cleared(item: Item) -> None:
    if item.on_clear is not None:
        done, item.on_clear = item.on_clear, None
        done()


def _items(hass: HomeAssistant) -> dict[str, Item]:
    """The items, by key, kept outside the entry (like commands.py's), so a reload keeps them."""
    return hass.data.setdefault(f"{DOMAIN}_attention", {})


class Attention:
    """Telling people: the items, and the channels they go out on."""

    def __init__(self, hass: HomeAssistant, hub: HearthHub | None = None) -> None:
        self.hass = hass
        self.hub = hub

    @property
    def options(self) -> Mapping[str, Any]:
        return self.hub.entry.options if self.hub is not None else {}

    # Items

    def items(self) -> list[Item]:
        self._tidy()
        return sorted(_items(self.hass).values(), key=lambda i: i.sent)

    def item(self, key: str) -> Item | None:
        self._tidy()
        return _items(self.hass).get(key)

    def _tidy(self) -> None:
        items = _items(self.hass)
        now = dt_util.utcnow()
        for key in [k for k, i in items.items() if i.expires is not None and i.expires <= now]:
            del items[key]
        for item in sorted(items.values(), key=lambda i: i.sent)[: max(0, len(items) - MAX_ITEMS)]:
            del items[item.key]

    def notify(self, item: Item) -> None:
        """Keeps [item] (in place of one with its key or tag) and sends it out on its channels."""
        items = _items(self.hass)
        replaced: list[Item] = []
        for key in [k for k, i in items.items() if k == item.key or i.channel_tag == item.channel_tag]:
            replaced.append(old := items.pop(key))
            _cleared(old)
        if item.bell:
            bell.show(self.hass, item)
        if item.phone:
            targets = self.item_targets(item)
            item.reached = frozenset(self._users(targets))
            companion.send(self.hass, self.options, targets, item)
        items[item.key] = item
        self._tidy()
        if item.tv:
            self._tvs_changed()
        # One of another key it replaced (by its tag) is gone; this one is new, or new words for the same key or tag
        for old in replaced:
            if old.key != item.key:
                self._announce(CLEARED, old)
        self._announce(UPDATED if replaced else SHOWN, item)

    def adopt(self, item: Item) -> None:
        """Keeps [item] without sending it: one its source sent before Home Assistant restarted, still on the phones,
        so its buttons work again and clearing it takes it off them."""
        if item.phone:
            item.reached = frozenset(self._users(self.item_targets(item)))
        _items(self.hass)[item.key] = item
        self._tidy()
        if item.tv:
            self._tvs_changed()

    def tv_items(self, people: set[str], device_id: str | None = None) -> list[Item]:
        """The items a TV shows (Item.tv), oldest first: every adult's, and one person's only when that person is one
        of the TV's ([people]); one for chosen TVs (Item.tvs) only on those ([device_id])."""
        return [item for item in self.items() if self.on_tv(item, people, device_id)]

    @staticmethod
    def on_tv(item: Item, people: set[str], device_id: str | None = None) -> bool:
        """Whether the TV [device_id], whose profiles are [people]'s, shows [item]."""
        if not item.tv or (item.tvs is not None and device_id not in item.tvs):
            return False
        return item.audience in (ADULTS, HOUSEHOLD, DEVICES) or (
            item.audience.startswith(PERSON) and item.audience[len(PERSON):] in people
        )

    def tv_notices(self, people: set[str], device_id: str | None = None) -> list[dict[str, Any]]:
        """tv_items as a TV's state document has them (its notices)."""
        return [item.notice() for item in self.tv_items(people, device_id)]

    def _tvs_changed(self) -> None:
        """A TV item came or went: the TVs' waits look again (their document's notices changed)."""
        async_dispatcher_send(self.hass, SIGNAL_NOTICES)

    def clear(self, key_or_tag: str, *, audience: str = ADULTS, bell_too: bool = False, phone: bool = False) -> None:
        """Takes the items with that key or tag off the channels they went to; with none kept (Home Assistant restarted
        since), off the channels given."""
        items = _items(self.hass)
        found = [i for i in items.values() if key_or_tag in (i.key, i.channel_tag)]
        # Only items that were kept are announced as cleared (one made up here was never announced)
        kept = bool(found)
        if not found:
            found = [Item(key_or_tag, "", audience=audience, bell=bell_too, phone=phone)]
        for item in found:
            items.pop(item.key, None)
            _cleared(item)
            if item.tv:
                self._tvs_changed()
            if item.phone:
                companion.clear(self.hass, self.options, self.item_targets(item), item.channel_tag)
            if item.bell:
                bell.dismiss(self.hass, item.channel_tag)
            if kept:
                self._announce(CLEARED, item)
        # And what belonged to them (a phone approval of a TV notice's button)
        gone = {item.key for item in found}
        for follower in [i for i in items.values() if i.follows in gone]:
            self.clear(follower.key)

    # The announcement (hearth_notice)

    def _announce(self, change: str, item: Item) -> None:
        """Fires hearth_notice for [item]. Never raises: no delivery depends on it."""
        try:
            self.hass.bus.async_fire(EVENT_NOTICE, self.notice_event(change, item))
        except Exception:  # noqa: BLE001 - the notice went out; only its announcement failed
            _LOGGER.exception("Hearth couldn't announce the notice %s", item.key)

    def notice_event(self, change: str, item: Item) -> dict[str, Any]:
        """The hearth_notice event's data (docs/contracts/notice-event.md): the item's words, who it's for and its
        buttons' labels. Never a button's service or data: those stay looked up here (act)."""
        about = {k: item.about[k] for k in ("person", "group") if isinstance(item.about.get(k), str)}
        channels = [name for name, on in (("phone", item.phone), ("bell", item.bell), ("tv", item.tv)) if on]
        return {
            "v": NOTICE_EVENT_VERSION,
            "change": change,
            "key": item.key,
            "tag": item.channel_tag,
            "kind": item.kind or notice_kind(item),
            "urgency": item.urgency if item.urgency in URGENCIES else INFO,
            "title": item.title or "",
            "text": item.text,
            "audience": {
                "kind": PERSON[:-1] if item.audience.startswith(PERSON) else item.audience,
                "people": self.audience_people(item),
            },
            "about": about,
            "actions": [{"n": n, "label": action.label} for n, action in enumerate(item.actions)],
            # What a tap on the phone opens: its page, or a request's (phones.page_link)
            "link": item.link or (phones.page_link(item.opens) if item.opens else None),
            "channels": channels,
            "sent": item.sent.isoformat(),
            "expires": item.expires.isoformat() if item.expires is not None else None,
        }

    def audience_people(self, item: Item) -> list[str]:
        """The person entity ids an item is for: the adults on Hearth's page who get notices, everyone on it (the
        household), the person, the administrators' persons; else the persons behind the phones it goes to."""
        audience = item.audience
        options = self.options
        if audience == ADULTS:
            off = set(options.get(phones.CONF_ASK_NOTIFY_OFF) or [])
            return [p for p in phones.adults(options) if p not in off]
        if audience == HOUSEHOLD:
            return [p for p, _role in _household(options)]
        if audience.startswith(PERSON):
            return [audience[len(PERSON):]]
        if audience == ADMINS:
            found: set[str] = set()
            users = self.hass.data.get(ADMIN_USERS) or set()
        else:
            targets = self.item_targets(item)
            found = {p.person for p in targets if p.person}
            users = self._users(targets)
        return sorted(
            found | {s.entity_id for s in self.hass.states.async_all("person") if s.attributes.get("user_id") in users}
        )

    # Audiences

    def item_targets(self, item: Item) -> list[phones.Phone]:
        """The phones [item] goes to: its own (Item.to), only ones that are there; else its audience's."""
        if item.to is not None:
            return [p for p in item.to if self.hass.services.has_service(p.domain, p.service)]
        return self.targets(item.audience)

    def targets(self, audience: str) -> list[phones.Phone]:
        """The phones an audience's items go to, each once, only ones that are there."""
        options = self.options
        if audience == ADULTS:
            return phones.phones(self.hass, options)
        if audience in (CHOSEN_PHONE, SCHEDULE_PHONE):
            from .apps import CONF_ASK_NOTIFY

            service = options.get(CONF_ASK_NOTIFY)
            if audience == SCHEDULE_PHONE:
                from .schedule import ScheduleConfig

                service = ScheduleConfig.from_options(options).notify or service
            return [phone] if (phone := self._service_phone(service)) else []
        if audience == ADMINS:
            return admin_phones(self.hass)[0]
        if audience.startswith(PERSON):
            person = audience[len(PERSON):]
            return [
                phones.Phone(service, person, os)
                for service, os in phones.person_phones(self.hass, person)
                if self.hass.services.has_service("notify", service)
            ]
        if audience == HOUSEHOLD:
            found: list[phones.Phone] = []
            for person, _role in _household(options):
                for service, os in phones.person_phones(self.hass, person):
                    if self.hass.services.has_service("notify", service) and all(p.service != service for p in found):
                        found.append(phones.Phone(service, person, os))
            return found
        return []

    def _service_phone(self, service: str | None) -> phones.Phone | None:
        """A service chosen in the options ("notify.mobile_app_x", or another domain's), when it's there."""
        if not service or "." not in service:
            return None
        domain, name = service.split(".", 1)
        if not self.hass.services.has_service(domain, name):
            return None
        return phones.Phone(name, None, None, domain=domain)

    def _users(self, targets: list[phones.Phone]) -> set[str]:
        """The Home Assistant users behind the phones told: each companion app's own user, and its person's."""
        by_service = {
            phones.service_of(e): e.data.get("user_id") for e in self.hass.config_entries.async_entries(phones.MOBILE_APP)
        }
        users: set[str] = set()
        for phone in targets:
            if user := by_service.get(phone.service):
                users.add(user)
            if phone.person and (state := self.hass.states.get(phone.person)) and state.attributes.get("user_id"):
                users.add(state.attributes["user_id"])
        return users

    # A button

    async def act(self, action: str, user) -> bool:
        """A HEARTH_ACT button from an adult's phone (the caller checked the adult): runs the item's action as them
        when the item reached them. False when [action] isn't one; an unknown or expired item is ignored."""
        if not action.startswith(ACT_PREFIX):
            return False
        parts = action.split("|")
        item = self.item(parts[1]) if len(parts) == 3 else None
        if item is None or not (parts[2].isascii() and parts[2].isdigit()) or int(parts[2]) >= len(item.actions):
            _LOGGER.debug("A Hearth notification button for something gone was ignored")
            return True
        n = int(parts[2])
        chosen = item.actions[n]
        allowed = user.is_admin if item.audience == ADMINS else user.id in item.reached
        if not allowed or not (chosen.service or chosen.dismiss):
            _LOGGER.warning("A Hearth notification button from someone it wasn't for was ignored")
            return True
        if chosen.dismiss:
            self.clear(item.key)
            return True
        if item.about.get("via"):
            # An assistant's action an adult approves (llm_api.py, voice): its history says how, and who tapped
            from .llm_api import run_audited

            about = item.about
            await run_audited(
                self.hub, about["via"], user.id, about.get("tool"), about.get("person"), dict(about.get("audit") or {}),
                self.run(chosen, user.id),
            )
        elif await self.run(chosen, user.id) and item.about.get("notice"):
            # A phone approval of a TV notice's button: who answered it goes in the history
            from .notices import VIA_PHONE, log_answer

            log_answer(self.hub, item.about, VIA_PHONE, user_id=user.id)
        if item.once:
            self.clear(item.key)
        return True

    @staticmethod
    def runs(action: Action) -> bool:
        """Whether [action] would run: a service, in the hearth domain only."""
        service = action.service or ""
        return "." in service and service.split(".", 1)[0] == DOMAIN

    async def run(self, action: Action, user_id: str | None) -> bool:
        """Runs a button's service as [user_id] (Context(user_id); none: the household's own, as an automation's).
        Only Hearth's own services, which check the adult and the person themselves. True when it ran."""
        if not self.runs(action):
            _LOGGER.warning("A Hearth notification button for %s was refused: only hearth services run", action.service)
            return False
        domain, service = action.service.split(".", 1)
        try:
            await call_service(self.hass,
                domain, service, dict(action.data), blocking=True, context=Context(user_id=user_id)
            )
        except Exception as err:  # noqa: BLE001 - a button has nobody to raise to
            _LOGGER.warning("A Hearth notification button's %s failed: %s", action.service, err)
            return False
        return True


ADMIN_USERS = f"{DOMAIN}_admin_users"


async def async_note_admins(hass: HomeAssistant) -> list[dict[str, Any]]:
    """Looks up the administrators (their phones are found from it, as the ADMINS audience's) and says who they are:
    [{name (their person's, else their user's), phone (a companion app of theirs will be told)}]."""
    users = [u for u in await hass.auth.async_get_users() if u.is_admin and u.is_active and not u.system_generated]
    hass.data[ADMIN_USERS] = {u.id for u in users}
    by_user = admin_phones(hass)[1]
    names = {
        state.attributes.get("user_id"): state.name for state in hass.states.async_all("person")
    }
    return sorted(
        ({"name": names.get(u.id) or u.name or "Administrator", "phone": bool(by_user.get(u.id))} for u in users),
        key=lambda a: a["name"].casefold(),
    )


def admin_phones(hass: HomeAssistant) -> tuple[list[phones.Phone], dict[str, list[str]]]:
    """The administrators' companion apps (as last looked up, async_note_admins): the apps their users registered and
    their persons' (each once, only ones that are there), and each administrator's notify services."""
    ids = hass.data.get(ADMIN_USERS) or set()
    found: list[phones.Phone] = []
    by_user: dict[str, list[str]] = {}

    def add(user_id: str, service: str | None, person: str | None, os: str | None) -> None:
        if not service or not hass.services.has_service("notify", service):
            return
        by_user.setdefault(user_id, []).append(service)
        if all(p.service != service for p in found):
            found.append(phones.Phone(service, person, os))

    for state in hass.states.async_all("person"):
        if (user_id := state.attributes.get("user_id")) in ids:
            for service, os in phones.person_phones(hass, state.entity_id):
                add(user_id, service, state.entity_id, os)
    for entry in hass.config_entries.async_entries(phones.MOBILE_APP):
        if (user_id := entry.data.get("user_id")) in ids:
            add(user_id, phones.service_of(entry), None, phones._os(entry))
    return found, by_user


def _household(options: Mapping[str, Any]) -> list[tuple[str, str]]:
    """Everyone on Hearth's page, adults and kids: (person entity id, role)."""
    return sorted((p, role) for p, role in (options.get(CONF_ROLES) or {}).items() if role in ("adult", "kid"))


def notice_kind(item: Item) -> str:
    """An item's kind by its key's or tag's start (KINDS_BY_PREFIX); "other" when none fits."""
    for prefix, kind in KINDS_BY_PREFIX:
        if item.key.startswith(prefix) or item.channel_tag.startswith(prefix):
            return kind
    return "other"


def attention(hass: HomeAssistant) -> Attention:
    """For a notice outside the household (a pairing, the new apps' list): the loaded household's, else one without
    options (the bell needs none)."""
    entries = hass.config_entries.async_loaded_entries(DOMAIN)
    hub = entries[0].runtime_data if entries else None
    return hub.attention if hub is not None else Attention(hass)
