"""Keeping Hearth and the first-party apps (Family Link, Nintendo, Family Safety) in step: a parent's change in their
own app is an adult's decision, which Hearth adopts and never overwrites."""

from datetime import timedelta

from homeassistant.core import HomeAssistant, ServiceCall, SupportsResponse
from homeassistant.exceptions import HomeAssistantError
from homeassistant.util import dt as dt_util
from pytest_homeassistant_custom_component.common import async_capture_events, async_mock_service
from pytest_homeassistant_custom_component.typing import ClientSessionGenerator

from custom_components.hearth import enforce
from custom_components.hearth.const import DOMAIN
from test_enforce import (
    FAMILY_LINK,
    FAMILY_SAFETY,
    NINTENDO_LIMIT,
    NINTENDO_SUSPEND,
    _bonus,
    _budget,
    _nintendo_services,
    _nintendo_switch,
    settled,  # noqa: F401 - the fixture
)
from test_people import _household_with_sam
from test_sources import _option

CHILD = "42"


def _weekday_limit() -> str:
    return f"number.sam_family_link_{enforce.WEEKDAYS[dt_util.now().weekday()]}_limit"


async def _sam_with_family_link(hass: HomeAssistant, hass_client_no_auth, limit: str = "120"):
    """Sam with a Family Link phone (its daily limit [limit]), held by Family Link when All screen time runs out."""
    limits = async_mock_service(hass, "familylink", "set_daily_limit")
    await _household_with_sam(hass, hass_client_no_auth)
    hass.states.async_set(
        FAMILY_LINK,
        "20",
        {"unit_of_measurement": "min", "child_id": CHILD, "apps": [{"package": "com.example.chat", "minutes": 20}]},
    )
    hass.states.async_set(_weekday_limit(), limit, {"child_id": CHILD})
    await _option(hass, "add_source", {"entity_id": FAMILY_LINK, "person": "person.sam"})
    await _option(hass, "enforce", {"person": "person.sam", "family_link": FAMILY_LINK})
    return limits


def _household(hass: HomeAssistant):
    return hass.config_entries.async_entries(DOMAIN)[0].runtime_data.household


# A. Compare and restore


async def test_a_daily_limit_a_parent_changed_while_held_is_kept(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator, freezer
) -> None:
    freezer.move_to(dt_util.now().replace(hour=12, minute=0))
    limits = await _sam_with_family_link(hass, hass_client_no_auth)
    events = async_capture_events(hass, "hearth_enforced")
    await _budget(hass, "all", 30)
    assert limits[-1].data["daily_minutes"] == 0

    # A parent sets 90 for today in the Family Link app (seen before Hearth's own 0 even showed)
    household = _household(hass)
    hass.states.async_set(_weekday_limit(), "90", {"child_id": CHILD})
    await _bonus(hass, "all", 30)
    assert len(limits) == 1  # 120 isn't written over the parent's 90
    assert events[-1].data["outcomes"] == {"Devices": "kept_current"}
    status = household.enforcement.status_of("person.sam")["family_link"]
    assert status["last"]["outcomes"] == {"Devices": "kept_current"} and status["last"]["ok"]


async def test_a_daily_limit_still_at_hearth_s_zero_is_put_back(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator, freezer
) -> None:
    freezer.move_to(dt_util.now().replace(hour=12, minute=0))
    limits = await _sam_with_family_link(hass, hass_client_no_auth)
    events = async_capture_events(hass, "hearth_enforced")
    await _budget(hass, "all", 30)
    hass.states.async_set(_weekday_limit(), "0", {"child_id": CHILD})
    await _bonus(hass, "all", 30)
    assert limits[-1].data["daily_minutes"] == 120
    assert events[-1].data["outcomes"] == {"Devices": "restored"}


async def test_a_switch_limit_a_parent_changed_while_held_is_kept(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator, freezer
) -> None:
    freezer.move_to(dt_util.now().replace(hour=12, minute=0))
    _nintendo_switch(hass)
    await _household_with_sam(hass, hass_client_no_auth)
    set_value, _turned_on, turned_off = _nintendo_services(hass)
    await _option(hass, "enforce", {"person": "person.sam", "nintendo": NINTENDO_LIMIT})
    await _budget(hass, "games", 5)
    assert set_value[-1].data["value"] == 0

    hass.states.async_set(NINTENDO_LIMIT, "45")
    hass.states.async_set(NINTENDO_SUSPEND, "on")
    await _bonus(hass, "games", 30)
    assert len(set_value) == 1 and turned_off == []


