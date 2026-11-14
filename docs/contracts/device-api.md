# Device API, contract 3

Owner: Hearth (the Home Assistant integration). This is what any app paired with Hearth (a "client") may rely on:
Hearth TV, a phone launcher, or any other app. The full endpoint reference is
[home-assistant-integration.md, The device's side of the API](../home-assistant-integration.md#the-devices-side-of-the-api);
this page says what contract 3 adds, and what Hearth reads and doesn't.

Contract 3 is additive: a contract-2 client keeps working. Every answer carries `contract` (now `3`). A reader
ignores fields it doesn't know.

## Already there, unchanged

- Pairing (`POST /api/hearth/pair`, the poll, the device secret, `urls`, `person`, `role`), tickets and redeeming.
- The status post and the state document: groups, `minutes_left`, `except`, `locked`, `lock`, `next_lock`, `pause`,
  `request`, `kind`/`kind_set`, to-do counts, `allow_ends`, `playing`.
- Asks (`/ask`, `/wait`, `hearth.answer_request`), `verify_pin`, the household summary and `hearth/me`,
  `hearth.add_bonus`, `hearth.pause`, push "changed" pings (`caps: ["push"]`).

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
  that the household or the shared app catalog put in a pool (an adult's move or list, Hearth's own lists, App facts'
  answer) is held like any other app. The client's own category for itself doesn't count as putting it in a pool.
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
- Only Home Assistant's check of an adult's Parent PIN mints one. A PIN a device checks itself (a TV's copy of the
  hashes, a phone's own PIN) never does.
- Give it as `"grant"` in the write's body, or in the `X-Hearth-Grant` header.

### Client settings

Small documents a client keeps in Hearth, per scope: [client-settings.md](client-settings.md). The state document of a
device paired with a client carries `client_settings`, `{"<scope>/<name>": "<etag>"}`, for every document it may read
(`{}` when there are none yet). A contract-3 state document **without** `client_settings` means the device paired
without a client (before contract 3, or with no `client`): its settings calls get `403 no_client` until it pairs again.

### `share_app_data`

In each person's document, in place of `tile_exchange_share` (which is no longer sent): whether a parent lets this
person's devices share app data with public app datasets (Hearth's page > Sharing app data). Hearth sends it for every
person; it's an adult's choice only for kids (adults' own apps follow the household's sharing switch), so a client
may apply it on kids' devices only. `false` turns a client's
own sharing off for that person. It's in the device path and in `hearth/me` alike.

### `catalog_categories` is no longer read

Hearth fetches the shared app catalog itself ([app-facts.md](app-facts.md)). A device may still send
`app_categories` (Android's own category per package).

## What Hearth interprets

Person kind (`kid`/`adult`), device kind (`tv`/`mobile`), the client id, usage, `app_categories`, `caps`,
`kids_profile`, and `checks[]` only as display. Nothing inside client settings, and no field it doesn't know.

## Events

| Event | Data |
|---|---|
| `hearth_device_check_failed` | `device_id`, `name`, `person`, `check`, `label` |
| `hearth_client_settings_changed` | `client`, `scope`, `name` (never the contents) |
| `hearth_device_paired` | as before, plus `client` (the id) for a redeemed ticket |
