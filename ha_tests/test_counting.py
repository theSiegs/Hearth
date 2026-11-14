"""Each minute counted once, and groups."""

from custom_components.hearth.counting import ALL, Reading, group_seconds, merge
from custom_components.hearth.limits import BUILTIN_GROUPS, GroupState, day_type, groups_of, groups_from_options

from datetime import date


def test_two_sources_on_one_device_take_the_larger_not_the_sum():
    usage = merge(
        [
            Reading("hearth", 600, {"com.example.game": 400, "com.example.video": 200}),
            Reading("family_link", 900, {"com.example.game": 500}),
        ]
    )
    assert usage.items == {"com.example.game": 500, "com.example.video": 200}
    assert usage.total_s == 900
    assert usage.rest_s == 200
    assert usage.sources == {"hearth": 600, "family_link": 900}


def test_known_apps_can_outweigh_any_one_total():
    usage = merge([Reading("a", 100, {"x": 100}), Reading("b", 100, {"y": 100})])
    assert usage.total_s == 200
    assert usage.rest_s == 0


def test_a_source_s_rest_counts_in_its_group():
    devices = {"switch": merge([Reading("nintendo", 1800, {}, rest_group="games")])}
    seconds = group_seconds(devices, lambda item: {ALL})
    assert seconds == {ALL: 1800, "games": 1800}


def test_a_minute_counts_in_its_one_pool_and_all():
    groups = groups_from_options({"groups": [{"id": "youtube", "name": "YouTube", "apps": ["com.thesiegs.hearthtube"]}]})
    membership = groups_of(groups, {"com.example.game": "game", "com.example.stream": "video"})
    devices = {
        "tv": merge([Reading("hearth", 960, {"com.thesiegs.hearthtube": 600, "com.example.game": 300, "com.example.stream": 60})]),
        "phone": merge([Reading("hearth", 300, {"com.thesiegs.hearthtube": 300})]),
    }
    seconds = group_seconds(devices, membership)
    assert seconds[ALL] == 1260
    assert seconds["youtube"] == 900
    assert seconds["games"] == 300
    # No built-in Video pool: a video app in no pool counts in All only, so the pools and "other" add up to All
    assert "video" not in seconds
    assert sum(v for k, v in seconds.items() if k != ALL) + 60 == seconds[ALL]


def test_apps_added_to_a_built_in_group():
    groups = groups_from_options({"group_apps": {"games": ["com.example.launcher"]}})
    assert "games" in groups_of(groups, {})("com.example.launcher")
    assert [g.id for g in groups] == [g.id for g in BUILTIN_GROUPS]


def test_minutes_left():
    assert GroupState(counted_min=50, budget_min=60, bonus_min=15).minutes_left == 25
    assert GroupState(counted_min=90, budget_min=60, bonus_min=0).minutes_left == 0
    assert GroupState(counted_min=90, budget_min=None, bonus_min=0).minutes_left is None


def test_day_types():
    assert day_type(date(2026, 10, 24)) == "weekend"  # a Saturday
    assert day_type(date(2026, 10, 26)) == "weekday"


def test_a_group_outside_all_screen_time_counts_only_in_itself():
    options = {
        "groups": [{"id": "music", "name": "Music", "apps": ["com.example.music"]}],
        "outside_all": ["music"],
    }
    groups = groups_from_options(options)
    # Messaging is outside All screen time too, unless an adult puts it in
    assert [g.id for g in groups if not g.in_all] == ["messaging", "music"]
    assert [g.id for g in groups_from_options({"inside_all": ["messaging"]}) if not g.in_all] == []
    devices = {
        "phone": merge([Reading("hearth", 1500, {"com.example.music": 600, "com.example.game": 600})]),
        "speaker": merge([Reading("tablet", 300, {}, rest_group="music")]),
    }
    membership = groups_of(groups, {"com.example.game": "game"})
    seconds = group_seconds(devices, membership, [g.id for g in groups if not g.in_all])
    # The phone's 300 s not put on an app still counts; the music, on an app or a source's rest, doesn't
    assert seconds[ALL] == 900
    assert seconds["music"] == 900
    assert seconds["games"] == 600


def test_all_screen_time_never_goes_outside_itself():
    groups = groups_from_options({"outside_all": ["all"], "inside_all": ["messaging"]})
    assert all(g.in_all for g in groups)
