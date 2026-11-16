"""App categories (categories.py, category_lookup.py): the precedence (an adult's override, the starter list, a store's
genre, an AI's answer, unknown), the store genre mappings on recorded answers, the AI Task's gating and caching, the
loose-category rule, the retired catalog's migration, where answers put apps (limits.placer), and Hearth's page."""

from datetime import timedelta
import json
from pathlib import Path

from homeassistant.core import HomeAssistant, ServiceCall, SupportsResponse
from homeassistant.util import dt as dt_util
from pytest_homeassistant_custom_component.common import MockConfigEntry
from pytest_homeassistant_custom_component.typing import ClientSessionGenerator

from custom_components.hearth import categories as cats
from custom_components.hearth import category_lookup as lookup
from custom_components.hearth.categories import (
    CategoryBook,
    Hit,
    StarterList,
    async_migrate_catalog,
    category_keys,
    migrated_options,
    normalize_name,
    read_starter,
)
from custom_components.hearth.const import DOMAIN
from custom_components.hearth.limits import OTHER, groups_from_options, groups_of, placer, pool_map
from test_panel import _ws
from test_people import _household_with_sam
from test_sources import _option

FIXTURES = Path(__file__).parent / "category_fixtures"
PLAY = "https://play.google.com/store/apps/details?id={}&hl=en_US&gl=US"


def _fixture(name: str) -> str:
    return (FIXTURES / name).read_text(encoding="utf-8")


async def _book(hass: HomeAssistant, starter: dict | None = None, **options) -> CategoryBook:
    book = CategoryBook(hass, "test", options)
    await book.async_load()
    if starter is not None:
        book.starter = StarterList(starter)
    return book


# Keys


def test_the_name_normalizer_passes_the_old_catalog_s_vectors() -> None:
    vectors = json.loads((Path(__file__).parent / "catalog_normalize_vectors.json").read_text(encoding="utf-8"))
    for raw, wanted in vectors["vectors"]:
        assert normalize_name(raw) == wanted, raw


def test_what_hearth_sees_is_known_under_its_keys() -> None:
    assert category_keys("com.example.player") == ["android:com.example.player"]
    assert category_keys("a:com.example.phone") == ["android:com.example.phone"]
    assert category_keys("appx:windowsplt:Example.Paint_8wekyb3d8bbwe") == ["pfn:example.paint_8wekyb3d8bbwe"]
    assert category_keys("x:xboxplt:0123456789ABCDEF") == ["fs:xboxplt:0123456789abcdef"]
    assert category_keys("0100152000022000") == ["switch:0100152000022000"]
    assert category_keys("Mario Kart™ 8 Deluxe")[:2] == ["name:xbox:mario kart 8 deluxe", "name:switch:mario kart 8 deluxe"]
    assert category_keys("win32:notepad.exe") == [] and category_keys("title:minecraft") == []
    assert cats.override_key("win32:notepad.exe") == "win32:notepad.exe"
    assert cats.override_key("com.example.player") == "android:com.example.player"


# The starter list


def test_the_starter_list_holds_the_old_catalog_and_hearth_s_additions() -> None:
    keys = read_starter()
    starter = StarterList(keys)
    assert len(starter) == len(keys) > 350
    namespaces = {k.split(":", 1)[0] for k in keys}
    assert {"android", "msstore", "xbox", "pfn", "steam", "switch", "name"} <= namespaces
    # Every entry is something Hearth reads
    for key, entry in keys.items():
        assert entry["category"] in (*cats.KNOWN_CATEGORIES, None), key
        assert entry.get("detail") in (None, *cats.DETAILS), key
    # System screens, parental controls, big games, a streaming detail, and an owner's "none of the ten"
    assert sum(1 for e in keys.values() if e["category"] == "interface") >= 15
    assert starter.lookup("com.android.systemui").uncounted
    assert starter.lookup("com.microsoft.familysafety").detail == "system"
    assert starter.lookup("com.roblox.client").category == "game"
    assert starter.lookup("com.netflix.mediaclient").detail == "streaming"
    chrome = starter.lookup("com.android.chrome")
    assert chrome is not None and chrome.category is None and chrome.confirmed and chrome.source == "starter"
    # Console keys too: a played title's name, through the app's other keys
    assert starter.lookup("Minecraft").category == "game"


