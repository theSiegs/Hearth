"""A paired TV without a token of its own has the integration ask an adult's phones to allow a switch into their Google
TV profile, and reads the answer back."""

from datetime import timedelta

from homeassistant.core import Context, HomeAssistant
from homeassistant.util import dt as dt_util
from pytest_homeassistant_custom_component.common import async_capture_events, async_fire_time_changed
from pytest_homeassistant_custom_component.typing import ClientSessionGenerator

from custom_components.hearth import switch_approval
from custom_components.hearth.const import DOMAIN
from test_init import TV_ID, _post
from test_people import _tv_status
from test_phones import _options, _two_adults

URL = f"/api/hearth/device/{TV_ID}/switch_approval"


async def _ready(hass: HomeAssistant, hass_client_no_auth):
    """Alex (an adult with an Android phone) is the TV's "Owner" profile (user:0); Sam (user:10) is a kid."""
    client, secret, alex, jordan = await _two_adults(hass, hass_client_no_auth)
    entry = hass.config_entries.async_entries(DOMAIN)[0]
    await _options(hass, profiles={**entry.options.get("profiles", {}), "name:owner": "person.alex"})
    assert (await _post(client, secret, body=_tv_status(hearthtube_s=60))).status == 200
    return client, {"X-Hearth-Secret": secret}, alex, jordan


async def _answer(hass: HomeAssistant, action: str, user_id: str | None = None) -> None:
    hass.bus.async_fire("mobile_app_notification_action", {"action": action}, context=Context(user_id=user_id))
    await hass.async_block_till_done()


async def test_the_adult_s_phone_allows_and_the_tv_reads_it(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator, hass_admin_user
) -> None:
    client, headers, alex, jordan = await _ready(hass, hass_client_no_auth)
    answered = async_capture_events(hass, switch_approval.EVENT_SWITCH_APPROVAL)

    started = await client.post(URL, json={"profile_id": "user:0"}, headers=headers)
    assert started.status == 200
    body = await started.json()
    request_id = body["request"]["id"]
    assert body["request"]["status"] == "pending" and body["phones"] == 1 and len(request_id) == 32
    # Only Alex's own phone
    assert len(alex) == 1 and not jordan
    actions = [a["action"] for a in alex[0].data["data"]["actions"]]
    assert actions == [f"HEARTH_SWITCH_ALLOW_{request_id}", f"HEARTH_SWITCH_DENY_{request_id}"]
    assert alex[0].data["data"]["tag"] == f"hearth-switch-{request_id}"

    # Still waiting: the TV's read says so after its timeout
    read = await (await client.get(f"{URL}/{request_id}?timeout=0", headers=headers)).json()
    assert read["request"]["status"] == "pending"

    # A kid (or anyone who isn't an adult) can't answer, even firing the same event from their own app; and Home
    # Assistant's own list, which every user sees, never shows the request's id
    from homeassistant.components import persistent_notification

    notices = persistent_notification._async_get_or_create_notifications(hass)
    assert notices and all(request_id not in n for n in notices)
    kid = await hass.auth.async_create_user("Sam")
    await _answer(hass, f"HEARTH_SWITCH_ALLOW_{request_id}", kid.id)
    await _answer(hass, f"HEARTH_SWITCH_ALLOW_{request_id}")
    read = await (await client.get(f"{URL}/{request_id}?timeout=0", headers=headers)).json()
    assert read["request"]["status"] == "pending"

    # An adult answers; who did is told
    await _answer(hass, f"HEARTH_SWITCH_ALLOW_{request_id}", hass_admin_user.id)
    read = await (await client.get(f"{URL}/{request_id}?timeout=5", headers=headers)).json()
    assert read["request"]["status"] == "allowed"
    assert alex[-1].data == {"message": "clear_notification", "data": {"tag": f"hearth-switch-{request_id}"}}
    assert [(e.data["answer"], e.data["person"], e.data["user_id"]) for e in answered] == [
        ("allowed", "person.alex", hass_admin_user.id)
    ]

    # Used once: a later Deny changes nothing
    await _answer(hass, f"HEARTH_SWITCH_DENY_{request_id}")
    read = await (await client.get(f"{URL}/{request_id}", headers=headers)).json()
    assert read["request"]["status"] == "allowed" and len(answered) == 1


