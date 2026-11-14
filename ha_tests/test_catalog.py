"""The shared app catalog (catalog.py): fetched, verified and kept; its keys; where it puts apps (limits.placer); Check
these on Hearth's page; and the upward sender, which waits while the relay has no /propose."""

import base64
from datetime import timedelta
import hashlib
import json
from pathlib import Path

from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PrivateKey
from cryptography.hazmat.primitives.serialization import Encoding, PublicFormat
import pytest

from homeassistant.core import HomeAssistant
from homeassistant.util import dt as dt_util
from pytest_homeassistant_custom_component.typing import ClientSessionGenerator

from custom_components.hearth import catalog as cat
from custom_components.hearth.catalog import (
    CatalogData,
    CatalogError,
    CatalogKeeper,
    Hit,
    catalog_keys,
    check_seq,
    check_shard,
    correctable_key,
    normalize_name,
    proposable_key,
    read_bundled,
    shard_list,
    verify_index,
)
from custom_components.hearth.const import DOMAIN
from custom_components.hearth.limits import (
    OTHER,
    catalog_value,
    groups_from_options,
    groups_of,
    placer,
    pool_map,
)
from test_panel import _ws
from test_people import _household_with_sam
from test_sources import _option

URL = "https://catalog.example/"
RELAY = "https://relay.example/"
PINNED = {
    "exchange-1": "RPjFgOTCSoJHIN6mdve1eM1ehgYSuBrketbP7IloApo=",
    "exchange-2": "U4OXyesZZJworjpLe+IEYphvnMPZxriY5Wu8spy7GfQ=",
}


def _key() -> tuple[Ed25519PrivateKey, bytes]:
    private = Ed25519PrivateKey.generate()
    return private, private.public_key().public_bytes(Encoding.Raw, PublicFormat.Raw)


def _shard(platform: str, keys: dict) -> bytes:
    return json.dumps({"format": "glint.catalog/1", "platform": platform, "keys": keys}, separators=(",", ":")).encode()


def _site(private: Ed25519PrivateKey, seq: int, shards: dict[str, bytes]) -> tuple[bytes, bytes, dict[str, bytes]]:
    """index.json, its signature and the shard files, as build_index.py publishes them."""
    listed, files = {}, {}
    for platform, data in shards.items():
        digest = hashlib.sha256(data).hexdigest()
        path = f"k/{platform}.{digest[:16]}.json"
        listed[platform] = {"path": path, "sha256": digest, "count": 1}
        files[path] = data
    index = json.dumps(
        {"format": "glint.exchange/1", "seq": seq, "issued": "2026-11-13T00:00:00Z", "apps": {}, "revoked": [],
         "catalog": {"format": "glint.catalog/1", "shards": listed}},
        separators=(",", ":"),
    ).encode()
    return index, base64.b64encode(private.sign(index)), files


XBOX = {"xbox:1828326430": {"app": "minecraft", "name": "Minecraft", "category": "game", "state": "confirmed", "source": "store"}}
ANDROID = {
    "android:com.example.tube": {"app": "tube", "name": "Tube", "category": "video", "detail": "youtube", "state": "confirmed"},
    "android:com.example.maybe": {"category": "game", "state": "suggested", "source": "ai"},
    "android:com.example.hub": {"app": "hub", "category": "productivity", "detail": "companion", "state": "confirmed"},
}


# Verifying


def test_a_signed_index_verifies_and_a_changed_one_doesn_t() -> None:
    private, public = _key()
    index, sig, _ = _site(private, 5, {"xbox": _shard("xbox", XBOX)})
    assert verify_index(index, sig, [public])["seq"] == 5
    with pytest.raises(CatalogError):
        verify_index(index.replace(b'"seq":5', b'"seq":6'), sig, [public])
    with pytest.raises(CatalogError):
        verify_index(index, sig, [_key()[1]])
    with pytest.raises(CatalogError):
        verify_index(index, b"not base64!", [public])
    with pytest.raises(CatalogError):
        verify_index(index, base64.b64encode(b"short"), [public])
    # Any one of the pinned keys may sign
    assert verify_index(index, sig, [_key()[1], public])["seq"] == 5
    other = json.dumps({"format": "glint.exchange/2", "seq": 1}).encode()
    with pytest.raises(CatalogError):
        verify_index(other, base64.b64encode(private.sign(other)), [public])