async def test_family_link_s_resume_answer_is_shown(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator
) -> None:
    """A newer Family Link says what resume_app did (kept_current: a parent's setting stayed)."""
    async_mock_service(hass, "familylink", "pause_app")

    async def resume(call: ServiceCall):
        return {"results": {p: "kept_current" for p in call.data["packages"]}, "kept_current": {}}

    hass.services.async_register("familylink", "resume_app", resume, supports_response=SupportsResponse.OPTIONAL)
    await _household_with_sam(hass, hass_client_no_auth)
    await _option(hass, "enforce", {"person": "person.sam", "family_link": FAMILY_LINK})
    events = async_capture_events(hass, "hearth_enforced")
    await _budget(hass, "video", 10)
    await _bonus(hass, "video", 15)
    assert set(events[-1].data["outcomes"].values()) == {"kept_current"}


# B. Parent grants


async def test_a_parent_grant_lifts_only_its_own_hold_until_ended(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator, freezer
) -> None:
    freezer.move_to(dt_util.now().replace(hour=12, minute=0))
    limits = await _sam_with_family_link(hass, hass_client_no_auth)
    await _budget(hass, "all", 30)
    assert limits[-1].data["daily_minutes"] == 0
    hass.states.async_set(_weekday_limit(), "0", {"child_id": CHILD})
    household = _household(hass)

    grant, new = household.grants.add(
        "person.sam", "family_link", "device", "Devices", dt_util.now() + timedelta(hours=1), "bonus time"
    )
    assert new
    await _bonus(hass, "all", 0)  # a recompute
    assert limits[-1].data["daily_minutes"] == 120  # let go: the lock is lifted
    # Budgets keep counting: All screen time is still out
    assert household.days["person.sam"].limits["all"].minutes_left == 0

    explained = await hass.services.async_call(
        DOMAIN, "explain", {"person": "person.sam", "group": "all"}, blocking=True, return_response=True
    )
    granted = [e for e in explained["exceptions"] if e.get("type") == "grant"]
    assert granted[0]["source"] == "from the Family Link app"
    assert granted[0]["target"] == {"kind": "device", "value": "Devices"}
    assert household.exceptions_of("person.sam")["grants"][0]["id"] == grant.id

    hass.states.async_set(_weekday_limit(), "120", {"child_id": CHILD})
    ended = await hass.services.async_call(
        DOMAIN, "allow_end", {"id": grant.id}, blocking=True, return_response=True
    )
    await hass.async_block_till_done()
    assert ended["ended"] == [grant.id]
    assert limits[-1].data["daily_minutes"] == 0  # held again


async def test_a_grant_ends_by_itself(hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator, freezer) -> None:
    freezer.move_to(dt_util.now().replace(hour=12, minute=0))
    await _sam_with_family_link(hass, hass_client_no_auth)
    household = _household(hass)
    household.grants.add("person.sam", "nintendo", "switch", "Switch", dt_util.utcnow() + timedelta(minutes=5), "x")
    assert household.grants.lifted("person.sam") == {"nintendo": {"Switch"}}
    freezer.tick(timedelta(minutes=6))
    assert household.grants.lifted("person.sam") == {}
    assert household.grants.prune()


# C. Seeing a parent's change


PHONE = "switch.sam_s_phone"


def _phone(hass: HomeAssistant, bonus: int = 0, **extra) -> None:
    """Sam's Family Link phone switch (a newer Family Link's attributes)."""
    hass.states.async_set(
        PHONE,
        "on",
        {"child_id": CHILD, "device_id": "dev1", "device_name": "Sam's phone", "bonus_minutes": bonus, **extra},
    )


async def _settle(hass: HomeAssistant, freezer) -> None:
    """Past the minute in which changes are taken as Hearth's own."""
    freezer.tick(timedelta(minutes=2))
    await hass.async_block_till_done()


