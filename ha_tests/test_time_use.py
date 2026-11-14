"""The time-use design: one pool per app (and the built-in Video pool retired), All screen time split by pool, the day
strip's bedtime, and the time left on each device as the server works it out."""

from datetime import timedelta
import logging

from homeassistant.core import HomeAssistant
from homeassistant.util import dt as dt_util
from pytest_homeassistant_custom_component.typing import ClientSessionGenerator

from custom_components.hearth.const import DOMAIN
from custom_components.hearth.limits import (
    CONF_POOLS,
    POOLS_VERSION,
    STARTER_VIDEO_APPS,
    groups_from_options,
    groups_of,
    one_pool_per_app,
    retire_video,
)
from custom_components.hearth.apps import options_with_app_in_group
from custom_components.hearth.websocket import summary
from test_enforce import FAMILY_SAFETY, _budget
from test_init import _post
from test_native_sync import _phone, _remaining, _sam_with_family_link
from test_panel import _ws
from test_people import KID, _household_with_sam, _tv_status
from test_sources import _option

HEARTHTUBE = "com.thesiegs.hearthtube"


def _hub(hass: HomeAssistant):
    return hass.config_entries.async_entries(DOMAIN)[0].runtime_data


def _sam(hass: HomeAssistant) -> dict:
    return next(p for p in summary(_hub(hass))["people"] if p["id"] == "person.sam")


# One pool per app


def test_an_app_counts_in_one_pool_an_adult_s_list_first() -> None:
    groups = groups_from_options(
        {
            "groups": [
                {"id": "chat", "name": "Chat", "apps": ["com.whatsapp"]},
                {"id": "fun", "name": "Fun", "apps": ["com.example.game"]},
            ]
        }
    )
    of = groups_of(groups, {"com.example.game": "game", "com.example.other": "game", "com.example.feed": "social"})
    # An adult's list beats a starter list (WhatsApp is a starter messaging app) and a category
    assert of("com.whatsapp") == {"all", "chat"}
    assert of("com.example.game") == {"all", "fun"}
    # Else a starter list, else the category
    assert of("tv.twitch.android.app") == {"all", "social"}
    assert of("com.example.other") == {"all", "games"}
    assert of("com.example.feed") == {"all", "social"}
    # No built-in Video pool: YouTube is in none until an adult puts it in one
    assert of("com.google.android.youtube") == {"all"}
    # Where an adult moved an app beats everything
    moved = groups_of(groups, {"com.example.game": "game"}, {"com.example.game": "games", "com.whatsapp": "other"})
    assert moved("com.example.game") == {"all", "games"}
    assert moved("com.whatsapp") == {"all"}


def test_an_app_put_in_a_pool_leaves_the_others() -> None:
    before = {
        "group_apps": {"games": ["com.example.app", "com.example.keep"]},
        "groups": [{"id": "youtube", "name": "YouTube", "apps": [HEARTHTUBE]}],
        "app_groups": {"com.example.app": "games"},
    }
    after = {
        **before,
        "groups": [{"id": "youtube", "name": "YouTube", "apps": [HEARTHTUBE, "com.example.app"]}],
    }
    out = one_pool_per_app(before, after)
    assert out["group_apps"] == {"games": ["com.example.keep"]}
    assert out["groups"][0]["apps"] == [HEARTHTUBE, "com.example.app"]
    # Where an adult had moved it follows its new list
    assert out["app_groups"] == {}
    # Lists that already held an app twice keep it in the first
    twice = {"group_apps": {"games": ["x"]}, "groups": [{"id": "fun", "name": "Fun", "apps": ["x"]}]}
    assert one_pool_per_app(twice, twice)["groups"][0]["apps"] == []
    # Sorting a new app into a pool does the same
    sorted_in = options_with_app_in_group(out, HEARTHTUBE, "games")
    assert sorted_in["group_apps"]["games"] == ["com.example.keep", HEARTHTUBE]
    assert sorted_in["groups"][0]["apps"] == ["com.example.app"]


# Retiring the built-in Video pool


def test_without_a_video_budget_video_goes(caplog) -> None:
    caplog.set_level(logging.INFO)
    options = {"group_apps": {"video": ["com.example.extra"], "games": ["com.example.game"]}, "outside_all": ["video"]}
    out = retire_video(options, {"person.sam": {"video": {"weekday": None, "weekend": None}, "all": {"weekday": 60}}})
    assert out[CONF_POOLS] == POOLS_VERSION
    assert out["group_apps"] == {"games": ["com.example.game"]}
    assert out["outside_all"] == []
    assert "video" not in [g["id"] for g in out.get("groups", [])]
    assert "nobody had a Video budget" in caplog.text and "com.example.extra" in caplog.text
    # Once only
    assert retire_video(out, {}) is None