def test_a_lower_seq_is_a_rollback() -> None:
    check_seq({"seq": 10}, 10)
    check_seq({"seq": 11}, 10)
    check_seq({"seq": 1}, None)
    with pytest.raises(CatalogError):
        check_seq({"seq": 9}, 10)


def test_a_shard_must_match_its_sha256_format_and_platform() -> None:
    data = _shard("xbox", XBOX)
    digest = hashlib.sha256(data).hexdigest()
    assert check_shard("xbox", digest, data) == XBOX
    with pytest.raises(CatalogError):
        check_shard("xbox", digest, data + b" ")
    with pytest.raises(CatalogError):
        check_shard("pfn", digest, data)
    with pytest.raises(CatalogError):
        shard_list({"catalog": {"format": "glint.catalog/1", "shards": {"xbox": {"path": "../x.json", "sha256": digest}}}})
    with pytest.raises(CatalogError):
        shard_list({"catalog": {"format": "glint.catalog/2", "shards": {}}})
    # An unknown shard is skipped; an index with no catalog is an empty one
    assert shard_list({"catalog": {"format": "glint.catalog/1", "shards": {"vr": {"path": "k/vr.0.json"}}}}) == {}
    assert shard_list({"format": "glint.exchange/1"}) == {}


def test_the_bundled_snapshot_verifies_with_the_pinned_keys() -> None:
    keys, index, shards = read_bundled()
    assert sorted(base64.b64encode(k).decode() for k in keys) == sorted(PINNED.values())
    assert index is not None and index["seq"] > 0
    assert "android" in shards and len(CatalogData(shards)) > 100


# Keys


def test_the_name_normalizer_passes_the_catalog_s_vectors() -> None:
    vectors = json.loads((Path(__file__).parent / "catalog_normalize_vectors.json").read_text(encoding="utf-8"))
    for raw, wanted in vectors["vectors"]:
        assert normalize_name(raw) == wanted, raw


def test_what_hearth_sees_is_looked_up_under_the_catalog_s_keys() -> None:
    assert catalog_keys("com.example.player") == ["android:com.example.player"]
    assert catalog_keys("a:com.example.phone") == ["android:com.example.phone"]
    assert catalog_keys("appx:windowsplt:Example.Paint_8wekyb3d8bbwe") == ["pfn:example.paint_8wekyb3d8bbwe"]
    assert catalog_keys("appx:Example.Paint") == ["pfn:example.paint"]
    assert catalog_keys("x:xboxplt:0123456789ABCDEF") == ["fs:xboxplt:0123456789abcdef"]
    assert catalog_keys("0100152000022000") == ["switch:0100152000022000"]
    assert catalog_keys("Mario Kart™ 8 Deluxe")[:2] == ["name:xbox:mario kart 8 deluxe", "name:switch:mario kart 8 deluxe"]
    assert catalog_keys("win32:notepad.exe") == []
    assert catalog_keys("title:minecraft") == []
    # fs: and win32: stay in the household; Android packages aren't sent as new keys either
    assert proposable_key("appx:Example.Paint") == "pfn:example.paint"
    assert proposable_key("x:xboxplt:0123456789abcdef") is None
    assert proposable_key("com.example.player") is None
    assert correctable_key("com.example.player") == "android:com.example.player"
    assert correctable_key("win32:notepad.exe") is None


def test_the_catalog_answers_confirmed_first_then_through_the_app_s_other_keys() -> None:
    data = CatalogData({
        "xbox": XBOX,
        "android": ANDROID,
        "name": {"name:xbox:minecraft": {"app": "minecraft", "name": "Minecraft", "state": "suggested"}},
        "pfn": {"pfn:example.hub_1": {"app": "hub", "category": "game", "state": "suggested"},
                "pfn:example.bad": {"category": "not-a-category", "detail": "nope", "state": "confirmed"}},
    })
    tube = data.lookup("com.example.tube")
    assert tube == Hit("android:com.example.tube", True, "video", "youtube", "Tube") and tube.value == "youtube"
    assert data.lookup("com.example.maybe").confirmed is False
    # The name key has no value of its own: the same app's xbox key answers
    hit = data.lookup("Minecraft")
    assert hit.key == "xbox:1828326430" and hit.confirmed and hit.category == "game"
    # A suggested key whose app has a confirmed key elsewhere takes that one
    assert data.lookup("appx:Example.Hub_1").detail == "companion"
    # Unknown values are as absent
    assert data.lookup("appx:Example.Bad") is None
    assert data.lookup("com.example.unknown") is None


