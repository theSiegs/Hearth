"""The household's Hearth devices as Home Assistant knows them: their secrets, what each last said, and pairing."""

from __future__ import annotations

from dataclasses import dataclass, field
import hashlib
import hmac
import secrets
from datetime import datetime, timedelta
import logging
from typing import Any

from homeassistant.config_entries import ConfigEntry
from homeassistant.core import HomeAssistant, callback
from homeassistant.helpers.dispatcher import async_dispatcher_send
from homeassistant.helpers.storage import Store
from homeassistant.util import dt as dt_util

from .const import (
    DOMAIN,
    APPROVED_EXPIRES,
    CONF_DEVICES,
    CONF_KIND,
    CONF_MODEL,
    CONF_PAIRED_AT,
    CONF_PERSON,
    CONF_PUSH_TOPIC,
    CONF_SECRET_HASH,
    CONF_SW_VERSION,
    CONNECTED_WITHIN,
    KIND_MOBILE,
    MAX_EVENT_POSTS,
    MAX_NOTICE_POSTS,
    MAX_PENDING_PAIRINGS,
    MAX_SETTINGS_CALLS,
    MAX_STATUS_POSTS,
    PAIRING_EXPIRES,
    PAIRING_INTERVAL_PER_ADDRESS,
    EVENT_DEVICE_CHECK_FAILED,
    EVENT_DEVICE_PAIRED,
    KIND_TV,
    CONF_CLIENT,
    MAX_TICKETS,
    TICKET_EXPIRES,
    default_caps,
    SIGNAL_DEVICE_ADDED,
    SIGNAL_PAIRINGS,
    SIGNAL_STATUS,
    STATUS_WINDOW,
    STORAGE_KEY,
    STORAGE_VERSION,
)
from .asks import Asks
from .fs_requests import RequestTracker
from .adult_offer import AdultOffers
from .attention import ADMINS, ADULTS, Attention, Item
from .client import checks_of, locked
from .client_settings import ClientSettings
from .glint_agent import GlintAgent
from .pin_grants import PinGrants
from .commands import Commands
from .push import PushChannel, new_topic
from .suggest_push import SuggestPush
from .wait import DeviceWaits
from .switch_approval import SwitchApprovals
from .household import Household
from .parent_pin import EVENT_PARENT_PIN_LOCKED_OUT

_LOGGER = logging.getLogger(__name__)

# A status's counts for its day (what _on_hearth_day keeps when the day isn't Hearth's)
_COUNTS = ("seconds_today", "app_seconds_today", "playing_seconds_today", "usage_today")
# A device's day may differ from Hearth's this close to midnight without its clock check failing
CLOCK_SLACK = timedelta(minutes=30)


def _its_own_date(posted: str, status: dict[str, Any]) -> bool:
    """Whether [posted] is today's date where the device is, by the offset from UTC it says (utc_offset_minutes)."""
    offset = status.get("utc_offset_minutes")
    if offset is None:
        return False
    there = dt_util.utcnow() + timedelta(minutes=offset)
    return there.date().isoformat() == posted


def _midnight(now: datetime) -> datetime:
    return now.replace(hour=0, minute=0, second=0, microsecond=0)


def _most(a: Any, b: Any) -> Any:
    """The larger of two counts; None when neither says."""
    known = [v for v in (a, b) if isinstance(v, (int, float))]
    return max(known) if known else None


def _most_each(a: Any, b: Any) -> dict[str, Any]:
    """Each item's larger count of two {item: seconds}."""
    out = dict(a or {})
    for item, seconds in (b or {}).items():
        out[item] = _most(out.get(item), seconds)
    return out


def hash_secret(secret: str) -> str:
    return hashlib.sha256(secret.encode()).hexdigest()


@dataclass
class Pairing:
    """A device asking to join, waiting for an administrator to check its code."""

    pairing_id: str
    code: str
    nonce_hash: str
    device_id: str
    kind: str
    name: str
    model: str | None
    sw_version: str | None
    expires: datetime
    # A phone's person, chosen when an administrator confirms
    person: str | None = None
    # Set once approved: the secret, handed to the device once
    secret: str | None = None
    # A phone's ntfy topic, made when it's approved (push.py)
    push_topic: str | None = None
    denied: bool = False
    # The client app it says it is (client.clean_client), shown to the adult and locked when they approve
    client: dict[str, Any] | None = None
    # Who a phone says it's for (the pair body's person_name and role, untrusted: shown to the administrators), and the
    # household's person of that name, when exactly one has it (what Approve on their notification pairs it as)
    for_name: str | None = None
    for_role: str | None = None
    for_person: str | None = None


