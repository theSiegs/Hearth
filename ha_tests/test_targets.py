"""A person's devices for an adult's app: targets, minutes per device and per app, and extra time on one device."""

from homeassistant.core import HomeAssistant
from pytest_homeassistant_custom_component.typing import ClientSessionGenerator

from custom_components.hearth.const import DOMAIN
from custom_components.hearth.websocket import summary
from test_init import TV_ID
from test_people import _household_with_sam
from test_sources import _option

FL_PHONE = "sensor.sam_pixel_daily_screen_time"


def _hub(hass: HomeAssistant):
    return hass.config_entries.async_entries(DOMAIN)[0].runtime_data


def _sam(hass: HomeAssistant) -> dict:
    return next(p for p in summary(_hub(hass))["people"] if p["id"] == "person.sam")


async def test_minutes_by_device_and_by_app(hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator) -> None:
    await _household_with_sam(hass, hass_client_no_auth)
    # A Family Link device's own Daily screen time sensor: that device
    hass.states.async_set(
        FL_PHONE,
        "45",
        {
            "unit_of_measurement": "min",
            "child_id": "42",
            "device_id": "d1",
            "device_name": "Pixel",
            "apps": [{"package": "com.example.game", "name": "Game", "minutes": 30}],
        },
    )
    await _option(hass, "add_source", {"entity_id": FL_PHONE, "person": "person.sam", "name": "Sam's phone"})

    sam = _sam(hass)
    assert sam["devices_today"] == [
        {"target": "fl:d1", "name": "Sam's phone", "minutes": 45},
        {"target": f"hearth:{TV_ID}", "name": "Kitchen", "minutes": 15},
    ]
    apps = {a["package"]: a["minutes"] for a in sam["apps_today"]}
    assert apps == {"com.example.game": 35, "com.thesiegs.hearthtube": 10}
