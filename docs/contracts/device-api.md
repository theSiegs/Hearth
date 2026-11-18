# Device API, contract 4

Owner: Hearth (the Home Assistant integration). This is what any app paired with Hearth (a "client") may rely on:
Hearth TV, a phone launcher, or any other app. The full endpoint reference is
[home-assistant-integration.md, The device's side of the API](../home-assistant-integration.md#the-devices-side-of-the-api);
this page says what contracts 3 and 4 add, and what Hearth reads and doesn't.

Contract 3 is additive: a contract-2 client keeps working. Every answer carries `contract` (now `4`). A reader
ignores fields it doesn't know.

## New in contract 4: parent PINs are no longer sent to TVs

Contract 4 takes a field away, so the number went up. A TV's state document no longer carries `parent_pins` (the
adults' Parent PIN hashes) for a TV that speaks contract 4. A Parent PIN has 10,000 possible values, so anyone who
got that list (on the home network, from plain HTTP) could try them all in under a minute, with no lockout.

- `parent_pins_version` stays: it changes whenever an adult's Parent PIN is set, changed or removed, and is gone when
  Home Assistant has none.
- A contract-4 TV asks `verify_pin` for every PIN, and Home Assistant's answer and lockout are final. It keeps,
  sealed with an Android Keystore key, only the PINs typed on it that `verify_pin` confirmed, tagged with the
  version they were confirmed under. A `{"ok": false}` drops a kept PIN that matches; a new version drops them all;
  a 429 (locked out) counts as a no that keeps what was learned.
- With Home Assistant unreachable, only a PIN kept on that TV works (or one another TV of the household learned
  from Home Assistant and vouches for, see [household-sync.md, Parent PIN](../household-sync.md#parent-pin)).
- **Each adult's version (additive, within contract 4).** The state document also carries `parent_pins_versions`:
  `{"<adult key>": "<version>"}`, one entry per adult with a Parent PIN. An adult's version changes only when their
  own PIN is set again (it is worked out from their salted hash and says nothing of the PIN), and their entry goes
  when their PIN is removed. The key names nobody: the first 16 hex digits of SHA-256 of `hearth-adult:` followed by
  the person entity id (`parent_pin.adult_key`). `verify_pin`'s yes already names the `person`, so a TV works out
  the same key and tags what it learns with that adult's key and version. On a new `parent_pins_version` it then
  drops only the PINs of adults whose version changed or went, so one adult changing their PIN while Home Assistant
  then stays down leaves the others' PINs working on every TV. A PIN learned without saying whose (another TV
  vouched for it, a notice's button, or a build before this field) and a document without the field still drop on
  any change, as before. `parent_pins_version` stays, for TVs that don't read the map.
- Which contract a TV speaks: the higher of the `client.contract` locked at pairing and the one in its latest status.
  So a post that names an older contract can't take a TV back to being sent the hashes.

**Staged migration.** This integration release still sends `parent_pins` to a TV that reports a contract below 4
(it has no other way to check a PIN offline). The next integration release stops sending them to anyone. Hashes
an older integration sent are never read by a contract-4 TV; ones it kept before the update still work until the
version changes. The hashes stay in Home Assistant's config entry (and so in its backups): this change doesn't
protect them there. Once every TV is updated, each adult sets a new Parent PIN, since an old hash may already have
been copied.

A phone was never sent hashes: nothing changes for a phone, and a contract-3 client keeps working.

## Already there, unchanged

- Pairing (`POST /api/hearth/pair`, the poll, the device secret, `urls`, `person`, `role`), tickets and redeeming.
- The status post and the state document: groups, `minutes_left`, `except`, `locked`, `lock`, `next_lock`, `pause`,
  `request`, `kind`/`kind_set`, to-do counts, `allow_ends`, `playing`.
- Asks (`/ask`, `/wait`, `hearth.answer_request`), `verify_pin`, the household summary and `hearth/me`,
  `hearth.add_bonus`, `hearth.pause`, push "changed" pings (`caps: ["push"]`).

## The time model (additive, within contract 3)

Daily time, category limits, bonus time and Unlimited add `time` to each person's state document, change what an ask
gives (bonus time, no category) and deprecate per-category bonuses for one release. The fields, the exact words kids see
and the payload changes are in [time-model.md](time-model.md).

## Pairing: who is asked, and confirming your own phone (additive, within contract 3)

The pair body (`POST /api/hearth/pair`) may say who a phone is for, both optional and shown to the administrators only
(never trusted further): `person_name` (at most 64 characters, "Alex") and `role` (`"adult"` or `"kid"`). The answer
adds who is asked to approve:

    {"pairing_id", "code", "expires_in", "approvers": [{"name": "Alex", "phone": true}]}

`approvers` are the Home Assistant administrators, by their person's name (else their user's), sorted by name; `phone`
says a companion app of theirs got the notification with Approve and Deny (every one of them also sees it in Home
Assistant's bell). An empty list means nobody can approve it from a notification. A client may write "Alex gets a
notice to approve".

What the administrators see: the companion-app notification titled `A Hearth device wants to pair`, with the text
`<person_name>'s <name> (<model>) wants to pair as an adult. Code 123 456: approve only if the device shows the same
code.` (`as a kid` for `role: "kid"`; no role, no "as ..."; no `person_name`, just `<name> (<model>)`; the model is
left out when it's the same as the name) and the buttons **Approve** and **Deny**. Approve pairs a phone as the
household's person whose name is `person_name` (exactly one, any case); when none matches, the text adds `Choose whose
phone it is on Hearth's page.` and only **Deny** is offered. The bell says `**<headline>**. Open Hearth's page, check it
shows the same code as the device, and confirm. ...` (no code: everyone who uses Home Assistant sees the bell).

The phone learns the answer as before, from its poll (`GET /api/hearth/pair/<id>`): `approved` (with the secret,
`person`, `role`) or `denied`.

**An adult who isn't an administrator** can confirm their own phone without one: signed in to Home Assistant as
themselves (their person is an adult on Hearth's page), the WebSocket command

    {"type": "hearth/pairing", "answer": "approve" | "deny", "code": "123456", "pairing_id": optional}

pairs the waiting phone that shows that code as their own person (a `person` given is ignored) and answers
`{"answer", "person", "device_id"}`. Errors: `wrong_code` (no phone waiting shows it; counts as a try),
`too_many_tries` (five wrong codes in ten minutes), `unauthorized` (a kid, a user whose person isn't an adult in Hearth,
or a phone paired for someone else), `expired`. An administrator's `hearth/pairing` is unchanged (`pairing_id`,
`answer`, `person`; no code).

## Hearth's day (additive, within contract 3)

Every status answer carries `day` (Hearth's own date, `YYYY-MM-DD`). Hearth judges the day by its own clock: a status
whose `day` isn't Hearth's (the device's clock moved) keeps the counts Hearth had, its answer says `"clock_off": true`,
and the device gets the check `hearth_clock` (`ok: false`, "Its date differs from Home Assistant's") until it posts for
Hearth's day again. Within Hearth's day a device's counts never go down (each app's seconds, the total, each TV
profile's): a client that restarts counting from zero loses nothing, and can't take time back either. A client should
count from Hearth's `day`, not its own clock's.

A client may send `utc_offset_minutes` at the top level of each status post: its offset from UTC now, in whole minutes
(-300 for EST, -240 for EDT; -840 to 840). When a `day` that isn't Hearth's is the device's own date for that offset
(a phone on a trip), it isn't a moved clock: the counts are kept as above, but there's no `clock_off` and no failed
check, and the adults hear once per time zone that the device "is set to another time zone (UTC-8)". A Hearth before
2026.11.28 ignores the field.

## New in contract 3

### `client`

Sent in the pair body (`POST /api/hearth/pair` and `/api/hearth/pair/redeem`) and in each status post:

```json
{"client": {"id": "com.example.launcher", "version": "1.4.2", "contract": 3,
            "companions": ["com.example.launcher.phone"]}}
```

- `id`: the client app's Android package, or a reverse-DNS id for a client that isn't an Android app. At most 128
  characters, two or more dot-separated parts of letters, digits and `_`.
- `companions`: at most 4 more packages of the same app family. Each must be `id` + `.` + a suffix
  (`com.example.launcher.phone`), so a client can't name anything outside its own family. A build whose id ends in
  `.debug` or `.nightly` (`com.example.launcher.debug`) may also name companions with that suffix at the end
  (`com.example.launcher.phone.debug`). Optional.
- `version`, `contract`: shown on Hearth's page.
- A pair body with a malformed `client` (a bad id, a companion outside the family, more than 4) is refused with 400
  `bad_request`. A status post with a malformed one keeps the last good one.
- Hearth TV sends its own package (`com.thesiegs.hearth`) and no companions.

**Locked at pairing.** The adult approving the pairing sees the id and companions, in Home Assistant's dialog and
on Hearth's page, and they're kept with the device when they approve. The approved pair answer says what was kept
(`"client": {"id", "companions"}`, or null). A debug or nightly build has another id, so it's another pairing.

**What Hearth does with it:**

- Routes the client's settings ([client-settings.md](client-settings.md)).
- **Never paused**: the locked id and companions of every device paired for a person are never paused for that
  person by Hearth's Family Link holds (budgets, School time, an adult's pause, the weekly schedule). Except: an id
  that the household or what it is put in a pool (an adult's move, list or answer, Hearth's own lists, Hearth's app
  categories) is held like any other app. The client's own category for itself doesn't count as putting it in a pool.
- Shows it on the device's row.

A later status post that names another `id` changes nothing: the new id isn't exempt and doesn't route settings.
Hearth adds its own check `hearth_client` ("App differs from pairing", `ok: false`) to the device until it pairs
again. A device paired before contract 3 has no locked client: it gets no exemption and no client settings until it
pairs again (its row shows the app it reports as "not confirmed").

### `checks[]`

In the status post, at most 10:

```json
{"checks": [{"id": "home_app", "ok": true, "label": "Home app"}]}
```

- `id` matches `[a-z0-9_]{1,32}`; ids starting `hearth_` are Hearth's own and are dropped. `label`: at most 40
  characters (the id when missing). `ok`: a Boolean, required.
- Display only. Hearth shows them as given on the device row (and in the household summary's `devices[].checks`) and
  knows none of the ids.
- When one turns false (it wasn't false in the device's last status), Hearth fires `hearth_device_check_failed`
  `{device_id, name, person, check, label}`, once per turn.
- A post without `checks` keeps the last ones.

### The `verify_pin` grant

A right PIN at `POST /api/hearth/device/<id>/verify_pin` now answers:

```json
{"ok": true, "person": "person.alex", "grant": "<32 characters>", "grant_expires": 120, "grant_writes": 8}
```

- For this device only, for 120 seconds, for at most 8 client-settings writes it couldn't make on its own. Each such
  write is kept with `updated_by: "pin"`.
- A device holds one grant at a time: a new one replaces it.
- Only Home Assistant's check of an adult's Parent PIN mints one. A PIN a device checks itself (one a TV learned,
  a phone's own PIN) never does.
- Give it as `"grant"` in the write's body, or in the `X-Hearth-Grant` header.

### Client settings

Small documents a client keeps in Hearth, per scope: [client-settings.md](client-settings.md). The state document of a
device paired with a client carries `client_settings`, `{"<scope>/<name>": "<etag>"}`, for every document it may read
(`{}` when there are none yet). A contract-3 state document **without** `client_settings` means the device paired
without a client (before contract 3, or with no `client`): its settings calls get `403 no_client` until it pairs again.

### `share_app_data`

**Retired.** In each person's document, in place of `tile_exchange_share` (which is no longer sent), and always
`false`: no client shares app data any more, so the setting is gone from Hearth's page and Configure, and the old
choices are removed from the options once. It stays in the document so a contract-3 client keeps reading sharing as
off; a client should not read it. It's in the device path and in `hearth/me` alike.

### `catalog_categories` is no longer read

Hearth knows app categories itself ([app-facts.md](app-facts.md), retired). A device may still send
`app_categories` (Android's own category per package).

### Usage Hearth doesn't count

Additive, no contract change. A client keeps sending every package's seconds (`app_seconds_today`) from local
midnight; Hearth, not the client, decides what counts:

- **System screens** count nowhere and are never paused: `android`, `com.android.systemui`,
  `com.android.permissioncontroller`, `com.google.android.permissioncontroller`, `com.android.packageinstaller`,
  `com.google.android.packageinstaller`, `com.google.android.gms.supervision`, the stock launchers, setup wizards and
  the common keyboards (`limits.STARTER_INTERFACE_APPS`), the apps App Facts confirms as `interface` (set only by
  its owner's override), plus any app an adult moves there. A phone's or tablet's total
  is then the sum of the apps kept. A client may leave these out itself as well; it changes nothing.
- **Before pairing**: on the day a device pairs, its first status after the approval is a baseline taken off the rest
  of that day. Pairing again takes a new one.

## What Hearth interprets

Person kind (`kid`/`adult`), device kind (`tv`/`mobile`), the client id, usage, `app_categories`, `caps`,
`kids_profile`, and `checks[]` only as display. Nothing inside client settings, and no field it doesn't know.

## Events

| Event | Data |
|---|---|
| `hearth_device_check_failed` | `device_id`, `name`, `person`, `check`, `label` |
| `hearth_client_settings_changed` | `client`, `scope`, `name` (never the contents) |
| `hearth_device_paired` | as before, plus `client` (the id) for a redeemed ticket |
