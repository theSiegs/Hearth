"""Keeping Hearth and the parents' own apps (Family Link, Nintendo, Microsoft Family Safety) in step, both ways. See
docs/home-assistant-integration.md, Keeping the parents' apps in step.

- A parent's change in their app that lets a kid use what Hearth holds becomes a grant (grants.py; found by
  enforce.py, which knows what it holds).
- An adult ending a grant early from Hearth: where that maps to a write in the first-party app, it's made (a Family
  Link bonus reset, Family Safety extra time cancelled); a re-lock is simply Hearth's hold coming back.
"""

from __future__ import annotations

from datetime import timedelta
import logging
import math
from typing import TYPE_CHECKING, Any

import voluptuous as vol

from homeassistant.core import HomeAssistant, callback
from homeassistant.exceptions import HomeAssistantError, ServiceValidationError
from homeassistant.helpers import entity_registry as er
from homeassistant.helpers.storage import Store
from homeassistant.util import dt as dt_util

from .entry_tasks import entry_task
from . import grants as g
from .counting import ALL
from .enforce import (
    FAMILY_LINK,
    FAMILY_SAFETY,
    FS_ALLOW_UNTIL,
    FS_FROM_HEARTH,
    FS_OWN_TOLERANCE,
    FS_HOLD_BONUS_OURS,
    FS_HOLD_OURS,
    FS_HOLD_PARENT,
    NINTENDO,
    QUIET_AFTER_CALL,
    RETRY,
    _utc as _when,
    fs_accepts,
    fs_account_of,
    fs_hold_state,
)
from .exceptions import end_of_day
from .activity import call_service

if TYPE_CHECKING:
    from .grants import Grant
    from .household import Household

_LOGGER = logging.getLogger(__name__)

FL_DOMAIN = "familylink"
FS_DOMAIN = "microsoft_family_safety"
# The platforms Family Safety can give extra time on (Windows only where the installed one takes it: fs_accepts)
FS_BONUS_PLATFORMS = ("Xbox", "Windows")
MINUTES_A_DAY = 24 * 60
# Family Safety extra time whose write failed is looked for this long (a few of its polls): one Microsoft applied
# anyway shows by then
POSSIBLY_GIVEN_WINDOW = timedelta(minutes=10)
SET_INTERVALS = "set_screentime_intervals"
# Family Safety's day_of_week: 0 is Sunday
FS_WEEKDAYS = ("sunday", "monday", "tuesday", "wednesday", "thursday", "friday", "saturday")
# A parent's change became a grant (its view)
EVENT_PARENT_GRANT = "hearth_parent_grant"