# Where an app goes


def _groups(extra: list[dict] | None = None):
    return groups_from_options({"groups": [{"id": "youtube", "name": "YouTube", "apps": []}, *(extra or [])]})


def test_the_resolver_order() -> None:
    groups = _groups([{"id": "fun", "name": "Fun", "apps": ["com.example.listed"]}])
    data = CatalogData({"android": ANDROID})
    categories = {"com.example.tube": "video", "com.example.hub": "game", "com.example.maybe": "news",
                  "com.example.declared": "game"}
    hints = {"com.example.hub": {"games"}, "com.example.hinted": {"games"}, "com.example.maybe": {"games"}}
    place = placer(groups, categories, {"com.example.moved": "other"}, catalog=data.lookup, hints=hints)

    assert place("com.example.moved").why == "moved" and place("com.example.moved").pool is None
    assert place("com.example.listed").pool == "fun"
    assert place("com.whatsapp").why == "starter"
    # Confirmed beats the device: YouTube's detail goes to the household's YouTube pool
    assert (place("com.example.tube").pool, place("com.example.tube").why) == ("youtube", "catalog")
    # A confirmed companion app is never a game: Other, and neither the device nor the hint moves it
    hub = place("com.example.hub")
    assert (hub.pool, hub.why, hub.disagree) == (None, "catalog", True)
    assert place("com.example.declared").why == "declared"
    # A guess goes only to a pool: here the device said news (no pool), so the suggestion places it
    assert (place("com.example.maybe").pool, place("com.example.maybe").why) == ("games", "suggested")
    assert place("com.example.hinted").why == "hint"
    assert place("com.example.none") .why == "other"
    # counting's view of it
    assert groups_of(groups, categories, catalog=data.lookup)("com.example.tube") == {"all", "youtube"}


def test_a_guess_never_takes_an_app_out_of_a_pool() -> None:
    data = CatalogData({"android": {"android:com.example.x": {"category": "productivity", "detail": "companion"}}})
    place = placer(_groups(), {}, catalog=data.lookup, hints={"com.example.x": {"games"}})
    assert place("com.example.x").why == "hint"


def test_the_household_s_pool_map() -> None:
    groups = _groups([{"id": "tv", "name": "TV", "apps": []}, {"id": "homework", "name": "Homework", "apps": []}])
    pools = pool_map(groups)
    assert pools["game"] == "games" and pools["youtube"] == "youtube" and pools["streaming"] == "tv"
    assert pools["education"] == "homework" and pools["companion"] == OTHER and "video" not in pools
    own = pool_map(groups, {"streaming": "youtube", "news": "other", "game": "gone"})
    assert own["streaming"] == "youtube" and own["news"] == OTHER and own["game"] == "games"
    # A move to a pool, said in the catalog's terms (never the pool)
    assert catalog_value(pools, "games") == {"category": "game"}
    assert catalog_value(pools, "youtube") == {"category": "video", "detail": "youtube"}
    assert catalog_value(pools, OTHER) is None
    # The Video pool retire_video kept takes video
    kept = groups_from_options({"groups": [{"id": "video", "name": "Video", "apps": [], "category": "video"}]})
    assert pool_map(kept)["video"] == "video"


# Fetching and keeping


async def _keeper(hass: HomeAssistant, public: bytes, **options) -> CatalogKeeper:
    keeper = CatalogKeeper(hass, "test", {"catalog_url": URL, "catalog_relay": RELAY, **options})
    await keeper.async_load()
    keeper.keys = [public]
    return keeper


def _serve(aioclient_mock, index: bytes, sig: bytes, files: dict[str, bytes], etag: str = '"one"') -> None:
    aioclient_mock.clear_requests()
    aioclient_mock.get(URL + "index.json", content=index, headers={"ETag": etag})
    aioclient_mock.get(URL + "index.json.sig", content=sig)
    for path, data in files.items():
        aioclient_mock.get(URL + path, content=data)


