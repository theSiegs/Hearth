"""TV profile keys: each TV numbers its profiles itself, so profiles are mapped by household ref or by one TV's key."""

from datetime import timedelta
from unittest.mock import patch

from homeassistant.core import HomeAssistant
from homeassistant.helpers import issue_registry as ir
from homeassistant.util import dt as dt_util
from pytest_homeassistant_custom_component.typing import ClientSessionGenerator

from custom_components.hearth.const import DOMAIN
from custom_components.hearth.profiles import ISSUE_PROFILE_KEYS
from custom_components.hearth.status import clean_status
from test_init import TV_ID, _pair, _post, _set_up

PLAYROOM_ID = "tv-fedcba9876543210"


def _status(profile_id: str, name: str, ref: str | None, seconds: int, others: dict | None = None) -> dict:
    usage = {profile_id: {"profile_name": name, "profile_ref": ref, "seconds": seconds, "apps": {"com.example.game": seconds}}}
    return {
        "screen": "on",
        "state": "idle",
        "profile": name,
        "profile_id": profile_id,
        "profile_ref": ref,
        "kids_profile": True,
        "day": dt_util.now().date().isoformat(),
        "seconds_today": seconds,
        "usage_today": usage,
        "profiles": {profile_id: {"name": name, "ref": ref, "kids": True}, **(others or {})},
    }


async def _people(hass: HomeAssistant) -> None:
    hass.states.async_set("person.sam", "home", {"friendly_name": "Sam"})
    hass.states.async_set("person.robin", "home", {"friendly_name": "Robin"})


async def _pair_two(hass: HomeAssistant, client) -> tuple[str, str]:
    """The Kitchen TV and the Playroom's (pairing again from one address is otherwise held off for a while)."""
    with patch("custom_components.hearth.hub.PAIRING_INTERVAL_PER_ADDRESS", timedelta(0)):
        return await _pair(hass, client), await _pair(hass, client, device_id=PLAYROOM_ID, name="Playroom")


async def _map(hass: HomeAssistant, entry, profiles: dict[str, str]) -> None:
    hass.config_entries.async_update_entry(entry, options={**entry.options, "profiles": profiles})
    await hass.async_block_till_done()


async def test_the_same_number_on_two_tvs_is_two_kids(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator
) -> None:
    """user:10 is Sam on the Kitchen TV and Robin on the Playroom's: each gets their own time and limits."""
    await _people(hass)
    entry = await _set_up(hass)
    client = await hass_client_no_auth()
    kitchen, playroom = await _pair_two(hass, client)
    await _map(hass, entry, {"name:sam": "person.sam", "name:robin": "person.robin"})

    sam_here = _status("user:10", "Sam", "name:sam", 600)
    # On the Playroom TV, Sam is user 12 (not used today) and user 10 is Robin
    robin_there = _status("user:10", "Robin", "name:robin", 1200, {"user:12": {"name": "Sam", "ref": "name:sam", "kids": True}})
    kitchen_doc = await (await _post(client, kitchen, body=sam_here)).json()
    playroom_doc = await (await _post(client, playroom, body=robin_there, device_id=PLAYROOM_ID)).json()
    await hass.async_block_till_done()

    assert hass.states.get("sensor.hearth_sam_screen_time_today").state == "10"
    assert hass.states.get("sensor.hearth_robin_screen_time_today").state == "20"
    # Each TV is answered by its own keys
    kitchen_doc = await (await _post(client, kitchen, body=sam_here)).json()
    playroom_doc = await (await _post(client, playroom, body=robin_there, device_id=PLAYROOM_ID)).json()
    assert kitchen_doc["state"]["profiles"]["user:10"]["person"] == "person.sam"
    assert playroom_doc["state"]["profiles"]["user:10"]["person"] == "person.robin"
    # Sam's YouTube blocks reach the Playroom TV under its own key for Sam, before Sam has used it today
    assert set(playroom_doc["state"]["youtube_blocks"]) == {"user:10", "user:12"}
    assert set(kitchen_doc["state"]["youtube_blocks"]) == {"user:10"}
    # Each TV learns who its mapped profiles are by its own keys, so a notification "for" person.sam finds Sam there
    assert kitchen_doc["state"]["people"] == {"user:10": "person.sam"}
    assert playroom_doc["state"]["people"] == {"user:10": "person.robin", "user:12": "person.sam"}

    # One choice per profile, listing the TVs that have it
    seen = entry.runtime_data.household.seen_profiles()
    assert seen["name:sam"] == "Sam · Kitchen, Playroom"
    assert seen["name:robin"] == "Robin · Playroom"


