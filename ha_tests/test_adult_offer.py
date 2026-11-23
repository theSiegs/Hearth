"""Make this person an adult? Asked of the administrators once, when someone who isn't an adult in Hearth signs in
from a phone (adult_offer.py)."""

import pytest

from homeassistant.auth import models as auth_models
from homeassistant.core import Context, HomeAssistant
from homeassistant.exceptions import ServiceValidationError, Unauthorized
from pytest_homeassistant_custom_component.common import async_capture_events, async_mock_service

from custom_components.hearth import adult_offer
from custom_components.hearth.const import DOMAIN

from test_init import PHONE_ID, TV_ID, _pair, _set_up
from test_phones import _companion_app

SAM = "person.sam"
JORDAN = "person.jordan"
KEY = adult_offer.offer_key(JORDAN)


def _hub(hass: HomeAssistant):
    return hass.config_entries.async_entries(DOMAIN)[0].runtime_data


async def _options(hass: HomeAssistant, **changes) -> None:
    entry = hass.config_entries.async_entries(DOMAIN)[0]
    hass.config_entries.async_update_entry(entry, options={**entry.options, **changes})
    await hass.async_block_till_done()


async def _household(hass: HomeAssistant):
    """Alex (an administrator, with a phone), Sam (a kid), and Jordan: a user of their own with a person and a phone of
    their own, not on Hearth's page yet."""
    hass.states.async_set(SAM, "home", {"friendly_name": "Sam"})
    await _set_up(hass)
    alex = await hass.auth.async_create_user("Alex", group_ids=["system-admin"])
    _companion_app(hass, "Alex Phone", "Android", user_id=alex.id)
    hass.states.async_set("person.alex", "home", {"friendly_name": "Alex", "user_id": alex.id})
    jordan = await hass.auth.async_create_user("Jordan", group_ids=["system-users"])
    hass.states.async_set(JORDAN, "home", {"friendly_name": "Jordan", "user_id": jordan.id})
    _companion_app(hass, "Jordan Phone", "Android", user_id=jordan.id)
    await _options(hass, roles={SAM: "kid", "person.alex": "adult"})
    sent = async_mock_service(hass, "notify", "mobile_app_alex_phone")
    return alex, jordan, sent


async def _ws_as(hass: HomeAssistant, hass_ws_client, user):
    refresh = await hass.auth.async_create_refresh_token(user, "https://hearth.test/")
    return await hass_ws_client(hass, hass.auth.async_create_access_token(refresh))


async def _read(hass: HomeAssistant, ws, n: int = 1, kind: str = "hearth/household") -> dict:
    await ws.send_json({"id": n, "type": kind})
    answer = await ws.receive_json()
    await hass.async_block_till_done()
    return answer


def _offers(sent) -> list:
    """The offers sent (not the messages that take one off a phone)."""
    return [c for c in sent if c.data.get("message") != "clear_notification"]


def _forget_looks(hass: HomeAssistant) -> None:
    """As after a restart: each user is looked at once per run."""
    hass.data.pop(adult_offer._LOOKED_AT, None)


async def _restart(hass: HomeAssistant) -> None:
    entry = hass.config_entries.async_entries(DOMAIN)[0]
    await hass.config_entries.async_reload(entry.entry_id)
    await hass.async_block_till_done()
    _forget_looks(hass)


async def _press(hass: HomeAssistant, sent, title: str, user) -> None:
    [push] = _offers(sent)[-1:]
    action = next(b["action"] for b in push.data["data"]["actions"] if b["title"] == title)
    hass.bus.async_fire("mobile_app_notification_action", {"action": action}, context=Context(user_id=user.id))
    await hass.async_block_till_done()


