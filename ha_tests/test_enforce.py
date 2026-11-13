"""Enforcing: a group out of time is held by Family Link, Family Safety and Nintendo too, and let go when it has time
again."""

from datetime import datetime, timedelta

import pytest
import voluptuous as vol

from homeassistant.core import HomeAssistant, ServiceCall, SupportsResponse
from homeassistant.exceptions import HomeAssistantError
from homeassistant.util import dt as dt_util
from pytest_homeassistant_custom_component.common import async_capture_events, async_fire_time_changed, async_mock_service
from pytest_homeassistant_custom_component.typing import ClientSessionGenerator

from custom_components.hearth import enforce
from custom_components.hearth.const import DOMAIN
from custom_components.hearth.enforce import essential, hours_to_midnight
from test_people import _household_with_sam
from test_sources import _option

FAMILY_LINK = "sensor.sam_family_link_daily_screen_time"
FAMILY_SAFETY = "sensor.sam_family_safety_account_info"


@pytest.fixture(autouse=True)
def settled(monkeypatch):
    """Tests don't wait out the minutes after a start in which nothing is let go."""
    monkeypatch.setattr(enforce, "SETTLE", timedelta(0))


async def _budget(hass: HomeAssistant, group: str, minutes: int) -> None:
    await hass.services.async_call(
        DOMAIN, "set_budget", {"person": "person.sam", "group": group, "minutes": minutes}, blocking=True
    )
    await hass.async_block_till_done()


async def _bonus(hass: HomeAssistant, group: str, minutes: int) -> None:
    await hass.services.async_call(
        DOMAIN, "add_bonus", {"person": "person.sam", "group": group, "minutes": minutes}, blocking=True
    )
    await hass.async_block_till_done()


async def _add_enforcer(hass: HomeAssistant, raw: dict) -> None:
    """An enforcer straight into the options (a typed-in Family Safety account id, which the form's entity picker
    doesn't take)."""
    entry = hass.config_entries.async_entries(DOMAIN)[0]
    enforce_list = [e for e in entry.options.get("enforce", []) if e.get("person") != raw["person"]] + [raw]
    hass.config_entries.async_update_entry(entry, options={**entry.options, "enforce": enforce_list})
    await hass.async_block_till_done()


def _family_link(hass: HomeAssistant):
    return async_mock_service(hass, "familylink", "pause_app"), async_mock_service(hass, "familylink", "resume_app")


async def test_family_link_pauses_the_group_s_apps_and_resumes_them(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator
) -> None:
    paused, resumed = _family_link(hass)
    await _household_with_sam(hass, hass_client_no_auth)
    await _option(hass, "enforce", {"person": "person.sam", "family_link": FAMILY_LINK})
    events = async_capture_events(hass, "hearth_enforced")

    await _budget(hass, "video", 10)  # 10 watched: none left
    assert len(paused) == 1
    assert paused[0].data["entity_id"] == FAMILY_LINK
    assert "com.thesiegs.hearthtube" in paused[0].data["packages"]
    held = hass.states.get("sensor.hearth_sam_held_by_parental_controls")
    assert int(held.state) == len(paused[0].data["packages"])
    assert events[0].data["by"] == "family_link"
    # Hearth's page: why each app is held, and its name (a guess from the package when none is known)
    from custom_components.hearth.websocket import _sync_view

    household = hass.config_entries.async_entries(DOMAIN)[0].runtime_data.household
    status = _sync_view(household, "person.sam")["family_link"]
    assert status["why"]["com.thesiegs.hearthtube"] == "budget"
    assert status["names"]["com.thesiegs.hearthtube"] and "." not in status["names"]["com.thesiegs.hearthtube"]

    await _bonus(hass, "video", 15)
    assert len(resumed) == 1
    assert sorted(resumed[0].data["packages"]) == sorted(paused[0].data["packages"])
    await _bonus(hass, "video", 15)  # nothing more to do
    assert len(paused) == 1 and len(resumed) == 1


async def test_what_s_held_shows_at_once_and_the_integration_is_read_again_soon(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator, freezer
) -> None:
    paused, resumed = _family_link(hass)
    refreshed = async_mock_service(hass, "homeassistant", "update_entity")
    await _household_with_sam(hass, hass_client_no_auth)
    await _option(hass, "enforce", {"person": "person.sam", "family_link": FAMILY_LINK})
    hass.states.async_set(FAMILY_LINK, "0", {"unit_of_measurement": "min"})
    household = hass.config_entries.async_entries(DOMAIN)[0].runtime_data.household
    writes: list[str] = []
    sensor = "sensor.hearth_sam_held_by_parental_controls"
    household.enforcement.on_applied = lambda: writes.append(hass.states.get(sensor).state)

    await _budget(hass, "video", 10)
    # The held sensor said so when the call returned, before anything else recomputed
    assert writes and int(writes[0]) == len(paused[0].data["packages"])
    assert refreshed == []
    freezer.tick(timedelta(seconds=11))
    async_fire_time_changed(hass)
    await hass.async_block_till_done()
    assert [c.data["entity_id"] for c in refreshed] == [FAMILY_LINK]

    # Let go: the sensor empties at once, one more refresh, and no more after it
    await _bonus(hass, "video", 30)
    assert int(writes[-1]) == 0
    for _ in range(3):
        freezer.tick(timedelta(seconds=11))
        async_fire_time_changed(hass)
        await hass.async_block_till_done()
    assert len(refreshed) == 2


async def test_a_negative_bonus_takes_time_away(hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator) -> None:
    paused, _ = _family_link(hass)
    await _household_with_sam(hass, hass_client_no_auth)
    await _option(hass, "enforce", {"person": "person.sam", "family_link": FAMILY_LINK})
    await _budget(hass, "video", 60)  # 10 watched: 50 left
    assert not paused

    await _bonus(hass, "video", -120)  # none left today, though no bonus was given before
    bonus = next(s for s in hass.states.async_all("number") if s.entity_id.endswith("_video_bonus_today"))
    assert float(bonus.state) == -120
    assert len(paused) == 1


