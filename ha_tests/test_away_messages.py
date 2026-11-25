"""Messages when away from adults (presence_rules.py): while a kid is away from home and apart from every adult, their
text app isn't held by time limits; 10 minutes with an adult or at home puts it back. It lifts time limits only, never
School time, the schedule, bedtime, a pause or a block, and it writes nothing of its own."""

from datetime import timedelta
import json

from homeassistant.core import CoreState, HomeAssistant
from homeassistant.util import dt as dt_util
from pytest_homeassistant_custom_component.typing import ClientSessionGenerator

from custom_components.hearth import household as household_module
from custom_components.hearth.const import DOMAIN
from custom_components.hearth.presence_rules import GOOGLE_MESSAGES, SAMSUNG_MESSAGES
from test_messaging import CHROME, DIALER, GAME, LATE, MESSAGES, _budget, _installed, settled  # noqa: F401
from test_presence import (
    ALEX,
    FAR,
    HOME_AT,
    OUT,
    SAM,
    _household,
    look,
    minutes,
    sam_out_of_time,
    set_adult,
)

WHATSAPP = "com.whatsapp"
SCHOOL_SENSOR = "binary_sensor.sam_phone_school_time_active"
BEDTIME_SENSOR = "binary_sensor.sam_phone_bedtime_active"


def _held(hass: HomeAssistant) -> list[str]:
    return _household(hass).enforcement.held_for(SAM).get("family_link", {}).get("held", [])


async def _call(hass: HomeAssistant, service: str, data: dict, response: bool = False):
    result = await hass.services.async_call(DOMAIN, service, data, blocking=True, return_response=response)
    await hass.async_block_till_done()
    return result


async def _opened(hass: HomeAssistant, freezer) -> None:
    """Sam goes out while Alex stays home: Messages opens."""
    await minutes(hass, freezer, 9, OUT)
    assert _household(hass).away.on(SAM)


async def test_daily_time_out_and_apart_opens_messages_and_pauses_the_rest(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator, freezer
) -> None:
    calls = await sam_out_of_time(hass, hass_client_no_auth, freezer)
    assert "Devices" in _held(hass)
    # Nothing written to Family Link's daily limit while Hearth holds the devices
    assert not [c for c in calls["limit"] if "day" not in c.data]
    # Out for 4 minutes: not yet
    await minutes(hass, freezer, 4, OUT)
    assert not _household(hass).away.on(SAM) and "Devices" in _held(hass)
    await minutes(hass, freezer, 5, OUT)
    household = _household(hass)
    assert household.away.on(SAM)
    held = _held(hass)
    assert "Devices" not in held and {CHROME, LATE, GAME} <= set(held)
    assert MESSAGES not in held and DIALER not in held
    assert household.open_apps(SAM) == {MESSAGES}
    # The backstop: the phone's 40 + 120 for the open app + 30
    assert [c.data["daily_minutes"] for c in calls["limit"] if "day" not in c.data][-1] == 190
    # Logged, with the app and never a place
    [record] = household.activity.query(SAM, "rule")
    assert record["result"] == "opened" and record["target"] == [MESSAGES] and record["reason"] == "away_messages"
    # Written as nothing of its own: no allow
    assert household.allows.of(SAM) == []


async def test_pausing_every_app_doesn_t_flip_back_to_the_device_lock_when_the_list_is_cut_short(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator, freezer
) -> None:
    """Pausing every app moves them all into Family Link's With time limits list, which then gets too big for Home
    Assistant and is cut short (truncated). The apps installed are still the ones last seen whole: Hearth keeps the
    apps paused rather than swapping back to the device lock, and back again, every few minutes."""
    calls = await sam_out_of_time(hass, hass_client_no_auth, freezer)
    await _opened(hass, freezer)
    household = _household(hass)
    held = _held(hass)
    assert "Devices" not in held and {CHROME, LATE, GAME} <= set(held)
    pauses, resumes = len(calls["pause"]), len(calls["resume"])
    # Family Link now lists the paused apps with a 1-minute limit, cut short; the other lists are left with Messages
    limited = [{"package": p, "limit_minutes": 1} for p in sorted({CHROME, LATE, GAME, DIALER} & set(held))]
    hass.states.async_set(
        "sensor.sam_apps_with_time_limits", str(len(limited)), {"child_id": "42", "apps": limited[:1], "truncated": True}
    )
    hass.states.async_set("sensor.sam_apps_without_limits", "2", {"child_id": "42", "apps": [{"package": MESSAGES}, {"package": DIALER}]})
    for _ in range(3):
        await minutes(hass, freezer, 3, OUT)
    assert household.open_apps(SAM) == {MESSAGES}
    assert "Devices" not in _held(hass) and {CHROME, LATE, GAME} <= set(_held(hass))
    assert len(calls["resume"]) == resumes and len(calls["pause"]) == pauses


