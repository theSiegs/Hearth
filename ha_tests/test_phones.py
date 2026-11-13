"""Requests for more time reach every adult's own phones, open the request when tapped, and leave every phone when
answered."""

from homeassistant.core import Context, HomeAssistant
from homeassistant.helpers import entity_registry as er
from pytest_homeassistant_custom_component.common import MockConfigEntry, async_mock_service
from pytest_homeassistant_custom_component.typing import ClientSessionGenerator

from custom_components.hearth.const import DOMAIN
from custom_components.hearth.phones import deep_link, page_link
from test_asks import _ask
from test_parent_pin import _adults
from test_people import _household_with_sam


def _companion_app(hass: HomeAssistant, name: str, os_name: str, user_id: str | None = None) -> str:
    """A mobile_app registration and its device tracker; the tracker's entity id."""
    entry = MockConfigEntry(
        domain="mobile_app",
        title=name,
        data={"device_name": name, "os_name": os_name, "user_id": user_id, "webhook_id": f"hook-{name}"},
    )
    entry.add_to_hass(hass)
    tracker = er.async_get(hass).async_get_or_create(
        "device_tracker", "mobile_app", f"tracker-{name}", config_entry=entry, suggested_object_id=name.replace(" ", "_")
    )
    return tracker.entity_id


async def _options(hass: HomeAssistant, **changes) -> None:
    entry = hass.config_entries.async_entries(DOMAIN)[0]
    hass.config_entries.async_update_entry(entry, options={**entry.options, **changes})
    await hass.async_block_till_done()


async def _two_adults(hass: HomeAssistant, hass_client_no_auth):
    """Sam is a kid; Alex (an Android phone they're tracked by) and Jordan (an iPhone their user registered) adults."""
    client, secret = await _household_with_sam(hass, hass_client_no_auth)
    alex_tracker = _companion_app(hass, "Alex Phone", "Android")
    _companion_app(hass, "Jordan iPhone", "iOS", user_id="jordan-user")
    hass.states.async_set("person.alex", "home", {"friendly_name": "Alex", "device_trackers": [alex_tracker]})
    hass.states.async_set("person.jordan", "home", {"friendly_name": "Jordan", "user_id": "jordan-user"})
    await _adults(hass, "person.alex", "person.jordan")
    alex = async_mock_service(hass, "notify", "mobile_app_alex_phone")
    jordan = async_mock_service(hass, "notify", "mobile_app_jordan_iphone")
    return client, secret, alex, jordan


async def test_every_adult_s_phone_gets_the_request_and_loses_it_once_answered(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator, hass_ws_client
) -> None:
    client, secret, alex, jordan = await _two_adults(hass, hass_client_no_auth)
    # The phone chosen in Configure is one of theirs: it gets it once
    await _options(hass, ask_notify="notify.mobile_app_alex_phone")

    request = (await (await _ask(client, secret, minutes=30, profile_id="user:10")).json())["request"]
    await hass.async_block_till_done()
    assert len(alex) == 1 and len(jordan) == 1
    tag = f"hearth_more_{request['id']}"
    for call in (alex[0], jordan[0]):
        assert call.data["title"] == "More time?"
        assert call.data["data"]["tag"] == tag
        assert [a["title"] for a in call.data["data"]["actions"]] == ["+30 min", "+45 min", "Not now"]
    # Android's tap and iOS's open Hearth's page at the request
    assert alex[0].data["data"]["clickAction"] == f"/hearth?ask={request['id']}" and "url" not in alex[0].data["data"]
    assert jordan[0].data["data"]["url"] == f"/hearth?ask={request['id']}" and "clickAction" not in jordan[0].data["data"]

    # Answered on Hearth's page: off every phone
    ws = await hass_ws_client(hass)
    await ws.send_json({"id": 1, "type": "hearth/approvals/answer", "request_id": request["id"], "minutes": 30})
    assert (await ws.receive_json())["success"]
    await hass.async_block_till_done()
    for phone in (alex, jordan):
        assert phone[-1].data == {"message": "clear_notification", "data": {"tag": tag}}


async def test_an_adult_can_switch_requests_off_or_open_them_in_their_own_app(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator, hass_admin_user
) -> None:
    client, secret, alex, jordan = await _two_adults(hass, hass_client_no_auth)
    other = async_mock_service(hass, "notify", "mobile_app_kitchen_tablet")
    await _options(
        hass,
        ask_notify_off=["person.jordan"],
        ask_deep_link=["person.alex"],
        ask_notify="notify.mobile_app_kitchen_tablet",
    )

    request = (await (await _ask(client, secret, minutes=15, profile_id="user:10")).json())["request"]
    await hass.async_block_till_done()
    assert not jordan
    assert alex[0].data["data"]["clickAction"] == f"hearth://ask/{request['id']}"
    # A phone that isn't a known companion app gets both, the page
    assert other[0].data["data"]["clickAction"] == page_link(request["id"])
    assert other[0].data["data"]["url"] == page_link(request["id"])

    # A button on the phone answers it: every phone told still loses it
    hass.bus.async_fire("mobile_app_notification_action", {"action": f"HEARTH_MORE|{request['id']}|0"}, context=Context(user_id=hass_admin_user.id))
    await hass.async_block_till_done()
    assert alex[-1].data["message"] == "clear_notification"
    assert other[-1].data["message"] == "clear_notification"
    assert not jordan


async def test_hearth_s_page_shows_each_adult_s_phones_and_sets_them(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator, hass_ws_client
) -> None:
    await _two_adults(hass, hass_client_no_auth)
    ws = await hass_ws_client(hass)
    await ws.send_json({"id": 1, "type": "hearth/config"})
    phones = (await ws.receive_json())["result"]["ask_phones"]
    assert phones["person.alex"] == {
        "phones": [{"service": "notify.mobile_app_alex_phone", "os": "android", "there": True}],
        "on": True,
        "deep_link": False,
    }
    assert phones["person.jordan"]["phones"][0]["os"] == "ios"

    await ws.send_json({"id": 2, "type": "hearth/config/set", "key": "ask_notify_off", "value": ["person.jordan"]})
    assert (await ws.receive_json())["success"]
    await ws.send_json({"id": 3, "type": "hearth/config/set", "key": "ask_deep_link", "value": ["not a person"]})
    assert not (await ws.receive_json())["success"]
    await hass.async_block_till_done()
    assert hass.config_entries.async_entries(DOMAIN)[0].options["ask_notify_off"] == ["person.jordan"]


def test_the_links() -> None:
    assert page_link("abc") == "/hearth?ask=abc"
    assert deep_link("abc") == "hearth://ask/abc"