def test_the_starter_list_answers_through_an_app_s_other_keys() -> None:
    starter = StarterList({
        "xbox:1828326430": {"category": "game", "app": "minecraft", "name": "Minecraft"},
        "name:xbox:minecraft": {"category": None, "app": "minecraft"},
        "pfn:example.hub_1": {"category": "productivity", "detail": "companion", "app": "hub"},
        "android:com.example.hub": {"category": "not-a-category", "app": "hub"},
    })
    # A name key with no category takes the same app's xbox key
    assert starter.lookup("Minecraft").key == "xbox:1828326430"
    assert starter.lookup("appx:Example.Hub_1").detail == "companion"
    # A value Hearth doesn't know is as absent
    assert starter.lookup("com.example.hub") is None


# Precedence


async def test_an_override_beats_the_starter_list_a_store_and_an_ai(hass: HomeAssistant) -> None:
    book = await _book(
        hass,
        {"android:com.example.tube": {"category": "video", "detail": "youtube"}},
        app_categories={"android:com.example.tube": {"category": "game"}, "win32:fun.exe": {"category": "game"}},
    )
    book.answers = {
        "android:com.example.tube": {"store": {"status": "found", "category": "social", "confirmed": True}},
        "android:com.example.shop": {"store": {"status": "found", "category": "video", "confirmed": True},
                                     "ai": {"category": "game"}},
        "android:com.example.vague": {"store": {"status": "found", "category": None, "unclear": True},
                                      "ai": {"category": "news"}},
        "android:com.example.none": {"store": {"status": "found", "category": None, "genre": "SHOPPING"}},
    }
    assert (book.lookup("com.example.tube").source, book.lookup("com.example.tube").category) == ("override", "game")
    assert book.lookup("win32:fun.exe").source == "override"
    # Without the override, the starter list
    book.overrides.pop("android:com.example.tube")
    assert (book.lookup("com.example.tube").source, book.lookup("com.example.tube").detail) == ("starter", "youtube")
    # A store's answer before an AI's
    shop = book.lookup("com.example.shop")
    assert (shop.source, shop.category, shop.confirmed) == ("store", "video", True)
    vague = book.lookup("com.example.vague")
    assert (vague.source, vague.category, vague.confirmed) == ("ai", "news", False)
    # The store's "none of the ten": unknown to placing, but the page says the store answered
    assert book.lookup("com.example.none") is None
    assert book.describe("com.example.none")["source"] == "store"
    assert book.describe("com.example.none")["genre"] == "SHOPPING"
    assert book.describe("com.example.never")["source"] == "unknown"


def test_the_resolver_order() -> None:
    groups = groups_from_options({"groups": [{"id": "youtube", "name": "YouTube", "apps": []},
                                             {"id": "fun", "name": "Fun", "apps": ["com.example.listed"]}]})
    answers = {
        "com.example.tube": Hit("android:com.example.tube", True, "video", "youtube", source="starter"),
        "com.example.hub": Hit("android:com.example.hub", True, "productivity", "companion", source="store"),
        "com.example.maybe": Hit("android:com.example.maybe", False, "game", None, source="ai"),
    }
    categories = {"com.example.tube": "video", "com.example.hub": "game", "com.example.maybe": "news",
                  "com.example.declared": "game"}
    hints = {"com.example.hub": {"games"}, "com.example.hinted": {"games"}, "com.example.maybe": {"games"}}
    place = placer(groups, categories, {"com.example.moved": "other"}, lookup=answers.get, hints=hints)

    assert place("com.example.moved").why == "moved" and place("com.example.moved").pool is None
    assert place("com.example.listed").pool == "fun"
    assert place("com.whatsapp").why == "starter"
    assert (place("com.example.tube").pool, place("com.example.tube").why) == ("youtube", "category")
    hub = place("com.example.hub")
    assert (hub.pool, hub.why, hub.disagree) == (None, "category", True)
    assert place("com.example.declared").why == "declared"
    # A guess goes only to a pool: the device said news (no pool), so the AI's game places it
    assert (place("com.example.maybe").pool, place("com.example.maybe").why) == ("games", "suggested")
    assert place("com.example.hinted").why == "hint"
    assert place("com.example.none").why == "other"
    assert groups_of(groups, categories, lookup=answers.get)("com.example.tube") == {"all", "youtube"}


