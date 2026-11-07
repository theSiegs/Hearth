"""Keeping Hearth and the parents' own apps (Family Link, Nintendo, Microsoft Family Safety) in step, both ways. See
docs/home-assistant-integration.md, Keeping the parents' apps in step.

- A parent's change in their app that lets a kid use what Hearth holds becomes a grant (grants.py; found by
  enforce.py, which knows what it holds).
- An adult ending a grant early from Hearth: where that maps to a write in the first-party app, it's made (a Family
  Link bonus reset, Family Safety extra time cancelled); a re-lock is simply Hearth's hold coming back.
"""

from __future__ import annotations

import logging
from typing import TYPE_CHECKING, Any

from homeassistant.core import HomeAssistant, callback
from homeassistant.util import dt as dt_util

from . import grants as g

if TYPE_CHECKING:
    from .grants import Grant
    from .household import Household

_LOGGER = logging.getLogger(__name__)

FL_DOMAIN = "familylink"
FS_DOMAIN = "microsoft_family_safety"
# A parent's change became a grant (its view)
EVENT_PARENT_GRANT = "hearth_parent_grant"


class NativeSync:
    """Hearth's side of the two-way sync with the first-party parental control apps."""

    def __init__(self, hass: HomeAssistant, household: Household) -> None:
        self.hass = hass
        self.household = household
        # The entities whose change may be a parent's (a state change of one recomputes)
        self.watched: set[str] = set()
        # The Family Link bonus minutes Hearth added today, by person: {"day", "devices" {device id: minutes}}
        self.fl_added: dict[str, dict[str, Any]] = {}
        household.enforcement.on_applied = self.after_apply

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
            self.hass.async_create_task(self._end_write(grant), "hearth grant end")

    async def _end_write(self, grant: Grant) -> None:
        enforcer = self._enforcer(grant.person, grant.via)
        key = f"{grant.via}|{grant.person}"
        try:
            if grant.end_with == g.END_RESET_BONUS:
                pressed = await self._reset_family_link_bonus(grant.person)
                self.household.enforcement.note(key, ended_grant=grant.id, bonus_reset=pressed)
            elif grant.end_with == g.END_CANCEL_BONUS and enforcer is not None:
                if not self.hass.services.has_service(FS_DOMAIN, "cancel_time_bonus"):
                    raise ValueError("Family Safety can't cancel extra time (update it)")
                await self.hass.services.async_call(
                    FS_DOMAIN,
                    "cancel_time_bonus",
                    {**_fs_target(enforcer.entity_id), "platform": grant.value},
                    blocking=True,
                )
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


def _fs_target(entity_id: str) -> dict[str, Any]:
    return {"entity_id": entity_id} if "." in entity_id else {"account_id": entity_id}


def _number(value: Any) -> float | None:
    try:
        number = float(value)
    except (TypeError, ValueError):
        return None
    return number if number == number else None