async def test_a_restart_while_every_app_is_paused_doesn_t_swap_to_the_device_lock(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator, freezer
) -> None:
    """After a restart nothing is remembered in memory and the With time limits list is still cut short by Hearth's
    own pauses. The apps Hearth holds are what filled it: the pauses stay, with no device lock and no resume."""
    calls = await sam_out_of_time(hass, hass_client_no_auth, freezer)
    await _opened(hass, freezer)
    household = _household(hass)
    held = _held(hass)
    assert "Devices" not in held and {CHROME, LATE, GAME} <= set(held)
    pauses, resumes = len(calls["pause"]), len(calls["resume"])
    limited = [{"package": p, "limit_minutes": 1} for p in sorted({CHROME, LATE, GAME, DIALER} & set(held))]
    hass.states.async_set(
        "sensor.sam_apps_with_time_limits", str(len(limited)), {"child_id": "42", "apps": limited[:1], "truncated": True}
    )
    hass.states.async_set("sensor.sam_apps_without_limits", "2", {"child_id": "42", "apps": [{"package": MESSAGES}, {"package": DIALER}]})
    # The restart: no whole read in memory, and none stored (the first start with a Hearth that stores it)
    hass.data.pop("hearth_fl_installed")
    for _ in range(3):
        await minutes(hass, freezer, 3, OUT)
    assert household.open_apps(SAM) == {MESSAGES}
    assert "Devices" not in _held(hass) and {CHROME, LATE, GAME} <= set(_held(hass))
    assert len(calls["resume"]) == resumes and len(calls["pause"]) == pauses


async def test_the_last_whole_read_of_the_installed_apps_is_stored_and_comes_back(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator, freezer
) -> None:
    from custom_components.hearth import family_link as fl
    from custom_components.hearth.enforce import Enforcement

    await sam_out_of_time(hass, hass_client_no_auth, freezer)
    household = _household(hass)
    whole = sorted([MESSAGES, CHROME, LATE, DIALER, GAME])
    assert fl.installed_apps(hass, "42") == set(whole)
    assert household.enforcement._data()["fl_installed"] == {"42": whole}
    await household.enforcement._store.async_save(household.enforcement._data())
    # A restart: nothing in memory, and the lists cut short. Loaded with what Hearth holds, before its first run
    hass.data.pop("hearth_fl_installed")
    hass.states.async_set(
        "sensor.sam_apps_with_time_limits", "4", {"child_id": "42", "apps": [{"package": CHROME}], "truncated": True}
    )
    hass.states.async_set("sensor.sam_apps_without_limits", "1", {"child_id": "42", "apps": [{"package": MESSAGES}]})
    assert fl.installed_apps(hass, "42") is None
    fresh = Enforcement(hass, household.hub.entry.entry_id)
    await fresh.async_load()
    assert fl.installed_apps(hass, "42") == set(whole)
    fl.on_installed_changed(hass, household.enforcement._installed_changed)
    # With nothing stored, only a With time limits list cut short alone reads as what Hearth holds
    hass.data.pop("hearth_fl_installed")
    assert fl.installed_apps(hass, "42", {GAME, LATE, "Devices"}) == {CHROME, MESSAGES, GAME, LATE}
    hass.states.async_set(
        "sensor.sam_apps_without_limits", "9", {"child_id": "42", "apps": [{"package": MESSAGES}], "truncated": True}
    )
    assert fl.installed_apps(hass, "42", {GAME, LATE}) is None