async def test_a_daily_limit_raised_in_family_link_becomes_a_grant(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator, freezer
) -> None:
    freezer.move_to(dt_util.now().replace(hour=12, minute=0))
    limits = await _sam_with_family_link(hass, hass_client_no_auth)
    grants = async_capture_events(hass, "hearth_parent_grant")
    await _budget(hass, "all", 30)
    hass.states.async_set(_weekday_limit(), "0", {"child_id": CHILD})  # Hearth's 0 shows
    await _settle(hass, freezer)

    hass.states.async_set(_weekday_limit(), "150", {"child_id": CHILD})  # a parent, in the Family Link app
    await hass.async_block_till_done()
    assert grants[0].data["source"] == "from the Family Link app"
    assert grants[0].data["target"] == {"kind": "device", "value": "Devices"}
    assert grants[0].data["endable"] is False
    assert len(limits) == 1  # nothing written over the parent's 150
    held = hass.states.get("sensor.hearth_sam_held_by_parental_controls")
    assert held.state == "0"


async def test_hearth_s_own_change_is_no_grant(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator, freezer
) -> None:
    """Right after the hold, Family Link still shows the old limit: that's Hearth's change not shown yet."""
    freezer.move_to(dt_util.now().replace(hour=12, minute=0))
    await _sam_with_family_link(hass, hass_client_no_auth)
    grants = async_capture_events(hass, "hearth_parent_grant")
    await _budget(hass, "all", 30)
    hass.states.async_set(_weekday_limit(), "120", {"child_id": CHILD, "seen": 1})
    await _settle(hass, freezer)
    await _bonus(hass, "all", 0)
    assert grants == []


async def test_bonus_time_from_family_link_is_a_grant_while_it_lasts(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator, freezer
) -> None:
    freezer.move_to(dt_util.now().replace(hour=12, minute=0))
    reset = async_mock_service(hass, "familylink", "reset_bonus")
    limits = await _sam_with_family_link(hass, hass_client_no_auth)
    _phone(hass)
    grants = async_capture_events(hass, "hearth_parent_grant")
    await _budget(hass, "all", 30)
    hass.states.async_set(_weekday_limit(), "0", {"child_id": CHILD})
    await _settle(hass, freezer)

    _phone(hass, bonus=30)
    await hass.async_block_till_done()
    assert grants[0].data["reason"] == "bonus time given in the Family Link app"
    assert grants[0].data["endable"] is True
    # Let go: the weekday's limit still reads Hearth's 0, so it's put back
    assert limits[-1].data["daily_minutes"] == 120
    household = _household(hass)
    assert household.grants.of("person.sam")

    # The bonus is used up: the grant ends and Hearth holds again
    hass.states.async_set(_weekday_limit(), "120", {"child_id": CHILD})
    hass.states.async_set(
        "sensor.sam_s_phone_active_bonus", "30", {"child_id": CHILD, "device_id": "dev1", "remaining_minutes": 0}
    )
    _phone(hass, bonus=30, tick=1)
    await hass.async_block_till_done()
    assert household.grants.of("person.sam") == []
    assert limits[-1].data["daily_minutes"] == 0
    assert reset == []


async def test_ending_a_family_link_bonus_grant_resets_the_bonus(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator, freezer
) -> None:
    freezer.move_to(dt_util.now().replace(hour=12, minute=0))
    reset = async_mock_service(hass, "familylink", "reset_bonus")
    await _sam_with_family_link(hass, hass_client_no_auth)
    _phone(hass)
    grants = async_capture_events(hass, "hearth_parent_grant")
    await _budget(hass, "all", 30)
    hass.states.async_set(_weekday_limit(), "0", {"child_id": CHILD})
    await _settle(hass, freezer)
    _phone(hass, bonus=30)
    await hass.async_block_till_done()

    await hass.services.async_call(DOMAIN, "allow_end", {"id": grants[0].data["id"]}, blocking=True)
    await hass.async_block_till_done()
    assert [c.data for c in reset] == [{"entity_id": PHONE}]


async def test_a_switch_limit_raised_in_the_nintendo_app_becomes_a_grant(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator, freezer
) -> None:
    freezer.move_to(dt_util.now().replace(hour=12, minute=0))
    _nintendo_switch(hass)
    await _household_with_sam(hass, hass_client_no_auth)
    set_value, _turned_on, turned_off = _nintendo_services(hass)
    await _option(hass, "enforce", {"person": "person.sam", "nintendo": NINTENDO_LIMIT})
    grants = async_capture_events(hass, "hearth_parent_grant")
    await _budget(hass, "games", 5)
    hass.states.async_set(NINTENDO_LIMIT, "0")
    await _settle(hass, freezer)

    hass.states.async_set(NINTENDO_LIMIT, "60")
    await hass.async_block_till_done()
    assert grants[0].data["source"] == "from the Nintendo app"
    assert grants[0].data["endable"] is True
    assert len(set_value) == 1 and turned_off == []  # the parent's 60 stays

    # An adult ends it from Hearth: the Switch is locked again
    await hass.services.async_call(DOMAIN, "allow_end", {"id": grants[0].data["id"]}, blocking=True)
    await hass.async_block_till_done()
    assert set_value[-1].data["value"] == 0


