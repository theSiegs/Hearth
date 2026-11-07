"""Contract 2 of the household summary: each person's headline, lines and actions, the household's, the
hearth.answer_request service, and who may call Hearth's services."""

from datetime import datetime, timedelta
import json
import os

import pytest

from homeassistant.core import Context, HomeAssistant
from homeassistant.exceptions import ServiceValidationError, Unauthorized
from homeassistant.util import dt as dt_util
from pytest_homeassistant_custom_component.typing import ClientSessionGenerator

from custom_components.hearth.const import DOMAIN
from custom_components.hearth.glance import household_glance, news_key, person_glance
from test_init import NONCE, PHONE_ID, _post
from test_people import _household_with_sam, _today
from test_sources import _option



def _at(hour: int, minute: int) -> datetime:
    """A fixed local time (Home Assistant's time zone, as set when the test runs)."""
    return datetime(2026, 11, 6, hour, minute, tzinfo=dt_util.get_default_time_zone())


def _person(**groups_left) -> dict:
    """A kid in the summary's shape, with groups {id: minutes_left} (used: whatever)."""
    return {
        "id": "person.alex",
        "name": "Alex",
        "kind": "kid",
        "groups": [
            {"id": gid, "name": "All screen time" if gid == "all" else gid.title(), "used_minutes": 30,
             "minutes_left": left, "budget": 60, "bonus": 0}
            for gid, left in groups_left.items()
        ],
        "playing": [],
    }


def _glance(person, asks=(), allows=(), offs=(), now=None):
    return person_glance(person, list(asks), list(allows), list(offs), now or _at(17, 40))


def test_the_key_names_the_news_not_the_minutes() -> None:
    assert news_key("low", "youtube") == "low:youtube"
    assert news_key("clear") == "clear"
    calm = [_glance(_person(all=90, youtube=m))["headline"] for m in (25, 24, 11)]
    assert [h["text"] for h in calm] == ["youtube · 25 left", "youtube · 24 left", "youtube · 11 left"]
    assert {h["key"] for h in calm} == {"left:youtube"} and {h["level"] for h in calm} == {"calm"}
    low = [_glance(_person(all=90, youtube=m))["headline"] for m in (9, 3)]
    assert {h["key"] for h in low} == {"low:youtube"} and {h["level"] for h in low} == {"notice"}
    out = _glance(_person(all=90, youtube=0))["headline"]
    assert out == {"text": "youtube · out", "level": "notice", "key": "out:youtube"}
    assert _glance(_person(all=0, youtube=0))["headline"] == {"text": "out of time", "level": "urgent", "key": "out:all"}
    assert _glance(_person())["headline"] == {"text": "all clear", "level": "calm", "key": "clear"}


def test_the_headline_follows_hearth_s_order() -> None:
    NOW = _at(17, 40)
    ask = {"type": "more_time", "id": "abc", "person": "person.alex", "person_name": "Alex", "minutes": 30,
           "group": "youtube", "offered": False}
    person = {**_person(all=50, youtube=5), "pause": {"until": (NOW + timedelta(minutes=50)).isoformat(), "reason": "Dinner"}}
    glance = _glance(person, asks=[ask])
    assert glance["headline"] == {"text": "asks for 30 more · youtube", "level": "urgent", "key": "ask:abc"}
    lines = [line["key"] for line in glance["lines"]]
    assert lines[:2] == [f"pause:{person['pause']['until']}", "low:youtube"]
    assert glance["lines"][0]["text"] == "paused · dinner till 6:30"
    # The pause's key holds as time passes; with the ask answered, the pause leads
    later = _glance(person, now=NOW + timedelta(minutes=5))
    assert later["headline"]["key"] == f"pause:{person['pause']['until']}"

    # A bedtime soon, an allow, School time off: notices, in that order, after a low group
    soon = {**_person(all=50), "next_lock": {"at": (NOW + timedelta(minutes=12)).isoformat(), "by": "x", "kind": "bedtime"}}
    allow = {"id": "a1", "app": None, "group": "games", "until": (NOW + timedelta(hours=1)).isoformat(), "reason": ""}
    off = {"id": "o1", "date": NOW.date().isoformat()}
    glance = _glance(soon, allows=[allow], offs=[off])
    assert glance["headline"]["text"] == "bedtime in 12 min" and glance["headline"]["level"] == "notice"
    assert [line["key"] for line in glance["lines"]][:2] == ["allow:a1", "school_off:o1"]
    # Twenty minutes off it's only a line
    early = _glance({**soon, "next_lock": {**soon["next_lock"], "at": (NOW + timedelta(minutes=20)).isoformat()}})
    assert early["headline"]["key"] == "left:all"
    assert early["lines"][-1]["text"] == "bedtime at 6:00"