async def test_messaging_s_limit_out_and_apart_opens_messages_only(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator, freezer
) -> None:
    calls = await sam_out_of_time(hass, hass_client_no_auth, freezer)
    _installed(hass, [MESSAGES, WHATSAPP, CHROME, GAME])
    await _budget(hass, "all", 500)
    await _budget(hass, "messaging", 30)
    assert MESSAGES in _held(hass) and "Devices" not in _held(hass)
    await _opened(hass, freezer)
    held = set(_held(hass))
    assert MESSAGES not in held and MESSAGES in calls["resume"][-1].data["packages"]
    # WhatsApp is Messaging too, not the text app: still held
    assert WHATSAPP in held


async def test_school_time_keeps_messages_paused(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator, freezer
) -> None:
    from test_sources import _option
    from test_messaging import FAMILY_LINK

    calls = await sam_out_of_time(hass, hass_client_no_auth, freezer)
    hass.states.async_set(SCHOOL_SENSOR, "on", {"child_id": "42", "schooltime_end": "2030-01-01T15:00:00"})
    await _option(hass, "enforce", {"person": SAM, "family_link": FAMILY_LINK, "school_time_apps": [MESSAGES]})
    await _opened(hass, freezer)
    household = _household(hass)
    # School time's pause holds, so it doesn't swap the device lock for a pause of every other app
    assert household.open_apps(SAM) == set()
    assert "Devices" in _held(hass) and MESSAGES in _held(hass)
    why = await _call(hass, "explain", {"person": SAM, "app": MESSAGES}, True)
    assert "school_time_apps" in [b["kind"] for b in why["blocked_by"]] and why["allowed"] is False


async def test_a_pause_a_block_and_bedtime_still_hold(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator, freezer
) -> None:
    await sam_out_of_time(hass, hass_client_no_auth, freezer)
    await _opened(hass, freezer)
    household = _household(hass)
    assert household.open_apps(SAM) == {MESSAGES}

    # An adult's pause of Messages: held, and the device lock is back rather than ~every app paused
    await _call(hass, "pause", {"people": [SAM], "app": MESSAGES, "minutes": 30})
    assert household.open_apps(SAM) == set() and "Devices" in _held(hass) and MESSAGES in _held(hass)
    await _call(hass, "pause_end", {"people": [SAM], "app": MESSAGES})
    assert household.open_apps(SAM) == {MESSAGES} and "Devices" not in _held(hass)

    # A family pause
    await _call(hass, "pause", {"people": [SAM], "minutes": 30})
    assert household.open_apps(SAM) == set() and "Devices" in _held(hass)
    await _call(hass, "pause_end", {"people": [SAM]})
    assert "Devices" not in _held(hass)

    # Family Link's bedtime
    hass.states.async_set(BEDTIME_SENSOR, "on", {"child_id": "42"})
    household.recompute()
    await hass.async_block_till_done()
    assert household.open_apps(SAM) == set() and "Devices" in _held(hass)
    hass.states.async_set(BEDTIME_SENSOR, "off", {"child_id": "42"})
    household.recompute()
    await hass.async_block_till_done()

    # Blocked in Family Link: Hearth's block holds whatever the rule says
    from test_app_blocks import _lists

    _lists(hass, [MESSAGES, CHROME, LATE, DIALER, GAME], blocked=[MESSAGES])
    hass.states.async_set("sensor.sam_blocked_apps", "1", {"child_id": "42", "apps": [{"package": MESSAGES}]})
    household.recompute()
    await hass.async_block_till_done()
    assert household.open_apps(SAM) == set() and "Devices" in _held(hass)
    # (and the rule doesn't pick a blocked text app at all)
    assert MESSAGES not in household.away.sms_apps(SAM)


