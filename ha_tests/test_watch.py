"""A kids profile's YouTube: the videos it started (posted by a TV), the parent's blocks (in the state document), the
services and the digest."""

import time

import pytest

from homeassistant.core import HomeAssistant
from homeassistant.exceptions import ServiceValidationError
from pytest_homeassistant_custom_component.common import async_capture_events
from pytest_homeassistant_custom_component.typing import ClientSessionGenerator

from custom_components.hearth.const import DOMAIN
from custom_components.hearth.watch import channel_id_of, clean_word, video_id_of
from test_init import TV_ID, _post
from test_people import KID, _household_with_sam, _tv_status

VIDEO = "aBcDeFgHiJk"
CHANNEL = "UC" + "x" * 22


def _started(t_ms: int, video: str = VIDEO, profile: str = KID, title: str = "A video") -> dict:
    return {"type": "video_started", "profile_id": profile, "t": t_ms, "v": video, "title": title,
            "ch": "A channel", "cid": CHANNEL}


async def _events(client, secret: str | None, events, device_id: str = TV_ID):
    headers = {"X-Hearth-Secret": secret} if secret else {}
    return await client.post(f"/api/hearth/device/{device_id}/events", json={"events": events}, headers=headers)


def test_ids_out_of_links() -> None:
    assert video_id_of("https://www.youtube.com/watch?v=aBcDeFgHiJk&t=10") == VIDEO
    assert video_id_of("https://youtu.be/aBcDeFgHiJk") == VIDEO
    assert video_id_of("https://www.youtube.com/shorts/aBcDeFgHiJk") == VIDEO
    assert video_id_of(VIDEO) == VIDEO
    assert video_id_of("not an id!") is None
    assert channel_id_of(f"https://www.youtube.com/channel/{CHANNEL}") == CHANNEL
    assert channel_id_of(CHANNEL) == CHANNEL
    assert channel_id_of("@somebody") is None
    assert clean_word("  Prank\n") == "prank"
    assert clean_word("") is None


async def test_started_videos_come_up_once(hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator) -> None:
    client, secret = await _household_with_sam(hass, hass_client_no_auth)
    started = async_capture_events(hass, "hearth_video_started")
    now = int(time.time() * 1000)

    response = await _events(client, secret, [_started(now - 60_000, title="First"), _started(now, "zYxWvUtSrQp")])
    assert response.status == 200
    assert (await response.json())["added"] == 2
    # A resend is harmless
    response = await _events(client, secret, [_started(now, "zYxWvUtSrQp")])
    assert (await response.json())["added"] == 0
    await hass.async_block_till_done()

    assert len(started) == 2
    assert started[0].data["person"] == "person.sam"
    assert started[0].data["url"] == f"https://www.youtube.com/watch?v={VIDEO}"
    state = hass.states.get("sensor.hearth_sam_last_video_started")
    assert state.state == "A video"
    assert state.attributes["video_id"] == "zYxWvUtSrQp"
    assert [e["title"] for e in state.attributes["recent"]] == ["A video", "First"]

    log = await hass.services.async_call(
        DOMAIN, "get_watch_log", {"person": "person.sam"}, blocking=True, return_response=True
    )
    assert [e["video_id"] for e in log["entries"]] == ["zYxWvUtSrQp", VIDEO]


async def test_what_isn_t_taken(hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator) -> None:
    client, secret = await _household_with_sam(hass, hass_client_no_auth)
    now = int(time.time() * 1000)
    # Not paired
    assert (await _events(client, None, [_started(now)])).status == 401
    assert (await _events(client, "wrong", [_started(now)])).status == 401
    # Too many at once
    assert (await _events(client, secret, [_started(now - i) for i in range(51)])).status == 400
    # A profile mapped to no one, a bad id, a time from long ago: dropped, but answered (so the TV marks them sent)
    response = await _events(
        client,
        secret,
        [_started(now, profile="user:11"), _started(now, video="bad id!"), _started(1_000), {"type": "other"}],
    )
    assert response.status == 200
    assert (await response.json())["added"] == 0
    await hass.async_block_till_done()
    assert hass.states.get("sensor.hearth_sam_last_video_started").state == "unknown"


async def test_a_user_s_log_finds_its_account_profile(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator
) -> None:
    """Hearth keeps a kids profile's log under its user ("user:10"); the mapping may name its account too."""
    client, secret = await _household_with_sam(hass, hass_client_no_auth)
    entry = hass.config_entries.async_entries(DOMAIN)[0]
    hass.config_entries.async_update_entry(entry, options={**entry.options, "profiles": {f"{KID}:sam": "person.sam"}})
    await hass.async_block_till_done()
    response = await _events(client, secret, [_started(int(time.time() * 1000))])
    assert (await response.json())["added"] == 1


async def test_a_phone_posts_no_events(hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator) -> None:
    client, secret = await _household_with_sam(hass, hass_client_no_auth)
    entry = hass.config_entries.async_entries(DOMAIN)[0]
    devices = {TV_ID: {**entry.data["devices"][TV_ID], "kind": "mobile"}}
    hass.config_entries.async_update_entry(entry, data={**entry.data, "devices": devices})
    await hass.async_block_till_done()
    response = await _events(client, secret, [_started(int(time.time() * 1000))])
    assert response.status == 403