class NativeSync:
    """Hearth's side of the two-way sync with the first-party parental control apps."""

    def __init__(self, hass: HomeAssistant, household: Household, entry_id: str) -> None:
        self.hass = hass
        # What Hearth itself added in the first-party apps is kept over a restart: forgotten, Hearth's own Family
        # Link bonus would look like a parent's (a grant), and an allow would be given extra time a second time
        self._store: Store[dict[str, Any]] = Store(hass, 1, f"hearth.sync.{entry_id}")
        self.household = household
        # The entities whose change may be a parent's (a state change of one recomputes)
        self.watched: set[str] = set()
        # The Family Link bonus minutes Hearth added today, by person: {"day", "devices" {device id: minutes}}
        self.fl_added: dict[str, dict[str, Any]] = {}
        household.enforcement.on_applied = self.after_apply
        household.enforcement.fs_bonus_until = self.fs_bonus_until
        # Extra time Hearth gave in the first-party apps, by (person, why: allow:<id> or bonus:<when>)
        self._given: dict[tuple[str, str], dict[str, Any]] = {}
        # Family Safety allowed hours Hearth moved on a weekday's setting (no today_only: upstream's), to put back
        # itself after midnight: by <entity>|<platform>|<weekday> (async_windows_tick). Kept until put back or found
        # changed by a parent, over a restart and a missed midnight
        self.windows: dict[str, dict[str, Any]] = {}
        # Every end of a Family Safety platform's allowed hours Hearth moved for extra time, today and yesterday:
        # {person, platform, day, weekday, begin, end}, kept before the write. Bedtime sync reads them as Hearth's
        # own, whichever extra time moved it and after that extra time's record is gone (moved_windows)
        self.moved: list[dict[str, Any]] = []
        # Family Safety extra time whose write failed but may have been applied: {person, why, platform, until (what
        # Hearth asked for), error, at}; adopted as Hearth's own if it shows, dropped after POSSIBLY_GIVEN_WINDOW
        self.possibly_given: list[dict[str, Any]] = []

    async def async_load(self) -> None:
        stored = await self._store.async_load() or {}
        today = dt_util.now().date().isoformat()
        self.fl_added = {
            person: record
            for person, record in (stored.get("fl_added") or {}).items()
            if isinstance(record, dict) and record.get("day") == today
        }
        given = {}
        for key, record in (stored.get("given") or {}).items():
            person, sep, why = key.partition("|")
            if sep and isinstance(record, dict) and record.get("day") == today:
                given[(person, why)] = record
        self._given = given
        self.windows = {
            str(key): record
            for key, record in (stored.get("windows") or {}).items()
            if isinstance(record, dict)
            and all(isinstance(record.get(f), int) for f in ("begin", "end", "target", "target_begin"))
            and all(isinstance(record.get(f), str) for f in ("person", "entity_id", "platform", "day"))
            and record.get("weekday") in FS_WEEKDAYS
        }
        self.moved = _recent_moves(stored.get("moved"))
        self.possibly_given = [
            entry
            for entry in stored.get("possibly_given") or []
            if isinstance(entry, dict)
            and all(isinstance(entry.get(f), str) for f in ("person", "why", "platform", "until", "at"))
        ]

    def _data(self) -> dict[str, Any]:
        return {
            "fl_added": self.fl_added,
            "given": {f"{p}|{why}": r for (p, why), r in self._given.items()},
            "windows": self.windows,
            "moved": self.moved,
            "possibly_given": self.possibly_given,
        }

    def _save(self) -> None:
        self._store.async_delay_save(self._data, 2)

    async def async_flush(self) -> None:
        await self._store.async_save(self._data())

    def own_bonus(self) -> dict[str, float]:
        """The Family Link bonus minutes Hearth itself added today, by device id."""
        today = dt_util.now().date().isoformat()
        found: dict[str, float] = {}
        for record in self.fl_added.values():
            if record.get("day") == today:
                for device_id, minutes in record.get("devices", {}).items():
                    found[device_id] = found.get(device_id, 0) + minutes
        return found

    @callback
    def after_apply(self) -> None:
        """Enforcement just held or let go: what it holds now is watched (and a change already there is seen)."""
        if self.detect():
            self.household.recompute()

    @callback
    def detect(self) -> bool:
        """A parent's changes in their own app become grants (before enforcement brings the holds in step); a grant
        from a Family Link bonus ends when the bonus is over."""
        from . import family_link as fl

        watch: set[str] = set()
        changed = False
        own = self.own_bonus()
        for spec in self.household.enforcement.parent_changes(own, watch):
            _LOGGER.debug("outside change for %s through %s: %s %s", spec["person"], spec["via"], spec["kind"], spec["value"])
            grant, new = self.household.grants.add(
                spec["person"],
                spec["via"],
                spec["kind"],
                spec["value"],
                spec["until"],
                spec["reason"],
                spec["end_with"],
                spec["ends_with"],
            )
            changed = changed or new
            if new:
                _LOGGER.info("%s: %s (%s), Hearth lets go of it", spec["person"], spec["reason"], spec["value"])
                self.household.enforcement.note(
                    f"{spec['via']}|{spec['person']}", parent_grant=grant.id, reason=spec["reason"]
                )
                self.hass.bus.async_fire(EVENT_PARENT_GRANT, grant.view())
                # A parent's change in their own app lifted one of Hearth's holds
                self.household.activity.hold(False, spec["person"], str(spec["value"]), "parent_grant", spec["via"])
        for grant in list(self.household.grants.grants.values()):
            if grant.ends_with != g.WHILE_BONUS:
                continue
            child = self.household.family_link_child(grant.person)
            if child is None:
                continue
            left = 0.0
            for device in fl.devices(self.hass, child):
                watch.add(device.entity_id)
                bonus = fl.bonus_left(self.hass, child, device, watch)
                # The parent's share of what's left: never more than what they gave (the device's bonus today less
                # Hearth's own), whichever part the kid used first
                mine = own.get(str(device.attributes.get("device_id")), 0)
                given = _number(device.attributes.get("bonus_minutes"))
                if given is None:  # an older Family Link: what's left less Hearth's, as before
                    left = max(left, bonus - mine)
                else:
                    left = max(left, min(bonus, max(0.0, given - mine)))
            if left <= 0:
                _LOGGER.info("%s: the Family Link bonus is over, Hearth holds again", grant.person)
                self.household.grants.end(grant.id)
                changed = True
        self.watched = watch
        return changed

    def _enforcer(self, person: str, kind: str):
        return next((e for e in self.household.enforcement.enforcers if e.person == person and e.kind == kind), None)

    def fs_bonus_until(self, person: str, platform: str):
        """When the latest extra time Hearth gave the person on a Family Safety platform today ends (None: none
        given): how Hearth tells its own extra time from a parent's where Family Safety doesn't say."""
        today = dt_util.now().date().isoformat()
        ends = [
            parsed
            for (p, _), record in self._given.items()
            if p == person and record.get("day") == today
            and (parsed := _when((record.get("until") or {}).get(platform))) is not None
        ]
        # A failed write that may yet show is Hearth's too while it's watched: never a parent's grant meanwhile
        ends += [
            parsed
            for entry in self.possibly_given
            if entry["person"] == person and entry["platform"] == platform and (parsed := _when(entry["until"]))
        ]
        return max(ends) if ends else None

    @callback
    def _possibly_given(self, person: str, why: str, platform: str, until, err: BaseException) -> None:
        self.possibly_given = [
            e for e in self.possibly_given if not (e["person"] == person and e["platform"] == platform)
        ]
        self.possibly_given.append(
            {
                "person": person,
                "why": why,
                "platform": platform,
                "until": dt_util.as_utc(until).isoformat(),
                "error": _scrub(str(err) or type(err).__name__)[:200],
                "at": dt_util.utcnow().isoformat(),
            }
        )
        self._save()

    async def async_pending_tick(self) -> None:
        """Each minute while a Family Safety extra time write failed (self.possibly_given): extra time Family Safety
        now shows on that platform, ending when Hearth asked (within 2 minutes), was applied after all. It's adopted
        as Hearth's own: given for its reason (so it's Hearth's, never a parent's grant, and Hearth's cancel applies),
        and logged as a WARNING to hand the Family Safety maintainer. When its reason ended meanwhile, it's cancelled
        through cancel_time_bonus (which checks what's in force first), as any of Hearth's own. Nothing shows within
        POSSIBLY_GIVEN_WINDOW: dropped, the write wasn't applied. Hearth never sends a blind cancel."""
        if not self.possibly_given:
            return
        now = dt_util.utcnow()
        keep = []
        looked = list(self.possibly_given)
        for entry in looked:
            enforcer = self._enforcer(entry["person"], FAMILY_SAFETY)
            until = _when(entry["until"])
            shown = None
            if enforcer is not None and until is not None:
                mine = self.household.enforcement.fs_mine(enforcer, entry["platform"])
                mine["bonus_until"] = until
                state = fs_hold_state(self.hass, enforcer.entity_id, entry["platform"], mine=mine) or {}
                ends = _when(state.get("allow_until") or state.get("override_until"))
                if state.get("override") == FS_ALLOW_UNTIL and ends is not None and abs(ends - until) <= FS_OWN_TOLERANCE:
                    shown = (state, ends)
            if shown is not None:
                await self._adopt(entry, enforcer, *shown)
                continue
            at = _when(entry["at"])
            if at is None or now - at >= POSSIBLY_GIVEN_WINDOW:
                _LOGGER.info(
                    "Family Safety extra time on %s: the write that failed at %s (asked until %s) was not applied "
                    "(none shown within %d minutes)",
                    entry["platform"], _local(entry["at"]), _local(entry["until"]),
                    POSSIBLY_GIVEN_WINDOW.total_seconds() // 60,
                )
                continue
            keep.append(entry)
        if keep != looked:
            # Kept with any that failed while this ran
            self.possibly_given = keep + [e for e in self.possibly_given if e not in looked]
            self._save()

    async def _adopt(self, entry: dict[str, Any], enforcer, state: dict[str, Any], ends) -> None:
        platform = entry["platform"]
        _LOGGER.warning(
            "Family Safety extra time on %s was applied although its write failed: add_time_bonus asked for extra "
            "time until %s and failed at %s with \"%s\"; Microsoft showed extra time until %s at %s. A write Microsoft "
            "didn't confirm was applied anyway. Hearth takes it as its own",
            platform, _local(entry["until"]), _local(entry["at"]), entry["error"], dt_util.as_local(ends).isoformat(),
            dt_util.now().isoformat(timespec="seconds"),
        )
        person = entry["person"]
        key = f"{FAMILY_SAFETY}|{person}"
        record = self._given.get((person, entry["why"]))
        if record is not None:
            if platform not in record["platforms"]:
                record["platforms"].append(platform)
            record.setdefault("until", {})[platform] = dt_util.as_utc(ends).isoformat()
            if state.get("source") == FS_FROM_HEARTH:
                # Upstream's extra time replaced any lock (one override per platform): Hearth no longer holds it
                held = self.household.enforcement.held.get(key)
                if held is not None:
                    held.items.discard(platform)
            self.household.enforcement.note(
                key, extra_time={platform: dt_util.as_local(ends).isoformat()}, reason=entry["why"],
                adopted="applied although its write failed",
            )
            self._save()
            return
        # Its reason ended meanwhile: ended as Hearth's own extra time is
        try:
            await self.cancel_family_safety_bonus(enforcer.entity_id, platform)
            self.household.enforcement.note(key, extra_time_cancelled=[platform], adopted="applied although its write failed")
        except Exception as err:  # noqa: BLE001 - it ends when it was set to
            self.household.enforcement.note(key, error=f"Family Safety extra time left to end by itself: {err}"[:200])

    @callback
    def end_grant(self, grant: Grant) -> None:
        """The first-party write that ends a grant early, where there is one."""
        if grant.end_with in (g.END_RESET_BONUS, g.END_CANCEL_BONUS):
            entry_task(self.hass, self.household.hub.entry.entry_id, self._end_write(grant), "hearth grant end")

    async def _end_write(self, grant: Grant) -> None:
        enforcer = self._enforcer(grant.person, grant.via)
        key = f"{grant.via}|{grant.person}"
        try:
            if grant.end_with == g.END_RESET_BONUS:
                pressed = await self._reset_family_link_bonus(grant.person)
                self.household.enforcement.note(key, ended_grant=grant.id, bonus_reset=pressed)
            elif grant.end_with == g.END_CANCEL_BONUS and enforcer is not None:
                await self.cancel_family_safety_bonus(enforcer.entity_id, grant.value)
                self.household.enforcement.note(key, ended_grant=grant.id, cancelled_bonus=grant.value)
        except Exception as err:  # noqa: BLE001 - told on Hearth's page; Hearth's hold comes back regardless
            _LOGGER.warning("Hearth couldn't end %s's grant in the first-party app: %s", grant.person, err)
            self.household.enforcement.note(key, ended_grant=grant.id, error=str(err)[:200])

    async def _reset_family_link_bonus(self, person: str) -> list[str]:
        """Presses Family Link's Reset bonus button of each of the child's devices with a bonus; says which."""
        from . import family_link as fl

        child = self.household.family_link_child(person)
        if child is None:
            return []
        pressed = []
        for device in fl.devices(self.hass, child):
            if not (_number(device.attributes.get("bonus_minutes")) or 0) > 0:
                continue
            await self.reset_bonus(child, device)
            pressed.append(device.entity_id)
        return pressed

    async def reset_bonus(self, child: str, device: Any) -> None:
        """Ends the day's bonus time on one Family Link device: familylink.reset_bonus, else its Reset bonus button.
        Raises when there's neither."""
        from . import family_link as fl

        if self.hass.services.has_service(FL_DOMAIN, "reset_bonus"):
            await call_service(self.hass,
                FL_DOMAIN, "reset_bonus", {"entity_id": device.entity_id}, blocking=True
            )
            self.household.enforcement.refresh_soon(device.entity_id)
            return
        button = fl.reset_bonus_button(self.hass, child, str(device.attributes.get("device_id")), device.entity_id)
        if button is None:
            raise ValueError(f"Family Link can't reset the bonus of {device.entity_id} (update it)")
        await call_service(self.hass, "button", "press", {"entity_id": button}, blocking=True)
        self.household.enforcement.refresh_soon(device.entity_id)

    # Hearth -> the first-party apps: an adult's "all screen time" opens Google's and Microsoft's own limits too

    @callback
    def mirror_allows(self) -> None:
        """Each recompute: an allow of All screen time not yet passed on gets extra time in Family Link and Family
        Safety, until it ends or midnight, once per allow and person."""
        now = dt_util.now()
        today = now.date().isoformat()
        self._given = {k: v for k, v in self._given.items() if v.get("day") == today}
        for allow in list(self.household.allows.allows.values()):
            if allow.group != ALL:
                continue
            for person, until in allow.until.items():
                key = (person, f"allow:{allow.id}")
                if key in self._given or until <= now or not self._mirrors(person):
                    continue
                self._given[key] = {"day": today, "devices": {}, "platforms": []}
                self._save()
                entry_task(
                    self.hass, self.household.hub.entry.entry_id,
                    self._give_time(person, min(until, end_of_day(now)), key), "hearth first-party extra time",
                )

    @callback
    def mirror_bonus(self, person: str, had_none: bool = True) -> None:
        """Bonus time given (every grant: hearth.add_time, an approved ask, a chore, the day-off bonus): Google's and
        Microsoft's own limits get as much as today's time now has left, until midnight at most, wherever they would
        stop the kid sooner, so a phone never locks early (Hearth's own holds stay the real limit). [had_none] is
        kept for older callers and no longer matters."""
        day = self.household.days.get(person)
        state = day.limits.get(ALL) if day else None
        left = state.minutes_left if state else None
        if left is None or left <= 0 or not self._mirrors(person):
            return
        now = dt_util.now()
        key = (person, f"bonus:{now.isoformat()}")
        self._given[key] = {"day": now.date().isoformat(), "devices": {}, "platforms": []}
        self._save()
        until = min(now + timedelta(minutes=left), end_of_day(now))
        entry_task(self.hass, self.household.hub.entry.entry_id, self._give_time(person, until, key), "hearth first-party extra time")

    @callback
    def take_back_bonus(self, person: str) -> bool:
        """An adult took back the extra time that gave All screen time back (hearth.remove_bonus): what Hearth gave for
        it in Family Link and Family Safety (the latest of today's, mirror_bonus) goes, as when extra time on one
        device ends early (a parent's own bonus there is kept). Says whether there was any."""
        today = dt_util.now().date().isoformat()
        keys = [k for k, v in self._given.items() if k[0] == person and k[1].startswith("bonus:") and v.get("day") == today]
        if not keys:
            return False
        record = self._given.pop(max(keys, key=lambda k: k[1]))
        self._save()
        if record["devices"] or record["platforms"] or record.get("cutoffs"):
            entry_task(self.hass, self.household.hub.entry.entry_id, self._take_back(person, record), "hearth extra time back")
        return True

    def _mirrors(self, person: str) -> bool:
        return any(
            e.person == person and e.kind in (FAMILY_LINK, FAMILY_SAFETY) for e in self.household.enforcement.enforcers
        )

    async def _give_time(
        self, person: str, until, key: tuple[str, str], fl_device: str | None = None, platform: str | None = None
    ) -> None:
        """[fl_device] or [platform]: only that Family Link device or Family Safety platform (extra time on one
        device, device_extra.py); neither: every one that would block."""
        now = dt_util.now()
        minutes = math.ceil((until - now).total_seconds() / 60)
        if minutes <= 0:
            return
        record = self._given[key]
        try:
            if platform is None:
                await self._give_family_link(person, minutes, key[1], record, only=fl_device)
            if fl_device is None:
                await self._give_family_safety(person, until, minutes, key[1], record, only=platform)
        finally:
            self._save()

    @callback
    def give_device(self, person: str, extra_id: str, until, fl_device: str | None, platform: str | None) -> None:
        """Extra time on one Family Link device or Family Safety platform (hearth.add_bonus or hearth.allow with a
        device), until [until]."""
        key = (person, f"device:{extra_id}")
        self._given[key] = {"day": dt_util.now().date().isoformat(), "devices": {}, "platforms": []}
        self._save()
        entry_task(
            self.hass, self.household.hub.entry.entry_id,
            self._give_time(person, until, key, fl_device, platform), "hearth extra time on one device",
        )

    @callback
    def device_ended(self, person: str, extra_id: str) -> None:
        """Extra time on one device ended early: what Hearth gave for it in Family Link or Family Safety goes."""
        record = self._given.pop((person, f"device:{extra_id}"), None)
        self._save()
        if record and (record["devices"] or record["platforms"] or record.get("cutoffs")):
            entry_task(self.hass, self.household.hub.entry.entry_id, self._take_back(person, record), "hearth extra time on one device back")

    async def _give_family_link(
        self, person: str, minutes: int, why: str, record: dict[str, Any], only: str | None = None
    ) -> None:
        """A today-only Family Link bonus on each of the child's devices whose own daily limit would block within
        [minutes] (a device with no limit gets none)."""
        from . import family_link as fl

        child = self.household.family_link_child(person)
        if child is None or not self.hass.services.has_service(FL_DOMAIN, "add_time_bonus"):
            return
        added: dict[str, int] = {}
        error = None
        for device in fl.devices(self.hass, child):
            info = fl.device_limit(self.hass, child, device)
            if only is not None and info["device_id"] != only:
                continue
            left = info["minutes_left"]
            if left is None or left >= minutes:
                continue
            bonus = max(1, min(1440, minutes - max(0, left)))
            try:
                await call_service(self.hass,
                    FL_DOMAIN, "add_time_bonus", {"entity_id": device.entity_id, "bonus_minutes": bonus}, blocking=True
                )
            except Exception as err:  # noqa: BLE001 - shown on Hearth's page; Hearth's own holds are let go anyway
                _LOGGER.warning("Hearth couldn't add Family Link bonus time on %s: %s", device.entity_id, err)
                error = str(err)[:200]
                continue
            self.household.enforcement.refresh_soon(device.entity_id)
            added[info["device"]] = bonus
            record["devices"][info["device_id"]] = record["devices"].get(info["device_id"], 0) + bonus
            mine = self.fl_added.setdefault(person, {"day": record["day"], "devices": {}})
            if mine.get("day") != record["day"]:
                mine.update({"day": record["day"], "devices": {}})
            mine["devices"][info["device_id"]] = mine["devices"].get(info["device_id"], 0) + bonus
        if added or error:
            self.household.enforcement.note(f"{FAMILY_LINK}|{person}", bonus_added=added, reason=why, error=error)

    async def _give_family_safety(
        self, person: str, until, minutes: int, why: str, record: dict[str, Any], only: str | None = None
    ) -> None:
        """Family Safety extra time (its experimental add_time_bonus) on the enforcer's platforms (Xbox, and Windows
        where the installed Family Safety takes it) whose allowance would block within [minutes]; [only]: that one
        platform, held by Hearth or not. Extra time replaces Hearth's own lock there; when Family Safety lets go of
        that lock for good (fs_hold_released), Hearth no longer holds the platform. A failure says Family Safety's
        extra time is unavailable, isn't retried, and counts as not given. Extra time that runs past the platform's
        allowed hours today moves today's end of them too (_fs_move_cutoff): Microsoft's extra time doesn't lift them."""
        enforcer = self._enforcer(person, FAMILY_SAFETY)
        if enforcer is None:
            return
        given: dict[str, Any] = {}
        moved: dict[str, str] = {}
        error = None
        bonus = self.hass.services.has_service(FS_DOMAIN, "add_time_bonus")
        for platform in (only,) if only is not None else enforcer.platforms:
            # Family Safety gives extra time on the Xbox and (a newer one) on Windows, never on Mobile
            if platform not in FS_BONUS_PLATFORMS:
                continue
            try:
                if end := await self._fs_move_cutoff(person, enforcer.entity_id, platform, until, record):
                    moved[platform] = end
            except (HomeAssistantError, vol.Invalid) as err:
                _LOGGER.info("Family Safety's allowed hours on %s for %s not moved: %s", platform, person, err)
                error = f"Family Safety's allowed hours not moved: {err}"[:200]
            if not bonus or not self._fs_would_block(enforcer, platform, minutes):
                continue
            data = {
                **_fs_target(enforcer.entity_id),
                "platform": platform,
                "until": dt_util.as_local(until).replace(tzinfo=None, microsecond=0).isoformat(),
            }
            # Extra time replaces Hearth's own lock (Family Safety puts it back when the time ends), never a parent's
            hold = self.household.enforcement.fs_state(enforcer, platform)
            if hold and hold.get("hold") in (FS_HOLD_OURS, FS_HOLD_BONUS_OURS):
                data["replace_lock"] = True
            if platform != "Xbox" and not fs_accepts(self.hass, "add_time_bonus", data):
                # A Family Safety without Windows extra time (upstream's is Xbox only): skipped quietly
                _LOGGER.debug("Family Safety gives no extra time on %s; skipped for %s", platform, person)
                continue
            try:
                response = await call_service(self.hass,
                    FS_DOMAIN,
                    "add_time_bonus",
                    data,
                    blocking=True,
                    return_response=self.household.enforcement._responds(FS_DOMAIN, "add_time_bonus"),
                )
            except (HomeAssistantError, vol.Invalid, TimeoutError) as err:
                _LOGGER.info("Family Safety extra time on %s for %s unavailable: %s", platform, person, err)
                error = f"Family Safety extra time unavailable: {err}"[:200]
                if not isinstance(err, (vol.Invalid, ServiceValidationError)):
                    # Refused by no schema: the write may have reached Microsoft all the same (an error or a timeout
                    # after it was applied). Watched for a while (async_pending_tick), never cancelled blind
                    self._possibly_given(person, why, platform, until, err)
                continue
            self.household.enforcement.refresh_soon(enforcer.entity_id)
            given[platform] = (
                response.get("applied_until") or response.get("until") if isinstance(response, dict) else None
            )
            record["platforms"].append(platform)
            # When it ends, as Family Safety took it: Hearth's own extra time, not a parent's (fs_derived_hold)
            ends = _when(given[platform]) or until
            record.setdefault("until", {})[platform] = dt_util.as_utc(ends).isoformat()
            if fs_hold_released(response):
                held = self.household.enforcement.held.get(f"{FAMILY_SAFETY}|{person}")
                if held is not None:
                    held.items.discard(platform)
        if given or moved or error:
            self.household.enforcement.note(
                f"{FAMILY_SAFETY}|{person}", extra_time=given, allowed_until=moved, reason=why, error=error
            )

    def _cutoff_elsewhere(self, person: str, platform: str, record: dict[str, Any]) -> dict[str, Any] | None:
        """Another extra time of the person's today that moved the platform's allowed hours (its kept window)."""
        return next(
            (
                r["cutoffs"][platform]
                for (p, _), r in self._given.items()
                if p == person and r is not record and platform in (r.get("cutoffs") or {})
            ),
            None,
        )

    async def _fs_move_cutoff(
        self, person: str, entity_id: str, platform: str, until, record: dict[str, Any]
    ) -> str | None:
        """Extra time that runs past the end of the platform's allowed hours today moves that end to cover it. Allowed
        hours go by half hours, so the end is rounded up to the next one. Only a day with one allowed window (two
        would be merged into one); the Xbox's goes through the Xbox Family Settings sign-in.

        A Family Safety that takes today_only (set_screentime_intervals) puts the day back itself at midnight. One that
        doesn't (upstream's) gets this weekday's setting (day_of_week), and Hearth puts the window back itself after
        midnight (self.windows, async_windows_tick): recorded before the write, so a restart or a missed midnight still
        knows it. Not on Windows while Family Safety keeps a saved schedule (its account lock, or limits off without
        the app's switch): it writes every change of a day into that restore point too, so Hearth's window would come
        back with it for good (fs_saved_schedule).

        The window from before any extra time moved it is kept in [record] to be put back when the extra time ends
        early (_put_back_cutoffs). The new end ("HH:MM"), or None."""
        window = fs_allowed_window(self.hass, entity_id, platform)
        if window is None:
            return None
        begin, end = window
        now = dt_util.now()
        local = dt_util.as_local(until)
        if local.date() != now.date():
            wanted = MINUTES_A_DAY  # until midnight
        else:
            wanted = local.hour * 60 + local.minute + (1 if local.second or local.microsecond else 0)
        wanted = min(MINUTES_A_DAY, math.ceil(wanted / 30) * 30)
        if wanted <= end:
            return None
        weekday = None
        data = _fs_window_data(entity_id, platform, begin, wanted)
        if not fs_accepts(self.hass, SET_INTERVALS, data):
            weekday = fs_weekday(now)
            data = _fs_window_data(entity_id, platform, begin, wanted, weekday)
            if not fs_accepts(self.hass, SET_INTERVALS, data):
                _LOGGER.debug("Family Safety can't move today's allowed hours on %s; skipped for %s", platform, person)
                return None
            if platform == "Windows" and fs_saved_schedule(self.hass, entity_id):
                raise HomeAssistantError(
                    "Family Safety keeps a saved schedule (its account lock or limits off), which would keep the change"
                )
        before = self._cutoff_elsewhere(person, platform, record) or {"begin": begin, "end": end}
        # Known as Hearth's before the write, and for the rest of the day: a second extra time moves the end again,
        # and one that ended early may leave it (a put back that failed, or another extra time still needs it)
        self.moved = _recent_moves(self.moved)
        self.moved.append(
            {"person": person, "platform": platform, "day": now.date().isoformat(), "weekday": fs_weekday(now),
             "begin": int(begin), "end": int(wanted)}
        )
        await self._store.async_save(self._data())
        key = was = None
        if weekday is not None:
            key, was = await self._window_begin(person, entity_id, platform, weekday, before, begin, wanted)
        try:
            await call_service(self.hass, FS_DOMAIN, SET_INTERVALS, data, blocking=True)
        except Exception:
            if was is not None:
                # The earlier move is still what's there: its record stands (a first move's stays unwritten:
                # Hearth's only if it's found to have landed after all)
                self.windows[key] = was
                self._save()
            raise
        if key is not None:
            self.windows[key]["written_at"] = dt_util.utcnow().isoformat()
        self.household.enforcement.refresh_soon(entity_id)
        cut = {"begin": before["begin"], "end": before["end"], "set": wanted}
        if weekday is not None:
            cut["weekday"] = weekday
        record.setdefault("cutoffs", {})[platform] = cut
        self._save()
        return _hhmm(wanted)

    def cutoff_today(self, person: str, platform: str) -> dict[str, Any] | None:
        """Read only, for bedtime sync: extra time of the person's today that moved the platform's allowed hours ({begin,
        end, set}), or None."""
        today = dt_util.now().date().isoformat()
        return next(
            (
                r["cutoffs"][platform]
                for (p, _), r in self._given.items()
                if p == person and r.get("day") == today and platform in (r.get("cutoffs") or {})
            ),
            None,
        )

    def moved_windows(self, person: str, platform: str) -> list[dict[str, Any]]:
        """Read only, for bedtime sync: the allowed hours of the person's platform that Hearth itself wrote for extra
        time today and yesterday ({day, weekday, begin, end}), every one of them, also once the extra time is over."""
        return [m for m in _recent_moves(self.moved) if m["person"] == person and m["platform"] == platform]

    async def async_set_window_today(self, person: str, entity_id: str, platform: str, begin: int, end: int) -> str:
        """Bedtime sync's today write of a platform's allowed hours (begin, end minutes; 1440 midnight): today only on a
        Family Safety that takes today_only, else this weekday's setting, recorded in self.windows to be put back after
        midnight (async_windows_tick), as _fs_move_cutoff does. Not on Windows while Family Safety keeps a saved
        schedule (raises). "today_only" or "weekday"."""
        data = _fs_window_data(entity_id, platform, begin, end)
        if fs_accepts(self.hass, SET_INTERVALS, data):
            await call_service(self.hass, FS_DOMAIN, SET_INTERVALS, data, blocking=True)
            self.household.enforcement.refresh_soon(entity_id)
            return "today_only"
        weekday = fs_weekday(dt_util.now())
        data = _fs_window_data(entity_id, platform, begin, end, weekday)
        if not fs_accepts(self.hass, SET_INTERVALS, data):
            raise vol.Invalid("Family Safety takes no allowed hours for this day")
        if platform == "Windows" and fs_saved_schedule(self.hass, entity_id):
            raise HomeAssistantError(
                "Family Safety keeps a saved schedule (its account lock or limits off), which would keep the change"
            )
        now_window = fs_allowed_window(self.hass, entity_id, platform) or (begin, end)
        key, was = await self._window_begin(
            person, entity_id, platform, weekday, {"begin": now_window[0], "end": now_window[1]}, begin, end
        )
        try:
            await call_service(self.hass, FS_DOMAIN, SET_INTERVALS, data, blocking=True)
        except Exception:
            if was is not None:
                self.windows[key] = was
            else:
                self.windows.pop(key, None)
            self._save()
            raise
        self.windows[key]["written_at"] = dt_util.utcnow().isoformat()
        self._save()
        self.household.enforcement.refresh_soon(entity_id)
        return "weekday"

    async def _window_begin(
        self, person: str, entity_id: str, platform: str, weekday: str, before: dict[str, Any], begin: int, wanted: int
    ) -> tuple[str, dict[str, Any] | None]:
        """Hearth's moved window, kept before its write (saved at once: a write whose answer was lost is still known
        as Hearth's). A window of this weekday Hearth moved and hasn't put back yet keeps what it was before (never
        Hearth's own as what to put back). (key, the record it replaced)."""
        key = f"{entity_id}|{platform}|{weekday}"
        was = self.windows.get(key)
        self.windows[key] = {
            "person": person,
            "entity_id": entity_id,
            "platform": platform,
            "weekday": weekday,
            "day": dt_util.now().date().isoformat(),
            "begin": int(was["begin"] if was else before["begin"]),
            "end": int(was["end"] if was else before["end"]),
            "target": int(wanted),
            "target_begin": int(begin),
            "written_at": None,
            "seen": None,
        }
        await self._store.async_save(self._data())
        return key, (dict(was) if was else None)

    async def _put_back_cutoffs(
        self, person: str, entity_id: str, record: dict[str, Any]
    ) -> tuple[list[str], str | None]:
        """Extra time that moved a platform's allowed hours today ended early: the window from before is put back,
        while it still reads Hearth's (a parent's change since stays) and no other extra time of the person's still
        moves it; as it was moved (today only, or the weekday's setting, whose record then goes). ([platforms put
        back], error)."""
        back: list[str] = []
        error = None
        for platform, cut in (record.get("cutoffs") or {}).items():
            if self._cutoff_elsewhere(person, platform, record) is not None:
                continue
            window = fs_allowed_window(self.hass, entity_id, platform)
            if window is None or window[1] != cut["set"]:
                continue
            weekday = cut.get("weekday")
            try:
                await call_service(self.hass,
                    FS_DOMAIN,
                    SET_INTERVALS,
                    _fs_window_data(entity_id, platform, cut["begin"], cut["end"], weekday),
                    blocking=True,
                )
                back.append(platform)
                self.household.enforcement.refresh_soon(entity_id)
            except (HomeAssistantError, vol.Invalid) as err:  # put back at midnight anyway
                error = f"Family Safety's allowed hours left until midnight: {err}"[:200]
                continue
            key = f"{entity_id}|{platform}|{weekday}"
            if weekday is not None and (kept := self.windows.get(key)) is not None:
                if (kept["begin"], kept["end"]) == (cut["begin"], cut["end"]):
                    self.windows.pop(key)
                else:
                    kept.update(target=cut["end"], target_begin=cut["begin"], written_at=dt_util.utcnow().isoformat())
                self._save()
        return back, error

    # Allowed hours Hearth moved on a weekday's setting go back after midnight

    async def async_windows_tick(self) -> None:
        """Each minute while Hearth has moved allowed hours (self.windows): today's are watched (whether they still
        read Hearth's window, so a parent's change is known after midnight too); a record from an earlier day is put
        back once Home Assistant has settled after a start. Put back only while the weekday still reads Hearth's
        window; read from the Windows weekday's own Start and End entities, or the Xbox's allowed hours when today is
        that weekday again, else as last seen (nothing seen: Hearth's, which it wrote). Windows waits while Family
        Safety keeps a saved schedule (it would write the window into it and back over the lock); a failed write is
        tried again after a while."""
        if not self.windows:
            return
        now = dt_util.now()
        today = now.date().isoformat()
        changed = False
        for key, record in list(self.windows.items()):
            reading = fs_weekday_window(self.hass, record["entity_id"], record["platform"], record["weekday"], now)
            hearths = (record["target_begin"], record["target"])
            if record["day"] == today:
                if reading == hearths and record.get("written_at") is None:
                    record["written_at"] = dt_util.utcnow().isoformat()  # it did land
                    changed = True
                if reading is not None and record.get("written_at") is not None:
                    seen = "hearth" if reading == hearths else None if _just(record["written_at"]) else "other"
                    if seen is not None and seen != record.get("seen"):
                        record["seen"] = seen
                        changed = True
                continue
            if not self.household.enforcement._may_let_go():
                continue
            if record["platform"] == "Windows" and fs_saved_schedule(self.hass, record["entity_id"]):
                continue
            if _when(record.get("failed_at")) and dt_util.utcnow() - _when(record["failed_at"]) < RETRY:
                continue
            if reading is not None:
                ours = reading == hearths
            else:
                # Can't be read now: as last seen; never seen, Hearth's if its write went through
                ours = record.get("seen") == "hearth" or (
                    record.get("seen") is None and record.get("written_at") is not None
                )
            if not ours:
                # A parent's change since (or Hearth's write never landed): it stays
                self.windows.pop(key)
                changed = True
                continue
            if not self.hass.services.has_service(FS_DOMAIN, SET_INTERVALS):
                continue
            data = _fs_window_data(record["entity_id"], record["platform"], record["begin"], record["end"], record["weekday"])
            note_key = f"{FAMILY_SAFETY}|{record['person']}"
            try:
                await call_service(self.hass, FS_DOMAIN, SET_INTERVALS, data, blocking=True)
            except (HomeAssistantError, vol.Invalid) as err:
                _LOGGER.info("Family Safety's allowed hours on %s not put back yet: %s", record["platform"], err)
                record["failed_at"] = dt_util.utcnow().isoformat()
                self.household.enforcement.note(
                    note_key, error=f"Family Safety's allowed hours not put back yet: {err}"[:200]
                )
                changed = True
                continue
            self.windows.pop(key)
            changed = True
            self.household.enforcement.refresh_soon(record["entity_id"])
            self.household.enforcement.note(
                note_key, allowed_hours_back=[record["platform"]], weekday=record["weekday"]
            )
        if changed:
            self._save()

    def _fs_would_block(self, enforcer, platform: str, minutes: int) -> bool:
        """Microsoft's own allowance would stop the platform within [minutes] (not a lock of Hearth's)."""
        state = fs_platform_state(self.hass, enforcer.entity_id, platform)
        if state is None:
            return False
        allowance, used = _number(state.get("allowance_minutes")), _number(state.get("used_minutes"))
        hold = (self.household.enforcement.fs_state(enforcer, platform) or {}).get("hold")
        if hold in (FS_HOLD_OURS, FS_HOLD_BONUS_OURS) or (allowance is not None and used is not None):
            # Hearth's own lock reads as 0 left: the allowance itself decides
            return allowance is not None and used is not None and allowance - used < minutes
        left = _number(state.get("remaining_minutes"))
        return left is not None and left < minutes

    @callback
    def allow_ended(self) -> None:
        """An allow of All screen time ended early (hearth.allow_end): the extra time Hearth gave for it in Family
        Link (reset_bonus, only where no parent's bonus came on top) and Family Safety (cancel_time_bonus) goes."""
        for key, record in list(self._given.items()):
            person, why = key
            if not why.startswith("allow:"):
                continue
            allow = self.household.allows.allows.get(why.removeprefix("allow:"))
            if allow is not None and person in allow.until:
                continue
            del self._given[key]
            self._save()
            if record["devices"] or record["platforms"] or record.get("cutoffs"):
                entry_task(self.hass, self.household.hub.entry.entry_id, self._take_back(person, record), "hearth first-party extra time back")

    async def _take_back(self, person: str, record: dict[str, Any]) -> None:
        from . import family_link as fl

        child = self.household.family_link_child(person)
        reset: list[str] = []
        kept: list[str] = []
        error = None
        for device in fl.devices(self.hass, child) if child and record["devices"] else []:
            device_id = str(device.attributes.get("device_id"))
            given = record["devices"].get(device_id)
            if not given:
                continue
            mine = self.fl_added.get(person, {}).get("devices", {})
            if (_number(device.attributes.get("bonus_minutes")) or 0) > mine.get(device_id, 0):
                kept.append(device.entity_id)  # a parent's bonus too: resetting would end theirs
                continue
            try:
                await self.reset_bonus(child, device)
                reset.append(device.entity_id)
                mine.pop(device_id, None)
            except Exception as err:  # noqa: BLE001 - it lapses at midnight
                error = f"Family Link bonus left to lapse at midnight: {err}"[:200]
        if reset:
            self._save()
        if reset or kept or error:
            self.household.enforcement.note(f"{FAMILY_LINK}|{person}", bonus_reset=reset, bonus_kept=kept, error=error)
        enforcer = self._enforcer(person, FAMILY_SAFETY)
        if enforcer is None:
            return
        if record.get("cutoffs"):
            back, error = await self._put_back_cutoffs(person, enforcer.entity_id, record)
            if back or error:
                self.household.enforcement.note(f"{FAMILY_SAFETY}|{person}", allowed_hours_back=back, error=error)
        if not record["platforms"]:
            return
        cancelled: list[str] = []
        kept: list[str] = []
        error = None
        for platform in record["platforms"]:
            # Only Hearth's own extra time is cancelled: a parent's extra time or lock that came since (the hold
            # reads parent) is theirs, and a cancel would end it
            mine = self.household.enforcement.fs_mine(enforcer, platform)
            # This extra time's own end (it's no longer among today's given ones)
            mine["bonus_until"] = _when((record.get("until") or {}).get(platform)) or mine["bonus_until"]
            hold = fs_hold_state(self.hass, enforcer.entity_id, platform, mine=mine)
            if hold and hold.get("hold") == FS_HOLD_PARENT:
                kept.append(platform)
                continue
            try:
                await self.cancel_family_safety_bonus(enforcer.entity_id, platform)
                cancelled.append(platform)
            except Exception as err:  # noqa: BLE001 - shown; it ends when it was set to
                error = str(err)[:200]
                # Still in force until its end: kept known as Hearth's, or a later hold would read it as a parent's
                if (until := (record.get("until") or {}).get(platform)) is not None:
                    self._given[(person, f"uncancelled:{platform}:{until}")] = {
                        "day": dt_util.now().date().isoformat(), "devices": {}, "platforms": [platform],
                        "until": {platform: until},
                    }
                    self._save()
        self.household.enforcement.note(
            f"{FAMILY_SAFETY}|{person}", extra_time_cancelled=cancelled, extra_time_kept=kept, error=error
        )

    async def cancel_family_safety_bonus(self, entity_id: str, platform: str) -> None:
        """Family Safety's cancel_time_bonus on one platform; raises when this Family Safety can't (none, or none for
        that platform: upstream's cancels Xbox extra time only)."""
        data = {**_fs_target(entity_id), "platform": platform}
        if not self.hass.services.has_service(FS_DOMAIN, "cancel_time_bonus"):
            raise ValueError("Family Safety can't cancel extra time (update it)")
        if not fs_accepts(self.hass, "cancel_time_bonus", data):
            raise ValueError(f"Family Safety can't cancel extra time on {platform} (update it)")
        await call_service(self.hass, FS_DOMAIN, "cancel_time_bonus", data, blocking=True)
        self.household.enforcement.refresh_soon(entity_id)

    # What the first-party apps say now (Hearth's page, the household summary, explain)

    def first_party(self, person: str) -> dict[str, Any]:
        """Google's own daily limit per Family Link device, Microsoft's allowance per Family Safety platform and each
        Switch's own limit and play today (nintendo.py), as their entities say now (only those there). blocking: the device's or platform's own limit stops it now,
        not a hold of Hearth's; parent_lock: a parent's own Family Safety lock."""
        from . import family_link as fl
        from .enforce import DEVICES, FS_BLOCK_UNTIL, FS_HOLD_PARENT

        found: dict[str, Any] = {}
        child = self.household.family_link_child(person)
        if child is not None:
            held = self.household.enforcement.held.get(f"{FAMILY_LINK}|{person}")
            hearth_holds = bool(held and DEVICES in held.items)
            rows = []
            for device in fl.devices(self.hass, child):
                row = fl.device_limit(self.hass, child, device)
                row.pop("remaining_entity", None)
                row["bonus_left"] = fl.bonus_left(self.hass, child, device)
                row["held_by_hearth"] = hearth_holds
                out = row["reached"] or row["minutes_left"] == 0
                row["blocking"] = bool(out and row["bonus_left"] <= 0 and not hearth_holds)
                rows.append(row)
            if rows:
                found[FAMILY_LINK] = rows
        enforcer = self._enforcer(person, FAMILY_SAFETY)
        if enforcer is not None:
            held = self.household.enforcement.held.get(enforcer.key)
            rows = []
            for platform in ("Windows", "Xbox"):
                state = fs_platform_state(self.hass, enforcer.entity_id, platform)
                if state is None:
                    continue
                allowed = state.get("state") if state["entity_id"].startswith("binary_sensor.") else None
                # Who holds it: Family Safety's own hold attributes, else told from what Hearth asked for
                who = self.household.enforcement.fs_state(enforcer, platform) or {}
                hold = who.get("hold")
                parent_lock = hold == FS_HOLD_PARENT and who.get("override") == FS_BLOCK_UNTIL
                rows.append(
                    {
                        "platform": platform,
                        "entity_id": state["entity_id"],
                        "minutes_left": _int(state.get("remaining_minutes")),
                        "allowance_minutes": _int(state.get("allowance_minutes")),
                        "used_minutes": _int(state.get("used_minutes")),
                        "allowed_now": None if allowed is None else allowed == "on",
                        "reason": state.get("reason"),
                        "hold": hold,
                        # attributes (Family Safety says), hearth (told from Hearth's own record) or None
                        "hold_from": who.get("source"),
                        "override_until": who.get("override_until") or state.get("override_until"),
                        "allow_until": who.get("allow_until") or state.get("allow_until"),
                        "held_by_hearth": bool(held and platform in held.items),
                        "parent_lock": parent_lock,
                        # Microsoft's own allowance or hours stop it, not a lock of anyone's
                        "blocking": allowed == "off" and hold in (None, "none") and not (held and platform in held.items),
                    }
                )
            if rows:
                found[FAMILY_SAFETY] = rows
        from .nintendo import switches

        if rows := switches(self.household, person):
            found[NINTENDO] = rows
        return found

    def app_limits_reached(self, person: str, packages: set[str], midnight: str) -> list[dict[str, Any]]:
        """For hearth.explain: Family Link's own app limits (a parent's, not Hearth's pauses) that an app of these has
        used up today on a device of the person's. Hearth's allows and bonuses don't raise them, so the device keeps
        the app closed whatever Hearth says."""
        from . import family_link as fl

        child = self.household.family_link_child(person)
        if child is None or not packages:
            return []
        found: list[dict[str, Any]] = []
        for limit in fl.app_limits(self.hass, child):
            package = limit.get("package")
            if package not in packages:
                continue
            minutes = _int(limit.get("limit_minutes"))
            if minutes is None or minutes < 0:  # -1 follows the device's limit, -2 unlimited
                continue
            for device, used in fl.app_minutes_today(self.hass, child, package):
                if used >= minutes:
                    found.append(
                        {
                            "kind": "app_limit",
                            "by": limit["entity_id"],
                            "app": package,
                            "device": device,
                            "limit_minutes": minutes,
                            "used_minutes": round(used, 1),
                            "until": midnight,
                        }
                    )
        return found

    def blocked_by(self, person: str, midnight: str) -> list[dict[str, Any]]:
        """For hearth.explain: the first-party limits that stop the person now on a device of theirs (device_limit:
        Google's daily limit on a Family Link device, Microsoft's allowance on a platform) and a parent's own Family
        Safety lock (parent_lock), so explain says what the device does."""
        found: list[dict[str, Any]] = []
        first = self.first_party(person)
        for row in first.get(FAMILY_LINK, []):
            if row["blocking"]:
                found.append(
                    {"kind": "device_limit", "by": row["entity_id"], "device": row["device"], "until": midnight}
                )
        for row in first.get(FAMILY_SAFETY, []):
            if row["parent_lock"]:
                found.append(
                    {
                        "kind": "parent_lock",
                        "by": row["entity_id"],
                        "platform": row["platform"],
                        "until": row["override_until"],
                    }
                )
            elif row["blocking"]:
                found.append(
                    {"kind": "device_limit", "by": row["entity_id"], "platform": row["platform"], "until": None}
                )
        return found


