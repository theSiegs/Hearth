# Household message hub (design)

> **Design only, nothing built.** Written 2026-11-06 from web research and from Hearth HA as it is on master. Claims
> from research carry a link; anything that couldn't be confirmed is marked **(unverified)**. The task list at the end
> starts with a trailblaze on the first adult's own phone and account. Read
> [home-assistant-integration.md](home-assistant-integration.md) first for Hearth HA's shape.

## Goal

Every message a household member receives (and, to a lesser degree, sends) over SMS, MMS and RCS, later WhatsApp,
Signal and Meta's apps, lands in one store the household runs, kept per account, where it can be acted on:

- **Kid-safety checks**: a local model flags what an adult should look at, and Hearth tells the adults.
- **Sending things to TVs**: a link texted to "the TV" plays there; a message can raise a pop-up.
- **Later, a local LLM acting on messages**: answering "when is pickup?" from what was texted, drafting replies.

Not a goal: a chat app. The household keeps using Google Messages and the rest. A Matrix client can read the archive,
but nobody has to use one.

## Shape in one picture

```
 phone (Google Messages) ──pairs like Messages for Web──> mautrix-gmessages ─┐
 phone (WhatsApp, Signal, ...)  ── later, other mautrix bridges ─────────────┤ appservice API
 phone (Glint: notifications, SMS provider) ── upload when home/tailnet ─────┤
                                                                             v
                                   Matrix homeserver (federation off, registration closed)
                                   = the archive: a room per conversation, per account
                                                                             │ appservice transactions
                                                                             v
                           Home Assistant: "hub consumer" (thin custom integration, bodies in memory only)
                             ├─ AI Task (local model via Ollama): classify, flag, extract
                             ├─ HA events (ids and labels, never bodies) -> automations
                             └─ Hearth HA: family directory, parent alerts and approvals, ntfy push, TVs
```

**Who owns what.**

