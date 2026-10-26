"""The status a TV posts is cleaned before anything uses it."""

from custom_components.hearth.status import MAX_APPS, MAX_TEXT, clean_status


def test_keeps_known_fields():
    status = clean_status(
        {
            "screen": "on",
            "state": "playing",
            "app": "Example TV",
            "app_package": "com.example.tv",
            "media_title": "Episode 1",
            "profile": "Alex",
            "profile_id": "user:0",
            "kids_profile": False,
            "screen_time_up": True,
            "screen_time_minutes_left": 5,
            "seconds_today": 3600,
            "app_seconds_today": {"com.example.tv": 1800},
            "usage_today": {"user:0": {"profile_name": "Alex", "seconds": 3600, "apps": {"com.example.tv": 1800}}},
        }
    )
    assert status["state"] == "playing"
    assert status["app"] == "Example TV"
    assert status["screen_time_up"] is True
    assert status["seconds_today"] == 3600
    assert status["usage_today"]["user:0"]["apps"] == {"com.example.tv": 1800}
    assert status["usage_today"]["user:0"]["playing"] == {}


def test_drops_unknown_fields_and_wrong_types():
    status = clean_status({"state": "exploding", "kids_profile": "yes", "seconds_today": "lots", "extra": 1})
    assert status["state"] is None
    assert status["kids_profile"] is None
    assert status["seconds_today"] is None
    assert "extra" not in status


def test_text_is_short_and_without_control_characters():
    status = clean_status({"media_title": "A\x00B\x1b[31mC\n" + "x" * 1000})
    assert status["media_title"].startswith("AB[31mC")
    assert len(status["media_title"]) == MAX_TEXT
    assert "\x00" not in status["media_title"]


def test_numbers_are_bounded():
    status = clean_status({"seconds_today": 10**9, "screen_time_minutes_left": -1, "media_duration_s": True})
    assert status["seconds_today"] is None
    assert status["screen_time_minutes_left"] is None
    assert status["media_duration_s"] is None


def test_lists_and_maps_are_capped():
    status = clean_status(
        {
            "allowed_apps": [f"com.example.app{i}" for i in range(500)] + [7],
            "app_seconds_today": {f"com.example.app{i}": i for i in range(500)},
        }
    )
    assert len(status["allowed_apps"]) == MAX_APPS
    assert len(status["app_seconds_today"]) == MAX_APPS


def test_not_an_object():
    assert clean_status([1, 2]) is None
    assert clean_status("on") is None