def test_a_video_budget_keeps_a_pool_of_that_name(caplog) -> None:
    options = {
        "group_apps": {"video": ["com.example.extra", "com.example.game"], "games": ["com.example.game"]},
        "groups": [{"id": "youtube", "name": "YouTube", "apps": [HEARTHTUBE, "com.google.android.youtube"]}],
        "app_groups": {"com.netflix.ninja": "games"},
    }
    out = retire_video(options, {"person.sam": {"video": {"weekday": 60, "weekend": None}}})
    video = next(g for g in out["groups"] if g["id"] == "video")
    assert video["name"] == "Video" and video["category"] == "video"
    # The starter list and the adult's additions, less what another pool (or a move) has
    assert "com.example.extra" in video["apps"] and "com.disney.disneyplus" in video["apps"]
    assert not {HEARTHTUBE, "com.google.android.youtube", "com.netflix.ninja", "com.example.game"} & set(video["apps"])
    assert out["group_apps"] == {"games": ["com.example.game"]}
    assert "Video had a budget for person.sam" in caplog.text
    # The kept pool counts the apps Android marks as video, after an adult's own lists
    of = groups_of(groups_from_options(out), {"com.example.stream": "video", HEARTHTUBE: "video"})
    assert of("com.example.stream") == {"all", "video"}
    assert of(HEARTHTUBE) == {"all", "youtube"}
    assert retire_video(out, {}) is None


def test_an_app_moved_to_video_keeps_it_and_an_own_video_pool_stays() -> None:
    moved = retire_video({"app_groups": {"com.example.film": "video"}}, {})
    assert {g["id"] for g in moved["groups"]} == {"video"}
    own = {"groups": [{"id": "video", "name": "Films", "apps": ["com.example.film"]}]}
    assert retire_video(own, {"person.sam": {"video": {"weekday": 30}}})["groups"] == own["groups"]


async def test_an_older_household_is_moved_on_start(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator, caplog
) -> None:
    await _household_with_sam(hass, hass_client_no_auth)
    await _budget(hass, "video", 30)
    assert hass.states.get("sensor.hearth_sam_video_minutes_left").state == "20"
    entry = hass.config_entries.async_entries(DOMAIN)[0]
    # As before the time-use design: no pools mark, Video built in (no pool of their own), an app added to it
    old = {k: v for k, v in entry.options.items() if k not in (CONF_POOLS, "groups")}
    hass.config_entries.async_update_entry(entry, options={**old, "group_apps": {"video": ["com.example.extra"]}})
    await hass.async_block_till_done()

    assert entry.options[CONF_POOLS] == POOLS_VERSION
    [video] = entry.options["groups"]
    assert video["id"] == "video" and "com.example.extra" in video["apps"] and HEARTHTUBE in video["apps"]
    assert entry.options["group_apps"] == {}
    assert "Video had a budget for person.sam" in caplog.text
    # The budget, its entities and today's minutes stay
    assert hass.states.get("sensor.hearth_sam_video_minutes_left").state == "20"


async def test_a_new_household_has_nothing_to_move(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator, caplog
) -> None:
    caplog.set_level(logging.INFO)
    await _household_with_sam(hass, hass_client_no_auth)
    assert hass.config_entries.async_entries(DOMAIN)[0].options[CONF_POOLS] == POOLS_VERSION
    assert "Video pool is retired" not in caplog.text


async def test_the_panel_keeps_an_app_in_one_pool(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator, hass_ws_client
) -> None:
    await _household_with_sam(hass, hass_client_no_auth)
    ws = await hass_ws_client(hass)
    entry = hass.config_entries.async_entries(DOMAIN)[0]
    groups = [*entry.options["groups"], {"id": "youtube", "name": "YouTube", "apps": [HEARTHTUBE]}]
    answer = await _ws(ws, {"type": "hearth/config/set", "key": "groups", "value": groups})
    assert answer["success"], answer
    await hass.async_block_till_done()
    by_id = {g["id"]: g["apps"] for g in entry.options["groups"]}
    assert by_id["youtube"] == [HEARTHTUBE] and HEARTHTUBE not in by_id["video"]
    # Sorting an app moves it out of every list
    _hub(hass).household.sort_app("com.netflix.ninja", "games")
    await hass.async_block_till_done()
    assert "com.netflix.ninja" not in {a for g in entry.options["groups"] for a in g["apps"]}


# The summary