| Part | Owns | Never |
|---|---|---|
| The hub (homeserver + bridges) | storage, bridging, media, retention, backups of the archive | decides who is a kid |
| Hearth HA (`custom_components/hearth`) | the family directory (person to accounts to devices, device secrets for kids' phones), consent records, parent alerts and approvals, push to phones, TVs | stores message bodies |
| AI Task (HA, with a local model) | the model, prompts run through `ai_task.generate_data` | keeps the archive |
| Glint (the family's Android launcher) | capture on the phone for apps without a bridge | keeps its own archive beyond an upload queue |
| HA's recorder | ids, labels, counts, bridge health | message bodies, phone numbers, media |

## Capture

### mautrix-gmessages (first)

[mautrix-gmessages](https://github.com/mautrix/gmessages) is a Matrix puppeting bridge that logs in to Google Messages
as a Messages for Web session and mirrors SMS, MMS and RCS both ways. What research found, as of November 2026:

- **Releases are monthly** (v26.10 on 16 Oct 2026, v26.09, v26.08, ...): [releases](https://github.com/mautrix/gmessages/releases).
  v26.08 is a required stepping stone (it prepared stable portal ids); v26.10 lets a login re-pair by tapping the emoji
  again and uses a more stable id so a re-login doesn't need bridged rooms deleted.
- **Pairing: Google account only.** QR pairing is gone: Google discontinued it and the bridge disabled it in v26.05
  ([releases](https://github.com/mautrix/gmessages/releases);
  [Android Authority](https://www.androidauthority.com/google-messages-qr-code-pairing-removed-3667876/)). The
  remaining method ([docs](https://docs.mau.fi/bridges/go/gmessages/authentication.html)): send `login google` to the
  bridge bot, sign in to the Google account in a **private** browser window, hand the bridge the `/web/config` request
  (as cURL) or its cookies, then tap the matching emoji in Google Messages on the phone. Use Firefox or another browser
  without Device Bound Session Credentials, don't browse anywhere else in that window, and don't use cookies of a
  browser signed in to several accounts. Google Fi's "sync to your Google Account" mode isn't supported. The cookies
  are a credential: they live in the bridge's database and nowhere else.
- **Pairing breaks when Google changes the protocol.** Late August 2026, pairing failed with `unknown error pairing:
  3/32`; the reporter traced it to the Google Messages **open beta** and pairing worked again on the stable app
  ([#91](https://github.com/mautrix/gmessages/issues/91), closed 14 Sep 2026; cause is the reporter's, not confirmed by
  the maintainer). Another project reports pairing still failing on v26.09
  ([linagora/twalk#223](https://github.com/linagora/twalk/issues/223)) **(unverified for v26.10)**. Rule: **the phone
  stays on the stable Messages app, not the beta.**
- **The phone must stay online.** All messages are proxied through the app on the phone
  ([docs](https://docs.mau.fi/bridges/go/gmessages/authentication.html); [etke.cc](https://etke.cc/help/bridges/mautrix-gmessages/)).
  The bridge pings the phone (every 20 minutes by default since v26.05) and warns when it hears nothing for a long time
  (a deployment guide says 12 days: [matrix-docker-ansible-deploy](https://git.cqre.net/cqrenet/matrix-docker-ansible-deploy/raw/commit/20c2aade3ec34bb6fd70fbad8c67653ae6c592b2/docs/configuring-playbook-bridge-mautrix-gmessages.md)
  **(unverified)**). A phone off or out of data means nothing arrives until it's back; the bridge then catches up.
- **One active web session.** Google lets a Messages account pair several computers but only one is active at a time;
  opening Messages for Web elsewhere makes the others inactive
  ([Google help](https://support.google.com/messages/answer/7611075)). The bridge is one of those sessions: another
  browser tab (or another libgm tool) takes over and the bridge goes idle until it's made active again
  ([myphone-rcs-bridge](https://github.com/JustCallMeAD/myphone-rcs-bridge),
  [kith#194](https://github.com/EugeneShtoka/kith/pull/194), [gmessages#97](https://github.com/mautrix/gmessages/pull/97)).
  Whether messages that arrive while it's idle are caught up, and how fast it takes the session back, is **unverified**:
  a Phase 0 test. Windows Phone Link may behave the same **(unverified)**.
- **Backfill** is limited by what the phone still has and by the bridge's config: historical backfill only fills new,
  empty rooms; messages missed while the bridge was down are filled into existing rooms
  ([backfill docs](https://docs.mau.fi/bridges/general/backfill.html)). The bridge's own defaults for initial and
  catch-up counts weren't found; one deployment sets `max_initial_messages: 50`, `max_catchup_messages: 500`,
  `unread_hours_threshold: 720` ([matrix-docker-ansible-deploy](https://git.cqre.net/cqrenet/matrix-docker-ansible-deploy/commit/53f3c94bef59f34924c1e5e5d6777d64f9c8c3d9))
  **(unverified for gmessages' defaults; whether media is backfilled is unverified)**. Set the counts high before the
  first login: rooms made with a small backfill can't be filled later.
- **Features** ([roadmap](https://github.com/mautrix/gmessages/blob/main/ROADMAP.md)): text, media and files both ways;
  replies, reactions, typing and read receipts on RCS; deletions "own device only" both ways; portals made at login and
  on new messages. Which items are done couldn't be read from the page **(unverified)**.
- **RCS end-to-end encrypted chats.** Google Messages encrypts 1:1 and group RCS chats end to end when both sides use
  it ([Google help](https://support.google.com/messages/answer/10262381)). Messages for Web shows those chats by relaying
  them from the phone over the web session's own encrypted channel
  ([Google's E2EE paper, 2020](https://www.gstatic.com/messages/papers/messages_e2ee.pdf)), so the bridge should see
  them in plain text like any other chat **(unverified for 2026; a Phase 0 test)**. Note what that means: end to end
  ends at the hub. The archive holds what the encryption protected.
- **Known breakages**: the pairing breaks above; sessions that stop receiving while still "active"
  ([gmessages#3](https://github.com/mautrix/gmessages/issues/3), old, worked around by logging in again); the bridge
  added automatic detection for "the app stops sending new messages" and resyncs stalled connections (v0.4.2, v26.09).
- **Supervised (Family Link) accounts: unverified.** No source says whether a supervised Google account can pair
  Messages for Web, or a bridge. Family Link supervises Android and Chromebooks; a child signed in on a web browser
  elsewhere is only partly supervised ([Family Link FAQ](https://families.google/familylink/faq/)). Pairing needs the
  kid's Google account signed in to a browser on the hub's side and Messages on the kid's phone in Google-account mode.
  This is a Phase 4 test before anything is promised for kids.

**Deletions are a design problem, not a detail.** The bridge mirrors a deletion on the phone as a Matrix redaction.
A homeserver that drops redacted content loses exactly what a kid-safety check or an archive wants. Synapse keeps
redacted events' content for `redaction_retention_period` (7 days by default; `null` keeps it forever, readable by
server admins only) **(unverified current default)**. Phase 0 tests what a phone deletion does.

### Other mautrix bridges (later)

WhatsApp ([mautrix/whatsapp](https://github.com/mautrix/whatsapp)), Signal and Meta (Messenger, Instagram) bridges use
the same homeserver and the same consumer. Each is a linked device of the person's account, with its own rules: WhatsApp
backfill comes from history-sync blobs and only into new rooms; Signal sends a one-time transfer with media from the last
45 days ([backfill docs](https://docs.mau.fi/bridges/general/backfill.html)). Meta's bridges carry account risk (Meta
may flag unofficial clients) **(unverified for 2026)**. Each gets its own Phase 0-style test when its turn comes.

### Glint (for apps without a bridge)

Glint already has a `NotificationListenerService` (its Arrivals feed) and `SEND_SMS`; it doesn't read the SMS provider.
As a capture source it adds a notification capturer and an SMS-provider reader that queue messages on the phone and
upload them to the hub. It is **received-only and incomplete**:

- **Notifications aren't messages.** A notification carries the last few lines of a `MessagingStyle` conversation,
  maybe truncated; muted chats post nothing; a chat open on screen posts nothing; a message read on another device is
  cancelled before it's seen; media is at most a thumbnail; reactions, edits and deletions don't show up. Sent messages
  never appear. **(Believed, from how Android notifications work; check per app on a device.)**
- **No stable conversation id.** Group chats and senders are matched by display name, or by joining the notification's
  shortcut id and `LocusId` to the app's conversation shortcuts (Glint's own research notes this as the weak point).
- **One-time codes may be hidden.** Android 15 added redaction of "sensitive" notifications (one-time codes) for
  untrusted listeners, behind a flag and a `RECEIVE_SENSITIVE_NOTIFICATIONS` permission a normal app can't hold
  ([AOSP change](https://gitlab.e.foundation/e/os/android_frameworks_base/-/commit/9752502c0e863c613e22690a3969ede161f7814e))
  **(unverified whether it shipped on by default)**. Fine for this use; a gap to know.
- **SMS provider covers SMS and MMS, sent and received, not RCS.** RCS chats live in Google Messages' own storage, and
  third-party apps have no RCS API ([XDA](https://www.xda-developers.com/google-messages-rcs-api-third-party-apps/))
  **(unverified that RCS never reaches the provider)**.
- **Restricted settings.** For a sideloaded app, Android 13+ blocks notification-listener access, and Android 15 also
  blocks the SMS permissions, until the person taps "Allow restricted settings" on the app's info page
  ([Android Authority](https://androidauthority.com/android-15-restricted-settings-sideloading-3481098),
  [9to5Google](https://9to5google.com/2024/09/12/android-15-sideloaded-apps-restrictions/)). An app installed through a
  session installer isn't restricted. On a supervised phone, whether a kid (or the parent through Family Link) can tap
  that is **unverified**; sideloading itself needs "Apps from unknown sources" allowed for the device in Family Link
  ([Bark's guide](https://support.bark.us/en/articles/13461179-install-or-update-bark-on-androids-supervised-with-family-link)).
- **Play policy doesn't bind Glint today** (it isn't on Play): Play allows `READ_SMS` only to the default SMS handler
  ([Play policy](https://support.google.com/googleplay/android-developer/answer/16909972)). Developer verification for
  sideloaded apps is enforced in four countries from 30 Sep 2026 and worldwide through 2027; adb installs are exempt for
  now ([9to5Google](https://9to5google.com/2026/03/30/android-developer-verifier-app/),
  [Android Authority](https://www.androidauthority.com/android-developer-verification-rollout-sideloading-flow-3653395)).
- **The listener can be killed** by battery savers (OEM-dependent) and is disconnected whenever access is turned off.
- **Upload path.** A kid's phone holds no Home Assistant token. Glint posts to the hub's ingest endpoint with a token
  Hearth HA hands it in its status answer (as it hands the ntfy topic today, see `push.py`), when it's on the home
  network or the tailnet; until then it keeps a bounded queue.

Glint capture is the fallback, not the base: it is used only for apps with no bridge, and messages it captures are
marked `source: glint` so nobody mistakes them for a complete record.

## Store

### Server: Synapse, not the Conduit family (a change from the first direction)

| | Synapse + PostgreSQL | continuwuity / tuwunel (Conduit family) |
|---|---|---|
| Bridges | mautrix's recommended server; Dendrite is unsupported ([registering appservices](https://docs.mau.fi/bridges/general/registering-appservices.html)) | supported for Go bridges; appservices registered by admin command ([continuwuity docs](https://jade-website.continuwuity.pages.dev/appservices)) |
| Maintenance | the reference server | conduwuit is archived; two successors, continuwuity (releases into autumn 2026, [releases](https://forgejo.ellis.link/continuwuation/continuwuity/releases)) and tuwunel ([conduwuit mirror](https://github.com/x86pup/conduwuit)); Conduit itself is still "beta" ([docs](https://docs.conduit.rs/)) |
| Bridge encryption (appservice E2EE) | works; MSC4190 flags built in from Synapse 1.141 ([mautrix docs](https://docs.mau.fi/bridges/general/end-to-bridge-encryption.html)) | tuwunel fixed broken appservice E2EE in 1.6.1 ([release](https://newreleases.io/project/github/matrix-construct/tuwunel/release/v1.6.1)); continuwuity unknown |
| Keeping redacted content, retention, admin API | `redaction_retention_period`, retention policies, admin API for purge and export | **(unverified)** |
| Home Assistant app | a community app exists, needs the PostgreSQL app ([ha-synapse](https://github.com/MichalTorma/ha-synapse)); maintenance unknown | none found |
| Footprint | heavier (Python + Postgres) | light (one Rust binary, RocksDB) |

**Choose once.** A homeserver can't be switched to another implementation without data loss
([matrix-docker-ansible-deploy](https://git.cqre.net/cqrenet/matrix-docker-ansible-deploy/commit/600d04ad166c3e25a56f91b89cf624cb840a460e)).
The archive is the one part of this that can't be rebuilt, so the recommendation is **Synapse with PostgreSQL**, from
Phase 0 on. Tuwunel is the fallback if the box that hosts it can't spare the memory.

### Settings

- `federation` off (no federation listener, `federation_domain_whitelist: []`), registration closed, a server name
  that is never public (`hub.home.arpa`).
- `redaction_retention_period: null` (keep what the phone deleted, for admins) unless the household decides otherwise.
- Rooms unencrypted in Matrix (see [Encryption at rest](#encryption-at-rest)), so the consumer and server-side search work.
- Media repository on the same disk, `max_upload_size` large enough for video (100 MB).
- Push gateway for Matrix clients: ntfy, with pushers in `event_id_only` format so no content leaves the hub.

### Hosting: this PC first, then decide

- **Phase 0 on a PC in Docker** (Docker Desktop with WSL 2): fast to try, easy to throw away. The cost: the bridge is
  down whenever the PC sleeps; the bridge catches up when it's back, and that gap is measured in Phase 0.
- **Then an always-on box.** Two choices, for the owner to make after Phase 0:
  1. **As Home Assistant apps** (add-ons were renamed apps in 2026.2,
     [release notes](https://www.home-assistant.io/blog/2026/02/04/release-20262/)): Synapse (community app above or a
     custom one), PostgreSQL, mautrix-gmessages (no app found: a custom one, a thin wrapper around the bridge's image).
     Pros: HA's backups and updates. Cons: Home Assistant OS has no disk encryption (a community report says the
     kernel lacks dm-crypt, [forum](https://community.home-assistant.io/t/run-ha-on-a-fully-encrypted-raspberry-pi/621576))
     **(unverified)**; every HA backup grows by the archive and its media; the HA box's memory and disk must hold it.
  2. **A small VM or box beside HA** with LUKS-encrypted disk, the same compose file as Phase 0, its own encrypted
     backups. HA reaches it on the home network.
  The recommendation is option 2 unless the HA box has spare memory and the household accepts an unencrypted disk.

### Away from home

The bridge needs no inbound connection (it talks out to Google). Only two things are reached from outside: Matrix
clients reading the archive, and Glint's uploads. Choices:

- **Tailscale** (recommended): nothing is exposed to the internet; phones that read the archive join the tailnet. On a
  supervised phone the VPN app needs a parent's approval and stays on as an always-on VPN **(unverified with Family Link)**.
- **Cloudflare tunnel**: no open port, but Cloudflare terminates TLS and sees every message in plain text. Not for this.
- **Reverse proxy with an open port**: works; the archive's login page is then on the internet. Not for this.
- **Home Assistant Cloud** proxies Home Assistant and apps' ingress pages, not an app's own port
  ([ingress](https://community.home-assistant.io/t/introducing-hass-io-ingress/111502); community-sourced), and Matrix
  clients can't log in through ingress. It doesn't help here.

Glint doesn't need any of these: it uploads when it's home or on the tailnet.

## Act

### The hub consumer lives in Home Assistant (a change from "integration or bot")

The consumer is a thin custom integration that the homeserver treats as an **application service**: the homeserver
pushes every new event to an HTTP view in Home Assistant (`PUT /api/message_hub/transactions/<txn>`, authorised by the
appservice's `hs_token`), and retries with backoff while Home Assistant is down, so nothing is lost across a restart.
Its namespace covers the household's Matrix users (non-exclusive), so it hears their rooms without joining them
**(unverified that Synapse accepts a namespace overlapping the bridge's; fallback: the hub's admin script invites a
read-only bot to each portal)**.

Why in Home Assistant and not a bot calling HA from outside: a bot would call `ai_task.generate_data` through HA's API,
and every service call fires a `call_service` event with its data, which the recorder stores
([recorder](https://www.home-assistant.io/integrations/recorder)): the message body would land in HA's database. Inside
HA the consumer calls AI Task's Python helper directly, so the body stays in memory **(unverified: confirm the helper is
public and AI Task's chat log isn't persisted; check Ollama's own logs too)**.

What it does with each new message:

1. Skip anything not `m.room.message`, anything older than 10 minutes (backfill, catch-up after an outage: archived,
   never alerted on), and rooms of accounts with no consent on record.
2. Look up the account's person and role (adult, kid) in Hearth HA's directory.
3. Run the checks that apply (below), at most one model call at a time, with a queue and a timeout.
4. Fire HA events and, for kids, raise Hearth alerts. Write the result (labels, flags, extractions) back to the hub as
   an annotation, not to HA.

### AI Task

[AI Task](https://www.home-assistant.io/integrations/ai_task/) runs `ai_task.generate_data` with `task_name`,
`instructions`, an optional `entity_id` (else the preferred AI Task entity), an optional `structure` (fields with
selectors, answered as structured data) and `attachments` (each the output of a Media selector, for multi-modal models)
([action docs](https://www.home-assistant.io/actions/ai_task.generate_data/)). Ollama provides an AI Task entity; a
change adds image attachments to it and refuses other file types
([PR diff](https://github.com/code/app-python-home-assistant-core/pull/927/files)) **(unverified which HA release ships
it)**. So: text classification works with any local model; pictures need a vision model and a release with that change;
video and voice notes aren't analysed (a frame or a transcript is later work).

Tasks, each a `structure`:

- **classify**: `kind` (personal, family logistics, school, delivery, bank or code, marketing, spam), `needs_reply`.
- **kid safety** (kids' accounts only): `concern` (none, bullying, sexual content, grooming signs, self-harm, violence,
  drugs, scam, stranger contact), `severity` (0-3), `reason` (one sentence, no quotes from the message).
- **extract**: dates and times, places, links (a YouTube link the TV can play), codes. Kept in the hub's annotation;
  HA gets only what an automation needs.

The model is wrong sometimes. A flag asks an adult to look; it never blocks, deletes or answers anything by itself.

### HA events

| Event | Data | Recorded |
|---|---|---|
| `message_hub_message` | `account`, `person`, `network` (sms, mms, rcs, whatsapp, ...), `direction`, `conversation` (an opaque id), `group`, `has_media`, `kind`, `needs_reply` | yes: no content |
| `message_hub_flag` | `account`, `person`, `conversation`, `concern`, `severity`, `reason`, `link` (to the hub view) | yes: `reason` is the model's sentence, never a quote |
| `message_hub_extract` | `person`, `type` (`date`, `link`, ...), `value` | **excluded from the recorder** by default (`recorder: exclude: event_types`); automation traces still keep the last few, so automations using it should be few |
| `message_hub_status` | `account`, `state` (connected, phone offline, needs login, idle: another web session), `since` | yes |

Never in any event: a message body, a phone number, a contact's name.

### Hearth: parent alerts and TVs

- **Alerts.** A flag on a kid's account at `severity >= 2` (configurable) becomes a Hearth alert to that kid's adults:
  the HA notification and an actionable notification on the phone chosen for new apps (as Ask for more does), and a
  "changed" ping over Hearth's ntfy channel to Hearth Mobile and Glint (`push.py`). Actions: **Look** (opens the hub
  view of that conversation, on the tailnet), **Fine** (marks it reviewed), **Talk later** (a reminder). The alert text
  carries the concern and the conversation's label, not the message.
- **Approvals.** A message can't be stopped once it has arrived, so approvals are about what follows: "a new number
  is texting Alex: keep watching / it's fine". Not a gate.
- **TVs.** An adult texts a link to the household's hub number or a note-to-self conversation marked "TV" (a room tag
  in the hub): the consumer calls `hearth.play_on_tv` (YouTube id or link, app, or http(s) link). Pop-ups on a TV
  ("New message for Alex") carry no message text unless that person turns it on.

### Later: a local LLM acting on messages

A local agent (HA's conversation agent, or one beside the hub) gets read access to one person's archive through the
hub, never through HA's database, and acts only through HA services the household allows (calendar, to-do lists,
`hearth.play_on_tv`). Drafting replies is fine; **sending** is a separate, per-person opt-in, because a bridge sends a
real SMS from that person's number.

### Push to phones

ntfy with UnifiedPush covers both: Matrix clients (Element, FluffyChat and others) register ntfy as their push gateway
(ntfy implements `/_matrix/push/v1/notify`, [Element's guide](https://ems-docs.element.io/books/element-support/page/using-unified-push-and-ntfy-for-push-notifications)),
and Hearth's phones already get a contentless "changed" ping on their own topic. One self-hosted ntfy server, on the
tailnet, serves both. Matrix pushers use `event_id_only`, so ntfy sees room and event ids, never text.

## Data model

| Thing | Where | Fields |
|---|---|---|
| **Person** | Hearth HA (HA's `person`) | id, role (adult, kid), date of birth or age band (for age-graded rules), adults responsible (for kids) |
| **Account** | Hearth HA directory, mirrored to the hub | id, person, network, capture (`bridge` or `glint`), handle (number or user name; in the hub only, hashed in HA), Matrix user (`@alex:hub.home.arpa`), bridge login id, consent (see below), state |
| **Device** | Hearth HA (as today) | the phone, its secret, its push topic, its hub upload token (Glint) |
| **Conversation** | the hub: one Matrix room per conversation per account | room id, account, network chat id, 1:1 or group, participants (bridge ghosts), title, tags (`tv`, `household`), retention class |
| **Message** | the hub: a Matrix event | event id, room, sender, direction, network time, bridged time, body, format, reply, edits, reactions, deleted on the phone (redaction kept), source (`bridge`, `backfill`, `glint`) |
| **Media** | the hub's media repository | `mxc://` URI, type, size, hash, thumbnail, retention class |
| **Annotation** | the hub: Matrix events in a private room per account, written by the consumer (so they are in the hub's backups, not HA's) | message, model, task, result, when, reviewed by, reviewed when |
| **Access log** | the hub | who read which conversation of another person, when (kids can see this about themselves) |

**Retention** (defaults for the owner to confirm): adults' text kept until they delete it; adults' media 2 years;
kids' text and media kept until the kid turns 18, then handed over (export) and deleted on the hub unless they choose
to keep it; Glint captures 1 year; annotations as long as their message. A person can delete their own archive at any
time (an adult) or ask an adult to (a kid).

## Per-person access

- **Each person reads their own.** Each person has a Matrix user on the hub; the bridge's portal rooms for their
  account have that user in them. Logins are by password on the tailnet (OIDC through HA is not available out of the
  box **(unverified)**).
- **Adults read kids'.** Two ways, tested in Phase 4: the adult's Matrix user is invited to the kid's portal rooms with
  a power level that can't send (whether the bridge keeps or resets those power levels is **unverified**), or a small
  read-only hub view behind Hearth's HA panel. Either way, every read lands in the access log.
- **Adults don't read each other's**, unless one shares with the other in the hub.
- **The server admin can read everything.** That is the owner. The only technical barrier would be Matrix encryption
  (below), which this design doesn't use at first. Every adult whose messages are captured is told so before consenting.

## Encryption at rest

- **Disk**: Phase 0 on a disk with BitLocker; later on a LUKS disk (option 2 under Hosting). Home Assistant OS
  can't do this **(unverified)**.
- **Backups**: always encrypted (below).
- **Matrix end-to-bridge encryption**: the bridge can encrypt rooms so the homeserver stores ciphertext
  ([mautrix docs](https://docs.mau.fi/bridges/general/end-to-bridge-encryption.html)). The keys then sit in the
  bridge's database on the same box, the consumer needs keys too, and server-side search stops working. It protects a
  stolen database dump without the bridge's database, little else. **Not at first**; reconsider if the hub ever runs
  on a box the household doesn't control.
- **Secrets**: the Google cookies, appservice tokens and the hub upload tokens live in the bridge and hub databases and
  Hearth HA's storage, never in YAML in a repository.

## Backups

- Nightly: `pg_dump` of Synapse and the bridge database, the media directory, the bridge config, the consumer's
  annotations. Encrypted (restic or the HA backup's own encryption, AES since 2025.1 and SecureTar v3 since 2026.4:
  [HA blog](https://www.home-assistant.io/blog/2026/03/26/modernizing-encryption-of-home-assistant-backups/)).
- Kept on the home network and one copy off-site, both encrypted with a key the owner keeps offline (the HA backup
  emergency kit's key if HA's backups carry it: [emergency kit](https://www.home-assistant.io/more-info/backup-emergency-kit/)).
- If the hub is an HA app, its data is in HA's backups unless excluded; HA Cloud backups (always encrypted) would then
  carry the archive off-site. A deliberate choice, not a default.
- A restore test each quarter: restore to a scratch container, check counts.

## Consent

- **Adults**: an adult's messages are captured only after that adult agrees, on their own phone and in their own
  words: they pair their own account (the Google sign-in and the emoji tap are theirs), and Hearth HA records consent
  (who, when, which account, which uses: archive, AI checks, TV actions, LLM). Withdrawing stops capture at once
  (the bridge logs out) and offers export and deletion. The owner is the first adult, and the trailblaze is on the
  owner's account only.
- **Kids**: transparency, not a secret. Before a kid's account is paired, the kid is told what is kept, who can read
  it, what the model looks for and what happens on a flag; Glint (and Hearth Mobile) show that messages are kept and
  checked; the kid can see the access log for their own archive. Rules can be age-graded (an older teen: only
  high-severity flags reach adults, no routine reading) **(the owner decides the grades)**.
- **Other people** (everyone who texts the household) are in the archive too. It is household-internal, never shared,
  and the household's own messages; any legal question about keeping them is the owner's to check (this note isn't
  legal advice).

## What Home Assistant sees

- Entities per account: **Bridge state** (connected, phone offline, needs login, idle), **Last message** (a time, no
  content), **Messages today** (counts in and out), **Flags open** (kids' accounts).
- The events in [HA events](#ha-events): ids, labels, the model's one-sentence reason, never bodies.
- In memory only, while a message is checked: its text (and an image, for a vision model).
- Never: the archive, media, phone numbers, contacts' names, the Google cookies.
- Hearth HA additionally holds: the directory (person, accounts, devices), consent records, alerts and their answers.

## Failure modes

| What fails | What happens | What we do |
|---|---|---|
| The phone is off or offline | nothing is bridged | status `phone offline` after a ping fails; the bridge catches up when it's back |
| Another Messages for Web session takes over | the bridge goes idle | status `idle`; an adult's notification "the hub stopped hearing your phone"; the bridge takes the session back (how: Phase 0) |
| Google changes pairing or the protocol | logins fail, or messages stop | keep the stable Messages app; update the bridge monthly; re-pair (v26.10 re-pairs by emoji tap) |
| The Google cookies expire or are revoked | `needs login` | the person re-pairs |
| The hub host is down (the PC asleep) | nothing is bridged | catch-up on start, limited by `max_catchup_messages`; measured in Phase 0 |
| Home Assistant is down | no checks, no events | the homeserver retries appservice transactions; messages older than 10 minutes are archived without alerts (an "alerts missed while HA was down" summary goes to the adults instead) |
| The model is slow or down | checks queue | timeout per message; skipped checks counted in `message_hub_status`; kids' messages retried |
| The model is wrong | false alarms, missed concerns | flags are for an adult to look at; adults can mark "Fine"; a weekly sample review |
| A phone deletion | Matrix redaction | content kept for admins (`redaction_retention_period: null`) |
| Disk full (media) | the homeserver refuses uploads | a disk sensor in HA; media retention |
| Glint's listener is killed or loses access | gaps in Glint captures | Glint reports `listener connected` in its status; HA shows it |
| A kid turns off Glint's access, or uninstalls it | no capture | Hearth HA tells the adults (Glint's status stops), as it does for other device changes |

## Phased plan

| Phase | What | Done when |
|---|---|---|
| 0 | Trailblaze on this PC: Synapse, PostgreSQL, mautrix-gmessages in Docker; the owner's phone and account; measurements; a minimal read-only HA consumer | the Phase 0 tasks are checked and the numbers are in this note |
| 1 | Move to the always-on box (an HA app or a VM beside HA), Tailscale, backups, the owner's Matrix client with ntfy push | a week without missed messages; a restore test passed |
| 2 | AI Task checks on the owner's account (classify, extract), TV actions | a week's flags reviewed; nothing written to HA's database |
| 3 | Hearth: directory, consent records, parent alerts (tested with an adult account playing a kid) | an alert travels to an adult's phone and back |
| 4 | A kid's phone: check supervised pairing; transparency; kid-safety checks live | a kid's account bridged (or the fallback chosen), the kid told, alerts working |
| 5 | Glint capture for apps without a bridge | Glint's captures arrive and are marked as such |
| 6 | Other bridges: WhatsApp, Signal, Meta, each with its own Phase 0 test | per bridge |
| 7 | A local LLM acting on messages | per use, opt-in |

## Decisions for the owner

1. **The homeserver**: Synapse + PostgreSQL (recommended) or tuwunel. Has to be made before Phase 0, since it can't be
   changed later without losing the archive.
2. **Hosting after Phase 0**: HA apps (HA's backups, no disk encryption) or a VM beside HA with LUKS (recommended).
3. **Keep deleted messages** (`redaction_retention_period: null`) for adults' accounts, kids' accounts, or neither.
4. **Retention** defaults above.
5. **Where the model runs** (Ollama on which machine, which models: a text model, a vision model) and whether images
   are sent to it.
6. **Kids' rules by age**: who reads what, which severities alert.
7. **The consumer's home**: inside `custom_components/hearth` or its own integration in this repository
   (recommended: its own, `hearth_messages`, talking to Hearth through its services and events).
8. **TV actions**: which conversation counts as "the TV".

## Task list

Owner: **the owner** (pairing, consent, anything needing the owner's phone, Google account or PIN) or **an agent**.
Nothing in Phase 0 touches anyone else's phone or account. Results recorded in this note are counts and times, never
message content, numbers or names.

### Phase 0: trailblaze on the owner's phone and account (on this PC)

- [ ] **0.1 (the owner)** Decide the homeserver (decision 1). Done when this note says which.
- [ ] **0.2 (the owner)** Check the PC's disk has BitLocker on, and that the PC may stay awake during the test
  weeks. Done when both are confirmed here.
- [ ] **0.3 (an agent)** Write `tool/message-hub/` (compose file and configs, no secrets): the chosen homeserver,
  PostgreSQL, mautrix-gmessages (pinned to the latest release), ntfy; server name `hub.home.arpa`; federation off;
  registration closed; `redaction_retention_period: null`; ports bound to the PC only (the homeserver calls Home Assistant, not the other way);
  backfill counts raised (`max_initial_messages` 2000, `max_catchup_messages` 5000) before any login; bridge
  permissions so only the owner's Matrix user can log in. Done when `docker compose up` is healthy, the client API
  answers on the PC, the federation port is closed, and registration is refused.
- [ ] **0.4 (an agent)** Create the owner's Matrix user and register the bridge; write the steps into
  `tool/message-hub/README.md`. Done when the bridge bot answers `help` in a DM with the owner's Matrix user.
- [ ] **0.5 (the owner)** On the phone: confirm Google Messages is the stable release (leave the beta if enrolled),
  in Google-account mode, and note every paired Messages for Web device and Phone Link. Done when listed here (count only).
- [ ] **0.6 (the owner)** Record consent for the owner's own account (date, scope: archive and Phase 0 tests only).
- [ ] **0.7 (the owner)** Pair: `login google` to the bridge bot, sign in in a private Firefox window, paste the
  `/web/config` request, tap the emoji on the phone. Done when the bridge reports connected and portal rooms appear.
- [ ] **0.8 (an agent)** Backfill check: number of conversations on the phone (the owner counts) against portal rooms;
  per room, the oldest bridged message's date; whether media in backfill came through. Done when the table is in this
  note.
- [ ] **0.9 (the owner, then an agent)** Completeness and latency matrix, 5 messages per cell, received and sent:
  SMS 1:1; RCS 1:1; RCS 1:1 end-to-end encrypted; RCS group; MMS group (with an iPhone or SMS-only member); picture;
  video; voice note; reply; reaction; edit; delete on the phone. The owner sends and receives with a second phone or
  a willing adult; the agent compares phone times with Matrix `origin_server_ts` and reports arrived/expected and
  latency p50/p95 per cell. Done when the matrix is in this note.
- [ ] **0.10 (the owner, then an agent)** Browser-session conflict: open messages.google.com in a browser, use it for
  5 minutes while 3 messages arrive, close it. The agent records the bridge's state over time, whether the 3 messages
  reached the hub, and what it took to make the bridge active again (on its own, a bridge command, a re-pair). Repeat
  with Phone Link if it's paired. Done when written here.
- [ ] **0.11 (the owner, then an agent)** Outages: phone in airplane mode for 30 minutes with 3 messages sent to it;
  the hub stopped for an hour with 5 messages arriving. Done when catch-up time and completeness are written here.
- [ ] **0.12 (an agent)** Deletion: after 0.9's delete, check that the original is still readable by the admin and
  hidden in the room. Done when written here.
- [ ] **0.13 (an agent)** Minimal read-only HA consumer (a development integration, not released): registered with
  the homeserver as an appservice, receives transactions, fires `message_hub_message` (ids, network, direction,
  `has_media`, no body) and nothing else; no AI Task, no notifications to phones. A test automation increments a
  counter helper on each event. Install it on Home Assistant only with the owner's go-ahead. Done when the counter
  matches the messages of 0.9 and the namespace question (overlapping the bridge's) is answered.
- [ ] **0.14 (the owner, then an agent)** Canary: the owner texts their own number a unique made-up word. The agent searches
  HA's database, logs and automation traces for it. Done when it's found nowhere in HA (and found in the hub).
- [ ] **0.15 (an agent)** Write the results and a go/no-go for Phase 1 into this note; list what changed in the design.

### Phase 1: an always-on hub

- [ ] **1.1 (the owner)** Decide hosting (decision 2).
- [ ] **1.2 (an agent)** Check the target box's free memory and disk against Phase 0's use (homeserver, PostgreSQL,
  bridge, media growth per month).
- [ ] **1.3 (an agent)** Package the hub for the chosen host (a custom HA app repository wrapping the images, or the
  compose file on a LUKS VM); move Phase 0's data (`pg_dump` and media), keeping the server name.
- [ ] **1.4 (the owner)** Set up Tailscale on the hub host and the owner's phone; install a Matrix client and ntfy
  (UnifiedPush) on the phone.
- [ ] **1.5 (an agent)** Nightly encrypted backups, one copy off-site; a restore test into a scratch container.
- [ ] **1.6 (an agent)** `message_hub_status` and per-account entities (bridge state, last message time, counts); an
  automation that tells the owner when the bridge isn't connected for 30 minutes.

### Phase 2: AI Task checks on the owner's account

- [ ] **2.1 (the owner)** Decide where the model runs and which models (decision 5).
- [ ] **2.2 (an agent)** Confirm the installed HA release's Ollama AI Task entity, and whether it takes image
  attachments.
- [ ] **2.3 (an agent)** Add classify and extract to the consumer, called in-process (no service call), with a queue
  and a timeout; annotations written to the hub; `message_hub_extract` excluded from the recorder.
- [ ] **2.4 (an agent)** Repeat 0.14's canary with checks on (the model's prompt holds the text): nothing in HA's
  database, logs or traces; check Ollama's logs too.
- [ ] **2.5 (the owner)** TV actions: name the "TV" conversation; text a YouTube link; it plays through
  `hearth.play_on_tv`.
- [ ] **2.6 (the owner)** A week's review of classifications: what was wrong, prompt changes.

### Phase 3: Hearth directory and parent alerts

- [ ] **3.1 (an agent)** Hearth HA: accounts per person in the directory, consent records, the hub's upload tokens in
  the status answer (beside `push`), documented in home-assistant-integration.md.
- [ ] **3.2 (an agent)** Kid-safety check and `message_hub_flag`; Hearth alert with Look / Fine / Talk later on the
  phone chosen for new apps, and a "changed" ping over ntfy.
- [ ] **3.3 (the owner)** Test with an adult account standing in as a kid (a second adult who agrees, or the owner's
  own marked as a test kid): a planted concerning message reaches an adult and the answer comes back.

### Phase 4: a kid's phone

- [ ] **4.1 (the owner)** Decide the kids' rules by age (decision 6) and tell the kid what is kept and why.
- [ ] **4.2 (the owner)** Check whether the kid's supervised Google account can pair: try Messages for Web in a
  browser first (no bridge); then the bridge's `login google`. Done when the answer is written here.
- [ ] **4.3 (the owner)** If it can: pair the kid's account (with the kid), record consent and the transparency talk.
  If it can't: decide between Glint capture (Phase 5) and nothing.
- [ ] **4.4 (an agent)** The kid's view: the access log and the "kept and checked" notice in Glint and Hearth Mobile.
- [ ] **4.5 (an agent)** Adults' read access to the kid's rooms (power levels or the hub view), tested against the
  bridge resetting power levels.

### Phase 5: Glint capture

- [ ] **5.1 (an agent)** Glint: notification capture for chosen apps, `READ_SMS` reader, bounded upload queue, upload
  to the hub with the token from Hearth HA, `source: glint`.
- [ ] **5.2 (the owner)** On a supervised phone: check that "Allow restricted settings" can be granted for Glint's
  notification access and SMS permission, and by whom (the kid on the phone, the parent in Family Link).
- [ ] **5.3 (an agent)** Measure Glint's gaps per app against the bridge on the owner's phone (both running): what
  share of received messages Glint saw, and with how much text.

### Phase 6: other bridges

- [ ] **6.1 (an agent)** Per bridge (WhatsApp, Signal, Messenger, Instagram): read its current docs and issues, write
  its limits here (linked-device rules, backfill, account risk).
- [ ] **6.2 (the owner)** Per bridge: consent and pairing on the owner's account first; repeat 0.8 to 0.12 for it.

### Phase 7: a local LLM acting on messages

- [ ] **7.1 (the owner)** Pick the first use (answering questions from one's own messages, calendar entries from
  texts) and what the agent may do (allowed services only; sending stays off).
- [ ] **7.2 (an agent)** Read access to one person's archive through the hub, scoped and logged; nothing through HA's
  database.
