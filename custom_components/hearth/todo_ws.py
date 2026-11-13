"""The to-do lists' commands (todos.py): hearth.chore_undo for the adults' Undo button, and the panel's WebSocket
commands (its Chores card): a kid's list and ledger, a task saved or removed, an item ticked, a reward given or undone,
money paid out or adjusted, and the daily caps. Administrators only, as the rest of the panel; the service checks the
adult as every Hearth service does (auth.py)."""

from __future__ import annotations

from typing import Any

import voluptuous as vol

from homeassistant.components import websocket_api
from homeassistant.core import HomeAssistant, ServiceCall, callback
from homeassistant.exceptions import ServiceValidationError
from homeassistant.helpers import config_validation as cv

from .auth import register_service
from .const import DOMAIN
from .todos import ADJUST, ADULT, CONF_CHORE_CAPS, MAX_REWARD_MINUTES, PAID, REPEATS, SERVICE_CHORE_UNDO, Actor, ChoreError

CHORE_UNDO_SCHEMA = vol.Schema({vol.Required("key"): cv.string})
_PERSON = cv.entity_domain("person")
_REWARD = vol.Any(
    None,
    vol.Schema({vol.Required("pool"): cv.string, vol.Required("minutes"): vol.All(int, vol.Range(min=1, max=MAX_REWARD_MINUTES))}),
    vol.Schema({vol.Required("cents"): vol.All(int, vol.Range(min=1, max=10000))}),
)
_REPEAT = vol.Schema(
    {
        vol.Required("kind"): vol.In(REPEATS),
        vol.Optional("days"): [vol.All(int, vol.Range(min=0, max=6))],
        vol.Optional("n"): vol.All(int, vol.Range(min=1, max=365)),
        vol.Optional("start"): cv.string,
    }
)


def _hub(hass: HomeAssistant):
    entries = hass.config_entries.async_loaded_entries(DOMAIN)
    return entries[0].runtime_data if entries else None


def _adult(connection) -> Actor:
    return Actor(ADULT, user_id=connection.user.id, via="panel")


def _run(connection, msg, work) -> None:
    try:
        result = work()
    except ChoreError as err:
        connection.send_error(msg["id"], err.code, str(err))
        return
    connection.send_result(msg["id"], result)


def _book(hass: HomeAssistant, connection, msg):
    hub = _hub(hass)
    if hub is None:
        connection.send_error(msg["id"], "not_set_up", "Hearth isn't set up")
        return None
    return hub.household.todos


@websocket_api.require_admin
@websocket_api.websocket_command({vol.Required("type"): "hearth/todo/list", vol.Required("person"): _PERSON})
@callback
def ws_list(hass: HomeAssistant, connection: websocket_api.ActiveConnection, msg: dict[str, Any]) -> None:
    """One kid's tasks, today's items, recent ledger entries, balance and chore minutes today; and the caps."""
    if (book := _book(hass, connection, msg)) is not None:
        connection.send_result(msg["id"], {**book.view(msg["person"]), "caps": book.caps()})


@websocket_api.require_admin
@websocket_api.websocket_command(
    {
        vol.Required("type"): "hearth/todo/task/save",
        vol.Optional("task_id"): vol.Any(None, cv.string),
        vol.Required("person"): _PERSON,
        vol.Required("title"): cv.string,
        vol.Optional("description"): vol.Any(None, cv.string),
        vol.Optional("repeat"): _REPEAT,
        vol.Optional("due_time"): vol.Any(None, cv.string),
        vol.Optional("due_date"): vol.Any(None, cv.string),
        vol.Optional("reward"): _REWARD,
    }
)
@callback
def ws_task_save(hass: HomeAssistant, connection: websocket_api.ActiveConnection, msg: dict[str, Any]) -> None:
    if (book := _book(hass, connection, msg)) is None:
        return
    data = {k: v for k, v in msg.items() if k not in ("id", "type", "task_id")}
    data["id"] = msg.get("task_id")
    _run(connection, msg, lambda: book.save_task(data, _adult(connection)))


@websocket_api.require_admin
@websocket_api.websocket_command({vol.Required("type"): "hearth/todo/task/delete", vol.Required("task_id"): cv.string})
@callback
def ws_task_delete(hass: HomeAssistant, connection: websocket_api.ActiveConnection, msg: dict[str, Any]) -> None:
    if (book := _book(hass, connection, msg)) is not None:
        _run(connection, msg, lambda: book.delete_task(msg["task_id"], _adult(connection)))


