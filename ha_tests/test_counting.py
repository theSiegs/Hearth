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


def test_a_minute_counts_in_every_group_its_app_is_in():
    groups = groups_from_options({"groups": [{"id": "youtube", "name": "YouTube", "apps": ["com.thesiegs.hearthtube"]}]})
    membership = groups_of(groups, {"com.example.game": "game"})
    devices = {
        "tv": merge([Reading("hearth", 900, {"com.thesiegs.hearthtube": 600, "com.example.game": 300})]),
        "phone": merge([Reading("hearth", 300, {"com.thesiegs.hearthtube": 300})]),
    }
    seconds = group_seconds(devices, membership)
    assert seconds[ALL] == 1200
    assert seconds["youtube"] == 900
    assert seconds["video"] == 900  # HearthTube is a starter video app
    assert seconds["games"] == 300


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
