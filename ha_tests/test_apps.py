"""New apps: noticed, suggested a group, asked about, and sorted into a group."""

from homeassistant.components import persistent_notification
from homeassistant.core import HomeAssistant
from homeassistant.data_entry_flow import FlowResultType
from pytest_homeassistant_custom_component.common import async_capture_events, async_mock_service
from pytest_homeassistant_custom_component.typing import ClientSessionGenerator

from custom_components.hearth.const import DOMAIN
from test_people import _household_with_sam
from test_sources import _option

ALLOWED = "sensor.sam_family_link_apps_without_limits"


def _allowed(hass: HomeAssistant, *apps: tuple[str, str]) -> None:
    hass.states.async_set(
        ALLOWED, str(len(apps)), {"child_name": "Sam", "apps": [{"package": p, "name": n} for p, n in apps]}
    )


async def _watching(hass: HomeAssistant, hass_client_no_auth, phone: bool = False):
    await _household_with_sam(hass, hass_client_no_auth)
    _allowed(hass, ("com.example.old", "Old App"))
    await _option(hass, "add_group", {"name": "Streaming", "apps": ["com.netflix.ninja"]})
    data = {"entities": [ALLOWED]}
    if phone:
        data["notify"] = "notify.mobile_app_parent"
    await _option(hass, "new_apps", data)


def _waiting(hass: HomeAssistant) -> list[dict]:
    return hass.states.get("sensor.hearth_home_apps_to_sort").attributes["apps"]


async def test_what_was_there_already_isn_t_new(hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator) -> None:
    await _watching(hass, hass_client_no_auth)
    assert hass.states.get("sensor.hearth_home_apps_to_sort").state == "0"


async def test_a_newly_allowed_app_is_asked_about(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator
) -> None:
    calls = async_mock_service(hass, "notify", "mobile_app_parent")
    await _watching(hass, hass_client_no_auth, phone=True)
    events = async_capture_events(hass, "hearth_new_app")

    _allowed(hass, ("com.example.old", "Old App"), ("com.example.newgame", "New Game"))
    await hass.async_block_till_done()

    assert [e.data["package"] for e in events] == ["com.example.newgame"]
    assert _waiting(hass)[0]["name"] == "New Game"
    assert _waiting(hass)[0]["who"] == "Sam"
    notes = persistent_notification._async_get_or_create_notifications(hass)
    assert any("New Game" in n["message"] for n in notes.values())
    assert len(calls) == 1
    buttons = [a["title"] for a in calls[0].data["data"]["actions"]]
    assert buttons == ["Streaming", "Games", "Other"]


async def test_an_app_already_in_a_group_isn_t_asked_about(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator
) -> None:
    await _watching(hass, hass_client_no_auth)
    _allowed(hass, ("com.example.old", "Old App"), ("com.netflix.ninja", "Netflix"))
    await hass.async_block_till_done()
    assert hass.states.get("sensor.hearth_home_apps_to_sort").state == "0"


async def test_sorting_on_the_phone_puts_it_in_the_group(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator
) -> None:
    async_mock_service(hass, "notify", "mobile_app_parent")
    await _watching(hass, hass_client_no_auth, phone=True)
    _allowed(hass, ("com.example.old", "Old App"), ("com.example.show", "Show Box"))
    await hass.async_block_till_done()

    hass.bus.async_fire("mobile_app_notification_action", {"action": "HEARTH_APP|streaming|com.example.show"})
    await hass.async_block_till_done()

    entry = hass.config_entries.async_entries(DOMAIN)[0]
    streaming = next(g for g in entry.options["groups"] if g["id"] == "streaming")
    assert "com.example.show" in streaming["apps"]
    assert hass.states.get("sensor.hearth_home_apps_to_sort").state == "0"
    notes = persistent_notification._async_get_or_create_notifications(hass)
    assert not any("Show Box" in n["message"] for n in notes.values())


async def test_sorting_in_the_options(hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator) -> None:
    await _watching(hass, hass_client_no_auth)
    _allowed(hass, ("com.example.old", "Old App"), ("com.example.a", "Alpha"), ("com.example.b", "Beta"))
    await hass.async_block_till_done()
    entry = hass.config_entries.async_entries(DOMAIN)[0]

    result = await hass.config_entries.options.async_init(entry.entry_id)
    result = await hass.config_entries.options.async_configure(result["flow_id"], {"next_step_id": "sort_apps"})
    assert result["type"] is FlowResultType.FORM
    result = await hass.config_entries.options.async_configure(
        result["flow_id"], {"Alpha (com.example.a)": "games", "Beta (com.example.b)": "other"}
    )
    assert result["type"] is FlowResultType.CREATE_ENTRY
    await hass.async_block_till_done()
    assert "com.example.a" in entry.options["group_apps"]["games"]
    assert hass.states.get("sensor.hearth_home_apps_to_sort").state == "0"


async def test_a_newly_watched_list_isn_t_a_flood(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator
) -> None:
    await _watching(hass, hass_client_no_auth)
    other = "sensor.alex_family_link_apps_without_limits"
    hass.states.async_set(other, "2", {"child_name": "Alex", "apps": [{"package": "com.example.x", "name": "X"}]})
    await _option(hass, "new_apps", {"entities": [ALLOWED, other]})
    assert hass.states.get("sensor.hearth_home_apps_to_sort").state == "0"