async def test_an_app_a_parent_changed_in_family_link_is_a_grant(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator, freezer
) -> None:
    paused = async_mock_service(hass, "familylink", "pause_app")
    resumed = async_mock_service(hass, "familylink", "resume_app")
    await _household_with_sam(hass, hass_client_no_auth)
    hass.states.async_set(FAMILY_LINK, "0", {"unit_of_measurement": "min", "child_id": CHILD})
    await _option(hass, "enforce", {"person": "person.sam", "family_link": FAMILY_LINK})
    grants = async_capture_events(hass, "hearth_parent_grant")
    await _budget(hass, "video", 10)
    assert "com.thesiegs.hearthtube" in paused[0].data["packages"]
    await _settle(hass, freezer)

    hass.states.async_set(
        "sensor.sam_family_link_apps_with_time_limits",
        "3",
        {
            "child_id": CHILD,
            "paused_apps": [{"package": "com.thesiegs.hearthtube", "pause_intact": False, "prior": -1}],
        },
    )
    await _bonus(hass, "video", 0)
    assert grants[0].data["target"] == {"kind": "app", "value": "com.thesiegs.hearthtube"}
    assert resumed[-1].data["packages"] == ["com.thesiegs.hearthtube"]

    # The summary names the app (from Sam's Family Link sensors when Hearth's catalog has no name), never the package
    from custom_components.hearth.websocket import _grant_views

    household = _household(hass)
    hass.states.async_set(
        "sensor.sam_family_link_screen_time_by_app",
        "1",
        {"child_id": CHILD, "apps": [{"package": "com.thesiegs.hearthtube", "name": "Video Club", "minutes": 4}]},
    )
    household.apps.apps.pop("com.thesiegs.hearthtube", None)
    assert household.app_names({"com.thesiegs.hearthtube", "com.example.unknown"}, "person.sam") == {
        "com.thesiegs.hearthtube": "Video Club"
    }
    [view] = _grant_views(household, "person.sam")
    assert view["name"] == "Video Club" and view["target"]["value"] == "com.thesiegs.hearthtube"


async def test_extra_time_from_family_safety_is_a_grant_until_it_ends(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator, freezer
) -> None:
    freezer.move_to(dt_util.now().replace(hour=12, minute=0))
    locked = async_mock_service(hass, "microsoft_family_safety", "lock_platform")
    unlocked = async_mock_service(hass, "microsoft_family_safety", "unlock_platform")
    hass.states.async_set(FAMILY_SAFETY, "Sam", {"user_id": 123456})
    await _household_with_sam(hass, hass_client_no_auth)
    await _option(hass, "enforce", {"person": "person.sam", "family_safety": FAMILY_SAFETY})
    grants = async_capture_events(hass, "hearth_parent_grant")
    allowed = "binary_sensor.sam_xbox_allowed_now"
    hass.states.async_set(allowed, "off", {"user_id": 123456, "platform": "Xbox", "hold": "ours"})
    await _budget(hass, "games", 5)
    assert len(locked) == 1
    await _settle(hass, freezer)

    until = (dt_util.now() + timedelta(hours=1)).replace(microsecond=0)
    hass.states.async_set(
        allowed,
        "on",
        {
            "user_id": 123456,
            "platform": "Xbox",
            "hold": "parent",
            "override": "allowUntil",
            "allow_until": until.isoformat(),
        },
    )
    await _bonus(hass, "games", 0)
    assert grants[0].data["source"] == "from the Family Safety app"
    assert grants[0].data["target"] == {"kind": "platform", "value": "Xbox"}
    assert grants[0].data["end_with"] == "family_safety_cancel_bonus"
    assert dt_util.parse_datetime(grants[0].data["until"]) == until
    assert [c.data["platform"] for c in unlocked] == ["Xbox"]


# D. Hearth's "all screen time" in the first-party apps


def _remaining(hass: HomeAssistant, minutes) -> None:
    hass.states.async_set(
        "sensor.sam_s_phone_screen_time_remaining", str(minutes), {"child_id": CHILD, "device_id": "dev1"}
    )