async def test_a_blocked_list_never_read_whole_keeps_the_device_lock(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator, freezer
) -> None:
    """Which apps are blocked isn't known (the Blocked apps list is cut short and was never read whole): the device
    lock isn't swapped for a pause of every other app, the blocked ones with them."""
    await sam_out_of_time(hass, hass_client_no_auth, freezer)
    await _opened(hass, freezer)
    household = _household(hass)
    assert household.open_apps(SAM) == {MESSAGES} and "Devices" not in _held(hass)

    # Cut short after a whole read: the last whole list stands, and nothing swaps
    hass.states.async_set("sensor.sam_blocked_apps", "80", {"child_id": "42", "apps": [], "truncated": True})
    household.recompute()
    await hass.async_block_till_done()
    assert household.open_apps(SAM) == {MESSAGES} and "Devices" not in _held(hass)

    # Never read whole
    household.blocks.last_blocked.clear()
    assert household.open_apps(SAM) == set()
    household.recompute()
    await hass.async_block_till_done()
    assert "Devices" in _held(hass)


async def test_with_an_adult_9_minutes_stays_open_10_closes(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator, freezer
) -> None:
    calls = await sam_out_of_time(hass, hass_client_no_auth, freezer)
    await _opened(hass, freezer)
    # Alex comes to Sam for 9 minutes, then leaves again
    await minutes(hass, freezer, 9, OUT, alex=OUT)
    assert _household(hass).away.on(SAM)
    await minutes(hass, freezer, 8, OUT, alex=HOME_AT)
    assert _household(hass).away.on(SAM)
    # Back with Alex: 10 minutes without a break and it's back to normal
    await minutes(hass, freezer, 9, OUT, alex=OUT)
    assert _household(hass).away.on(SAM)
    await minutes(hass, freezer, 2, OUT, alex=OUT)
    household = _household(hass)
    assert not household.away.on(SAM)
    assert "Devices" in _held(hass) and household.open_apps(SAM) == set()
    assert [r["result"] for r in household.activity.query(SAM, "rule")] == ["closed", "opened"]
    # Not opened again within 15 minutes of opening, whatever happens next
    assert len(calls["pause"]) >= 1


async def test_at_home_10_minutes_with_no_adult_there_closes(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator, freezer
) -> None:
    await sam_out_of_time(hass, hass_client_no_auth, freezer)
    await _opened(hass, freezer)
    set_adult(hass, FAR)
    # Home: Places confirms it with two fixes, then 10 minutes
    await minutes(hass, freezer, 9, HOME_AT)
    assert _household(hass).away.on(SAM)
    await minutes(hass, freezer, 3, HOME_AT)
    assert not _household(hass).away.on(SAM) and "Devices" in _held(hass)


async def test_home_alone_never_opens(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator, freezer
) -> None:
    await sam_out_of_time(hass, hass_client_no_auth, freezer, adult=FAR)
    await minutes(hass, freezer, 30, HOME_AT)
    assert not _household(hass).away.on(SAM) and "Devices" in _held(hass)


async def test_an_allow_and_a_pause_made_while_open_are_left_alone(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator, freezer
) -> None:
    calls = await sam_out_of_time(hass, hass_client_no_auth, freezer)
    _installed(hass, [MESSAGES, WHATSAPP, CHROME, GAME])
    await _budget(hass, "all", 500)
    await _budget(hass, "messaging", 30)
    await _opened(hass, freezer)
    # An adult's allow of Messages while it's open: its own record, which outlives the rule
    await _call(hass, "allow", {"people": [SAM], "app": MESSAGES, "until": "end_of_day"})
    await minutes(hass, freezer, 12, OUT, alex=OUT)
    household = _household(hass)
    assert not household.away.on(SAM)
    assert [a.app for a in household.allows.of(SAM)] == [MESSAGES]
    assert MESSAGES not in _held(hass) and WHATSAPP in _held(hass)
    await _call(hass, "allow_end", {"people": [SAM], "app": MESSAGES})
    assert MESSAGES in _held(hass)

    # Open again, then an adult's pause of Messages: it holds at once, and stays after the rule ends
    set_adult(hass, HOME_AT)
    await minutes(hass, freezer, 10, OUT)
    assert _household(hass).away.on(SAM) and MESSAGES not in _held(hass)
    await _call(hass, "pause", {"people": [SAM], "app": MESSAGES, "minutes": 120})
    assert MESSAGES in _held(hass)
    await minutes(hass, freezer, 12, OUT, alex=OUT)
    assert not _household(hass).away.on(SAM) and MESSAGES in _held(hass)


