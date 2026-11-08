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
