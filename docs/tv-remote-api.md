# Hearth TV remote API, version 1 (contract)

> **Contract, not built yet.** Agreed with Glint (the phone launcher) on 2026-11-07. Glint mirrors it in its own
> design notes. A change to anything here is a change to the contract: bump `v` and tell the Glint side.

## What it is for

A phone app on the home network controls a TV running Hearth TV and reads what it is playing, without Home Assistant.
It gives what the TV's own Android TV Remote service (Remote v2, ports 6466/6467) can't: the title, art, position,
a real seek, the TV's app list, its profile and the profile's rules.

Keys, text and power are **not** part of v1. They stay on Remote v2, which the phone pairs separately; the phone
merges the two links per capability (Hearth TV first where it has the capability). Hearth TV can only inject keys
through its accessibility service, which Android turns off after every sideloaded update, and its d-pad actions need
Android 13. A later version may add `key` if it is needed.

## Discovery

- mDNS/NSD service type `_hearth-tv._tcp`, announced whenever Hearth TV runs, from the **TV owner's user only** (like
  the Home Assistant bridge): one server and one announcement per TV, whichever profile is in front.
- The service port is the **session** port (7677). TXT records:

| Key | Value |
|---|---|
| `id` | The TV's remote id: hex SHA-256 of the remote API certificate's public key, first 16 characters |
| `n` | The TV's name |
| `v` | `1` |
| `pp` | The pairing port (7678) |
| `u` | `1` while the TV is in use (screen on and a media session playing or paused in the last 10 minutes, or an app other than the home screen in front). Absent otherwise, and always absent while no phone is paired. Nothing else about what's on. |

