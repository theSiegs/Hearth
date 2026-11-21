# Glint Panel configuration, `glint.panel-config/1.1`

Owner: the integration that serves it, `<d>` below (today Hearth, `hearth`). A Glint Panel is a wall tablet, one per
room. Its settings live in Home Assistant: an administrator approves its pairing code and picks the room, and the
panel gets one versioned document over a WebSocket subscription.

**Signing in to Home Assistant is the owner's, not pairing's.** The panel uses a long-lived access token the owner
made (Profile > Security), any user's; panels may share one non-administrator user, a token each. Pairing makes
no user and hands out no token. The panel's **device secret** (from pairing) says which panel it is, on every
command below; the login only gets it onto Home Assistant's WebSocket.

The panel side finds `<d>` itself: it reads `get_config`'s `components` and uses the first of `glint_panel`, `hearth`
that is loaded. Every name below is built from `<d>`; nothing is registered under any other prefix. The panel refuses
a document whose `served_by` differs from the domain it asked.

In Hearth the panel part is its own package, `custom_components/hearth/glint_panel/`, so it can later move to its own
`glint_panel` integration (or partly into a voice integration). It imports nothing else of Hearth's: what it needs
comes through one interface (`glint_panel/host.py`, `PanelHost`), and a test checks it. Its storage is its own store
(`<d>.panels`); its entity unique ids are `panel_<device_id>_<key>`; its devices' identifiers are
`(<d>, "panel:<device_id>")`. Nothing a panel does touches Hearth's config entry: saving a panel's settings never
reloads it, and never ends a TV's `/wait`.

## Pairing

As for TVs and phones (`docs/contracts/device-api.md`), with kind `panel`:

    POST /api/<d>/pair
    {"device_id": "panel-1a2b3c4d", "kind": "panel", "name": "glint panel", "model": "Fire HD 10",
     "version": "1.0.0", "nonce": "...", "seed": {...}?}

- `device_id` is required (8 to 64 of `A-Z a-z 0-9 _ -`), as for every device. An id that is already a TV's or a
  phone's is refused (400), and a TV or phone can't pair with a panel's id.
- `seed` (optional): the panel's settings from before it paired, in the document's own shape, at most 16 KB as JSON
  (bigger, or not an object: 400). It is untrusted: only known fields are kept, an entity Home Assistant doesn't have
  is dropped, a field of the wrong type is dropped, and a value equal to the derived default isn't kept. It is taken
  once, at the panel's first pairing; house-wide values in it (calendars, night, doorbell, routine windows, commute,
  the photo album) are taken only while the house has none. A valid `proxy.key` is kept, so an ESPHome proxy already
  set up keeps working, and so is a valid `proxy.name` (see the document), so ESPHome sees the same device.
- The answer is as today: `{pairing_id, code, expires_in, approvers}`.
- A paired TV can't vouch for a panel: tickets are for TVs and phones only.
- Finding the server before pairing: a panel has no token yet, so it tries `POST /api/glint_panel/pair`, then
  `POST /api/hearth/pair`. Every error Hearth itself answers on these routes is JSON `{"error": "<reason>"}` (404
  `not_set_up` included); only Home Assistant's own plain 404 means "no such route". A future server keeps both rules.

Approval (Hearth's page, the administrators' phone notice, or Settings > Devices & services) asks only for a room (an
area, optional): no person, no role. Over the WebSocket: `{"type": "hearth/pairing", "pairing_id", "answer":
"approve", "area_id"?}`; the phone notice's service: `hearth.pairing_answer {pairing_id, answer, area_id?}`. On
approval:

- a device under the config entry, named `<area name> panel` (`Panel` without a room), its area set, `model` and
  `sw_version` from the pair body (later from reports), `configuration_url` to the panel's card on Hearth's page. It
  is renamed with its room until the owner renames it.

The poll's approved answer (`GET /api/<d>/pair/<pairing_id>`, header `X-Panel-Nonce`, or `X-Hearth-Nonce` as for TVs and
phones; any future server takes `X-Panel-Nonce`) is handed over once, as for
every device:

    {"status": "approved", "contract": 3, "device_id": "...", "secret": "...",
     "urls": {"internal": "...", "external": "..."}, "person": null, "role": null, "push": null, "client": null}

A later poll is 404: the secret is never given again. The panel keeps `secret` for the commands below.

