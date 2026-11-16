"""Looking an app up (categories.py): a store's genre, and, when that's unclear, the owner's AI Task entity.

Stores, each asked for one public id with a fixed language and market, and no cookies kept:

- **Google Play** (`android:<package>`): the app's page, its schema.org data (`application/ld+json`) giving
  `applicationCategory` (Play's genre id: GAME_PUZZLE, SOCIAL, COMMUNICATION...), the app's name and its one-line
  description.
- **Microsoft Store** (`msstore:<product id>`, `xbox:<title id>`, `pfn:<package family name>`): the public
  displaycatalog API's product kind (Game or Application) and category.
- **Steam** (`steam:<app id>`): the store's appdetails type and genres.

Switch titles aren't looked up: every one is a game by the platform rule (limits.placer's hint).

Only the mappings the old App Facts classifier was sure of confirm a category (its tools' Play genre map, store
rules for games); a genre too broad to say (Entertainment, Lifestyle, Education...) is unclear and may go to an AI; a
genre outside the ten (Shopping, Finance...) is none of them. A store never confirms a loose category (messaging,
accessibility) nor any detail: categories.CategoryBook marks such an answer unconfirmed.
"""

from __future__ import annotations

import json
import logging
import re
from typing import Any
from urllib.parse import quote

from homeassistant.core import HomeAssistant

from .categories import DETAILS, clean_answer, namespace
from .const import APP_CATEGORIES

_LOGGER = logging.getLogger(__name__)

PLAY_URL = "https://play.google.com/store/apps/details?id={id}&hl=en_US&gl=US"
DISPLAYCATALOG = "https://displaycatalog.mp.microsoft.com/v7.0/"
MARKET = "market=US&languages=en-US"
STEAM_URL = "https://store.steampowered.com/api/appdetails?appids={id}&cc=us&l=en"
# A generic browser's user agent: a store sees a request for one public id and nothing about Hearth's household
USER_AGENT = "Mozilla/5.0 (compatible)"
TIMEOUT_S = 30
MAX_BYTES = 4 * 1024 * 1024
ABOUT_MAX = 300
NAME_MAX = 80

_PACKAGE = re.compile(r"^[A-Za-z][A-Za-z0-9_]*(\.[A-Za-z0-9_]+)+$")
_MSSTORE = re.compile(r"^[0-9A-Za-z]{12}$")
_NUMBER = re.compile(r"^[1-9][0-9]{0,9}$")
_PFN = re.compile(r"^[a-z0-9][a-z0-9.\-]{0,120}_[a-z0-9]{13}$")
_LD_JSON = re.compile(r'<script[^>]*type="application/ld\+json"[^>]*>(.*?)</script>', re.S | re.I)

# Google Play: genre -> category, where the genre says it cleanly (the classifier's GENRES; every GAME_* is a game)
PLAY_GENRES = {
    "SOCIAL": "social",
    "DATING": "social",
    "VIDEO_PLAYERS": "video",
    "MUSIC_AND_AUDIO": "audio",
    "NEWS_AND_MAGAZINES": "news",
    "MAPS_AND_NAVIGATION": "maps",
    "PHOTOGRAPHY": "image",
    "ART_AND_DESIGN": "image",
    "PRODUCTIVITY": "productivity",
    "TOOLS": "productivity",
    "BUSINESS": "productivity",
}
# Genres too broad to map by rule (Netflix and a comedy-clip app are both Entertainment; a kids' app under Education
# may be a game or a study tool): unclear. Communication holds messengers but also browsers, accessibility and
# hearing tools, dialers and VPNs
PLAY_UNCLEAR = frozenset({"ENTERTAINMENT", "LIFESTYLE", "EDUCATION", "TRAVEL_AND_LOCAL", "COMICS", "PARENTING",
                          "COMMUNICATION"})
EMAIL_WORDS = re.compile(r"e-?mail|\bmail\b|\binbox\b", re.I)
MESSENGER_WORDS = re.compile(r"messag|messenger|\bchat|\bsms\b|\btext(s|ing)?\b|\bcalls?\b|video call|\btalk\b", re.I)
NOT_MESSENGER_WORDS = re.compile(r"browser|\bweb\b|internet|search|vpn|accessib|hearing|deaf|blind|transcri|amplif|"
                                 r"caption|screen reader|keyboard", re.I)

