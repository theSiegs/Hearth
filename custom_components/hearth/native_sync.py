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
from homeassistant.helpers import entity_registry as er

from . import grants as g

if TYPE_CHECKING:
    from .grants import Grant
    from .household import Household

_LOGGER = logging.getLogger(__name__)

FL_DOMAIN = "familylink"
FS_DOMAIN = "microsoft_family_safety"


class NativeSync:
    """Hearth's side of the two-way sync with the first-party parental control apps."""

    def __init__(self, hass: HomeAssistant, household: Household) -> None:
        self.hass = hass
        self.household = household

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
