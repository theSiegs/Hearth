"""A shared Switch (switch_play.py): who is playing, from each player's minutes (Home Assistant's own Nintendo
integration) or a playing sensor of their own; someone else since; the "caught" hold that stays until the kid has time
again; unknown never lets a hold go; Let someone else play and Hold it now; play on no player told, never held."""

from datetime import timedelta

import pytest

from homeassistant.core import Context, HomeAssistant, State
from homeassistant.exceptions import ServiceValidationError, Unauthorized
from homeassistant.helpers import device_registry as dr, entity_registry as er
from homeassistant.util import dt as dt_util
from pytest_homeassistant_custom_component.common import (
    MockConfigEntry,
    async_capture_events,
    async_fire_time_changed,
)
from pytest_homeassistant_custom_component.typing import ClientSessionGenerator

from custom_components.hearth import enforce, switch_play as sp
from custom_components.hearth.const import DOMAIN
from test_enforce import _add_enforcer, _bonus, _budget, _nintendo_services
from test_people import _household_with_sam

N = "nintendo_parental_controls"
LIMIT = "number.our_switch_max_screentime_today"
SUSPEND = "switch.our_switch_suspend_software"
SAM_MIN = "sensor.our_switch_sam_used_screen_time"
ALEX_MIN = "sensor.our_switch_alex_used_screen_time"
SAM_PLAYING = "binary_sensor.our_switch_sam_playing"
# An adult's player (adults have no limits in Hearth) and the console's own minutes
JORDAN_MIN = "sensor.our_switch_jordan_used_screen_time"
CONSOLE = "sensor.our_switch_used_screen_time"
NOTICE = "hearth_switch_number_our_switch_max_screentime_today"
UNATTRIBUTED = "hearth_switch_number_our_switch_max_screentime_today_unattributed"


@pytest.fixture(autouse=True)
def settled(monkeypatch):
    monkeypatch.setattr(enforce, "SETTLE", timedelta(0))


def _switch(hass: HomeAssistant, *, patched: bool = False) -> None:
    """The family's Switch as Home Assistant's own Nintendo integration makes it: three players, Sam and Alex (kids)
    and Jordan (an adult), each with their minutes today, and the console's own; [patched]: a patched copy's playing
    sensor for Sam's player too."""
    entry = MockConfigEntry(domain=N, title="Nintendo")
    entry.add_to_hass(hass)
    device = dr.async_get(hass).async_get_or_create(
        config_entry_id=entry.entry_id, identifiers={(N, "abc123")}, name="Our Switch"
    )
    registry = er.async_get(hass)
    rows = [
        (LIMIT, "abc123_today_max_screentime", "120", None),
        (SUSPEND, "abc123_suspend_software", "off", None),
        (SAM_MIN, "abc123_p1_player_playing_time", "20", "Sam used screen time"),
        (ALEX_MIN, "abc123_p2_player_playing_time", "10", "Alex used screen time"),
        (JORDAN_MIN, "abc123_p3_player_playing_time", "0", "Jordan used screen time"),
        (CONSOLE, "abc123_playing_time", "30", None),
    ]
    if patched:
        rows.append((SAM_PLAYING, "abc123_p1_playing", "off", "Sam playing"))
    for entity_id, unique_id, state, name in rows:
        domain, object_id = entity_id.split(".")
        registry.async_get_or_create(
            domain, N, unique_id, device_id=device.id, suggested_object_id=object_id, original_name=name
        )
        hass.states.async_set(entity_id, state)


def _hub(hass: HomeAssistant):
    return hass.config_entries.async_entries(DOMAIN)[0].runtime_data


async def _minute(hass: HomeAssistant, freezer, n: int = 1, **readings: str) -> None:
    """[n] minutes pass, the integration reading each one (the same minutes, or [readings] by entity)."""
    for _ in range(n):
        freezer.tick(timedelta(minutes=1))
        for entity_id, value in {SAM_MIN: None, ALEX_MIN: None, JORDAN_MIN: None, CONSOLE: None, **_ids(readings)}.items():
            hass.states.async_set(entity_id, value if value is not None else hass.states.get(entity_id).state)
        async_fire_time_changed(hass)
        await hass.async_block_till_done()


