# Glint Panel configuration, `glint.panel-config/1`

Owner: the integration that serves it, `<d>` below (today Hearth, `hearth`). A Glint Panel is a wall tablet, one per
room. Its settings live in Home Assistant: an administrator approves its pairing code and picks the room, and the
panel gets one versioned document over a WebSocket subscription it holds with its own Home Assistant user.

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
- a Home Assistant user named as the device: not an administrator (group `system-users`), local only, in no person;
  and a long-lived access token for it (client name `Glint Panel`, 10 years). Only the user id is kept.

The poll's approved answer (`GET /api/<d>/pair/<pairing_id>`, header `X-Panel-Nonce`, or `X-Hearth-Nonce` as for TVs and
phones; any future server takes `X-Panel-Nonce`) is handed over once, as for
every device, and adds the token:

    {"status": "approved", "contract": 3, "device_id": "...", "secret": "...", "ha_token": "...",
     "urls": {"internal": "...", "external": "..."}, "person": null, "role": null, "push": null, "client": null}

A later poll is 404: the token is never given again. The panel signs in to Home Assistant with `ha_token` and keeps
`secret` for the commands below.

Removing the panel's device in Home Assistant deletes its user (and so its token). Pairing again deletes the old user
and makes a new one; the panel's settings, room and proxy key stay.

## The WebSocket commands

As the panel's own user (an administrator's connection may also use them), each with the device secret. A wrong
secret, or another user's connection: error `unauthorized`.

### `<d>/panel/subscribe {device_id, secret}`

Result `null`, then an event with the whole document at once, and again on every change (a setting set by a service
or an entity, a house-wide value, the device's area or name), batched 1 s: one service call that sets three things
is one push. A push is only sent when the document's `version` differs from the last one this subscription got.
While a subscription is open the panel's **Connected** entity is on; it goes off 2 minutes after the last one closes.
No heartbeat.

When the panel is removed or paired again, each open subscription gets one last event `{"unpaired": true}` and no
more (removal also deletes the user, which closes the connection).

### `<d>/panel/report {device_id, secret, view?, version?, on_tablet?, sw_version?, model?, unpaired?}`

Sent on change only (at most 30 a minute: error `too_often`). Sets the **View** entity (`photos`, `tiles`, `night`,
`off`, `dark_clock` (or `dark clock`), `pairing`; anything else: unknown), **On the tablet** (words, or a list of them
joined with `; `; none: `none`), and the device's `sw_version` / `model`. `version` is the document version the panel
holds (`get_panel` says whether it's up to date). `unpaired: true` removes the panel: its device, entities and user.

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
  "news": {"seen": null}
}
```

- `version`: the first 8 hex digits of a SHA-256 of the rest of the document: it changes exactly when the content
  does.
- `schema` major is 1. Adding fields is a minor change (`glint.panel-config/1.1`), read by old panels. Renaming or
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
| `house_panel` | switch | config | at most one on: turning one on turns the others off; turning it off leaves none until one is turned on. Until one is chosen: the first paired shared-room panel (no `people`) |
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

### `<d>.get_panel`

`device_id` optional (none: every panel). Answers `{"panels": [...], "defaults": {...}}`: per panel its `device_id`,
`ha_device_id`, `name`, `area_id`, `settings` (each key as `{"value", "source": "set" | "derived"}`), `connected`,
`view`, `on_the_tablet`, `up_to_date` (the version it reported is the current one) and `document` (without secrets);
each house-wide value as `{"value", "source"}`. Never a secret.

## Not yet built

- Hearth's page › panels (approve with a room, a card per panel with its lists, switches, overrides,
  connected/view/on the tablet and the proxy key step "add it in ESPHome", and one house-wide card). Until then a
  panel is approved from the pending list on Hearth's page (no room), the phone notice, or Settings > Devices &
  services (with a room), and set up with the entities and services.