def test_actions_are_what_applies_now() -> None:
    NOW = _at(17, 40)
    ask = {"type": "more_time", "id": "abc", "person": "person.alex", "person_name": "Alex", "minutes": 30,
           "group": "youtube", "offered": False}
    actions = {a["id"]: a for a in _glance(_person(all=40, youtube=0), asks=[ask])["actions"]}
    assert actions["ask_yes:abc"]["data"] == {"request_id": "abc", "minutes": 30}
    assert actions["ask_yes:abc"]["service"] == "hearth.answer_request" and actions["ask_yes:abc"]["primary"]
    assert actions["ask_no:abc"]["data"] == {"request_id": "abc", "deny": True}
    assert actions["bonus:youtube"]["data"] == {"person": "person.alex", "minutes": 15, "group": "youtube"}
    assert actions["bonus:youtube"]["primary"] is True and "primary" not in actions["bonus:all"]
    assert actions["pause"]["data"] == {"people": ["person.alex"], "minutes": 30}
    assert actions["pause"]["confirm"] == "pause alex for 30 min?"
    assert "pause_end" not in actions

    paused = {**_person(), "pause": {"until": NOW.isoformat(), "reason": ""}}
    allow = {"id": "a1", "app": "com.example.app", "group": None, "until": NOW.isoformat(), "reason": ""}
    actions = {a["id"]: a for a in _glance(paused, allows=[allow])["actions"]}
    assert set(actions) == {"pause_end", "allow_end:a1"}
    assert actions["pause_end"]["data"] == {"people": ["person.alex"]}
    assert actions["allow_end:a1"]["data"] == {"people": ["person.alex"], "app": "com.example.app"}

    household = household_glance([paused, {**_person(), "id": "person.sam", "name": "Sam"}], [])
    assert household["headline"]["text"] == "alex paused till 5:40"
    assert {a["id"]: a["data"] for a in household["actions"]} == {"pause_end": {}, "pause_all": {"minutes": 30}}


async def _kids_alex_and_sam(hass: HomeAssistant, hass_client_no_auth, freezer):
    """Sam on the TV (15 minutes today), Alex on a phone (25 minutes of video), both kids with budgets, Sam's bedtime at
    9 pm."""
    hass.states.async_set("person.alex", "home", {"friendly_name": "Alex"})
    client, _secret = await _household_with_sam(hass, hass_client_no_auth)
    # One address may ask to pair every 10 seconds
    freezer.tick(timedelta(seconds=11))
    response = await client.post(
        "/api/hearth/pair", json={"device_id": PHONE_ID, "kind": "mobile", "name": "Alex's phone", "nonce": NONCE}
    )
    pairing_id = (await response.json())["pairing_id"]
    await hass.async_block_till_done()
    flow = hass.config_entries.flow.async_progress_by_handler(DOMAIN)[0]
    await hass.config_entries.flow.async_configure(flow["flow_id"], {"person": "person.alex"})
    await hass.async_block_till_done()
    phone = (await (await client.get(f"/api/hearth/pair/{pairing_id}", headers={"X-Hearth-Nonce": NONCE})).json())["secret"]
    status = {"screen": "on", "day": _today(), "seconds_today": 1500,
              "app_seconds_today": {"com.thesiegs.hearthtube": 1500}}
    assert (await _post(client, phone, body=status, device_id=PHONE_ID)).status == 200

    bedtime = "binary_sensor.sam_tablet_bedtime_active"
    today = dt_util.now().date()
    hass.states.async_set(bedtime, "off", {"bedtime_start": f"{today}T21:00:00", "bedtime_end": f"{today + timedelta(days=1)}T07:00:00"})
    await _option(hass, "locks", {"person": "person.sam", "entities": [bedtime]})
    entry = hass.config_entries.async_entries(DOMAIN)[0]
    hass.config_entries.async_update_entry(
        entry, options={**entry.options, "roles": {"person.alex": "kid", "person.sam": "kid"}}
    )
    await hass.async_block_till_done()
    for person, group, minutes in (
        ("person.alex", "all", 120), ("person.alex", "video", 30), ("person.sam", "all", 120), ("person.sam", "video", 60)
    ):
        await hass.services.async_call(
            DOMAIN, "set_budget", {"person": person, "group": group, "minutes": minutes}, blocking=True
        )
    return client, phone


