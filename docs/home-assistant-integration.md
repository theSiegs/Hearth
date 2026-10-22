# Hearth integration for Home Assistant (design draft)

> **Design draft.** Nothing here is built. It is written so another person or agent can pick it up: it says what Hearth
> does with Home Assistant today, what hurts, what the integration should be, and what is still undecided. Read
> [home-assistant.md](home-assistant.md) first (what exists) and [household-sync.md](household-sync.md) (the first
> new consumer).

## Why

Hearth uses Home Assistant in more and more ways, each wired by hand:

| Feature | How it works today | What hurts |
|---|---|---|
| TV status | Hearth posts JSON to a webhook; an automation writes seven helpers per TV | needs an administrator's token to create them; helpers and automation are fragile to rename; one webhook ID per TV to guard |
| Dashboard panel | long-lived token of a non-admin user; Hearth draws the cards itself | a hand-made token with the user's full rights |
| Approve a switch from a phone | Hearth calls `notify.mobile_app_*`, listens on the WebSocket for `mobile_app_notification_action` | the token can call any service; the notify service name is picked by hand |
| Pop-ups and buttons | Home Assistant `rest_command` posts to Hearth on port 7676; buttons call services with the panel's token | hand-written YAML per automation |
| Allowance and shared YouTube pool | `sensor.hearth_allowance` and `input_text` helpers read and written by Hearth and automations | helpers made by hand; JSON in a state string |
| Household sync mailbox (new) | needs a place to keep sealed blobs | a plain sensor loses its value on restart |

An integration can replace most of this with one setup, named entities and services, and credentials scoped to Hearth's
jobs.

**Hearth keeps working without it.** Everything above stays available on the webhook-and-token path for anyone without
the integration. The integration is the easy path, not a requirement.

## Shape

A custom integration, domain `hearth`, in this repository under `custom_components/hearth` (so it is versioned with the
app it serves), installable by HACS (custom repository) or by copying the folder. Pure Python, no extra packages if
possible. Minimum Home Assistant version: whatever the current stable release is when work starts; no support for
older ones.

One **config entry per household** (a set of TVs) and one **device per TV**.

### Entities, per TV (device)

Replacing the seven helpers:

| Entity | Type | Source field |
|---|---|---|
| TV state | `media_player`-like `sensor` (`off`, `idle`, `paused`, `playing`) | `state`, `screen` |
| App | `sensor` | `app`, `app_package` |
| Media title / artist / app | `sensor` | `media_title`, `media_artist`, `media_app` |
| Profile | `sensor` (attrs: `profile_id`, kids) | `profile`, `profile_id` |
| Kids profile | `binary_sensor` | `kids_profile` |
| Screen time up | `binary_sensor` (attrs: reason, minutes left, unlocks at) | `screen_time_*` |
| Usage today | `sensor` per profile (seconds) with per-app attributes | `usage_today` |
| Connected | `binary_sensor` (heartbeat seen within 15 minutes) | heartbeat |

Per household: **Allowance** (`hearth_allowance` replacement, see below) and **Pending TV approvals**.

Use the platform conventions: `unique_id` from the TV's stable id, `has_entity_name`, device info (model,
sw_version from Hearth's version), `entity_category` for diagnostics.

### How a TV reports

The TV posts the same JSON it posts to the webhook today ([home-assistant.md](home-assistant.md#tv-status)) so the
payload is not a second contract. Two options, to decide in review:

- **A. Integration-owned webhook per TV** (`webhook.async_register`, id made by the integration and handed to the TV at
  pairing). Smallest change; keeps `local_only`.
- **B. Integration-owned REST view** (`HomeAssistantView`) at `/api/hearth/<tv>/status`, authenticated with a
  per-TV bearer secret made at pairing. Lets the integration reject a TV that was removed and rate-limit it.

Recommendation: **B**, with the secret scoped to Hearth's endpoints only (it can't read or call anything else).

### Pairing (no token, no webhook ID typed)

1. In Home Assistant: Settings > Devices & services > Add > Hearth. The flow asks for nothing and shows a short code and
   a QR code, and waits.
2. On the TV: Settings > Home Assistant > **Pair with Home Assistant**. The TV finds Home Assistant by its address (the
   existing address field, or Zeroconf `_home-assistant._tcp`), asks Home Assistant to start pairing, and shows the same
   short code. Someone confirms the codes match in the Home Assistant UI (an administrator, since this is the
   admin-only step).
3. Home Assistant gives the TV a **per-TV secret**. That is the only thing stored on the TV; there's no long-lived
   token of a person. The integration makes the device and entities.
4. A TV removed in Home Assistant loses the secret at once (the next post is refused).

Keep the existing "Set up from your phone" page for the legacy path.

What still needs a person's own token: the **dashboard panel** (it shows a person's dashboards, with their rights) and
**phone approval** (it calls a notify service). Plan: the integration offers a **Dashboard** endpoint that returns the
dashboards and view config for a chosen Home Assistant user, and a service to run the approval, so the TV needs no
person's token at all. If that proves too large, the panel keeps using a non-admin user's token.