async def test_first_run_uses_the_bundled_snapshot(hass: HomeAssistant) -> None:
    keeper = CatalogKeeper(hass, "test", {})
    await keeper.async_load()
    assert keeper.origin == "bundled" and len(keeper.data) > 100 and keeper.stale()


async def test_a_fetch_is_verified_kept_and_used_offline(hass: HomeAssistant, aioclient_mock, hass_storage) -> None:
    private, public = _key()
    keeper = await _keeper(hass, public)
    bundled_seq = keeper.seq
    index, sig, files = _site(private, bundled_seq + 10, {"xbox": _shard("xbox", XBOX), "android": _shard("android", ANDROID)})
    _serve(aioclient_mock, index, sig, files)
    changed = []
    keeper.on_change = lambda: changed.append(True)

    assert await keeper.async_fetch() is True
    assert keeper.origin == "fetched" and keeper.seq == bundled_seq + 10 and changed == [True]
    assert keeper.data.lookup("com.example.tube").detail == "youtube"
    assert all(h is None or h.get("User-Agent") == "Hearth" for _m, _u, _d, h in aioclient_mock.mock_calls)
    await keeper.async_flush()

    # Unchanged: the index answers 304 to its ETag and nothing else is fetched
    aioclient_mock.clear_requests()
    aioclient_mock.get(URL + "index.json", status=304)
    assert await keeper.async_fetch() is False
    assert aioclient_mock.call_count == 1 and aioclient_mock.mock_calls[0][3]["If-None-Match"] == '"one"'

    # Offline after a restart: the stored copy, no expiry
    again = await _keeper(hass, public)
    assert again.origin == "fetched" and again.seq == bundled_seq + 10 and not again.stale()
    aioclient_mock.clear_requests()
    aioclient_mock.get(URL + "index.json", exc=TimeoutError())
    assert await again.async_fetch() is False
    assert again.data.lookup("com.example.tube").detail == "youtube" and again.error


async def test_a_bad_fetch_keeps_the_last_good_copy(hass: HomeAssistant, aioclient_mock) -> None:
    private, public = _key()
    keeper = await _keeper(hass, public)
    seq = keeper.seq + 10
    index, sig, files = _site(private, seq, {"xbox": _shard("xbox", XBOX)})
    _serve(aioclient_mock, index, sig, files)
    assert await keeper.async_fetch()

    # A rollback
    old, old_sig, old_files = _site(private, seq - 1, {"android": _shard("android", ANDROID)})
    _serve(aioclient_mock, old, old_sig, old_files, etag='"two"')
    assert await keeper.async_fetch() is False and "rollback" in keeper.error
    # Signed by someone else
    other, _ = _key()
    forged, forged_sig, forged_files = _site(other, seq + 1, {"android": _shard("android", ANDROID)})
    _serve(aioclient_mock, forged, forged_sig, forged_files, etag='"three"')
    assert await keeper.async_fetch() is False and "signature" in keeper.error
    # A shard that isn't what the index signed
    good, good_sig, good_files = _site(private, seq + 2, {"android": _shard("android", ANDROID)})
    _serve(aioclient_mock, good, good_sig, {path: data + b" " for path, data in good_files.items()}, etag='"four"')
    assert await keeper.async_fetch() is False and "SHA-256" in keeper.error

    assert keeper.seq == seq and keeper.data.has("xbox:1828326430")
    assert keeper.data.lookup("com.example.tube") is None


async def test_a_fetch_reuses_shards_whose_hash_didn_t_change(hass: HomeAssistant, aioclient_mock) -> None:
    private, public = _key()
    keeper = await _keeper(hass, public)
    xbox = _shard("xbox", XBOX)
    index, sig, files = _site(private, keeper.seq + 1, {"xbox": xbox})
    _serve(aioclient_mock, index, sig, files)
    assert await keeper.async_fetch()
    index, sig, files = _site(private, keeper.seq + 1, {"xbox": xbox, "android": _shard("android", ANDROID)})
    _serve(aioclient_mock, index, sig, files, etag='"two"')
    assert await keeper.async_fetch()
    assert [str(u) for _m, u, _d, _h in aioclient_mock.mock_calls if "/k/" in str(u)] == [
        URL + next(p for p in files if p.startswith("k/android"))
    ]


