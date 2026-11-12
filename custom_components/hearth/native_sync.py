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
from homeassistant.exceptions import HomeAssistantError
from homeassistant.helpers.storage import Store
from homeassistant.util import dt as dt_util

from .entry_tasks import entry_task
from . import grants as g
from .counting import ALL
from .enforce import (
    FAMILY_LINK,
    FAMILY_SAFETY,
    FS_HOLD_BONUS_OURS,
    FS_HOLD_OURS,
    FS_HOLD_PARENT,
    fs_accepts,
    fs_account_of,
    fs_hold_state,
)
from .exceptions import end_of_day

if TYPE_CHECKING:
    from .grants import Grant
    from .household import Household

_LOGGER = logging.getLogger(__name__)

FL_DOMAIN = "familylink"
FS_DOMAIN = "microsoft_family_safety"
# The platforms Family Safety can give extra time on (Windows only where the installed one takes it: fs_accepts)
FS_BONUS_PLATFORMS = ("Xbox", "Windows")
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
        # Extra time Hearth gave in the first-party apps, by (person, why: allow:<id> or bonus:<when>)
        self._given: dict[tuple[str, str], dict[str, Any]] = {}

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

    def _data(self) -> dict[str, Any]:
        return {"fl_added": self.fl_added, "given": {f"{p}|{why}": r for (p, why), r in self._given.items()}}

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
                left = max(left, bonus - own.get(str(device.attributes.get("device_id")), 0))
            if left <= 0:
                _LOGGER.info("%s: the Family Link bonus is over, Hearth holds again", grant.person)
                self.household.grants.end(grant.id)
                changed = True
        self.watched = watch
        return changed

    def _enforcer(self, person: str, kind: str):
        return next((e for e in self.household.enforcement.enforcers if e.person == person and e.kind == kind), None)

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
            await self.hass.services.async_call(
                FL_DOMAIN, "reset_bonus", {"entity_id": device.entity_id}, blocking=True
            )
            return
        button = fl.reset_bonus_button(self.hass, child, str(device.attributes.get("device_id")), device.entity_id)
        if button is None:
            raise ValueError(f"Family Link can't reset the bonus of {device.entity_id} (update it)")
        await self.hass.services.async_call("button", "press", {"entity_id": button}, blocking=True)

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
    def mirror_bonus(self, person: str, had_none: bool) -> None:
        """Extra time that gave All screen time back (it had none left): Google's and Microsoft's own limits get
        as much, until midnight at most."""
        day = self.household.days.get(person)
        state = day.limits.get(ALL) if day else None
        left = state.minutes_left if state else None
        if not had_none or left is None or left <= 0 or not self._mirrors(person):
            return
        now = dt_util.now()
        key = (person, f"bonus:{now.isoformat()}")
        self._given[key] = {"day": now.date().isoformat(), "devices": {}, "platforms": []}
        self._save()
        until = min(now + timedelta(minutes=left), end_of_day(now))
        entry_task(self.hass, self.household.hub.entry.entry_id, self._give_time(person, until, key), "hearth first-party extra time")

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
        if record and (record["devices"] or record["platforms"]):
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
                await self.hass.services.async_call(
                    FL_DOMAIN, "add_time_bonus", {"entity_id": device.entity_id, "bonus_minutes": bonus}, blocking=True
                )
            except Exception as err:  # noqa: BLE001 - shown on Hearth's page; Hearth's own holds are let go anyway
                _LOGGER.warning("Hearth couldn't add Family Link bonus time on %s: %s", device.entity_id, err)
                error = str(err)[:200]
                continue
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
        where the installed Family Safety takes it) whose allowance would block within [minutes]. Extra time replaces
        Hearth's own lock there; when Family Safety lets go of that lock for good (fs_hold_released), Hearth no longer
        holds the platform. A failure says Family Safety's extra time is unavailable, isn't retried, and counts as not
        given."""
        enforcer = self._enforcer(person, FAMILY_SAFETY)
        if enforcer is None or not self.hass.services.has_service(FS_DOMAIN, "add_time_bonus"):
            return
        given: dict[str, Any] = {}
        error = None
        for platform in enforcer.platforms:
            if only is not None and platform != only:
                continue
            # Family Safety gives extra time on the Xbox and (a newer one) on Windows, never on Mobile
            if platform not in FS_BONUS_PLATFORMS or not self._fs_would_block(enforcer.entity_id, platform, minutes):
                continue
            data = {
                **_fs_target(enforcer.entity_id),
                "platform": platform,
                "until": dt_util.as_local(until).replace(tzinfo=None, microsecond=0).isoformat(),
            }
            # Extra time replaces Hearth's own lock (Family Safety puts it back when the time ends), never a parent's
            hold = fs_hold_state(self.hass, enforcer.entity_id, platform)
            if hold and hold.get("hold") in (FS_HOLD_OURS, FS_HOLD_BONUS_OURS):
                data["replace_lock"] = True
            if platform != "Xbox" and not fs_accepts(self.hass, "add_time_bonus", data):
                # A Family Safety without Windows extra time (upstream's is Xbox only): skipped quietly
                _LOGGER.debug("Family Safety gives no extra time on %s; skipped for %s", platform, person)
                continue
            try:
                response = await self.hass.services.async_call(
                    FS_DOMAIN,
                    "add_time_bonus",
                    data,
                    blocking=True,
                    return_response=self.household.enforcement._responds(FS_DOMAIN, "add_time_bonus"),
                )
            except (HomeAssistantError, vol.Invalid) as err:
                _LOGGER.info("Family Safety extra time on %s for %s unavailable: %s", platform, person, err)
                error = f"Family Safety extra time unavailable: {err}"[:200]
                continue
            given[platform] = (
                response.get("applied_until") or response.get("until") if isinstance(response, dict) else None
            )
            record["platforms"].append(platform)
            if fs_hold_released(response):
                held = self.household.enforcement.held.get(f"{FAMILY_SAFETY}|{person}")
                if held is not None:
                    held.items.discard(platform)
        if given or error:
            self.household.enforcement.note(f"{FAMILY_SAFETY}|{person}", extra_time=given, reason=why, error=error)

    def _fs_would_block(self, entity_id: str, platform: str, minutes: int) -> bool:
        """Microsoft's own allowance would stop the platform within [minutes] (not a lock of Hearth's)."""
        state = fs_platform_state(self.hass, entity_id, platform)
        if state is None:
            return False
        allowance, used = _number(state.get("allowance_minutes")), _number(state.get("used_minutes"))
        if state.get("hold") in ("ours", "bonus_ours") or (allowance is not None and used is not None):
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
            if record["devices"] or record["platforms"]:
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
        if enforcer is None or not record["platforms"]:
            return
        cancelled: list[str] = []
        kept: list[str] = []
        error = None
        for platform in record["platforms"]:
            # Only Hearth's own extra time is cancelled: a parent's extra time or lock that came since (the hold
            # reads parent) is theirs, and a cancel would end it
            hold = fs_hold_state(self.hass, enforcer.entity_id, platform)
            if hold and hold.get("hold") == FS_HOLD_PARENT:
                kept.append(platform)
                continue
            try:
                await self.cancel_family_safety_bonus(enforcer.entity_id, platform)
                cancelled.append(platform)
            except Exception as err:  # noqa: BLE001 - shown; it ends when it was set to
                error = str(err)[:200]
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
        await self.hass.services.async_call(FS_DOMAIN, "cancel_time_bonus", data, blocking=True)

    # What the first-party apps say now (Hearth's page, the household summary, explain)

    def first_party(self, person: str) -> dict[str, Any]:
        """Google's own daily limit per Family Link device, and Microsoft's allowance per Family Safety platform,
        as their entities say now (only those there). blocking: the device's or platform's own limit stops it now,
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
                hold = state.get("hold")
                parent_lock = hold == FS_HOLD_PARENT and state.get("override") == FS_BLOCK_UNTIL
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
                        "override_until": state.get("override_until"),
                        "allow_until": state.get("allow_until"),
                        "held_by_hearth": bool(held and platform in held.items),
                        "parent_lock": parent_lock,
                        # Microsoft's own allowance or hours stop it, not a lock of anyone's
                        "blocking": allowed == "off" and hold in (None, "none") and not (held and platform in held.items),
                    }
                )
            if rows:
                found[FAMILY_SAFETY] = rows
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


def fs_platform_state(hass: HomeAssistant, entity_id: str, platform: str) -> dict[str, Any] | None:
    """A Family Safety platform today, from a newer Family Safety: its Allowed Now sensor's attributes (reason,
    remaining_minutes, allowance_minutes, used_minutes, hold...) with its state, else its Time Remaining sensor's.
    None when there's neither."""
    account = fs_account_of(hass, entity_id)
    if account is None:
        return None
    for domain in ("binary_sensor", "sensor"):
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
            return found
    return None


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
