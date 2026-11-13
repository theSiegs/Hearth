"""Screen time sources: other integrations' entities the household adds (see docs/home-assistant-integration.md).

Two sorts:

- **Totals**: a sensor of time today (Family Link's Daily Screen Time, Family Safety's Screen Time, Nintendo's Used
  screen time). Its state is the time; an `apps` attribute of `{"package", "minutes"}` (Family Link's) breaks it down.
  Family Safety's Screen Time has no such attribute: its breakdown comes from the same child's Applications sensor
  (its `applications` list of `{"app_id", "app_name", "usage_minutes", ...}`), each app under its Microsoft app id
  (x:... Xbox, appx:... or win32:... Windows, a:... a phone), as a group's Family Safety apps name them. The Xbox
  Screen Time sensor's takes only the Xbox's (x:...).
- **Live**: a sensor whose state is what's being played now (Xbox's Now playing, a Switch presence Game sensor), or
  empty. The integration times it (live.py).
- **Phone app** (`phone_app: true`, live): a phone's last used app, from the Home Assistant companion app
  (`sensor.<device>_last_used_app`, Android). It's now playing only while the phone's screen is on and interactive
  (`screen`: a binary sensor, by default the same device's `binary_sensor.<device>_interactive`), never a launcher, and
  it isn't timed (the phone's own parental controls, or nothing, count its time). For phones without Hearth's app:
  a kid's Family Link phone, an adult's.

A source can be "the same device" as a Hearth device or another source, so their minutes are counted once.
"""

from __future__ import annotations

from dataclasses import dataclass
import re
from typing import Any

from homeassistant.const import STATE_UNAVAILABLE, STATE_UNKNOWN
from homeassistant.core import HomeAssistant
from homeassistant.helpers import entity_registry as er

from .counting import Reading

CONF_SOURCES = "sources"
CONF_TITLES = "titles"

# A live sensor saying one of these isn't playing anything
NOT_PLAYING = {"", "none", "offline", "online", "idle", "home", "away", "not playing", STATE_UNKNOWN, STATE_UNAVAILABLE}

_UNITS = {"s": 1, "sec": 1, "min": 60, "h": 3600, "hr": 3600, "d": 86400}
FS_DOMAIN = "microsoft_family_safety"
MAX_APPS = 200


@dataclass(frozen=True)
class Source:
    id: str
    entity_id: str
    person: str
    name: str
    live: bool = False
    # Another source's id, or "hearth:<device_id>": the same device, counted once
    same_as: str | None = None
    # The group its time is in when it can't say which app (games, for a Switch or Xbox)
    group: str | None = None
    # A companion app's last used app: playing only while [screen] (else the phone's Interactive sensor) is on; untimed
    phone_app: bool = False
    screen: str | None = None

    @property
    def reading_source(self) -> str:
        return f"{'live' if self.live else 'source'}:{self.id}"


def sources_from_options(options: dict[str, Any]) -> list[Source]:
    return [
        Source(
            id=s["id"],
            entity_id=s["entity_id"],
            person=s["person"],
            name=s.get("name") or s["entity_id"],
            live=bool(s.get("live")),
            same_as=s.get("same_as") or None,
            group=s.get("group") or None,
            phone_app=bool(s.get("phone_app")),
            screen=s.get("screen") or None,
        )
        for s in options.get(CONF_SOURCES, [])
    ]


LAST_USED_APP = "_last_used_app"
INTERACTIVE = "_interactive"
# What a phone shows between apps: its home screen and the system's own screens
_NOT_APPS = ("launcher", "com.android.systemui", "com.google.android.permissioncontroller", "com.android.settings")


def is_phone_app(entity_id: str) -> bool:
    """A companion app's Last used app sensor, by its entity id."""
    return entity_id.startswith("sensor.") and entity_id.endswith(LAST_USED_APP)


def screen_entity(hass: HomeAssistant, source: Source) -> str | None:
    """A phone app source's screen sensor: its own, else an Interactive binary sensor of the same device, else the
    one named after the sensor (binary_sensor.<device>_interactive)."""
    if source.screen:
        return source.screen
    registry = er.async_get(hass)
    entry = registry.async_get(source.entity_id)
    if entry is not None and entry.device_id:
        for other in er.async_entries_for_device(registry, entry.device_id):
            if other.domain == "binary_sensor" and other.entity_id.endswith(INTERACTIVE):
                return other.entity_id
    stem = source.entity_id.removeprefix("sensor.").removesuffix(LAST_USED_APP)
    return f"binary_sensor.{stem}{INTERACTIVE}"


def phone_app_playing(hass: HomeAssistant, source: Source) -> str | None:
    """The app a phone app source says is in use now (a package), or None: the screen isn't on and interactive (or
    can't be told), or it's the home screen."""
    screen = hass.states.get(screen_entity(hass, source) or "")
    if screen is None or screen.state != "on":
        return None
    package = now_playing(hass, source)
    if package is None or any(part in package.lower() for part in _NOT_APPS):
        return None
    return package