# Microsoft Store: an application's category -> category (the classifier's STORE_CATEGORIES); one mapped to None,
# or missing, is unclear
STORE_CATEGORIES = {
    "music": "audio", "social": "social", "news & weather": "news", "navigation & maps": "maps",
    "photo & video": "image", "productivity": "productivity", "utilities & tools": "productivity",
    "business": "productivity", "developer tools": "productivity", "education": "productivity",
}
# Steam genres that make a "game" a tool (Wallpaper Engine is type "game")
STEAM_SOFTWARE = frozenset({"utilities", "design & illustration", "animation & modeling", "photo editing",
                            "video production", "software training", "web publishing", "audio production",
                            "education", "accounting", "game development"})


def _answer(category: str | None, *, confirmed: bool = False, unclear: bool = False, detail: str | None = None,
            genre: str | None = None, name: Any = None, about: Any = None, status: str = "found") -> dict[str, Any]:
    out: dict[str, Any] = {"status": status, "category": category, "detail": detail, "confirmed": confirmed,
                           "unclear": unclear}
    if genre:
        out["genre"] = str(genre)[:60]
    if isinstance(name, str) and name.strip():
        out["name"] = " ".join(name.split())[:NAME_MAX]
    if isinstance(about, str) and about.strip():
        out["about"] = " ".join(about.split())[:ABOUT_MAX]
    return out


def missing() -> dict[str, Any]:
    return _answer(None, status="missing")


def failed() -> dict[str, Any]:
    return _answer(None, status="failed")


# Google Play


def is_clear_messenger(name: str | None, about: str | None) -> bool:
    text = f"{name or ''} {about or ''}"
    return bool(MESSENGER_WORDS.search(text)) and not NOT_MESSENGER_WORDS.search(text)


def is_email(name: str | None, about: str | None) -> bool:
    return bool(EMAIL_WORDS.search(name or "")) or (
        bool(EMAIL_WORDS.search(about or "")) and not MESSENGER_WORDS.search(f"{name or ''} {about or ''}"))


def from_play(genre: str | None, name: str | None = None, about: str | None = None) -> dict[str, Any]:
    """A Play genre id as an answer: a game or a clean genre confirmed; email under Communication productivity and a
    clear messenger messaging (neither confirmed: Communication isn't a sure genre); a broad genre unclear; anything
    else none of the ten."""
    g = (genre or "").upper()
    if g.startswith("GAME_") or g == "GAME":
        return _answer("game", confirmed=True, genre=g, name=name, about=about)
    if g in PLAY_GENRES:
        return _answer(PLAY_GENRES[g], confirmed=True, genre=g, name=name, about=about)
    if g == "COMMUNICATION" and is_email(name, about):
        return _answer("productivity", genre=g, name=name, about=about)
    if g == "COMMUNICATION" and is_clear_messenger(name, about):
        # Never confirmed (messaging is loose): Check these asks an adult, and an AI isn't asked
        return _answer("messaging", genre=g, name=name, about=about)
    if g in PLAY_UNCLEAR or not g:
        return _answer(None, unclear=True, genre=g or None, name=name, about=about)
    return _answer(None, genre=g, name=name, about=about)


def parse_play_page(html: str) -> dict[str, Any] | None:
    """{genre, name, about} from a Play app page's schema.org data; None when the page has none."""
    for block in _LD_JSON.findall(html or ""):
        try:
            data = json.loads(block)
        except ValueError:
            continue
        for item in data if isinstance(data, list) else [data]:
            if isinstance(item, dict) and item.get("applicationCategory"):
                return {"genre": str(item["applicationCategory"]), "name": item.get("name"),
                        "about": item.get("description")}
    return None


# Microsoft Store


def product_url(big_id: str) -> str:
    return f"{DISPLAYCATALOG}products?bigIds={quote(big_id)}&{MARKET}"


def lookup_url(id_type: str, value: str) -> str:
    return f"{DISPLAYCATALOG}products/lookup?alternateId={id_type}&value={quote(value)}&{MARKET}&fieldsTemplate=details"