def _ids(readings: dict[str, str]) -> dict[str, str]:
    names = {"sam": SAM_MIN, "alex": ALEX_MIN, "jordan": JORDAN_MIN, "console": CONSOLE, "sam_playing": SAM_PLAYING}
    return {names[k]: v for k, v in readings.items()}


async def _sam_caught(hass, hass_client_no_auth, freezer, *, patched: bool = False, row: dict | None = None):
    """Sam out of Games time on the shared Switch, then caught playing (their minutes grew): held."""
    freezer.move_to(dt_util.now().replace(hour=12, minute=0, second=0))
    _switch(hass, patched=patched)
    await _household_with_sam(hass, hass_client_no_auth)
    hass.states.async_set("person.alex", "home", {"friendly_name": "Alex"})
    entry = hass.config_entries.async_entries(DOMAIN)[0]
    hass.config_entries.async_update_entry(
        entry, options={**entry.options, "roles": {**entry.options.get("roles", {}), "person.alex": "kid"}}
    )
    await hass.async_block_till_done()
    calls = _nintendo_services(hass)
    await _add_enforcer(
        hass, row or {"kind": "nintendo", "person": "person.sam", "entity_id": LIMIT, "player": [SAM_MIN]}
    )
    await _budget(hass, "games", 5)
    # Out of time, but nothing says it's Sam on the Switch: it's open for whoever plays
    assert calls[0] == []
    await _minute(hass, freezer, 2)
    assert calls[0] == []
    await _minute(hass, freezer, sam="25")
    assert [c.data["value"] for c in calls[0]] == [0]
    hass.states.async_set(LIMIT, "0")
    return calls


# Reading the sources


def test_a_player_s_minutes_say_playing_only_when_they_grow_and_never_off_unseen() -> None:
    now = dt_util.utcnow()
    window = sp.WINDOW

    def state(value: str, at, changed=None) -> State:
        return State(SAM_MIN, value, last_changed=changed or at, last_reported=at, last_updated=changed or at)

    track = sp.MinutesTrack()
    # A first look: where growth counts from; unknown till watched a whole window
    track.observe(state("20", now), now)
    assert track.verdict(now, window) is None
    later = now + timedelta(minutes=5)
    track.observe(state("25", later), later)
    assert track.verdict(later, window) is True
    # Grown 14 minutes ago: still playing; 16: not, now that it was watched all along
    for minutes in (14, 16):
        at = later + timedelta(minutes=minutes)
        track.observe(state("25", at, changed=later), at)
    assert track.verdict(later + timedelta(minutes=14), window) is True
    assert track.verdict(later + timedelta(minutes=16), window) is False
    # Unavailable, or a reading gone stale: unknown, never "not playing"
    at = later + timedelta(minutes=20)
    track.observe(State(SAM_MIN, "unavailable", last_reported=at), at)
    assert track.verdict(at, window) is None
    track.observe(state("25", at - sp.STALE - timedelta(minutes=1)), at)
    assert track.verdict(at, window) is None
    # Nintendo's reset (a lower number) is a new start, not growth
    track.observe(state("0", at), at)
    assert track.value == 0 and track.verdict(at, window) is None


def test_a_playing_sensor_s_off_counts_only_once_it_stayed_off_and_is_fresh() -> None:
    now = dt_util.utcnow()
    assert sp.binary_verdict(State(SAM_PLAYING, "on", last_reported=now), now) is True
    just_off = State(SAM_PLAYING, "off", last_changed=now, last_reported=now)
    assert sp.binary_verdict(just_off, now) is None
    off = State(SAM_PLAYING, "off", last_changed=now - timedelta(minutes=3), last_reported=now)
    assert sp.binary_verdict(off, now) is False
    stale = State(SAM_PLAYING, "off", last_changed=now - timedelta(hours=1), last_reported=now - timedelta(minutes=30))
    assert sp.binary_verdict(stale, now) is None
    assert sp.binary_verdict(State(SAM_PLAYING, "unavailable", last_reported=now), now) is None
    assert sp.binary_verdict(None, now) is None
    assert sp.combine([None, False]) is False and sp.combine([False, True]) is True and sp.combine([None]) is None


# The caught hold