Removing the panel's device in Home Assistant removes the panel (its secret stops working); the owner's login and
token are left alone (revoke the token in the user's profile to shut the panel out of Home Assistant too). Pairing
again gives a new secret; the panel's settings, room and proxy key stay, and so do its own Start, its last 10 Start
changes and the room layout it last reported (removing the device drops them).

## The WebSocket commands

On any Home Assistant login, each with the device secret, which alone says which panel it is: a wrong secret, or
another panel's: error `unauthorized`.

### `<d>/panel/subscribe {device_id, secret}`

Result `null`, then an event with the whole document at once, and again on every change (a setting set by a service
or an entity, a house-wide value, the device's area or name), batched 1 s: one service call that sets three things
is one push. A push is only sent when the document's `version` differs from the last one this subscription got.
While a subscription is open the panel's **Connected** entity is on; it goes off 2 minutes after the last one closes.
No heartbeat.

When the panel is removed or paired again, each open subscription gets one last event `{"unpaired": true}` and no
more.

### `<d>/panel/report {device_id, secret, view?, version?, on_tablet?, sw_version?, model?, room_layout?, unpaired?}`

Sent on change only (at most 30 a minute: error `too_often`). Sets the **View** entity (`photos`, `tiles`, `night`,
`off`, `dark_clock` (or `dark clock`), `pairing`; anything else: unknown), **On the tablet** (words, or a list of them
joined with `; `; none: `none`), and the device's `sw_version` / `model`. `version` is the document version the panel
holds (`get_panel` says whether it's up to date). `unpaired: true` removes the panel: its device and entities.

`room_layout` (since 1.1; the panel sends it only to a server whose document says `glint.panel-config/1.1` or later,
and only when it changes): the room's layout as the panel lays it out, in `start`'s tile shape, built-in kinds only.
The server keeps the last one per panel only to start a first `change_panel_start` from; it is not the panel's Start.
A layout that isn't right: error `invalid` (as `set_start`), nothing of the report taken. `null` forgets it.

### `<d>/panel/set_start {device_id, secret, start, base_version}`

The panel's whole `start` after an edit made on the wall (`{"tiles": [...]}`; its `changed` and `version` are ignored),
or `null` for "back to the room's layout". `base_version` is the `start.version` the edit started from (`null`, or
left out, when it started from the room's layout).

- At most 30 a minute per panel (counted apart from reports): error `too_often`.
- `base_version` differs from the stored `start.version` (both `null` counts as equal): error `stale`,
  `translation_placeholders.version` the stored one (`""` when the stored `start` is `null`). Nothing changes; the panel
  takes the document it is pushed (Home Assistant wins) and shows "changed elsewhere · undo".
- Not a right layout (see [The panel's own Start](#the-panels-own-start)): error `invalid`,
  `translation_placeholders.why` the first problem in words (`no tile kind toaster`, `lock.front_door is a normal
  state, never dealt`, `tiles heat_lamp and clock overlap`).
- Else it is stored, stamped `changed: {"by": "panel", "at": now, "undo": <new id>}`; the `start` before it is kept as
  one of the last 10 changes; the document is pushed to every subscription of that panel. Result `{"version": "<new
  start.version or null>", "undo": "<id>"}`.
- First time (migration): a panel that kept a Start on the tablet before the server had one sends it once with
  `base_version: null`; with the stored `start` still `null` it is taken as above.
- A wrong secret, or another panel's: `unauthorized`.

### `<d>/panel/verify_pin {device_id, secret, pin}`

A Parent PIN typed on the panel, checked by Hearth as phones' `verify_pin` is, in its own lockout (the panel's, keyed
`panel:<device_id>`): `FREE_TRIES` free, then 30 s doubling to an hour; a right PIN clears it. The panel never gets a
PIN or a hash.

- Right: result `{"person": "person.alex"}`.
- Wrong: error `wrong_pin` (`translation_placeholders.retry_in`: seconds of the lockout this guess started, `0` for
  none).
- Locked out: error `locked_out`, `translation_placeholders.retry_in` seconds.
- No Parent PIN set in Hearth: error `no_pin`.

(The handoff's `parent_pins` and `parent_pins_version` are not in the document: no PIN hash leaves Home Assistant.)

## The document

Sent whole, never as a diff. Every key is present; `null` or `[]` means "derive it" (the panel works out live things
such as presence and the room's thermostat itself).

```json
{
  "schema": "glint.panel-config/1",
  "served_by": "hearth",
  "version": "9c1e04aa",
  "panel": {"device_id": "panel-1a2b3c4d", "name": "Kitchen panel", "area_id": "kitchen",
            "extra_areas": [], "people": [], "house_panel": true, "panel_areas": ["bedroom", "kitchen"]},
  "look": {"motion": "easy"},
  "photos": {"camera": "camera.photo_album", "every_s": 60, "caption": true, "on_this_day": true},
  "calendars": {"family": ["calendar.family"], "person": {"person.alex": ["calendar.alex_work"]}, "titles": true},
  "wake": {"someone_in_front": true, "presence": null},
  "night": {"entity": "input_boolean.night_mode", "dark_at_night": true},
  "doors": {"pin_to_unlock": true, "doorbell_camera": null},
  "messages": {"shared_room_says_who": true},
  "routines": {"entities": [],
               "windows": [{"word": "good morning", "from": "06:00", "until": "09:00",
                            "days": ["mon", "tue", "wed", "thu", "fri", "sat", "sun"], "after_bedtimes": false}],
               "commute": {"from": "07:00", "until": "08:30", "days": ["mon", "tue", "wed", "thu", "fri"]}},
  "bed": null,
  "proxy": {"on": false, "name": "kitchen-panel", "key": "...base64..."},
  "voice": {"heard": null, "reply": null, "reply_attribute": null, "show": null},
  "news": {"seen": null},
  "start": null
}
```

- `version`: the first 8 hex digits of a SHA-256 of the rest of the document: it changes exactly when the content
  does.
- `schema` is `glint.panel-config/1.1` (1.1 added `start`, and `room_layout` in reports). The major is 1. Adding
  fields is a minor change, read by old panels. Renaming or
  removing one is a new major; old panels then keep their cached document.
- `panel.name`: the device's name (the owner's, when they renamed it). `panel.panel_areas`: every paired panel's area,
  sorted (the house panel needs it). `panel.house_panel`: at most one panel's is true.
- `look.motion`: `still` · `calm` · `easy` (default) · `lively`. `photos.every_s`: 30 · 60 (default) · 120 · 300.
- `photos.camera`: the panel's own album, else the house's, else `null`.
- `routines.windows` defaults: good morning 06:00–09:00 every day; dinner 17:30–19:00 weekdays; good night 21:00–23:30
  every day with `after_bedtimes: true`. `routines.commute` default: weekdays 07:00–08:30.
- `bed`: `null`, or `{"left": side | null, "right": side | null}`, a side being `{"connected": entity | null,
  "scripts": [entities], "positions": [entities]}`.
- `proxy.name`: the name the panel's seed gave (kept, so ESPHome sees the same device) or set with `set_panel`
  `proxy_name`; else the device's name as an ESPHome name (`kitchen-panel`, at most 31 characters). `proxy.key`: a
  32-byte ESPHome API encryption key (base64), made at the first pairing (or kept from the seed).
- `news.seen`: the `input_text` where the panel keeps which news it has shown, or `null` (the panel's own
  fallback). Set with `set_panel` `news_seen`.
- `voice` only names entities; the voice turn log, timers and the shared request entity belong to the voice
  integration (or plain helpers), never to the panel part.
- The one secret in it is `proxy.key`. The document goes only to the panel that owns it, over its own subscription;
  it is never in an entity's state or attributes, nor in a service's answer.

## The panel's own Start

`start` is `null` until something is placed: the panel lays out Start by its room rule, exactly as before 1.1. Once
something is placed (from the wall with `set_start`, or with `change_panel_start`):

```json
"start": {
  "tiles": [
    {"id": "clock",      "kind": "clock",      "col": 1, "row": 1, "w": 2, "h": 1},
    {"id": "calendar",   "kind": "calendar",   "col": 3, "row": 1, "w": 2, "h": 2},
    {"id": "room_stack", "kind": "room_stack", "col": 1, "row": 3, "w": 2, "h": 1,
     "deals": [{"entity": "fan.bedroom_fan", "when": "on"},
               {"entity": "light.porch", "when": {"from": "18:00", "until": "22:00", "days": ["mon", "tue"]}}]},
    {"id": "heat_lamp",  "kind": "entity", "entity": "switch.heat_lamp", "col": 7, "row": 3, "w": 2, "h": 1},
    {"id": "stack",      "kind": "stack", "name": "porch and yard",
     "entities": ["light.porch", "light.yard"], "col": 5, "row": 4, "w": 2, "h": 1}
  ],
  "changed": {"by": "home assistant", "at": "2026-11-21T19:40:00Z", "undo": "a41c07"},
  "version": "5e0d1a2b"
}
```

- Cells count from 1; `w`, `h` in cells. `col`, `row`, `w`, `h` are whole numbers from 1, and `col + w - 1 <= 8`,
  `row + h - 1 <= 8` (the page's larger side: 8 x 5 landscape, 5 x 8 portrait). Tiles may not overlap. The panel
  leaves out a tile that is off its page.
- `kind`: `clock`, `calendar`, `weather`, `climate_stack`, `family`, `arrivals`, `media_stack`, `room_stack`,
  `routines_stack` (each at most once), `entity` (needs `entity`), `stack` (hand-made: needs `name`, at most 40
  letters, and `entities`, 1 to 12 different ones). Anything else is refused. Other fields of a tile are dropped.
- `id`: `[a-z0-9_]{1,32}`, unique. A built-in kind's id is its kind; a new entity tile's is its entity's object id, a new
  stack's `stack`, with a number added on a clash (`stack2`).
- `deals` only on `room_stack` and `stack` tiles, each entity once: `when` is `"on"` or `{from, until, days}` (`HH:MM`,
  `mon`...`sun`). Never for `lock`, `binary_sensor`, `sensor`, `person`, `device_tracker`, `alarm_control_panel`, or a
  `cover` of class `door`, `garage` or `gate`: those are normal states, never alerts.
- Stacks derive their contents: `room_stack` lists no devices (the panel fills it from the room). Only placed tiles,
  hand-made stacks' members and `deals` are stored. The panel evaluates `deals` itself.
- At most 40 tiles and 16 KB of tiles as JSON.
- `changed`: who made the last change (`panel` from the wall, `home assistant` from a service, or the name a service
  call gave as `by`), when (UTC), and the undo id that takes it back.
- `version`: the first 8 hex digits of a SHA-256 of `tiles` only (a new stamp alone doesn't change it); `set_start`'s
  `base_version` is checked against it. The document's own `version` changes with any part of `start`.
- When Home Assistant renames an entity id, it is rewritten in every panel's `start` (`entity`, `entities`,
  `deals[].entity`, and the kept changes) and pushed; the tile keeps its id. An entity removed from Home Assistant is
  kept: the panel marks its tile until someone removes it.
- The last 10 changes are kept per panel in `<d>.panels`, each the `start` from before it with its undo id (oldest
  dropped). Pairing again keeps them; removing the panel's device drops them.

## Entities on each panel device

They show the panel part's store and write to it; nothing is restored from the state machine, so a restart shows what
the store has.

| Entity (key) | Type | Category | Values |
|---|---|---|---|
| `motion` | select | config | still · calm · easy · lively (default easy) |
| `photos_every` | select | config | `30` · `60` · `120` · `300` seconds, shown as 30 s · 1 min · 2 min · 5 min (default 60) |
| `photo_caption` | switch | config | on |
| `on_this_day` | switch | config | on |
| `calendar_titles` | switch | config | on (off = "busy") |
| `pin_to_unlock` | switch | config | on |
| `someone_in_front` | switch | config | on |
| `dark_at_night` | switch | config | on |
| `says_who_has_a_message` | switch | config | on |
| `house_panel` ("Shows rooms without a panel": device issues from rooms with no panel of their own show here) | switch | config | at most one on: turning one on turns the others off; turning it off leaves none until one is turned on. Until one is chosen: the first paired shared-room panel (no `people`) |
| `bluetooth_proxy` | switch | config | off |
| `connected` | binary_sensor | diagnostic | the subscription is open (2 min grace) |
| `view` | sensor (enum) | diagnostic | photos · tiles · night · off · dark_clock · pairing |
| `on_the_tablet` | sensor | diagnostic | words, e.g. `allow turning the screen off`; `none` |

Unique ids `panel_<device_id>_<key>`.

## Services (administrators and adults, and automations, as Hearth's other services check)

### `<d>.set_panel`

`device_id`: the one panel's Home Assistant device. Any of `people` (persons), `extra_areas` (areas), `routines`
(entities), `bed_left`, `bed_right` (a bed side), `photos`, `presence`, `voice_heard`, `voice_reply`, `voice_show`,
`news_seen` (entities), `voice_reply_attribute` (words), `proxy_name` (an ESPHome name), `motion`, `photos_every`, and every switch key above (`house_panel`
included). Left out: unchanged. `null` or `[]`: back to derived (for a switch: its default; `house_panel: null` goes
back to the derived house panel). An entity or area Home Assistant doesn't have is refused, naming it; a device that
isn't a panel is refused. The answer (`return_response`) is the effective document without its secrets (no
`proxy.key`, no `version`).

### `<d>.set_panel_defaults`

House-wide: `family_calendars` (calendars), `person_calendars` (`{person: [calendars]}`), `night` (entity),
`doorbell_camera` (camera), `photos` (the house's album), `routine_windows` (`[{word, from, until, days,
after_bedtimes?}]`, at most 12; times `HH:MM`, days `mon`…`sun`), `commute_window` (`{from, until, days}`). `null` or
`[]`: back to the default. Answers `{"defaults": ...}` as `get_panel` gives them.

### `<d>.change_panel_start`

`device_id` (the panel's device), `ops` (a list, applied in order, all or none), `by` (optional: who is changing it, at
most 40 letters; default `home assistant`). Cells from 1:

| op | fields | does |
|---|---|---|
| `add` | `kind` (default `entity`), `entity` (for `entity`), `size` `"2x1"` (default), `at` `[col, row]`? | places a tile; no `at`: the first fit from the top-left, row by row. Refused: a built-in kind already there, the same entity already placed on its own, an entity Home Assistant doesn't have, no room; `stack` (use `make_stack`) |
| `move` | `tile`, `at` | moves it there if it fits |
| `resize` | `tile`, `size` `"WxH"` | resizes it in place if it fits |
| `remove` | `tile` | takes it off Start (a hand-made stack's devices go back to the room stack) |
| `deals` | `tile` (`room_stack` or a `stack`), `entity`, `when` (`"on"`, `{from, until, days}`, or `null` to stop) | sets one device's "deals when" (in a `stack`, one of its members) |
| `make_stack` | `name`, `entities` (1 to 12), `size`?, `at`? | a hand-made stack; those devices' own `entity` tiles leave Start, and they leave other hand-made stacks (an emptied one goes) |
| `reset` | | `start: null` (the room's layout) |

The first change of a panel whose `start` is `null` starts from the `room_layout` it last reported; none reported yet:
refused, `the panel hasn't said its layout yet`. The result is checked as `set_start`'s, stamped, the `start` before it
kept as a change, and pushed. Answer: `{"changed": "test lamp placed at column 5, row 1; ...", "start": {...} | null,
"undo": "<id>"}`, the words of each op joined with `; `. Refused: nothing changes, and the error says why (`no room for
a 2×2 tile`, `no tile lamp`, `no op explode`).

### `<d>.undo_panel_start`

`device_id`, `undo` (an id from a change's answer, `changed.undo`, or `get_panel`'s `start_versions`), `by`?. Puts back
the `start` from before that change (any of the last 10) as a new change, pushes, and answers as `change_panel_start`
(`changed`: `change <id> undone`). An unknown or expired id is refused; nothing changes.

### `<d>.get_panel`

`device_id` optional (none: every panel). Answers `{"panels": [...], "defaults": {...}}`: per panel its `device_id`,
`ha_device_id`, `name`, `area_id`, `settings` (each key as `{"value", "source": "set" | "derived"}`), `connected`,
`view`, `on_the_tablet`, `signed_in_as` (`{"user", "token"}`: the names of the login its last subscription used, null
before one), `up_to_date` (the version it reported is the current one), `document` (without secrets), `start` (as in the
document) and `start_versions` (the kept Start changes, newest first, each `{"undo", "changed": {"by", "at"}}`);
each house-wide value as `{"value", "source"}`. Never a secret.

## Not yet built

- Hearth's page › panels (approve with a room, a card per panel with its lists, switches, overrides,
  connected/view/on the tablet and the proxy key step "add it in ESPHome", and one house-wide card). Until then a
  panel is approved from the pending list on Hearth's page (no room), the phone notice, or Settings > Devices &
  services (with a room), and set up with the entities and services.