- Both ports answer home-network addresses only (Hearth's `LocalNet` rule: private ranges, link-local) and refuse
  everything else before TLS.

## The TV's key

A separate **RSA-2048** key in Android Keystore, only for this API, with a self-signed certificate (subject
`CN=hearth-tv`). It's RSA because the pairing secret is computed over the RSA modulus and exponent. It is not
Hearth's household sync key, which is EC P-256 and is never used here.

## Pairing (pairing port)

The polo exchange of Remote v2, unchanged except for the service name: TLS on the pairing port, where the phone
presents its own client certificate; pairing_request {service `hearth-tv` (also accepted: `atvremote`), client name} →
ack → options {input, hex 6} → the phone's options → configuration {input, hex 6} → ack, **and Hearth TV shows a
6-hex-digit code** in its own overlay → secret → ack.

- Secret = SHA-256(client modulus ‖ client exponent ‖ server modulus ‖ server exponent ‖ the code's last 4 hex digits
  as 2 bytes), the numbers as unsigned big-endian bytes; its first byte equals the code's first two digits. A wrong
  secret: status 402, the overlay shows a new code.
- The code shows only while the TV's screen is on; pairing a sleeping TV fails (the phone says so).
- On success Hearth TV stores the phone's **certificate fingerprint** (SHA-256), the client name, the time, and
  the phone's role: **restricted** for every new phone.
- The phone pins the TV's certificate from the pairing connection (Glint does).

## Who a phone is: adult or restricted

- A new phone is **restricted** (kid rules below). An adult marks it as an adult's phone in Hearth TV's
  **Settings > Family > Phones that control this TV**, which only an adult profile reaches. There is no PIN.
- The same list shows each paired phone (name, adult or restricted, last used) with **Remove**, which forgets the
  fingerprint at once and closes its open session.
- The phone may say `kid: true` in `hello` (Glint: from Family Link or its kid phone setting). The TV applies the
  **stricter** of its own role and the phone's word; `kid: false` never grants anything.

## Session (session port)

Mutual TLS: only certificates of paired phones are accepted (an unknown one: the handshake fails, or
`error {code: not_paired}` and close). Messages are **varint-length-prefixed UTF-8 JSON**, one object each, framed
like Remote v2's protobuf messages. The largest message is the `art` reply, up to 256 KB. Every message has a `t`
(its type).

### Phone → TV

| `t` | Fields | What it does |
|---|---|---|
| `hello` | `v` (1), `client` (name), `kid` (optional bool) | Starts the session; the TV answers `state` (and `error` if `v` is unsupported). |
| `media` | `do`: `play`, `pause`, `toggle`, `next`, `prev`, `stop` | Transport controls of the active media session. |
| `seek` | `toMs` or `byMs` (may be negative) | Exact seek on the active media session (`by` from the extrapolated position). |
| `launch` | `pkg` | Opens the app in the current profile (Hearth TV is the launcher). |
| `volume` | `set` (0–100) or `step` (+1/-1) or `mute` (bool) | The TV's music stream volume. |
| `apps` | | One-shot list of the current profile's apps. |
| `art` | `id` | The art of the current title, by the `artId` in `state`. |
| `bye` | | Ends the session; the TV closes. |

### TV → phone

| `t` | Fields |
|---|---|
| `state` | `on`, `profile` (the current profile's name), `kid` (whether the current profile is a kids profile), `app` (package in front), `appLabel`, `title`, `subtitle`, `artId` (null when none), `playing`, `positionMs`, `durationMs`, `positionAtMs` (the TV's wall clock when position was read), `speed`, `actions` {`seek`, `next`, `prev`, `playPause`}, `volume` (0–100), `muted`, `volumeSettable` |
| `apps` | `list`: [{`pkg`, `label`, `allowed`}] (`allowed` false: blocked or held for the current profile now) |
| `art` | `id`, `mime` (`image/jpeg`), `data` (base64, at most 64 KB) |
| `error` | `code`, `for` (the request's `t`), `message` (for logs) |

- `state` is sent **once after `hello` and then only on change** (app, title, playback state, volume, profile, screen).
  Position is not streamed: the phone extrapolates from `positionMs`, `positionAtMs` and `speed`.
- `actions` come from the media session's PlaybackState actions; the phone hides controls whose action is false
  (no back/ahead 30 without `seek`). No media session: `title` null, `actions` all false.
- `volumeSettable` is false when the TV can only step (for example volume over HDMI-CEC to a soundbar); `volume` is
  then the TV's own level or null.
- Fields the TV doesn't know are null, never invented.

### Errors

`not_paired`, `not_allowed` (a rule below), `unsupported` (an unknown `t` or field value), `no_session` (no media
session to control), `bad_request`.

## Rules on the TV

- **Restricted phones** (and any phone that said `kid: true`): `launch` of an app blocked or held for the current
  profile now (Hearth's budgets, pauses, School time apps, bedtime) answers `not_allowed`; `media`, `seek` and
  `volume` are allowed; the `apps` list marks what they can't open.
- **No profile switching** in v1, for anyone.
- Nothing wakes the TV: power stays with Remote v2 or the TV's own remote.
- Hearth TV logs one line per pairing, session start and end, and refused command, with the phone's name; never the
  content of a command beyond its type and app.

## Open on a TV

- Whether the owner user's media session listener sees a media session playing inside a Google TV kids profile
  user. If not, while a kids profile is in front `state` carries `app` and `profile` only (`title` null, all
  `actions` false).

## Version 2 (contract, approved 2026-11-10, amended the same day)

> Mirrors the approved text in Glint `docs/design/tv-remote.md` (Glint commits 54ca7573b, amended in 5d5aeaf19:
> kid asks forwarded to HA in mode `ha`, V2.10b one-tap HA for parent phones). Hearth TV owns this API; the two
> copies must stay identical. Nothing in v2 is built yet.

> Status: **contract approved by the owner 2026-11-10; nothing built yet.** The Hearth side writes the same text as
> "Version 2" in Hearth `docs/tv-remote-api.md` (Hearth TV owns the API, contracts README #16). The full proposal,
> with the `:hearth-client` plan and phasing, is the lead's design note of 2026-11-10; this section is the wire contract
> and the rules both sides build to. Everything in v1 ("As built: Hearth TV direct") stays as written unless the diff
> below says otherwise.
>
> Amended 2026-11-10 (owner): kid asks forwarded in mode ha; one-tap HA for parent phones (V2.10b).

Decisions it follows:

- **Roles are told, never detected.** A phone app's Hearth role is `none` | `kid` | `parent`, with the TV's mode
  `local` | `ha`. The TV binding tells it; on one phone, Glint's stand-down intent can tell HearthTube `none`. No app
  looks for Glint, HearthTube or HA. **One agent per device** follows from these told roles.
- **HA wins outright** when a TV is paired with Home Assistant; nothing is merged. In HA homes HA holds every ask: kid
  apps still ask over the hub and the TV forwards the ask to HA; adult TVs show and answer them as they do without HA
  (V2.10a), and a Glint parent phone joins HA in one tap (V2.10b).
- **No ntfy, no push service, no background polling.** Pushes travel only over a session the app opened itself.
- **Household sync stays TV-only and sealed.** A phone app never joins or reads it; a TV writes a kid app's usage into it.
- **HearthTube mobile** (on phones without Glint) is a Hearth agent; contract #13 is reversed. It consumes
  `:hearth-client` as published artifacts (GitHub Packages: `com.thesiegs.hearth:hearth-client-core`, a plain-JVM jar,
  and `com.thesiegs.hearth:hearth-client-android`, a thin AAR). `:hearth-client` license: TBD (owner).

### V2.1 Diff against v1

```diff
 Discovery
-| `v` | `1` |
+| `v` | `2` (the highest version the TV speaks; it accepts hello v 1 or 2) |
+| `a` | `1` while an ask waits in this household and the TV is in mode `local` (no name, no minutes). Absent
+|     | otherwise, and always absent in mode `ha`. Read only by Glint on parent phones, on the LAN (V2.15). |

 The TV's key
+The TV's remote id is also written into its household-sync `member` entry (`remoteId`), so every TV can tell a phone
+app which other TVs are its household's.

 Who a phone is
-adult or restricted
+Each paired app has a told Hearth role, `none` | `kid` (bound to one person) | `parent`, and the TV's mode,
+`local` | `ha`. An adult binds each paired app in Settings > Family > Phones as "<kid>'s phone", "a parent's phone" or
+"not this one" (`none`; also every new pairing until bound). v1's "adult" is `parent`; v1's "restricted" is `none`.
+The binding is a signed `phone` entry {fingerprint, role, person, name, addedBy} in household sync (TV-to-TV only), so
+every TV in the household accepts that app with that role: pair once, use any TV.

 Session
+Every phone message may carry `id` (a short string); the TV answers it with `ok {re}` or `error {re, ...}`.
+New messages and fields below are used only in sessions whose hello said v: 2.

 Phone -> TV
+| `sync`   | any role  | role and mode; for kid: usage counters and the rules tag it has; answered by `synced` |
+| `ask`    | kid       | an ask for more time for the app's own kid (both modes; in mode `ha` the TV forwards it to HA) |
+| `kids`   | parent    | one-shot list of every kid's time and waiting asks |
+| `answer` | parent    | answers an ask (mode `local` only) |
+| `hold` / `hold_end` | parent | pause (all, a group or an app) for a kid, or end one (mode `local` only) |
+| `ha_ticket` | parent | asks for a one-time HA ticket, Glint's one-tap HA link (mode `ha` only, V2.10b) |
+| `unpair` | any role  | forgets this app on every TV |

 TV -> phone
+| `welcome` | after a v2 hello, before the first `state` |
+| `state.time` | new optional object in `state` |
+| `synced`, `rules`, `time`, `ask`, `answered`, `kids`, `ha_ticket`, `ok` |

 Errors
+`forbidden`, `not_bound`, `ha_rules`, `ha_unreachable`, `stale_day`, `too_often`, `already_answered`, `expired`, `not_found`
```

### V2.2 Hello and welcome

```json
{"t":"hello","v":2,"client":"HearthTube · Pixel 9","kid":true}
```

`client` is "Glint · <device>" or "HearthTube · <device>", so an adult can spot two apps on one handset in the Phones list.
A v2 TV answers:

```json
{"t":"welcome","v":2,"role":"kid","mode":"local","person":{"id":"p_3f9a…","name":"Sam"},
 "tvs":[{"id":"9c1e44d07a2b11f0","n":"the den TV"},{"id":"51aa…","n":"the living room TV"}],
 "now":1794336000000,"tz":"America/Denver"}
```

- `role`: `none` | `kid` | `parent`, as an adult bound this app (V2.4). `person` only for `kid`, never anyone else's.
- `mode`: `local` (the TV's own Hearth rules) or `ha` (the TV is paired with Home Assistant; rules and minutes come from HA
  through the TV, V2.10). `synced` repeats `role` and `mode`, so a change reaches the app at its next sync.
- `tvs`: the household's TVs by remote id. The app trusts another TV when its pairing-port certificate key hashes to an id
  on this list (Glint already checks TXT `id` against the key, `HearthTvId.matches`). Refreshed on every welcome.
- `now`, `tz`: the TV's clock and the household zone (V2.8).
- `ha`: `{"offer":true}` only to a `parent` app in mode `ha` whose hello didn't say `"haPaired":true` (V2.10b).

### V2.3 `state.time`

```json
{"t":"state", "...v1 fields...": "",
 "time":{"minutesLeft":12,"group":{"id":"youtube","name":"YouTube"},
         "until":"2026-11-10T20:30:00-07:00","locked":false,"why":null}}
```

- For the profile in front: `minutesLeft` for the group that binds the app in front (the smaller of that group and All);
  `group` names it (`all` when All binds); `until` is when the next lock starts (bedtime, school time) while not locked, or
  when the lock ends while `locked`; `why` is `time_up` | `bedtime` | `school` | `paused` | null.
- `time` is null for an adult profile or no limit. **In a kid session it is null unless the profile in front is that app's
  own kid**; a `none` session always gets null. Pushed on change like the rest of `state`; a minute ticking down is not a
  change (the app counts down from `minutesLeft` at receipt). In mode `ha` it reports what the TV enforces (HA's rules).
- Glint's dealt TV tile gets "the den TV · title · 12 min left" from this.

### V2.4 Told roles (no detection)

- **Default `none`.** An app that isn't paired, or is bound "not this one", is just its app: HearthTube is just YouTube,
  Glint is just the launcher. No Hearth UI, no Hearth background work.
- **The TV tells.** An adult binds each paired app on the TV (Settings > Family > Phones): "<kid>'s phone", "a parent's
  phone" or "not this one". The TV returns `role` and `mode` in `welcome` and `synced`. With `mode: ha` the app shows HA's
  minutes as the TV relays them and **never runs its own rules** (HearthTube's own allowance stays off).
- **A local agent can tell another app to stand down.** When Glint is the Hearth agent on a phone (told `kid` or `parent`
  by a TV, or paired with Hearth HA), it sends HearthTube an **explicit intent** to a permission-protected receiver:
  action `com.thesiegs.hearth.action.SET_ROLE`, extras `role: "none"`, `agent: "glint"`, `why: "another agent handles
  Hearth here"`. HearthTube's receiver requires `com.thesiegs.hearth.permission.SET_ROLE`, declared
  `signature|knownSigner` with Glint's signing certificate in `knownCerts` (Android 12+, within HearthTube's minSdk 31).
  Glint sends it when its own role becomes `kid` or `parent`, and `role: "tv"` (follow the TV again) if it stops being the
  agent. An explicit intent to an app that isn't installed goes nowhere, so Glint doesn't query for HearthTube either.
  `agent: "glint"` also tells HearthTube that Glint's provider (contract #1, unchanged) is where its kid minutes come from.
- **The TV records it.** HearthTube, standing down, says so at its next contact with a TV (`sync {standDown: true}`); the
  TV then shows that HearthTube pairing as "not this one", and its `welcome`/`synced` say `role: none` from then on.
- **HearthTube never queries for other apps** (no package checks, no provider probes for roles, no HA lookups). It obeys
  only the TV and that receiver.
- **When the role is read:** on app open and at the app's own syncs (V2.15), nowhere else; no background role checks.
- **One agent per device** is enforced by these told roles: the adult's binding, the stand-down intent, and the client
  names. Apps can't reliably recognize one handset across apps (ANDROID_ID differs per signing key), so the TV doesn't try.

### V2.5 Role table

| App | Told role | Mode | What it shows | Background work |
|---|---|---|---|---|
| Glint | none | – | Launcher only; on a kid phone its own parent-PIN limit (`GlintLocal`) as today | None for Hearth |
| Glint | kid | local | Own minutes from the hub, holds at 0, ask over the hub | None; syncs only at the V2.15 triggers; ask wait ≤ 10 min with the screen on |
| Glint | kid | ha | Its Hearth HA pairing if it has one (HA wins); else HA's minutes relayed by the TV, read-only; **ask over the hub** (forwarded to HA by the TV) | As above; no usage upload; ask wait ≤ 10 min with the screen on |
| Glint | parent | local | Family: each kid's minutes, asks, answer and hold; "12 min left" on the TV tile | None; the existing Start-visible probe of paired TVs (throttled), which also fires on TXT `a=1` |
| Glint | parent | ha | Family from the HA summary (HA wins); asks through HA (its own HA link, one tap: V2.10b); TV tile time | Existing HA socket while Start is up |
| HearthTube | none | – | Just YouTube; no Hearth UI | None |
| HearthTube | kid | local | Its YouTube allowance from hub minutes (smaller of YouTube group and All); ask | None; sync on open and on crossing 15/5/0 while playing; ask wait ≤ 10 min while open |
| HearthTube | kid | ha | HA's minutes relayed by the TV; its own rules off; **ask button (forwarded to HA by the TV)** | None; sync on open and on crossing 15/5/0; no usage upload; ask wait ≤ 10 min while open |
| HearthTube | parent | local | While open only: each kid's minutes, answer or hold asks | None: no checks, no push service, no ntfy |
| HearthTube | parent | ha | One line: "asks come through Home Assistant" | None |

Asks reach adult TVs in both modes (V2.10a). Without HA they also reach Glint on parent phones; a HearthTube parent sees
them only while it is open. In mode `ha` kid apps still ask over the hub; the TV forwards the ask to HA. Parents' phones
get asks from HA's own app notifications.

### V2.6 Kid role: pair, rules and minutes, usage, ask

**Pair.** Unchanged v1 polo pairing with the code on the TV (Glint's `RemoteV2Pairer`/`PairTarget.hearth`). The new app is
`none` until an adult binds it (V2.4). An app may say `kid: true` in hello; that keeps v1's "stricter" rule and puts it at
the top of the TV's Phones list as "wants to be a kid's phone".

**Sync** (one round trip; the only regular kid message):

```json
{"t":"sync","id":"s41","have":"r-8c1f","now":1794336012000,
 "usage":[{"day":"2026-11-10","seq":118,"allMs":3120000,
           "groups":{"youtube":1500000,"games":900000}}]}
```

```json
{"t":"synced","re":"s41","role":"kid","mode":"local","now":1794336012400,
 "rules":null,
 "time":{"asOf":1794336012400,"day":"2026-11-10",
         "all":{"left":42,"used":78},"groups":{"youtube":{"left":10,"used":50},"games":{"left":30,"used":30}},
         "locked":false,"why":null,"until":"2026-11-10T20:30:00-07:00","hold":null},
 "ask":{"id":"a7","status":"waiting"}}
```

- `rules` is sent only in mode `local` and only when the TV's tag differs from `have`:

```json
{"tag":"r-8d02","tz":"America/Denver",
 "all":{"weekday":120,"weekend":180},
 "groups":[{"id":"youtube","name":"YouTube","weekday":60,"weekend":90,
            "apps":["com.google.android.youtube","com.thesiegs.hearthtube.mobile"]},
           {"id":"games","name":"Games","weekday":45,"weekend":60,"category":"game","apps":[]}],
 "bedtime":{"from":"20:30","to":"07:00","days":"all"},
 "notCounted":["com.android.dialer","com.google.android.apps.messaging"]}
```

  `category` lets a group take every app Android files under that category (`ApplicationInfo.category`), so the TV need not
  list phone packages. `apps` may mix TV and phone packages; `:hearth-client` carries a small alias table (YouTube TV ↔
  mobile, HearthTube TV ↔ mobile).
- `time.*.left` already includes this upload, so the app's local estimate is exact at that moment (`HubSnapshot` in `:hearth-client`).
- Only the bound kid's rules and minutes are ever in a kid session. There is no `person` field the app can set: the person
  comes from the binding.
- In mode `ha`: `rules` is always null, `time` is HA's minutes as the TV holds them (read-only), and `usage` is not taken
  (HA counts the phone through Family Link); the reply says `"usage":"not_taken"`.

**Usage counter rules** (TV side, mirrored in tests):
- Keyed by (app fingerprint, household day, bucket). Values are **cumulative milliseconds since the household day began**.
  The TV keeps the **maximum** it has seen; a repeat, a reorder or a lower value changes nothing (idempotent, never
  loosens). `seq` rises per upload and is for logs only.
- Days accepted: today and the two days before, by the TV's clock in the household zone. A future or older day is
  `stale_day` (the rest of the upload is still taken).
- The TV writes the counter into household sync for the app as a `usage` entry (person = the kid's person id, item
  `phone:<fingerprint16>:<day>`, value = the buckets). Merge for this kind is **per-bucket max** (a grow-only counter), not
  newest-wins, so two TVs writing the same app's entry agree. Every TV sums all devices' entries for the kid's minutes.
  Household sync itself stays TV-only and sealed: the app never sees an entry.

**Ask** (both modes). In mode `local` the TV files the ask in household sync (V2.10a). In mode `ha` the TV forwards it to
Hearth HA's asks on behalf of the bound kid (the person comes from the app's binding, never from the message). Either way
the app sees the same thing: `ok {re}` at once, then `answered` on the held session or `synced.ask` at its next sync. If
the TV can't reach HA, the ask is still `ok` and the TV forwards it when HA is back; `synced.ask.status` stays `waiting`
meanwhile. `too_often` follows HA's ladder in mode `ha` (the TV passes HA's `retryInSec` through).

```json
{"t":"ask","id":"q9","ask":"a7","minutes":30,"group":"youtube","note":"homework done"}
```

The ask id (`ask`) is made by the app, so a resend is the same ask. Answered `ok {re}` at once; the answer arrives as

```json
{"t":"answered","ask":"a7","minutes":30,"by":"an adult","at":1794336400000}
```

on the session the app holds open while the ask waits (V2.15), or as `synced.ask` at its next sync (`status`: `waiting` |
`approved` | `not_now` | `expired`). One waiting ask per kid; `too_often {retryInSec}` after "not now" or repeated asks
(same ladder as Hearth HA's).

### V2.7 Parent role: kids, answer, hold

```json
{"t":"kids","id":"k1"}
{"t":"kids","re":"k1","list":[{"person":{"id":"p_3f9a…","name":"Sam"},
   "time":{"all":{"left":42,"used":78},"groups":{"youtube":{"left":10,"used":50}},"locked":false,"why":null},
   "asks":[{"id":"a7","minutes":30,"group":"youtube","note":"homework done","at":1794336012000,"expiresAt":1794337812000}]}]}
{"t":"answer","id":"n2","ask":"a7","minutes":30}
{"t":"answer","id":"n3","ask":"a7","minutes":0}
{"t":"hold","id":"h1","person":"p_3f9a…","what":{"group":"youtube"},"minutes":30,"reason":"dinner"}
{"t":"hold_end","id":"h2","person":"p_3f9a…","what":{"group":"youtube"}}
```

- `minutes: 0` is "not now". `hold.what` is `{all:true}` | `{group}` | `{app}`; length is `minutes` or `until`, as
  `HearthPauses` builds for HA, so one `PauseChoice` feeds both.
- While a parent session is open the TV pushes `ask` events (same shape as a `kids.asks` item) and `answered`. Parent apps
  open sessions only while they are on screen (HearthTube: while open; Glint: Family hub open or the Start-visible probe).
- In mode `ha`, `kids` still reports (display only, no asks list) and `answer`/`hold`/`hold_end` answer `ha_rules`;
  parents answer through HA (Glint: its own HA link, one tap via `ha_ticket`, V2.10b).

### V2.8 Clock and time zone

- The household zone (`tz`) and the TV's clock are the authority for "today" and bedtime. The app keeps
  `offset = tv.now - phone.now` from each welcome/synced and uses phone time + offset for day boundaries and bedtime;
  durations come from the phone's elapsed counts and need no correction.
- The app buckets usage by household day: an interval over household midnight is split (DST days of 23 and 25 hours
  included). A phone away in another zone keeps home time (owner decision: home time).
- A phone clock set back does not reopen a day: counters are max-merged per day and only today/two days back are taken.

### V2.9 Roles and scopes

| Message | parent | kid | none |
|---|---|---|---|
| v1 `media`/`seek`/`volume`/`apps`/`art` | yes | yes (v1 restricted rules) | yes (v1 restricted rules) |
| v1 `launch` | yes | the stricter of the profile in front and the kid's own rules | profile in front (v1 restricted) |
| `state.time` | profile in front | only when the profile in front is their kid | null |
| `sync` | role and mode only | own kid only | role and mode only |
| `ask` | `forbidden` | own kid only | `not_bound` |
| `kids`, `answer`, `hold`, `hold_end` | yes | `forbidden` | `forbidden` |
| `ha_ticket` | mode `ha` only (V2.10b) | `forbidden` | `forbidden` |
| `unpair` | self | self | self |

`forbidden` never says whether a person or ask exists. The TV checks the role on every message, from its own store, never
from the app's word (`kid: false` still grants nothing).

### V2.10 With Home Assistant (HA wins)

When the TV is paired with HA, `mode` is `ha`. Nothing is merged: the TV enforces HA's last rules (also while HA is
offline) and relays them read-only: `state.time`, `synced.time` and `kids` report them; `rules` is never sent; kid usage is
not taken; `ask` from kid apps is forwarded to HA (V2.6); `answer`, `hold` and `hold_end` from parent apps answer
`ha_rules` (Glint parents answer through their own HA link, set up in one tap: V2.10b); TXT `a` is absent. HA's approvals
hold every ask; parents' phones get them from HA's own app notifications, and adult TVs show them (V2.10a). A Glint kid
phone paired with Hearth HA uses that pairing first; without one it asks over the hub like any kid app.

### V2.10a Asks: one surface, two authorities

The TV's ask and answer surface is the **same in both modes**: a TV showing an adult profile shows kids' asks with answer
and hold. Only the authority behind it differs.

- **`mode: local`:** Hearth is the authority. Asks go TV-to-TV through household sync (`HouseholdNotices`) and to paired
  parent apps over v2 (`ask` events on open sessions, `kids`, TXT `a` for Glint's probe).
- **`mode: ha`:** HA is the authority. The adult TV sends the answer (or hold) to HA's approvals as the adult whose profile
  is loaded, checked with the parent PIN. Kid apps' asks reach HA through the TV they're synced with (V2.6). Parent
  phone apps answer through HA, not over v2; Glint parents get that HA link in one tap (V2.10b).
- **Both modes:** the first adult to answer anywhere wins, and the ask clears everywhere else (`already_answered` to a late
  answer over v2; HA's approval state in mode `ha`).
- **Dependency (Hearth session):** in mode `ha`, asks show on adult TVs within seconds only with the instant HA-to-TV
  refresh (review C2).

### V2.10b One-tap Home Assistant for parent phones (mode `ha`)

So a parent phone joins the home's HA with one tap and no address, code or admin approval.

1. **Offer.** In mode `ha`, `welcome` (and `synced`) to an app bound as `parent` carries `"ha":{"offer":true}` unless the
   app's `hello` said `"haPaired":true`. Never sent to `kid` or `none` apps, or in mode `local`.
2. **Ask for a ticket only on the tap.** Glint shows "Use this home's Home Assistant" once (dismissable; it doesn't come
   back after "not now" until the next pairing). On tap it sends:

   ```json
   {"t":"ha_ticket","id":"h1"}
   ```

   The TV asks HA for a fresh ticket for "a parent phone" bound to this app and answers:

   ```json
   {"t":"ha_ticket","re":"h1","url":"https://ha.example:8123","ticket":"…","expiresAt":1794336700000}
   ```

   Tickets are minted on demand (none sit unused), single-use, short-lived (5 min), and tied to this app's binding on
   this TV. Errors: `forbidden` (not a parent app, or mode `local`), `ha_unreachable` (`retryInSec`).
3. **Redeem.** Glint redeems the ticket with HA directly (Hearth HA's endpoint; HA side owned by the Hearth session) and
   gets its own device secret as a `mobile` device for that parent. From then on Glint's `hello` says `"haPaired":true`
   and it answers and holds asks through its own HA link (V2.10).
4. **Already HA-paired:** Glint never shows the offer and never asks for a ticket.
5. **HearthTube** never requests a ticket; its parent role stays the view-only line ("asks come through Home Assistant").
6. **Security:** the ticket travels only over the paired, encrypted v2 session, only to an app an adult bound as a
   parent's phone; it is never logged, stored after redemption, or passed to other apps.

### V2.11 Versioning and backward compatibility

- An app reads TXT `v`: `1` → speak v1 exactly; `2` → hello `v: 2`. A v2 TV takes hello v 1 or 2; a v1 session sees no
  `welcome`, no `state.time`, no new messages and no new errors: byte-for-byte v1.
- A v2 app on a v1 TV: the remote works; Hearth roles stay `none` ("update Hearth TV to share minutes").
- Within v2, optional fields may be added and ignored by readers (the contracts README rule). New messages or changed
  meanings bump to 3. `HearthPorts.VERSION` becomes the app's maximum; `ContractDocsTest` checks it against the doc.

### V2.12 Offline and catch-up

- No TV reachable: the app keeps the last role, mode, `rules` and `time` snapshot with its counter at that moment, and
  counts locally (`HubSnapshot` in `:hearth-client`). A new day starts from the cached rules' daily minutes less the phone's own use (mode `local`; in
  mode `ha` the last relayed minutes stand until the next sync). Holds and bonuses granted while away arrive at the next
  sync; overspend while away is accepted (owner).
- On return: one `sync` with today's counter and any earlier days still within two days. Max-merge makes it safe to send
  everything again.
- Doubt never changes a role: an unreachable TV keeps the last told role. Only a told change does (`role: none` in
  `welcome`/`synced`, or the stand-down intent); then the app goes back to just being its app, as the adult chose.

### V2.13 Conflict rules

| What | Rule |
|---|---|
| Rules | Edited on a TV; household newest wins (Hearth). Apps never write rules in v2. |
| Usage | Per (app, day, bucket) max; sum across devices. |
| Ask answers | Both modes: the first adult to answer anywhere wins and the ask clears everywhere else; later v2 answers get `already_answered {minutes}`. Mode `local`: bonuses are entries keyed by ask id, so applying twice adds once. Mode `ha`: HA's approvals decide. |
| Holds | Newest wins per (person, what); `hold_end` ends only that what. An adult's family pause never ends one app's hold. |
| Bindings | Signed `phone` entries; a removal never loses (as `member`). The stand-down report sets `none`. |
| HA vs Hearth | HA wins outright while the TV is HA-paired. |

### V2.14 Errors

v1: `not_paired`, `not_allowed`, `unsupported`, `no_session`, `bad_request`. New in v2: `forbidden` (role lacks the scope),
`not_bound` (a `none` app asked a kid thing), `ha_rules` (a rule-changing or parent message in mode `ha`: `answer`,
`hold`, `hold_end`, any `rules` write; `ask` never gets it), `ha_unreachable` (`retryInSec`; the TV can't reach HA for
an `ha_ticket`, V2.10b), `stale_day` (`day`: which day), `too_often`
(`retryInSec`), `already_answered` (`minutes`), `expired` (ask), `not_found` (parent only: unknown ask). Every error carries
`re` when the request had `id`, plus v1's `for` and `message`.

### V2.15 Battery

No polling, no background work, no push service, no ntfy. An app opens a session only:

1. **On open**: Glint when Start comes to the front with the screen on (at most once per 5 minutes); HearthTube when it
   opens. Connect, `hello`, `sync` (parent: `kids`), `bye`: one TLS handshake with the radio already awake.
2. **When the local estimate crosses 15, 5 and 0 minutes** while the kid uses the phone (Glint) or plays (HearthTube): one
   sync before holding, so a hold is never based only on a stale number.
3. **While an ask waits**: the session stays open (no pings) for at most 10 minutes, Glint with the screen on, HearthTube
   while open, so `answered` arrives at once. This replaces `AskCheck`'s 20-second status posts on the hub path.
4. **Glint parent phones, mode `local`**: the existing Start-visible probe of paired TVs (at most every 2 minutes per TV)
   also fires when a TV's TXT says `a=1`, and reads `kids`. That is the only use of `a`; HearthTube never reads it.

Where to connect: the last TV's address first (3 s), only when it is in the phone's current network
(`LocalAddress.inNetwork`); NSD (`_hearth-tv._tcp`, ids from `tvs`) at most once per open and 15 minutes when that fails; on
cellular or another network, nothing at all. Roles are read only at these moments.