async def test_family_safety_locks_xbox_while_games_are_out_of_time(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator
) -> None:
    locked = async_mock_service(hass, "microsoft_family_safety", "lock_platform")
    unlocked = async_mock_service(hass, "microsoft_family_safety", "unlock_platform")
    hass.states.async_set(FAMILY_SAFETY, "Sam", {"user_id": 123456})
    await _household_with_sam(hass, hass_client_no_auth)
    await _option(hass, "enforce", {"person": "person.sam", "family_safety": FAMILY_SAFETY})

    await _budget(hass, "video", 5)  # not a group Family Safety holds for
    assert locked == []
    await _budget(hass, "games", 5)
    assert len(locked) == 1
    # By the chosen entity, until the next local midnight
    assert locked[0].data["entity_id"] == FAMILY_SAFETY
    assert "account_id" not in locked[0].data
    assert locked[0].data["platform"] == "Xbox"
    until = dt_util.parse_datetime(locked[0].data["until"])
    assert until == enforce.next_midnight() and until.tzinfo is not None

    await _bonus(hass, "games", 30)
    assert [c.data["platform"] for c in unlocked] == ["Xbox"]
    assert unlocked[0].data["entity_id"] == FAMILY_SAFETY


def _older_family_safety(hass: HomeAssistant) -> tuple[list[ServiceCall], list[ServiceCall]]:
    """Family Safety before entity_id and until: account_id and duration_hours only."""
    locked: list[ServiceCall] = []
    unlocked: list[ServiceCall] = []

    async def lock(call: ServiceCall) -> None:
        locked.append(call)

    async def unlock(call: ServiceCall) -> None:
        unlocked.append(call)

    platform = vol.In(["Windows", "Xbox", "Mobile"])
    hass.services.async_register(
        "microsoft_family_safety",
        "lock_platform",
        lock,
        schema=vol.Schema(
            {vol.Required("account_id"): str, vol.Required("platform"): platform, vol.Optional("duration_hours"): int}
        ),
    )
    hass.services.async_register(
        "microsoft_family_safety",
        "unlock_platform",
        unlock,
        schema=vol.Schema({vol.Required("account_id"): str, vol.Required("platform"): platform}),
    )
    return locked, unlocked


async def test_an_older_family_safety_is_called_as_before(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator
) -> None:
    locked, unlocked = _older_family_safety(hass)
    hass.states.async_set(FAMILY_SAFETY, "Sam", {"user_id": 123456})
    await _household_with_sam(hass, hass_client_no_auth)
    await _option(hass, "enforce", {"person": "person.sam", "family_safety": FAMILY_SAFETY})

    await _budget(hass, "games", 5)
    assert len(locked) == 1
    assert locked[0].data["account_id"] == "123456"
    assert 1 <= locked[0].data["duration_hours"] <= 24
    assert "until" not in locked[0].data
    await _bonus(hass, "games", 30)
    assert [(c.data["account_id"], c.data["platform"]) for c in unlocked] == [("123456", "Xbox")]
    held = hass.states.get("sensor.hearth_sam_held_by_parental_controls")
    assert held.state == "0"


async def test_a_typed_in_account_id_stays_an_account_id(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator
) -> None:
    locked = async_mock_service(hass, "microsoft_family_safety", "lock_platform")
    async_mock_service(hass, "microsoft_family_safety", "unlock_platform")
    await _household_with_sam(hass, hass_client_no_auth)
    await _add_enforcer(hass, {"kind": "family_safety", "person": "person.sam", "entity_id": "987654"})
    await _budget(hass, "games", 5)
    assert locked[0].data["account_id"] == "987654"
    assert "entity_id" not in locked[0].data
    assert "until" in locked[0].data


@pytest.mark.parametrize("applied", ["hold_expired", "left_parent_override", "not_locked"])
async def test_an_unlock_with_nothing_left_to_undo_is_fine(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator, applied: str
) -> None:
    async def lock(call: ServiceCall):
        return {"prior": None, "applied": {"until": call.data["until"]}}

    async def unlock(call: ServiceCall):
        return {"prior": None, "applied": applied}

    for name, handler in (("lock_platform", lock), ("unlock_platform", unlock)):
        hass.services.async_register(
            "microsoft_family_safety", name, handler, supports_response=SupportsResponse.OPTIONAL
        )
    hass.states.async_set(FAMILY_SAFETY, "Sam", {"user_id": 123456})
    await _household_with_sam(hass, hass_client_no_auth)
    await _option(hass, "enforce", {"person": "person.sam", "family_safety": FAMILY_SAFETY})
    await _budget(hass, "games", 5)
    held = hass.states.get("sensor.hearth_sam_held_by_parental_controls")
    assert held.attributes["family_safety"]["held"] == ["Xbox"]
    await _bonus(hass, "games", 30)
    held = hass.states.get("sensor.hearth_sam_held_by_parental_controls")
    assert held.state == "0"
    assert "family_safety" not in held.attributes or held.attributes["family_safety"]["error"] is None


def _family_safety_apps(hass: HomeAssistant):
    async_mock_service(hass, "microsoft_family_safety", "lock_platform")
    async_mock_service(hass, "microsoft_family_safety", "unlock_platform")
    return (
        async_mock_service(hass, "microsoft_family_safety", "pause_app"),
        async_mock_service(hass, "microsoft_family_safety", "resume_app"),
    )


