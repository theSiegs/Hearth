"""Constants for the Hearth integration."""

from datetime import timedelta

DOMAIN = "hearth"

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

TV_STATES = ["off", "idle", "paused", "playing"]