async def test_caught_playing_out_of_time_holds_the_switch_until_they_have_time_again(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator, freezer
) -> None:
    switch_events = async_capture_events(hass, "hearth_switch")
    set_value, _on, _off = await _sam_caught(hass, hass_client_no_auth, freezer)
    assert [e.data["what"] for e in switch_events] == ["caught"]
    item = _hub(hass).attention.item(NOTICE)
    assert item is not None and "Sam" in item.text and "Our Switch" in (item.title or "")
    assert item.actions[0].service == "hearth.let_someone_play"
    assert item.actions[0].data == {"device": f"nintendo:{LIMIT}", "minutes": 60}

    # The hold stops the game: Sam's minutes stop growing. Watched a whole window, that's a trusted "not playing",
    # and still the Switch stays held (it was let go here before, and Sam played on)
    await _minute(hass, freezer, 40)
    assert _hub(hass).household.enforcement.playing_now[f"nintendo|person.sam|{LIMIT}"] is False
    assert [c.data["value"] for c in set_value] == [0]

    # Time again: let go, and the adults' notice goes
    await _bonus(hass, "games", 30)
    assert [c.data["value"] for c in set_value] == [0, 120]
    assert _hub(hass).attention.item(NOTICE) is None
    assert [e.data["what"] for e in switch_events] == ["caught", "released"]


async def test_unknown_or_unavailable_never_lets_the_hold_go(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator, freezer
) -> None:
    set_value, _on, _off = await _sam_caught(hass, hass_client_no_auth, freezer)
    await _minute(hass, freezer, 30, sam="unavailable")
    await _minute(hass, freezer, 5, sam="unknown")
    assert [c.data["value"] for c in set_value] == [0]


async def test_unknown_doesn_t_catch_anyone_either(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator, freezer
) -> None:
    freezer.move_to(dt_util.now().replace(hour=12, minute=0, second=0))
    _switch(hass)
    await _household_with_sam(hass, hass_client_no_auth)
    set_value, _on, _off = _nintendo_services(hass)
    await _add_enforcer(hass, {"kind": "nintendo", "person": "person.sam", "entity_id": LIMIT, "player": [SAM_MIN]})
    hass.states.async_set(SAM_MIN, "unavailable")
    await _budget(hass, "games", 5)
    await _minute(hass, freezer, 20, sam="unavailable")
    # Back with more minutes: growth Hearth didn't see happen isn't play now
    await _minute(hass, freezer, 1, sam="60")
    assert set_value == []


async def test_a_patched_playing_sensor_beside_its_minutes_is_read_from_the_minutes(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator, freezer
) -> None:
    """The patched copy's sensor is the same growth, and flickers off and on at each reading: alone it catches no one
    (nor in a turn); the minutes growing do. Without its minutes sensor, it's read as itself and catches at once."""
    freezer.move_to(dt_util.now().replace(hour=12, minute=0, second=0))
    _switch(hass, patched=True)
    await _household_with_sam(hass, hass_client_no_auth)
    set_value, _on, _off = _nintendo_services(hass)
    await _add_enforcer(hass, {"kind": "nintendo", "person": "person.sam", "entity_id": LIMIT, "playing": [SAM_PLAYING]})
    await _budget(hass, "games", 5)
    await _minute(hass, freezer, 2)
    # Still on from Sam's play before the limit, flickering at a reading: not new play
    hass.states.async_set(SAM_PLAYING, "on")
    hass.states.async_set(SAM_PLAYING, "off")
    hass.states.async_set(SAM_PLAYING, "on")
    await _minute(hass, freezer, 1)
    assert set_value == []
    await _minute(hass, freezer, 1, sam="25")
    assert [c.data["value"] for c in set_value] == [0]
    assert hass.services.has_service(DOMAIN, "let_someone_play")

    # In a turn, the sensor's flicker isn't Sam playing again either
    hass.states.async_set(LIMIT, "0")
    await hass.services.async_call(
        DOMAIN, "let_someone_play", {"device": f"nintendo:{LIMIT}", "minutes": 30}, blocking=True
    )
    await hass.async_block_till_done()
    hass.states.async_set(LIMIT, "120")
    await _minute(hass, freezer, 13)
    hass.states.async_set(SAM_PLAYING, "off")
    hass.states.async_set(SAM_PLAYING, "on")
    await _minute(hass, freezer, 1)
    assert [c.data["value"] for c in set_value] == [0, 120]


