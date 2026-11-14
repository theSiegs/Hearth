"""Each kid's to-do list (todos.py) as a Home Assistant to-do entity, todo.hearth_<kid>: the to-do card on a tablet,
Assist's list intents and todo.item_completed triggers.

What a change may do depends on who makes it (the context's user, todos.async_actor): an adult anything; the kid ticks
and unticks their items and adds, changes and removes their own; a sibling nothing; anyone else (a shared screen's user,
voice, an automation) ticks without a reward. See the design's table "What each to-do operation does, by caller"."""

from __future__ import annotations

from homeassistant.components.todo import TodoItem, TodoItemStatus, TodoListEntity, TodoListEntityFeature
from homeassistant.core import HomeAssistant
from homeassistant.helpers.entity_platform import AddConfigEntryEntitiesCallback

from . import HearthConfigEntry
from .entity import HearthPersonEntity
from .hub import HearthHub
from .todos import Actor, async_actor


async def async_setup_entry(
    hass: HomeAssistant, entry: HearthConfigEntry, async_add_entities: AddConfigEntryEntitiesCallback
) -> None:
    hub = entry.runtime_data
    async_add_entities(KidTodo(hub, person) for person in hub.household.todos.kids())


class KidTodo(HearthPersonEntity, TodoListEntity):
    """"Alex's to-do": today's items of Alex's tasks and Alex's open one-off tasks; uids are occurrence ids."""

    _attr_has_entity_name = False
    _attr_supported_features = (
        TodoListEntityFeature.CREATE_TODO_ITEM
        | TodoListEntityFeature.UPDATE_TODO_ITEM
        | TodoListEntityFeature.DELETE_TODO_ITEM
        | TodoListEntityFeature.SET_DESCRIPTION_ON_ITEM
        | TodoListEntityFeature.SET_DUE_DATE_ON_ITEM
        # The card sends a timed item's due time back with every tick
        | TodoListEntityFeature.SET_DUE_DATETIME_ON_ITEM
    )

    def __init__(self, hub: HearthHub, person: str) -> None:
        super().__init__(hub, person, "todo")
        self._attr_name = f"{hub.household.person_name(person)}'s to-do"
        # Not on the person's device: the To-do panel lists it by this name alone
        self._attr_device_info = None
        self.entity_id = f"todo.hearth_{person.split('.', 1)[-1]}"

    @property
    def book(self):
        return self.hub.household.todos

    @property
    def todo_items(self) -> list[TodoItem]:
        return [
            TodoItem(
                uid=occ.id,
                summary=self.book.summary_of(occ.task),
                status=TodoItemStatus.COMPLETED if occ.done is not None else TodoItemStatus.NEEDS_ACTION,
                due=occ.due,
                description=occ.task.get("description"),
            )
            for occ in self.book.items(self.person)
        ]

    async def _actor(self) -> Actor:
        user_id = self._context.user_id if self._context is not None else None
        return await async_actor(self.hass, self.hub, user_id, "todo")

    async def async_create_todo_item(self, item: TodoItem) -> None:
        self.book.add_item(self.person, item.summary or "", await self._actor(), item.description, item.due)

    async def async_update_todo_item(self, item: TodoItem) -> None:
        self.book.edit_item(
            item.uid or "",
            self.person,
            await self._actor(),
            summary=item.summary,
            description=item.description or "",
            due=item.due,
            done=None if item.status is None else item.status == TodoItemStatus.COMPLETED,
        )

    async def async_delete_todo_items(self, uids: list[str]) -> None:
        self.book.delete_items(self.person, uids, await self._actor())
