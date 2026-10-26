"""Constants for the Hearth integration."""

from datetime import timedelta

DOMAIN = "hearth"

# Config entry data: the household's TVs, by the TV's own stable id
CONF_TVS = "tvs"
CONF_SECRET_HASH = "secret_hash"
CONF_MODEL = "model"
CONF_SW_VERSION = "sw_version"

# A TV not heard from in this long counts as not connected (it posts at least every 10 minutes)
CONNECTED_WITHIN = timedelta(minutes=15)

# Pairing: how long a TV's request waits for an administrator, and how long an approved secret waits for the TV
PAIRING_EXPIRES = timedelta(minutes=10)
APPROVED_EXPIRES = timedelta(minutes=2)
# At most this many pairing requests wait at once, and one address may ask this often
MAX_PENDING_PAIRINGS = 5
PAIRING_INTERVAL_PER_ADDRESS = timedelta(seconds=10)

# A status post bigger than this is refused
MAX_STATUS_BYTES = 64 * 1024
# A TV may post this many times in STATUS_WINDOW (it posts within ~2 s of a change, and every 2 minutes)
MAX_STATUS_POSTS = 20
STATUS_WINDOW = timedelta(seconds=60)

STORAGE_VERSION = 1
STORAGE_KEY = "hearth.status"

SIGNAL_STATUS = "hearth_status_{}"
SIGNAL_TV_ADDED = "hearth_tv_added"

TV_STATES = ["off", "idle", "paused", "playing"]