async def _summary(ws, message_id: int = 1) -> dict:
    await ws.send_json({"id": message_id, "type": "hearth/household"})
    answer = await ws.receive_json()
    assert answer["success"], answer
    return answer["result"]


async def test_a_summary_with_alex_waiting_paused_and_low_and_sam_calm(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator, hass_ws_client, freezer
) -> None:
    # Signed in first: the sign-in's token is checked against the clock
    ws = await hass_ws_client(hass)
    freezer.move_to(_at(17, 40))
    client, phone = await _kids_alex_and_sam(hass, hass_client_no_auth, freezer)
    asked = await client.post(
        f"/api/hearth/device/{PHONE_ID}/ask", json={"minutes": 30, "group": "video"}, headers={"X-Hearth-Secret": phone}
    )
    assert asked.status == 200, await asked.text()
    ask_id = (await asked.json())["request"]["id"]
    await hass.services.async_call(
        DOMAIN, "pause", {"minutes": 50, "reason": "Dinner", "people": ["person.alex"]}, blocking=True
    )

    body = await _summary(ws)
    assert body["contract"] == 2
    people = {p["id"]: p for p in body["people"]}
    alex, sam = people["person.alex"], people["person.sam"]
    # Contract 1 stays as it was
    assert alex["groups"][1]["minutes_left"] == 5 and alex["pause"]["reason"] == "Dinner"
    assert alex["headline"] == {"text": "asks for 30 more · video", "level": "urgent", "key": f"ask:{ask_id}"}
    assert [line["text"] for line in alex["lines"]][:2] == ["paused · dinner till 6:30", "video · 5 left"]
    assert {a["id"] for a in alex["actions"]} == {
        f"ask_yes:{ask_id}", f"ask_no:{ask_id}", "bonus:video", "bonus:all", "pause_end"
    }
    assert sam["headline"] == {"text": "video · 50 left", "level": "calm", "key": "left:video"}
    assert sam["lines"][-1]["text"] == "bedtime at 9:00"
    assert body["household"]["headline"] == {"text": "alex asks for 30 more", "level": "urgent", "key": f"asks:{ask_id}"}
    assert {a["id"] for a in body["household"]["actions"]} == {f"ask_yes:{ask_id}", f"ask_no:{ask_id}", "pause_end", "pause_all"}

    # For the docs and Glint: HEARTH_EXAMPLE_OUT=<file> writes this summary out
    if out := os.environ.get("HEARTH_EXAMPLE_OUT"):
        with open(out, "w", encoding="utf-8") as file:
            json.dump(body, file, indent=2, ensure_ascii=False)
            file.write("\n")

    # Answered through the new service: the first answer wins, the next is refused
    answer = await hass.services.async_call(
        DOMAIN, "answer_request", {"request_id": ask_id, "minutes": 30}, blocking=True, return_response=True
    )
    assert answer["status"] == "approved" and answer["minutes"] == 30
    with pytest.raises(ServiceValidationError):
        await hass.services.async_call(DOMAIN, "answer_request", {"request_id": ask_id, "deny": True}, blocking=True)
    body = await _summary(ws, 2)
    alex = next(p for p in body["people"] if p["id"] == "person.alex")
    assert alex["headline"]["key"].startswith("pause:")
    assert next(g for g in alex["groups"] if g["id"] == "video")["minutes_left"] == 35