async def test_a_group_s_xbox_apps_are_paused_through_family_safety(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator
) -> None:
    paused, resumed = _family_safety_apps(hass)
    fl_paused, _ = _family_link(hass)
    hass.states.async_set(FAMILY_SAFETY, "Sam", {"user_id": 123456})
    await _household_with_sam(hass, hass_client_no_auth)
    # Video lists an Xbox app and a Windows one; Sam's Family Safety holds Xbox only
    await _option(hass, "group_apps", {"video": ["x:videoapp", "win32:player"], "games": []})
    await _option(
        hass, "enforce", {"person": "person.sam", "family_safety": FAMILY_SAFETY, "family_link": FAMILY_LINK}
    )

    await _budget(hass, "video", 10)  # out of time; Games (the platform lock's) isn't
    assert [c.data for c in paused] == [{"entity_id": FAMILY_SAFETY, "apps": ["x:videoapp"]}]
    # Family Link never gets an Xbox or Windows app
    assert fl_paused and not any(":" in p for p in fl_paused[0].data["packages"])
    held = hass.states.get("sensor.hearth_sam_held_by_parental_controls")
    assert held.attributes["family_safety"]["held"] == ["x:videoapp"]

    await _bonus(hass, "video", 30)
    assert [c.data for c in resumed] == [{"entity_id": FAMILY_SAFETY, "apps": ["x:videoapp"]}]


async def test_an_app_on_a_locked_platform_isn_t_paused_too(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator
) -> None:
    paused, _ = _family_safety_apps(hass)
    hass.states.async_set(FAMILY_SAFETY, "Sam", {"user_id": 123456})
    await _household_with_sam(hass, hass_client_no_auth)
    await _option(hass, "group_apps", {"video": [], "games": ["x:gameapp"]})
    await _option(hass, "enforce", {"person": "person.sam", "family_safety": FAMILY_SAFETY})
    await _budget(hass, "games", 5)
    held = hass.states.get("sensor.hearth_sam_held_by_parental_controls")
    assert held.attributes["family_safety"]["held"] == ["Xbox"]
    assert paused == []


async def test_an_older_family_safety_holds_platforms_only(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator
) -> None:
    locked = async_mock_service(hass, "microsoft_family_safety", "lock_platform")
    async_mock_service(hass, "microsoft_family_safety", "unlock_platform")
    hass.states.async_set(FAMILY_SAFETY, "Sam", {"user_id": 123456})
    await _household_with_sam(hass, hass_client_no_auth)
    await _option(hass, "group_apps", {"video": ["x:videoapp"], "games": []})
    await _option(hass, "enforce", {"person": "person.sam", "family_safety": FAMILY_SAFETY})
    await _budget(hass, "video", 10)
    held = hass.states.get("sensor.hearth_sam_held_by_parental_controls")
    assert held.state == "0" and "family_safety" not in held.attributes
    assert locked == []


async def test_family_safety_apps_are_offered_in_the_app_pickers(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator
) -> None:
    hass.states.async_set(
        "sensor.sam_screen_time",
        "30",
        {
            "user_id": "123456",
            "apps": [
                {"package": "x:gameapp", "name": "A Game", "minutes": 20, "platform": "xbox"},
                {"package": "appx:Example.Paint", "name": "Paint", "minutes": 10, "platform": "windows"},
                {"package": "a:com.example.phone", "name": "Phone app", "minutes": 0, "platform": "mobile"},
            ],
        },
    )
    hass.states.async_set(FAMILY_SAFETY, "Sam", {"user_id": 123456})
    await _household_with_sam(hass, hass_client_no_auth)
    household = hass.config_entries.async_entries(DOMAIN)[0].runtime_data.household
    assert "x:gameapp" not in household.known_apps()  # nobody's Family Safety yet
    await _option(hass, "enforce", {"person": "person.sam", "family_safety": FAMILY_SAFETY})
    household = hass.config_entries.async_entries(DOMAIN)[0].runtime_data.household
    known = household.known_apps()
    assert known["x:gameapp"] == "A Game (Xbox)"
    assert known["appx:Example.Paint"] == "Paint (Windows)"
    assert "a:com.example.phone" not in known


async def test_nothing_is_let_go_right_after_a_start(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator, monkeypatch
) -> None:
    paused, resumed = _family_link(hass)
    await _household_with_sam(hass, hass_client_no_auth)
    await _option(hass, "enforce", {"person": "person.sam", "family_link": FAMILY_LINK})
    await _budget(hass, "video", 10)
    assert len(paused) == 1

    monkeypatch.setattr(enforce, "SETTLE", timedelta(hours=1))
    await _bonus(hass, "video", 15)
    assert resumed == []
    monkeypatch.setattr(enforce, "SETTLE", timedelta(0))
    await _bonus(hass, "video", 1)
    assert len(resumed) == 1


async def test_stopping_lets_go_of_what_was_held(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator
) -> None:
    paused, resumed = _family_link(hass)
    await _household_with_sam(hass, hass_client_no_auth)
    await _option(hass, "enforce", {"person": "person.sam", "family_link": FAMILY_LINK})
    await _budget(hass, "video", 10)
    assert len(paused) == 1

    await _option(hass, "enforce", {"person": "person.sam"})
    assert len(resumed) == 1
    assert resumed[0].data["entity_id"] == FAMILY_LINK
    assert hass.states.get("sensor.hearth_sam_held_by_parental_controls").state == "0"


async def test_a_failure_is_shown_and_tried_again(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator, monkeypatch
) -> None:
    calls: list[ServiceCall] = []

    async def failing(call: ServiceCall) -> None:
        calls.append(call)
        raise HomeAssistantError("Google said no")

    hass.services.async_register("familylink", "pause_app", failing)
    async_mock_service(hass, "familylink", "resume_app")
    await _household_with_sam(hass, hass_client_no_auth)
    await _option(hass, "enforce", {"person": "person.sam", "family_link": FAMILY_LINK})
    await _budget(hass, "video", 10)
    assert len(calls) == 1
    held = hass.states.get("sensor.hearth_sam_held_by_parental_controls")
    assert held.attributes["family_link"]["error"] == "Google said no"

    await _bonus(hass, "video", -1)  # a recompute: too soon to try again
    assert len(calls) == 1
    monkeypatch.setattr(enforce, "RETRY", timedelta(0))
    await _bonus(hass, "video", -1)
    assert len(calls) == 2