@websocket_api.require_admin
@websocket_api.websocket_command(
    {vol.Required("type"): "hearth/todo/check", vol.Required("item"): cv.string, vol.Required("done"): bool}
)
@callback
def ws_check(hass: HomeAssistant, connection: websocket_api.ActiveConnection, msg: dict[str, Any]) -> None:
    """An adult ticks or unticks an item: a tick grants its reward, as the kid's own would."""
    if (book := _book(hass, connection, msg)) is not None:
        _run(connection, msg, lambda: {"granted": book.check(msg["item"], msg["done"], _adult(connection))})


@websocket_api.require_admin
@websocket_api.websocket_command({vol.Required("type"): "hearth/todo/give", vol.Required("item"): cv.string})
@callback
def ws_give(hass: HomeAssistant, connection: websocket_api.ActiveConnection, msg: dict[str, Any]) -> None:
    """The reward of a done item that has none live (a shared screen's tick, or after an undo)."""
    if (book := _book(hass, connection, msg)) is not None:
        _run(connection, msg, lambda: book.give(msg["item"], _adult(connection)))


@websocket_api.require_admin
@websocket_api.websocket_command({vol.Required("type"): "hearth/todo/undo", vol.Required("key"): cv.string})
@callback
def ws_undo(hass: HomeAssistant, connection: websocket_api.ActiveConnection, msg: dict[str, Any]) -> None:
    if (book := _book(hass, connection, msg)) is not None:
        _run(connection, msg, lambda: book.undo(msg["key"], connection.user.id))


@websocket_api.require_admin
@websocket_api.websocket_command(
    {
        vol.Required("type"): "hearth/todo/money",
        vol.Required("person"): _PERSON,
        vol.Required("kind"): vol.In((PAID, ADJUST)),
        vol.Required("cents"): int,
        vol.Optional("note"): vol.Any(None, cv.string),
    }
)
@callback
def ws_money(hass: HomeAssistant, connection: websocket_api.ActiveConnection, msg: dict[str, Any]) -> None:
    if (book := _book(hass, connection, msg)) is not None:
        _run(
            connection,
            msg,
            lambda: book.money(msg["person"], msg["kind"], msg["cents"], _adult(connection), msg.get("note")),
        )


@websocket_api.require_admin
@websocket_api.websocket_command(
    {
        vol.Required("type"): "hearth/todo/caps",
        vol.Required("caps"): vol.Schema({cv.string: vol.Any(None, vol.All(int, vol.Range(min=0, max=1440)))}),
    }
)
@callback
def ws_caps(hass: HomeAssistant, connection: websocket_api.ActiveConnection, msg: dict[str, Any]) -> None:
    """The most chores earn a kid a day per group ({group: minutes}; null: no cap). The entry reloads with it."""
    hub = _hub(hass)
    if hub is None:
        connection.send_error(msg["id"], "not_set_up", "Hearth isn't set up")
        return
    caps = {g: m for g, m in msg["caps"].items() if m is not None and (g == "all" or hub.household.group(g))}
    hass.config_entries.async_update_entry(hub.entry, options={**hub.entry.options, CONF_CHORE_CAPS: caps})
    connection.send_result(msg["id"], caps)


@callback
def async_register_commands(hass: HomeAssistant) -> None:
    for command in (ws_list, ws_task_save, ws_task_delete, ws_check, ws_give, ws_undo, ws_money, ws_caps):
        websocket_api.async_register_command(hass, command)


def async_register_services(hass: HomeAssistant) -> None:
    @callback
    def chore_undo(call: ServiceCall) -> None:
        """An adult's Undo (the button on a chore's notice): the reward is taken back, whole."""
        hub = _hub(hass)
        if hub is None:
            raise ServiceValidationError("Hearth isn't set up")
        try:
            hub.household.todos.undo(call.data["key"], call.context.user_id)
        except ChoreError as err:
            raise ServiceValidationError(str(err)) from err

    register_service(hass, DOMAIN, SERVICE_CHORE_UNDO, chore_undo, schema=CHORE_UNDO_SCHEMA)
