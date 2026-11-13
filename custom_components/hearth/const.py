"""Constants for the Hearth integration."""

from datetime import timedelta

DOMAIN = "hearth"
# The device API's and the household summary's shape (docs/home-assistant-integration.md, Contract): goes up only
# when a field changes meaning or type, becomes required, or goes; never for an added field. 2: the household summary's
# headline, lines and actions (glance.py): added fields, but the bump tells an app they are there
CONTRACT = 2

# Config entry data: the household's Hearth devices (TVs, phones), by the device's own stable id
CONF_DEVICES = "devices"
CONF_KIND = "kind"
CONF_SECRET_HASH = "secret_hash"
CONF_MODEL = "model"
CONF_SW_VERSION = "sw_version"

# A device not heard from in this long counts as not connected (a TV posts at least every 10 minutes)
CONNECTED_WITHIN = timedelta(minutes=15)

# Pairing: how long a device's request waits for an administrator, and how long an approved secret waits for it
PAIRING_EXPIRES = timedelta(minutes=10)
APPROVED_EXPIRES = timedelta(minutes=2)
# At most this many pairing requests wait at once, and one address may ask this often
MAX_PENDING_PAIRINGS = 5
PAIRING_INTERVAL_PER_ADDRESS = timedelta(seconds=10)
# A pairing ticket (a paired TV vouching for another TV of its household, or for a parent's phone): single use
TICKET_EXPIRES = timedelta(minutes=5)
MAX_TICKETS = 10
EVENT_DEVICE_PAIRED = "hearth_device_paired"

# A status post bigger than this is refused
MAX_STATUS_BYTES = 64 * 1024
# A device may post this many times in STATUS_WINDOW (it posts within ~2 s of a change, and every 2 minutes)
MAX_STATUS_POSTS = 20
STATUS_WINDOW = timedelta(seconds=60)

STORAGE_VERSION = 1
STORAGE_KEY = "hearth.status"

SIGNAL_STATUS = "hearth_status_{}"
SIGNAL_DEVICE_ADDED = "hearth_device_added"

# What a device is: Hearth on a TV, or Hearth Mobile on a phone or tablet
KIND_TV = "tv"
KIND_MOBILE = "mobile"
KINDS = (KIND_TV, KIND_MOBILE)

# What a device can do, for new features: a device may say so in its status (`caps`); one that never did gets its
# kind's (default_caps). The kind stays who the device is (a TV's profiles, a phone's person) and what it may vouch
# for; caps say only what it can be sent. commands.play: hearth.play_on_tv; events: HearthTube's started videos;
# push: an ntfy channel for "something changed" pings; notices: attention items in its state document
CAP_PLAY = "commands.play"
CAP_EVENTS = "events"
CAP_PUSH = "push"
CAP_NOTICES = "notices"
CAPS = (CAP_PLAY, CAP_EVENTS, CAP_PUSH, CAP_NOTICES)
MAX_CAPS = 16


def default_caps(kind: str | None) -> frozenset[str]:
    """What a device of [kind] could do before devices said: a TV plays and posts events, a phone gets pings."""
    if kind == KIND_TV:
        return frozenset((CAP_PLAY, CAP_EVENTS))
    if kind == KIND_MOBILE:
        return frozenset((CAP_PUSH,))
    return frozenset()

TV_STATES = ["off", "idle", "paused", "playing"]

# A phone's person (set when it pairs); options: TV profile_id -> person
CONF_PERSON = "person"
CONF_PROFILES = "profiles"
CONF_GROUPS = "groups"
CONF_GROUP_APPS = "group_apps"
# Groups whose time isn't screen time: not counted in All screen time, not held when it runs out
CONF_OUTSIDE_ALL = "outside_all"
# People whose phone may share with a launcher's tile exchange (scrubbed layouts only): a parent's choice
CONF_TILE_EXCHANGE = "tile_exchange_share"
# Options: voice assistants (Assist calls without a Home Assistant user) may use Hearth's LLM API (llm_api.py); off
CONF_VOICE_ASSISTANTS = "voice_assistants"
# Options: {person: "kid" | "adult"}, set on Hearth's page
CONF_ROLES = "roles"
# Options: {device_id: media_player entity}: a TV's own media player (the androidtv or cast one), for apps' tiles
CONF_MEDIA_PLAYERS = "media_players"
# Options: [{"entity_id", "person"}]: the person is locked while any of their lock entities is on
CONF_LOCKS = "locks"
# Options: the ntfy server phones are pinged through when their state changes (push.py); none: no pings
CONF_PUSH_SERVER = "push_server"
# A phone's own random ntfy topic (entry data, made when it pairs)
CONF_PUSH_TOPIC = "push_topic"

SIGNAL_PEOPLE = "hearth_people"
# A device asked to pair, or its pairing was answered
SIGNAL_PAIRINGS = "hearth_pairings"
# A one-shot command was queued for a TV (commands.py): its held wait wakes
SIGNAL_COMMANDS = "hearth_commands"
# An attention item the TVs show (notices) came or went: their held waits look again
SIGNAL_NOTICES = "hearth_notices"

EVENT_BUDGET_REACHED = "hearth_budget_reached"
EVENT_PLAYING_TOGETHER = "hearth_playing_together"
EVENT_VIDEO_STARTED = "hearth_video_started"

# A kids profile's started videos, or a parent's YouTube blocks, changed
SIGNAL_WATCH = "hearth_watch"
# A device may post its events this many times in STATUS_WINDOW (each post carries at most 50)
MAX_EVENT_POSTS = 10
# A TV may press its notices' buttons this many times in STATUS_WINDOW
MAX_NOTICE_POSTS = 6

# Android app categories a device may report for its apps (ApplicationInfo.category, lower case)
APP_CATEGORIES = (
    "game", "video", "audio", "image", "social", "messaging", "news", "maps", "productivity", "accessibility"
)