async def test_a_playing_sensor_without_minutes_catches_at_once(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator, freezer
) -> None:
    """Friend presence, or a patched copy's sensor whose minutes sensor has no state: read as itself."""
    freezer.move_to(dt_util.now().replace(hour=12, minute=0, second=0))
    _switch(hass, patched=True)
    hass.states.async_remove(SAM_MIN)
    await _household_with_sam(hass, hass_client_no_auth)
    set_value, _on, _off = _nintendo_services(hass)
    await _add_enforcer(hass, {"kind": "nintendo", "person": "person.sam", "entity_id": LIMIT, "playing": [SAM_PLAYING]})
    await _budget(hass, "games", 5)
    assert set_value == []
    hass.states.async_set(SAM_PLAYING, "on")
    await hass.async_block_till_done()
    assert [c.data["value"] for c in set_value] == [0]


async def test_a_hold_from_before_this_version_counts_as_caught(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator, freezer
) -> None:
    row = {"kind": "nintendo", "person": "person.sam", "entity_id": LIMIT, "playing": [SAM_PLAYING]}
    freezer.move_to(dt_util.now().replace(hour=12, minute=0, second=0))
    _switch(hass, patched=True)
    await _household_with_sam(hass, hass_client_no_auth)
    set_value, _on, _off = _nintendo_services(hass)
    await _add_enforcer(hass, row)
    await _budget(hass, "games", 5)
    await _minute(hass, freezer, 2)
    await _minute(hass, freezer, 1, sam="25", sam_playing="on")
    assert [c.data["value"] for c in set_value] == [0]
    # An older Hearth kept no "caught": what it holds is
    enforcement = _hub(hass).household.enforcement
    enforcement.switch.clear()
    hass.states.async_set(SAM_PLAYING, "off")
    await _minute(hass, freezer, 10, sam_playing="off")
    assert [c.data["value"] for c in set_value] == [0]


async def test_midnight_ends_a_caught_hold(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator, freezer
) -> None:
    set_value, _on, _off = await _sam_caught(hass, hass_client_no_auth, freezer)
    freezer.move_to(dt_util.now().replace(hour=23, minute=59))
    await _minute(hass, freezer, 0)
    await _bonus(hass, "games", 0)
    assert [c.data["value"] for c in set_value] == [0, 120]


# Let someone else play


async def test_let_someone_else_play_lifts_the_hold_and_playing_in_it_holds_again(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator, freezer
) -> None:
    set_value, _on, _off = await _sam_caught(hass, hass_client_no_auth, freezer)
    await _minute(hass, freezer, 2)
    response = await hass.services.async_call(
        DOMAIN, "let_someone_play", {"device": f"nintendo:{LIMIT}", "minutes": 60, "for_person": "person.alex"},
        blocking=True, return_response=True,
    )
    await hass.async_block_till_done()
    assert response["held_for"] == ["person.sam"]
    assert [c.data["value"] for c in set_value] == [0, 120]
    assert _hub(hass).attention.item(NOTICE) is None
    hass.states.async_set(LIMIT, "120")

    # Nintendo's next upload still carries Sam's play from before the hold: forgiven, once
    await _minute(hass, freezer, 6, sam="30")
    # Alex plays: Alex's minutes grow, nothing happens
    await _minute(hass, freezer, 5, alex="20")
    assert [c.data["value"] for c in set_value] == [0, 120]
    switch = _hub(hass).household.enforcement.switch_view(LIMIT)
    assert switch["turn"]["for_person"] == "person.alex" and switch["turn"]["held_for"] == ["person.sam"]

    # Sam plays during Alex's turn: held again, and the adults are told
    await _minute(hass, freezer, 1, sam="35")
    assert [c.data["value"] for c in set_value] == [0, 120, 0]
    item = _hub(hass).attention.item(NOTICE)
    assert "Alex's turn" in item.text
    assert _hub(hass).household.enforcement.switch_view(LIMIT)["caught"] == ["person.sam"]