async def test_all_screen_time_split_by_pool_adds_up(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator
) -> None:
    client, secret = await _household_with_sam(hass, hass_client_no_auth)
    status = _tv_status(hearthtube_s=600, game_s=300)
    # Five minutes the TV can't put on an app: "other"
    status["seconds_today"] += 300
    status["usage_today"][KID]["seconds"] += 300
    assert (await _post(client, secret, body=status)).status == 200
    await hass.async_block_till_done()
    sam = _sam(hass)
    assert sam["all"]["used_minutes"] == 20
    assert sam["all_by_pool"] == [
        {"id": "games", "name": "Games", "minutes": 5},
        {"id": "video", "name": "Video", "minutes": 10},
        {"id": "other", "name": "Other", "minutes": 5},
    ]
    assert sum(p["minutes"] for p in sam["all_by_pool"]) == sam["all"]["used_minutes"]


async def test_bedtime_today_comes_from_the_lock_entities(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator, freezer
) -> None:
    freezer.move_to(dt_util.now().replace(hour=15, minute=0, second=0))
    await _household_with_sam(hass, hass_client_no_auth)
    assert "bedtime" not in _sam(hass)
    today = dt_util.now().date()
    tablet = "binary_sensor.sam_tablet_bedtime_active"
    phone = "binary_sensor.sam_phone_bedtime_active"
    hass.states.async_set(tablet, "off", {"bedtime_start": f"{today}T21:00:00", "bedtime_end": f"{today + timedelta(days=1)}T07:00:00"})
    # A time of day alone reads too; with two, the earliest bedtime and the latest wake
    hass.states.async_set(phone, "off", {"bedtime_start": "20:30:00", "bedtime_end": "06:45:00"})
    await _option(hass, "locks", {"person": "person.sam", "entities": [tablet, phone]})
    bedtime = _sam(hass)["bedtime"]
    start, end = dt_util.parse_datetime(bedtime["start"]), dt_util.parse_datetime(bedtime["end"])
    assert (start.date(), start.hour, start.minute) == (today, 20, 30)
    assert (end.date(), end.hour, end.minute) == (today, 7, 0)


async def test_the_time_left_on_each_device(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator, freezer
) -> None:
    freezer.move_to(dt_util.now().replace(hour=12, minute=0, second=0, microsecond=0))
    await _sam_with_family_link(hass, hass_client_no_auth)
    _phone(hass)
    _remaining(hass, 40)
    await _budget(hass, "all", 120)
    targets = {t["id"]: t for t in _sam(hass)["targets"]}
    left = _sam(hass)["all"]["minutes_left"]
    assert left > 40
    # Google's limit is less than Hearth's on the phone; the TV has Hearth's
    phone, tv = targets["fl:dev1"], next(t for t in targets.values() if t["via"] == "hearth")
    assert (phone["left"], phone["left_by"], phone["locked"]) == (40, "google", False)
    assert (tv["left"], tv["left_by"], tv["left_pool"], tv["locked"]) == (left, "hearth", "all", False)

    # Google's own limit used up: locked there by it, not by Hearth
    _remaining(hass, 0)
    phone = next(t for t in _sam(hass)["targets"] if t["id"] == "fl:dev1")
    assert (phone["left"], phone["locked"], phone["locked_kind"]) == (0, True, "device_limit")

    # A lock of theirs: every device is locked, with its kind
    bedtime = "binary_sensor.sam_tablet_bedtime_active"
    hass.states.async_set(bedtime, "on", {"bedtime_start": "21:00:00", "bedtime_end": "07:00:00"})
    await _option(hass, "locks", {"person": "person.sam", "entities": [bedtime]})
    _hub(hass).household.recompute()
    assert {(t["locked"], t["locked_kind"]) for t in _sam(hass)["targets"]} == {(True, "bedtime")}


async def test_an_xbox_held_to_games_shows_games_by_hearth(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator
) -> None:
    hass.states.async_set(FAMILY_SAFETY, "Sam", {"user_id": 123456})
    hass.states.async_set(
        "binary_sensor.sam_xbox_allowed_now",
        "on",
        {"user_id": 123456, "platform": "Xbox", "hold": "none", "allowance_minutes": 180, "used_minutes": 30,
         "remaining_minutes": 150},
    )
    await _household_with_sam(hass, hass_client_no_auth)
    await _option(hass, "enforce", {"person": "person.sam", "family_safety": FAMILY_SAFETY})
    await _budget(hass, "all", 120)
    await _budget(hass, "games", 15)  # 5 used: 10 left
    xbox = next(t for t in _sam(hass)["targets"] if t["id"] == "fs:xbox")
    assert (xbox["left"], xbox["left_by"], xbox["left_pool"], xbox["locked"]) == (10, "hearth", "games", False)