async def _allow_all(hass: HomeAssistant, until) -> str:
    response = await hass.services.async_call(
        DOMAIN,
        "allow",
        {"people": ["person.sam"], "group": "all", "until": until},
        blocking=True,
        return_response=True,
    )
    await hass.async_block_till_done()
    return response["id"]


async def test_allowing_all_screen_time_adds_a_family_link_bonus_where_google_would_block(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator, freezer
) -> None:
    freezer.move_to(dt_util.now().replace(hour=12, minute=0, second=0, microsecond=0))
    added = async_mock_service(hass, "familylink", "add_time_bonus")
    reset = async_mock_service(hass, "familylink", "reset_bonus")
    await _sam_with_family_link(hass, hass_client_no_auth)
    _phone(hass)
    _remaining(hass, 10)

    allow_id = await _allow_all(hass, dt_util.now().replace(hour=13, minute=0).isoformat())
    assert [c.data for c in added] == [{"entity_id": PHONE, "bonus_minutes": 50}]
    await _bonus(hass, "all", 0)  # evaluated again: not added twice
    assert len(added) == 1
    status = _household(hass).enforcement.status_of("person.sam")["family_link"]
    assert status["last"]["bonus_added"] == {"Sam's phone": 50}

    # A grant isn't made of Hearth's own bonus
    assert _household(hass).grants.of("person.sam") == []

    _phone(hass, bonus=50)
    await hass.services.async_call(DOMAIN, "allow_end", {"id": allow_id}, blocking=True)
    await hass.async_block_till_done()
    assert [c.data for c in reset] == [{"entity_id": PHONE}]


async def test_what_hearth_added_is_remembered_over_a_restart(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator, freezer
) -> None:
    freezer.move_to(dt_util.now().replace(hour=12, minute=0, second=0, microsecond=0))
    added = async_mock_service(hass, "familylink", "add_time_bonus")
    reset = async_mock_service(hass, "familylink", "reset_bonus")
    await _sam_with_family_link(hass, hass_client_no_auth)
    _phone(hass)
    _remaining(hass, 10)
    allow_id = await _allow_all(hass, dt_util.now().replace(hour=13, minute=0).isoformat())
    assert len(added) == 1

    # A restart: what's in memory is gone, what was saved comes back
    household = _household(hass)
    await household.async_flush()
    household.sync.fl_added, household.sync._given, household.enforcement.last = {}, {}, {}
    await household.sync.async_load()
    await household.enforcement.async_load()
    assert household.enforcement.status_of("person.sam")["family_link"]["last"]["bonus_added"] == {"Sam's phone": 50}

    # Hearth's own bonus is still Hearth's (no grant), and the allow isn't given extra time again
    _phone(hass, bonus=50)
    await _bonus(hass, "all", 0)
    assert len(added) == 1
    assert household.grants.of("person.sam") == []

    # Ending the allow still takes Hearth's bonus back
    await hass.services.async_call(DOMAIN, "allow_end", {"id": allow_id}, blocking=True)
    await hass.async_block_till_done()
    assert [c.data for c in reset] == [{"entity_id": PHONE}]


async def test_a_device_with_time_enough_or_no_limit_gets_no_bonus(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator, freezer
) -> None:
    freezer.move_to(dt_util.now().replace(hour=12, minute=0, second=0, microsecond=0))
    added = async_mock_service(hass, "familylink", "add_time_bonus")
    await _sam_with_family_link(hass, hass_client_no_auth)
    _phone(hass)
    _remaining(hass, 240)
    await _allow_all(hass, dt_util.now().replace(hour=13, minute=0).isoformat())
    _remaining(hass, "unknown")  # no daily limit
    await _allow_all(hass, dt_util.now().replace(hour=14, minute=0).isoformat())
    assert added == []


async def test_a_parent_s_bonus_on_top_of_hearth_s_isn_t_reset(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator, freezer
) -> None:
    freezer.move_to(dt_util.now().replace(hour=12, minute=0, second=0, microsecond=0))
    async_mock_service(hass, "familylink", "add_time_bonus")
    reset = async_mock_service(hass, "familylink", "reset_bonus")
    await _sam_with_family_link(hass, hass_client_no_auth)
    _phone(hass)
    _remaining(hass, 0)
    allow_id = await _allow_all(hass, dt_util.now().replace(hour=13, minute=0).isoformat())
    _phone(hass, bonus=90)  # Hearth's 60 and a parent's 30
    await hass.services.async_call(DOMAIN, "allow_end", {"id": allow_id}, blocking=True)
    await hass.async_block_till_done()
    assert reset == []
    status = _household(hass).enforcement.status_of("person.sam")["family_link"]
    assert status["last"]["bonus_kept"] == [PHONE]