### Services (Home Assistant to the TV)

Replacing hand-written `rest_command` posts to port 7676:

- `hearth.notify` (target: a TV device or a household; `title`, `message`, `duration`, `position`, `image`, `camera`
  entity, up to three `actions`). Actions call a Home Assistant service **as a named user the household chose**, not as
  the panel's token.
- `hearth.approve_switch` / events `hearth_switch_approved|denied` (see approvals).
- `hearth.set_screen_time` (later), `hearth.open_app` (later, kids' parent).

Hearth on the TV keeps its own HTTP listener for these; the integration is the client and finds the TV by its address
(Zeroconf `_hearth._tcp`).

### Approving a switch from a phone

Today Hearth calls the phone's notify service itself and waits on the WebSocket. With the integration:

1. The TV tells the integration "profile P wants to log in on TV T" (a post to its endpoint).
2. The integration sends the actionable notification to the **mobile_app devices of the persons mapped to profile P**
   (a mapping the household picks once: Hearth profile to Home Assistant person), and creates the matching
   `persistent_notification`.
3. When the person taps Allow, the integration marks the request approved and answers the TV's pending request.
4. The TV enters the saved PIN as it does now. Hearth never learns which phone or notify service, and the TV needs no
   WebSocket.

It does not change who can approve: only the mapped person's phone.

### Allowance and the shared YouTube pool

Replace the JSON-in-a-state hack with real entities and services:

- Number entities per profile for minutes of YouTube left today.
- A **service** `hearth.add_usage` and an **event** for a limit reached, so automations (including ones off the TVs, like
  other family devices) can contribute to one pool.
- The integration, not the user, owns the "profile_id to name" map.

### Household sync mailbox

The first new consumer ([household-sync.md](household-sync.md)). The integration offers a small store:

- `POST /api/hearth/household/<id>/outbox` and `GET .../inbox?since=<version>`: sealed, opaque blobs with a version.
- Persisted with `homeassistant.helpers.storage.Store`, so it survives a restart. Quota: 2 MB per household, oldest
  blobs dropped first. Pictures are not stored here; they move TV to TV.
- The integration never has the household key and can't read the blobs. TVs still publish on their heartbeat as a backstop.

## Security

- Each TV's secret works on Hearth's endpoints only. A leaked secret can post status and read/write the mailbox, not
  run a service or read a state.
- Nothing is exposed to the internet. Endpoints answer local network addresses only (checked against `request.remote`,
  not a header), as the webhook does today.
- The mailbox holds ciphertext only.
- Approvals: the request id is single-use and expires in two minutes; only the mapped person can answer; a denied or
  expired request is cleaned up, as now.
- All text from the TV is untrusted: lengths capped, control characters stripped, never templated.
- The pairing flow is the one place a person must be an administrator. Document that clearly.

## Migration

1. Ship the integration alongside the existing paths; the TV prefers the integration when it is paired.
2. A TV paired to the integration stops posting to its old webhook and says so. The old automation and helpers are left
   alone and reported ("these are no longer used"); the integration offers to remove them if it made them.
3. Each TV moves on its own, one at a time, checked in Home Assistant history.
4. After a release or two of both paths, document the webhook path as legacy.

## Testing

- `pytest-homeassistant-custom-component` for the config flow, entities, the endpoints, the mailbox and the approval
  flow. Cover: pairing happy path and wrong code, a removed TV refused, quota behaviour, oversized or malformed posts,
  restart persistence, a TV that goes quiet (`Connected` turns off).
- A contract test shared with Hearth: the TV status JSON in [home-assistant.md](home-assistant.md) is one fixture used by
  both sides.
- Manual: a real Home Assistant, a real TV, phone approval end to end.

## Releasing

Version the integration with Hearth (`manifest.json` `version`). The TV reports its Hearth version on pairing and the
integration warns when the two are too far apart (a `repairs` issue). Ship through a tag; HACS reads the tag.

## Build order

1. Skeleton, config flow with the pairing handshake, per-TV device, status endpoint, status entities, `Connected`.
2. Migration of TV status; Hearth side: **Pair with Home Assistant**.
3. `hearth.notify` and action buttons.
4. Phone approval through the integration.
5. Allowance and the pool.
6. The household mailbox.
7. The dashboard endpoint (only if worth it).

## Open questions

- Status via webhook (A) or an authenticated view (B)? Recommendation is B; review the cost to the TV side.
- Can the dashboard panel avoid a person's token? If not, what is the smallest scope to ask for?
- One config entry per household or per TV? One per household is assumed; a second household on one Home Assistant is
  not planned.
- Does HACS-only installation suffice, or should it also be submitted to the default HACS list later (that has its own
  review rules)?
- Should the integration create the "Hearth profile to person" mapping from `person` entities automatically by name, and
  let a parent fix it?
- What of TVs on another VLAN: Zeroconf will not cross it, so keep the address-typed path.
