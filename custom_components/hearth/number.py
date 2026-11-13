"""Per person and group: the daily budget (weekday and weekend) and today's bonus, as numbers an adult can set.

As Hearth's services (auth.py): an administrator, a user whose person is an adult on Hearth's page, or an automation
(no user) may change them; anyone else (a kid with a Home Assistant user of their own) is refused with an error."""

from __future__ import annotations

from homeassistant.components.number import NumberEntity, NumberMode
from homeassistant.const import UnitOfTime
from homeassistant.core import HomeAssistant
from homeassistant.exceptions import ServiceValidationError
from homeassistant.helpers.entity_platform import AddConfigEntryEntitiesCallback

from . import HearthConfigEntry
from .auth import is_adult_user
from .entity import HearthPersonEntity
from .hub import HearthHub
from .limits import DAY_TYPES, Group

# -1 is "no limit" (as Nintendo's own does): a number entity can't be left empty
NO_LIMIT = -1
MAX_MINUTES = 24 * 60


async def async_setup_entry(
    hass: HomeAssistant, entry: HearthConfigEntry, async_add_entities: AddConfigEntryEntitiesCallback
) -> None:
    hub = entry.runtime_data
    household = hub.household
    entities: list[NumberEntity] = []
    for person in household.people():
        for group in household.groups:
            entities.extend(Budget(hub, person, group, kind) for kind in DAY_TYPES)
            entities.append(Bonus(hub, person, group))
    async_add_entities(entities)


async def _check_writer(entity: HearthPersonEntity) -> None:
    """Raises unless the change is an automation's (no user), an administrator's or an adult's."""
    context = entity._context
    user_id = context.user_id if context is not None else None
    if user_id is None:
        return
    user = await entity.hass.auth.async_get_user(user_id)
    if user is None or not is_adult_user(entity.hass, entity.hub, user):
        raise ServiceValidationError(
            "Only an adult can change Hearth's budgets and bonus time (an administrator, or a user whose person is an "
            "adult on Hearth's page)"
        )


class Budget(HearthPersonEntity, NumberEntity):
    """A group's daily budget on weekdays or at weekends (-1: no limit)."""

    _attr_native_min_value = NO_LIMIT
    _attr_native_max_value = MAX_MINUTES
    _attr_native_step = 5
    _attr_mode = NumberMode.BOX
    _attr_native_unit_of_measurement = UnitOfTime.MINUTES

    def __init__(self, hub: HearthHub, person: str, group: Group, kind: str) -> None:
        super().__init__(hub, person, f"budget_{kind}", group)
        self.kind = kind
        self._attr_translation_key = f"budget_{kind}"

    @property
    def native_value(self) -> float:
        minutes = self.hub.household.limits.budget(self.person, self.budget_group.id, self.kind)
        return NO_LIMIT if minutes is None else minutes

    async def async_set_native_value(self, value: float) -> None:
        await _check_writer(self)
        minutes = None if value < 0 else int(value)
        self.hub.household.set_budget(self.person, self.budget_group.id, self.kind, minutes)


class Bonus(HearthPersonEntity, NumberEntity):
    """Minutes added to a group's budget today (back to 0 at midnight)."""

    _attr_translation_key = "bonus_today"
    _attr_native_min_value = -MAX_MINUTES
    _attr_native_max_value = MAX_MINUTES
    _attr_native_step = 5
    _attr_mode = NumberMode.BOX
    _attr_native_unit_of_measurement = UnitOfTime.MINUTES

    def __init__(self, hub: HearthHub, person: str, group: Group) -> None:
        super().__init__(hub, person, "bonus_today", group)

    @property
    def native_value(self) -> float:
        return self.hub.household.limits.bonus(self.person, self.budget_group.id)

    async def async_set_native_value(self, value: float) -> None:
        await _check_writer(self)
        self.hub.household.set_bonus(self.person, self.budget_group.id, int(value))