async def test_a_sync_error_clears_once_there_s_nothing_to_hold(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator
) -> None:
    async def failing(call: ServiceCall) -> None:
        raise HomeAssistantError("Google said no")

    hass.services.async_register("familylink", "pause_app", failing)
    async_mock_service(hass, "familylink", "resume_app")
    await _household_with_sam(hass, hass_client_no_auth)
    await _option(hass, "enforce", {"person": "person.sam", "family_link": FAMILY_LINK})
    await _budget(hass, "video", 10)
    household = hass.config_entries.async_entries(DOMAIN)[0].runtime_data.household
    assert household.enforcement.status_of("person.sam")["family_link"]["last"]["error"] == "Google said no"

    await _bonus(hass, "video", 30)  # time again: nothing to hold, nothing to retry
    status = household.enforcement.status_of("person.sam")["family_link"]
    assert status["error"] is None and "error" not in status["last"]
    assert "error" not in hass.states.get("sensor.hearth_sam_held_by_parental_controls").attributes.get("family_link", {})


def test_a_sync_error_older_than_a_day_isn_t_news() -> None:
    from custom_components.hearth.glance import _sync_items

    now = dt_util.now()
    sync = {"family_safety": {"held": [], "error": None, "last": {"at": (now - timedelta(days=2)).isoformat(), "error": "Xbox said no"}}}
    assert _sync_items(sync, now) == []
    sync["family_safety"]["last"]["at"] = (now - timedelta(hours=2)).isoformat()
    assert [i["text"] for i in _sync_items(sync, now)] == ["family safety · didn't take"]


def test_essential_apps_are_never_held():
    assert essential("com.google.android.apps.messaging")
    assert essential("com.android.phone")
    assert not essential("com.netflix.mediaclient")


def test_a_lock_lasts_until_midnight():
    zone = dt_util.get_default_time_zone()
    assert hours_to_midnight(datetime(2026, 10, 26, 20, 30, tzinfo=zone)) == 4
    assert hours_to_midnight(datetime(2026, 10, 26, 23, 50, tzinfo=zone)) == 1
    assert hours_to_midnight(datetime(2026, 10, 26, 0, 0, 1, tzinfo=zone)) == 24


NINTENDO_LIMIT = "number.sam_s_switch_max_screentime_today"
NINTENDO_SUSPEND = "switch.sam_s_switch_suspend_software"
NINTENDO_MODE = "select.sam_s_switch_restriction_mode"


def _nintendo_switch(hass: HomeAssistant, limit: str = "120", suspend: str = "off", mode: str = "daily") -> None:
    """A Switch as Nintendo Switch Parental Controls makes it: one device, its entities keyed by the device id."""
    from homeassistant.helpers import device_registry as dr, entity_registry as er
    from pytest_homeassistant_custom_component.common import MockConfigEntry

    nintendo = MockConfigEntry(domain="nintendo_parental_controls")
    nintendo.add_to_hass(hass)
    device = dr.async_get(hass).async_get_or_create(
        config_entry_id=nintendo.entry_id, identifiers={("nintendo_parental_controls", "abc123")}, name="Sam's Switch"
    )
    registry = er.async_get(hass)
    for entity_id, key, state in (
        (NINTENDO_LIMIT, "today_max_screentime", limit),
        (NINTENDO_SUSPEND, "suspend_software", suspend),
        (NINTENDO_MODE, "timer_mode", mode),
    ):
        domain, object_id = entity_id.split(".")
        registry.async_get_or_create(
            domain, "nintendo_parental_controls", f"abc123_{key}", device_id=device.id, suggested_object_id=object_id
        )
        hass.states.async_set(entity_id, state)


def _nintendo_services(hass: HomeAssistant):
    """After the household is set up: Hearth's number platform brings number.set_value of its own."""
    return (
        async_mock_service(hass, "number", "set_value"),
        async_mock_service(hass, "switch", "turn_on"),
        async_mock_service(hass, "switch", "turn_off"),
    )


async def test_nintendo_suspends_the_switch_while_games_are_out_of_time(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator, freezer
) -> None:
    freezer.move_to(dt_util.now().replace(hour=12, minute=0))
    _nintendo_switch(hass)
    await _household_with_sam(hass, hass_client_no_auth)
    set_value, turned_on, turned_off = _nintendo_services(hass)
    await _option(hass, "enforce", {"person": "person.sam", "nintendo": NINTENDO_LIMIT})
    events = async_capture_events(hass, "hearth_enforced")

    await _budget(hass, "video", 5)  # not a group Nintendo holds for
    assert set_value == []
    await _budget(hass, "games", 5)
    assert [c.data for c in turned_on] == [{"entity_id": NINTENDO_SUSPEND}]
    assert [c.data for c in set_value] == [{"entity_id": NINTENDO_LIMIT, "value": 0}]
    held = hass.states.get("sensor.hearth_sam_held_by_parental_controls")
    assert held.state == "1"
    assert held.attributes["nintendo"]["held"] == ["Switch"]
    assert events[-1].data["by"] == "nintendo"

    # What Nintendo then says: 0 minutes today. Letting go puts back what it was, not that
    hass.states.async_set(NINTENDO_LIMIT, "0")
    hass.states.async_set(NINTENDO_SUSPEND, "on")
    await _bonus(hass, "games", 30)
    assert set_value[-1].data == {"entity_id": NINTENDO_LIMIT, "value": 120}
    assert [c.data for c in turned_off] == [{"entity_id": NINTENDO_SUSPEND}]
    assert hass.states.get("sensor.hearth_sam_held_by_parental_controls").state == "0"