def fs_platform_state(
    hass: HomeAssistant, entity_id: str, platform: str, domains: tuple[str, ...] = ("binary_sensor", "sensor")
) -> dict[str, Any] | None:
    """A Family Safety platform today, from a newer Family Safety: its Allowed Now sensor's attributes (reason,
    remaining_minutes, allowance_minutes, used_minutes, hold...) with its state, else its Time Remaining sensor's.
    None when there's neither."""
    account = fs_account_of(hass, entity_id)
    if account is None:
        return None
    for domain in domains:
        for state in hass.states.async_all(domain):
            attrs = state.attributes
            if str(attrs.get("user_id")) != account or "allowance_minutes" not in attrs:
                continue
            if domain == "sensor" and not state.entity_id.endswith("_time_remaining"):
                continue
            named = attrs.get("platform") or ("Xbox" if "xbox" in state.entity_id else "Windows")
            if str(named).lower() != platform.lower():
                continue
            found = {**attrs, "state": state.state, "entity_id": state.entity_id}
            if domain == "sensor":
                found["remaining_minutes"] = _number(state.state)
            elif "remaining_minutes" not in found:
                # Upstream's Allowed Now leaves the minutes left to the Time Remaining sensor
                found["remaining_minutes"] = (fs_platform_state(hass, entity_id, platform, ("sensor",)) or {}).get(
                    "remaining_minutes"
                )
            return found
    return None


