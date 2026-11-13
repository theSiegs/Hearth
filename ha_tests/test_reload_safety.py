"""Work that must not outlive the entry, and the app list that's built once per document."""

import asyncio
from unittest.mock import patch

from homeassistant.core import HomeAssistant
from pytest_homeassistant_custom_component.typing import ClientSessionGenerator

from custom_components.hearth.const import DOMAIN
from custom_components.hearth.enforce import Enforcement
from test_people import _household_with_sam


async def test_the_app_list_is_built_once_per_document(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator
) -> None:
    """known_apps() walks every device, source and sensor: one build asks for it once, not once per group."""
    await _household_with_sam(hass, hass_client_no_auth)
    household = hass.config_entries.async_entries(DOMAIN)[0].runtime_data.household
    real = household.known_apps
    with patch.object(household, "known_apps", side_effect=real) as known_apps:
        groups = [g for g in household.groups if g.id != "all"]
        assert len(groups) >= 2
        membership = household.membership()
        for group in groups:
            household._group_apps(group, membership)
        assert known_apps.call_count == 1
        # A new build (a new membership) sees what changed since
        household._group_apps(groups[0], household.membership())
        assert known_apps.call_count == 2


async def test_flush_waits_for_the_running_pass_and_starts_no_new_one(hass: HomeAssistant) -> None:
    """On unload the enforcement pass under way stops before the store is saved, and none starts after."""
    enforcement = Enforcement(hass, "not-an-entry")
    started = asyncio.Event()

    async def slow_pass() -> None:
        started.set()
        await asyncio.sleep(3600)

    enforcement._async_apply = slow_pass
    enforcement._run()
    await started.wait()
    running = enforcement._task

    await enforcement.async_flush()

    assert running is not None and running.done()
    enforcement._run()
    assert enforcement._task is running