async def test_nintendo_waits_out_bonus_time_given_in_the_nintendo_app(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator, freezer
) -> None:
    """The Switch refuses a new limit while bonus time runs: no calls then, and a clear reason."""
    freezer.move_to(dt_util.now().replace(hour=12, minute=0))
    _nintendo_switch(hass)
    hass.states.async_set("sensor.sam_s_switch_time_extended", "15")
    await _household_with_sam(hass, hass_client_no_auth)
    set_value, turned_on, _ = _nintendo_services(hass)
    await _option(hass, "enforce", {"person": "person.sam", "nintendo": NINTENDO_LIMIT})
    await _budget(hass, "games", 5)
    assert set_value == [] and turned_on == []
    held = hass.states.get("sensor.hearth_sam_held_by_parental_controls")
    assert "bonus time" in held.attributes["nintendo"]["error"]


async def test_a_shared_switch_is_held_only_while_its_kid_is_playing(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator, freezer
) -> None:
    """Out of time on a Switch others share: held while Sam is the one playing, let go when Sam isn't."""
    freezer.move_to(dt_util.now().replace(hour=12, minute=0))
    _nintendo_switch(hass)
    playing = "binary_sensor.sam_s_switch_sam_playing"
    hass.states.async_set(playing, "off")
    await _household_with_sam(hass, hass_client_no_auth)
    set_value, turned_on, _ = _nintendo_services(hass)
    await _option(
        hass, "enforce", {"person": "person.sam", "nintendo": NINTENDO_LIMIT, "nintendo_playing": [playing]}
    )
    await _budget(hass, "games", 5)
    # Out of time, but someone else is playing: the Switch is theirs
    assert set_value == [] and turned_on == []

    hass.states.async_set(playing, "on")
    await hass.async_block_till_done()
    assert set_value[-1].data == {"entity_id": NINTENDO_LIMIT, "value": 0}

    freezer.tick(timedelta(minutes=5))
    hass.states.async_set(NINTENDO_LIMIT, "0")
    hass.states.async_set(playing, "off")
    await hass.async_block_till_done()
    assert set_value[-1].data == {"entity_id": NINTENDO_LIMIT, "value": 120}


async def test_nintendo_leaves_suspend_software_on_when_it_was(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator, freezer
) -> None:
    freezer.move_to(dt_util.now().replace(hour=12, minute=0))
    _nintendo_switch(hass, limit="-1", suspend="on")
    await _household_with_sam(hass, hass_client_no_auth)
    set_value, turned_on, turned_off = _nintendo_services(hass)
    await _option(hass, "enforce", {"person": "person.sam", "nintendo": NINTENDO_LIMIT})
    await _budget(hass, "all", 5)  # All screen time holds it too
    assert turned_on == []
    assert set_value[-1].data["value"] == 0
    await _bonus(hass, "all", 30)
    assert set_value[-1].data["value"] == -1  # no limit, as it was
    assert turned_off == []


async def test_nintendo_s_limit_is_put_back_after_a_restart(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator, freezer
) -> None:
    freezer.move_to(dt_util.now().replace(hour=12, minute=0))
    _nintendo_switch(hass, limit="90")
    await _household_with_sam(hass, hass_client_no_auth)
    set_value, _turned_on, turned_off = _nintendo_services(hass)
    await _option(hass, "enforce", {"person": "person.sam", "nintendo": NINTENDO_LIMIT})
    await _budget(hass, "games", 5)
    assert set_value[-1].data["value"] == 0
    hass.states.async_set(NINTENDO_LIMIT, "0")

    entry = hass.config_entries.async_entries(DOMAIN)[0]
    assert await hass.config_entries.async_reload(entry.entry_id)
    await hass.async_block_till_done()
    await _bonus(hass, "games", 30)
    assert set_value[-1].data == {"entity_id": NINTENDO_LIMIT, "value": 90}
    assert len(turned_off) == 1


async def test_nintendo_lets_go_just_before_midnight(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator, freezer
) -> None:
    """A Switch's limit is a setting of every day (or of this weekday): it's put back while it's still today's."""
    freezer.move_to(dt_util.now().replace(hour=23, minute=50))
    _nintendo_switch(hass, mode="each_day_of_the_week")
    await _household_with_sam(hass, hass_client_no_auth)
    set_value, _turned_on, _turned_off = _nintendo_services(hass)
    await _option(hass, "enforce", {"person": "person.sam", "nintendo": NINTENDO_LIMIT})
    await _budget(hass, "games", 5)
    assert set_value[-1].data["value"] == 0

    freezer.move_to(dt_util.now().replace(hour=23, minute=59))
    await _bonus(hass, "games", 0)  # a recompute
    assert set_value[-1].data["value"] == 120


def test_a_weekday_held_past_midnight_is_put_back_with_its_bedtime():
    from custom_components.hearth.enforce import _held_weekday_call

    restore = {"device_id": "dev1", "weekday": "friday", "bedtime_alarm": "21:00:00", "bedtime_end_time": "07:00:00"}
    assert _held_weekday_call(restore, 90) == {
        "device_id": "dev1",
        "day_of_week": "friday",
        "max_play_time": 90,
        "bedtime_start": "21:00:00",
        "bedtime_end": "07:00:00",
    }
    # No limit (-1) and bedtime off (00:00): both left out, as the service reads them
    off = {**restore, "bedtime_alarm": "00:00:00"}
    assert _held_weekday_call(off, -1) == {"device_id": "dev1", "day_of_week": "friday"}
    assert _held_weekday_call({"weekday": "friday"}, 90) is None