async def test_extra_time_given_back_reaches_family_link_too(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator, freezer
) -> None:
    freezer.move_to(dt_util.now().replace(hour=12, minute=0, second=0, microsecond=0))
    added = async_mock_service(hass, "familylink", "add_time_bonus")
    await _sam_with_family_link(hass, hass_client_no_auth)
    _phone(hass)
    _remaining(hass, 0)
    await _budget(hass, "all", 30)
    await _bonus(hass, "all", 20)  # All screen time back: 35 used of 50, 15 left
    assert [c.data["bonus_minutes"] for c in added] == [15]


async def test_allowing_all_screen_time_gives_family_safety_extra_time(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator, freezer
) -> None:
    freezer.move_to(dt_util.now().replace(hour=12, minute=0, second=0, microsecond=0))
    async_mock_service(hass, "microsoft_family_safety", "lock_platform")
    async_mock_service(hass, "microsoft_family_safety", "unlock_platform")
    cancelled = async_mock_service(hass, "microsoft_family_safety", "cancel_time_bonus")
    given: list[ServiceCall] = []

    async def add_time_bonus(call: ServiceCall):
        given.append(call)
        return {"platform": call.data["platform"], "applied_until": call.data["until"], "released_hold": False}

    hass.services.async_register(
        "microsoft_family_safety", "add_time_bonus", add_time_bonus, supports_response=SupportsResponse.OPTIONAL
    )
    hass.states.async_set(FAMILY_SAFETY, "Sam", {"user_id": 123456})
    hass.states.async_set(
        "binary_sensor.sam_xbox_allowed_now",
        "on",
        {"user_id": 123456, "platform": "Xbox", "hold": "none", "allowance_minutes": 60, "used_minutes": 50,
         "remaining_minutes": 10},
    )
    await _household_with_sam(hass, hass_client_no_auth)
    await _option(hass, "enforce", {"person": "person.sam", "family_safety": FAMILY_SAFETY})

    allow_id = await _allow_all(hass, dt_util.now().replace(hour=13, minute=0).isoformat())
    assert [c.data for c in given] == [
        {"entity_id": FAMILY_SAFETY, "platform": "Xbox", "until": dt_util.now().replace(hour=13).replace(
            tzinfo=None).isoformat()}
    ]
    await hass.services.async_call(DOMAIN, "allow_end", {"id": allow_id}, blocking=True)
    await hass.async_block_till_done()
    assert [c.data["platform"] for c in cancelled] == ["Xbox"]


async def test_family_safety_extra_time_replaces_hearth_s_own_lock(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator, freezer
) -> None:
    """Family Safety refuses extra time over a lock unless asked to replace it; Hearth asks when the lock is its own."""
    freezer.move_to(dt_util.now().replace(hour=12, minute=0, second=0, microsecond=0))
    async_mock_service(hass, "microsoft_family_safety", "lock_platform")
    async_mock_service(hass, "microsoft_family_safety", "unlock_platform")
    async_mock_service(hass, "microsoft_family_safety", "cancel_time_bonus")
    given: list[ServiceCall] = []

    async def add_time_bonus(call: ServiceCall):
        given.append(call)
        return {"platform": call.data["platform"], "applied_until": call.data["until"], "hold_kept": True}

    hass.services.async_register(
        "microsoft_family_safety", "add_time_bonus", add_time_bonus, supports_response=SupportsResponse.OPTIONAL
    )
    hass.states.async_set(FAMILY_SAFETY, "Sam", {"user_id": 123456})
    hass.states.async_set(
        "binary_sensor.sam_xbox_allowed_now",
        "off",
        {"user_id": "123456", "platform": "Xbox", "hold": "ours", "override": "blockUntil",
         "allowance_minutes": 60, "used_minutes": 60, "remaining_minutes": 0},
    )
    await _household_with_sam(hass, hass_client_no_auth)
    await _option(hass, "enforce", {"person": "person.sam", "family_safety": FAMILY_SAFETY})

    await _allow_all(hass, dt_util.now().replace(hour=13, minute=0).isoformat())
    assert [c.data.get("replace_lock") for c in given] == [True]


