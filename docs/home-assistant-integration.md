# Hearth integration for Home Assistant (design draft)

> **Design draft, step 1 built.** Step 1 of the [build order](#build-order) (household setup, pairing, a device per
> Hearth TV or phone, the status endpoint and its entities) is in `custom_components/hearth`, see
> [The device's side of the API](#the-devices-side-of-the-api). Nothing on the TV or the phone calls it yet. The rest is
> written so another person or agent can pick it up: what Hearth does with Home Assistant today, what the integration
> should be, and what is still undecided. Read [home-assistant.md](home-assistant.md) first (what exists) and
> [household-sync.md](household-sync.md) (the mailbox's first user).

## What it's for

One place in Home Assistant where the household's Hearth devices plug in, and where data moves in and out of them
without hand-made helpers, tokens or YAML:

- **Hearth devices.** Hearth on a TV (Google TV, one device, several profiles) and Hearth Mobile on a phone or tablet
  (one person's device; the kids' companion app, and later the adult launcher). Each pairs once and gets its own
  secret.
- **Data in.** What each device says it's doing (status, usage, requests such as "ask for 15 more" or an approval),
  and screen time that other integrations already read from other places: Family Link (phones, tablets), Microsoft
  Family Safety (Xbox, Windows), Nintendo Switch Parental Controls.
- **Data out.** What Home Assistant tells the devices: pop-ups, each person's minutes left, a family pause, approval
  answers, and the household sync mailbox.
- **People, not devices.** Screen time, allowances and approvals belong to a household person (Home Assistant's
  `person`), whichever device or service the minutes came from.

**Hearth keeps working without it.** Everything Hearth does with Home Assistant today (webhook status, the panel's
token, `rest_command` pop-ups, `sensor.hearth_allowance`) stays available. The integration is the easy path, not a
requirement.

## What it replaces

| Today | How it works | What hurts | With the integration |
|---|---|---|---|
| TV status | the TV posts to a webhook; an automation writes seven helpers per TV | needs an administrator's token to create them; renames break them; one webhook ID per TV to guard | a device per TV with its own entities |
| Dashboard panel | long-lived token of a non-admin user | a hand-made token with that user's full rights | (later) a dashboard endpoint, see [Open questions](#open-questions) |
| Phone approval of a switch | Hearth calls `notify.mobile_app_*` and listens on the WebSocket | the token can call any service; the notify service is picked by hand | the integration asks the person's phone and answers the device |
| Pop-ups and buttons | `rest_command` posts to the TV on port 7676 | hand-written YAML per automation | `hearth.notify` to any device |
| YouTube allowance, pooled | template sensors adding a pool, a bonus, Family Link minutes and Hearth's seconds; `sensor.hearth_allowance` read by the TV | hand-made per kid; one source per template; JSON in a state string | per-person screen time from every source, and budgets the devices read |
| Household sync mailbox | nowhere yet | a plain sensor loses its value on restart | a small stored mailbox |

## Shape

A custom integration, domain `hearth`, in this repository under `custom_components/hearth` (versioned with the apps
it serves), installable through HACS (custom repository) or by copying the folder. Pure Python, no extra packages.
Supports the current stable Home Assistant only.

- **One config entry: the household.** Set up once (a name). Only one per Home Assistant.
- **One device per Hearth device**, with a **kind**: `tv` or `mobile`. The kind decides its entities and what it can
  be sent. Model and software version come from the device at pairing.
- **Screen time sources** (other integrations' entities) and the **person mapping** live in the household's options.

### Kinds

| | `tv` (Hearth on Google TV) | `mobile` (Hearth Mobile) |
|---|---|---|
| Whose | several people: Google TV profiles, kids profiles among them | one person, chosen when it pairs |
| Reaches Home Assistant | on the home network only | at home, and away from home through a webhook (see [Away from home](#away-from-home)) |
| Status entities | State, App, Media title / artist / app, Profile, Kids profile, Screen time up, Screen time today, Connected | App, Media title / artist / app, Screen time today, Connected |
| Gets | pop-ups, minutes left per profile, family pause, approval answers, the mailbox | its person's state (minutes left, bedtime, pause), pop-ups, approval answers, the mailbox |
| Sends | status (with usage per profile), approval requests | status, "ask for more", approval requests |

Hearth Mobile is designed in the notes repository (the companion app first, its tests done; the adult launcher later).
Constraint from there: **no Home Assistant token on a kid's device.** The device's own secret, which works on Hearth's
endpoints only, is what this integration gives it.

## Pairing

No token, no webhook ID typed.

1. Home Assistant: Settings > Devices & services > Add integration > Hearth, and a name for the household (once).
2. The device: **Pair with Home Assistant** (on a TV, Settings > Home Assistant). It finds Home Assistant by the
   address it has, or by Zeroconf (`_home-assistant._tcp`), asks to pair and shows a 6-digit code.
3. Home Assistant shows a discovered **Hearth** device with that name. An administrator checks the codes match and
   confirms. For a `mobile` device the confirm step also asks **whose device** it is (a person); not built yet.
4. The device gets its own secret, once. That is the only thing of Home Assistant's it keeps. Pairing again gives a
   new secret and ends the old one; deleting the device in Home Assistant ends it at once.

The legacy **Set up from your phone** page stays for the webhook-and-token path.

## Data in

### Device status

Each device posts its status: when something changes (within about 2 seconds) and as a heartbeat (a TV every 10
minutes, a phone as its battery allows). The body is the JSON a TV already posts to its webhook
([home-assistant.md](home-assistant.md#tv-status)), so there is no second contract; a phone posts the fields that fit
it (`screen`, `app`, `app_package`, `media_*`, `day`, `seconds_today`, `app_seconds_today`, `playing_seconds_today`).
The integration keeps only known fields, cleaned, and keeps the last status across restarts. **Connected** turns off
after 15 minutes without a post; the device's other entities show unavailable then.

### Requests and events from a device (later)

Posted to the same device endpoint family, each turned into a Home Assistant event and, where it fits, a
notification to the right person:

- `hearth_approval_requested` (a switch into a PIN-locked profile, the Parent PIN prompt), answered as in
  [Approvals](#approvals).
- `hearth_more_time_requested` (person, minutes, the app), from Hearth Mobile's "ask for 15 more" or a kids profile on a
  TV. Answering adds a bonus (see [Budgets](#budgets)).
- Tripwires Hearth Mobile raises (see its design): an event each, never content.

### Screen time from other integrations

Many places already report screen time to Home Assistant, each from its own cloud. The integration reads their
entities; it never signs in to those services itself.

| Source | Integration | What it gives (per child) | Freshness |
|---|---|---|---|
| Hearth TVs | this one | seconds today per profile and per app (`usage_today`), playing time per app | seconds |
| Hearth Mobile | this one | seconds today and per app on that phone | seconds to minutes |
| Phones, tablets, Google TV kids profiles | [HAFamilyLink, theSiegs fork](https://github.com/theSiegs/HAFamilyLink) (branch `ha/combined`) | per child: Daily Screen Time (with usage totals) and Screen Time Remaining; per device: Daily Screen Time (per-app seconds in `apps`) and per-app usage sensors | polled every 60 s, but Google's numbers lag: seconds to about 40 minutes, for a TV profile sometimes until it next starts |
| Xbox, Windows | [Microsoft Family Safety](https://github.com/noiwid/HAFamilySafety) (HACS) | `sensor.<child>_screen_time` (minutes today, the whole account) and `sensor.<device>_screen_time` per device | polled, 5 minutes by default (30 s to an hour) |
| Nintendo Switch | [Nintendo Switch parental controls](https://www.home-assistant.io/integrations/nintendo_parental_controls) (built in) | Used screen time and Time remaining per Switch (minutes) | cloud polling; the Switch must be online |

How a source is added: in the household's options, **Add a screen time source**: pick a `duration` sensor (or one in
minutes), whose it is (a person), what kind of time it is (**video**, **games** or **other**), and whether it's one
device or a whole account. Hearth's own devices are sources automatically: a phone counts for its person, a TV's
profile for the person mapped to it ([People](#people)).

**Counting each minute once.**

- Pick per-device sensors over per-account ones where the service has both (Family Safety's account total already
  includes its devices; add either the account or its devices, never both: the options flow refuses a device sensor
  next to its own account's).
- One device, one source. Hearth Mobile on a phone and Family Link for the same phone both see that phone's time: the
  person's total takes the larger of the two for that device, not the sum; the breakdown keeps both.
- Family Link lists each kid's Google TV profile as a device of its own, so a TV's minutes come from Hearth and from
  Family Link. The options flow links that Family Link device to the TV profile it is, and Hearth's (fresher) count is
  used for it.
- Sources reset at their own midnight (the service's account time zone). A value that drops counts as a new day.
- A source that hasn't changed in a long time is shown as stale in the breakdown, not dropped: its last count still
  counts for today.

What's not available from those services, as of this writing: per-app minutes from Family Safety (it lists apps, not
their time), and Nintendo per-game time other than through its usage-report action.

## People

The household maps once, in the options:

- each **TV profile** (`profile_id`, as Hearth reports it) to a person, or to nobody (a guest or shared profile);
- each **phone** to its person (asked when it pairs);
- each **screen time source** to its person.

Hearth's TVs can suggest the mapping by name (a profile called like a person), for an adult to check. The integration,
not Hearth, owns this map; Hearth's `profile_id` to name map goes away.

Per person, the integration makes:

- **Screen time today** (minutes): the total, counted once per device as above. Attributes: per source (with its
  freshness), per kind (video, games, other), per device.
- **Video today**, **Games today** (minutes), from the same sources by their kind.

## Data out

### Games and titles

**Games** are games wherever they're played: Xbox, Windows (Steam and other launchers among them), Nintendo Switch,
phones and tablets, and game apps on a TV. How the integration knows:

| Where | Counts as games | Per game |
|---|---|---|
| Nintendo Switch | all of it | from the Nintendo integration's `device_usage_report` action, which the integration calls a few times an hour |
| Xbox | all of it | what's playing, from Home Assistant's Xbox integration (now playing per gamer), timed by the integration; Family Safety gives totals only |
| Windows | by app, from a list (Steam, Epic, Battle.net, Minecraft Launcher and the like, editable) | the playing title where a source has it; otherwise the launcher's time |
| Phones, tablets, TVs | apps Android marks as games (Hearth sends each app's category), plus any an adult adds | per app, from Hearth and Family Link |

**Titles** tie one game together across places: a title (for example "Minecraft") lists what it's called in each source
(the Android package, the Xbox and Nintendo names, the Windows app). The integration offers the matches it sees and an
adult confirms them. A title's time is its time everywhere.

### Rules

Budgets apply to everything of their kind unless a **rule** says otherwise. A rule names a title (or an app), who it's
for (everyone or some people), and one of:

- **Doesn't count:** time on it is shown but never taken from any budget (homework apps, a music app, a drawing app).
- **Own limit:** it has its own daily budget instead of its kind's, which may be longer than the person's whole daily
  screen time (Minecraft: 3 hours, while games are 90 minutes). Its time counts toward that limit only.
- **Counts less:** each minute counts as a fraction (half, a quarter) toward the kind's budget.

A rule can apply only **when** something is true; outside it, the title counts as usual:

- **Together:** two or more of the household's people are playing that title at the same time (seen where a source
  knows what's playing now: Hearth devices and Xbox; Nintendo and Family Safety report only after the fact, so
  together on a Switch can't be seen yet);
- on certain days, or between certain times.

**Playing together** is a state the integration knows and shows, not only a rule's condition: a **Playing together**
binary sensor for the household (on while two or more people play the same title; attributes: the title, who, since
when, on which devices), and a **Playing together today** duration per person. Automations and dashboards can use it
like any other state.

Rules decide in the order listed, the first that applies wins. Examples: "Minecraft, everyone, together: own limit 4
hours"; "Khan Academy Kids: doesn't count". Anything else (a longer afternoon one day, a weekend treat) is an
**extension**: the same bonus as "ask for more", given to a kind or to one title (see [Budgets](#budgets)).

### Budgets

Replaces the hand-made pool templates. Per person, number entities an adult (or an automation) sets:

- a daily **budget** per kind (for example video 120, games 90; unset is no limit), weekday and weekend values;
- **Bonus today** (minutes, reset at midnight), what chores, "ask for more" approvals and automations add to: the
  one extension mechanism, for a kind or for one title with its own limit.

And per person and kind: **Minutes left** (budget + bonus - used today, never below 0), and the event
`hearth_budget_reached` (person, kind) once a day when it reaches 0. A title with its own limit gets its own **Minutes
left** and event (person, title), and devices are told which titles are still open when the kind's budget is used up. An optional **shared pool** counts every kind
together against one budget, which is how the household's YouTube pool works today.

Services: `hearth.add_bonus` (person, minutes, and a kind or a title), `hearth.set_budget`.

**Who enforces.** The integration counts and tells; it doesn't lock anything itself:

- Hearth devices get the person's minutes left (below) and enforce it in HearthTube as Hearth does with
  `sensor.hearth_allowance` now.
- Other services keep their own limits. Automations act on `hearth_budget_reached` with those services' own actions:
  Nintendo's Max screentime today and Suspend software, Family Safety's `lock_platform` or daily limits, Family Link's
  app limits. Example blueprints ship with the integration.
- Granting more works the same way in reverse: `hearth_more_time_requested` answered with Allow adds a bonus here, and
  a blueprint can pass the same minutes on (Nintendo's `add_bonus_time`, Family Safety's `approve_request`).

### What a device gets

- **A TV**, in the answer to each status post: per profile, `{"minutes_left": {"video": n | null, ...},
  "schedule_locked": bool, "message": text | null, "pause": {"until": iso, "reason": text} | null}`. Same meaning as
  `sensor.hearth_allowance`'s map today, so Hearth's enforcement doesn't change. A TV that hasn't posted in a while
  gets it on its next post (it posts at least every 10 minutes, and every 2 while playing).
- **A phone**: its person's state document (the same fields, plus bedtime) in the answer to each post, and pushed when
  it changes (see [Away from home](#away-from-home)).
- **Pop-ups**: `hearth.notify` (target: devices, a person's devices, or the household; `title`, `message`,
  `duration`, `position`, `image`, `camera`, up to three `actions`). On a TV it's Hearth's pop-up; on a phone, a
  notification. Actions call a Home Assistant service as a user the household chose, not with any device's secret.
- **Family pause**: `hearth.pause` (minutes, reason) and `hearth.resume`: every device shows the pause and HearthTube
  stops; replaces the hand-made pause helpers and scripts.

### Approvals

1. A device posts "profile P wants to log in on TV T" (or "the Parent PIN prompt is up").
2. The integration sends an actionable notification to the `mobile_app` devices of the persons allowed to approve
   (mapped to P, or every adult for the Parent PIN), and the matching `persistent_notification`.
3. Allow or Deny answers the device's waiting request (the answer to its next poll). The TV enters the saved PIN as it
   does now. The device never learns which phone answered, and needs no WebSocket or token.

Who can approve doesn't change.

### Household sync mailbox

[household-sync.md](household-sync.md): `POST .../household/outbox` and `GET .../household/inbox?since=<version>`,
sealed blobs the integration can't read (it never has the household key), kept with Home Assistant's storage helper so
they survive restarts, 2 MB per household, oldest dropped first. Pictures don't go through it. Devices still exchange
directly on the home network; the mailbox is for devices that are rarely on at the same time.

## Away from home

TVs stay on the home network. A phone isn't always there, so `mobile` devices also get a **webhook** the integration
registers (`webhook.async_register`, not local-only), and, when Home Assistant Cloud is set up, a cloudhook URL for it.
The device's secret is still required on every call: knowing the URL isn't enough. Home Assistant to the phone uses a
push channel the phone holds open (ntfy, per Hearth Mobile's design), carrying only "something changed"; the phone
then fetches its state with its secret.

## The device's side of the API

What step 1 built. Every endpoint answers local network addresses only (403 otherwise) and answers JSON; errors are
`{"error": "<reason>"}`.

**Pairing.** Once the household is set up:

1. `POST /api/hearth/pair` with `{"device_id", "kind", "name", "model", "version", "nonce"}`. `device_id` is the
   device's own stable id (8-64 of `A-Z a-z 0-9 _ -`, made once and kept); `kind` is `tv` (the default) or `mobile`;
   `nonce` is 32-128 of the same characters, random, made for this pairing and never shown. Answers
   `{"pairing_id", "code", "expires_in"}` (seconds, 600). The device shows `code`. 404 `not_set_up` when the household
   isn't set up, 429 `try_later` when this address asked in the last 10 seconds or five devices are already waiting,
   400 `bad_request` for a malformed body or an unknown kind.
2. Home Assistant shows a discovered **Hearth** device named `name`; an administrator checks the codes match and
   confirms. Asking again from the same device replaces its earlier request.
3. The device polls `GET /api/hearth/pair/<pairing_id>` with header `X-Hearth-Nonce: <nonce>` (every 2 seconds is
   plenty): `{"status": "pending"}`, then once `{"status": "approved", "device_id", "secret"}`. After that, or once
   the request expires (10 minutes, or 2 minutes after approval), it's 404. A wrong or missing nonce is 404 too.
4. The device keeps `secret`, and nothing else of Home Assistant's.

**Status.** `POST /api/hearth/device/<device_id>/status` with header `X-Hearth-Secret: <secret>` and the status JSON
(see [Device status](#device-status)), at most 64 KB. 200 `{"ok": true}`; 401 `not_paired` for an unknown device or
wrong secret (it was removed: stop posting and offer to pair again); 429 `too_often` past 20 posts a minute; 400
`bad_request`. A refused secret is a plain 401, never a failed Home Assistant login, so it doesn't count toward Home
Assistant's IP ban. (The answer will carry what the device gets, see [What a device gets](#what-a-device-gets).)

**Entities**, per device, by kind as in [Kinds](#kinds). Screen time today is in seconds (shown in minutes), with
per-app, playing and (on a TV) per-profile attributes kept out of history. All but Connected are unavailable until the
first post and once the device has been quiet for 15 minutes; the last status is kept across restarts. Deleting the
device removes it from the household.

## Security

- A device's secret works on Hearth's endpoints only. A leaked one can post that device's status and read and write
  the mailbox, never run a service or read a state. Secrets are stored hashed.
- TV endpoints answer local addresses only (checked on `request.remote`, not a header). The phone's webhook is the one
  way in from outside, and it needs the secret too.
- The mailbox holds ciphertext only.
- Approvals: one-time request ids, two minutes, only the mapped persons can answer; denied or expired requests are
  cleaned up.
- Everything a device sends is untrusted: only known fields, lengths capped, control characters stripped, numbers
  bounded, never templated.
- Kids' devices hold no Home Assistant token.
- Pairing is the one step that needs an administrator.

## Migration

1. Ship the integration alongside the old paths; a paired device prefers the integration.
2. A paired TV stops posting to its old webhook and says so. The old automation, helpers and pool templates are left
   alone and listed as no longer used; the integration offers to remove only what it made.
3. Devices move one at a time, checked in history.
4. After a release or two of both, the webhook path is documented as legacy.

## Testing

- `pytest-homeassistant-custom-component`, in `ha_tests`: config flow, pairing (happy path, wrong nonce, too often,
  expiry), entities by kind, a removed device refused, oversized or malformed posts, rate limits, restart persistence,
  a device going quiet. Later: sources and counting-once rules, budgets and events, approvals, the mailbox's quota.
- Running them: Home Assistant's test tools need Linux. On Windows, a container: `docker run --rm -v <repo>:/src:ro
  python:3.14-slim`, then `pip install pytest-homeassistant-custom-component`, copy `custom_components` and
  `ha_tests` out of `/src`, and run `python -m pytest` in `ha_tests`.
- One status fixture shared with Hearth's own tests, so the two sides can't drift.
- Manual: a real Home Assistant, a real TV, a phone, approval end to end.

## Releasing

`manifest.json` `version` follows Hearth's version once the TV side ships (now `0.1.0`). A device reports its version
at pairing; the integration raises a repair issue when the two are too far apart. HACS reads the release tag.

## Build order

1. **Done:** skeleton, household setup, pairing with kinds, a device per Hearth device, status endpoint and entities,
   Connected.
2. Hearth TV side: **Pair with Home Assistant**, posting status to the integration (and no longer to the webhook).
3. People: the person mapping, per-person Screen time today from Hearth's own devices.
4. Screen time sources: Family Link, Family Safety, Nintendo; counting once; per-kind totals.
5. Budgets, bonus, minutes left, `hearth_budget_reached`; minutes left back to the TVs (replacing
   `sensor.hearth_allowance`); blueprints for the other services' locks.
6. `hearth.notify`, `hearth.pause`.
7. Approvals through the integration; `hearth_more_time_requested`.
8. Hearth Mobile: pairing with a person, the webhook away from home, its state document.
9. The household mailbox.
10. The dashboard endpoint (only if worth it).

## Open questions

- **Family Link's per-device numbers:** a test phone (an emulator) once showed 1.2 minutes in Home Assistant against 2
  hours on the device. Check on a real phone before trusting them in budgets; the per-child total may be the safer
  source until then.
- **Enforcing a rule on another service:** when games are used up but Minecraft's own limit isn't, a Hearth device can
  keep only Minecraft open; on a Switch or Xbox the service's own limits can't tell titles apart the same way (Nintendo
  limits the whole Switch; Family Safety can block other apps one by one). How far blueprints should go there is open.
- **Together on a Switch:** Nintendo reports play after the fact, so "together" can't be seen there yet.
- **Counting once:** is "the larger of two sources for one device" right, or should one source be chosen per device?
- **Budget kinds:** are video, games and other enough, and should the shared pool be the default?
- **Dashboard panel without a person's token:** can the integration serve a chosen user's dashboard config, or does the
  panel keep a non-admin user's token?
- **Second household on one Home Assistant:** not planned.
- **Devices on another network segment:** Zeroconf won't cross it; keep the address-typed path.