async def test_a_failed_nintendo_hold_keeps_the_limit_it_found_first(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator, freezer, monkeypatch
) -> None:
    freezer.move_to(dt_util.now().replace(hour=12, minute=0))
    calls: list[ServiceCall] = []

    async def failing(call: ServiceCall) -> None:
        calls.append(call)
        raise HomeAssistantError("Nintendo said no")

    _nintendo_switch(hass)
    await _household_with_sam(hass, hass_client_no_auth)
    hass.services.async_register("number", "set_value", failing)
    async_mock_service(hass, "switch", "turn_on")
    async_mock_service(hass, "switch", "turn_off")
    await _option(hass, "enforce", {"person": "person.sam", "nintendo": NINTENDO_LIMIT})
    await _budget(hass, "games", 5)
    held = hass.states.get("sensor.hearth_sam_held_by_parental_controls")
    assert held.attributes["nintendo"]["error"] == "Nintendo said no"

    # Half done, as if the 0 had reached Nintendo: the retry and the let-go still use the 120 found first
    hass.states.async_set(NINTENDO_LIMIT, "0")
    hass.services.async_remove("number", "set_value")
    set_value = async_mock_service(hass, "number", "set_value")
    monkeypatch.setattr(enforce, "RETRY", timedelta(0))
    await _bonus(hass, "games", 30)
    assert [c.data["value"] for c in set_value] == [120]


async def _pause(hass: HomeAssistant, **data) -> None:
    await hass.services.async_call(DOMAIN, "pause", {"people": ["person.sam"], **data}, blocking=True)
    await hass.async_block_till_done()


async def _pause_end(hass: HomeAssistant, **data) -> None:
    await hass.services.async_call(DOMAIN, "pause_end", {"people": ["person.sam"], **data}, blocking=True)
    await hass.async_block_till_done()


async def test_a_family_pause_holds_the_switch_until_it_ends(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator, freezer
) -> None:
    freezer.move_to(dt_util.now().replace(hour=18, minute=0))
    _nintendo_switch(hass, limit="90")
    await _household_with_sam(hass, hass_client_no_auth)
    set_value, turned_on, turned_off = _nintendo_services(hass)
    await _option(hass, "enforce", {"person": "person.sam", "nintendo": NINTENDO_LIMIT})
    assert set_value == []

    # Time left in every group, but a family pause: the Switch is held as for a budget
    await _pause(hass, minutes=45, reason="Dinner")
    assert [c.data for c in turned_on] == [{"entity_id": NINTENDO_SUSPEND}]
    assert [c.data for c in set_value] == [{"entity_id": NINTENDO_LIMIT, "value": 0}]
    held = hass.states.get("sensor.hearth_sam_held_by_parental_controls")
    assert held.attributes["nintendo"]["held"] == ["Switch"]

    # The pause ends: the limit and Suspend software go back as they were
    hass.states.async_set(NINTENDO_LIMIT, "0")
    hass.states.async_set(NINTENDO_SUSPEND, "on")
    await _pause_end(hass)
    assert set_value[-1].data == {"entity_id": NINTENDO_LIMIT, "value": 90}
    assert [c.data for c in turned_off] == [{"entity_id": NINTENDO_SUSPEND}]

    # On its own, it ends when its time is up (the minute's recompute)
    hass.states.async_set(NINTENDO_LIMIT, "90")
    hass.states.async_set(NINTENDO_SUSPEND, "off")
    await _pause(hass, minutes=10)
    assert set_value[-1].data["value"] == 0
    hass.states.async_set(NINTENDO_LIMIT, "0")
    freezer.tick(timedelta(minutes=11))
    await _bonus(hass, "games", 0)  # a recompute
    assert set_value[-1].data == {"entity_id": NINTENDO_LIMIT, "value": 90}


async def test_a_pause_of_games_holds_the_switch_and_a_pause_of_video_doesn_t(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator, freezer
) -> None:
    freezer.move_to(dt_util.now().replace(hour=16, minute=0))
    _nintendo_switch(hass)
    await _household_with_sam(hass, hass_client_no_auth)
    set_value, _turned_on, _turned_off = _nintendo_services(hass)
    await _option(hass, "enforce", {"person": "person.sam", "nintendo": NINTENDO_LIMIT})

    await _pause(hass, group="video", minutes=30, reason="Homework")
    assert set_value == []
    await _pause(hass, group="games", minutes=30, reason="Homework")
    assert [c.data["value"] for c in set_value] == [0]
    # An allow doesn't lift a pause
    await hass.services.async_call(
        DOMAIN, "allow", {"people": ["person.sam"], "group": "games"}, blocking=True, return_response=True
    )
    await hass.async_block_till_done()
    assert [c.data["value"] for c in set_value] == [0]

    hass.states.async_set(NINTENDO_LIMIT, "0")
    await _pause_end(hass, group="video")
    assert [c.data["value"] for c in set_value] == [0]
    await _pause_end(hass, group="games")
    assert [c.data["value"] for c in set_value] == [0, 120]


async def test_a_paused_kid_s_shared_switch_is_held_only_while_they_are_playing(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator, freezer
) -> None:
    freezer.move_to(dt_util.now().replace(hour=18, minute=0))
    _nintendo_switch(hass)
    playing = "binary_sensor.sam_s_switch_sam_playing"
    hass.states.async_set(playing, "off")
    await _household_with_sam(hass, hass_client_no_auth)
    set_value, _turned_on, _turned_off = _nintendo_services(hass)
    await _option(
        hass, "enforce", {"person": "person.sam", "nintendo": NINTENDO_LIMIT, "nintendo_playing": [playing]}
    )
    await _pause(hass, minutes=60)
    # Someone else is playing: the Switch is theirs
    assert set_value == []
    hass.states.async_set(playing, "on")
    await hass.async_block_till_done()
    assert [c.data["value"] for c in set_value] == [0]