async def test_family_safety_extra_time_unavailable_is_shown_not_raised(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator, freezer
) -> None:
    freezer.move_to(dt_util.now().replace(hour=12, minute=0, second=0, microsecond=0))

    async def add_time_bonus(call: ServiceCall):
        raise HomeAssistantError("Microsoft did not apply the extra time (experimental request)")

    hass.services.async_register(
        "microsoft_family_safety", "add_time_bonus", add_time_bonus, supports_response=SupportsResponse.OPTIONAL
    )
    hass.states.async_set(FAMILY_SAFETY, "Sam", {"user_id": 123456})
    hass.states.async_set(
        "sensor.sam_xbox_time_remaining", "5", {"user_id": 123456, "allowance_minutes": 60}
    )
    await _household_with_sam(hass, hass_client_no_auth)
    await _option(hass, "enforce", {"person": "person.sam", "family_safety": FAMILY_SAFETY})
    await _allow_all(hass, dt_util.now().replace(hour=13, minute=0).isoformat())
    status = _household(hass).enforcement.status_of("person.sam")["family_safety"]
    assert "unavailable" in status["last"]["error"] and status["last"]["ok"] is False


# E. Explain says what the device does


async def test_explain_names_google_s_own_device_limit(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator
) -> None:
    await _sam_with_family_link(hass, hass_client_no_auth)
    _phone(hass)
    _remaining(hass, 0)
    hass.states.async_set(
        "binary_sensor.sam_s_phone_daily_limit_reached", "on", {"child_id": CHILD, "device_id": "dev1"}
    )
    explained = await hass.services.async_call(
        DOMAIN, "explain", {"person": "person.sam", "app": "com.example.chat"}, blocking=True, return_response=True
    )
    assert explained["allowed"] is False
    assert explained["blocked_by"][-1]["kind"] == "device_limit"
    assert explained["blocked_by"][-1]["device"] == "Sam's phone"

    # A bonus on the device: Google's limit doesn't stop it
    _phone(hass, bonus=15)
    explained = await hass.services.async_call(
        DOMAIN, "explain", {"person": "person.sam", "app": "com.example.chat"}, blocking=True, return_response=True
    )
    assert all(b["kind"] != "device_limit" for b in explained["blocked_by"])


async def test_explain_names_a_parent_s_own_family_safety_lock(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator
) -> None:
    hass.states.async_set(FAMILY_SAFETY, "Sam", {"user_id": 123456})
    hass.states.async_set(
        "binary_sensor.sam_xbox_allowed_now",
        "off",
        {
            "user_id": 123456,
            "platform": "Xbox",
            "hold": "parent",
            "override": "blockUntil",
            "override_until": "2026-11-08T07:00:00-05:00",
            "allowance_minutes": 60,
            "used_minutes": 10,
            "remaining_minutes": 0,
        },
    )
    await _household_with_sam(hass, hass_client_no_auth)
    await _option(hass, "enforce", {"person": "person.sam", "family_safety": FAMILY_SAFETY})
    explained = await hass.services.async_call(
        DOMAIN, "explain", {"person": "person.sam", "group": "games"}, blocking=True, return_response=True
    )
    lock = next(b for b in explained["blocked_by"] if b["kind"] == "parent_lock")
    assert lock["platform"] == "Xbox" and lock["until"] == "2026-11-08T07:00:00-05:00"
    first = _household(hass).sync.first_party("person.sam")["family_safety"][0]
    assert first["parent_lock"] and first["allowance_minutes"] == 60


async def test_a_request_answered_in_the_family_safety_app_closes_its_ask(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator
) -> None:
    hass.states.async_set(FAMILY_SAFETY, "Sam", {"user_id": 123456})
    await _household_with_sam(hass, hass_client_no_auth)
    await _option(hass, "enforce", {"person": "person.sam", "family_safety": FAMILY_SAFETY})
    hub = hass.config_entries.async_entries(DOMAIN)[0].runtime_data
    hass.bus.async_fire(
        "microsoft_family_safety_request", {"account_id": "123456", "request_id": "r1", "platform": "Xbox"}
    )
    await hass.async_block_till_done()
    assert len(hub.asks.pending()) == 1

    # Hearth's own answer comes back as via service: nothing more
    hass.bus.async_fire(
        "microsoft_family_safety_request_resolved",
        {"account_id": "123456", "request_id": "r1", "outcome": "approved", "via": "service"},
    )
    await hass.async_block_till_done()
    assert len(hub.asks.pending()) == 1

    hass.bus.async_fire(
        "microsoft_family_safety_request_resolved",
        {"account_id": "123456", "request_id": "r1", "outcome": "approved", "minutes": 30, "via": "app"},
    )
    await hass.async_block_till_done()
    assert hub.asks.pending() == []
    answered = hub.asks.answered_elsewhere("person.sam")
    assert answered[0]["text"] == "answered in the Family Safety app" and answered[0]["status"] == "approved"


