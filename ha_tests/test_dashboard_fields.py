"""The dashboard spec's server-built fields: one time format, each person's binding group, today line and state, each
group's state, the household's counts, and a play's time (remaining, progress, minutes, text)."""

from datetime import datetime, timedelta

from homeassistant.util import dt as dt_util

from custom_components.hearth.glance import amount, duration, household_glance, person_glance
from custom_components.hearth.household import Playing
from custom_components.hearth.websocket import _playing_view


def _now() -> datetime:
    return datetime(2026, 11, 6, 17, 0, tzinfo=dt_util.get_default_time_zone())


def _kid(groups: dict[str, tuple[int | None, int]], **extra) -> dict:
    """A kid in the summary's shape: groups {id: (budget, used)}."""
    rows = []
    for gid, (budget, used) in groups.items():
        rows.append(
            {"id": gid, "name": "All screen time" if gid == "all" else gid.title(), "used_minutes": used,
             "minutes_left": None if budget is None else max(0, budget - used), "budget": budget, "bonus": 0}
        )
    person = {"id": "person.alex", "name": "Alex", "kind": "kid", "groups": rows, "playing": [], **extra}
    person["all"] = next((g for g in rows if g["id"] == "all"), None)
    return person


def _glance(person, allows=()):
    return person_glance(person, [], list(allows), [], _now())


def test_one_time_format() -> None:
    assert [duration(m) for m in (0, 45, 60, 65, 130, 180)] == ["0 min", "45 min", "1 h", "1 h 05", "2 h 10", "3 h"]
    assert [amount(m) for m in (10, 59, 60, 80)] == ["10", "59", "1 h", "1 h 20"]
    # The glance writes it: no more "130 left"
    glance = _glance(_kid({"all": (300, 170), "youtube": (180, 50)}))
    assert glance["headline"]["text"] == "youtube · 2 h 10 left" and glance["headline"]["key"] == "left:youtube"


def test_the_binding_group_the_today_line_and_states() -> None:
    glance = _glance(_kid({"all": (180, 130), "games": (60, 50), "social": (None, 20)}))
    assert glance["binding"] == {"group": "games", "minutes_left": 10}
    assert glance["day_line"] == {"text": "2 h 10 of 3 h · games · 10 left", "level": "calm", "key": "day:left:games"}
    assert glance["state"] == "ok"
    person = _kid({"all": (180, 130), "games": (60, 50), "social": (None, 20)})
    _glance(person)
    states = {g["id"]: (g["state"], g["limited"]) for g in person["groups"]}
    assert states == {"all": ("ok", True), "games": ("ok", True), "social": ("none", False)}
    assert person["all"]["state"] == "ok"

    # All binds
    glance = _glance(_kid({"all": (180, 130), "games": (120, 10)}))
    assert glance["day_line"]["text"] == "2 h 10 of 3 h · 50 left" and glance["binding"]["group"] == "all"
    # A group out
    glance = _glance(_kid({"all": (180, 180), "games": (60, 60)}))
    assert glance["binding"] == {"group": "all", "minutes_left": 0}
    assert glance["day_line"]["text"] == "3 h of 3 h · out of time" and glance["state"] == "out"
    glance = _glance(_kid({"all": (180, 100), "games": (60, 60)}))
    assert glance["day_line"]["text"] == "1 h 40 of 3 h · games out" and glance["day_line"]["key"] == "day:out:games"
    # Low
    glance = _glance(_kid({"all": (180, 175)}))
    assert glance["state"] == "low" and glance["day_line"]["level"] == "notice"
    # No limit
    glance = _glance(_kid({"all": (None, 80)}))
    assert glance["binding"] is None and glance["day_line"]["text"] == "1 h 20 today · no limit"
    assert glance["state"] == "none"


def test_a_pause_a_lock_and_an_allow_replace_or_lift() -> None:
    until = (_now() + timedelta(minutes=90)).isoformat()
    glance = _glance(_kid({"all": (180, 130)}, pause={"until": until, "reason": "Dinner"}))
    assert glance["day_line"]["text"] == "paused · dinner till 6:30" and glance["state"] == "paused"
    glance = _glance(_kid({"all": (180, 130)}, lock={"kind": "bedtime", "until": until}))
    assert glance["day_line"]["text"] == "bedtime till 6:30" and glance["state"] == "locked"
    # An allow of a group lifts it: it never binds, and its state says so
    person = _kid({"all": (180, 130), "games": (60, 60)})
    glance = _glance(person, [{"id": "a1", "group": "games", "until": until}])
    assert glance["binding"]["group"] == "all"
    assert next(g for g in person["groups"] if g["id"] == "games")["state"] == "allowed"
    # A first-party hold, Hearth's time not out
    glance = _glance(_kid({"all": (180, 30)}, held_by=["family_link"]))
    assert glance["state"] == "held"


def test_the_household_counts() -> None:
    out = {**_kid({"all": (60, 60)}), "id": "person.alex", "state": "out", "suggestions": [{"key": "more:all",
           "reason": "group_out", "group": "all"}]}
    low = {**_kid({"all": (60, 55)}), "id": "person.sam", "name": "Sam", "state": "low", "suggestions": []}
    approvals = [{"type": "more_time", "id": "x", "person": "person.sam", "person_name": "Sam", "minutes": 30,
                  "group": "all"}]
    counts = household_glance([out, low], approvals)["counts"]
    assert counts == {"asks": 1, "suggestions": 1, "pairings": 0, "paused": 0, "out": 1, "low": 1, "locked": 0,
                      "held": 0}


def _view(play: Playing, now: datetime) -> dict:
    return _playing_view(play, now, lambda item: {"games"} if item == "com.mojang.minecraftpe" else set())


def test_a_play_s_time() -> None:
    now = dt_util.utcnow()
    started = (now - timedelta(minutes=25)).isoformat()
    # A show with its length: what's left, the position running on while it plays
    show = Playing("HearthTube", "com.thesiegs.hearthtube", "Kitchen TV", "playing", "hearth:tv", "Sleepytime", "s2e4",
                   since=started, kind="video", series="Bluey", duration_s=1200.0, position_s=600.0,
                   position_at=now - timedelta(minutes=2), key="Bluey")
    view = _view(show, now)
    assert view["remaining"] == 8 and view["progress"] == 0.6 and view["text"] == "bluey · s2e4 · 8 min left"
    # Paused: it stands
    show.paused = True
    assert _view(show, now)["remaining"] == 10
    # An app in the Games group is a game, timed from its start
    game = Playing("Minecraft", "com.mojang.minecraftpe", "Alex's phone", "playing", "fl:1", since=started, kind="app",
                   key="com.mojang.minecraftpe")
    view = _view(game, now)
    assert view["kind"] == "game" and view["minutes"] == 25 and view["remaining"] is None
    assert view["text"] == "minecraft · 25 min"
    # Music: no time
    track = Playing("Spotify", "com.spotify.music", "Kitchen TV", "playing", "hearth:tv", "Song", since=started,
                    kind="music", artist="Artist", key="Song")
    view = _view(track, now)
    assert view["text"] == "artist · song" and view["minutes"] is None and "minutes_today" not in view


def test_a_device_s_document_never_carries_a_play_s_ticking_time() -> None:
    """The state document's playing is Playing.view(): no minutes, remaining or text, so a TV's wait isn't woken by
    them (wait.signature)."""
    view = Playing("App", "pkg", "TV", "playing", "hearth:tv", duration_s=60.0, position_s=1.0,
                   position_at=dt_util.utcnow()).view()
    assert not {"minutes", "remaining", "progress", "text", "duration_s", "position_s"} & set(view)