async def test_a_pause_lets_go_of_the_switch_just_before_midnight(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator, freezer
) -> None:
    """A pause past midnight: the Switch's limit is the weekday's setting, so it goes back while it's still today's."""
    freezer.move_to(dt_util.now().replace(hour=23, minute=40))
    _nintendo_switch(hass, mode="each_day_of_the_week")
    await _household_with_sam(hass, hass_client_no_auth)
    set_value, _turned_on, _turned_off = _nintendo_services(hass)
    await _option(hass, "enforce", {"person": "person.sam", "nintendo": NINTENDO_LIMIT})
    await _pause(hass, minutes=60)
    assert [c.data["value"] for c in set_value] == [0]
    hass.states.async_set(NINTENDO_LIMIT, "0")
    freezer.move_to(dt_util.now().replace(hour=23, minute=59))
    await _bonus(hass, "games", 0)  # a recompute
    assert [c.data["value"] for c in set_value] == [0, 120]


async def test_a_switch_s_used_screen_time_is_games_by_itself(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator
) -> None:
    from homeassistant.helpers import entity_registry as er

    used = "sensor.sam_s_switch_used_screen_time"
    er.async_get(hass).async_get_or_create(
        "sensor", "nintendo_parental_controls", "abc123_playing_time", suggested_object_id="sam_s_switch_used_screen_time"
    )
    hass.states.async_set(used, "40", {"unit_of_measurement": "min"})
    await _household_with_sam(hass, hass_client_no_auth)
    await _option(hass, "add_source", {"entity_id": used, "person": "person.sam"})
    entry = hass.config_entries.async_entries(DOMAIN)[0]
    assert entry.options["sources"][0]["group"] == "games"
    assert hass.states.get("sensor.hearth_sam_games_today").state == "45"  # 5 on the TV, 40 on the Switch


async def test_all_screen_time_knows_every_app_of_theirs(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator
) -> None:
    await _household_with_sam(hass, hass_client_no_auth)
    # Sam's phone, through Family Link: a chat app no group has
    hass.states.async_set(
        FAMILY_LINK, "15", {"unit_of_measurement": "min", "apps": [{"package": "com.example.chat", "minutes": 15}]}
    )
    await _option(hass, "add_source", {"entity_id": FAMILY_LINK, "person": "person.sam"})
    household = hass.config_entries.async_entries(DOMAIN)[0].runtime_data.household
    packages = household._person_apps(household.days.get("person.sam"), household.membership())
    assert {"com.example.chat", "com.example.game", "com.thesiegs.hearthtube"} <= set(packages)


async def test_all_screen_time_out_locks_the_family_link_devices(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator, freezer
) -> None:
    freezer.move_to(dt_util.now().replace(hour=12, minute=0))
    paused, _resumed = _family_link(hass)
    limits = async_mock_service(hass, "familylink", "set_daily_limit")
    await _household_with_sam(hass, hass_client_no_auth)
    hass.states.async_set(
        FAMILY_LINK,
        "20",
        {"unit_of_measurement": "min", "child_id": "42", "apps": [{"package": "com.example.chat", "minutes": 20}]},
    )
    weekday = enforce.WEEKDAYS[dt_util.now().weekday()]
    hass.states.async_set(f"number.sam_family_link_{weekday}_limit", "120", {"child_id": "42"})
    hass.states.async_set(f"number.alex_family_link_{weekday}_limit", "60", {"child_id": "7"})
    await _option(hass, "add_source", {"entity_id": FAMILY_LINK, "person": "person.sam"})
    await _option(hass, "enforce", {"person": "person.sam", "family_link": FAMILY_LINK})

    await _budget(hass, "all", 30)  # 15 on the TV, 20 on the phone
    # The devices are locked (apps with unlimited time still work), not every app paused
    assert paused == []
    day = dt_util.now().isoweekday()
    assert [c.data for c in limits] == [{"child_id": "42", "daily_minutes": 0, "day": day}]
    held = hass.states.get("sensor.hearth_sam_held_by_parental_controls")
    assert held.attributes["family_link"]["held"] == ["Devices"]

    # Family Link then says 0 for today: letting go puts back what it was
    hass.states.async_set(f"number.sam_family_link_{weekday}_limit", "0", {"child_id": "42"})
    await _bonus(hass, "all", 30)
    assert limits[-1].data == {"child_id": "42", "daily_minutes": 120, "day": day}
    assert hass.states.get("sensor.hearth_sam_held_by_parental_controls").state == "0"


FL_DAILY_LIMIT_SWITCH = "switch.sam_family_link_daily_limit"


async def _family_link_lock_setup(hass: HomeAssistant, hass_client_no_auth, switch: str):
    """Sam's Family Link child (42) with today's limit 120 and the child's Daily Limit switch in [switch]."""
    from homeassistant.helpers import entity_registry as er

    _family_link(hass)
    limits = async_mock_service(hass, "familylink", "set_daily_limit")
    turned_on = async_mock_service(hass, "switch", "turn_on")
    turned_off = async_mock_service(hass, "switch", "turn_off")
    er.async_get(hass).async_get_or_create(
        "switch", "familylink", "familylink_42_daily_limit", suggested_object_id="sam_family_link_daily_limit"
    )
    hass.states.async_set(FL_DAILY_LIMIT_SWITCH, switch, {"child_id": "42"})
    await _household_with_sam(hass, hass_client_no_auth)
    hass.states.async_set(
        FAMILY_LINK,
        "20",
        {"unit_of_measurement": "min", "child_id": "42", "apps": [{"package": "com.example.chat", "minutes": 20}]},
    )
    weekday = enforce.WEEKDAYS[dt_util.now().weekday()]
    hass.states.async_set(f"number.sam_family_link_{weekday}_limit", "120", {"child_id": "42"})
    await _option(hass, "add_source", {"entity_id": FAMILY_LINK, "person": "person.sam"})
    await _option(hass, "enforce", {"person": "person.sam", "family_link": FAMILY_LINK})
    return limits, turned_on, turned_off, weekday