def fs_allowed_window(hass: HomeAssistant, entity_id: str, platform: str) -> tuple[int, int] | None:
    """Today's allowed hours of a Family Safety platform as (begin, end) in minutes from midnight (an end of 1440 is
    midnight), from its Time Remaining sensor's allowed_ranges; None unless there's exactly one window."""
    account = fs_account_of(hass, entity_id)
    if account is None:
        return None
    for state in hass.states.async_all("sensor"):
        attrs = state.attributes
        if str(attrs.get("user_id")) != account or not state.entity_id.endswith("_time_remaining"):
            continue
        named = attrs.get("platform") or ("Xbox" if "xbox" in state.entity_id else "Windows")
        if str(named).lower() != platform.lower():
            continue
        ranges = attrs.get("allowed_ranges")
        if not isinstance(ranges, list) or len(ranges) != 1 or not isinstance(ranges[0], dict):
            return None
        begin, end = _clock(ranges[0].get("begin")), _clock(ranges[0].get("end"))
        if begin is None or end is None:
            return None
        if end <= begin:
            end = MINUTES_A_DAY  # an end of 00:00 is midnight
        return begin, end
    return None


def _fs_window_data(
    entity_id: str, platform: str, begin: int, end: int, weekday: str | None = None
) -> dict[str, Any]:
    """set_screentime_intervals' data: today only (a Family Safety that takes today_only), or the setting of
    [weekday] (upstream's: day_of_week, 0 is Sunday)."""
    day: dict[str, Any] = {"today_only": True} if weekday is None else {"day_of_week": FS_WEEKDAYS.index(weekday)}
    return {
        **_fs_target(entity_id),
        "platform": platform,
        **day,
        "start_hour": begin // 60,
        "start_minute": begin % 60,
        "end_hour": end // 60,
        "end_minute": end % 60,
    }


