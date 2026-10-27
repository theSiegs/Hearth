"""Per person and group: the daily budget (weekday and weekend) and today's bonus, as numbers anyone can set."""

from __future__ import annotations

from homeassistant.components.number import NumberEntity, NumberMode
from homeassistant.const import UnitOfTime
from homeassistant.core import HomeAssistant
from homeassistant.helpers.entity_platform import AddConfigEntryEntitiesCallback

from . import HearthConfigEntry
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
        minutes = None if value < 0 else int(value)
        self.hub.household.set_budget(self.person, self.budget_group.id, self.kind, minutes)


class Bonus(HearthPersonEntity, NumberEntity):
    """Minutes added to a group's budget today (back to 0 at midnight)."""

    _attr_translation_key = "bonus_today"
    _attr_native_min_value = 0
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
        self.hub.household.set_bonus(self.person, self.budget_group.id, int(value))