async def test_a_linked_person_who_isn_t_a_kid_is_offered_once(hass: HomeAssistant, hass_ws_client) -> None:
    alex, jordan, sent = await _household(hass)
    offered = async_capture_events(hass, adult_offer.EVENT_ADULT_OFFERED)
    ws = await _ws_as(hass, hass_ws_client, jordan)
    answer = await _read(hass, ws)
    assert not answer["success"] and answer["error"]["code"] == "unauthorized"

    [push] = _offers(sent)
    assert push.data["title"] == "Make Jordan an adult?"
    assert push.data["message"] == (
        "Jordan (Home Assistant login Jordan) signed in from Jordan Phone. Make them an adult in Hearth? Adults see "
        "the kids' time and can give more."
    )
    assert [b["title"] for b in push.data["data"]["actions"]] == ["Make adult", "Not now"]
    # A tap opens Hearth's page by a relative path, so it works away from home too
    assert push.data["data"]["clickAction"] == push.data["data"]["url"] == "/hearth"
    assert [e.data for e in offered] == [{"person": JORDAN}]
    # On Hearth's page too
    admin_ws = await _ws_as(hass, hass_ws_client, alex)
    config = await _read(hass, admin_ws, kind="hearth/config")
    assert config["result"]["adult_offers"] == [
        {"person": JORDAN, "name": "Jordan", "login": "Jordan", "from": "Jordan Phone"}
    ]

    # Every poll after, the subscription, and Glint's own reads: never asked again
    for n, kind in enumerate(("hearth/household", "hearth/household/subscribe", "hearth/glint/phones"), start=2):
        assert not (await _read(hass, ws, n, kind))["success"]
    # Nor after a restart, nor through another way in
    await _restart(hass)
    ws = await _ws_as(hass, hass_ws_client, jordan)
    assert not (await _read(hass, ws, 9, "hearth/glint/phones"))["success"]
    assert len(_offers(sent)) == 1 and len(offered) == 1


async def test_glint_s_own_read_asks_too(hass: HomeAssistant, hass_ws_client) -> None:
    _alex, jordan, sent = await _household(hass)
    ws = await _ws_as(hass, hass_ws_client, jordan)
    assert not (await _read(hass, ws, kind="hearth/glint/phones"))["success"]
    assert len(_offers(sent)) == 1


async def test_make_adult_sets_the_role_and_the_next_read_works(hass: HomeAssistant, hass_ws_client) -> None:
    alex, jordan, sent = await _household(hass)
    ws = await _ws_as(hass, hass_ws_client, jordan)
    await _read(hass, ws)
    await _press(hass, sent, "Make adult", alex)

    entry = hass.config_entries.async_entries(DOMAIN)[0]
    assert entry.options["roles"] == {SAM: "kid", "person.alex": "adult", JORDAN: "adult"}
    assert _hub(hass).adult_offers.people[JORDAN]["state"] == adult_offer.MADE
    assert _hub(hass).adult_offers.open_offers() == []
    assert (await _read(hass, ws, 2))["success"]


async def test_an_open_offer_s_buttons_work_after_a_restart(hass: HomeAssistant, hass_ws_client) -> None:
    alex, jordan, sent = await _household(hass)
    ws = await _ws_as(hass, hass_ws_client, jordan)
    await _read(hass, ws)
    await _restart(hass)
    assert _hub(hass).attention.item(KEY) is not None
    await _press(hass, sent, "Make adult", alex)
    assert hass.config_entries.async_entries(DOMAIN)[0].options["roles"][JORDAN] == "adult"


async def test_not_now_never_asks_again(hass: HomeAssistant, hass_ws_client) -> None:
    alex, jordan, sent = await _household(hass)
    ws = await _ws_as(hass, hass_ws_client, jordan)
    await _read(hass, ws)
    await _press(hass, sent, "Not now", alex)
    assert JORDAN not in hass.config_entries.async_entries(DOMAIN)[0].options["roles"]
    assert _hub(hass).adult_offers.people[JORDAN]["state"] == adult_offer.DECLINED
    assert _hub(hass).attention.item(KEY) is None

    await _restart(hass)
    ws = await _ws_as(hass, hass_ws_client, jordan)
    assert not (await _read(hass, ws, 2))["success"]
    assert len(_offers(sent)) == 1
    # Set by hand on Hearth's page later: still works
    await _options(hass, roles={**hass.config_entries.async_entries(DOMAIN)[0].options["roles"], JORDAN: "adult"})
    assert (await _read(hass, ws, 3))["success"]