async def test_when_the_turn_ends_the_switch_stays_open_until_they_play_again(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator, freezer
) -> None:
    set_value, _on, _off = await _sam_caught(hass, hass_client_no_auth, freezer)
    freezer.tick(timedelta(minutes=20))
    await hass.services.async_call(
        DOMAIN, "let_someone_play", {"device": f"nintendo:{LIMIT}", "minutes": 15}, blocking=True
    )
    await hass.async_block_till_done()
    hass.states.async_set(LIMIT, "120")
    assert [c.data["value"] for c in set_value] == [0, 120]
    await _minute(hass, freezer, 20)
    # Over, and Sam hasn't played: open (no hold for the past)
    assert [c.data["value"] for c in set_value] == [0, 120]
    assert _hub(hass).household.enforcement.switch_view(LIMIT)["turn"] is None
    await _minute(hass, freezer, 1, sam="30")
    assert [c.data["value"] for c in set_value] == [0, 120, 0]


async def test_ending_a_turn_holds_again_now_and_bad_turns_are_refused(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator, freezer
) -> None:
    async def turn(**data):
        await hass.services.async_call(
            DOMAIN, "let_someone_play", {"device": f"nintendo:{LIMIT}", **data}, blocking=True
        )
        await hass.async_block_till_done()

    set_value, _on, _off = await _sam_caught(hass, hass_client_no_auth, freezer)
    with pytest.raises(ServiceValidationError, match="Nothing would hold"):
        await turn(minutes=0)
    with pytest.raises(ServiceValidationError, match="Sam"):
        await turn(minutes=30, for_person="person.sam")
    with pytest.raises(ServiceValidationError, match="isn't a Switch"):
        await hass.services.async_call(
            DOMAIN, "let_someone_play", {"device": "nintendo:number.other", "minutes": 30}, blocking=True
        )
    await turn(minutes=30)
    hass.states.async_set(LIMIT, "120")
    assert [c.data["value"] for c in set_value] == [0, 120]
    await turn(minutes=0)
    assert [c.data["value"] for c in set_value] == [0, 120, 0]

    await _bonus(hass, "games", 30)
    with pytest.raises(ServiceValidationError, match="isn't holding"):
        await turn(minutes=30)


async def test_the_page_shows_the_hold_and_lets_someone_else_play(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator, hass_ws_client, hass_admin_user, freezer
) -> None:
    set_value, _on, _off = await _sam_caught(hass, hass_client_no_auth, freezer)
    # A token of the frozen time's (the fixture's was made before the clock moved)
    refresh = await hass.auth.async_create_refresh_token(hass_admin_user, "https://hearth.test/")
    ws = await hass_ws_client(hass, hass.auth.async_create_access_token(refresh))

    async def call(msg: dict) -> dict:
        await ws.send_json({"id": call.n, **msg})
        call.n += 1
        return await ws.receive_json()

    call.n = 1
    device_id = er.async_get(hass).async_get(LIMIT).device_id
    summary = (await call({"type": "hearth/household"}))["result"]
    sam = next(p for p in summary["people"] if p["id"] == "person.sam")
    [row] = sam["first_party"]["nintendo"]
    assert row["shared"] and row["caught"] and row["held_by_hearth"] and row["turn"] is None

    result = await call(
        {"type": "hearth/nintendo/let_play", "person": "person.sam", "device_id": device_id, "minutes": 30}
    )
    assert result["success"], result
    await hass.async_block_till_done()
    assert [c.data["value"] for c in set_value] == [0, 120]
    summary = (await call({"type": "hearth/household"}))["result"]
    [row] = next(p for p in summary["people"] if p["id"] == "person.sam")["first_party"]["nintendo"]
    assert not row["caught"] and row["turn"]["held_for"] == ["person.sam"]

    # The players to pick, each with its Switch, and Sam's found by name
    config = (await call({"type": "hearth/config"}))["result"]
    players = {p["entity_id"]: p for p in config["choices"]["nintendo_players"]}
    assert players[SAM_MIN]["nickname"] == "Sam" and players[SAM_MIN]["switch"] == LIMIT
    assert sp.guess_player(hass, LIMIT, "Sam Rivera") == SAM_MIN
    assert sp.guess_player(hass, LIMIT, "Taylor") is None
    caps = config["capabilities"]["nintendo"]
    assert caps["player_minutes"] and not caps["player_playing"]
    await ws.close()