def from_store_product(product: dict[str, Any]) -> dict[str, Any]:
    """A displaycatalog product as an answer: a Game confirmed (one in the games genre Tools is a companion app,
    unconfirmed); an Application by its category, unconfirmed; an unmapped category unclear."""
    props = product.get("Properties") or {}
    loc = (product.get("LocalizedProperties") or [{}])[0] or {}
    name, about = loc.get("ProductTitle"), loc.get("ShortDescription") or loc.get("ProductDescription")
    category = props.get("Category")
    genre = f"{product.get('ProductKind')}: {category}" if category else product.get("ProductKind")
    if product.get("ProductKind") == "Game":
        genres = {str(c).strip().lower() for c in [category, *(props.get("Categories") or [])] if c}
        if "tools" in genres:
            return _answer("productivity", detail="companion", genre=genre, name=name, about=about)
        return _answer("game", confirmed=True, genre=genre, name=name, about=about)
    cat = (category or "").strip().lower()
    mapped = STORE_CATEGORIES.get(cat)
    if mapped is None:
        return _answer(None, unclear=True, genre=genre, name=name, about=about)
    return _answer(mapped, detail="education" if cat == "education" else None, genre=genre, name=name, about=about)


def from_store_products(data: Any) -> dict[str, Any]:
    """The first Game product's answer, else the first Application's; missing when none."""
    products = [p for p in (data or {}).get("Products") or [] if isinstance(p, dict)]
    products = [p for p in products if p.get("ProductKind") in ("Game", "Application")]
    if not products:
        return missing()
    product = next((p for p in products if p.get("ProductKind") == "Game"), products[0])
    return from_store_product(product)


# Steam


def from_steam(data: Any, appid: str) -> dict[str, Any]:
    """A Steam appdetails answer: a game confirmed, unless its genres make it a tool; software by its genres,
    unconfirmed."""
    record = (data or {}).get(str(appid)) or {}
    if not record.get("success"):
        return missing()
    d = record.get("data") or {}
    genres = {str(g.get("description", "")).lower() for g in d.get("genres") or [] if isinstance(g, dict)}
    shown = ", ".join(sorted(genres))[:60] or None
    genre = f"{d.get('type')}: {shown}" if shown else d.get("type")
    name, about = d.get("name"), d.get("short_description")
    if d.get("type") == "game" and not genres & STEAM_SOFTWARE:
        return _answer("game", confirmed=True, genre=genre, name=name, about=about)
    if genres & {"education", "software training"}:
        return _answer("productivity", detail="education", genre=genre, name=name, about=about)
    if genres & STEAM_SOFTWARE:
        return _answer("productivity", genre=genre, name=name, about=about)
    return _answer(None, unclear=True, genre=genre, name=name, about=about)


# Fetching


def store_request(key: str) -> tuple[str, str] | None:
    """(url, kind) of the one request that looks [key] up, or None when no store answers for it (or its id isn't
    well formed: nothing is sent)."""
    ns, value = namespace(key), key.split(":", 1)[-1]
    if ns == "android" and _PACKAGE.match(value):
        return PLAY_URL.format(id=quote(value)), "play"
    if ns == "msstore" and _MSSTORE.match(value):
        return product_url(value.upper()), "msstore"
    if ns == "xbox" and _NUMBER.match(value):
        return lookup_url("XboxTitleId", value), "msstore"
    if ns == "pfn" and _PFN.match(value):
        return lookup_url("PackageFamilyName", value), "msstore"
    if ns == "steam" and _NUMBER.match(value):
        return STEAM_URL.format(id=value), "steam"
    return None


async def _get(session, url: str) -> tuple[int, bytes]:
    import aiohttp

    async with session.get(
        url, headers={"User-Agent": USER_AGENT, "Accept-Language": "en-US"},
        timeout=aiohttp.ClientTimeout(total=TIMEOUT_S), allow_redirects=True,
    ) as resp:
        if resp.status != 200:
            return resp.status, b""
        data = bytearray()
        async for chunk in resp.content.iter_chunked(64 * 1024):
            data += chunk
            if len(data) > MAX_BYTES:
                break
        return resp.status, bytes(data)