async def test_set_by_hand_meanwhile_the_button_does_nothing(hass: HomeAssistant, hass_ws_client) -> None:
    alex, jordan, sent = await _household(hass)
    ws = await _ws_as(hass, hass_ws_client, jordan)
    await _read(hass, ws)
    await _options(hass, roles={SAM: "kid", "person.alex": "adult", JORDAN: "kid"})
    # The reload took the open offer off: settled, never asked again
    assert _hub(hass).adult_offers.people[JORDAN]["state"] == adult_offer.SETTLED
    with pytest.raises(ServiceValidationError):
        await hass.services.async_call(
            DOMAIN, "adult_offer_answer", {"person": JORDAN, "answer": "adult"}, blocking=True,
            context=Context(user_id=alex.id),
        )
    assert hass.config_entries.async_entries(DOMAIN)[0].options["roles"][JORDAN] == "kid"


async def test_only_an_administrator_answers(hass: HomeAssistant, hass_ws_client) -> None:
    _alex, jordan, _sent = await _household(hass)
    casey = await hass.auth.async_create_user("Casey", group_ids=["system-users"])
    hass.states.async_set("person.casey", "home", {"friendly_name": "Casey", "user_id": casey.id})
    # Casey is an adult in Hearth, but not an administrator
    await _options(hass, roles={SAM: "kid", "person.alex": "adult", "person.casey": "adult"})
    ws = await _ws_as(hass, hass_ws_client, jordan)
    await _read(hass, ws)
    data = {"person": JORDAN, "answer": "adult"}
    for context in (Context(), Context(user_id=jordan.id), Context(user_id=casey.id)):
        with pytest.raises(Unauthorized):
            await hass.services.async_call(DOMAIN, "adult_offer_answer", data, blocking=True, context=context)
    assert JORDAN not in hass.config_entries.async_entries(DOMAIN)[0].options["roles"]
    # Casey's phone button is ignored too (the item is the administrators')
    item = _hub(hass).attention.item(KEY)
    assert not casey.is_admin and item is not None and item.audience == "admins"


_KID_SIGNALS = {
    "role kid": {"roles": {SAM: "kid", JORDAN: "kid"}},
    "role adult already": {"roles": {SAM: "kid", JORDAN: "adult"}},
    "family link": {"enforce": [{"kind": "family_link", "person": JORDAN, "entity_id": "sensor.jordan_fl"}]},
    "family safety": {"enforce": [{"kind": "family_safety", "person": JORDAN, "entity_id": "sensor.jordan_fs"}]},
    "nintendo": {"enforce": [{"kind": "nintendo", "person": JORDAN, "entity_id": "sensor.jordan_switch"}]},
    "source": {"sources": [{"id": "jordan_xbox", "entity_id": "sensor.jordan_xbox", "person": JORDAN}]},
    "lock": {"locks": [{"entity_id": "binary_sensor.jordan_bedtime", "person": JORDAN}]},
}


@pytest.mark.parametrize("options", list(_KID_SIGNALS.values()), ids=list(_KID_SIGNALS))
async def test_never_for_someone_with_a_kid_s_signal(hass: HomeAssistant, hass_ws_client, options) -> None:
    _alex, jordan, sent = await _household(hass)
    await _options(hass, **options)
    hub = _hub(hass)
    assert adult_offer.kid_signals(hub, JORDAN) or JORDAN in hub.entry.options["roles"]
    ws = await _ws_as(hass, hass_ws_client, jordan)
    await _read(hass, ws)
    assert _offers(sent) == [] and JORDAN not in _hub(hass).adult_offers.people


@pytest.mark.parametrize("what", ["budget", "bonus", "schedule"])
async def test_never_for_someone_with_limits(hass: HomeAssistant, hass_ws_client, what) -> None:
    _alex, jordan, sent = await _household(hass)
    household = _hub(hass).household
    if what == "budget":
        household.limits.data.budgets[JORDAN] = {"all": {"school": 60}}
    elif what == "bonus":
        household.limits.data.bonus[JORDAN] = {"all": 15}
    else:
        household.week.data.people[JORDAN] = {}
    assert adult_offer.kid_signals(_hub(hass), JORDAN)
    ws = await _ws_as(hass, hass_ws_client, jordan)
    await _read(hass, ws)
    assert _offers(sent) == []


