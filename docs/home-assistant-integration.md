# Hearth integration for Home Assistant (design draft)

> **Design draft, partly built.** In `custom_components/hearth`: household setup, pairing, a device per Hearth TV or
> phone with its status entities, people, screen time sources (totals and live), titles, counting once, playing
> together, groups, budgets, bonuses, minutes left and the state document (see [Build order](#build-order) and
> [The device's side of the API](#the-devices-side-of-the-api)). Hearth on a TV pairs and reports to it; Hearth
> Mobile doesn't yet. The rest is
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
| Nintendo Switch | [Nintendo Switch parental controls](https://www.home-assistant.io/integrations/nintendo_parental_controls) (built in) | Used screen time and Screen time remaining per Switch (minutes; added as a source, its time is games unless chosen otherwise); per app through its usage report | polled every 60 s; the Switch must be online |
| Nintendo Switch, live | Switch friend presence: HACS [Nintendo-Switch-Presence](https://github.com/itsfatlum/Nintendo-Switch-Presence), fed by a self-hosted [nxapi](https://github.com/samuelthomas2774/nxapi) presence server and a watcher account | what each kid's Switch is playing now | 30-60 s |
| Xbox, live | Home Assistant's Xbox integration | now playing per gamer | about a minute |

How a source is added: in the household's options, **Add a screen time source**: pick a `duration` sensor (or one in
minutes), whose it is (a person), what kind of time it is (**video**, **games** or **other**), and whether it's one
device or a whole account. Hearth's own devices are sources automatically: a phone counts for its person, a TV's
profile for the person mapped to it ([People](#people)).

How minutes from these are combined, counted once and tied to games: see [Counting](#counting).

## People

The household maps once (see [Setting it up](#setting-it-up)):

- each **TV profile** (`profile_id`, as Hearth reports it) to a person, or to nobody (a guest or shared profile);
- each **phone** to its person (asked when it pairs);
- each **screen time source** to its person;
- each **gamer account** (Xbox gamertag, Switch user as friend presence names it) to its person.

Hearth's TVs can suggest the mapping by name (a profile called like a person), for an adult to check. The integration,
not Hearth, owns this map; Hearth's `profile_id` to name map goes away.

## Counting

### Play sessions

Where a source says what's playing **now** (Hearth TVs and phones, Xbox now playing, Switch friend presence), the
integration looks at least once a minute and whenever the sensor changes. A live source's time accrues between two
looks that both saw the same title (a skipped look loses that minute, never adds one; a gap of over 3 minutes, such as
Home Assistant being stopped, adds nothing). Today's timed seconds per source and title are kept across restarts.
(Built so far: today's totals. A 7-day timeline of sessions, to show and check a day, is still to do.)

Where a source only gives **totals** (Family Link, Family Safety, the Nintendo integration), the integration takes the
increase since its last reading as minutes on that device, at the time it saw them grow. Those minutes have no exact
time; they're "sometime before this reading".

### Counting each minute once

Per person, per device, per app or title, the day's minutes are the **larger** of what each source says, never the
sum; the breakdown keeps every source's number. So:

- Hearth Mobile and Family Link on the same phone: the larger of the two.
- A Google TV kids profile: Family Link lists it as a device of its own; the options link it to the TV profile it is,
  and Hearth's count wins whenever it's larger (it's fresher).
- Switch friend presence and the Nintendo integration on the same Switch: the larger.
- Family Safety's account total already includes its devices: add the account or its devices, never both. (The
  options don't check this yet.)

Days start at local midnight. A source that resets at its own midnight (another time zone) is read as dropping to
zero: a drop is a new day for that source. A source that stops changing is shown as stale in the breakdown; its last
count still counts, and so does its last number today while its sensor has none (unavailable). A person's Screen time
today and group sensors (total increasing, for Home Assistant's statistics) never go down during the day: when the count
dips (a source's number corrected down a minute), they keep the highest shown today until the count passes it, after
a restart too; the count itself, which the budgets use, is in the attributes.

### Games and titles

**Games** are games wherever they're played: Xbox, Windows (Steam and other launchers among them), Nintendo Switch,
phones and tablets, and game apps on a TV. How the integration knows:

| Where | Counts as games | Per game | Live (for together) |
|---|---|---|---|
| Nintendo Switch | all of it | Switch friend presence (state and game, Switch and Switch 2) through a self-hosted nxapi presence server or the HACS Nintendo-Switch-Presence sensors; needs a separate adult "watcher" account friended with each kid. Fallback: per-app minutes from the built-in Nintendo integration | presence, 30-60 s behind |
| Xbox | all of it | Home Assistant's Xbox integration (now playing per gamer), timed by the integration; Family Safety gives totals only | yes |
| Windows | by app, from a list (Steam, Epic, Battle.net, Minecraft Launcher and the like, editable) | the playing title where a source has it (Xbox now playing covers Xbox-signed-in PC games); otherwise the launcher's time | partly |
| Phones, tablets, TVs | apps Android marks as games (Hearth sends each app's category), plus any an adult adds | per app, from Hearth and Family Link | on Hearth devices |

**Titles** tie one game (or show service, or app) together across places: a title (for example "Minecraft") lists what
it's called in each source (the Android package, the Xbox and Nintendo names, the Windows app). Names match once
cleaned (case, marks, "Edition", "for Nintendo Switch", "Java", "Bedrock"), so "Minecraft for Nintendo Switch" and
"Minecraft: Java Edition" are both "Minecraft". A title's time is its time everywhere. (Built: an adult adds a title
and picks its other names from what's been seen. Still to do: offering matches by itself.)

### Playing together

**Playing together** is a state of its own: two or more of the household's people in play sessions of the same title
at the same time (overlapping by a minute or more). The integration shows it as:

- a **Playing together** binary sensor for the household (attributes: the title, who, since when, on which devices);
- **Playing together today**, a duration per person.

Automations and dashboards can use it like any other state, and rules can depend on it. Only live sources can show
it; minutes known only from totals are never "together".

## Limits

### Groups

A budget is set on a **group**: a set of apps and titles whose minutes count together. Built in:

- **All screen time**: everything not excluded by a rule.
- **Video**: video apps (Android's video category, plus any an adult adds).
- **Games**: as above.

An adult can add groups: **YouTube** (YouTube and HearthTube, on every device) is the household's pool today. A
minute counts toward every group its app or title is in, so a YouTube minute is taken from YouTube, Video and All
screen time. A device's time is up when **any** group it's playing from is used up.

### Budgets

Per person and group, number entities an adult (or an automation) sets:

- a daily **budget** (weekday and weekend values; unset is no limit);
- **Bonus today** (minutes, back to 0 at midnight).

From them, per person and group: **Minutes left** (budget + bonus - counted today, never below 0) and the event
`hearth_budget_reached` (person, group) once a day when it reaches 0. A **shared budget** can also span people (one
pool the siblings draw from), with its own Minutes left.

### Rules

Budgets apply to everything in their groups unless a **rule** says otherwise. A rule names a title or an app, who it's
for (everyone or some people), and one of:

- **Doesn't count:** time on it is shown but taken from no group (homework apps, a music app, a drawing app).
- **Own limit:** it leaves its groups and has its own daily budget, which may be longer than the person's whole daily
  screen time (Minecraft: 3 hours, while games are 90 minutes). It gets its own Minutes left and
  `hearth_budget_reached` (person, title).
- **Counts less:** each minute counts as a fraction (half, a quarter) toward its groups.

A rule can apply only **when**:

- **together:** the title is being played together (see [Playing together](#playing-together));
- on certain days, or between certain times.

Rules are checked in the order listed; the first that applies wins; a title no rule matches counts as usual. Minutes
with no exact time (from totals) count as usual too: a rule with a condition can only lighten minutes the integration
saw live. Examples: "Minecraft, everyone, together: own limit 4 hours"; "Khan Academy Kids: doesn't count".

### Extensions

Anything else (a longer afternoon one day, a weekend treat, chores) is an **extension**: minutes added to a person's
Bonus today, for a group or for one title with its own limit. There's one way to add them, `hearth.add_bonus` (person,
minutes, group or title), whoever asks:

- **Ask for more.** A kid asks from a Hearth device (Hearth Mobile's "ask for 15 more", or a TV's time's-up screen).
  The integration fires `hearth_more_time_requested` and sends the adults' phones an actionable notification: **+15**,
  **+30**, **Not now**. The first answer adds the bonus (or not) and is shown on the kid's device. One open request
  per person; it ends after 10 minutes.
- **Chores, automations, a dashboard button**: call `hearth.add_bonus`.

**Who enforces.** When one of a person's groups is out of time, its apps are held everywhere the household chose,
until the group has time again (a bonus, a higher budget, a new day):

- **Hearth devices** get the person's minutes left per group, with the group's apps, in their state document (below),
  and stop those apps themselves (HearthTube holds YouTube on its own). On a TV, in a kids profile, a held app doesn't
  open from Hearth's tiles, Continue Watching or remote buttons ("Time's up for Games today. An adult can add more
  time."); opened another way (Google TV's kids home, a voice search, a link), Hearth's home comes back over it.
  YouTube's own app is the exception: kids watch YouTube in HearthTube, so it's swapped for HearthTube, which holds
  the YouTube time itself. All
  screen time out of time holds every app. Never held: Hearth, HearthTube, Settings, the Play Store, the assistant and
  Google TV's own screens (chooser, PIN, time up). Adult profiles have no limits, and without today's answer from Home
  Assistant nothing is held.
- **Other parental controls**, per person (Configure > Enforce):
  - **Family Link** pauses the group's Android apps (`familylink.pause_app`: a 1 minute daily limit, the app stays
    installed) and resumes them (`resume_app` puts back the setting they had). Google TV ignores Family Link's app
    limits, which is why a TV is held by Hearth. All screen time out of time pauses every app of the person's Hearth
    knows: those in any group, and those in their usage today on any device or source (at most 150). Calls, texts, the
    system and the parental controls' own apps are never paused.
  - **Microsoft Family Safety** locks the chosen platforms (Xbox by default) until midnight while one of the chosen
    groups (Games and All screen time by default) is out of time (`lock_platform`), and unlocks them when none is.
  - **Nintendo** (the built-in [Nintendo Switch parental controls](https://www.home-assistant.io/integrations/nintendo_parental_controls)
    integration; the person's Switch is chosen by its **Max screentime today** number): while one of the chosen groups
    (Games and All screen time by default) is out of time, Max screentime today is set to 0 with **Suspend software**
    on, so the game is suspended (as with Nintendo's own limit, a game may close without saving). The limit and Suspend
    software it had are kept with what's held and put back when none is out of time. That limit is a setting of the
    Switch's (of every day, or of this weekday when it has a limit per weekday), not of today only, so it's put back 2
    minutes before midnight; if Home Assistant was off over midnight and the Switch has a limit per weekday, it's left
    for an adult to check in the Nintendo app (a warning in the log says so). The change goes through Nintendo's cloud and
    reaches the Switch while it's online (how soon hasn't been measured yet).
- What's held is kept across restarts, so only what Hearth held is let go. For a few minutes after Home Assistant
  starts nothing is let go (the sources report in first). A failed call shows on the person's **Held by parental
  controls** sensor and is tried again 5 minutes later. Each change fires `hearth_enforced` (person, by, held, let go).
- `hearth_budget_reached` stays for anything else an automation wants to do.

## Data out

### What a device gets

The answer to each status post carries the person's (or, on a TV, each profile's) **state document**:

```json
{
  "profiles": {
    "user:10": {
      "person": "person.sam",
      "groups": [{"id": "youtube", "name": "YouTube", "minutes_left": 25, "apps": ["com.thesiegs.hearthtube"]}],
      "open_titles": [{"title": "Minecraft", "minutes_left": 140, "apps": ["com.mojang.minecraftpe"]}],
      "pause": {"until": "2026-10-26T19:00:00-05:00", "reason": "Dinner"},
      "request": {"status": "answered", "minutes": 15},
      "message": null
    }
  },
  "version": 42
}
```

`groups` lists only groups with a budget; `minutes_left` null is no limit. `open_titles` are the own-limit titles still
open when their usual groups are used up. A TV that hasn't posted in a while gets it on its next post (at least every
10 minutes, every 2 while playing); `version` lets it skip an unchanged one. This replaces `sensor.hearth_allowance`:
same meaning, from the integration instead of a template.

A **phone** gets its person's part of the same document, in the answer to each post and pushed when it changes (see
[Away from home](#away-from-home)).

**Pop-ups**: `hearth.notify` (target: devices, a person's devices, or the household; `title`, `message`, `duration`,
`position`, `image`, `camera`, up to three `actions`). On a TV it's Hearth's pop-up; on a phone, a notification.
Actions call a Home Assistant service as a user the household chose, not with any device's secret.

**Family pause**: `hearth.pause` (minutes, reason, people or everyone) and `hearth.resume`: the devices show the pause
and stop playing; replaces the hand-made pause helpers and scripts.

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

## Setting it up

All in the household's options (Settings > Devices & services > Hearth > Configure), a menu:

1. **People**: the TV profiles the TVs have reported, each with a person or nobody; gamer accounts likewise.
2. **Screen time sources**: add (a sensor, whose, which device or account, and the Family Link device that is really a
   TV profile), remove.
3. **Titles**: the suggested matches to confirm, and titles to edit.
4. **Groups**: the built-in ones, and groups an adult adds (name, apps and titles).
5. **Rules**: an ordered list; add, edit, move, remove.

Budgets aren't in the options: they're number entities, so a dashboard, a voice assistant or an automation can change
them like any other. The lists (titles, groups, rules) are kept with Home Assistant's storage helper; if editing them
in the options flow proves clumsy, a small panel of the integration's own takes over later.

## Entities

Per Hearth device: as in [Kinds](#kinds).

Per person (a device of its own in Home Assistant, "Hearth: <person>"):

| Entity | Type |
|---|---|
| Screen time today | duration; attributes per source, per device, per group, and stale sources |
| <group> today, for each group with a budget | duration |
| <group> budget, weekday / weekend | number (minutes) |
| <group> minutes left | duration |
| Bonus today, per group | number (minutes) |
| <title> minutes left, for each own-limit title | duration |
| Playing | sensor: the title or app now, and where |
| Playing together today | duration |

Per household: **Playing together** (binary sensor), **Shared budgets** (their minutes left), **Requests** (open
"ask for more" requests).

Events: `hearth_budget_reached` (person, group or title), `hearth_more_time_requested` (person, device, group or
title), `hearth_more_time_answered`, `hearth_playing_together` (title, people, started or ended).

Services: `hearth.add_bonus`, `hearth.set_budget`, `hearth.notify`, `hearth.pause`, `hearth.resume`.

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
Assistant's IP ban. The 200 answer carries the device's state document, `{"ok": true, "state": {...}}` (see
[What a device gets](#what-a-device-gets); for now only `groups` per profile or person, and `version`). A device may
also send `app_categories`, `{"<package>": "game" | "video" | ...}` (Android's category, lower case), which puts its
apps in Video and Games.

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
3. What a household like this one has made by hand, and what takes its place:

   | By hand today | With the integration |
   |---|---|
   | Per-TV status helpers and webhook automations | each TV's device |
   | A YouTube pool (weekday and weekend helpers) and a per-kid "minutes left" template | a YouTube group with a weekday and weekend budget per kid, or a shared budget |
   | Per-kid bonus helpers, reset at midnight | Bonus today |
   | Chores automations that add to the bonus | the same automations, calling `hearth.add_bonus` |
   | Pause helpers and start / end scripts | `hearth.pause`, `hearth.resume` |
   | `sensor.hearth_allowance` | the state document in each status answer |

   Each moves when an adult chooses, checked side by side in history for a few days first.
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
   **Also done, ahead of order:** sources (options: a sensor, whose, live or totals, the same device as a Hearth device
   or another source, the group its unexplained time is in; read from Family Link's `apps` breakdown; minutes, hours or
   seconds), live timing, titles (options), counting once per device, **Playing together** (household binary sensor,
   `hearth_playing_together` started and ended), Playing together today per person; people (options: who each TV
   profile is; whose a phone is, at pairing), per-person
   Screen time today, group times, Playing (Hearth devices), groups (built-in and one's own, apps added to Video or
   Games), budgets (weekday and weekend numbers), Bonus today, Minutes left, `hearth_budget_reached`, `hearth.add_bonus`,
   `hearth.set_budget`, and the state document in each status answer (groups only; no titles, pause or requests yet).
2. **Done:** Hearth TV side: **Pair with Home Assistant** (Settings > Home Assistant), posting status to the
   integration (and no longer to the webhook) with each app's category, and each answer's minutes left as HearthTube's
   allowance (the fewest left in a group holding HearthTube).
3. People: the person mapping; per-person Screen time today and Playing from Hearth's own devices; play sessions.
4. Sources: Family Link, Family Safety, Nintendo, Xbox, Switch presence; counting once; titles; Playing together.
5. Groups, budgets, bonus, minutes left, `hearth_budget_reached`; the state document back to the TVs (replacing
   `sensor.hearth_allowance`).
6. Rules.
7. Ask for more; `hearth.notify`, `hearth.pause`; blueprints for the other services.
8. Approvals through the integration.
9. Hearth Mobile: pairing with a person, the webhook away from home, its state document.
10. The household mailbox.
11. The dashboard endpoint (only if worth it).

## Open questions

- **Family Link's per-device numbers:** a test phone (an emulator) once showed 1.2 minutes in Home Assistant against 2
  hours on the device. Check on a real phone before trusting them in budgets; the per-child total may be the safer
  source until then.
- **Enforcing per title on another service:** Family Safety locks a whole platform, as Nintendo would the whole
  Switch. Holding single Xbox titles (Family Safety's `block_app`) needs each title's Family Safety id in the group.
- **Together on a Switch:** friend presence (unofficial API; login goes through a third-party token server; breaks
  a few times a year) or the parental controls fallback (no third party, delay unmeasured). To test first: can the
  kids' supervised Switch users accept the watcher, how fast presence changes, whether two kids in Minecraft show the
  same game name, and whether Switch Minecraft also shows in the Xbox integration's now playing sensor.
- **Dashboard panel without a person's token:** can the integration serve a chosen user's dashboard config, or does the
  panel keep a non-admin user's token?
- **Video category:** Android's video category misses some apps (a TV's live channels, browsers); the built-in Video
  group may need a starter list.
- **Second household on one Home Assistant:** not planned.
- **Devices on another network segment:** Zeroconf won't cross it; keep the address-typed path.