def test_a_guess_never_takes_an_app_out_of_a_pool() -> None:
    answers = {"com.example.x": Hit("android:com.example.x", False, "productivity", "companion", source="ai")}
    place = placer(groups_from_options({}), {}, lookup=answers.get, hints={"com.example.x": {"games"}})
    assert place("com.example.x").why == "hint"


async def test_only_an_override_or_the_starter_list_loosens_a_limit(hass: HomeAssistant) -> None:
    """Messaging and Accessibility: never from a store's genre or an AI alone, only from an adult or Hearth's list."""
    book = await _book(
        hass,
        {"android:com.example.reader": {"category": "accessibility"}},
        app_categories={"android:com.example.mine": {"category": "messaging"}},
    )
    book.answers = {
        "android:com.example.chat": {"store": {"status": "found", "category": "messaging", "confirmed": True}},
        "android:com.example.helper": {"store": {"status": "found", "category": None, "unclear": True},
                                       "ai": {"category": "accessibility"}},
        "android:com.example.talk": {"ai": {"category": "messaging"}},
    }
    # A store's messaging is never confirmed, whatever its record says
    assert book.lookup("com.example.chat").confirmed is False
    groups = groups_from_options({})
    place = placer(groups, {"com.example.sneaky": "accessibility"}, lookup=book.lookup, pools=pool_map(groups))
    for item in ("com.example.chat", "com.example.helper", "com.example.talk"):
        p = place(item)
        assert (p.pool, p.why) == (None, "suggested"), item
    assert place("com.example.sneaky").pool is None
    assert (place("com.example.reader").pool, place("com.example.reader").why) == ("accessibility", "category")
    assert (place("com.example.mine").pool, place("com.example.mine").why) == ("messaging", "category")


async def test_system_screens_come_only_from_a_list_or_an_override(hass: HomeAssistant) -> None:
    book = await _book(hass, {"android:com.example.home": {"category": "interface"}},
                       app_categories={"android:com.example.kiosk": {"category": "interface"}})
    groups = groups_from_options({})
    place = placer(groups, {"com.example.home": "game"}, lookup=book.lookup,
                   pools=pool_map(groups, {"interface": "games", "game": "interface"}))
    assert (place("com.example.home").pool, place("com.example.home").why) == ("interface", "category")
    assert place("com.example.kiosk").pool == "interface"
    # An AI never says System screens, whatever it answers
    assert lookup.parse_ai({"category": "interface", "detail": "none"}) == {"category": None, "detail": None}
    # An adult's move wins
    moved = placer(groups, {}, {"com.example.home": "games"}, lookup=book.lookup)
    assert moved("com.example.home").pool == "games"


def test_the_household_s_pool_map() -> None:
    groups = groups_from_options({"groups": [{"id": "youtube", "name": "YouTube", "apps": []},
                                             {"id": "tv", "name": "TV", "apps": []},
                                             {"id": "homework", "name": "Homework", "apps": []}]})
    pools = pool_map(groups)
    assert pools["game"] == "games" and pools["youtube"] == "youtube" and pools["streaming"] == "tv"
    assert pools["education"] == "homework" and pools["companion"] == OTHER and "video" not in pools
    own = pool_map(groups, {"streaming": "youtube", "news": "other", "game": "gone"})
    assert own["streaming"] == "youtube" and own["news"] == OTHER and own["game"] == "games"


# Store genres, on answers recorded from the stores (2026-11-16, trimmed to what Hearth reads)


