"""Glint Panel's names, keys and defaults (docs/contracts/panel-config.md).

The serving integration's domain is never written here: it comes from the host (PanelHost.domain, Hearth's one DOMAIN
constant), and every wire name, store key and device identifier is built from it by the functions below. Moving the
panels to their own integration changes that one constant.
"""

from __future__ import annotations

from datetime import timedelta

# The document's schema: adding fields is a minor change (/1.1), renaming or removing one a new major
SCHEMA = "glint.panel-config/1"
# A pairing's kind for a Glint Panel
KIND = "panel"

STORE_VERSION = 1
# The Connected entity stays on this long after the panel's subscription closes (no heartbeat)
CONNECTED_GRACE = timedelta(minutes=2)
# Changes within this many seconds go to a panel as one document
PUSH_DELAY = 1.0
# A pair body's seed (the panel's settings before it paired), as JSON
MAX_SEED_BYTES = 16 * 1024
# A panel's long-lived access token: the lifespan Home Assistant's own profile page offers at most
TOKEN_DAYS = 3650
TOKEN_CLIENT = "Glint Panel"
# A panel may report this many times a minute (it reports on change only)
MAX_REPORTS = 30
REPORT_WINDOW = timedelta(seconds=60)


def ws_type(domain: str, name: str) -> str:
    """A WebSocket command's type: <domain>/panel/<name>."""
    return f"{domain}/panel/{name}"


def store_key(domain: str) -> str:
    return f"{domain}.panels"


def identifier(domain: str, device_id: str) -> tuple[str, str]:
    """The panel's device registry identifier: apart from the domain's other devices (a TV of the same id can't be
    taken over)."""
    return (domain, f"{IDENTIFIER_PREFIX}{device_id}")


IDENTIFIER_PREFIX = "panel:"


def unique_id(device_id: str, key: str) -> str:
    return f"panel_{device_id}_{key}"


def signal(domain: str, device_id: str) -> str:
    """One panel's values, view or connection changed: its entities write their state."""
    return f"{domain}_glint_panel_{device_id}"


def signal_added(domain: str) -> str:
    """A panel was paired: the platforms add its entities."""
    return f"{domain}_glint_panel_added"


# Entities (key -> default)

MOTIONS = ("still", "calm", "easy", "lively")
PHOTO_EVERY = (30, 60, 120, 300)
SELECTS: dict[str, tuple[object, tuple]] = {
    "motion": ("easy", MOTIONS),
    "photos_every": (60, PHOTO_EVERY),
}
SWITCHES: dict[str, bool] = {
    "photo_caption": True,
    "on_this_day": True,
    "calendar_titles": True,
    "pin_to_unlock": True,
    "someone_in_front": True,
    "dark_at_night": True,
    "says_who_has_a_message": True,
    "bluetooth_proxy": False,
}
# At most one panel's is on; kept house-wide (Panels.house_panel)
HOUSE_PANEL = "house_panel"
VIEWS = ("photos", "tiles", "night", "off", "dark_clock", "pairing")
NOTHING_ON_TABLET = "none"

# set_panel's other keys: entity ids, lists of them, and words
ENTITY_KEYS = ("photos", "presence", "voice_heard", "voice_reply", "voice_show")
ENTITY_LIST_KEYS = ("routines",)
BED_KEYS = ("bed_left", "bed_right")
PANEL_KEYS = (
    "people",
    "extra_areas",
    *ENTITY_LIST_KEYS,
    *BED_KEYS,
    *ENTITY_KEYS,
    "voice_reply_attribute",
    *SELECTS,
    *SWITCHES,
)

# set_panel_defaults' keys (house-wide)
HOUSE_KEYS = (
    "family_calendars",
    "person_calendars",
    "night",
    "doorbell_camera",
    "photos",
    "routine_windows",
    "commute_window",
)

DAYS = ("mon", "tue", "wed", "thu", "fri", "sat", "sun")
WEEKDAYS = DAYS[:5]
DEFAULT_WINDOWS = (
    {"word": "good morning", "from": "06:00", "until": "09:00", "days": list(DAYS), "after_bedtimes": False},
    {"word": "dinner", "from": "17:30", "until": "19:00", "days": list(WEEKDAYS), "after_bedtimes": False},
    {"word": "good night", "from": "21:00", "until": "23:30", "days": list(DAYS), "after_bedtimes": True},
)
DEFAULT_COMMUTE = {"from": "07:00", "until": "08:30", "days": list(WEEKDAYS)}
MAX_WINDOWS = 12
MAX_LIST = 50