def _recent_moves(moved: Any) -> list[dict[str, Any]]:
    """The moved allowed hours (NativeSync.moved) of today and yesterday, well-formed ones only."""
    since = (dt_util.now().date() - timedelta(days=1)).isoformat()
    return [
        m
        for m in moved or []
        if isinstance(m, dict)
        and all(isinstance(m.get(f), str) for f in ("person", "platform", "day"))
        and all(isinstance(m.get(f), int) for f in ("begin", "end"))
        and m.get("weekday") in FS_WEEKDAYS
        and m["day"] >= since
    ]


def fs_weekday(when) -> str:
    """Family Safety's name of a local day's weekday ("monday"...)."""
    return FS_WEEKDAYS[(dt_util.as_local(when).weekday() + 1) % 7]


def fs_saved_schedule(hass: HomeAssistant, entity_id: str) -> bool:
    """Family Safety keeps a saved schedule of the child's now (has_saved_policy on its account Lock or Screen Time
    Limits switch): its account lock, or limits turned off through its web fallback. While it does, every change of a
    Windows day is written into that restore point too, and the unlock writes the restore point back."""
    account = fs_account_of(hass, entity_id)
    if account is None:
        return False
    return any(
        state.attributes.get("has_saved_policy") is True and str(state.attributes.get("user_id")) == account
        for state in hass.states.async_all("switch")
    )


