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

## Without Home Assistant for a while (additive, within contract 3)

A device that loses Home Assistant keeps its last word (Home Assistant's rules win while paired). Each person's state
document carries what that word needs to go on, and an older Hearth leaves it out:

- `next_lock.until`: when the next lock would end if the device starts it itself: a lock entity's own end
  (Family Link's `bedtime_end` or `schooltime_end`, Family Safety's `downtime_end`), the weekly schedule's next change
  (wake for Sleep), or for a lifted bedtime the bedtime's own end. Missing when nothing says; a device then takes the
  weekly schedule's wake time (`schedule.bedtime.wake`).
- `tomorrow`: `{date, groups: [{id, minutes}], daily_minutes, next_lock}`. Each group's base minutes for tomorrow's kind
  of day (its day type and the weekly schedule, no bonus time), daily time's as `daily_minutes` (null without a
  limit). A group whose apps tomorrow aren't today's group's in `groups` (left out today, or its `apps`/`except`
  changed by an allow) carries `name` and `apps` (daily time: `except`). `next_lock` is the weekly schedule's first Sleep
  or School after waking `{at, by: "schedule", kind, until}`, missing when there's none or School time is off. A
  device that starts a new day before Home Assistant answers counts each group down from these minutes, and holds the
  new day's `next_lock` once the night's lock is over.
- `lifts`: `[{group, name, until, minutes, minutes_after, apps or except, in_daily}]`, one per group with a limit that
  something lifts for a while and is left out of `groups` for it: an allow of the group or Unlimited with an end
  before midnight (`until`), a category's own bonus (`minutes`: its bonus left, spent first). `minutes_after` is what's
  left of the group's limit once the lift is over; `in_daily` says its apps count in daily time again then (daily
  time's `except` loses them). A lift that lasts until midnight isn't listed. A device that hasn't heard from Home
  Assistant since `until` (3 minutes on), or whose group's apps have been in front for `minutes` since the last word,
  holds the group again with `minutes_after`, counted down by its own time in front.

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
- Only Home Assistant's check of an adult's Parent PIN mints one. A PIN a device checks itself (a TV's copy of the
  hashes, a phone's own PIN) never does.
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

### `category_values` (additive, within contract 3)

A phone's state document (and `hearth/me`) carries Hearth's own app-category values, the table Hearth decides by
(`categories.BUILTIN_VALUES`). The TV's part of the document doesn't have it.

```json
{"category_values": {
  "format": "hearth.values/1",
  "version": "3f1c2a9b0d4e5f67",
  "categories": {
    "game": {"label": "Games", "pool": "games"},
    "messaging": {"label": "Messaging", "pool": "messaging", "loose": true},
    "interface": {"label": "System screens", "counted": false, "overrides_only": true},
    "youtube": {"label": "YouTube", "parent": "video", "pool": "other", "pool_names": ["youtube"]}
  }}}
```

- `format`: `hearth.values/1`. It changes only when the shape changes; a client that doesn't know the format ignores
  the key. `version`: 16 hex characters, changes with any value, so a client can keep its copy until it does.
- `categories`, by value (the ten categories, `interface` and the details): `label`; `pool`, the pool a value goes to
  by default (the household's own map decides, an adult's move wins); `pool_names`, pool names that also take it;
  `parent`, a detail's category; `loose`, set only by a confirmed answer; `counted: false` and `overrides_only` for
  System screens. A field left out is false or none. A client ignores fields it doesn't know.
- The fields that change a limit (`pool`, `loose`, `counted`) are Hearth's alone: a client shows them, it doesn't
  decide by them. A client paired with a Hearth reads labels from here instead of carrying its own table; a client
  without a hub (or with a Hearth older than this key) keeps its own table.
- Additive: a client that doesn't read it is unaffected. It's part of the document's `version`.

### A kid's to-do list (additive, within contract 3)

A phone paired to a kid (its person's role is kid) gets `todo_lists` in its state document: one entry per list (Hearth
has one per kid, to-dos and chores together; a chore is an item with a reward), refreshed as the document is.

```json
"todo_lists": [{"entity_id": "todo.hearth_alex", "name": "Alex's to-do", "items": [
  {"uid": "<occurrence id>", "summary": "Feed the cat", "status": "needs_action", "due": "2026-11-24", "reward": "+15 min Games"}
]}]
```

- `items`: today's: one-off tasks, today's occurrence of each repeating task, and what was done today (`completed`,
  until the day ends). `status` is `needs_action` or `completed`; `due` a date, a local date-time, or `null`;
  `reward` its words ("+15 min Games", "+$1.00") or `null`.
- A TV, a phone of an adult's or nobody's gets no `todo_lists`. The `todo` counts stay as they were. A kid's own
  `hearth/me` document carries it too.

`POST /api/hearth/device/{device_id}/todo_item` (`X-Hearth-Secret`; on the home network, as every device call):
`{"entity_id", "uid", "status": "completed" | "needs_action"}`. It checks the item off (or back) as the kid
themselves: a reward is granted on a check-off with no approval step and taken back by the check back, and the
adults are told with an Undo.

- 200 `{"ok": true, "entity_id", "uid", "status", "granted"}` (`granted`: a reward stands for this check-off).
- Refused: `{"error", "code" (the same), "message"}`, the message in words to show as they are. 403 `not_yours` (not
  this phone's kid's list, or a phone of an adult's or nobody's); 404 `unknown_item` (not on the list now: a new
  day, deleted); 409 `undone` (an adult undid its reward: only an adult unticks it); 400 `bad_request`; 401
  `not_paired`; 429 `too_often`.
- A check-off is never queued offline by Hearth: the answer is the result.

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

Person kind (`kid`/`adult`), device kind (`tv`/`mobile`; a wall tablet pairs as `panel` and is served apart, see
[panel-config.md](panel-config.md)), the client id, usage, `app_categories`, `caps`,
`kids_profile`, and `checks[]` only as display. Nothing inside client settings, and no field it doesn't know.

## Events

| Event | Data |
|---|---|
| `hearth_device_check_failed` | `device_id`, `name`, `person`, `check`, `label` |
| `hearth_client_settings_changed` | `client`, `scope`, `name` (never the contents) |
| `hearth_device_paired` | as before, plus `client` (the id) for a redeemed ticket |