async def test_old_bare_keys_match_nothing_and_ask_to_pick_again(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator
) -> None:
    await _people(hass)
    entry = await _set_up(hass)
    client = await hass_client_no_auth()
    secret = await _pair(hass, client)
    # A TV with an older Hearth: no refs
    old_tv = _status("user:10", "Sam", None, 600)
    del old_tv["profiles"], old_tv["profile_ref"]
    assert (await _post(client, secret, body=old_tv)).status == 200
    await _map(hass, entry, {"user:10": "person.sam"})

    issue = ir.async_get(hass).async_get_issue(DOMAIN, ISSUE_PROFILE_KEYS)
    assert issue is not None
    assert issue.translation_placeholders == {"keys": "user:10"}
    body = await (await _post(client, secret, body=old_tv)).json()
    assert body["state"]["profiles"] == {}
    seen = entry.runtime_data.household.seen_profiles()
    assert seen["user:10"].startswith("Old mapping")
    assert seen[f"{TV_ID}/user:10"] == "Sam on Kitchen (this TV only)"

    # Picked again for this TV: it counts, and the issue goes
    await _map(hass, entry, {f"{TV_ID}/user:10": "person.sam"})
    assert ir.async_get(hass).async_get_issue(DOMAIN, ISSUE_PROFILE_KEYS) is None
    body = await (await _post(client, secret, body=old_tv)).json()
    await hass.async_block_till_done()
    assert body["state"]["profiles"]["user:10"]["person"] == "person.sam"
    assert hass.states.get("sensor.hearth_sam_screen_time_today").state == "10"


async def test_an_ask_and_a_video_resolve_with_the_tv_they_came_from(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator
) -> None:
    await _people(hass)
    entry = await _set_up(hass)
    client = await hass_client_no_auth()
    kitchen, playroom = await _pair_two(hass, client)
    await _map(hass, entry, {"name:sam": "person.sam"})
    await _post(client, kitchen, body=_status("user:10", "Sam", "name:sam", 60))
    await _post(client, playroom, body=_status("user:10", "Robin", "name:robin", 60), device_id=PLAYROOM_ID)

    household = entry.runtime_data.household
    assert household.profile_person(TV_ID, "user:10") == "person.sam"
    # Robin isn't mapped: the Playroom's user:10 is nobody's, never Sam's
    assert household.profile_person(PLAYROOM_ID, "user:10") is None
    response = await client.post(
        f"/api/hearth/device/{PLAYROOM_ID}/ask", json={"minutes": 15, "profile_id": "user:10"}, headers={"X-Hearth-Secret": playroom}
    )
    assert response.status == 404


def test_a_status_keeps_refs_and_the_profiles_table() -> None:
    status = clean_status(
        {
            "profile_id": "user:10",
            "profile_ref": "name:sam-lee",
            "usage_today": {"user:10": {"profile_name": "Sam Lee", "profile_ref": "name:sam lee!", "seconds": 5}},
            "profiles": {
                "user:10": {"name": "Sam Lee", "ref": "name:sam-lee", "kids": True},
                "user:0:zoë": {"name": "Zoë", "ref": "name:zoë", "kids": "no"},
                "Alex": {"name": "Alex", "ref": "name:alex"},
            },
        }
    )
    assert status["profile_ref"] == "name:sam-lee"
    assert status["usage_today"]["user:10"]["profile_ref"] is None
    assert status["profiles"] == {
        "user:10": {"name": "Sam Lee", "ref": "name:sam-lee", "kids": True},
        "user:0:zoë": {"name": "Zoë", "ref": "name:zoë", "kids": None},
    }