def fs_weekday_window(hass: HomeAssistant, entity_id: str, platform: str, weekday: str, now=None) -> tuple[int, int] | None:
    """A weekday's allowed hours of a Family Safety platform as (begin, end) minutes (1440: midnight): today's from
    its Time Remaining sensor (fs_allowed_window); another day's on Windows from the integration's Start and End
    entities of that weekday (unique id <entry>_<account>_interval_<weekday>_start/_end; an end of 23:59 is midnight).
    None when it can't be read (the Xbox on another day)."""
    if weekday == fs_weekday(now or dt_util.now()):
        return fs_allowed_window(hass, entity_id, platform)
    if platform != "Windows":
        return None
    account = fs_account_of(hass, entity_id)
    if account is None:
        return None
    found: dict[str, int | None] = {}
    for entry in er.async_get(hass).entities.values():
        if entry.domain != "time" or entry.platform != FS_DOMAIN:
            continue
        for end in ("start", "end"):
            if str(entry.unique_id).endswith(f"_{account}_interval_{weekday}_{end}"):
                state = hass.states.get(entry.entity_id)
                found[end] = _clock(state.state) if state else None
    begin, end = found.get("start"), found.get("end")
    if begin is None or end is None:
        return None
    if end >= MINUTES_A_DAY - 1 or end <= begin:
        end = MINUTES_A_DAY  # 23:59 (how the integration shows midnight) or 00:00
    return begin, end