@dataclass
class Ticket:
    """A single-use pairing ticket a paired TV asked for: the device that redeems it pairs with no code to check."""

    kind: str
    # A phone's person (an adult's); None for a TV
    person: str | None
    # The paired TV that asked for it
    minted_by: str
    expires: datetime


def _shared(hass: HomeAssistant) -> dict[str, dict]:
    """Pairings kept outside the entry: approving one saves the device, which reloads the entry, and the device
    asking for its secret meanwhile must still find it. Tickets too, so an options change doesn't void one."""
    shared = hass.data.setdefault(f"{DOMAIN}_pairing", {"pairings": {}, "asked_at": {}})
    shared.setdefault("tickets", {})
    return shared


@dataclass
class PinLockout:
    """Wrong parent PINs in a row from one device, and the lockout they earned."""

    failures: int = 0
    locked_until: datetime | None = None
    # Guesses being checked right now (api._check_pin): past the free tries, one at a time
    checking: int = 0


def pin_lockout(hass: HomeAssistant, device_id: str) -> PinLockout:
    """A device's parent-PIN lockout, kept outside the entry like the pairings: changing an option reloads the
    entry, and that must not hand someone guessing the PIN a fresh set of tries. Saved too (save_pin_lockouts), so
    a restart doesn't either."""
    lockouts: dict[str, PinLockout] = hass.data.setdefault(f"{DOMAIN}_pin_lockout", {})
    return lockouts.setdefault(device_id, PinLockout())


def _pin_store(hass: HomeAssistant):
    from homeassistant.helpers.storage import Store

    key = f"{DOMAIN}_pin_lockout_store"
    if key not in hass.data:
        hass.data[key] = Store(hass, 1, f"{DOMAIN}.pin_lockout")
    return hass.data[key]


@callback
def save_pin_lockouts(hass: HomeAssistant) -> None:
    """Every device's wrong PINs in a row and lockout, saved a moment later."""

    def data() -> dict[str, Any]:
        lockouts: dict[str, PinLockout] = hass.data.get(f"{DOMAIN}_pin_lockout", {})
        return {
            device_id: {
                "failures": lock.failures,
                "locked_until": lock.locked_until.isoformat() if lock.locked_until else None,
            }
            for device_id, lock in lockouts.items()
            if lock.failures or lock.locked_until
        }

    _pin_store(hass).async_delay_save(data, 1)


async def async_load_pin_lockouts(hass: HomeAssistant) -> None:
    """The lockouts saved before Home Assistant stopped, once per start."""
    flag = f"{DOMAIN}_pin_lockout_loaded"
    if hass.data.get(flag):
        return
    hass.data[flag] = True
    for device_id, kept in (await _pin_store(hass).async_load() or {}).items():
        if not isinstance(kept, dict):
            continue
        lock = pin_lockout(hass, device_id)
        lock.failures = max(lock.failures, int(kept.get("failures") or 0))
        until = dt_util.parse_datetime(kept["locked_until"]) if isinstance(kept.get("locked_until"), str) else None
        if until is not None and (lock.locked_until is None or until > lock.locked_until):
            lock.locked_until = until


def find_pairing(hass: HomeAssistant, pairing_id: str, nonce: str | None) -> Pairing | None:
    """A waiting pairing, only for the device that started it (it holds the nonce); works while the entry reloads."""
    pairings: dict[str, Pairing] = _shared(hass)["pairings"]
    now = dt_util.utcnow()
    for gone in [p.pairing_id for p in pairings.values() if p.expires <= now]:
        del pairings[gone]
    pairing = pairings.get(pairing_id)
    if pairing is None or not nonce or not hmac.compare_digest(pairing.nonce_hash, hash_secret(nonce)):
        return None
    return pairing