# Upward


async def test_the_sender_no_ops_while_the_relay_has_no_propose(hass: HomeAssistant, aioclient_mock) -> None:
    _private, public = _key()
    keeper = await _keeper(hass, public, catalog_share=True)
    keeper.note_seen({"appx:Example.Paint": {"person.alex"}, "appx:Example.Kid": {"person.sam"},
                      "com.example.app": {"person.alex"}}, lambda p: p == "person.alex", lambda _i: False)
    assert keeper.queue_correction("android:com.example.app", "game", None)
    assert keeper.batch(dt_util.utcnow()) == ([{"key": "pfn:example.paint"}], [{"key": "android:com.example.app", "category": "game"}])

    aioclient_mock.post(RELAY + "challenge", json={"token": "t", "expires": 1})
    aioclient_mock.post(RELAY + "propose", status=404)
    assert await keeper.async_send() == "absent"
    assert keeper.candidates and keeper.corrections

    aioclient_mock.clear_requests()
    aioclient_mock.post(RELAY + "challenge", json={"token": "t", "expires": 1})
    aioclient_mock.post(RELAY + "propose", status=202, json={"accepted": 1, "dropped": 0})
    assert await keeper.async_send() == "sent"
    body = aioclient_mock.mock_calls[1][2]
    assert body == {"format": "glint.catalog-propose/1", "optIn": True, "token": "t",
                    "keys": [{"key": "pfn:example.paint"}], "corrections": [{"key": "android:com.example.app", "category": "game"}]}
    assert not keeper.candidates and not keeper.corrections
    # Sent lately: not again
    keeper.note_seen({"appx:Example.Paint": {"person.alex"}}, lambda p: True, lambda _i: False)
    assert keeper.batch(dt_util.utcnow()) == ([], [])
    assert await keeper.async_send() == "nothing"


async def test_nothing_is_noted_or_sent_with_sharing_off(hass: HomeAssistant, aioclient_mock, hass_storage) -> None:
    # Waiting from when it was on: dropped
    hass_storage["hearth.catalog.test"] = {"version": 1, "minor_version": 1, "key": "hearth.catalog.test", "data": {
        "candidates": {"pfn:example.paint": "2026-11-13"}, "corrections": [{"key": "android:com.example.app", "category": "game"}]}}
    _private, public = _key()
    keeper = await _keeper(hass, public)
    await keeper.async_flush()
    stored = hass_storage["hearth.catalog.test"]["data"]
    assert stored["candidates"] == {} and stored["corrections"] == []
    keeper.note_seen({"appx:Example.Paint": {"person.alex"}}, lambda p: True, lambda _i: False)
    assert not keeper.queue_correction("android:com.example.app", "game", None)
    assert keeper.candidates == {} and await keeper.async_send() == "off"
    assert aioclient_mock.call_count == 0


async def test_the_send_waits_a_week(hass: HomeAssistant, aioclient_mock) -> None:
    _private, public = _key()
    keeper = await _keeper(hass, public, catalog_share=True)
    now = dt_util.utcnow()
    assert await keeper.async_maybe_send(now) is None and keeper.next_send
    assert await keeper.async_maybe_send(now + timedelta(days=6)) is None
    assert await keeper.async_maybe_send(now + timedelta(days=8, hours=1)) == "nothing"
    assert aioclient_mock.call_count == 0


# On Hearth's page


