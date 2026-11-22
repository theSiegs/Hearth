# Glint Panel configuration, `glint.panel-config/1.4`

Owner: the integration that serves it, `<d>` below (today Hearth, `hearth`). A Glint Panel is a wall tablet, one per
room. Its settings live in Home Assistant. It is set up over its WebSocket (`hello`, below; a room named in it, on an
administrator's or an adult's login, approves it at once, else an adult picks its room in Home Assistant), and it gets
one versioned document over a WebSocket subscription.

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

## Setting a panel up over its socket: `<d>/panel/hello` (since 1.4)

The panel signs in to Home Assistant before it is set up (its owner's long-lived token, as for every command), so it
asks for its secret on the WebSocket it already holds: no HTTP route, no code, no nonce, no poll. The panel sends
hello whenever it has a socket and no secret.

    {"type": "<d>/panel/hello", "device_id": "panel-1a2b3c4d5e6f7a8b", "name": "glint panel", "model": "Example tablet",
     "version": "2.0.0", "area": "Kitchen"?, "seed": {...}?, "replaces": false?}

- `device_id` as for pairing (8 to 64 of `A-Z a-z 0-9 _ -`); `name`, `model` (at most 64 letters) and `version` (32)
  are shown on the approval card; `area` is an area id or an area's name (any case), at most 100 letters; `seed` as for
  pairing (taken only when a new panel is made; at most 16 KB as JSON); `replaces: false` never takes an offline
  panel's place (a second tablet in a room).
- A subscription, on any login. Result `null`, then events:
  - `{"status": "pending"}`: waiting for an approval in HA (below); the answer comes later on the same subscription;
  - `{"status": "approved", "device_id", "secret", "name", "area_id", "urls": {"internal", "external"}}`.
    `device_id` may differ from the one sent (the tablet took a panel's place): the panel keeps it from then on;
  - `{"status": "denied"}`: refused in HA. A refused hello is answered `denied` for a day, whatever it names and on
    any login, then may wait again.
- Errors: `taken` (the id is a TV's or a phone's: one id is one device), `try_later` (20 panels wait already),
  `unavailable` (as for the other commands).
- **The acknowledgment is the panel's first `<d>/panel/subscribe` with that secret.** Until then every hello (an app
  restart, a reinstall, Home Assistant restarting, a dropped socket) is sent the approved event again, on the login it
  was approved for (or an administrator's or an adult's). Nothing is handed over once. The secret is kept in memory
  only, never in `<d>.panels`: after Home Assistant restarts the hello gets a fresh secret for that panel and the old
  one stops. A hello for it on any other login stops the approval (its secret no longer opens the panel) and waits for
  an approval in HA on that login, with its card and notice.
- A waiting hello is kept in `<d>.panels` (it outlives a restart) and never times out; one unseen for 30 days is
  dropped, with its card and notice. The same `device_id` saying hello again is the same entry, never a second one.

### How a hello is matched (first rule that fits)

1. **A known panel**: `device_id` is a panel's id or one of its `tablet_ids`. The same panel, with a new secret: the
   old secret stops at once (its subscriptions get `{"unpaired": true}`, and it is `unknown_panel` from then on).
   Settings, room, Start, proxy key and MAC, and name stay. The panel's **current tablet** is the id that last got its
   secret (by rule 1 or 2, or an approval in HA; the panel's own id until then). Two limits, so a healthy panel is
   never taken over:
   - an id that isn't the current tablet (an old tablet) waits for an approval in HA, unless the login is an
     administrator's or an adult's; approving it makes it the current tablet;
   - a panel that is connected now waits too, unless the login is an administrator's, an adult's or the panel's own
     (the one its subscription last signed in with). A panel that isn't connected (a reinstall) is set up again at
     once on any login but a kid's.
2. **Taking an offline panel's place**: `area` is an area HA has, `replaces` isn't `false`, and exactly one panel in
   that area isn't connected. The answer carries that panel's `device_id`; the hello's id joins the panel's
   `tablet_ids` (so rule 1 finds it after the next reinstall). Same device, entities, settings, Start, proxy key and
   MAC. The logbook says `<Area> panel moved to a new tablet`.
3. **A new panel**: `area` is an area HA has. Its device `<Area> panel` is made in that area before any entity is
   registered.
4. **Otherwise** (no area, or one HA doesn't have): it waits for an approval in HA.

For 2 minutes after Hearth loads (Home Assistant starting, or the entry reloading) every panel counts as connected, as
its socket may not be back yet: rule 2 takes no panel's place then (a hello naming a room is a new panel), rule 1
waits as for a connected panel, and no panel is offered as offline on the card or in `panels_offline`.

**Any login but a kid's.** Rules 1 to 3 are approved at once on any Home Assistant login, the panels' shared login
included (rule 1 within its two limits): a setup command that names a room needs no step in HA (the owner's choice).
Rule 4 waits, and so does any hello on a kid's own login (a user whose person is a kid on Hearth's page), so a kid
can't take a panel over.

### Approval in HA

The discovered card (Settings › Devices & services › Discovered) and the same card on Hearth's page (Today), which the
administrators' notice points to (only an administrator can approve) (it never approves by itself: no buttons). The line under the title tells two waiting panels
apart: the model, the id's last four characters, and the login it signed in as (the user's and the token's names).

- **Room** (required), and **This panel is**: a new panel, or taking the place of a panel that isn't connected
  (`<name> (offline since hh:mm)`, newest offline first). A hello whose id is a panel's already is approved as that
  panel again (a new secret, moved to the room picked).
- Hearth's page: `{"type": "hearth/panel_hello", "device_id", "answer": "approve" | "deny", "area_id", "replaces"?}`
  (administrators; `area_id` required to approve; `replaces` a panel's `device_id`). `hearth/config` lists the waiting
  ones as `panel_hellos` (with `panels_offline` and `areas`).
- The approved event goes to the waiting hello's open subscriptions on the login the card names.

## Pairing over HTTP (before 1.4, retired)

From 1.4 a panel says hello instead. `POST /api/<d>/pair` with kind `panel` is refused with `410 {"error":
"use_hello"}`; TVs and phones keep the route. What follows is kept for the record.

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
  the photo album) are taken only while the house has none. `doors.pin_to_unlock` is never taken from a seed: the PIN
  stays on until an adult turns it off. A valid `proxy.key` is kept, so an ESPHome proxy already
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
again gives a new secret; the panel's settings, room and proxy key (`proxy.key`) stay, and so do its own Start, its last 10 Start
changes and the room layout and page it last reported (removing the device drops them).

## The WebSocket commands

On any Home Assistant login, each with the device secret, which alone says which panel it is: a wrong secret, or
another panel's (the panel was removed, or paired again elsewhere), on every command below: error `unknown_panel`
(since 1.2; before, `unauthorized`). **Only `unknown_panel` means "this secret is dead"**: the panel then drops its
secret and pairs again. Home Assistant's own `auth_invalid` / `unauthorized` (a refused login token, or a command the
login may not use) is never that: the token is the owner's to fix, and the panel keeps its secret and its cached
document, shows that it can't sign in, and tries again later. No panel command answers `unauthorized` for a secret.

While `<d>` is reloading (Hearth reloads whenever a setting is saved on its page) or hasn't loaded yet, every command
answers error `unavailable`, `translation_placeholders.retry_in` the seconds to wait (5): try again then. Right after
Home Assistant starts, before `<d>` has loaded, the commands aren't registered yet and Home Assistant answers
`unknown_command`: the same, try again. After a restart the panel subscribes again.

### `<d>/panel/subscribe {device_id, secret}`

Result `null`, then an event with the whole document at once, and again on every change (a setting set by a service
or an entity, a house-wide value, the device's area or name), batched 1 s: one service call that sets three things
is one push. A push is only sent when the document's `version` differs from the last one this subscription got.
While a subscription is open the panel's **Connected** entity is on; it goes off 2 minutes after the last one closes.
No heartbeat. The Home Assistant user it signed in as is kept with the panel, and the first subscribe with an approved hello's secret is that hello's acknowledgment.

When the panel is removed or paired again, each open subscription gets one last event `{"unpaired": true}` and no
more.

### `<d>/panel/report {device_id, secret, view?, version?, on_tablet?, sw_version?, model?, room_layout?, page?, unpaired?}`

Sent on change only (at most 30 a minute: error `too_often`). Sets the **View** entity (`photos`, `tiles`, `night`,
`off`, `dark_clock` (or `dark clock`), `pairing`; anything else: unknown), **On the tablet** (words, or a list of them
joined with `; `; none: `none`), and the device's `sw_version` / `model`. `version` is the document version the panel
holds (`get_panel` says whether it's up to date). `unpaired: true` removes the panel: its device and entities.

`room_layout` (since 1.1; the panel sends it only to a server whose document says `glint.panel-config/1.1` or later,
and only when it changes): the room's layout as the panel lays it out, in `start`'s tile shape, built-in kinds only.
The server keeps the last one per panel only to start a first `change_panel_start` from; it is not the panel's Start.
A layout that isn't right: error `invalid` (as `set_start`), nothing of the report taken. `null` forgets it.

`page` (since 1.1, sent as `room_layout` is): `{"cols", "rows"}`, whole numbers 1 to 12, the panel's page in cells. The
server keeps the last one per panel; `change_panel_start` fits tiles on it (first fit, and every op's bounds). Before
one is reported: 8 cols x 5 rows (panels are landscape only). Not right: the command's schema error. `null` forgets it.

### `<d>/panel/set_start {device_id, secret, start, base_version}`

The panel's whole `start` after an edit made on the wall (`{"tiles": [...]}`; its `changed` and `version` are ignored),
or `null` (or `{"tiles": null}`) for "back to the room's layout". `base_version` is the `start.version` the edit started from (`null`, or
left out, when it started from the room's layout).

- At most 30 a minute per panel (counted apart from reports): error `too_often`.
- `base_version` differs from the stored `start.version` (both `null` counts as equal; a `start` of `null` and one
  with `tiles: null` both have version `null`): error `stale`, `translation_placeholders.version` the stored one (`""`
  when it is `null`). Nothing changes; the panel
  takes the document it is pushed (Home Assistant wins) and shows "changed elsewhere · undo".
- Not a right layout (see [The panel's own Start](#the-panels-own-start); here a tile may reach cell 8 either way, or
  further on a larger reported page, since the panel leaves out what is off its page): error `invalid`,
  `translation_placeholders.why` the first problem in words (`no tile kind toaster`, `lock.front_door is a normal
  state, never dealt`, `tiles heat_lamp and clock overlap`).
- Else it is stored, stamped `changed: {"by": "panel", "at": now, "undo": <new id>}`; the `start` before it is kept as
  one of the last 10 changes; the document is pushed to every subscription of that panel. Result `{"version": "<new
  start.version or null>", "undo": "<id>"}`.
- First time (migration): a panel that kept a Start on the tablet before the server had one sends it once with
  `base_version: null`; with the stored `start` still `null` it is taken as above.
- A wrong secret, or another panel's: `unknown_panel`.

### `<d>/panel/verify_pin {device_id, secret, pin}`

A Parent PIN typed on the panel, checked by Hearth as phones' `verify_pin` is, in its own lockout (the panel's, keyed
`panel:<device_id>`): `FREE_TRIES` free, then 30 s doubling to an hour; a right PIN clears it. The panel never gets a
PIN or a hash.

- Right: result `{"person": "person.alex"}`.
- Wrong: error `wrong_pin` (`translation_placeholders.retry_in`: seconds of the lockout this guess started, `0` for
  none).
- Locked out: error `locked_out`, `translation_placeholders.retry_in` seconds.
- No adult has a Parent PIN in Hearth: error `no_pin`. Only this answer means "no PIN is set".
- Hearth isn't ready (reloading, or not loaded yet): error `unavailable`, `translation_placeholders.retry_in` seconds
  (or `unknown_command` before it has loaded). This never means "no PIN".

**The panel keeps its door locked (the adult screen shut) on every error**, and on no answer at all: only a right PIN
opens it. `wrong_pin`, `locked_out`, `unavailable`, `unknown_command`, `unknown_panel`, `unauthorized`, a lost connection or anything
else is "not now", never "open" and never "check locally". (What the panel does on `no_pin` is its own choice; it must
not be what it does on any other error.)

(The handoff's `parent_pins` and `parent_pins_version` are not in the document: no PIN hash leaves Home Assistant.)

## The document

Sent whole, never as a diff. Every key is present; `null` or `[]` means "derive it" (the panel works out live things
such as presence and the room's thermostat itself).

```json
{
  "schema": "glint.panel-config/1.4",
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
  "proxy": {"on": false, "name": "kitchen-panel", "key": "...base64...", "mac": "02:00:5e:10:00:01"},
  "voice": {"heard": null, "reply": null, "reply_attribute": null, "show": null},
  "news": {"seen": null},
  "start": null
}
```

- `version`: the first 8 hex digits of a SHA-256 of the rest of the document: it changes exactly when the content
  does.
- `schema` is `glint.panel-config/1.4` (1.1 added `start`, and `room_layout` in reports; 1.2 a bed side's `name`,
  `active`, `reliable`, `presets` and `controls`; 1.3: every panel has a `proxy.key`, and an administrator can change
  it; 1.4: `proxy.mac`, and setting a panel up over its socket, `hello`). The major is 1. Adding
  fields is a minor change, read by old panels. Renaming or
  removing one is a new major; old panels then keep their cached document.
- `panel.name`: the device's name (the owner's, when they renamed it). `panel.panel_areas`: every paired panel's area,
  sorted (the house panel needs it). `panel.house_panel`: at most one panel's is true.
- `look.motion`: `still` · `calm` · `easy` (default) · `lively`. `photos.every_s`: 30 · 60 (default) · 120 · 300.
- `photos.camera`: the panel's own album, else the house's, else `null`.
- `routines.windows` defaults: good morning 06:00–09:00 every day; dinner 17:30–19:00 weekdays; good night 21:00–23:30
  every day with `after_bedtimes: true`. `routines.commute` default: weekdays 07:00–08:30.
- `bed`: `null`, or `{"left": side | null, "right": side | null}`. A side always has every key (a side set before 1.2
  gets the new ones empty; its values are unchanged):

  ```json
  {"connected": "binary_sensor.bed_controller_bed_1_connected", "scripts": [], "positions": [],
   "name": "alex's side", "active": null, "reliable": null,
   "presets": [{"name": "flat", "entity": "button.bed_controller_bed_1_flat"},
               {"name": "zero g", "entity": "script.bed_preset", "data": {"side": "left", "preset": "zero_g"}}],
   "controls": {"stop": {"entity": "script.bed_stop", "data": {"side": "left"}}}}
  ```

  - `connected`, `active`: an entity or `null`; `scripts`, `positions`: entities (at most 50 each).
  - `name` (1.2): words, at most 40 letters, or `null`. `reliable` (1.2): `true`, `false` or `null`.
  - `presets` (1.2): at most 12, each `{"name", "entity", "data"?}`; names at most 40 letters, different (ignoring
    case).
  - `controls` (1.2): any of `stop`, `light`, `massage`, `massage_head_up`, `massage_head_down`,
    `massage_foot_up`, `massage_foot_down`, `massage_mode`, each `{"entity", "data"?}`. `set_panel` also takes a bare
    entity id for a control (or a preset's `{name, entity}`), and stores and serves the object. Only the controls set
    are present; `{}` when none.
  - `data` (a preset's or control's, 1.2): a JSON object, at most 16 fields and 1 KB as JSON, left out when there is
    none. The panel runs an action by its entity's domain (a button is pressed, a script runs with `data` as its
    variables, a scene turns on, a switch toggles).
  - Every entity must be one Home Assistant has (`set_panel` refuses it, naming it; a seed's is dropped). A side is
    `null` when nothing in it is set. Anything not set is the panel's to derive (a bed controller found by
    `connected`).
- `proxy.name`: the name the panel's seed gave (kept, so ESPHome sees the same device) or set with `set_panel`
  `proxy_name`; else the device's name as an ESPHome name (`kitchen-panel`, at most 31 characters).
- `proxy.key` (every panel's since 1.3): the Noise pre-shared key of the panel's ESPHome Bluetooth proxy, 32 random
  bytes in standard base64, as ESPHome's `api: encryption: key`. One per panel, kept in its record in `<d>.panels`:
  made at its first pairing (or kept from the seed), and for a panel paired before 1.3 without one, when the store
  loads. It stays across pairing again and through entity, area and device renames; removing the panel's device
  drops it. The panel app runs the proxy with it and restarts the proxy when it changes. Home Assistant's ESPHome
  entry for the proxy uses the same key to connect: an administrator reads it from `get_panel` and enters it there.
  Changing it (`set_panel` `proxy_key`) pushes the new key to the panel, so the ESPHome entry must be given the new
  key again (ESPHome asks to re-authenticate). A panel before 1.3 ignores it.
- `proxy.mac` (1.4): the MAC the panel's ESPHome proxy uses, lowercase with colons. One per panel, for life, so ESPHome
  sees the same device and needs no re-add: a panel stored before 1.4 takes the MAC of the ESPHome entry whose name,
  title or host is its `proxy.name` (the entry's unique id), when Home Assistant loads the store; a new panel's (and a
  panel with no such entry) is derived from its `device_id`: the first 6 bytes of SHA-256 of it, the first byte's low
  two bits set to `10` (locally administered, unicast). A tablet that takes a panel's place gets that panel's MAC and
  key. It never changes on its own; an administrator can set it (`set_panel` `proxy_mac`). The panel uses it when
  present; without one (an older Home Assistant) it keeps its own.
- `news.seen`: the `input_text` where the panel keeps which news it has shown, or `null` (the panel's own
  fallback). Set with `set_panel` `news_seen`.
- `voice` only names entities; the voice turn log, timers and the shared request entity belong to the voice
  integration (or plain helpers), never to the panel part.
- The one secret in it is `proxy.key` (`proxy.mac` isn't a secret, but services show it to administrators only). The document goes only to the panel that owns it, over its own
  secret-authenticated subscription; the key is never in an entity's state or attributes, an event, a log, the
  diagnostics or an error, and in a service's answer only to a Home Assistant administrator (`get_panel`, and
  `set_panel` when they change it). An adult who isn't an administrator, an automation and the panels' shared login
  never get it. (Hearth never logs it; Home Assistant's own `websocket_api` debug logging, when someone turns it on,
  prints every message it sends, this document too.)

## The panel's own Start

`start` is `null` for a panel whose Start was never changed: the panel lays out Start by its room rule, exactly as
before 1.1. After a change back to the room's layout (`reset`, `set_start` with `null`, or an undo to before the first
change) it is `{"tiles": null, "changed": {...}, "version": null}`: still the room's layout, but stamped, so the panel
can say who changed it. A change from either starts from the reported `room_layout`. Once something is placed (from
the wall with `set_start`, or with `change_panel_start`):

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
  `row + h - 1 <= 8` (or a larger reported page's larger side). Tiles may not overlap. The panel leaves out a tile that
  is off its page. The services' ops fit tiles on the reported page (8 x 5 until one is reported).
- `kind`: `clock`, `calendar`, `weather`, `climate_stack`, `family`, `arrivals`, `media_stack`, `room_stack`,
  `routines_stack`, `lists_stack` (the house's to-do lists; each at most once), `entity` (needs `entity`), `stack` (hand-made: needs `name`, at most 40
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
  `deals[].entity`, and the kept changes) and its reported `room_layout`, in every panel setting that names entities
  (`people`, `routines`, `photos`, `presence`, `voice_heard`, `voice_reply`, `voice_show`, `news_seen`, `bed_left`,
  `bed_right`: `connected`, `scripts`, `positions`, `active`, and each preset's and control's `entity`) and in the house-wide values (`family_calendars`, `person_calendars` (its people too), `night`,
  `doorbell_camera`, `photos`), and pushed; the tile keeps its id. An entity removed from Home Assistant is
  kept: the panel marks its tile until someone removes it.
- The last 10 changes are kept per panel in `<d>.panels`, each the `start` from before it with its undo id (oldest
  dropped). Pairing again keeps them; removing the panel's device drops them.

## Entities on each panel device

They show the panel part's store and write to it; nothing is restored from the state machine, so a restart shows what
the store has. Changing a setting entity is checked as the services are: an administrator, an adult, or a call with no
user (an automation); anyone else (the panels' shared login, a kid's own login) gets Home Assistant's `Unauthorized`.

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
| `house_panel` ("Shows rooms without a panel": device issues from rooms with no panel of their own show here) | switch | config | at most one on: turning one on turns the others off; turning it off leaves none until one is turned on. Until one is chosen: the first paired shared-room panel (no `people`; by its first pairing, so pairing again doesn't move it) |
| `bluetooth_proxy` | switch | config | off |
| `connected` | binary_sensor | diagnostic | the subscription is open (2 min grace) |
| `view` | sensor (enum) | diagnostic | photos · tiles · night · off · dark_clock · pairing |
| `on_the_tablet` | sensor | diagnostic | words, e.g. `allow turning the screen off`; `none` |

Unique ids `panel_<device_id>_<key>`. A new entity's id is its device's name and its key,
`<domain>.<area>_panel_<key>` (`switch.kitchen_panel_photo_caption`): the device is made, named for its room and in it,
before any entity is registered, and the id never has the area twice (Home Assistant's own naming puts the area before
the device's name). An entity registered already keeps its id; names come from translation keys.

## Services (administrators and adults, and automations, as Hearth's other services check)

### `<d>.set_panel`

`device_id`: the one panel's Home Assistant device. Any of `people` (persons), `extra_areas` (areas), `routines`
(entities), `bed_left`, `bed_right` (a bed side), `photos`, `presence`, `voice_heard`, `voice_reply`, `voice_show`,
`news_seen` (entities), `voice_reply_attribute` (words), `proxy_name` (an ESPHome name), `motion`, `photos_every`, and every switch key above (`house_panel`
included), and `proxy_key` and `proxy_mac` (administrators only, below). Left out: unchanged. `null` or `[]`: back to derived (for a switch: its default; `house_panel: null` goes
back to the derived house panel). An entity or area Home Assistant doesn't have is refused, naming it; a device that
isn't a panel is refused. The answer (`return_response`) is the effective document without its secrets (no
`proxy.key`, no `version`).

`proxy_key` (1.3): only a Home Assistant administrator may give it (anyone else, adults and automations included, gets
`Unauthorized` and nothing changes). `"new"` makes a fresh key; a valid key (32 bytes, base64) sets that one; anything
else is refused without repeating the value, and nothing changes. The new key is pushed to the panel, and the answer
has it as a top-level `proxy_key`. Then enter it again in the ESPHome entry. Prefer `"new"`: a key given by value is
in Home Assistant's own `call_service` event, as every service call's data is.

`proxy_mac` (1.4): administrators only, as `proxy_key`. A unicast MAC (`02:00:5e:10:00:01`, or with dashes or none,
any case), stored lowercase with colons; anything else is refused and nothing changes. Pushed to the panel; the
answer has it as a top-level `proxy_mac` (the document part never has `proxy.mac`). Change it only to match an
ESPHome entry: ESPHome sees another device otherwise.

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
| `add` | `kind` (default `entity`), `entity` (for `entity`), `size` `"2x1"` (default), `at` `[col, row]`? | places a tile on the page; no `at`: the first fit from the top-left, row by row. Refused: a built-in kind already there, the same entity already placed on its own, an entity Home Assistant doesn't have, no room; `stack` (use `make_stack`) |
| `move` | `tile`, `at` | moves it there if it fits on the page |
| `resize` | `tile`, `size` `"WxH"` | resizes it in place if it fits on the page |
| `remove` | `tile` | takes it off Start (a hand-made stack's devices go back to the room stack) |
| `deals` | `tile` (`room_stack` or a `stack`), `entity`, `when` (`"on"`, `{from, until, days}`, or `null` to stop) | sets one device's "deals when" (in a `stack`, one of its members) |
| `make_stack` | `name`, `entities` (1 to 12), `size`?, `at`? | a hand-made stack; those devices' own `entity` tiles leave Start, and they leave other hand-made stacks (an emptied one goes) |
| `reset` | | `start: null` (the room's layout) |

The first change of a panel on the room's layout (`start` `null`, or `tiles` `null`) starts from the `room_layout` it last reported; none reported yet:
refused, `the panel hasn't said its layout yet`. The result is checked as `set_start`'s, stamped, the `start` before it
kept as a change, and pushed. Answer: `{"changed": "test lamp placed at column 5, row 1; ...", "start": {...},
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
each house-wide value as `{"value", "source"}`. To a Home Assistant administrator only, each panel also has
`proxy_key` (its `proxy.key`, for the ESPHome entry), `mac` (its `proxy.mac`) and `tablet_ids` (the ids of the
tablets that took its place, hello rule 2); an adult who isn't one, or an automation, gets none of these keys at all.
Never another secret.

## Not yet built

- Hearth's page › panels (approve with a room, a card per panel with its lists, switches, overrides,
  connected/view/on the tablet and the proxy key step "add it in ESPHome", and one house-wide card). Until then a
  panel is approved from the pending list on Hearth's page (no room), the phone notice, or Settings > Devices &
  services (with a room), and set up with the entities and services.