def collect_secret(hass: HomeAssistant, pairing: Pairing) -> str | None:
    """The approved secret, once: the pairing ends with it."""
    secret = pairing.secret
    if secret is not None:
        _shared(hass)["pairings"].pop(pairing.pairing_id, None)
    return secret


@dataclass
class DeviceState:
    status: dict[str, Any] | None = None
    seen: datetime | None = None
    posts: list[datetime] = field(default_factory=list)
    event_posts: list[datetime] = field(default_factory=list)
    notice_posts: list[datetime] = field(default_factory=list)
    settings_calls: list[datetime] = field(default_factory=list)
    # A phone's or tablet's count at its first post after pairing, taken off the rest of that day (_note_baseline):
    # {"paired_at", "day" (None: it first posted on a later day), "seconds", "apps"}
    baseline: dict[str, Any] | None = None
    # A TV's own checks failing since (check id -> when it first failed), and those the adults were told of
    failing: dict[str, datetime] = field(default_factory=dict)
    told_failing: set[str] = field(default_factory=set)


# A TV's own check failing this long (its accessibility service off, say) is told to the adults; a moment's (the
# service connecting just after the TV starts) isn't
CHECK_FAILING_TELL_AFTER = timedelta(minutes=5)


class HearthHub:
    """One per config entry (the household)."""

    def __init__(self, hass: HomeAssistant, entry: ConfigEntry) -> None:
        self.hass = hass
        self.entry = entry
        self._store: Store[dict[str, Any]] = Store(hass, STORAGE_VERSION, f"{STORAGE_KEY}.{entry.entry_id}")
        self._states: dict[str, DeviceState] = {}
        # A Home Assistant user's own asks (hearth/ask), counted as a device's events posts are
        self._user_posts: dict[str, list] = {}
        # Kept outside the entry, so a pairing waiting to be collected survives the entry reloading
        shared = _shared(hass)
        self._pairings: dict[str, Pairing] = shared["pairings"]
        self._asked_at: dict[str, datetime] = shared["asked_at"]
        # Pairing tickets by their hash (the ticket itself is never kept)
        self._tickets: dict[str, Ticket] = shared["tickets"]
        # Telling people (the companion app, the bell): first, so everything after can
        self.attention = Attention(hass, self)
        self.household = Household(hass, self)
        self.asks = Asks(hass, self)
        # Family Safety requests read from its Pending Requests sensors (the released one fires no events)
        self.fs_requests = RequestTracker(hass, self)
        # One-shot commands for the TVs (hearth.play_on_tv), handed over in their state documents
        self.commands = Commands(hass)
        # "Something changed" pings to the phones, when the household has a push server
        self.push = PushChannel(hass, self)
        # The suggestions the household chose, on the adults' phones
        self.suggest_push = SuggestPush(hass, self)
        self.waits = DeviceWaits(hass, self)
        # Paired clients' own documents, kept without being read (client_settings.py), and the writes a parent PIN
        # typed on a device allows it (pin_grants.py)
        self.client_settings = ClientSettings(hass, self)
        self.pin_grants = PinGrants(hass)
        # Glint agents through Hearth: each Glint phone's inbox, the tool calls waiting on it, its doorbell (glint_agent.py)
        self.glint_agent = GlintAgent(hass, self)
        # Phone approval of a switch into an adult's Google TV profile, asked for a paired TV (switch_approval.py)
        self.switch_approvals = SwitchApprovals(hass, self)
        # "Make this person an adult?", asked of the administrators once a person (adult_offer.py)
        self.adult_offers = AdultOffers(hass, self)

    # The devices

    @property
    def devices(self) -> dict[str, dict[str, Any]]:
        return self.entry.data.get(CONF_DEVICES, {})

    def kind(self, device_id: str) -> str | None:
        device = self.devices.get(device_id)
        return device.get(CONF_KIND) if device else None

    def has_cap(self, device_id: str, cap: str) -> bool:
        """Whether the device can be sent [cap] (const.CAPS): what it said in its status, once it has said; until
        then its kind's (default_caps), so a device from before caps keeps what it had."""
        declared = (self.state(device_id).status or {}).get("caps")
        if declared is not None:
            return cap in declared
        return cap in default_caps(self.kind(device_id))

    def state(self, device_id: str) -> DeviceState:
        return self._states.setdefault(device_id, DeviceState())

    async def async_load(self) -> None:
        await self.household.async_load()
        await self.fs_requests.async_load()
        await self.client_settings.async_load()
        await self.glint_agent.async_load()
        await self.adult_offers.async_load()
        stored = await self._store.async_load() or {}
        for device_id, kept in stored.items():
            if device_id not in self.devices or not isinstance(kept, dict):
                continue
            state = self.state(device_id)
            state.status = kept.get("status")
            seen = kept.get("seen")
            state.seen = dt_util.parse_datetime(seen) if isinstance(seen, str) else None
            baseline = kept.get("baseline")
            state.baseline = baseline if isinstance(baseline, dict) else None

    def authorized(self, device_id: str, secret: str | None) -> bool:
        """The secret is this device's (compared in constant time; a removed device has none)."""
        device = self.devices.get(device_id)
        if device is None or not secret:
            return False
        return hmac.compare_digest(device.get(CONF_SECRET_HASH, ""), hash_secret(secret))

    def connected(self, device_id: str) -> bool:
        seen = self.state(device_id).seen
        return seen is not None and dt_util.utcnow() - seen < CONNECTED_WITHIN

    def too_often(self, device_id: str) -> bool:
        """Notes a post, and says whether the device posted too many in the last minute."""
        now = dt_util.utcnow()
        state = self.state(device_id)
        state.posts = [t for t in state.posts if now - t < STATUS_WINDOW]
        if len(state.posts) >= MAX_STATUS_POSTS:
            return True
        state.posts.append(now)
        return False

    def too_many_events(self, device_id: str) -> bool:
        """The same for its events posts, counted on their own."""
        now = dt_util.utcnow()
        state = self.state(device_id)
        state.event_posts = [t for t in state.event_posts if now - t < STATUS_WINDOW]
        if len(state.event_posts) >= MAX_EVENT_POSTS:
            return True
        state.event_posts.append(now)
        return False

    def too_many_notice_presses(self, device_id: str) -> bool:
        """The same for its notices' button presses, counted on their own."""
        now = dt_util.utcnow()
        state = self.state(device_id)
        state.notice_posts = [t for t in state.notice_posts if now - t < STATUS_WINDOW]
        if len(state.notice_posts) >= MAX_NOTICE_POSTS:
            return True
        state.notice_posts.append(now)
        return False

    def too_many_settings_calls(self, device_id: str) -> bool:
        """The same for its client-settings calls (reads and writes), counted on their own."""
        now = dt_util.utcnow()
        state = self.state(device_id)
        state.settings_calls = [t for t in state.settings_calls if now - t < STATUS_WINDOW]
        if len(state.settings_calls) >= MAX_SETTINGS_CALLS:
            return True
        state.settings_calls.append(now)
        return False

    def too_many_user_asks(self, user_id: str) -> bool:
        """too_many_events for a Home Assistant user's own asks (hearth/ask)."""
        now = dt_util.utcnow()
        posts = [t for t in self._user_posts.get(user_id, []) if now - t < STATUS_WINDOW]
        self._user_posts[user_id] = posts
        if len(posts) >= MAX_EVENT_POSTS:
            return True
        posts.append(now)
        return False

    @callback
    def update_status(self, device_id: str, status: dict[str, Any]) -> None:
        state = self.state(device_id)
        # A TV checks the Parent PIN itself: a lockout there is told as for a phone that asked here
        before = (state.status or {}).get("pin_lockouts")
        after = status.get("pin_lockouts")
        if before is not None and after is not None and after > before:
            self.hass.bus.async_fire(
                EVENT_PARENT_PIN_LOCKED_OUT, {"device_id": device_id, "lockouts": after - before, "retry_in": None}
            )
        # A device that said its caps once keeps them while its later posts leave them out; its client and checks too
        for kept in ("caps", "client", "checks"):
            if status.get(kept) is None and (state.status or {}).get(kept) is not None:
                status = {**status, kept: state.status[kept]}
        status = self._on_hearth_day(device_id, state.status, status)
        self._tell_failed_checks(device_id, state.status, status)
        if self.kind(device_id) == KIND_TV:
            self._tell_failing_tv_checks(device_id, state, status)
        self._note_baseline(device_id, status)
        state.status = status
        state.seen = dt_util.utcnow()
        # What the TV ran of its commands leaves the queue (its answer no longer carries them)
        if status.get("commands_done"):
            self.commands.take_done(device_id, status["commands_done"])
        self._store.async_delay_save(self._data_to_save, 30)
        async_dispatcher_send(self.hass, SIGNAL_STATUS.format(device_id))
        # A TV paired after it had rules of its own: they're the kids' first budgets
        if status.get("local_rules") and self.kind(device_id) == KIND_TV:
            self.household.import_local_rules(device_id, status["local_rules"])
        self.household.recompute()

    def _tell_failing_tv_checks(self, device_id: str, state: DeviceState, status: dict[str, Any]) -> None:
        """A TV's own check that has failed for CHECK_FAILING_TELL_AFTER (its accessibility service off: apps opened
        outside Hearth aren't held, and time in them isn't counted) is told to the adults once; it's cleared once it
        passes again."""
        now = dt_util.utcnow()
        name = (self.devices.get(device_id) or {}).get("name") or "A TV"
        for check in status.get("checks") or []:
            check_id, key = check["id"], f"hearth_check_{device_id}_{check['id']}"
            if check["ok"]:
                state.failing.pop(check_id, None)
                if check_id in state.told_failing:
                    state.told_failing.discard(check_id)
                    self.attention.clear(key)
                continue
            since = state.failing.setdefault(check_id, now)
            if check_id in state.told_failing or now - since < CHECK_FAILING_TELL_AFTER:
                continue
            state.told_failing.add(check_id)
            if check_id == "accessibility":
                text = (
                    f"{name}: Hearth's accessibility service is off. Apps opened outside Hearth aren't held and their "
                    "time isn't counted until it's on again (Settings > Accessibility on the TV)."
                )
            else:
                text = f"{name}: this isn't so any more: {check['label']}."
            self.attention.notify(
                Item(key, text, title="A TV needs a look", urgency="notice", audience=ADULTS)
            )

    def _tell_clock_changed(self, device_id: str, zone: int | None = None) -> None:
        """The adults hear once that a device's date was changed (a kid moving a phone's clock to get a new day): its
        counts are kept, and its row on Hearth's page fails the clock check until its date is Hearth's again. With
        [zone] (its offset from UTC in minutes), the date is right for the time zone the device is set to: a trip, or
        a time zone changed on purpose; no failed check, and it says so."""
        device = self.devices.get(device_id) or {}
        person = device.get(CONF_PERSON)
        whose = self.household.person_name(person) if person else None
        name = device.get("name") or "A device"
        what = f"{whose}'s {name}" if whose else name
        if zone is not None:
            hours, minutes = divmod(abs(zone), 60)
            utc = f"UTC{'-' if zone < 0 else '+'}{hours}" + (f":{minutes:02d}" if minutes else "")
            text = f"{what} is set to another time zone ({utc}). Hearth keeps counting today's time by its own clock."
            title = "A device is in another time zone"
        else:
            text = f"{what}: its date was changed. Hearth keeps counting today's time by its own clock."
            title = "A device's clock was changed"
        self.attention.notify(
            Item(
                f"hearth_clock_{device_id}",
                text,
                title=title,
                urgency="notice",
                audience=ADULTS,
                about={"person": person} if person else {},
            )
        )

    def _on_hearth_day(
        self, device_id: str, before: dict[str, Any] | None, status: dict[str, Any]
    ) -> dict[str, Any]:
        """Hearth judges the day by its own clock, never a device's (a kid can move a phone's clock). A status for
        another day than Hearth's (the clock moved forward or back) keeps the counts Hearth had, and says so
        (clock_off: the day it said, a failed clock check); one for Hearth's day never counts less than the device's
        last status that day did (each app's seconds, the total, each TV profile's)."""
        now = dt_util.now()
        today = now.date().isoformat()
        posted = status.get("day")
        before = before or {}
        if posted is None:
            return status
        if posted != today:
            # A clock a few minutes off around midnight is no news, nor a device in another time zone whose own date
            # is the one it says (a phone on a trip); its counts are kept all the same
            to_midnight = min(now - _midnight(now), _midnight(now) + timedelta(days=1) - now)
            zone = status.get("utc_offset_minutes") if _its_own_date(posted, status) else None
            off = posted if to_midnight > CLOCK_SLACK and zone is None else None
            if off and not before.get("clock_off"):
                _LOGGER.warning(
                    "Hearth device %s posted a status for %s, but Hearth's day is %s: its counts are kept as they were",
                    device_id, posted, today,
                )
                self._tell_clock_changed(device_id)
            # Another time zone: told once per zone, and its row's clock check stays passed
            told = before.get("zone_told")
            if zone is not None and to_midnight > CLOCK_SLACK and told != zone:
                self._tell_clock_changed(device_id, zone)
                told = zone
            return {
                **status,
                **{key: before.get(key) for key in _COUNTS},
                "day": before.get("day"),
                "clock_off": off,
                "zone_told": told,
            }
        status = {**status, "clock_off": None, "zone_told": before.get("zone_told")}
        if before.get("day") != today:
            return status
        status["seconds_today"] = _most(before.get("seconds_today"), status.get("seconds_today"))
        for key in ("app_seconds_today", "playing_seconds_today"):
            status[key] = _most_each(before.get(key), status.get(key))
        usage = {**(before.get("usage_today") or {})}
        for profile_id, mine in (status.get("usage_today") or {}).items():
            had = usage.get(profile_id) or {}
            usage[profile_id] = {
                **mine,
                "seconds": _most(had.get("seconds"), mine.get("seconds")),
                "apps": _most_each(had.get("apps"), mine.get("apps")),
                "playing": _most_each(had.get("playing"), mine.get("playing")),
            }
        status["usage_today"] = usage
        return status

    def _note_baseline(self, device_id: str, status: dict[str, Any]) -> None:
        """A phone's or tablet's first post after it paired: on the day it paired, what it counted so far is from
        before Hearth had it (another launcher in front all night, say), so it's kept and taken off the rest of that
        day (household._device_reading). Once per pairing: pairing again takes a new one. A TV counts its own
        profiles."""
        device = self.devices.get(device_id) or {}
        paired_at = device.get(CONF_PAIRED_AT)
        state = self.state(device_id)
        if device.get(CONF_KIND) == KIND_TV or not paired_at or (state.baseline or {}).get("paired_at") == paired_at:
            return
        paired = dt_util.parse_datetime(paired_at)
        day = dt_util.as_local(paired).date().isoformat() if paired else None
        if day is None or status.get("day") != day:
            state.baseline = {"paired_at": paired_at, "day": None}
            return
        state.baseline = {
            "paired_at": paired_at,
            "day": day,
            "seconds": status.get("seconds_today") or 0,
            "apps": dict(status.get("app_seconds_today") or {}),
        }

    def checks(self, device_id: str) -> list[dict[str, Any]]:
        """A device's checks as its row shows them: its own, then Hearth's client check (client.py)."""
        return checks_of(self.devices.get(device_id, {}), self.state(device_id).status)

    def _tell_failed_checks(self, device_id: str, before: dict[str, Any] | None, after: dict[str, Any]) -> None:
        """hearth_device_check_failed for each check that is false now and wasn't in the device's last status."""
        device = self.devices.get(device_id, {})
        was = {c["id"]: c["ok"] for c in checks_of(device, before)} if before is not None else {}
        for check in checks_of(device, after):
            if check["ok"] is False and was.get(check["id"]) is not False:
                self.hass.bus.async_fire(
                    EVENT_DEVICE_CHECK_FAILED,
                    {
                        "device_id": device_id,
                        "name": device.get("name"),
                        "person": device.get(CONF_PERSON),
                        "check": check["id"],
                        "label": check["label"],
                    },
                )

    @callback
    def _data_to_save(self) -> dict[str, Any]:
        return {
            device_id: {
                "status": state.status,
                "seen": state.seen.isoformat() if state.seen else None,
                **({"baseline": state.baseline} if state.baseline else {}),
            }
            for device_id, state in self._states.items()
            if device_id in self.devices
        }

    async def async_flush(self) -> None:
        """Saves what the devices last said now (Home Assistant also does when it stops)."""
        await self._store.async_save(self._data_to_save())
        await self.household.async_flush()
        await self.household.apps.async_flush()
        await self.fs_requests.async_flush()
        await self.client_settings.async_flush()
        await self.glint_agent.async_flush()
        await self.adult_offers.async_flush()

    async def async_remove_device(self, device_id: str) -> None:
        """Forgets a device: its secret stops working at once."""
        # Its device documents go with it, first and saved at once: updating the entry may reload it straight away;
        # person and household documents stay until an adult removes them
        self.pin_grants.forget(device_id)
        self.glint_agent.forget(device_id)
        self.client_settings.remove_device(device_id)
        await self.client_settings.async_flush()
        devices = {k: v for k, v in self.devices.items() if k != device_id}
        self.hass.config_entries.async_update_entry(self.entry, data={**self.entry.data, CONF_DEVICES: devices})
        self._states.pop(device_id, None)
        self.commands.forget(device_id)
        await self._store.async_save(self._data_to_save())
        self.household.recompute()

    # Pairing

    def _drop_expired(self) -> None:
        now = dt_util.utcnow()
        for pairing_id in [p.pairing_id for p in self._pairings.values() if p.expires <= now]:
            del self._pairings[pairing_id]

    def start_pairing(
        self,
        address: str,
        device_id: str,
        kind: str,
        name: str,
        model: str | None,
        sw_version: str | None,
        nonce: str,
        client: dict[str, Any] | None = None,
        for_name: str | None = None,
        for_role: str | None = None,
    ) -> Pairing | None:
        """A device asks to pair; None when too many are waiting or this address asked a moment ago. A phone may say
        who it's for ([for_name], [for_role]): shown to the administrators, never trusted further."""
        from .notifications import clear_pairing

        self._drop_expired()
        now = dt_util.utcnow()
        last = self._asked_at.get(address)
        if last is not None and now - last < PAIRING_INTERVAL_PER_ADDRESS:
            return None
        if len(self._pairings) >= MAX_PENDING_PAIRINGS:
            return None
        self._asked_at[address] = now
        # The same device asking again replaces its earlier request (and its notification)
        for old in [p.pairing_id for p in self._pairings.values() if p.device_id == device_id]:
            del self._pairings[old]
            clear_pairing(self.hass, old)
        named = [
            state.entity_id
            for state in self.hass.states.async_all("person")
            if for_name and kind == KIND_MOBILE and state.name.casefold() == for_name.casefold()
        ]
        pairing = Pairing(
            for_name=for_name,
            for_role=for_role,
            for_person=named[0] if len(named) == 1 else None,
            pairing_id=secrets.token_urlsafe(16),
            code=f"{secrets.randbelow(1_000_000):06d}",
            nonce_hash=hash_secret(nonce),
            device_id=device_id,
            kind=kind,
            name=name,
            model=model,
            sw_version=sw_version,
            expires=now + PAIRING_EXPIRES,
            client=client,
        )
        self._pairings[pairing.pairing_id] = pairing
        async_dispatcher_send(self.hass, SIGNAL_PAIRINGS)
        return pairing

    def pending_pairings(self) -> list[Pairing]:
        """The devices waiting for an administrator to check their code."""
        self._drop_expired()
        return [p for p in self._pairings.values() if p.secret is None and not p.denied]

    def pairing(self, pairing_id: str) -> Pairing | None:
        self._drop_expired()
        return self._pairings.get(pairing_id)

    def pairing_for(self, pairing_id: str, nonce: str | None) -> Pairing | None:
        """The pairing, only for the device that started it (it holds the nonce)."""
        pairing = self.pairing(pairing_id)
        if pairing is None or not nonce or not hmac.compare_digest(pairing.nonce_hash, hash_secret(nonce)):
            return None
        return pairing

    async def async_approve(self, pairing_id: str, person: str | None = None) -> bool:
        """An administrator checked the code: the device joins (or gets a new secret, if it was here)."""
        pairing = self.pairing(pairing_id)
        if pairing is None or pairing.denied:
            return False
        secret = secrets.token_urlsafe(32)
        # A phone gets its own push topic; pairing again makes a new one, as it does a new secret
        topic = new_topic() if pairing.kind == KIND_MOBILE else None
        devices = {
            **self.devices,
            pairing.device_id: {
                "name": pairing.name,
                CONF_KIND: pairing.kind,
                CONF_MODEL: pairing.model,
                CONF_SW_VERSION: pairing.sw_version,
                CONF_SECRET_HASH: hash_secret(secret),
                CONF_PERSON: person,
                CONF_PAIRED_AT: dt_util.utcnow().isoformat(),
                **({CONF_PUSH_TOPIC: topic} if topic else {}),
                # The client app the adult saw when approving: pairing again is the only way to change it
                **({CONF_CLIENT: pinned} if (pinned := locked(pairing.client)) else {}),
            },
        }
        self.hass.config_entries.async_update_entry(self.entry, data={**self.entry.data, CONF_DEVICES: devices})
        pairing.secret = secret
        pairing.person = person
        pairing.push_topic = topic
        pairing.expires = dt_util.utcnow() + APPROVED_EXPIRES
        async_dispatcher_send(self.hass, SIGNAL_DEVICE_ADDED, pairing.device_id)
        async_dispatcher_send(self.hass, SIGNAL_PAIRINGS)
        return True

    # Tickets: one confirmed pairing adds the household's other TVs, and a parent's phone in one tap

    def mint_ticket(self, minted_by: str, kind: str, person: str | None) -> str | None:
        """A single-use ticket a paired TV hands to another TV of its household (kind tv) or to a phone an adult bound
        as a parent's (kind mobile, for that adult); None when too many are outstanding."""
        now = dt_util.utcnow()
        for gone in [h for h, t in self._tickets.items() if t.expires <= now]:
            del self._tickets[gone]
        if len(self._tickets) >= MAX_TICKETS:
            return None
        ticket = secrets.token_urlsafe(32)
        self._tickets[hash_secret(ticket)] = Ticket(kind, person if kind == KIND_MOBILE else None, minted_by,
                                                    now + TICKET_EXPIRES)
        return ticket

    async def async_redeem(
        self,
        ticket: str,
        device_id: str,
        kind: str,
        name: str,
        model: str | None,
        sw_version: str | None,
        client: dict[str, Any] | None = None,
    ) -> Pairing | None:
        """Pairs a device that holds a live ticket of its kind, at once (the TV that asked for the ticket vouched for
        it); None when the ticket is unknown, used, expired or of another kind. The ticket is spent either way."""
        now = dt_util.utcnow()
        held = self._tickets.pop(hash_secret(ticket), None)
        if held is None or held.expires <= now or held.kind != kind or held.minted_by not in self.devices:
            return None
        # A device already paired as another kind (an adult's phone, say) is never taken over by a ticket: re-pairing
        # the same TV after a reinstall is fine
        if device_id in self.devices and self.kind(device_id) != kind:
            return None
        for old in [p.pairing_id for p in self._pairings.values() if p.device_id == device_id]:
            del self._pairings[old]
        pairing = Pairing(
            pairing_id=secrets.token_urlsafe(16),
            code="",
            nonce_hash="",
            device_id=device_id,
            kind=kind,
            name=name,
            model=model,
            sw_version=sw_version,
            expires=now + APPROVED_EXPIRES,
            client=client,
        )
        self._pairings[pairing.pairing_id] = pairing
        by_name = self.devices[held.minted_by].get("name") or held.minted_by
        if not await self.async_approve(pairing.pairing_id, held.person):
            return None
        self.hass.bus.async_fire(
            EVENT_DEVICE_PAIRED,
            {
                "device_id": device_id,
                "name": name,
                "kind": kind,
                "person": held.person,
                "by": held.minted_by,
                "client": (client or {}).get("id"),
            },
        )
        self.attention.notify(
            Item(
                f"hearth_paired_{device_id}",
                f"**{name}** paired with Hearth through **{by_name}**, which is already paired. If that wasn't you, "
                "delete it in [Devices & services](/config/integrations/integration/hearth).",
                title="A Hearth device paired",
                urgency="notice",
                audience=ADMINS,
                bell=True,
                phone=False,
            )
        )
        return pairing

    def deny(self, pairing_id: str) -> None:
        pairing = self.pairing(pairing_id)
        if pairing is not None:
            pairing.denied = True
            async_dispatcher_send(self.hass, SIGNAL_PAIRINGS)

    def collect(self, pairing: Pairing) -> str | None:
        """The approved secret, once: the pairing ends with it."""
        secret = pairing.secret
        if secret is not None:
            self._pairings.pop(pairing.pairing_id, None)
        return secret