async def async_store(session, key: str) -> dict[str, Any]:
    """The store's answer for [key]: found (with a category or not), missing, or failed (offline, an odd answer:
    tried again the next day)."""
    request = store_request(key)
    if request is None:
        return missing()
    url, kind = request
    try:
        status, data = await _get(session, url)
    except Exception as err:  # noqa: BLE001 - offline, a timeout, a refused connection: tried again tomorrow
        _LOGGER.debug("Hearth couldn't look %s up: %s", key, err)
        return failed()
    if status == 404:
        return missing()
    if status != 200:
        return failed()
    try:
        if kind == "play":
            page = parse_play_page(data.decode("utf-8", errors="replace"))
            return from_play(page["genre"], page["name"], page["about"]) if page else failed()
        parsed = json.loads(data.decode("utf-8"))
        if kind == "steam":
            return from_steam(parsed, key.split(":", 1)[1])
        return from_store_products(parsed)
    except (ValueError, TypeError, AttributeError, KeyError) as err:
        _LOGGER.debug("Hearth couldn't read the store's answer for %s: %s", key, err)
        return failed()


# Asking an AI (Home Assistant's AI Task)

AI_CATEGORIES = (*APP_CATEGORIES, "unknown")
AI_DETAILS = ("none", *DETAILS)
INSTRUCTIONS = """You sort apps into categories for a family screen-time tool. Say what this app is.
category: game (games), video (watching video or TV), audio (music, podcasts, radio, audiobooks), image (photos,
drawing, image editing), social (social networks and feeds), news (news and magazines), maps (map and navigation apps
only; not airlines, hotels, theme parks, ride or travel booking), productivity (work, school, office, utility and
learning tools), accessibility (helps people with disabilities use the device), messaging (chat, calls, SMS; not
email, not a web browser), or unknown.
detail: youtube (YouTube or YouTube Kids), streaming (a TV and film streaming service), education (a learning app),
companion (a platform's hub, store, remote or game launcher, not the game itself), system (a phone's or console's own
system app or a parental control), or none.
Answer unknown when the app fits none of these or you are not sure what it is: unknown is always better than a wrong
category.

App: {name}
Store id: {key}
{about}"""


def ai_request(entity_id: str, key: str, name: str | None, about: str | None) -> dict[str, Any]:
    """The ai_task.generate_data call asking what one app is, with structured output: the app's name, its store id
    and the store's one-line description, nothing else."""
    return {
        "task_name": "Hearth app category",
        "entity_id": entity_id,
        "instructions": INSTRUCTIONS.format(
            name=(name or "not known")[:NAME_MAX], key=key,
            about=f"Store description: {about[:ABOUT_MAX]}" if about else "No store description.",
        ),
        "structure": {
            "category": {"description": "What the app is", "required": True,
                         "selector": {"select": {"options": list(AI_CATEGORIES)}}},
            "detail": {"description": "A finer kind, or none", "required": True,
                       "selector": {"select": {"options": list(AI_DETAILS)}}},
        },
    }


def parse_ai(data: Any) -> dict[str, Any]:
    """{category, detail} from the AI's structured answer; anything Hearth doesn't know is unknown (None). Never
    System screens: only a list puts an app there."""
    data = data if isinstance(data, dict) else {}
    category = str(data.get("category") or "").strip().lower()
    detail = str(data.get("detail") or "").strip().lower()
    category, detail = clean_answer(category, detail, APP_CATEGORIES)
    return {"category": category, "detail": detail}


async def async_ask_ai(hass: HomeAssistant, entity_id: str, key: str, name: str | None,
                       about: str | None) -> dict[str, Any] | None:
    """What the owner's AI Task entity says the app is ({category, detail}, either None for unknown); None when it
    couldn't answer (no such entity, an error)."""
    if not hass.services.has_service("ai_task", "generate_data"):
        return None
    try:
        response = await hass.services.async_call(
            "ai_task", "generate_data", ai_request(entity_id, key, name, about), blocking=True, return_response=True
        )
    except Exception as err:  # noqa: BLE001 - the entity's own errors (offline model, quota): asked again tomorrow
        _LOGGER.debug("Hearth's AI question about %s failed: %s", key, err)
        return None
    return parse_ai((response or {}).get("data"))