async def test_a_lock_switches_family_link_s_daily_limit_on_and_off_again(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator, freezer
) -> None:
    """Daily limits switched off: set_daily_limit alone locks nothing, so Hearth switches them on for the hold."""
    freezer.move_to(dt_util.now().replace(hour=12, minute=0))
    limits, turned_on, turned_off, weekday = await _family_link_lock_setup(hass, hass_client_no_auth, "off")
    day = dt_util.now().isoweekday()

    await _budget(hass, "all", 30)
    assert [c.data for c in turned_on] == [{"entity_id": FL_DAILY_LIMIT_SWITCH}]
    assert [c.data for c in limits] == [{"child_id": "42", "daily_minutes": 0, "day": day}]
    hass.states.async_set(FL_DAILY_LIMIT_SWITCH, "on", {"child_id": "42"})
    hass.states.async_set(f"number.sam_family_link_{weekday}_limit", "0", {"child_id": "42"})

    await _bonus(hass, "all", 30)
    assert limits[-1].data == {"child_id": "42", "daily_minutes": 120, "day": day}
    assert [c.data for c in turned_off] == [{"entity_id": FL_DAILY_LIMIT_SWITCH}]


async def test_a_daily_limit_already_on_stays_on(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator, freezer
) -> None:
    freezer.move_to(dt_util.now().replace(hour=12, minute=0))
    limits, turned_on, turned_off, weekday = await _family_link_lock_setup(hass, hass_client_no_auth, "on")

    await _budget(hass, "all", 30)
    assert turned_on == []
    assert limits[-1].data["daily_minutes"] == 0
    hass.states.async_set(f"number.sam_family_link_{weekday}_limit", "0", {"child_id": "42"})
    await _bonus(hass, "all", 30)
    assert limits[-1].data["daily_minutes"] == 120
    assert turned_off == []


async def test_the_switched_on_daily_limit_goes_off_after_a_restart(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator, freezer
) -> None:
    freezer.move_to(dt_util.now().replace(hour=12, minute=0))
    limits, turned_on, turned_off, weekday = await _family_link_lock_setup(hass, hass_client_no_auth, "off")
    await _budget(hass, "all", 30)
    assert len(turned_on) == 1
    hass.states.async_set(FL_DAILY_LIMIT_SWITCH, "on", {"child_id": "42"})
    hass.states.async_set(f"number.sam_family_link_{weekday}_limit", "0", {"child_id": "42"})

    entry = hass.config_entries.async_entries(DOMAIN)[0]
    assert await hass.config_entries.async_reload(entry.entry_id)
    await hass.async_block_till_done()
    await _bonus(hass, "all", 30)
    assert limits[-1].data["daily_minutes"] == 120
    assert len(turned_on) == 1  # the switch was on: nothing to switch on again
    assert [c.data for c in turned_off] == [{"entity_id": FL_DAILY_LIMIT_SWITCH}]


async def test_a_group_outside_all_screen_time_isn_t_held_by_it(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator
) -> None:
    await _household_with_sam(hass, hass_client_no_auth)
    household = hass.config_entries.async_entries(DOMAIN)[0].runtime_data.household
    entry = hass.config_entries.async_entries(DOMAIN)[0]
    hass.config_entries.async_update_entry(
        entry,
        options={
            **entry.options,
            "groups": [{"id": "music", "name": "Music", "apps": ["com.example.music"]}],
            "outside_all": ["music"],
        },
    )
    await hass.async_block_till_done()
    household = hass.config_entries.async_entries(DOMAIN)[0].runtime_data.household
    assert household.outside_all() == {"music", "messaging"}
    assert household.group_packages()["music"] == ["com.example.music"]
    assert "com.example.music" not in household._person_apps(household.days.get("person.sam"), household.membership())


async def test_family_link_never_pauses_an_app_with_unlimited_time(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator
) -> None:
    paused, _resumed = _family_link(hass)
    await _household_with_sam(hass, hass_client_no_auth)
    hass.states.async_set(FAMILY_LINK, "0", {"unit_of_measurement": "min", "child_id": "42"})
    hass.states.async_set(
        "sensor.sam_family_link_always_allowed_apps",
        "1",
        {"child_id": "42", "apps": [{"name": "HearthTube", "package": "com.thesiegs.hearthtube"}]},
    )
    await _option(hass, "enforce", {"person": "person.sam", "family_link": FAMILY_LINK})

    await _budget(hass, "video", 10)
    assert len(paused) == 1
    assert "com.thesiegs.hearthtube" not in paused[0].data["packages"]


async def test_a_reload_does_not_start_the_settle_again(hass: HomeAssistant, freezer) -> None:
    # Saving a setting reloads the entry: a hold due to be let go isn't kept another five minutes
    first = enforce.Enforcement(hass, "entry-1")
    freezer.tick(timedelta(minutes=10))
    again = enforce.Enforcement(hass, "entry-1")
    assert again.started == first.started
    assert again._may_let_go()


def test_two_switches_of_one_kid_are_two_holds() -> None:
    a = enforce.Enforcer(enforce.NINTENDO, "person.sam", "number.switch_a_max_screentime_today")
    b = enforce.Enforcer(enforce.NINTENDO, "person.sam", "number.switch_b_max_screentime_today")
    assert a.key != b.key
    assert enforce.key_parts(a.key) == ("nintendo", "person.sam")
    # Other kinds keep their key
    fl = enforce.Enforcer(enforce.FAMILY_LINK, "person.sam", "sensor.x")
    assert fl.key == "family_link|person.sam" and enforce.key_parts(fl.key) == ("family_link", "person.sam")


async def test_a_kid_on_two_switches_shows_one_nintendo_line(hass: HomeAssistant) -> None:
    held = enforce.Enforcement(hass, "entry-2")
    held.held["nintendo|person.sam|number.a"] = enforce.Held(items={"Switch"})
    held.held["nintendo|person.sam|number.b"] = enforce.Held(items=set(), error="Nintendo said no")
    assert held.held_for("person.sam") == {"nintendo": {"held": ["Switch"], "error": "Nintendo said no"}}
    assert held.status_of("person.sam")["nintendo"]["held"] == ["Switch"]