async def test_answer_request_wants_minutes_or_deny(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator
) -> None:
    await _household_with_sam(hass, hass_client_no_auth)
    import voluptuous as vol

    for data in ({"request_id": "x"}, {"request_id": "x", "minutes": 30, "deny": True}, {"request_id": "x", "minutes": 0}):
        with pytest.raises(vol.Invalid):
            await hass.services.async_call(DOMAIN, "answer_request", data, blocking=True)
    with pytest.raises(ServiceValidationError):
        await hass.services.async_call(DOMAIN, "answer_request", {"request_id": "x", "deny": True}, blocking=True)


async def test_only_adults_and_automations_call_hearth_s_services(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator, hass_admin_user, hass_read_only_user
) -> None:
    await _household_with_sam(hass, hass_client_no_auth)
    bonus = {"person": "person.sam", "minutes": 15, "group": "all"}
    # An automation (no user) and an administrator
    await hass.services.async_call(DOMAIN, "add_bonus", bonus, blocking=True)
    await hass.services.async_call(DOMAIN, "add_bonus", bonus, blocking=True, context=Context(user_id=hass_admin_user.id))

    # A user whose person is an adult on Hearth's page, not an administrator
    user = hass_read_only_user
    hass.states.async_set("person.alex", "home", {"friendly_name": "Alex", "user_id": user.id})
    from test_parent_pin import _adults

    await _adults(hass, "person.alex")
    as_user = Context(user_id=user.id)
    await hass.services.async_call(DOMAIN, "add_bonus", bonus, blocking=True, context=as_user)
    await hass.services.async_call(DOMAIN, "pause_end", {}, blocking=True, context=as_user)
    log = await hass.services.async_call(
        DOMAIN, "get_watch_log", {"person": "person.sam"}, blocking=True, return_response=True, context=as_user
    )
    assert log["person"] == "person.sam"

    # The same user as a kid: nothing that changes something, and not the watch log
    entry = hass.config_entries.async_entries(DOMAIN)[0]
    hass.config_entries.async_update_entry(entry, options={**entry.options, "roles": {"person.alex": "kid"}})
    await hass.async_block_till_done()
    for service, data, response in (
        ("add_bonus", bonus, False),
        ("pause", {"minutes": 10}, False),
        ("answer_request", {"request_id": "x", "deny": True}, False),
        ("get_watch_log", {"person": "person.sam"}, True),
        ("explain", {"person": "person.sam", "group": "all"}, True),
        ("copy_sites", {"dry_run": True}, True),
    ):
        with pytest.raises(Unauthorized):
            await hass.services.async_call(
                DOMAIN, service, data, blocking=True, return_response=response, context=as_user
            )
    # Three bonuses went through, none of the kid's
    hub = hass.config_entries.async_entries(DOMAIN)[0].runtime_data
    assert hub.household.limits.bonus("person.sam", "all") == 45


async def test_an_adult_who_isn_t_an_administrator_gets_contract_2_without_pairing(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator, hass_ws_client, hass_admin_user, freezer
) -> None:
    """H-3: a second parent who isn't an administrator reads the summary, headline and actions too, and never a
    pairing."""
    from test_parent_pin import _adults

    await _household_with_sam(hass, hass_client_no_auth)
    hass.states.async_set("person.alex", "home", {"friendly_name": "Alex", "user_id": hass_admin_user.id})
    await _adults(hass, "person.alex")
    hass_admin_user.groups = []
    hub = hass.config_entries.async_entries(DOMAIN)[0].runtime_data
    client = await hass_client_no_auth()
    freezer.tick(timedelta(seconds=11))
    await client.post(
        "/api/hearth/pair", json={"device_id": PHONE_ID, "kind": "mobile", "name": "A phone", "nonce": NONCE}
    )
    await hass.async_block_till_done()
    assert hub.pending_pairings()
    body = await _summary(await hass_ws_client(hass))
    assert body["contract"] == 2
    assert all(a["type"] != "pairing" for a in body["approvals"])
    assert "pair" not in body["household"]["headline"]["text"]
    sam = next(p for p in body["people"] if p["id"] == "person.sam")
    assert sam["headline"] and isinstance(sam["lines"], list) and sam["actions"]


def test_google_tv_s_own_limit_is_a_notice_like_a_lock() -> None:
    person = {**_person(all=90), "google_tv_limit": ["Kitchen"]}
    assert _glance(person)["headline"] == {"text": "google tv's own limit", "level": "notice", "key": "google_limit:Kitchen"}