def test_play_pages_map_by_the_classifier_s_sure_genres() -> None:
    minecraft = lookup.parse_play_page(_fixture("play_minecraft.html"))
    assert minecraft["genre"] == "GAME_ARCADE"
    answer = lookup.from_play(**minecraft)
    assert (answer["category"], answer["confirmed"], answer["unclear"]) == ("game", True, False)
    assert answer["name"].startswith("Minecraft")
    # Entertainment is too broad: unclear (an AI may be asked)
    netflix = lookup.from_play(**lookup.parse_play_page(_fixture("play_netflix.html")))
    assert (netflix["category"], netflix["unclear"], netflix["genre"]) == (None, True, "ENTERTAINMENT")
    # Communication holds browsers as well as messengers: Chrome is unclear, never messaging
    chrome = lookup.from_play(**lookup.parse_play_page(_fixture("play_chrome.html")))
    assert (chrome["category"], chrome["unclear"]) == (None, True)
    # WhatsApp's one-liner doesn't say chat: unclear too
    whatsapp = lookup.from_play(**lookup.parse_play_page(_fixture("play_whatsapp.html")))
    assert whatsapp["category"] is None and whatsapp["unclear"]
    # A clear messenger is messaging, never confirmed; email is productivity; a genre outside the ten is none
    texts = lookup.from_play("COMMUNICATION", "Example Chat", "Free texts and video calls")
    assert (texts["category"], texts["confirmed"], texts["unclear"]) == ("messaging", False, False)
    assert lookup.from_play("COMMUNICATION", "Example Mail", "Your inbox")["category"] == "productivity"
    shop = lookup.from_play("SHOPPING", "Shop", "")
    assert (shop["category"], shop["unclear"], shop["confirmed"]) == (None, False, False)
    assert lookup.from_play("PHOTOGRAPHY")["category"] == "image"
    assert lookup.parse_play_page("<html>no data</html>") is None


def test_microsoft_store_and_steam_answers() -> None:
    minecraft = lookup.from_store_products(json.loads(_fixture("ms_minecraft.json")))
    assert (minecraft["category"], minecraft["confirmed"], minecraft["name"]) == ("game", True, "Minecraft for Windows")
    xbox = lookup.from_store_products(json.loads(_fixture("ms_xbox.json")))
    assert (xbox["category"], xbox["confirmed"]) == ("game", True)
    # An application in Entertainment: unclear
    netflix = lookup.from_store_products(json.loads(_fixture("ms_pfn_netflix.json")))
    assert (netflix["category"], netflix["unclear"], netflix["genre"]) == (None, True, "Application: Entertainment")
    # A game in the games genre Tools is a companion app, never confirmed; an application by its category, unconfirmed
    tools = lookup.from_store_product({"ProductKind": "Game", "Properties": {"Category": "Tools"}})
    assert (tools["category"], tools["detail"], tools["confirmed"]) == ("productivity", "companion", False)
    music = lookup.from_store_product({"ProductKind": "Application", "Properties": {"Category": "Music"}})
    assert (music["category"], music["confirmed"]) == ("audio", False)
    assert lookup.from_store_products({"Products": []})["status"] == "missing"
    dota = lookup.from_steam(json.loads(_fixture("steam_570.json")), "570")
    assert (dota["category"], dota["confirmed"]) == ("game", True)
    # Wallpaper Engine is type "game" with tool genres
    wallpaper = lookup.from_steam(json.loads(_fixture("steam_431960.json")), "431960")
    assert (wallpaper["category"], wallpaper["confirmed"]) == ("productivity", False)
    assert lookup.from_steam({"1": {"success": False}}, "1")["status"] == "missing"


def test_only_a_public_store_id_is_sent() -> None:
    assert lookup.store_request("android:com.example.app")[0] == PLAY.format("com.example.app")
    assert lookup.store_request("pfn:4df9e0f8.netflix_mcm4njqhnhss8")[0].endswith(
        "alternateId=PackageFamilyName&value=4df9e0f8.netflix_mcm4njqhnhss8&market=US&languages=en-US&fieldsTemplate=details")
    assert "bigIds=9NBLGGH2JHXJ" in lookup.store_request("msstore:9NBLGGH2JHXJ")[0]
    assert "XboxTitleId&value=1828326430" in lookup.store_request("xbox:1828326430")[0]
    assert lookup.store_request("steam:570")[0] == "https://store.steampowered.com/api/appdetails?appids=570&cc=us&l=en"
    # Family Safety's own ids, Switch titles, names and anything malformed: nothing goes out
    for key in ("fs:xboxplt:0123456789abcdef", "switch:0100152000022000", "name:xbox:minecraft", "pfn:example.paint",
                "android:not a package"):
        assert lookup.store_request(key) is None, key