async def test_blocks_go_down_in_the_state_document(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator
) -> None:
    client, secret = await _household_with_sam(hass, hass_client_no_auth)
    body = await (await _post(client, secret, body=_tv_status(hearthtube_s=60))).json()
    assert body["state"]["profiles"][KID]["youtube_blocks"] == {"videos": [], "channels": [], "words": [], "labels": {}}
    version = body["state"]["version"]

    await hass.services.async_call(
        DOMAIN,
        "block_video",
        {"person": "person.sam", "video": f"https://youtu.be/{VIDEO}", "label": "A video"},
        blocking=True,
    )
    await hass.services.async_call(DOMAIN, "block_channel", {"person": "person.sam", "channel": CHANNEL}, blocking=True)
    await hass.services.async_call(DOMAIN, "block_word", {"person": "person.sam", "word": " Prank "}, blocking=True)
    body = await (await _post(client, secret, body=_tv_status(hearthtube_s=60))).json()
    assert body["state"]["profiles"][KID]["youtube_blocks"] == {
        "videos": [VIDEO],
        "channels": [CHANNEL],
        "words": ["prank"],
        "labels": {VIDEO: "A video"},
    }
    assert body["state"]["version"] != version
    # Every mapped profile's, also one not on this TV today
    assert body["state"]["youtube_blocks"][KID]["words"] == ["prank"]

    await hass.services.async_call(DOMAIN, "unblock_word", {"person": "person.sam", "word": "prank"}, blocking=True)
    body = await (await _post(client, secret, body=_tv_status(hearthtube_s=60))).json()
    assert body["state"]["profiles"][KID]["youtube_blocks"]["words"] == []

    await hass.async_block_till_done()
    blocked = hass.states.get("sensor.hearth_sam_last_video_started").attributes["blocked"]
    assert blocked["videos"][0]["label"] == "A video"


async def test_block_refuses_what_isn_t_one(hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator) -> None:
    await _household_with_sam(hass, hass_client_no_auth)
    with pytest.raises(ServiceValidationError):
        await hass.services.async_call(
            DOMAIN, "block_channel", {"person": "person.sam", "channel": "@somebody"}, blocking=True
        )
    hass.states.async_set("person.alex", "home")
    with pytest.raises(ServiceValidationError):
        await hass.services.async_call(DOMAIN, "block_word", {"person": "person.alex", "word": "x"}, blocking=True)


async def test_the_digest(hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator) -> None:
    client, secret = await _household_with_sam(hass, hass_client_no_auth)
    now = int(time.time() * 1000)
    day = 24 * 3600 * 1000
    await _events(
        client,
        secret,
        [_started(now - 10 * day, "oLdOlDoLdOl"), _started(now - day, "zYxWvUtSrQp"), _started(now)],
    )
    await hass.services.async_call(DOMAIN, "block_word", {"person": "person.sam", "word": "prank"}, blocking=True)

    digest = await hass.services.async_call(DOMAIN, "watch_digest", {}, blocking=True, return_response=True)
    sam = digest["people"][0]
    assert sam["person"] == "person.sam"
    assert sam["videos_started"] == 2
    assert sam["per_channel"] == [{"channel": "A channel", "channel_id": CHANNEL, "videos": 2}]
    assert sum(sam["per_day"].values()) == 2
    assert [b["word"] for b in sam["blocked_in_period"]["words"]] == ["prank"]
    assert "2 YouTube videos" in digest["summary"]
    assert "Blocked in that time: 1." in digest["summary"]


async def test_the_log_survives_a_restart(hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator) -> None:
    client, secret = await _household_with_sam(hass, hass_client_no_auth)
    await _events(client, secret, [_started(int(time.time() * 1000))])
    await hass.services.async_call(DOMAIN, "block_word", {"person": "person.sam", "word": "prank"}, blocking=True)
    entry = hass.config_entries.async_entries(DOMAIN)[0]
    assert await hass.config_entries.async_reload(entry.entry_id)
    await hass.async_block_till_done()
    assert hass.states.get("sensor.hearth_sam_last_video_started").state == "A video"
    log = await hass.services.async_call(
        DOMAIN, "get_watch_log", {"person": "person.sam"}, blocking=True, return_response=True
    )
    assert log["blocked"]["words"][0]["word"] == "prank"


async def test_the_weekly_digest_blueprint(hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator) -> None:
    """The blueprint (blueprints/automation/hearth) loads, and run sends the summary."""
    import shutil
    from pathlib import Path

    from homeassistant.setup import async_setup_component

    assert await async_setup_component(hass, "persistent_notification", {})
    client, secret = await _household_with_sam(hass, hass_client_no_auth)
    await _events(client, secret, [_started(int(time.time() * 1000))])
    source = Path(__file__).resolve().parent.parent / "blueprints" / "automation" / "hearth" / "weekly_watch_digest.yaml"
    target = Path(hass.config.path("blueprints", "automation", "hearth"))
    await hass.async_add_executor_job(lambda: (target.mkdir(parents=True, exist_ok=True), shutil.copy(source, target)))
    assert await async_setup_component(
        hass,
        "automation",
        {
            "automation": {
                "id": "digest",
                "alias": "Digest",
                "use_blueprint": {"path": "hearth/weekly_watch_digest.yaml", "input": {}},
            }
        },
    )
    await hass.async_block_till_done()
    assert hass.states.get("automation.digest").state == "on"
    await hass.services.async_call(
        "automation", "trigger", {"entity_id": "automation.digest", "skip_condition": True}, blocking=True
    )
    await hass.async_block_till_done()
    from homeassistant.components import persistent_notification

    shown = persistent_notification._async_get_or_create_notifications(hass)
    assert any("1 YouTube video started" in n["message"] for n in shown.values())
    # Its weekly trigger goes with it
    await hass.services.async_call("automation", "turn_off", {"entity_id": "automation.digest"}, blocking=True)
