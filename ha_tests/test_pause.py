"""A family pause, and when a person's locks start and end."""

from datetime import timedelta

from homeassistant.core import HomeAssistant
from homeassistant.util import dt as dt_util
from pytest_homeassistant_custom_component.typing import ClientSessionGenerator

from custom_components.hearth.const import DOMAIN
from test_init import _post
from test_people import KID, _household_with_sam, _tv_status
from test_sources import _option


async def test_a_pause_holds_everyone_until_it_ends(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator, hass_ws_client, freezer
) -> None:
    client, secret = await _household_with_sam(hass, hass_client_no_auth)
    await hass.services.async_call(DOMAIN, "pause", {"minutes": 45, "reason": "Dinner"}, blocking=True)

    body = await (await _post(client, secret, body=_tv_status(hearthtube_s=60))).json()
    sam = body["state"]["profiles"][KID]
    assert sam["locked"] is True
    assert sam["pause"]["reason"] == "Dinner"
    assert sam["lock"]["by"] == ["pause"] and sam["lock"]["until"] == sam["pause"]["until"]
    assert sam["lock"]["kind"] == "pause"

    ws = await hass_ws_client(hass)
    await ws.send_json({"id": 1, "type": "hearth/household"})
    [person] = (await ws.receive_json())["result"]["people"]
    assert person["pause"]["reason"] == "Dinner"

    await hass.services.async_call(DOMAIN, "pause_end", {}, blocking=True)
    body = await (await _post(client, secret, body=_tv_status(hearthtube_s=60))).json()
    sam = body["state"]["profiles"][KID]
    assert sam["locked"] is False and "pause" not in sam and "lock" not in sam

    # On its own, it ends when its time is up
    await hass.services.async_call(DOMAIN, "pause", {"minutes": 10, "people": ["person.sam"]}, blocking=True)
    freezer.tick(timedelta(minutes=11))
    body = await (await _post(client, secret, body=_tv_status(hearthtube_s=60))).json()
    assert body["state"]["profiles"][KID]["locked"] is False


async def test_bedtime_says_until_when_and_comes_with_a_heads_up(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator, freezer
) -> None:
    freezer.move_to(dt_util.now().replace(hour=20, minute=30, second=0))
    client, secret = await _household_with_sam(hass, hass_client_no_auth)
    today = dt_util.now().date()
    tomorrow = today + timedelta(days=1)
    bedtime = "binary_sensor.sam_tablet_bedtime_active"
    attributes = {"bedtime_start": f"{today}T21:00:00", "bedtime_end": f"{tomorrow}T07:00:00"}
    hass.states.async_set(bedtime, "off", attributes)
    await _option(hass, "locks", {"person": "person.sam", "entities": [bedtime]})

    body = await (await _post(client, secret, body=_tv_status(hearthtube_s=60))).json()
    upcoming = body["state"]["profiles"][KID]["next_lock"]
    assert upcoming["by"] == bedtime and upcoming["kind"] == "bedtime"
    assert dt_util.parse_datetime(upcoming["at"]).hour == 21

    hass.states.async_set(bedtime, "on", attributes)
    await hass.async_block_till_done()
    body = await (await _post(client, secret, body=_tv_status(hearthtube_s=60))).json()
    sam = body["state"]["profiles"][KID]
    assert sam["lock"]["by"] == [bedtime] and sam["lock"]["kind"] == "bedtime"
    assert dt_util.parse_datetime(sam["lock"]["until"]).hour == 7
    assert "next_lock" not in sam



async def test_family_safety_downtime_is_a_bedtime(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator, freezer
) -> None:
    """Family Safety's Downtime Active sensor mirrors Family Link's bedtime attributes (with an offset)."""
    freezer.move_to(dt_util.now().replace(hour=20, minute=30, second=0))
    client, secret = await _household_with_sam(hass, hass_client_no_auth)
    start = dt_util.now().replace(hour=21, minute=0, second=0, microsecond=0)
    end = start + timedelta(hours=10)
    downtime = "binary_sensor.sam_xbox_downtime_active"
    attributes = {
        "user_id": "123456",
        "platform": "Xbox",
        "downtime_start": start.isoformat(),
        "downtime_end": end.isoformat(),
        "bedtime_start": start.isoformat(),
        "bedtime_end": end.isoformat(),
    }
    hass.states.async_set(downtime, "off", attributes)
    await _option(hass, "locks", {"person": "person.sam", "entities": [downtime]})

    body = await (await _post(client, secret, body=_tv_status(hearthtube_s=60))).json()
    upcoming = body["state"]["profiles"][KID]["next_lock"]
    assert upcoming == {"at": start.isoformat(), "by": downtime, "kind": "bedtime"}

    hass.states.async_set(downtime, "on", attributes)
    await hass.async_block_till_done()
    body = await (await _post(client, secret, body=_tv_status(hearthtube_s=60))).json()
    sam = body["state"]["profiles"][KID]
    assert sam["locked"] is True
    assert sam["lock"]["by"] == [downtime] and sam["lock"]["kind"] == "bedtime"
    assert dt_util.parse_datetime(sam["lock"]["until"]) == end

    # An older Family Safety without the times: still a bedtime, by its name
    hass.states.async_set(downtime, "on", {"user_id": "123456"})
    await hass.async_block_till_done()
    body = await (await _post(client, secret, body=_tv_status(hearthtube_s=60))).json()
    assert body["state"]["profiles"][KID]["lock"]["kind"] == "bedtime"