async def test_which_app(hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator, freezer) -> None:
    from test_app_blocks import _lists

    await sam_out_of_time(hass, hass_client_no_auth, freezer)
    away = _household(hass).away
    assert away.sms_apps(SAM) == {GOOGLE_MESSAGES}
    _lists(hass, [SAMSUNG_MESSAGES, CHROME])
    assert away.sms_apps(SAM) == {SAMSUNG_MESSAGES}
    # Google Messages first when both are there
    _lists(hass, [SAMSUNG_MESSAGES, GOOGLE_MESSAGES, CHROME])
    assert away.sms_apps(SAM) == {GOOGLE_MESSAGES}
    # Neither: the rule is idle (it never opens), and an odd setting doesn't stop anything
    _lists(hass, [CHROME, GAME])
    assert away.sms_apps(SAM) == set()
    await minutes(hass, freezer, 9, OUT)
    assert not _household(hass).away.on(SAM)
    # An app an adult added for Sam is lifted too
    entry = hass.config_entries.async_entries(DOMAIN)[0]
    hass.config_entries.async_update_entry(
        entry, options={**entry.options, "away_messages_apps": {SAM: [WHATSAPP, "not a package", 7], "person.ghost": [GAME]}}
    )
    await hass.async_block_till_done()
    _lists(hass, [WHATSAPP, CHROME, GAME])
    assert _household(hass).away.sms_apps(SAM) == {WHATSAPP}
    await minutes(hass, freezer, 3, OUT)
    assert _household(hass).away.on(SAM)
    assert _household(hass).open_apps(SAM) == {WHATSAPP}


async def test_explain_the_sensor_and_the_state_document(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator, freezer
) -> None:
    await sam_out_of_time(hass, hass_client_no_auth, freezer)
    await _opened(hass, freezer)
    household = _household(hass)
    why = await _call(hass, "explain", {"person": SAM, "app": MESSAGES}, True)
    assert why["allowed"] is True
    assert any(h["kind"] == "budget" and h["by"] == "all" for h in why["lifted"])
    [rule] = [e for e in why["exceptions"] if e["id"] == "rule:away_messages"]
    assert rule["until"] is None and rule["while"]["apart"] == "adults"
    assert rule["while"]["text"] == "while Sam is out without an adult" and rule["since"]
    game = await _call(hass, "explain", {"person": SAM, "app": GAME}, True)
    assert game["allowed"] is False and not [e for e in game["exceptions"] if e["id"].startswith("rule:")]
    # Screen time today: the rule next to allows and grants
    sensor = hass.states.get("sensor.hearth_sam_screen_time_today")
    assert [r["id"] for r in sensor.attributes["exceptions"]["rules"]] == ["rule:away_messages"]
    # The kid's own state document: Messages left out of the held apps and in All screen time's except, and nothing
    # about a place or a person
    document = household._person_document(SAM)
    whole = next(g for g in document["groups"] if g["id"] == "all")
    assert MESSAGES in whole.get("except", [])
    text = json.dumps(document)
    for word in ("apart", "away_messages", "Alex", "person.alex", "with_adult", "0234567"):
        assert word not in text
    # The adults' page: where Sam is, by name, and what's open
    page = household.presence.page(SAM)
    assert page["away"] and page["apart"] and page["open"] == [page["open"][0]] and page["apart_since"]


async def test_switched_off_nothing_is_lifted_and_it_closes(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator, freezer
) -> None:
    await sam_out_of_time(hass, hass_client_no_auth, freezer)
    await _opened(hass, freezer)
    entry = hass.config_entries.async_entries(DOMAIN)[0]
    hass.config_entries.async_update_entry(entry, options={**entry.options, "away_messages": False})
    await hass.async_block_till_done()
    household = _household(hass)
    assert household.away.lifted_apps(SAM) == set() and household.open_apps(SAM) == set()
    await look(hass)
    assert not _household(hass).away.on(SAM) and "Devices" in _held(hass)
    # Off, it never opens
    await minutes(hass, freezer, 15, OUT)
    assert not _household(hass).away.on(SAM)