async def test_a_store_lookup_reads_the_page_and_keeps_its_answer(hass: HomeAssistant, aioclient_mock) -> None:
    aioclient_mock.get(PLAY.format("com.mojang.minecraftpe"), text=_fixture("play_minecraft.html"))
    aioclient_mock.get(PLAY.format("com.example.gone"), status=404)
    aioclient_mock.get(PLAY.format("com.example.down"), status=503)
    book = await _book(hass, {})
    changed = []
    book.on_change = lambda: changed.append(1)
    book.note_used({"com.mojang.minecraftpe": "Minecraft", "com.example.gone": None, "com.example.down": None})
    assert book.queue == ["android:com.mojang.minecraftpe", "android:com.example.gone", "android:com.example.down"]
    for _ in range(3):
        await book.async_next()
    assert book.queue == []
    hit = book.lookup("com.mojang.minecraftpe")
    assert (hit.source, hit.category, hit.confirmed) == ("store", "game", True) and changed == [1]
    assert book.answers["android:com.example.gone"]["store"]["status"] == "missing"
    assert book.answers["android:com.example.down"]["store"]["status"] == "failed"
    # The request carried nothing but the id: a generic user agent, no cookies
    sent = [call for call in aioclient_mock.mock_calls if "mojang" in str(call[1])][0]
    assert sent[0] == "GET" and str(sent[1]) == PLAY.format("com.mojang.minecraftpe")
    # Kept: a new book reads it back, and it isn't looked up again until its re-check
    await book.async_flush()
    again = await _book(hass, {})
    assert again.lookup("com.mojang.minecraftpe").category == "game"
    again.note_used({"com.mojang.minecraftpe": None})
    # Nor is the failed one before tomorrow
    again.note_used({"com.example.down": None})
    assert again.queue == []
    today = dt_util.now().date()
    assert not cats.store_due(again.answers["android:com.mojang.minecraftpe"]["store"], today)
    assert cats.store_due(again.answers["android:com.mojang.minecraftpe"]["store"], today + timedelta(days=91))
    assert not cats.store_due(again.answers["android:com.example.gone"]["store"], today + timedelta(days=29))
    assert cats.store_due(again.answers["android:com.example.down"]["store"], today + timedelta(days=1))


async def test_lookups_skip_known_apps_and_keep_to_a_daily_limit(hass: HomeAssistant, aioclient_mock, monkeypatch) -> None:
    monkeypatch.setattr(cats, "STORE_PER_DAY", 1)
    aioclient_mock.get(PLAY.format("com.example.one"), text=_fixture("play_minecraft.html"))
    aioclient_mock.get(PLAY.format("com.example.two"), text=_fixture("play_minecraft.html"))
    book = await _book(hass, {"android:com.example.known": {"category": "game"}},
                       app_categories={"android:com.example.mine": {"category": "game"}})
    book.note_used({"com.example.known": None, "com.example.mine": None, "win32:x.exe": None, "title:t": None,
                    "0100152000022000": None, "com.example.one": None, "com.example.two": None})
    assert book.queue == ["android:com.example.one", "android:com.example.two"]
    assert await book.async_next() == "android:com.example.one"
    # Today's one lookup is used: the next waits for tomorrow
    assert await book.async_next() is None and book.queue == ["android:com.example.two"]
    assert aioclient_mock.call_count == 1
    # Off: nothing is queued or sent
    off = await _book(hass, {}, category_lookup=False)
    off.note_used({"com.example.three": None})
    assert off.queue == []


# The AI Task


def _ai_service(hass: HomeAssistant, answer: dict | None = None, fail: bool = False) -> list[ServiceCall]:
    calls: list[ServiceCall] = []

    async def generate(call: ServiceCall):
        calls.append(call)
        if fail:
            raise RuntimeError("the model is offline")
        return {"conversation_id": "x", "data": answer or {"category": "video", "detail": "streaming"}}

    hass.services.async_register("ai_task", "generate_data", generate, supports_response=SupportsResponse.ONLY)
    return calls


async def test_no_ai_is_asked_without_an_entity(hass: HomeAssistant, aioclient_mock) -> None:
    calls = _ai_service(hass)
    aioclient_mock.get(PLAY.format("com.netflix.example"), text=_fixture("play_netflix.html"))
    book = await _book(hass, {})
    book.note_used({"com.netflix.example": None})
    await book.async_next()
    assert calls == [] and book.lookup("com.netflix.example") is None
    assert book.describe("com.netflix.example")["source"] == "unknown"