def device_key(source: Source, sources: dict[str, Source]) -> str:
    """The device a source's time is on: followed through "same as" (a Hearth device is its own id)."""
    seen: set[str] = set()
    current = source
    while current.same_as and current.id not in seen:
        seen.add(current.id)
        if current.same_as.startswith("hearth:"):
            return current.same_as.removeprefix("hearth:")
        nxt = sources.get(current.same_as)
        if nxt is None:
            break
        current = nxt
    return f"source:{current.id}"


def _seconds(value: Any, unit: str | None) -> float | None:
    try:
        number = float(value)
    except (TypeError, ValueError):
        return None
    if number != number or number < 0:
        return None
    return number * _UNITS.get((unit or "min").lower(), 60)


def totals_reading(hass: HomeAssistant, source: Source) -> Reading | None:
    """A totals source's reading now; None while its sensor has no number."""
    state = hass.states.get(source.entity_id)
    if state is None:
        return None
    total = _seconds(state.state, state.attributes.get("unit_of_measurement"))
    if total is None:
        return None
    items: dict[str, float] = {}
    apps = state.attributes.get("apps")
    if isinstance(apps, list):
        for app in apps[:MAX_APPS]:
            if not isinstance(app, dict):
                continue
            package = app.get("package") or app.get("name")
            seconds = _seconds(app.get("minutes"), "min")
            if seconds is None:
                seconds = _seconds(app.get("seconds"), "s")
            if isinstance(package, str) and package and seconds is not None:
                items[package[:128]] = max(items.get(package[:128], 0.0), seconds)
    else:
        items = family_safety_apps_today(hass, source.entity_id)
    return Reading(source.reading_source, min(total, 86400.0), items, source.group)


def fs_applications_of(hass: HomeAssistant, entity_id: str) -> tuple[str, str | None] | None:
    """A Family Safety child's Screen Time sensor (unique id <entry>_<account>_screentime) or Xbox Screen Time
    (<entry>_<account>_xbox_screentime): the same child's Applications sensor (<entry>_<account>_app_count), with the
    app id prefix its apps must have (x:xboxplt: for the Xbox's; x:windowsplt: ids are Windows Store apps), else
    None."""
    registry = er.async_get(hass)
    entry = registry.async_get(entity_id)
    if entry is None or entry.platform != FS_DOMAIN or entry.domain != "sensor":
        return None
    unique_id = str(entry.unique_id)
    if unique_id.endswith("_xbox_screentime"):
        stem, prefix = unique_id.removesuffix("_xbox_screentime"), "x:xboxplt:"
    elif unique_id.endswith("_screentime"):
        stem, prefix = unique_id.removesuffix("_screentime"), None
    else:
        return None
    applications = registry.async_get_entity_id("sensor", FS_DOMAIN, f"{stem}_app_count")
    return (applications, prefix) if applications else None


def family_safety_apps_today(hass: HomeAssistant, entity_id: str) -> dict[str, float]:
    """Microsoft app id -> seconds today, of the apps used today, from the Applications sensor of the Family Safety
    child whose Screen Time [entity_id] is; empty for any other sensor."""
    found = fs_applications_of(hass, entity_id)
    state = hass.states.get(found[0]) if found else None
    applications = state.attributes.get("applications") if state else None
    if not found or not isinstance(applications, list):
        return {}
    prefix = found[1]
    items: dict[str, float] = {}
    for app in applications[:500]:
        if not isinstance(app, dict) or not isinstance(app_id := app.get("app_id"), str) or not app_id:
            continue
        if prefix is not None and not app_id.startswith(prefix):
            continue
        seconds = _seconds(app.get("usage_minutes"), "min")
        if seconds:
            items[app_id[:128]] = max(items.get(app_id[:128], 0.0), seconds)
    # The most used, as many as an apps attribute would give
    return dict(sorted(items.items(), key=lambda item: -item[1])[:MAX_APPS])


def now_playing(hass: HomeAssistant, source: Source) -> str | None:
    """What a live source says is being played, or None."""
    state = hass.states.get(source.entity_id)
    if state is None:
        return None
    value = (state.state or "").strip()
    if value.lower() in NOT_PLAYING:
        return None
    return value[:128]


def normalize(name: str) -> str:
    """A name for matching: lower case, letters and digits, without "edition" and trademark marks."""
    name = name.lower().replace("™", "").replace("®", "")
    name = re.sub(r"\b(edition|for nintendo switch|nintendo switch 2 edition|java|bedrock)\b", " ", name)
    return re.sub(r"[^a-z0-9]+", " ", name).strip()


@dataclass(frozen=True)
class Title:
    id: str
    name: str
    matches: frozenset[str]  # normalized names and packages
    raw: tuple[str, ...] = ()  # as the adult chose them (packages, played names)


def titles_from_options(options: dict[str, Any]) -> list[Title]:
    return [
        Title(
            t["id"],
            t["name"],
            frozenset(normalize(m) for m in [t["name"], *t.get("matches", [])]),
            tuple(t.get("matches", [])),
        )
        for t in options.get(CONF_TITLES, [])
    ]


def title_key(titles: list[Title], item: str) -> str:
    """The key an app or played name counts under: its title's, when one matches."""
    wanted = normalize(item)
    for title in titles:
        if wanted in title.matches:
            return f"title:{title.id}"
    return item