async def test_the_configure_menu_finds_the_player_by_name_on_a_shared_switch(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator
) -> None:
    from test_sources import _option

    _switch(hass)
    await _household_with_sam(hass, hass_client_no_auth)
    await _option(hass, "enforce", {"person": "person.sam", "nintendo": LIMIT})
    [row] = [r for r in hass.config_entries.async_entries(DOMAIN)[0].options["enforce"] if r["kind"] == "nintendo"]
    assert row["player"] == [SAM_MIN]


# Who's playing: someone else since, adults, play on no player


async def _set_up(hass, hass_client_no_auth, freezer):
    freezer.move_to(dt_util.now().replace(hour=12, minute=0, second=0))
    _switch(hass)
    await _household_with_sam(hass, hass_client_no_auth)
    calls = _nintendo_services(hass)
    await _add_enforcer(hass, {"kind": "nintendo", "person": "person.sam", "entity_id": LIMIT, "player": [SAM_MIN]})
    await _minute(hass, freezer, 2)
    return calls


async def test_someone_else_playing_since_isn_t_the_kid_caught_when_time_runs_out(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator, freezer
) -> None:
    """Sam played until a few minutes ago, then an adult took over (their minutes, and the console's, grew at a later
    reading without Sam's): when Sam runs out now, Sam isn't the one playing, and the adult plays on."""
    set_value, _on, _off = await _set_up(hass, hass_client_no_auth, freezer)
    await _minute(hass, freezer, 1, sam="25", console="35")
    await _minute(hass, freezer, 4)
    await _minute(hass, freezer, 5, jordan="10", console="45")
    await _budget(hass, "games", 5)
    assert set_value == []
    enforcement = _hub(hass).household.enforcement
    assert enforcement.playing_now[f"nintendo|person.sam|{LIMIT}"] is False
    # The adult plays on for an hour: never held
    for minutes in range(20, 80, 10):
        await _minute(hass, freezer, 10, jordan=str(minutes), console=str(minutes + 35))
    assert set_value == []
    assert _hub(hass).attention.item(UNATTRIBUTED) is None

    # Sam's own minutes grow again: that's Sam, caught
    await _minute(hass, freezer, 1, sam="30", console="120")
    assert [c.data["value"] for c in set_value] == [0]


async def test_the_kid_and_someone_else_in_one_upload_is_the_kid_playing(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator, freezer
) -> None:
    """Two playing together (each with their own user): both grow in the same upload, so Sam is playing."""
    set_value, _on, _off = await _set_up(hass, hass_client_no_auth, freezer)
    await _minute(hass, freezer, 1, sam="25", jordan="5", console="35")
    await _budget(hass, "games", 5)
    assert [c.data["value"] for c in set_value] == [0]


async def test_play_on_no_player_is_told_with_hold_it_now_never_held_by_itself(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator, freezer
) -> None:
    """The console's minutes grow and no player's do (software that needs no user, or no user picked) while Sam is
    out of time: the adults are told, once an hour at most, and can hold the Switch now."""
    switch_events = async_capture_events(hass, "hearth_switch")
    set_value, _on, _off = await _set_up(hass, hass_client_no_auth, freezer)
    await _budget(hass, "games", 5)
    await _minute(hass, freezer, 10, console="40")
    assert _hub(hass).attention.item(UNATTRIBUTED) is None  # Nintendo's rounding, not yet play
    await _minute(hass, freezer, 10, console="50")
    item = _hub(hass).attention.item(UNATTRIBUTED)
    assert item is not None and "20 min" in item.text and "Sam" in item.text
    assert item.actions[0].data == {"device": f"nintendo:{LIMIT}", "minutes": 0}
    assert set_value == []
    assert [e.data["what"] for e in switch_events] == ["unattributed"]
    await _minute(hass, freezer, 10, console="70")
    assert [e.data["what"] for e in switch_events] == ["unattributed"]  # not again within the hour
    page = _hub(hass).household.enforcement.switch_view(LIMIT)
    assert page["waiting"] == ["person.sam"] and page["caught"] == []

    # An adult holds it now: held until Sam has time again
    await hass.services.async_call(
        DOMAIN, "let_someone_play", {"device": f"nintendo:{LIMIT}", "minutes": 0}, blocking=True
    )
    await hass.async_block_till_done()
    assert [c.data["value"] for c in set_value] == [0]
    assert _hub(hass).attention.item(UNATTRIBUTED) is None
    assert _hub(hass).household.enforcement.switch_view(LIMIT)["caught"] == ["person.sam"]
    hass.states.async_set(LIMIT, "0")
    await _minute(hass, freezer, 30)
    assert [c.data["value"] for c in set_value] == [0]
    await _bonus(hass, "games", 30)
    assert [c.data["value"] for c in set_value] == [0, 120]