# Views: the household summary (contract 2), Hearth's page


def _kid(**extra) -> dict:
    return {"id": "person.sam", "name": "Sam", "kind": "kid", "groups": [], "playing": [], **extra}


def _grant(endable: bool, via: str = "nintendo", kind: str = "switch", value: str = "Switch") -> dict:
    return {
        "id": "g1",
        "type": "grant",
        "via": via,
        "source": "from the Nintendo app",
        "target": {"kind": kind, "value": value},
        "until": dt_util.now().replace(hour=21, minute=0).isoformat(),
        "endable": endable,
    }


def test_a_grant_is_news_and_endable_ones_are_actions() -> None:
    from custom_components.hearth.glance import person_glance

    now = dt_util.now().replace(hour=17, minute=0)
    glance = person_glance(_kid(), [], [], [], now, [_grant(True)])
    assert glance["headline"] == {"text": "switch open · the nintendo app till 9:00", "level": "notice", "key": "grant:g1"}
    end = next(a for a in glance["actions"] if a["id"] == "grant_end:g1")
    assert end["service"] == "hearth.allow_end" and end["data"] == {"id": "g1"} and end["confirm"]

    glance = person_glance(_kid(), [], [], [], now, [_grant(False, "family_link", "device", "Devices")])
    assert glance["headline"]["text"].startswith("devices open · the family link app")
    assert not any(a["id"].startswith("grant_end") for a in glance["actions"])


def test_first_party_limits_status_and_answers_are_lines() -> None:
    from custom_components.hearth.glance import person_glance

    now = dt_util.now().replace(hour=17, minute=0)
    person = _kid(
        first_party={
            "family_link": [{"entity_id": PHONE, "device": "Sam's phone", "blocking": True}],
            "family_safety": [{"platform": "Xbox", "parent_lock": True, "override_until": None}],
        },
        sync={"nintendo": {"held": [], "error": "bonus time is active", "last": None}},
    )
    answered = [{"id": "a1", "text": "answered in the Family Safety app"}]
    glance = person_glance(person, [], [], [], now, [], answered)
    keys = [glance["headline"]["key"]] + [line["key"] for line in glance["lines"]]
    assert keys[:4] == [f"device_limit:{PHONE}", "parent_lock:xbox", "sync_error:nintendo", "answered:a1"]
    # Older callers (no grants or answers) get what they always did
    assert person_glance(_kid(), [], [], [], now)["headline"]["key"] == "clear"


async def test_the_summary_shows_grants_first_party_limits_and_sync(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator, freezer
) -> None:
    from custom_components.hearth.websocket import summary

    freezer.move_to(dt_util.now().replace(hour=12, minute=0))
    limits = await _sam_with_family_link(hass, hass_client_no_auth)
    _phone(hass)
    _remaining(hass, 30)
    await _budget(hass, "all", 30)
    assert limits[-1].data["daily_minutes"] == 0
    hass.states.async_set(_weekday_limit(), "0", {"child_id": CHILD})
    await _settle(hass, freezer)
    _phone(hass, bonus=30)
    await hass.async_block_till_done()

    body = summary(hass.config_entries.async_entries(DOMAIN)[0].runtime_data)
    sam = next(p for p in body["people"] if p["id"] == "person.sam")
    assert sam["grants"][0]["source"] == "from the Family Link app" and sam["grants"][0]["endable"]
    phone = sam["first_party"]["family_link"][0]
    assert phone["device"] == "Sam's phone" and phone["minutes_left"] == 30 and phone["bonus_left"] == 30
    assert sam["sync"]["family_link"]["last"]["outcomes"] == {"Devices": "restored"}
    assert sam["allows"] == [] and sam["answered_elsewhere"] == []
    assert any(a["id"].startswith("grant_end:") for a in sam["actions"])
    assert any(line["key"].startswith("grant:") for line in [sam["headline"], *sam["lines"]])
