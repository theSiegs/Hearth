# Where a device is used (contract)

For a presence reader (which room, who is home): when a kid's phone or tablet was last used and whether it was on the
home network, and an event when someone switches profiles on a TV. These are stable; anything not listed here may
change without notice.

## Last interaction, for each phone or tablet

One sensor per paired phone or tablet (`sensor.<device>_last_interaction`), adults' devices too. Find them in the
entity registry: platform `hearth`, unique id `<device_id>_last_interaction`; then read `person`. Never build entity
ids from names (they follow the device's name, and the user may rename them). A TV has none: its profile sensor and
the event below say who is on it ([tv-entities.md](tv-entities.md)).

| | |
|---|---|
| `kind` | always `last_interaction`: find these sensors by it and `person` |
| State | when the device was last used (timestamp, to the minute), or unknown before its first use |
| `person` | the `person.*` id the device is paired for (its owner), or `null` |
| `device_id` | Hearth's id of the device |
| `last_interaction` | the state again, as local ISO 8601 |
| `last_interaction_local` | whether that post came straight over the home network (bool, `null` when unknown) |
| `last_user` | the `person.*` id of who used it then, when the device named a profile that is mapped to a person; else `null` |
| `last_post` | when the device last posted a status at all (to the minute), used or not |
| `local` | whether that last post came straight over the home network (bool, `null` when unknown) |

Example: Sam's tablet, used at home a minute ago.

```yaml
state: "2026-11-09T21:05:00+00:00"
kind: last_interaction
person: person.sam
device_id: tablet-0123456789ab
last_interaction: "2026-11-09T16:05:00-05:00"
last_interaction_local: true
last_user: null
last_post: "2026-11-09T16:06:00-05:00"
local: true
```

**Used** means a status post with the screen on, or one whose time today grew since the post before. A heartbeat
with the screen off moves `last_post` and `local` only. The sensor keeps its value while the device is quiet or off
(it is never unavailable) and across restarts.

**Who used it.** A phone or tablet is paired for one person, and Hearth doesn't know who is holding it: when a kid
picks up a sibling's tablet, `person` is still the owner. `last_user` is set only when the device's status names a
profile (`profile_id`, `profile_ref`) that the household mapped to a person; a device that names none leaves it
`null`. Read `last_user` first and fall back to `person`.

### Local: straight over the home network

Home Assistant is also reached through Home Assistant Cloud, a public hostname, a reverse proxy or a tunnel, and such
a request can arrive from this machine or a private address. So `local` is true only when **all** of these hold, and
false whenever one is unsure:

1. The request didn't come through Home Assistant Cloud's remote access (Home Assistant's own mark on the request).
2. It carries no header a proxy, tunnel or CDN adds: `Forwarded`, `X-Forwarded-For`, `X-Forwarded-Host`,
   `X-Forwarded-Proto`, `X-Forwarded-Server`, `X-Real-IP`, `Via`, `CF-Connecting-IP`, `CF-Ray`, `True-Client-IP`.
3. The other end of the connection itself (the socket's address, never what a forwarding header says) is a private
   (`10.0.0.0/8`, `172.16.0.0/12`, `192.168.0.0/16`, `fd00::/8`) or link-local address. Not this machine (loopback: a
   proxy or tunnel running beside Home Assistant), not Home Assistant OS's add-on network (`172.30.32.0/23`), and not
   one of Home Assistant's `trusted_proxies`. A VPN's or carrier's shared range (`100.64.0.0/10`) isn't home.
4. The device asked for a home address (the `Host` header): a private address, the host of Home Assistant's internal
   URL, a single-label name, or a name ending in `.local`, `.lan`, `.home`, `.internal`, `.home.arpa` or
   `.localdomain`. Never the external URL's host, even when the internal URL is the same. This covers a router that
   hands a forwarded connection on as its own address.

What this costs: a household whose devices reach Home Assistant only through a reverse proxy, or by the public name
from inside the house, reads `local: false` at home. False means "not shown to be at home", never "away".

What it can't see: a tunnel on another machine of the home network that passes requests on with none of the headers
above, to a home address. Hearth has no way to tell that from a tablet.

The status endpoint itself is unchanged: it still answers local addresses only, as Home Assistant sees them
([device-api.md](device-api.md)).

## `hearth_tv_profile_changed`

Fired when someone switches Google TV profiles on a paired Hearth TV.

| Field | |
|---|---|
| `device` | Hearth's id of the TV (as in `hearth_video_started`) |
| `name` | the TV's name |
| `area_id` | the area of the TV's device in Home Assistant, or `null` |
| `ha_device_id` | the TV's device id in Home Assistant's device registry (for its area when `area_id` is `null`), or `null` |
| `profile_ref` | the profile switched to (`name:<slug>`, the same on every TV), or `null` from a TV too old to send refs |
| `profile_id` | that TV's own key for it (`user:10`) |
| `kids_profile` | whether it's a kids profile (bool, or `null`) |
| `person` | the `person.*` id the profile is mapped to, or `null` |
| `from_profile_ref`, `from_profile_id`, `from_person` | the same for the profile switched away from |
| `at` | when Hearth heard of it (local ISO 8601 with offset) |

```yaml
event_type: hearth_tv_profile_changed
data:
  device: tv-0123456789abcdef
  name: The TV
  area_id: den
  ha_device_id: 0123456789abcdef0123456789abcdef
  profile_ref: name:sam
  profile_id: user:10
  kids_profile: true
  person: person.sam
  from_profile_ref: name:alex
  from_profile_id: user:0
  from_person: person.alex
  at: "2026-11-09T16:05:00-05:00"
```

It is fired only for a real switch: two status posts from the TV, both received since Home Assistant (or Hearth) last
started, the second in another profile and within 15 minutes of the TV's last post. So never:

- on the first report after a restart or a reload (the restored profile is not compared with);
- when a TV comes back after being off or off the network for 15 minutes or more, in whatever profile;
- for the same profile again, a profile the TV learned the name of, or one renamed in Google TV (same `profile_id`);
- for a post that names no profile (the chooser in front): the next named profile is compared with the last named one.

Who is on the TV now is the profile sensor's state ([tv-entities.md](tv-entities.md)); the event only says it changed.

A change to this page is a contract change: update its test (`ha_tests/test_device_presence.py`).