async def test_a_pause_of_one_group_holds_only_its_apps(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator, monkeypatch
) -> None:
    from pytest_homeassistant_custom_component.common import async_mock_service

    from custom_components.hearth import enforce

    monkeypatch.setattr(enforce, "SETTLE", timedelta(0))

    paused = async_mock_service(hass, "familylink", "pause_app")
    resumed = async_mock_service(hass, "familylink", "resume_app")
    client, secret = await _household_with_sam(hass, hass_client_no_auth)
    hass.states.async_set("sensor.sam_family_link_daily_screen_time", "0", {"unit_of_measurement": "min", "child_id": "42"})
    await _option(hass, "enforce", {"person": "person.sam", "family_link": "sensor.sam_family_link_daily_screen_time"})

    await hass.services.async_call(
        DOMAIN, "pause", {"group": "video", "minutes": 30, "reason": "Homework", "people": ["person.sam"]}, blocking=True
    )
    await hass.async_block_till_done()

    # The TV and phone get it as a group with no time left; the person isn't locked
    body = await (await _post(client, secret, body=_tv_status(hearthtube_s=60))).json()
    sam = body["state"]["profiles"][KID]
    assert sam["locked"] is False and "pause" not in sam
    [group] = [g for g in sam["groups"] if g["id"] == "pause:group:video"]
    assert group["minutes_left"] == 0 and "com.thesiegs.hearthtube" in group["apps"]
    assert group["name"].endswith("(paused: Homework)")
    await hass.async_block_till_done()
    # Family Link pauses the group's apps on the phone
    assert len(paused) == 1 and "com.thesiegs.hearthtube" in paused[0].data["packages"]

    # Explain names it; an allow doesn't lift it
    await hass.services.async_call(
        DOMAIN, "allow", {"people": ["person.sam"], "group": "video"}, blocking=True, return_response=True
    )
    why = await hass.services.async_call(
        DOMAIN, "explain", {"person": "person.sam", "app": "com.thesiegs.hearthtube"}, blocking=True,
        return_response=True,
    )
    assert why["allowed"] is False
    [pause] = [b for b in why["blocked_by"] if b["kind"] == "pause"]
    assert pause["group"] == "video" and pause["reason"] == "Homework"
    other = await hass.services.async_call(
        DOMAIN, "explain", {"person": "person.sam", "group": "games"}, blocking=True, return_response=True
    )
    assert other["allowed"] is True

    # Ending that group's pause lets it go
    await hass.services.async_call(DOMAIN, "pause_end", {"group": "video"}, blocking=True)
    await hass.async_block_till_done()
    body = await (await _post(client, secret, body=_tv_status(hearthtube_s=60))).json()
    assert not [g for g in body["state"]["profiles"][KID]["groups"] if g["id"].startswith("pause:")]
    await hass.async_block_till_done()
    assert len(resumed) == 1


async def test_a_pause_of_one_app_ends_on_its_own(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator, freezer
) -> None:
    client, secret = await _household_with_sam(hass, hass_client_no_auth)
    await hass.services.async_call(
        DOMAIN, "pause", {"app": "com.thesiegs.hearthtube", "minutes": 10}, blocking=True
    )
    body = await (await _post(client, secret, body=_tv_status(hearthtube_s=60))).json()
    [group] = [g for g in body["state"]["profiles"][KID]["groups"] if g["id"].startswith("pause:")]
    assert group["id"] == "pause:app:com.thesiegs.hearthtube" and group["apps"] == ["com.thesiegs.hearthtube"]

    # pause_end with nothing ends the family pause only; the app's pause stays until it's ended by name
    await hass.services.async_call(DOMAIN, "pause", {"minutes": 10}, blocking=True)
    await hass.services.async_call(DOMAIN, "pause_end", {}, blocking=True)
    body = await (await _post(client, secret, body=_tv_status(hearthtube_s=60))).json()
    sam = body["state"]["profiles"][KID]
    assert sam["locked"] is False and [g for g in sam["groups"] if g["id"].startswith("pause:")]
    await hass.services.async_call(DOMAIN, "pause_end", {"app": "com.thesiegs.hearthtube"}, blocking=True)
    body = await (await _post(client, secret, body=_tv_status(hearthtube_s=60))).json()
    assert not [g for g in body["state"]["profiles"][KID]["groups"] if g["id"].startswith("pause:")]

    await hass.services.async_call(DOMAIN, "pause", {"app": "com.thesiegs.hearthtube", "minutes": 10}, blocking=True)
    freezer.tick(timedelta(minutes=11))
    body = await (await _post(client, secret, body=_tv_status(hearthtube_s=60))).json()
    assert not [g for g in body["state"]["profiles"][KID]["groups"] if g["id"].startswith("pause:")]