async def test_the_ai_is_asked_only_when_the_store_is_unclear_and_once(hass: HomeAssistant, aioclient_mock) -> None:
    calls = _ai_service(hass)
    aioclient_mock.get(PLAY.format("com.netflix.example"), text=_fixture("play_netflix.html"))
    aioclient_mock.get(PLAY.format("com.mojang.minecraftpe"), text=_fixture("play_minecraft.html"))
    book = await _book(hass, {}, category_ai_task="ai_task.local")
    book.note_used({"com.netflix.example": "Netflix", "com.mojang.minecraftpe": None})
    await book.async_next()
    await book.async_next()
    # Minecraft's genre is sure: no question about it
    assert len(calls) == 1
    data = calls[0].data
    assert data["entity_id"] == "ai_task.local" and data["task_name"] == "Hearth app category"
    assert "Netflix" in data["instructions"] and "android:com.netflix.example" in data["instructions"]
    assert "leading subscription service" in data["instructions"]
    assert data["structure"]["category"]["selector"]["select"]["options"][-1] == "unknown"
    assert "interface" not in data["structure"]["category"]["selector"]["select"]["options"]
    hit = book.lookup("com.netflix.example")
    assert (hit.source, hit.category, hit.detail, hit.confirmed) == ("ai", "video", "streaming", False)
    # Cached: asked again neither now nor after a reload
    book.note_used({"com.netflix.example": "Netflix"})
    assert book.queue == []
    await book.async_flush()
    again = await _book(hass, {}, category_ai_task="ai_task.local")
    assert again.lookup("com.netflix.example").source == "ai"


async def test_an_ai_that_fails_is_asked_again_a_day_later(hass: HomeAssistant, freezer) -> None:
    calls = _ai_service(hass, fail=True)
    # Lookups off: the AI gets the id and the name only
    book = await _book(hass, {}, category_lookup=False, category_ai_task="ai_task.local")
    book.note_used({"x:xboxplt:0123456789abcdef": "Example Video (Xbox)"})
    await book.async_next()
    assert len(calls) == 1 and "Example Video (Xbox)" in calls[0].data["instructions"]
    assert book.answers["fs:xboxplt:0123456789abcdef"]["ai"]["failed"]
    book.note_used({"x:xboxplt:0123456789abcdef": "Example Video (Xbox)"})
    assert book.queue == []
    freezer.tick(timedelta(days=1))
    book.note_used({"x:xboxplt:0123456789abcdef": "Example Video (Xbox)"})
    assert book.queue == ["fs:xboxplt:0123456789abcdef"]


async def test_an_ai_s_loose_answer_never_loosens_a_limit(hass: HomeAssistant) -> None:
    calls = _ai_service(hass, {"category": "messaging", "detail": "none"})
    book = await _book(hass, {}, category_lookup=False, category_ai_task="ai_task.local")
    book.note_used({"com.example.chatty": "Chatty"})
    await book.async_next()
    assert len(calls) == 1
    hit = book.lookup("com.example.chatty")
    assert (hit.source, hit.category, hit.confirmed) == ("ai", "messaging", False)
    groups = groups_from_options({})
    p = placer(groups, {}, lookup=book.lookup, pools=pool_map(groups))("com.example.chatty")
    assert (p.pool, p.why) == (None, "suggested")
    # Anything the AI says that Hearth doesn't know is unknown; a detail under the wrong category is dropped
    assert lookup.parse_ai({"category": "spaceship"}) == {"category": None, "detail": None}
    assert lookup.parse_ai({"category": "game", "detail": "youtube"}) == {"category": "game", "detail": None}
    assert lookup.parse_ai(None) == {"category": None, "detail": None}


# The retired shared catalog, migrated once