def fs_policy_windows(
    hass: HomeAssistant, entity_id: str, platform: str, weekday: str
) -> list[tuple[int, int]] | None:
    """A weekday's allowed hours of a platform from the child's Screen Time Policy sensor (bedtime sync): Windows'
    <weekday>_allowed_intervals (48 half hours), the Xbox's xbox_<weekday>_allowed_intervals ([{begin, end}]), as
    [(begin, end)] minutes (1440: midnight). [] when nothing is allowed; None when the sensor doesn't say."""
    account = fs_account_of(hass, entity_id)
    if account is None:
        return None
    key = f"xbox_{weekday}_allowed_intervals" if platform == "Xbox" else f"{weekday}_allowed_intervals"
    for state in hass.states.async_all("sensor"):
        attrs = state.attributes
        if str(attrs.get("user_id")) != account or key not in attrs:
            continue
        value = attrs.get(key)
        if not isinstance(value, list):
            return None
        out: list[tuple[int, int]] = []
        if platform != "Xbox":
            if len(value) != 48:
                return None
            start = None
            for n, allowed in enumerate([*value, False]):
                if allowed and start is None:
                    start = n
                elif not allowed and start is not None:
                    out.append((start * 30, n * 30))
                    start = None
            return out
        for item in value:
            if not isinstance(item, dict):
                return None
            begin, end = _clock(item.get("begin")), _clock(item.get("end"))
            if begin is None or end is None:
                return None
            out.append((begin, MINUTES_A_DAY if end <= begin or end >= MINUTES_A_DAY - 1 else end))
        return out
    return None