async def test_deny_withdraw_and_expiry(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator, hass_admin_user
) -> None:
    client, headers, alex, _ = await _ready(hass, hass_client_no_auth)

    first = (await (await client.post(URL, json={"profile_id": "user:0"}, headers=headers)).json())["request"]["id"]
    await _answer(hass, f"HEARTH_SWITCH_DENY_{first}", hass_admin_user.id)
    assert (await (await client.get(f"{URL}/{first}", headers=headers)).json())["request"]["status"] == "denied"

    # Withdrawn by the TV (the remote is in use): off the phone
    second = (await (await client.post(URL, json={"profile_id": "user:0"}, headers=headers)).json())["request"]["id"]
    gone = await client.delete(f"{URL}/{second}", headers=headers)
    assert (await gone.json())["request"]["status"] == "withdrawn"
    assert alex[-1].data["data"] == {"tag": f"hearth-switch-{second}"}
    await _answer(hass, f"HEARTH_SWITCH_ALLOW_{second}", hass_admin_user.id)
    assert (await (await client.get(f"{URL}/{second}", headers=headers)).json())["request"]["status"] == "withdrawn"

    # A newer request from the TV replaces its waiting one; no answer in time: expired
    third = (await (await client.post(URL, json={"profile_id": "user:0"}, headers=headers)).json())["request"]["id"]
    fourth = (await (await client.post(URL, json={"profile_id": "user:0"}, headers=headers)).json())["request"]["id"]
    assert (await (await client.get(f"{URL}/{third}", headers=headers)).json())["request"]["status"] == "withdrawn"
    async_fire_time_changed(hass, dt_util.utcnow() + timedelta(seconds=switch_approval.ANSWER_SECONDS + 1))
    await hass.async_block_till_done()
    assert (await (await client.get(f"{URL}/{fourth}", headers=headers)).json())["request"]["status"] == "expired"
    # And it's let go a while later
    async_fire_time_changed(
        hass,
        dt_util.utcnow() + timedelta(seconds=switch_approval.ANSWER_SECONDS + switch_approval.KEEP_SECONDS + 2),
    )
    await hass.async_block_till_done()
    assert (await client.get(f"{URL}/{fourth}", headers=headers)).status == 404


async def test_the_phone_chosen_on_the_tvs_wins(hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator) -> None:
    client, headers, alex, jordan = await _ready(hass, hass_client_no_auth)
    body = await (
        await client.post(URL, json={"profile_id": "user:0", "phone": "mobile_app_jordan_iphone"}, headers=headers)
    ).json()
    assert body["phones"] == 1 and len(jordan) == 1 and not alex
    # One Home Assistant doesn't have: the person's own phones
    body = await (
        await client.post(URL, json={"profile_id": "user:0", "phone": "mobile_app_gone_phone"}, headers=headers)
    ).json()
    assert body["phones"] == 1 and len(alex) == 1


async def test_only_the_paired_tv_and_only_for_an_adult(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator
) -> None:
    client, headers, _, _ = await _ready(hass, hass_client_no_auth)
    assert (await client.post(URL, json={"profile_id": "user:0"}, headers={"X-Hearth-Secret": "nope"})).status == 401
    # A kid's profile, an unmapped one, a bad phone
    kid = await client.post(URL, json={"profile_id": "user:10"}, headers=headers)
    assert kid.status == 403 and (await kid.json())["error"] == "not_adult"
    nobody = await client.post(URL, json={"profile_id": "user:99"}, headers=headers)
    assert nobody.status == 404 and (await nobody.json())["error"] == "no_person"
    assert (await client.post(URL, json={"profile_id": "user:0", "phone": "notify"}, headers=headers)).status == 400
    assert (await client.post(URL, json={}, headers=headers)).status == 400
    # No such request (or a guess): gone
    assert (await client.get(f"{URL}/{'0' * 32}", headers=headers)).status == 404
    assert (await client.delete(f"{URL}/not-an-id", headers=headers)).status == 404

    request_id = (await (await client.post(URL, json={"profile_id": "user:0"}, headers=headers)).json())["request"]["id"]
    # Another device's secret can't read it
    assert (await client.get(f"{URL}/{request_id}", headers={"X-Hearth-Secret": "nope"})).status == 401


def test_only_its_own_action_ids_are_read() -> None:
    rid = "ab" * 16
    assert switch_approval.parse_action(f"HEARTH_SWITCH_ALLOW_{rid}") == (rid, True)
    assert switch_approval.parse_action(f"HEARTH_SWITCH_DENY_{rid}") == (rid, False)
    assert switch_approval.parse_action("HEARTH_SWITCH_ALLOW_short") is None
    assert switch_approval.parse_action(f"HEARTH_APPROVE_ALLOW_{rid}") is None
    assert switch_approval.parse_action("") is None