async def test_hold_it_now_needs_a_reason_and_an_adult(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator, freezer, hass_read_only_user
) -> None:
    set_value, _on, _off = await _set_up(hass, hass_client_no_auth, freezer)
    # Sam has time: nothing would hold the Switch, so it isn't held for anyone
    with pytest.raises(ServiceValidationError, match="Nothing would hold"):
        await hass.services.async_call(
            DOMAIN, "let_someone_play", {"device": f"nintendo:{LIMIT}", "minutes": 0}, blocking=True
        )
    await _budget(hass, "games", 5)
    # A user who isn't an adult (a kid's own Home Assistant user) can neither hold it nor give a turn
    for minutes in (0, 60):
        with pytest.raises(Unauthorized):
            await hass.services.async_call(
                DOMAIN, "let_someone_play", {"device": f"nintendo:{LIMIT}", "minutes": minutes}, blocking=True,
                context=Context(user_id=hass_read_only_user.id),
            )
    assert set_value == []


async def test_extra_time_on_the_switch_alone_lets_a_caught_hold_go(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator, freezer
) -> None:
    """Extra time on this Switch only (Hearth's page) lifts what would hold it: the caught hold goes with it."""
    switch_events = async_capture_events(hass, "hearth_switch")
    set_value, _on, _off = await _sam_caught(hass, hass_client_no_auth, freezer)
    await hass.services.async_call(
        DOMAIN, "add_bonus", {"person": "person.sam", "minutes": 20, "group": "all", "device": f"nintendo:{LIMIT}"},
        blocking=True,
    )
    await hass.async_block_till_done()
    assert [c.data["value"] for c in set_value] == [0, 120]
    assert [e.data["what"] for e in switch_events][-1] == "released"
    assert _hub(hass).attention.item(NOTICE) is None


async def test_a_reading_gone_for_a_moment_is_no_play_in_a_turn(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator, freezer
) -> None:
    """The integration's entities go unavailable for a few seconds around a reload: Sam's minutes missing and back
    the same are no play."""
    set_value, _on, _off = await _sam_caught(hass, hass_client_no_auth, freezer)
    freezer.tick(timedelta(minutes=20))
    await hass.services.async_call(
        DOMAIN, "let_someone_play", {"device": f"nintendo:{LIMIT}", "minutes": 60}, blocking=True
    )
    await hass.async_block_till_done()
    hass.states.async_set(LIMIT, "120")
    await _minute(hass, freezer, 2, sam="unavailable")
    await _minute(hass, freezer, 1, sam="25")
    await _minute(hass, freezer, 20)
    assert [c.data["value"] for c in set_value] == [0, 120]


def test_console_watch_counts_play_on_no_player_only() -> None:
    now = dt_util.utcnow()
    watch = sp.ConsoleWatch()
    assert watch.update(30, 30, now) is None  # where it counts from
    # Two playing together: the players count past the console, from there again
    assert watch.update(40, 50, now) is None
    assert watch.update(50, 55, now) is None  # 5 on no player: Nintendo's rounding
    assert watch.update(70, 55, now) == 25
    assert watch.update(90, 55, now + timedelta(minutes=10)) is None  # told within the hour
    # A gap: nothing in it counts
    assert watch.update(None, 55, now) is None
    assert watch.update(200, 55, now + timedelta(hours=2)) is None