def _local(value: Any) -> str:
    when = _when(value)
    return dt_util.as_local(when).isoformat(timespec="seconds") if when is not None else str(value)


def _scrub(text: str) -> str:
    """An error as logged: long numbers (account ids, xuids) left out."""
    import re

    return re.sub(r"\d{6,}", "<id>", text)


def _just(written_at: Any) -> bool:
    """Written this soon: Family Safety may not show it yet."""
    written = _when(written_at)
    return written is not None and dt_util.utcnow() - written < QUIET_AFTER_CALL


def _clock(value: Any) -> int | None:
    """ "22:00:00" or "22:00" as minutes from midnight."""
    try:
        hours, minutes = str(value).split(":")[:2]
        return int(hours) * 60 + int(minutes)
    except (TypeError, ValueError):
        return None


def _hhmm(minutes: int) -> str:
    return f"{minutes // 60:02d}:{minutes % 60:02d}"


def fs_hold_released(response: Any) -> bool:
    """Family Safety's add_time_bonus answer says the lock Hearth held there is gone for good (Hearth no longer holds
    the platform). A Family Safety that keeps holds answers hold_kept: true when it keeps the lock to put back after
    the extra time, false when it doesn't. Upstream's answers {added, until, replaced_lock}: extra time that replaced
    a lock ended it. No answer, or neither field: as before, Hearth keeps holding the platform."""
    if not isinstance(response, dict):
        return False
    if "hold_kept" in response:
        return response["hold_kept"] is False
    return response.get("replaced_lock") is True


def _fs_target(entity_id: str) -> dict[str, Any]:
    return {"entity_id": entity_id} if "." in entity_id else {"account_id": entity_id}


def _int(value: Any) -> int | None:
    number = _number(value)
    return None if number is None else int(number)


def _number(value: Any) -> float | None:
    try:
        number = float(value)
    except (TypeError, ValueError):
        return None
    return number if number == number else None
