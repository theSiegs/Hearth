"""New apps: noticed and sorted on their own (a group that lists them, their category, else Other); an adult moves one
later, and that beats everything."""

from homeassistant.components import persistent_notification
from homeassistant.core import Context, HomeAssistant
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


async def test_a_new_app_is_sorted_without_asking(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator
) -> None:
    calls = async_mock_service(hass, "notify", "mobile_app_parent")
    await _watching(hass, hass_client_no_auth, phone=True)
    events = async_capture_events(hass, "hearth_new_app")

    _allowed(hass, ("com.example.old", "Old App"), ("com.example.newgame", "New Game"), ("com.whatsapp", "WhatsApp"))
    await hass.async_block_till_done()

    assert {e.data["package"]: e.data["group"] for e in events} == {
        "com.example.newgame": "other",
        "com.whatsapp": "messaging",
    }
    assert hass.states.get("sensor.hearth_home_apps_to_sort").state == "0"
    assert calls == []
    notes = persistent_notification._async_get_or_create_notifications(hass)
    assert not any("New Game" in n["message"] for n in notes.values())
    household = hass.config_entries.async_entries(DOMAIN)[0].runtime_data.household
    recent = {a["package"]: a["group"] for a in household.apps_overview()["recent"]}
    assert recent == {"com.example.newgame": "other", "com.whatsapp": "messaging"}


async def test_an_app_an_adult_moved_stays_where_they_put_it(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator, hass_admin_user
) -> None:
    async_mock_service(hass, "notify", "mobile_app_parent")
    await _watching(hass, hass_client_no_auth, phone=True)
    _allowed(hass, ("com.example.old", "Old App"), ("com.example.show", "Show Box"), ("com.netflix.ninja", "Netflix"))
    await hass.async_block_till_done()

    # An older phone button still works: it moves the app
    hass.bus.async_fire("mobile_app_notification_action", {"action": "HEARTH_APP|streaming|com.example.show"}, context=Context(user_id=hass_admin_user.id))
    await hass.async_block_till_done()
    entry = hass.config_entries.async_entries(DOMAIN)[0]
    assert entry.options["app_groups"] == {"com.example.show": "streaming"}

    # Moving an app out of the group that lists it beats the list
    hass.config_entries.async_update_entry(
        entry, options={**entry.options, "app_groups": {**entry.options["app_groups"], "com.netflix.ninja": "other"}}
    )
    await hass.async_block_till_done()
    household = hass.config_entries.async_entries(DOMAIN)[0].runtime_data.household
    groups = {a["package"]: (a["group"], a["moved"]) for a in household.apps_overview()["apps"]}
    assert groups["com.example.show"] == ("streaming", True)
    assert groups["com.netflix.ninja"] == ("other", True)


async def test_a_newly_watched_list_isn_t_a_flood(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator
) -> None:
    await _watching(hass, hass_client_no_auth)
    other = "sensor.alex_family_link_apps_without_limits"
    hass.states.async_set(other, "2", {"child_name": "Alex", "apps": [{"package": "com.example.x", "name": "X"}]})
    await _option(hass, "new_apps", {"entities": [ALLOWED, other]})
    assert hass.states.get("sensor.hearth_home_apps_to_sort").state == "0"
