"""Who may read the household and call Hearth's services (docs/home-assistant-integration.md, Security).

An administrator, or a user whose person is an adult on Hearth's page (a second parent who isn't an administrator).
A service call with no user (an automation, or a script an automation runs) is the household's own and may too.
Anyone else (a kid with a Home Assistant user of their own, say) is refused.
"""

from __future__ import annotations

from collections.abc import Awaitable, Callable
import inspect
from typing import Any

from homeassistant.core import Context, HomeAssistant, ServiceCall
from homeassistant.exceptions import Unauthorized

from .const import CONF_ROLES, DOMAIN


def is_adult_user(hass: HomeAssistant, hub, user) -> bool:
    """An administrator, or a user whose person is an adult on Hearth's page."""
    if user is None:
        return False
    if user.is_admin:
        return True
    if hub is None:
        return False
    roles = hub.entry.options.get(CONF_ROLES, {})
    return any(
        roles.get(state.entity_id) == "adult" and state.attributes.get("user_id") == user.id
        for state in hass.states.async_all("person")
    )


def is_kid_user(hass: HomeAssistant, hub, user) -> bool:
    """A user (not an administrator) whose person is a kid on Hearth's page."""
    if user is None or user.is_admin or hub is None:
        return False
    roles = hub.entry.options.get(CONF_ROLES, {})
    return any(
        roles.get(state.entity_id) == "kid" and state.attributes.get("user_id") == user.id
        for state in hass.states.async_all("person")
    )


def _hub(hass: HomeAssistant):
    entries = hass.config_entries.async_loaded_entries(DOMAIN)
    return entries[0].runtime_data if entries else None


async def async_check_caller(hass: HomeAssistant, call: ServiceCall) -> None:
    """Raises Unauthorized unless the call is an automation's, an administrator's or an adult's."""
    await async_check_context(hass, call.context)


async def async_check_context(hass: HomeAssistant, context: Context | None) -> None:
    """async_check_caller for a [context] (an entity's service call, say): no user (or no context) is the
    household's own and may; else an administrator or an adult only."""
    user_id = context.user_id if context is not None else None
    if user_id is None:
        return
    user = await hass.auth.async_get_user(user_id)
    if user is None or not is_adult_user(hass, _hub(hass), user):
        raise Unauthorized(context=context, user_id=user_id)


def adults_only(hass: HomeAssistant, handler: Callable[[ServiceCall], Any]) -> Callable[[ServiceCall], Awaitable[Any]]:
    """A service handler that checks the caller first."""

    async def checked(call: ServiceCall) -> Any:
        await async_check_caller(hass, call)
        result = handler(call)
        return await result if inspect.isawaitable(result) else result

    # Not functools.wraps: it would copy @callback's mark onto a coroutine function
    checked.__name__ = getattr(handler, "__name__", "service")
    return checked


def register_service(hass: HomeAssistant, domain: str, name: str, handler, **kwargs: Any) -> None:
    """hass.services.async_register, with the caller checked first (adults_only)."""
    hass.services.async_register(domain, name, adults_only(hass, handler), **kwargs)