async def test_check_these_and_the_setting_on_the_page(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator, hass_ws_client
) -> None:
    await _household_with_sam(hass, hass_client_no_auth)
    entry = hass.config_entries.async_entries(DOMAIN)[0]
    household = entry.runtime_data.household
    # The TV says com.example.game is a game; the catalog says it's a companion app (confirmed); another app is only
    # a guess
    household.catalog.data = CatalogData({"android": {
        "android:com.example.game": {"category": "productivity", "detail": "companion", "state": "confirmed"},
        "android:com.example.news": {"category": "game", "state": "suggested"},
    }})
    household.recompute()
    ws = await hass_ws_client(hass)

    config = (await _ws(ws, {"type": "hearth/config"}))["result"]
    rows = {r["package"]: r for r in config["check_these"]}
    assert rows["com.example.news"]["group"] == "games" and rows["com.example.news"]["suggested"]
    # Suggestions first
    assert config["check_these"][0]["package"] == "com.example.news"
    assert rows["com.example.game"]["group"] == OTHER and "the device says game" in rows["com.example.game"]["why"]
    assert config["catalog"]["fetch"] is True and config["catalog"]["share"] is False and not config["catalog"]["asked"]
    assert config["catalog"]["pools"]["game"] == "games"

    # Sharing is off: a correction isn't queued
    answer = await _ws(ws, {"type": "hearth/catalog/correct", "app": "com.example.game", "group": "games"})
    assert answer["success"] and answer["result"] == {"queued": False}

    # An adult says Right: it stays put, whatever the catalog says later, and leaves the list
    answer = await _ws(ws, {"type": "hearth/config/set", "key": "app_groups", "value": {"com.example.game": "other"}})
    assert answer["success"], answer
    await hass.async_block_till_done()
    household = entry.runtime_data.household
    household.catalog.data = CatalogData({"android": {
        "android:com.example.game": {"category": "game", "state": "confirmed"}}})
    overview = household.apps_overview()
    assert "com.example.game" not in {r["package"] for r in overview["check_these"]}
    assert next(a for a in overview["apps"] if a["package"] == "com.example.game")["catalog_says"] == "game"

    # Turned on (asked once): an adult's move is shared as what the app is, never the pool
    for key in ("catalog_share_asked", "catalog_share"):
        assert (await _ws(ws, {"type": "hearth/config/set", "key": key, "value": True}))["success"]
        await hass.async_block_till_done()
    household = entry.runtime_data.household
    answer = await _ws(ws, {"type": "hearth/catalog/correct", "app": "com.example.game", "group": "games"})
    assert answer["result"] == {"queued": True}
    assert household.catalog.corrections == [{"key": "android:com.example.game", "category": "game"}]
    # Never about a messaging app, and never Other
    assert (await _ws(ws, {"type": "hearth/catalog/correct", "app": "com.whatsapp", "group": "games"}))["result"] == {"queued": False}
    assert (await _ws(ws, {"type": "hearth/catalog/correct", "app": "com.example.x", "group": "other"}))["result"] == {"queued": False}
    # The pool map is the household's to change
    answer = await _ws(ws, {"type": "hearth/config/set", "key": "catalog_pools", "value": {"companion": "games"}})
    assert answer["success"], answer
    answer = await _ws(ws, {"type": "hearth/config/set", "key": "catalog_pools", "value": {"bogus": "games"}})
    assert not answer["success"]
    answer = await _ws(ws, {"type": "hearth/config/set", "key": "catalog_url", "value": "http://insecure.example/"})
    assert not answer["success"]


async def test_the_daily_fetch_runs_at_its_own_time(hass: HomeAssistant, aioclient_mock, freezer) -> None:
    """Started with a stale copy: one fetch soon after, then once a day; never offline errors out."""
    keeper = CatalogKeeper(hass, "test", {"catalog_url": URL})
    await keeper.async_load()
    jobs = []
    keeper.start(lambda job: jobs.append(hass.async_create_task(job)))
    aioclient_mock.get(URL + "index.json", status=503)
    freezer.tick(timedelta(minutes=11))
    from pytest_homeassistant_custom_component.common import async_fire_time_changed

    async_fire_time_changed(hass)
    await hass.async_block_till_done()
    assert jobs and aioclient_mock.call_count >= 1 and "503" in keeper.error
    assert keeper.origin == "bundled"
    keeper.stop()


async def test_the_setting_in_configure(hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator) -> None:
    await _household_with_sam(hass, hass_client_no_auth)
    await _option(hass, "app_catalog", {"fetch": False, "share": True})
    entry = hass.config_entries.async_entries(DOMAIN)[0]
    assert (entry.options["catalog_fetch"], entry.options["catalog_share"], entry.options["catalog_share_asked"]) == (False, True, True)
    catalog = entry.runtime_data.household.catalog
    assert catalog.fetch_on is False and catalog.share_on is True