async def test_never_for_an_administrator_or_users_without_one_person(hass: HomeAssistant, hass_ws_client) -> None:
    alex, jordan, sent = await _household(hass)
    offers = _hub(hass).adult_offers
    # An administrator reads anyway; never offered
    offers.refused(alex)
    # No person
    nobody = await hass.auth.async_create_user("Guest", group_ids=["system-users"])
    ws = await _ws_as(hass, hass_ws_client, nobody)
    await _read(hass, ws)
    # Two persons for one user
    hass.states.async_set("person.jordan_2", "home", {"friendly_name": "Jordan Two", "user_id": jordan.id})
    ws = await _ws_as(hass, hass_ws_client, jordan)
    await _read(hass, ws, 2)
    # A user that isn't active, or one Home Assistant made itself
    inactive = await hass.auth.async_create_user("Riley", group_ids=["system-users"])
    await hass.auth.async_deactivate_user(inactive)
    hass.states.async_set("person.riley", "home", {"friendly_name": "Riley", "user_id": inactive.id})
    offers.refused(inactive)
    system = await hass.auth.async_create_system_user("Helper")
    hass.states.async_set("person.helper", "home", {"friendly_name": "Helper", "user_id": system.id})
    offers.refused(system)
    await hass.async_block_till_done()
    assert _offers(sent) == [] and offers.people == {}


async def test_each_user_is_looked_at_once_a_run(hass: HomeAssistant, hass_ws_client) -> None:
    _alex, jordan, sent = await _household(hass)
    # Looked at while two persons pointed at them: not offered, and not looked at again this run
    hass.states.async_set("person.jordan_2", "home", {"friendly_name": "Jordan Two", "user_id": jordan.id})
    ws = await _ws_as(hass, hass_ws_client, jordan)
    await _read(hass, ws)
    hass.states.async_remove("person.jordan_2")
    await _read(hass, ws, 2)
    assert _offers(sent) == []
    # Next run, it holds
    _forget_looks(hass)
    await _read(hass, ws, 3)
    assert len(_offers(sent)) == 1


# A device's login (the panels' login on a wall tablet, or a TV's) is never offered, and only someone with a phone of
# their own is


async def _long_lived(hass: HomeAssistant, user, name: str):
    return await hass.auth.async_create_refresh_token(
        user, client_name=name, token_type=auth_models.TOKEN_TYPE_LONG_LIVED_ACCESS_TOKEN
    )


async def test_a_panel_s_login_is_never_offered(hass: HomeAssistant, hass_ws_client) -> None:
    _alex, jordan, sent = await _household(hass)
    hub = _hub(hass)
    # The panels' login: a wall tablet's subscription signed in as Jordan's user (kept with the panel)
    hub.glint_panel.panels["tablet-1"] = {"name": "Hall panel", "user_id": jordan.id}
    assert adult_offer.device_login(hass, hub, jordan) == "Hall panel"
    ws = await _ws_as(hass, hass_ws_client, jordan)
    assert not (await _read(hass, ws))["success"]
    assert _offers(sent) == [] and JORDAN not in hub.adult_offers.people


async def test_a_read_on_a_panel_s_token_is_never_offered(hass: HomeAssistant, hass_ws_client) -> None:
    """No panel record names the user, but the read came with the token a tablet saying hello signed in with."""
    _alex, jordan, sent = await _household(hass)
    hub = _hub(hass)
    hub.glint_panel.hellos["tablet-2"] = {"name": "Kitchen panel", "signed_in_as": {"user": "x", "token": "Panels"}}
    token = await _long_lived(hass, jordan, "Panels")
    ws = await hass_ws_client(hass, hass.auth.async_create_access_token(token))
    assert not (await _read(hass, ws))["success"]
    assert _offers(sent) == [] and JORDAN not in hub.adult_offers.people


async def test_a_paired_tv_s_login_is_never_offered(hass: HomeAssistant, hass_ws_client, hass_client_no_auth) -> None:
    _alex, jordan, sent = await _household(hass)
    await _pair(hass, await hass_client_no_auth(), TV_ID, "tv", "Den TV")
    hub = _hub(hass)
    # The TV signs in with a token of Jordan's user named as the paired TV is
    await _long_lived(hass, jordan, "Den TV")
    assert adult_offer.device_login(hass, hub, jordan) == "Den TV"
    ws = await _ws_as(hass, hass_ws_client, jordan)
    assert not (await _read(hass, ws))["success"]
    # (the pairing's own notice went out; no offer did)
    assert not [c for c in _offers(sent) if c.data.get("title", "").startswith("Make ")]
    assert JORDAN not in hub.adult_offers.people