def test_the_catalog_s_options_go_and_corrections_become_overrides() -> None:
    old = {"catalog_fetch": False, "catalog_share": True, "catalog_share_asked": True,
           "catalog_url": "https://catalog.example/", "catalog_relay": "https://relay.example/",
           "catalog_pools": {"companion": "games"}, "app_groups": {"com.example.game": "games"},
           "app_categories": {"android:com.example.mine": {"category": "news"}}}
    corrections = [
        {"key": "android:com.example.game", "category": "game"},
        {"key": "pfn:example.paint_8wekyb3d8bbwe", "category": "image"},
        {"key": "android:com.example.mine", "category": "game"},
        {"key": "xbox:1", "category": "video", "detail": "streaming"},
        {"key": "web:example.com", "category": "game"},
        {"key": "android:com.example.bad", "category": "interface"},
    ]
    out = migrated_options(old, corrections)
    assert not any(k.startswith("catalog_") and k != "catalog_pools" for k in out)
    # The pool map and the moves stay; fetching turned off means no store lookups
    assert out["catalog_pools"] == {"companion": "games"} and out["app_groups"] == {"com.example.game": "games"}
    assert out["category_lookup"] is False
    assert out["app_categories"] == {
        "android:com.example.mine": {"category": "news"},
        "android:com.example.game": {"category": "game"},
        "pfn:example.paint_8wekyb3d8bbwe": {"category": "image"},
        "xbox:1": {"category": "video", "detail": "streaming"},
    }
    # Nothing to migrate
    assert migrated_options({"app_groups": {}}, None) is None
    assert "category_lookup" not in migrated_options({"catalog_fetch": True}, [])


async def test_the_migration_runs_once_and_removes_the_old_copy(hass: HomeAssistant, hass_storage) -> None:
    entry = MockConfigEntry(domain=DOMAIN, options={"catalog_fetch": True, "catalog_share": True, "groups": []})
    entry.add_to_hass(hass)
    hass_storage[f"hearth.catalog.{entry.entry_id}"] = {
        "version": 1, "key": f"hearth.catalog.{entry.entry_id}",
        "data": {"seq": 5, "shards": {"android": {}}, "corrections": [{"key": "android:com.example.x", "category": "game"}]},
    }
    assert await async_migrate_catalog(hass, entry) is True
    await hass.async_block_till_done()
    assert entry.options == {"groups": [], "app_categories": {"android:com.example.x": {"category": "game"}}}
    assert f"hearth.catalog.{entry.entry_id}" not in hass_storage
    assert await async_migrate_catalog(hass, entry) is False


# Hearth's page and the household


async def test_the_page_shows_and_sets_what_apps_are(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator, hass_ws_client
) -> None:
    await _household_with_sam(hass, hass_client_no_auth)
    entry = hass.config_entries.async_entries(DOMAIN)[0]
    household = entry.runtime_data.household
    # Sam's apps the household doesn't place by a list join the lookup queue (HearthTube is in the tests' Video list)
    assert household.categories_book.queue == ["android:com.example.game"]
    household.categories_book.answers = {
        "android:com.example.game": {"store": {"status": "found", "category": None, "unclear": True},
                                     "ai": {"category": "game", "detail": None}},
    }
    household.recompute()
    ws = await hass_ws_client(hass)
    config = (await _ws(ws, {"type": "hearth/config"}))["result"]
    rows = {r["package"]: r for r in config["apps"]}
    assert (rows["com.example.game"]["source"], rows["com.example.game"]["category"]) == ("ai", "game")
    c = config["categories"]
    assert c["lookup"] is True and c["ai_entity"] is None and c["starter"] > 350
    assert c["sources"]["ai"] >= 1 and c["pools"]["game"] == "games" and c["labels"]["youtube"] == "YouTube"
    assert "interface" in c["category_choices"] and c["detail_choices"]["streaming"] == "video"
    assert "catalog" not in config

    # An adult moved it, then says what it is: the move goes, what it is decides
    await _ws(ws, {"type": "hearth/config/set", "key": "app_groups", "value": {"com.example.game": "other"}})
    await hass.async_block_till_done()
    answer = await _ws(ws, {"type": "hearth/apps/category", "app": "com.example.game", "category": "video", "detail": "streaming"})
    assert answer["success"], answer
    await hass.async_block_till_done()
    assert entry.options["app_categories"] == {"android:com.example.game": {"category": "video", "detail": "streaming"}}
    assert "com.example.game" not in entry.options["app_groups"]
    household = entry.runtime_data.household
    hit = household.categories_book.lookup("com.example.game")
    assert (hit.source, hit.detail, hit.confirmed) == ("override", "streaming", True)
    # None of Hearth's kinds, then back to Hearth's answer
    await _ws(ws, {"type": "hearth/apps/category", "app": "com.example.game", "category": "none"})
    await hass.async_block_till_done()
    assert entry.options["app_categories"]["android:com.example.game"] == {"category": None}
    await _ws(ws, {"type": "hearth/apps/category", "app": "com.example.game", "category": "auto"})
    await hass.async_block_till_done()
    assert entry.options["app_categories"] == {}
    bad = await _ws(ws, {"type": "hearth/apps/category", "app": "com.example.game", "category": "spaceship"})
    assert not bad["success"]
    # The settings
    for key, value in (("category_lookup", False), ("category_ai_task", "ai_task.local"), ("catalog_pools", {"companion": "games"})):
        assert (await _ws(ws, {"type": "hearth/config/set", "key": key, "value": value}))["success"]
        await hass.async_block_till_done()
    book = entry.runtime_data.household.categories_book
    assert book.lookup_on is False and book.ai_entity == "ai_task.local"
    assert not (await _ws(ws, {"type": "hearth/config/set", "key": "category_ai_task", "value": "light.kitchen"}))["success"]
    assert not (await _ws(ws, {"type": "hearth/config/set", "key": "catalog_url", "value": "https://x.example/"}))["success"]