# Restarts


async def _restart(hass: HomeAssistant, monkeypatch) -> None:
    """Home Assistant starts again: the positions in memory are gone, and the household settles for 90 seconds."""
    monkeypatch.setattr(household_module, "STARTUP_SETTLE", timedelta(seconds=90))
    entry = hass.config_entries.async_entries(DOMAIN)[0]
    assert await hass.config_entries.async_unload(entry.entry_id)
    hass.data.pop("hearth_presence_tracks", None)
    # Set up before Home Assistant runs, as at a start: settling from the first look
    hass.set_state(CoreState.not_running)
    assert await hass.config_entries.async_setup(entry.entry_id)
    await hass.async_block_till_done()
    hass.set_state(CoreState.running)
    _household(hass)._settle_until = None


def _facts(presence, at: bool = True) -> dict:
    """Each fact's value, last known value and since (as an instant). [at]: with the place (Places' own, which a
    reload reads afresh)."""
    return {
        person: {
            name: (f.value, f.known, f.since and dt_util.as_utc(f.since).isoformat())
            for name, f in facts.items()
            if at or name != "at"
        }
        for person, facts in presence.core.facts.items()
    }


def _call_count(calls) -> int:
    return sum(len(v) for v in calls.values())


async def test_open_stays_open_over_a_restart_with_no_family_link_call(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator, freezer, monkeypatch
) -> None:
    calls = await sam_out_of_time(hass, hass_client_no_auth, freezer)
    await _opened(hass, freezer)
    made = _call_count(calls)
    await _restart(hass, monkeypatch)
    await look(hass)
    household = _household(hass)
    assert household._settling(dt_util.utcnow())
    assert household.away.on(SAM) and "Devices" not in _held(hass)
    # Settled, with Sam still out: still open, and nothing was called for the restart
    await minutes(hass, freezer, 3, OUT)
    assert _household(hass).away.on(SAM)
    assert _call_count(calls) == made


async def test_an_old_adult_position_keeps_its_age_over_a_restart(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator, freezer, monkeypatch
) -> None:
    await sam_out_of_time(hass, hass_client_no_auth, freezer, adult=FAR)
    first = _household(hass).presence.seen[ALEX]["at"]
    await minutes(hass, freezer, 100, OUT)
    household = _household(hass)
    # Alex's position is 100 minutes old and Alex isn't home: left out, so Sam's facts are unknown
    assert household.presence.core.located(dt_util.utcnow()) == {}
    facts = _facts(household.presence)
    rules = json.loads(json.dumps(household.presence.rules))
    await _restart(hass, monkeypatch)
    # Home Assistant restores Alex's person with a new change time: the stored age stands
    state = hass.states.get(ALEX)
    hass.states.async_set(ALEX, state.state, dict(state.attributes), force_update=True)
    await look(hass)
    household = _household(hass)
    assert household.presence.seen[ALEX]["at"] == first
    assert household.presence.core.located(dt_util.utcnow()) == {}
    # Nothing changed while settling
    assert _facts(household.presence) == facts
    assert household.presence.rules == rules


async def test_a_reload_keeps_the_facts_and_the_tracks(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator, freezer
) -> None:
    await sam_out_of_time(hass, hass_client_no_auth, freezer)
    await _opened(hass, freezer)
    before = _household(hass).presence
    kept = (_facts(before, at=False), len(before.core.tracks["kids"][SAM]))
    entry = hass.config_entries.async_entries(DOMAIN)[0]
    assert await hass.config_entries.async_reload(entry.entry_id)
    await hass.async_block_till_done()
    after = _household(hass).presence
    assert after is not before
    assert (_facts(after, at=False), len(after.core.tracks["kids"][SAM])) == kept
    assert _household(hass).away.on(SAM)