async def test_a_token_a_hearth_tv_made_is_a_device_s_login(hass: HomeAssistant) -> None:
    _alex, jordan, _sent = await _household(hass)
    await _long_lived(hass, jordan, "Hearth household: Playroom TV 2026-11-20 18:05")
    hub = _hub(hass)
    assert adult_offer.device_login(hass, hub, jordan) == "Playroom TV"
    assert adult_offer.qualifying_person(hass, hub, jordan) is None


async def test_a_paired_phone_is_a_person_s_own(hass: HomeAssistant, hass_client_no_auth) -> None:
    """A phone paired to Hearth signs in as its person: a token named as it doesn't make it a device's login."""
    _alex, jordan, _sent = await _household(hass)
    await _pair(hass, await hass_client_no_auth(), PHONE_ID, "mobile", "Jordan Phone")
    await _long_lived(hass, jordan, "Jordan Phone")
    hub = _hub(hass)
    assert adult_offer.device_login(hass, hub, jordan) is None
    assert adult_offer.qualifying_person(hass, hub, jordan) == JORDAN


async def test_never_for_someone_with_no_phone_of_their_own(hass: HomeAssistant, hass_ws_client) -> None:
    _alex, _jordan, sent = await _household(hass)
    # Riley has a person but no companion app registered by their user (Alex's and Jordan's don't count)
    riley = await hass.auth.async_create_user("Riley", group_ids=["system-users"])
    hass.states.async_set("person.riley", "home", {"friendly_name": "Riley", "user_id": riley.id})
    ws = await _ws_as(hass, hass_ws_client, riley)
    assert not (await _read(hass, ws))["success"]
    assert _offers(sent) == [] and "person.riley" not in _hub(hass).adult_offers.people
    # With a phone of their own they are (looked at again next run)
    _companion_app(hass, "Riley Phone", "iOS", user_id=riley.id)
    _forget_looks(hass)
    assert not (await _read(hass, ws, 2))["success"]
    assert len(_offers(sent)) == 1


async def test_the_notice_names_the_login_and_the_device(hass: HomeAssistant, hass_ws_client) -> None:
    _alex, jordan, sent = await _household(hass)
    # Jordan signs in with a username of their own, on a token with a name
    await hass.auth.async_link_user(
        jordan,
        auth_models.Credentials(auth_provider_type="homeassistant", auth_provider_id=None, data={"username": "jordan.r"}),
    )
    token = await _long_lived(hass, jordan, "Jordan's tablet")
    ws = await hass_ws_client(hass, hass.auth.async_create_access_token(token))
    await _read(hass, ws)
    [push] = _offers(sent)
    assert push.data["message"].startswith(
        "Jordan (Home Assistant login jordan.r) signed in from Jordan's tablet. Make them an adult in Hearth?"
    )
    # After a restart the offer comes back with the same words
    await _restart(hass)
    assert _hub(hass).attention.item(KEY).text == push.data["message"]


async def test_the_answer_refuses_someone_who_no_longer_qualifies(hass: HomeAssistant, hass_ws_client) -> None:
    alex, jordan, sent = await _household(hass)
    ws = await _ws_as(hass, hass_ws_client, jordan)
    await _read(hass, ws)
    assert len(_offers(sent)) == 1
    data = {"person": JORDAN, "answer": "adult"}
    # Meanwhile a wall tablet starts signing in as Jordan's user: Make adult is refused, the role isn't set
    panels = _hub(hass).glint_panel.panels
    panels["tablet-1"] = {"name": "Hall panel", "user_id": jordan.id}
    with pytest.raises(ServiceValidationError):
        await hass.services.async_call(DOMAIN, "adult_offer_answer", data, blocking=True, context=Context(user_id=alex.id))
    del panels["tablet-1"]
    # So is someone with no phone of their own any more (their phone now registered by another user)
    for entry in hass.config_entries.async_entries("mobile_app"):
        if entry.data.get("user_id") == jordan.id:
            hass.config_entries.async_update_entry(entry, data={**entry.data, "user_id": alex.id})
    with pytest.raises(ServiceValidationError):
        await hass.services.async_call(DOMAIN, "adult_offer_answer", data, blocking=True, context=Context(user_id=alex.id))
    assert JORDAN not in hass.config_entries.async_entries(DOMAIN)[0].options["roles"]