async def test_check_these_lists_guesses(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator
) -> None:
    await _household_with_sam(hass, hass_client_no_auth)
    household = hass.config_entries.async_entries(DOMAIN)[0].runtime_data.household
    # The TV says com.example.game is a game; Hearth's list says it's a companion app; another app is an AI's guess
    household.categories_book.starter = StarterList({
        "android:com.example.game": {"category": "productivity", "detail": "companion"},
    })
    household.categories_book.answers = {"android:com.example.news": {"ai": {"category": "game"}}}
    household.recompute()
    rows = {r["package"]: r for r in household.check_these({"com.example.game": "Game", "com.example.news": "News"})}
    assert rows["com.example.news"]["group"] == "games" and rows["com.example.news"]["why"] == "an AI guessed game"
    assert rows["com.example.game"]["group"] == OTHER and "the device says game" in rows["com.example.game"]["why"]
    # An adult's own answer is never second-guessed
    household.categories_book.overrides = {"android:com.example.game": {"category": "productivity", "detail": "companion"}}
    assert "com.example.game" not in {r["package"] for r in household.check_these({"com.example.game": "Game"})}


async def test_an_interface_app_from_the_starter_list_counts_nowhere(
    hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator
) -> None:
    await _household_with_sam(hass, hass_client_no_auth)
    household = hass.config_entries.async_entries(DOMAIN)[0].runtime_data.household
    assert household.days["person.sam"].groups["all"] == 900
    household.categories_book.starter = StarterList({"android:com.example.game": {"category": "interface"}})
    household.recompute()
    day = household.days["person.sam"]
    assert day.groups["all"] == 600 and not day.groups.get("games")
    assert "com.example.game" in household.never_held(household.membership())


async def test_the_setting_in_configure(hass: HomeAssistant, hass_client_no_auth: ClientSessionGenerator) -> None:
    await _household_with_sam(hass, hass_client_no_auth)
    await _option(hass, "app_categories", {"lookup": False, "ai_task": "ai_task.local"})
    entry = hass.config_entries.async_entries(DOMAIN)[0]
    assert (entry.options["category_lookup"], entry.options["category_ai_task"]) == (False, "ai_task.local")
    book = entry.runtime_data.household.categories_book
    assert book.lookup_on is False and book.ai_entity == "ai_task.local"


async def test_lookups_run_on_their_own(hass: HomeAssistant, aioclient_mock, freezer) -> None:
    """Started with the entry: the queue is worked one key per tick, and a new answer places apps again."""
    aioclient_mock.get(PLAY.format("com.example.one"), text=_fixture("play_minecraft.html"))
    book = await _book(hass, {})
    changed = []
    book.on_change = lambda: changed.append(1)
    jobs = []
    book.start(lambda job: jobs.append(hass.async_create_task(job)))
    book.note_used({"com.example.one": None})
    freezer.tick(cats.TICK + timedelta(seconds=1))
    from pytest_homeassistant_custom_component.common import async_fire_time_changed

    async_fire_time_changed(hass)
    await hass.async_block_till_done()
    assert jobs and changed == [1] and book.lookup("com.example.one").category == "game"
    book.stop()
    await hass.async_block_till_done()
