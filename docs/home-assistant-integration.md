# Hearth integration for Home Assistant (design draft)

> **Design draft, partly built.** In `custom_components/hearth`: household setup, pairing, a device per Hearth TV or
> phone with its status entities, people, screen time sources (totals and live), titles, counting once, playing
> together, groups, budgets, bonuses, minutes left and the state document (see [Build order](#build-order) and
> [The device's side of the API](#the-devices-side-of-the-api)). Hearth TV pairs and reports to it; Hearth
> Mobile doesn't yet. The rest is
> written so another person or agent can pick it up: what Hearth does with Home Assistant today, what the integration
> should be, and what is still undecided. Read [home-assistant.md](https://github.com/theSiegs/HearthTV/blob/master/docs/home-assistant.md) first (what exists) and
> [household-sync.md](https://github.com/theSiegs/HearthTV/blob/master/docs/household-sync.md) (the mailbox's first user).

## What it's for

One place in Home Assistant where the household's Hearth devices plug in, and where data moves in and out of them
without hand-made helpers, tokens or YAML:

- **Hearth devices.** Hearth TV on a Google TV (one device, several profiles) and Hearth Mobile on a phone or tablet
  (one person's device; the kids' companion app, and later the adult launcher). Each pairs once and gets its own
  secret.
- **Data in.** What each device says it's doing (status, usage, requests such as "ask for 15 more" or an approval),
  and screen time that other integrations already read from other places: Family Link (phones, tablets), Microsoft
  Family Safety (Xbox, Windows), Nintendo Switch Parental Controls.
- **Data out.** What Home Assistant tells the devices: pop-ups, each person's minutes left, a family pause, approval
  answers, and the household sync mailbox.
- **People, not devices.** Screen time, allowances and approvals belong to a household person (Home Assistant's
  `person`), whichever device or service the minutes came from.

**Hearth keeps working without it.** Hearth TV has its own screen-time rules, and the panel's token and pop-ups work
without the integration. TV status and Home Assistant's say in screen time go through the integration only: the older
webhook status and `sensor.hearth_allowance` are retired.

## What it replaces

| Today | How it works | What hurts | With the integration |
|---|---|---|---|
| TV status | the TV posts to a webhook; an automation writes seven helpers per TV | needs an administrator's token to create them; renames break them; one webhook ID per TV to guard | a device per TV with its own entities |
| Dashboard panel | long-lived token of a non-admin user | a hand-made token with that user's full rights | (later) a dashboard endpoint, see [Open questions](#open-questions) |
| Phone approval of a switch | Hearth calls `notify.mobile_app_*` and listens on the WebSocket | the token can call any service; the notify service is picked by hand | built: the integration tells the TV the person's phones (`adult_phones`), asks them and answers the TV ([Phone approval of a switch](#the-devices-side-of-the-api)), so a paired TV needs no token |
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
| Status entities | State, App, Media title / artist / app, Profile, Kids profile, Screen time up, Screen time today, Connected | App, Media title / artist / app, Screen time today, Last interaction, Connected |
| Gets | pop-ups, minutes left per profile, family pause, approval answers, the mailbox | its person's state (minutes left, bedtime, pause), pop-ups, approval answers, the mailbox |
| Sends | status (with usage per profile), approval requests | status, "ask for more", approval requests |

Hearth Mobile is designed in the notes repository (the companion app first, its tests done; the adult launcher later).
Constraint from there: **no Home Assistant token on a kid's device.** The device's own secret, which works on Hearth's
endpoints only, is what this integration gives it.

## Pairing

No token, no webhook ID typed.

1. Home Assistant: Settings > Devices & services > Add integration > Hearth, and a name for the household (once).
2. The device: **Pair with Home Assistant** (on a TV, Settings > Home Assistant). It finds Home Assistant by the
   address it has (typed; finding it by Zeroconf, `_home-assistant._tcp`, isn't built), asks to pair and shows a 6-digit code.
3. Home Assistant shows a discovered **Hearth** device with that name. An administrator checks the codes match and
   confirms. For a `mobile` device the confirm step also asks **whose device** it is (a person).
   - The administrators are told at once: the bell (linking to Hearth's page, where the device waits with its code)
     and a notification on each administrator's companion app, "Alex's Glint (Pixel 9) wants to pair as an adult.
     Code 123 456: approve only if the device shows the same code.", with **Approve** and **Deny** that work from the
     notification (`hearth.pairing_answer`, administrators only). A phone may say who it's for (`person_name`, `role`
     in the pair body): Approve pairs it as the household's person of that name; with none, whose phone it is is
     chosen on Hearth's page (the notification has Deny only). The pair answer lists who is asked (`approvers`).
   - **An adult in Hearth who isn't an administrator** confirms their own phone without one: signed in to Home
     Assistant as themselves, `hearth/pairing` with the code the phone shows pairs it as their own person. Only a
     phone, only as themselves, never one paired for someone else; five wrong codes in ten minutes and they wait. A
     kid, or a user whose person isn't an adult in Hearth, can't.
4. The device gets its own secret, once. That is the only thing of Home Assistant's it keeps. Pairing again gives a
   new secret and ends the old one; deleting the device in Home Assistant ends it at once.

**Once for the household.** A TV of a Hearth household that is paired gets a single-use ticket from Home Assistant for
each TV of its household on the network that isn't paired, and leaves it for that TV in household sync, which pairs
with it at once: no code, no administrator. So pairing one TV pairs them all, and a TV that joins later is paired too.
A TV unpaired on purpose (on the TV, or deleted in Home Assistant) isn't paired again this way. Home Assistant shows a
notification and fires `hearth_device_paired` for each one (see [Tickets](#the-devices-side-of-the-api)). The same
tickets give a parent's phone its own pairing in one tap (TV remote API, Version 2, V2.10b).

**Set up from your phone** stays for the panel's token; the webhook part of it is retired.

## Data in

### Device status

Each device posts its status: when something changes (within about 2 seconds) and as a heartbeat (a paired TV every 2
minutes, a phone as its battery allows). The body is the JSON a TV already posts to its webhook
([home-assistant.md](https://github.com/theSiegs/HearthTV/blob/master/docs/home-assistant.md#tv-status)), so there is no second contract; a phone posts the fields that fit
it (`screen`, `app`, `app_package`, `media_*`, `day`, `seconds_today`, `app_seconds_today`, `playing_seconds_today`).
The integration keeps only known fields, cleaned, and keeps the last status across restarts. **Connected** turns off
after 15 minutes without a post; the device's other entities show unavailable then.

**Where a device is used.** A phone's or tablet's **Last interaction** sensor says when it was last used (a post with
the screen on, or with more time today), whose it is (`person`), and whether its posts came straight over the home
network (`local`: never through Home Assistant Cloud, a proxy, a tunnel or the public URL). A TV fires
`hearth_tv_profile_changed` when someone switches profiles on it (not for its first report after a restart). Both are
a contract for presence readers: [contracts/device-presence.md](contracts/device-presence.md).

**Time from before pairing.** A phone's or tablet's counts start at local midnight, so on the day it pairs its first
post carries time from before Hearth had it. That first post after an adult approves the pairing is kept as the
device's baseline (with the status, across restarts) and taken off every later post that day, per app and in total;
from the next day its counts are its own. Pairing again (a new approval) takes a new baseline. A TV counts its own
profiles and has none. Apps in System screens (below) never count either way.

**Hearth's day, not the device's.** A kid can move a phone's clock, so Hearth judges the day by its own clock. A status
whose `day` isn't Hearth's (the clock moved forward or back) keeps the counts Hearth had: nothing of it counts, the
device's check `hearth_clock` fails ("Its date differs from Home Assistant's", firing `hearth_device_check_failed`;
not within 30 minutes of midnight), and the status answer says `"clock_off": true`. A device that says its offset
from UTC (`utc_offset_minutes`) and whose `day` is its own date there is in another time zone, not a moved clock: no
failed check, and the adults hear once per time zone. Every status answer carries
Hearth's `day`. Within Hearth's day a device's counts never go down: each app's seconds, the total and each TV
profile's are the most it has said today.

**Caps.** A device may say what it can be sent: `"caps": [...]`, at most 16 of `commands.play` (`hearth.play_on_tv`),
`events` (HearthTube's started videos, the Events endpoint), `push` (a ping channel, see [Away from
home](#away-from-home)) and `notices` (attention items in its state document, to come); unknown ones are dropped, so a
newer device may send more. Optional: a device that never sent `caps` gets its kind's, a TV `commands.play` and
`events`, a phone `push`, which is what each could do before. Once sent, a device's caps stay until it sends others
(a post without `caps` keeps them). Caps say only what a device is sent: its **kind** still decides who it is (a TV's
profiles, a phone's one person) and what it may vouch for (only a TV mints tickets).

### A kids profile's YouTube

What a kids profile started in HearthTube comes up, and what a parent blocks here goes down to it (the design is
HearthTube's `docs/parent-channel.md`). Home Assistant is the second place for it: Hearth keeps the log and its own
lists without it (Settings > Family > Kids profiles > the kid).

- **Up**: after each status post, a TV posts the started videos Home Assistant hasn't had to
  `/api/hearth/device/<id>/events` (see [The device's side of the API](#the-devices-side-of-the-api)), only from the
  last day. They're kept per person (a kid on two TVs is one log, the newest 2,000), and each new one fires
  `hearth_video_started` (person, time, video_id, title, channel, channel_id, url, device, parent_approved).
  `parent_approved` is true for a video a parent's PIN let play past the time limit or a lock (the first video opened
  in the PIN's window, played to its end). Hearth also writes a logbook note on the person ("was let play "<title>"
past the limit with a Parent PIN"), and an automation on the event can tell the adults' phones.
- **Read**: the person's **Last video started** sensor (its attributes hold the newest 50 and the blocked lists, kept
  out of history); `hearth.get_watch_log` (person, days, limit) answers the entries and lists; `hearth.watch_digest`
  (person or everyone, days, default 7) answers one document per kid: every entry, counts per channel and per day,
  what was blocked in that time, and a readable `summary`.
- **Weekly digest**: the blueprint `blueprints/automation/hearth/weekly_watch_digest.yaml` sends the summary (to the
  parents' phones, say) and hands the whole document, as JSON, to a reviewer (a conversation agent, say).
- **Down**: `hearth.block_video` (an id or a YouTube link), `hearth.block_channel` (a `UC...` id or a `/channel/` link;
  a handle can't be looked up here), `hearth.block_word` (matched against titles only, as HearthTube's own words are),
  and their `unblock_` twins; optional `label` (videos and channels) for what to show. Each profile's state document carries
  `youtube_blocks` `{"videos", "channels", "words", "labels"}`; the TV takes it with its next status (within 2 minutes)
  and hands HearthTube its own lists and these together. The kid can't undo
  them; they're taken back here only. A TV that leaves Home Assistant forgets these lists (Hearth's own stay).

### Requests and events from a device (later)

Posted to the same device endpoint family, each turned into a Home Assistant event and, where it fits, a
notification to the right person:

- `hearth_approval_requested` (a switch into a PIN-locked profile, the Parent PIN prompt), answered as in
  [Approvals](#approvals).
- `hearth_more_time_requested` (built: see [Ask for more](#ask-for-more)), from Hearth Mobile's "ask for 15 more" or a kids profile on a
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
| Xbox, Windows | [Microsoft Family Safety](https://github.com/noiwid/HAFamilySafety) (HACS) | `sensor.<child>_screen_time` (minutes today, the whole account) and `sensor.<device>_screen_time` per device; per-app minutes from the child's Applications sensor (`applications`: each app's `app_id`, `app_name` and `usage_minutes`), which Hearth reads for the child's Screen Time (or Xbox Screen Time: Xbox apps only) as a source, each app by its Microsoft app id (`x:...` Xbox, `appx:...` or `win32:...` Windows, `a:...` a phone) as groups and pickers name them. A source with an `apps` attribute (Family Link's) uses that instead | polled, 5 minutes by default (30 s to an hour) |
| Nintendo Switch | [Nintendo Switch parental controls](https://www.home-assistant.io/integrations/nintendo_parental_controls) (built in) | Used screen time and Screen time remaining per Switch (minutes; added as a source, its time is games unless chosen otherwise). Whole-console: on a shared Switch, use each player's playing-time sensor as the source instead. Per-app minutes (its usage report service) aren't read yet | polled every 60 s; the Switch must be online; its values aren't marked unavailable when an update fails |
| Nintendo Switch, live | Switch friend presence: HACS [Nintendo-Switch-Presence](https://github.com/itsfatlum/Nintendo-Switch-Presence), fed by a self-hosted [nxapi](https://github.com/samuelthomas2774/nxapi) presence server and a watcher account | what each kid's Switch is playing now | 30-60 s |
| Xbox, live | Home Assistant's Xbox integration | now playing per gamer | about a minute |
| Phones without Hearth's app, live | Home Assistant's companion app (Android): **Last used app** (`sensor.<device>_last_used_app`) and **Interactive** (`binary_sensor.<device>_interactive`), both disabled by default in the app | the app in use while the screen is on; not timed | when the sensor updates |

**A phone's app as now playing** (kids' Family Link phones and tablets, an adult's own phone; anyone, adults
included): in the companion app on that phone, Settings > Companion app > Manage sensors, turn on **Last used app**
and **Interactive** (and, for prompt updates, let the app run in the background). Then add
`sensor.<device>_last_used_app` as a screen time source for its person. Hearth sees the Last used app sensor by its
name and makes it a **phone app** source (`phone_app: true`, live): it's now playing only while the same device's
Interactive sensor is on (another binary sensor can be named as the source's `screen` on Hearth's page), never the
home screen or the system's own screens, and it's **not timed**: Family Link counts a kid's phone, and an adult's
phone isn't counted. It shows in Playing, the household's `playing`, together and the history's `played`. Without the
Interactive sensor it's never playing (the last app stays put after the screen goes off).

How a source is added: in the household's options, **Add a screen time source**: pick a `duration` sensor (or one in
minutes or hours), whose it is (a person), whether it's live (what's playing now) or totals, whether it's the same
device as a Hearth device or another source, and the group its time is in (any but All screen time). Hearth's own devices are sources automatically: a phone counts for its person, a TV's
profile for the person mapped to it ([People](#people)).

How minutes from these are combined, counted once and tied to games: see [Counting](#counting).

## People

The household maps once (see [Setting it up](#setting-it-up)):

- each **TV profile** to a person, or to nobody (a guest or shared profile). See [TV profile keys](#tv-profile-keys);
- each **phone** to its person (asked when it pairs);
- each **screen time source** to its person;
- each **gamer account** (Xbox gamertag, Switch user as friend presence names it) to its person (for now, by adding
  its sensor as a screen time source with its person).

Hearth's TVs can suggest the mapping by name (a profile called like a person), for an adult to check. The integration,
not Hearth, owns this map; Hearth's `profile_id` to name map goes away.

### Adults' own phones

Each person can have a **role** on Hearth's page (the `roles` option): `adult` or `kid`. An adult's own phone (Glint, or
any Hearth client signed in to Home Assistant as their own user) reads the household (`hearth/household`, its
subscription, Glint's `hearth/glint/*`) only when that user is an administrator, or their person (the one whose
`user_id` is that user) is an adult on Hearth's page.

That step is easy to miss, so Hearth asks. When a user is refused one of those reads, and all of this holds, the
administrators get one notice (their phones, and a card on Hearth's page): "Alex (Home Assistant login alex) signed in
from Alex's Pixel. Make them an adult in Hearth? Adults see the kids' time and can give more.", with **Make adult** and
**Not now**. It names the login (its username) and where it signed in from (the name of the token the read came with,
when it has one, else the user's own companion apps), so an administrator can tell a device's login from a person's:

- the user is active, not one Home Assistant made itself, and not an administrator;
- the user has a phone of their own: at least one companion app (`mobile_app`) registered by that user. A login with
  none, such as one shared by wall tablets or TVs, is never offered;
- it isn't a device's login. Not one a Glint Panel signs in with (the user its subscription signed in as, kept with
  the panel, or a tablet saying hello as one; or a token named as a panel's is), and not one a paired TV signs in with
  (a token named as a paired TV, or one a Hearth TV made for another TV, "Hearth household: ..."). Both the user's
  tokens and the token the refused read came with are looked at. A paired phone is its person's own and doesn't count;
- exactly one person has that `user_id`;
- that person has no role yet (a kid, or any choice made on Hearth's page, is never overridden);
- nothing about the person is a kid's: no Family Link, Family Safety or Nintendo account (`enforce`), no screen time
  source, no lock, no budget, schedule or bonus. Anyone with any of these is never offered.

**Make adult** looks at all of the above again first (refused when the user no longer qualifies, for example a panel
signs in as it now, or it has no phone of its own any more), then sets the role as Hearth's page does (the options; the
entry reloads), and the next read succeeds.
**Not now** takes the notice away. Either way, and once asked at all, the person is never asked again: asked, declined
and made are kept in Hearth's store (`hearth.adult_offers.<entry>`) across restarts, and an offer still open after a
restart keeps working. The role can still be set or changed by hand on Hearth's page at any time; an offer settled
that way goes from the phones. A refused read comes on every poll, so each user is looked at only once per Home
Assistant run.

Both buttons run `hearth.adult_offer_answer` (`person`, `answer`: `adult` or `not_now`), which only an administrator
may call: an adult who isn't one, an automation or anyone else is refused, since only an administrator may make
someone an adult. It checks again that the person still qualifies. Each offer fires `hearth_adult_offered`
(`person`).

### TV profile keys

A TV names a profile by its own key, `profile_id` (`user:10`, or `user:0:sam` for another account in an adults' user).
The number is the profile's Android user serial **on that TV**: the same Google TV profile is `user:10` on one TV and
`user:12` on another. So the options (`profiles`) never map a bare `user:10`. They map:

1. a **household ref**, `name:<slug>` (`name:sam-lee`): the profile's name as Google TV's chooser shows it, the same on
   every TV, in lower case with words joined by `-`. Each TV reports it beside every key (`profile_ref`, the
   `profile_ref` of each `usage_today` entry, and the `profiles` table). One choice covers the profile on every TV.
2. or **one TV's key**, `<device_id>/user:10`: for a TV whose Hearth TV is older than 2026.11.07 (it reports no refs),
   or a profile whose name that TV hasn't learned yet.

A TV profile resolves by its ref first, then by its TV key; a TV's `user:0` also matches the one mapped account of the
same user on that TV (`user:0:sam`). Everything that names a profile (status, the state document's `profiles`,
`youtube_blocks` and parent PINs' `profiles`, `video_started` events, an ask) uses the TV's own key on the wire; the
integration resolves it with the device it came from. A profile renamed in Google TV gets a new ref, and needs picking
again.

**Migration.** Options from before 2026.11.07 map bare keys (`user:10`). Which TV each was picked from is unknown, and
on a household with several TVs it was wrong on the others (one kid got another's limits). They match nothing now:
the integration raises a repair issue ("Pick the kids' TV profiles again") listing them, until an adult picks again on
Hearth's page (Devices > TV profiles, listed by name with the TVs that have them) or in Configure > Who's who on the
TVs, which drops the old entries when saved.

## Counting

### Play sessions

Where a source says what's playing **now** (Hearth TVs and phones, Xbox now playing, Switch friend presence, a kid's
Switch's playing sensors, a phone app source), the integration looks at least once a minute and whenever the sensor
changes. A live source's time accrues between two
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
zero: a drop is a new day for that source. A source that stops changing keeps its last
count (showing it as stale in the breakdown isn't built yet), and so does its last number today while its sensor has none (unavailable). A person's Screen time
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
| Windows | by app, from a list (Steam, Epic, Battle.net, Minecraft Launcher and the like, editable; not built yet) | the playing title where a source has it (Xbox now playing covers Xbox-signed-in PC games); otherwise the launcher's time | partly |
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

What counts as playing now, for Playing, `playing` and together:

- **Hearth devices**: a TV's app in front for its current profile's person, a phone's for its person. When the TV
  has a media player in the options (`media_players`, TV device id to `media_player`) that's playing or paused, its
  `media_series_title` (else `media_title`) is the person's `title` and `media_title` the `episode`, and together
  matches on the show rather than the app. Not timed here (the devices' own counts are).
- **Live sources** (Xbox now playing, Switch friend presence): timed by the integration.
- **A kid's Switch**: a Nintendo enforcer's `playing` entities (a shared Switch's player sensors; else the Switch's own
  Playing sensor when no one else's enforcer is on it), or their player's minutes growing (see **A shared Switch**
  under Enforce). While one is on, the person plays the game it names (a
  `title`, `game` or `application_name` attribute, as a patched integration or presence gives it), else "Switch", on
  the Switch's target (`nintendo:<entity>`). Not timed (Nintendo's own minutes count); counted for together. A live
  source on the same Switch says it instead.
- **Phone app sources**: above, in [Screen time from other integrations](#screen-time-from-other-integrations).

Each such play is also logged when it ends, in the history's `played` (see [History](#history)).

## Limits

### Groups

A budget is set on a **group**: a set of apps and titles whose minutes count together. Built in:

- **All screen time**: everything not excluded by a rule.
- **Games**: games (Android's game category, plus any an adult adds).
- **Social** and **Messaging**: social and messaging apps (a starter list, plus any an adult adds; Social also takes
  Android's category). Messaging counts toward daily time and is paused like any app (daily time or its limit used
  up, bedtime, Pause screens); an adult may take it out of daily time (Not screen time, below). Before the time
  model it was outside daily time by default: on the first start after the upgrade, `messaging` leaves the
  stored Not screen time list once (option `messaging_counted`), whether an adult put it there or the page saved the
  old default (the two can't be told apart); put it back there if you meant it.
- **Accessibility**: apps a kid may rely on (Voice Access, Lookout, Live Transcribe, Sound Amplifier, TalkBack: a
  starter list, plus `accessibility` from Hearth's categories starter list or an adult, and any an adult moves
  there). Not screen time
  unless an adult puts it in, and **never paused**: not All screen time (or any group) running out, an adult's pause
  of the app or a group, School time's apps, nor the weekly schedule. Family Link and Family Safety are never asked to
  pause them, and the state document lists them in All screen time's `except` and in the person's `never_held`, for
  a device that can spare them from a lock too. It has no budget or bonus (no number entities, no minutes left).
  Family Link's own whole-device lock (All screen time out of time) is Google's: it spares only the apps a parent gave
  unlimited time in Family Link.
- **System screens** (`interface`): what's in front when no app is: Android's own screens (`android`, System UI, the
  permission and package installers), Family Link's lock and downtime screen (`com.google.android.gms.supervision`),
  the stock launchers (Pixel, Samsung, AOSP, Google TV and Android TV, and other phone makers'), setup wizards and the
  common keyboards. **Counted nowhere**: its seconds are taken out of a device's reading before anything is counted,
  so they're in no group and not in All screen time (an adult can't put it in), and a phone or tablet that sends its
  own per-app seconds gets its total from the apps kept. **Never paused**, like Accessibility, and no budget or bonus.
  Stricter than the loosening pools below: only Hearth's list, an adult's move or list, or `interface` from an
  adult's answer of what the app is or Hearth's categories starter list (App categories, below) puts an app there.
  Never a store's genre or an AI, any other value, an adult's map of a whole kind of app, nor a device's own
  category; an adult's move or list wins over everything.
  Settings and Files are not System screens: time in them still counts. A client that says its home screen
  (the launcher it shows) was in front all night thus never empties a kid's All screen time.

**Only a confirmed answer puts an app in Messaging or Accessibility.** Accessibility is never paused, and Messaging
is kept for real messaging apps (it counts and is paused like any category, but a household may give it its own limit,
take it out of daily time, or allow it for a while), so a guess never puts an app in them: only an adult's move or list, Hearth's starter
lists, or an answer of what the app is from an adult or Hearth's categories starter list does. A device's own
category (any app may declare one in its manifest, so a misfiled game would escape limits), a store's genre and an
AI's answer pass over them: an app a store or an AI calls messaging or accessibility counts in Other and shows in
Check these, unless a starter list or an adult already puts it somewhere (Snapchat is on Social's starter list,
Discord on Messaging's).

An adult can add groups (pools): **YouTube** (YouTube and HearthTube, on every device) and **Streaming** (the
streaming apps), say. **An app is in one pool at most**, besides All screen time, so the pools' minutes and "other"
(apps in no pool) add up to All screen time's. Where it goes is the first of these that answers:

1. where an adult moved it (Hearth's page, Sort new apps; "Right" in Check these is a move to where it is);
2. a pool whose list an adult put it in;
3. Hearth's curated starter lists;
4. a **confirmed** answer of what the app is (App categories, below: an adult's, the starter list's, a store's sure
   genre), by the household's map; a confirmed value the map sends to no pool (a companion app, say) is Other, and
   nothing further down moves it;
5. the device's own category (Android's, from a Hearth device; a device's `catalog_categories` is no longer read
   since contract 3);
6. an **unconfirmed** answer (a store's loose genre, an AI's guess), only when it goes to a pool: a guess never takes
   an app out of one; neither 5 nor 6 ever puts an app in Messaging or Accessibility (above);
7. where its time came from (a Switch's or an Xbox's titles are games);
8. Other.

Settings keep it so:
an app put in one pool's list (the options flow, Hearth's page, sorting a new app) leaves every other list. A
YouTube minute is taken from YouTube and All screen time. A device's time is up when **any** group it's playing from
is used up.

The built-in **Video** pool is retired: it held YouTube and the streaming apps alike, so their minutes counted twice.
On its first start after the update Hearth moves an older household's settings once (`pools: 2` in the options) and
logs what it did. If anyone had a Video budget, or an adult had moved an app to Video, Video stays as a pool of the
household's own with the same id (`video`) and name, so its budgets, bonuses, entities, pauses and history carry on:
it holds the old starter list and the apps an adult added, less any app another pool lists, and the apps Android
marks as video (its `category`, kept when Hearth's page saves the pools). Remove it in the settings once YouTube and
streaming have pools of their own. Otherwise Video goes, with the apps added to it; those count in All screen time
only until put in a pool (the log names them). Configure > Add apps to Games replaces Add apps to Video or Games.

#### App categories

What an app **is** (one of ten categories: game, video, audio, image, social, messaging, news, maps, productivity,
accessibility, or `interface` for System screens; and a finer `detail`: youtube, streaming, education, companion,
system) is Hearth's own knowledge (categories.py); the household says which pool that goes to. It replaces the shared
App Facts catalog, which is retired ([contracts/app-facts.md](contracts/app-facts.md)): Hearth fetches nothing and
sends nothing upward. For any app it sees, the answer is the first of:

1. **An adult's answer** (Hearth's page > Apps > Every app, the "what it is" choice; `app_categories` in the options,
   key -> `{category, detail?}`, category `null` meaning none of Hearth's kinds). It wins over everything below, may
   say Messaging, Accessibility or System screens, and is the latest thing an adult did: saying what an app is takes
   back a move or a pool list of it, so what it is decides its pool ("Hearth decides" takes the answer back). A move
   or list made after it wins as before.
2. **The starter list** shipped with the integration (`categories_data/starter.json`, `hearth.starter/1`): every
   confirmed answer of the retired catalog (Android packages and the console and PC keys), its hand overrides
   (an override that said "none of the ten", a browser or an airline, stays an explicit none, so no store
   second-guesses it), the System screens set, and Hearth's additions (parental-control apps as `system`, big
   games). `tool/categories_starter.py --catalog <app-facts checkout>` regenerates it.
3. **A store's genre**, looked up when a kid first uses an app that 1 and 2 don't cover (an adult's move or list, or
   Hearth's own pool lists, cover it too), kept with its date:
   - Google Play (`android:<package>`): the app page's schema.org `applicationCategory`;
   - Microsoft Store (`msstore:<id>`, `xbox:<title id>`, `pfn:<package family>`): the public displaycatalog
     product's kind and category;
   - Steam (`steam:<appid>`): appdetails' type and genres;
   - Switch titles aren't looked up: every one is a game by the platform rule.
   Only the old catalog classifier's sure mappings confirm a category: every Play `GAME_*` genre and Social, Dating,
   Video players, Music and audio, News, Maps, Photography, Art and design, Productivity, Tools and Business; a
   Microsoft Store or Steam game. Communication is messaging only for a clear messenger and never confirmed (it holds
   browsers and hearing tools too); an application's store category and Steam software are unconfirmed; Entertainment,
   Lifestyle, Education, Travel, Comics, Parenting and an unmapped store category are **unclear**; anything else
   (Shopping, Finance) is none of the ten. A store never confirms a detail or a loose category.
4. **An AI answer**, by default from **Home Assistant's default AI Task** (Settings > AI Task, its default for
   generating data, read at each question, so a change there counts at once); an HA administrator can choose a
   specific AI Task entity instead, or Off. With the default and none set in Home Assistant, nothing is asked. Only
   for an app whose store genre is unclear or that its store doesn't have (or, with store lookups off, has no other
   answer), at most 20 a day. Hearth calls `ai_task.generate_data` with structured output (a category from
   the ten or unknown, and a detail or none), giving the app's name, its store id and the store's one-line
   description, nothing else. The answer is **never confirmed**: it places an app only in a pool that doesn't loosen
   a limit, never in Messaging, Accessibility or System screens, and shows in Check these. It's kept; an AI that
   couldn't answer is asked again a day later, and a new store answer replaces an old AI one.
5. Unknown: the device's own category and where its time came from answer instead (above).

- **What leaves the house.** A store lookup sends one public store id to that store (Google Play, Microsoft's
  displaycatalog, Steam), with a fixed language and market, a generic user agent and no cookies kept; nothing about
  the household, the kid or the device. An adult's apps aren't looked up. An AI question goes to the model behind
  Home Assistant's default AI Task (or the AI Task entity an adult chose instead; none when it's Off): a local model
  such as Ollama keeps it in the house, a cloud one gets the app's name, store id and store description.
  Nothing else is sent anywhere.
- **How often.** One lookup at a time, every 30 seconds while apps wait, at most 100 store lookups and 20 AI
  questions a day. A store's answer is looked at again after 90 days, an app the store doesn't have after 30, a
  lookup that failed (offline, an odd answer) the next day. Answers are kept in Home Assistant's storage
  (`hearth.categories.<entry>`); a new answer places apps again at once.
- **Settings** (Hearth's page > Apps > App categories, or Configure > App categories): `category_lookup` (store
  lookups, on by default) and `category_ai_task`: `default` (Home Assistant's default AI Task; what an install
  with no value uses), `off`, or an `ai_task.*` entity. Both places show which entity the AI guesses use now, or that
  Home Assistant has no default AI Task.
- **The household's map** (Hearth's page > Apps > App categories > Which group each kind of app goes to;
  `catalog_pools`, value -> pool or `other`, a name kept from the catalog's days): by default a game goes to Games,
  social to Social, messaging to Messaging and accessibility to Accessibility (those two on a confirmed answer only),
  a value a pool claims by its category (the kept Video pool) to it, YouTube to a pool of the household's called
  YouTube, streaming to one called Streaming, TV or Shows, audio to Music, education to Homework or School (else
  Other), and companion and system apps to Other, never Games.
- **Every app** (Hearth's page > Apps) shows each app's kind and where it came from (set by you, Hearth's list,
  store with its genre, AI guess, not known, or "looking it up"), filters to AI guesses or apps not known yet, and
  offers both choices: what it is, and its group. App categories counts the apps by where their answer came from.
- **Check these** (Hearth's page > Apps): apps placed on an unconfirmed answer (an AI's guess, a store's loose
  genre), then apps where a confirmed answer (not an adult's) and the device disagree on whether it's a game (Hearth
  goes by the answer). **Right** keeps one where it is; moving it is an adult's move. Either way it leaves the list,
  and a later answer never moves it: Every app shows "Hearth now knows it as X" instead.

**The retired catalog's settings.** On its first start after the update Hearth removes `catalog_fetch`,
`catalog_share`, `catalog_share_asked`, `catalog_url` and `catalog_relay` and the kept catalog copy
(`hearth.catalog.<entry>`), once. Each correction an adult had queued to share becomes their answer of what the app
is (an answer already there wins), and fetching turned off becomes store lookups off. `catalog_pools` stays.

**Not screen time** (Configure > Not screen time): a group whose minutes don't count toward All screen time, music
say. Its minutes still count in the group itself (and its own budget, if it has one, still applies), but not in All
screen time, and its apps stay usable when All screen time runs out: Family Link's lock spares them only if a parent
gave them unlimited time there, and Hearth TV is told them (the All group's `except` list). The person's Screen
time today sensor lists each group's packages (`groups_apps`) and these groups (`not_screen_time`).

### Budgets

Per person, number entities an adult (or an automation) sets:

- **Daily time** on school days and on other days (group `all`; "Daily time on school days"), as Configure > School
  days says; -1 is no daily time.
- Per category, a **limit** on school days and on other days ("Games limit on school days"; -1 is no limit).
- **Bonus time today** (daily time's; back to 0 at midnight) and, per category, **limit raised today** (what a raised
  limit adds; back to 0 at midnight). Their entity ids are as an older Hearth named them
  (`number.hearth_<person>_all_screen_time_bonus_today`, `number.hearth_<person>_games_budget_on_school_days`).

From them, per person: **Daily time left** (`sensor.hearth_<person>_all_screen_time_minutes_left`), each category's
**Minutes left** (what can actually be used: never more than daily time left), **Bonus time left**
(`sensor.hearth_<person>_bonus_time_left`), and the event `hearth_budget_reached` (person, group, group_name) when one
reaches 0, and again after bonus time or a raised limit reopened it. How they're worked out is
[Today's time](#todays-time).

### Today's time

One **daily time** per kid; **categories** may have a **limit** inside it ("Games: 2 h limit"). A limit never gives
time: it only stops one category from taking the whole day. The categories' limits may add up to more than daily time
(Games 2 h + YouTube 1 h + Streaming 1 h 30 against 3 h of daily time is normal: they're ceilings, not shares).

Three ways to give more (services, adults only, as every Hearth service: [Security](#security)):

- **Bonus time**: `hearth.add_time` {`person` or `people`, `minutes` 1-1440, `reason`}; `hearth.remove_time` {`person`
  or `people`, `minutes`} takes back what an adult gave today (never more). It has **no category**: N minutes added to
  daily time, which the kid may spend anywhere. Minutes past any category's limit come out of the same N, so one bonus
  is shared by every category. Chores' minutes, approved asks, the schedule's day-off and half-day minutes and an
  adult's gift are all bonus time. It ends at midnight. Each grant also adds a Family Link bonus (and Family Safety
  extra time) where the device's own limit would stop the kid sooner (`native_sync.mirror_bonus`), so a phone never
  locks early: Hearth's holds stay the real limit. Given during bedtime, it lifts bedtime while it lasts
  ([Extra time at bedtime](#extra-time-at-bedtime)).
- **A category's bonus**: `hearth.add_time` with `category` ("+15 min Messaging bonus"; `hearth.remove_time` with
  the same `category` takes it back, never below 0). Minutes usable only in that category, past daily time and its
  limit: its minutes past daily time or past its limit are paid from its own bonus first, then from the general one.
  While it lasts, daily time's hold leaves that category's apps out (Family Link pauses the other apps instead of
  locking the device), and Family Link's backstop counts it. Bedtime, School time and Pause screens still apply. It
  ends at midnight. Kids see "Messaging: 15 min bonus left" (`time.category_bonuses`). "Give Sam 15 more minutes of
  messaging" is this; "15 more minutes" with no category is the general bonus. As accurate as Family Link's per-app
  minutes, which arrive a few minutes late. A bonus for one app isn't built.
- **Raise limit**: `hearth.raise_cap` {`person` or `people`, `category`, one of `minutes` (raise by, -1440..1440),
  `to` (the limit today) or `no_cap: true` (no limit today), `until` (a time, `end_of_day` by default)};
  `hearth.raise_cap_end` {`person` or `people`, `category` (every raised one when left out)}. Daily time is unchanged.
- **Unlimited**: see [Unlimited](#unlimited).

**The accounting** (time_model.py; worked examples in `ha_tests/test_time_model.py`):

    a category's own bonus pays first: its minutes past its limit, or past daily time (those go to categories with
      a bonus first, in the kid's favour), up to its bonus; paid minutes don't count in daily time or its limit
    bonus_used = max(0, minutes still over daily time, sum over categories of minutes still over each limit)
    bonus_left = max(0, N - bonus_used)
    daily time left = max(0, daily time + N - used today)
    a category is held when max(0, limit - used in it) + bonus_left is 0
    a category's minutes left (shown) = min(that, daily time left)

Minutes past a limit are also minutes of the day, which is why bonus_used is a max, not a sum. Example: daily time 3 h,
Games 2 h, +30 bonus. After 2 h 30 of games the bonus is used, Games is held ("Games are done for today · 1 h left for
other things") and the kid has 1 h for anything else. Minutes past a limit before any bonus was given (counting runs a
little behind) are paid from the next bonus. A negative bonus (an adult taking time away) lowers daily time instead.

**Grants.** Each bonus, raised limit and Unlimited is a grant of its own (limits.py `add_grant`), linked to its origin; the effective numbers come from the active grants (bonuses add up; raises "by" add up, a "to" or no limit is a floor and the highest wins; Unlimited lasts to the latest end). `hearth.end_grant` {`origin_id`} ends exactly one: a bonus's unused part (spent minutes go to the oldest grants first), one raise, one Unlimited grant, a chore's reward or Pause screens. `raise_cap_end` and `unlimited_end` end all. Today's state became one grant each on the upgrade. See [docs/contracts/time-model.md](contracts/time-model.md).

**Older services and entities, kept for one release** (see [docs/contracts/time-model.md](contracts/time-model.md)):
`hearth.add_bonus` without a group (or with `all`) is bonus time; with a category's `group` it raises that category's
limit by the minutes (negative lowers it). `hearth.remove_bonus` likewise. A category's "limit raised today" number is
the older per-category bonus. **Migration:** on the first start after the upgrade, today's stored per-category bonuses
become raised limits by as many minutes (once; the stored data carries a version). Daily time's bonus stays bonus time,
so nothing is counted twice.

**Words** (one place each: strings.json, the panel's string table, the TV's app_en.arb; the contract lists the kids'):
"Daily time", a category's "limit" ("2 h limit", "no limit", "Games limit today: 3 h (raised)"), "bonus" ("30 min bonus
left", "+20 min bonus earned", "Ask for bonus time"), "Unlimited", and "Pause screens" for the family pause. Never pool,
bucket, budget or max to a person, and "adult", never "grown-up".

**Where it came from (origin).** Each bonus, raised limit, Unlimited window and Pause screens records `{kind, source
(hearth, chore, ask; family_link, family_safety and nintendo are coming), by (the adult's name when known), at,
detail}`, shown on a status line's "?" ("Bonus +30 · added by Alex in Hearth · 3:05 PM"): in the state document's
`time.origins`, `hearth.explain` and `hearth/config`.

### Unlimited

`hearth.unlimited` {`person` or `people`, `until` (a time, `end_of_day` by default, or `turned_off`: until an adult
ends it), `include_bedtime`, `reason`}; `hearth.unlimited_end` {`person` or `people` (everyone's when left out)}.
It's always over at midnight.

While it lasts nothing Hearth holds for daily time or a category's limit holds the kid (it's an allow of daily time:
[Exceptions](#exceptions)), and **the minutes used aren't counted**: daily time, every limit and bonus time pick up
exactly where they were when it started ("Limits back on · 1 h 10 min left today"). Bedtime, School time and Pause
screens still lock the kid; with `include_bedtime`, bedtime is lifted for the window too (Family Link's bedtime moved,
[Extra time at bedtime](#extra-time-at-bedtime)).

**How the minutes are left out** (unlimited.py): an exclusion window per person and group. At its start Hearth notes
the minutes counted so far in each group; while it lasts, and for 10 minutes after it ends, whatever is counted above
that is left out of today's minutes. This works the same for a live source (a TV, a title Hearth times) and a
total-only one (Family Link's and Family Safety's daily totals, which only give a day's sum): the window's minutes are
the total's growth between the two notes. Totals arrive a few minutes late, so the end note is taken after the 10-minute
settle, and what is counted in the settle goes to the kid. Approximation: a minute a total reports late from just
before the window (or one played during the settle) is left out too; never one the other way. A total can report
later than the settle (Family Link lags up to about 40 minutes): after it, no source can have gained more than the
time since, so what one gains beyond that is the window's too and is left out (per source, never less than before;
only the day's last window looks). Unlimited started again while the last window is still settling opens that window
again, so no minute is left out twice. Each window is
recorded in the history (`unlimited`: start, end, minutes not counted; "Unlimited 2:00–5:10 PM · 3 h 10 min not
counted") and fires `hearth_unlimited_started` {person, until, open} and `hearth_unlimited_ended` {person, id, text}.

While it lasts Family Link's backstop is a whole day ([Family Link backstop](#family-link-backstop)), and back after.

### Rules

Not built yet. Budgets apply to everything in their groups unless a **rule** says otherwise. A rule names a title or an app, who it's
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
minutes, group: All screen time by default; by title isn't built), whoever asks:

- **Ask for more.** A kid asks from a Hearth device (Hearth Mobile's "ask for 15 more", or a TV's time's-up screen).
  The integration fires `hearth_more_time_requested` and sends the phone chosen in Configure > Watch for new apps an
  actionable notification: the amount asked, the next one up, **Not now** (see [Ask for more](#ask-for-more)). The
  first answer adds the bonus (or not) and is shown on the kid's device. One open request per person; it's open 30
  minutes.
- **Suggest to phones** (the Kids tab of Hearth's page, or Configure > Suggest more time to phones): when one of a
  kid's chosen groups runs out, its suggestion goes to the adults' phones ("Sam's YouTube ran out. Give 30 more
  minutes today?", with two amounts and Not today); see [Pushed to phones](#pushed-to-phones). Nothing is asked of the
  kid and their devices aren't told about it. (This was Offer more time, which made an offered request: its choices
  carry over.)
- **Chores**: a reward on an item of a kid's to-do list, granted when it's checked off (see
  [To-do lists](#to-do-lists)). Chore minutes aren't added to the bonus: they're counted with it.
- **Automations, a dashboard button**: call `hearth.add_bonus`.

Negative minutes take time away today (`minutes: -60`), even with no bonus given: Bonus today goes below 0 and the
minutes left stop at none. It ends at midnight like any bonus.

### To-do lists

Every person marked kid on Hearth's page has a to-do list, `todo.hearth_<kid>` ("Sam's to-do"): the to-do card on a
tablet, Assist's list intents ("mark feed the cat done on Sam's to-do") and `todo.item_completed` triggers. Adults set
the list up in the Kids tab of Hearth's page (Chores): a task's name, how it repeats (once, every day, some weekdays,
every N days, N days after it was last done), a time it's due, and optionally a reward: minutes in one of the kid's
groups ("+15 min Games") or money ("+$2.00"). The list shows today's items of each task, one-off tasks until they're
done, and what was done today until the day ends.

- **No approval step.** A reward is granted when the item is checked off by the kid themselves (their own Home
  Assistant user) or by an adult. The adults' phones are told ("Sam finished a chore: Feed the cat: +15 min of Games
  today"), with **Undo**, which takes the whole reward back (the group can drop to none left, and holds then).
  `hearth_chore_done` (person, chore, group, minutes or cents, key, by) fires on each grant, `hearth_chore_reversed`
  on each take-back.
- **Who may do what.** A sibling's user is refused on another kid's list. Any other user (a wall tablet signed in as a
  household user with no person), voice and automations may check an item off, but nothing is granted; an adult can
  give it from Hearth's page. Sign shared screens in as such a user, not an adult's: an adult's check-off grants. A
  kid may add items of their own (homework: never rewarded) and change or remove those; on an adult's item they may
  only tick and untick. Removing a done item (Clear checked items) only hides it: its reward stays.
- **Untick** by the kid or an adult takes the reward back; a tick again grants it again, never twice. Each grant is a
  ledger entry keyed `<item uid>#<n>`.
- **Minutes** count today, in the day the item was checked off, as Bonus today does: the summary's group `bonus`
  includes them and `bonus_chores` says how much. All screen time minutes also reach Family Link and Family Safety as
  `hearth.add_bonus`'s do, and the history has them as a bonus `via: chore`. An optional cap per group
  (`chore_caps`, the most chores earn a kid in a day) limits them; a grant past it gives what's left.
- **Money** is a balance per kid (`balance_cents` in the summary): what was earned, less what an adult marked paid
  out, plus adjustments. Hearth moves no money.
- The old Configure > Chores earn time is gone: its lists' open items became one-off tasks with their rewards (a
  "+N" in the text, else the row's minutes), once. The old to-do list is left as it was.

**Who enforces.** When one of a person's groups is out of time, its apps are held everywhere the household chose,
until the group has time again (a bonus, a higher budget, a new day):

- **Hearth devices** get the person's minutes left per group, with the group's apps, in their state document (below),
  and stop those apps themselves (HearthTube holds YouTube on its own). On a TV, in a kids profile, a held app doesn't
  open from Hearth's tiles, Continue Watching or remote buttons ("Time's up for Games today. An adult can add more
  time."); opened another way (Google TV's kids home, a voice search, a link), Hearth TV's home comes back over it.
  YouTube's own app is the exception: kids watch YouTube in HearthTube, so it's swapped for HearthTube, which holds
  the YouTube time itself. All
  screen time out of time holds every app. Never held: Hearth, HearthTube, Settings, the Play Store, the assistant and
  Google TV's own screens (chooser, PIN, time up). Adult profiles have no limits, and without today's answer from Home
  Assistant nothing is held.
- **Other parental controls**, per person (Configure > Enforce):
  - **Family Link** pauses the group's Android apps (`familylink.pause_app`: a 1 minute daily limit, the app stays
    installed) and resumes them (`resume_app` puts back the setting they had). Google TV ignores Family Link's app
    limits, which is why a TV is held by Hearth. All screen time out of time **locks** the child's devices instead:
    today's daily limit goes to 0 (`familylink.set_daily_limit`, every device of the child), so the apps a parent gave
    unlimited time in Family Link still work, as when Family Link's own limit is reached. The limit they had (the
    child's weekday limit entity) is kept and put back when there's time again, and just before midnight, since it's
    the weekday's setting. With the child's Daily Limit switch off (Family Link then locks nothing), Hearth switches
    it on for the lock and off again when it puts the limit back. An app with unlimited time is never paused for a group either. Calls, texts, the system and
    the parental controls' own apps are never paused for a group. Only apps the child has are paused (for a group, a
    pause or School time): the child's four Family Link app lists (Blocked apps, Apps with time limits, Apps without
    limits, Always allowed apps) together are every app on their devices; while one is missing or cut short
    (`truncated`), every app of the group is paused as before.

    **During School time, pause these apps** (Google Messages by default in the form): those apps are paused while
    the child's Family Link School time is on (any of their devices' School time sensors), and resumed when it ends,
    through the same hold. That matters: Family Link keeps one saved setting per child and app, `pause_app` saves only
    the first, and any `resume_app` puts it back, so two owners (a budget hold and a School-time pause) would undo each
    other. Hearth is the one owner, holding by person, and resumes an app only when no reason to hold it is left. The
    School-time apps are the adult's own choice, so they may include Messages and apps with unlimited time; never
    Hearth's own or Family Link's.
  - **Microsoft Family Safety** locks the chosen platforms (Xbox by default) until midnight while one of the chosen
    groups (Games and All screen time by default) is out of time (`lock_platform`), and unlocks them when none is.
    The child is named by the chosen entity (`entity_id`: any of the child's Family Safety entities, or a typed-in
    account id as `account_id`), and the lock runs `until` the next local midnight. A Family Safety that takes
    neither (the released one, upstream's 2.3.0) gets the account sensor's `user_id` and `duration_hours`: whole hours,
    so the lock would run up to an hour past midnight. Hearth then unlocks it itself at midnight (`unlock_platform`;
    the time is kept with what's held, checked every minute, so a midnight missed while Home Assistant was off is
    caught up at the first check after the start), only while the lock still reads Hearth's (see below): a parent's
    change since (their own lock, an unlock, extra time) drops the plan and stays. A lock that's gone, unreadable or
    under Hearth's own extra time at midnight is waited for, in case it comes back, until its own end, then dropped.
    Letting go, or a Family Safety that takes `until`, needs none of this. On 2.3.0 `unlock_platform` cancels any
    platform lock in force; from the release with its #94 it puts back the lock or extra time it replaced. An unlock
    answered with `hold_expired`, `left_parent_override` (a parent's own lock stays) or `not_locked` is fine: nothing
    of Hearth's is left. **Xbox and Windows apps in a group:** a group may list Family Safety's app ids (`x:...` Xbox, `appx:...` or
    `win32:...` Windows; the app pickers offer those of the kids with Family Safety, from its sensors' `apps`). While
    any group with such apps is out of time, those on the chosen platforms are paused (`pause_app`, a block that keeps
    whether the app was blocked before; an app a parent blocked is left alone) and resumed (`resume_app`) when it has
    time again; an app whose whole platform is locked isn't paused as well. Family Link never gets them. An older
    Family Safety without `pause_app` holds platforms only.
  - **Nintendo** (the built-in [Nintendo Switch parental controls](https://www.home-assistant.io/integrations/nintendo_parental_controls)
    integration; the person's Switch is chosen by its **Max screentime today** number): while one of the chosen groups
    (Games and All screen time by default) is out of time, Max screentime today is set to 0 with **Suspend software**
    on, so the game is suspended (as with Nintendo's own limit, a game may close without saving). The limit and Suspend
    software it had are kept with what's held and put back when none is out of time. That limit is a setting of the
    Switch's (of every day, or of this weekday when it has a limit per weekday), not of today only, so it's put back 2
    minutes before midnight; if Home Assistant was off over midnight and the Switch has a limit per weekday, that
    weekday's limit and bedtime are put back through `nintendo_parental_controls.update_daily_restrictions`. While bonus
    time from the Nintendo app runs (its time-extended sensor), the Switch refuses a new limit: Hearth waits and says so.
    The change goes through Nintendo's cloud and reaches the Switch while it's online.

    Nintendo's limits are the whole console's: there's no limit per child. See **A shared Switch** below for
    holding one kid on a Switch the family shares. Two kids held on one Switch share the hold: it's put back only when
    neither is.

    An adult's **pause** holds the Switch the same way, through the same hold: a family pause of the person
    (`hearth.pause` without an app or group), or a pause of a group the enforcer covers (`group: games` with the
    defaults; a pause of Video doesn't touch it). It's let go when the pause ends (or 2 minutes before midnight, as
    above), and on a shared Switch it's held once the person is caught playing, as for a budget. A parent's grant in the
    Nintendo app (a changed limit, bonus time) lifts it as it lifts a budget's hold; an allow doesn't, as for any pause.

    **A shared Switch.** One kid out of time can only be held by holding the whole Switch, so on a Switch the family
    shares (an enforcer row with a `player` or `playing` entity) Hearth waits until that kid is **caught** playing it,
    then holds it **until the kid may play again**: extra time (on all their devices or on this Switch), a new day's
    budget, the pause or the schedule's mode ending, a bedtime lift on this Switch, a parent's grant in the Nintendo
    app, or 2 minutes before midnight. Whatever would hold the Switch were the kid playing (a budget, a pause, Sleep,
    School, a closed group) waits for the catch the same way. Before, the hold followed the kid's playing sensor, which
    goes off because the hold stops the game; the kid then played on until the next upload showed it.

    **Who is playing.** Set the person's player on the Switch (the enforcer's `player`: their **"<nickname> used screen
    time"** sensor). Hearth's page and the Configure menu pick it by name on a Switch with several players (the one
    whose nickname is the person's name, or has their first name as a word); pick another or **Hold the whole Switch**.
    - Nintendo takes the minutes from the console about every 10 minutes, in steps of 5 to 10 minutes, and every
      player's in the same upload; the first growth of a session shows about 10 minutes after play starts. A player
      whose minutes grew within the last **15 minutes** is playing (an enforcer row may set `window`, 5 to 60), unless
      **someone else since**: another player's minutes or the console's own grew at a later upload (more than 2
      minutes later) without theirs, so they stopped and someone else (an adult, a brother or sister, a guest, or no
      user at all) took over. Two players growing in one upload (playing together) are both playing.
    - A player is **not playing** once their minutes have been read, fresh, for a whole window without growing, or
      someone else's grew since. Anything else is **unknown**: the sensor is unavailable, unknown or hasn't been read
      for 10 minutes, or Hearth hasn't watched it for a window yet (after a restart, or after a gap longer than a
      window; growth during a gap that long isn't taken as play now).
    - A patched Nintendo integration's per-player playing sensor (`<switch>_<player>_playing`) is the same minutes
      growing (on for 10 minutes after each growth, and off and on again within milliseconds at each reading). Where
      the player's minutes sensor is there, Hearth reads the minutes alone, so its flicker never reads as new play. Set
      in the row (`playing`), its player's minutes are found and used. Friend presence, or a playing sensor without a
      minutes sensor, is read as itself: "on" is playing, "off" is believed once it has stayed off for 2 minutes and is
      fresh; unavailable, unknown or stale is unknown.
    - Any source saying "playing" wins; else any trusted "not playing"; else unknown. **Nothing about playing ever lets
      a hold go**, and unknown never catches anyone: the release comes only from the kid's time, as above.

    So a hold starts about 10 to 20 minutes after the kid starts playing (the first upload that shows it), sooner with
    friend presence. A hold from before this version counts as caught. While the kid is caught, the adults get a notice
    on their phones (and on TVs that show notices): "Our Switch held for Alex", with **Let someone else play 1 h**.

    **Adults.** Adults have no limits, so an adult playing on their own player is never caught: their minutes are
    someone else's, and they end any "playing" left over from the kid. What Hearth can't know: an adult (or a brother
    or sister) playing on the kid's user counts as the kid; while a kid is caught, the Switch is held for everyone,
    adults too, until an adult gives a turn (or enters the console's parental controls PIN on the Switch).

    **Play on no player.** The console counts play that no player's minutes do: software that needs no user, or a game
    started with no user picked. Hearth can't put it on anyone, so it never holds the Switch for it. While a kid on the
    Switch would be held once caught (and isn't, and it's no one's turn), **15 minutes** or more of the console's
    minutes that no player's account for (less is Nintendo's rounding) are told to the adults, at most once an hour:
    "Someone is playing Our Switch", with **Hold it now**. It fires `hearth_switch` with `what: unattributed`, `minutes`
    and `held_for`.

    **Let someone else play.** `hearth.let_someone_play` (adults only, as every `hearth.*` action; `device`:
    `nintendo:<entity>` or the Switch's device id, `minutes` 1 to 240, default 60, `for_person` optional) lifts the
    caught hold for that long: one write, about a second to reach the Switch. Hearth's page has the same buttons on the
    kid's Switch card (30 min, 1 h, 2 h; the WebSocket command `hearth/nintendo/let_play`). During the turn:
    - if the held kid's player shows play (their minutes grow past what they were when the turn started, or a playing
      sensor of their own turns on after it), the Switch is held again at once and the adults are told ("Alex played
      during Sam's turn"). The first upload within 12 minutes of the hold starting is forgiven once: it can still carry
      play from before the hold. A reading gone for a moment (the integration reloading) is no play;
    - with `for_person`, the turn ends early when that person's own time for the Switch's groups runs out (and it's
      refused when they have none);
    - when it ends, the Switch stays open and is held again only once the kid plays after it.

    What a turn can't see: the held kid playing on someone else's user during it counts as that someone.

    **Hold it now** (`minutes: 0`, and the button on the kid's Switch card while they may not play, or during a turn)
    holds the Switch now for every kid on it whom something would hold: it ends a turn, or catches a kid not caught yet
    (an adult who sees them playing, or play on no player). It's refused when nothing would hold the Switch for anyone.

    Each change fires `hearth_switch` (`person`, `entity_id`, `what`: caught, caught_in_turn, turn_ended, released,
    held_now, unattributed; with `for_person`, `by`, `minutes`, `held_for` where they apply). The notices are of kind
    `switch` in `hearth_notice`. The kid's Switch in the household summary (`first_party.nintendo`) adds `shared`,
    `caught`, `waiting` (something would hold it for them once caught), `turn` ({until, for_person, held_for}) and
    `playing_now` (true, false or null for unknown).

    The page's Nintendo capabilities (`hearth/config` `capabilities.nintendo`) add `player_minutes` (players' minutes
    sensors exist: Home Assistant's own integration), `player_playing` (a patched copy's playing sensors exist) and
    `update_daily_restrictions`. Not built yet: a sibling's own "I want to play" on their TV or phone (it would notify
    the adults), and showing the console's PIN to adults.
- What's held is kept across restarts, so only what Hearth held is let go. For a few minutes after Home Assistant
  starts nothing is let go (the sources report in first). A failed call shows on the person's **Held by parental
  controls** sensor and is tried again 5 minutes later. Each change fires `hearth_enforced` (person, by, held, let go).
- `hearth_budget_reached` stays for anything else an automation wants to do.

### Exceptions

An adult lets someone use an app or a group for a while, whatever would hold it:

- `hearth.allow` (`people`; `app`, a package, or `group`, a Hearth group or `all`; `until`: a time, tomorrow's if it
  has passed, `school_time_end` (the end of their School time today, from Family Link's sensors) or `end_of_day`, the
  default; `reason`) returns `{id, until: {person: when}}`. It's kept across restarts. While it lasts, Hearth holds
  that app or group nowhere for those people: their TVs' and phones' state documents leave the group out (an allowed
  app is taken out of every group's `apps` and added to All screen time's `except`, so a device needs no change),
  Family Link doesn't pause it (budget or School time), and Family Safety and Nintendo don't hold for an allowed group.
  It ends on its own; what should hold then holds again with the next minute's recompute.
- `hearth.allow_end` (`id`, or `people` with an optional `app` or `group`) ends one early; returns `{ended: [ids]}`.
- **Ends on a place.** `hearth.allow`, `hearth.pause` and `hearth.school_time_off` take `ends_on: {arrive: <place>}`
  or `ends_on: {leave: <place>}`, a place key (`home`, `school`, or a favorite place's key, see [Places](#places)) of
  each of the people. It ends for each person on their own, exactly as `hearth.allow_end`, `hearth.pause_end` or
  `hearth.school_time_off_cancel` would for them (Hearth's extra time in Family Link and Family Safety for an allow is
  taken back too), when their confirmed place changes: `arrive` when it becomes that place, `leave` when a confirmed
  that place becomes another (known) one. An exception that starts with them already there doesn't end until they
  come back (arrive) or leave. An unknown or stale place never ends anything: the time stays the cap (an allow's
  `until`, the end of the day by default; a pause's `minutes` or `until`, the end of the day when it has neither;
  School time off: its day, and `ends_on` only for today's). The adults are told the way requests reach them ("Sam got
  home; their allow (screen time) ended."). The allow, the pause and the School time off carry `ends_on` {arrive or
  leave, `place` (its name), `text`: "ends when Sam gets home, or 21:00"} on the Screen time today sensor, in
  `hearth.explain` (with the exception, and with a pause in `blocked_by`) and in the household summary. A pause for
  several people ends per person (each person's pause is their own), so the others stay paused until they move too.
- **Extra time on one device.** `hearth.add_bonus` with `device` (a target id from the household summary's
  `targets`: `hearth:<device_id>`, `fl:<Family Link device id>`, `fs:xbox`, `fs:windows`, `nintendo:<entity>`) gives
  that many minutes (more than 0) on that device only, today (returns `{id: "dx_...", until}`, so an undo can end
  just that one); `hearth.allow` with `device` opens a group there until the time (`end_of_day`, `school_time_end` or
  a time; no `app`, no `ends_on`; returns the `dx_...` id). The person's shared time keeps counting and every other
  device still reads it: only that device may go past it. Ended early by `hearth.allow_end` with `people` and the
  same `device`, or with its id. On a Family Link device, a Family Safety platform or a Switch (`groups: false` in
  `targets`) only `all` can be given: what holds a group there holds it on every device of theirs (Family Link's app
  pauses are the child's, Family Safety's app blocks the account's). What it does, by device:
  - a Hearth TV or phone: that device's state document shows the group with what's left of the bonus there (the
    minutes less what that device used of the group since; an allow: the group isn't held there), never less than
    the pool; until midnight.
  - a Family Link device: a Family Link bonus of that many minutes on that device (`add_time_bonus`, only where
    Google's own limit would stop it, as for an allow of All screen time: the limit Hearth sets to 0 when All screen
    time is out, say), which Google counts down; Hearth remembers it as its own, so it's no parent's grant, and
    ending it early resets it (unless a parent's bonus came on top).
  - a Family Safety platform: Hearth's lock of that platform is let go, and Microsoft's own allowance gets extra
    time where it would stop it (`add_time_bonus`, until then; on Windows only where Family Safety takes it); by the
    clock, from now. Microsoft's extra time doesn't lift the platform's allowed hours, so extra time that runs past
    the end of today's allowed hours moves that end to cover it, rounded up to the next half hour
    (`set_screentime_intervals` with `today_only`: Family Safety puts the day back at midnight; only a day with one
    allowed window, and on the Xbox only with the Xbox Family Settings sign-in). Ended early, the end it found goes
    back, unless a parent changed it since or other extra time of theirs still needs it. **A Family Safety without
    `today_only`** (the released one, upstream's 2.3.0) gets this weekday's setting instead (`day_of_week`, 0 is
    Sunday), and Hearth puts the window back itself: it records the window it found and the one it wrote before
    writing (kept with Home Assistant's storage helper, so a restart or a missed midnight still knows it), watches
    each minute whether the day still reads Hearth's window, and after midnight writes the window it found back,
    only while the weekday still reads Hearth's: read from the Windows weekday's own Start and End entities, the Xbox's
    allowed hours when today is that weekday again, else as last seen before midnight (a parent's change seen before
    midnight stays). After a start that missed midnight it does so once Home Assistant has settled (a few minutes);
    a failed write is tried again every 5 minutes. On Windows it's never moved while Family Safety keeps a saved
    schedule (`has_saved_policy` on the child's account Lock or Screen Time Limits switch: its account lock, or
    limits off through its web fallback), because Family Safety then writes every change of a Windows day into that
    restore point too and the unlock would write Hearth's window back for good; a window moved before such a lock is
    put back only once the restore point is gone (the unlock wrote the schedule back), still only while it reads
    Hearth's. Upstream's platform locks (`lock_platform`, `unlock_platform`) are Microsoft overrides and never save
    or touch the schedule, and its Xbox allowed hours (Xbox Family Settings) have no restore point. Any platform their Family
    Safety reports is a target, whether or not Hearth's enforcer holds it. When it ends, Hearth locks
    the platform again if the pool is still out.
  - a Switch: Hearth's hold of the Switch is let go (its own limit and Suspend software put back); by the clock, from
    now. Where the Switch's own limit would stop it sooner, Nintendo's extra playing time is added too, as for the
    Switch's mirror of extra time ([Keeping the parents' apps in step](#keeping-the-parents-apps-in-step)), and
    cancelled when it ends early.
  **Bedtime on one device** (`hearth.allow` with `device` and `bedtime: true`, an `until`, no app or group): bedtime
  is lifted on that device only, until then (midnight at most). A family pause, School time and a daily time that
  runs out still stop it there, and the time used there counts as always; it never counts as extra time at bedtime,
  so the person's other devices stop at bedtime as before. By device:
  - a Hearth TV or phone: that device's copy of the person's state document isn't locked by bedtime (the schedule's
    Sleep or a bedtime lock entity), says `bedtime_lifted` `{since: null, until}`, and names the lift's end as
    `next_lock` (kind bedtime, `until` the wake), so a TV that loses Home Assistant locks again by itself at the end.
    It never moves Family Link's bedtime.
  - a Family Link device: what opens Family Link's bedtime on one device is a bonus there (as
    [Extra time at bedtime](#extra-time-at-bedtime) found), so once that device is in bedtime (Family Link's own, or
    Hearth's Sleep lock of the devices) it gets `add_time_bonus` for the minutes until the lift's end, never more than
    All screen time has left. It waits while School time, a pause or daily time running out holds the device (a bonus
    would open those too), and is given once only those are gone. Hearth's own, so no parent's grant; ended early,
    it's reset (unless a parent's bonus came on top). Family Link's bedtime itself isn't moved.
  - a Family Safety platform: the schedule's Sleep lock of that platform is let go (a budget's or a pause's lock
    stays), and Microsoft's allowed hours today move to cover the lift, as for extra time on that platform (no extra
    time: its daily allowance still counts). Ended early, the allowed hours go back. E.g. "Xbox until 10 tonight,
    nothing else".
  - a Switch: the schedule's Sleep hold of the Switch is let go (a budget's or a pause's hold stays). No extra
    playing time, and the Switch's own bedtime alarm (set in the Nintendo app) isn't moved.
  Example: bedtime at 9 PM, and an automation that lifts it on a kid's TVs until 10 PM each night. `kind` is
  `bedtime` in `device_extras`; `hearth.allow_end` with the `device` (or the id) ends it.
  Each shows in the summary's `device_extras`, in `hearth.explain` (`device_extras`) and as a contract 2 line.
- Bedtime, School time itself and a family pause still lock the person. An allow lifts Hearth's holds, not those
  locks: a TV can't open one app through a lock without a change on the TV, and Family Link's own bedtime still locks
  the phone. To lift School time, take it off (`hearth.school_time_off`).
- `hearth.explain` (`person`; `app` or `group`), response only: `{allowed, until, blocked_by: [{kind, by, until}],
  lifted, exceptions, school_time_off}`. `kind` is `budget` (by the group, until midnight), `bedtime`, `school_time`
  or `other` (by the lock entity, until it says), `pause` (until, reason) or `device_limit` (a device's own limit
  stops it now, not a hold of Hearth's: Google's daily limit on a Family Link device, with its `device` name, until
  midnight; Microsoft's allowance or allowed hours on a platform, with its `platform`, until null; a Switch's own limit,
  by its Max screentime entity, with its `device` name, until midnight, listed only for what the Switch is held for:
  All screen time, Games, an app of those) or `parent_lock` (a parent's own Family Safety lock, with its `platform`,
  until it ends) or `school_time_apps` (by the Family Link
  entity, until School time ends) or `google_tv_limit` (by the TV's device id, with its `device` name, until null; see
  below) or `app_limit` (a parent's own Family Link app limit used up on a device: by the Apps with time limits
  sensor, with `app`, `device`, `limit_minutes` and `used_minutes`, until midnight; Hearth's allows and bonuses don't
  raise it, so an adult raises or removes it in Family Link; Hearth's own pauses aren't listed here) or `blocked_app`
  (Hearth's own block of the app, [Blocked apps](#blocked-apps): `by` is `hearth.block_app`,
  `block_unsupported_browsers` or `block_ai_companions`, with `app` and `why`, until null; no allow lifts it; or a parent's own block made in
  Family Link or Family Safety, not by Hearth: `by` is `family_link` or the Family Safety Applications sensor, with
  `provider`, `app` and `why: ["parent"]`, until null; only unblocking it there lifts it, since `hearth.unblock_app` leaves a parent's own block). `place` is kept for place rules (none are built yet: a place only ends an exception so far). `until` is when it's allowed again (the latest of the blocks, null when one doesn't
  say), or, when allowed thanks to an exception, when that ends. `lifted` lists the holds an allow lifts now.
- **Google TV's own Kids daily limit.** A kids profile can also have a daily limit set in Google TV itself (Family Link's
  or the TV's own Kids profile settings). When it runs out, Google TV shows its time up screen and blocks the whole
  profile, whatever Hearth allows: a Hearth bonus or `hearth.allow` doesn't get past it. The TV reports it
  (`google_time_up` in its status), `hearth.explain` lists it as `google_tv_limit`, and the person's headline says
  `google tv's own limit`. **Hearth can't lift it**: an adult has to raise or turn off that profile's daily limit in
  Google TV. To let Hearth own the limits, turn Google TV's daily limit and bedtime off for kids' TV profiles (in
  Google TV or Family Link), and set them in Hearth. A paired TV's setup says so (its "Leave Google's time limits off"
  step), and once the TV saw Google's time up screen in the last week, its Set up Hearth TV page says "Google TV's own
  limit is on".
- The person's **Screen time today** sensor has an `exceptions` attribute: `allows` (id, app or group, until, reason),
  `grants` (below), `school_time_off` (what's taken off and when it's put back) and `rules` (a standing rule while it
  lifts something: [Messages when away from adults](#messages-when-away-from-adults)).

### Blocked apps

Every kid control goes through Hearth: block an app with `hearth.block_app`, never with `familylink.block_app` directly,
so Hearth's pauses, its schedule and its blocks stay in step (`app_blocks.py`).

- `hearth.block_app` and `hearth.unblock_app` (`app` or `apps`: Android package names, or Family Safety's app ids of
  Xbox and Windows apps; `people`: the kids, by default every kid with what blocks the app), adults only like Hearth's
  other services. Hearth blocks an Android app through Family Link (`familylink.block_app` with the kid's Family Link
  entity) and keeps its own record of what it blocked. Hearth's own apps, Family Link, Google Play, Settings, the
  dialer and contacts are never blocked (an emergency call always works). Messages apps can be blocked; blocking one
  (unlike pausing it) makes it miss incoming texts, while a paused Messages still receives them.
  The response names who each app was blocked or unblocked for.
- **Xbox and Windows apps.** An app id as Family Safety's Applications sensor lists it (`x:...` an Xbox game or app,
  `x:windowsplt:...` or `appx:...` a Microsoft Store app, `win32:...` a Windows program) is blocked through Family
  Safety's `block_app` (unblocked with `unblock_app`), for a kid with a Family Safety enforcer (Configure > Enforce);
  the block is the account's, on every platform. Everything below holds for them too, read from the kid's
  Applications sensor instead of Family Link's lists: only Hearth's own blocks are lifted (one a parent made in the
  Family Safety app stays theirs), one not in the list waits until the app is, a list cut short or missing blocks and
  unblocks nothing, a block Family Safety never lists is tried 3 times, and a parent's unblock in the Family Safety app
  is kept. One more rule: Family Safety pauses an app (Hearth's holds of Xbox and Windows apps) by blocking it and
  puts back on resume what the app was before, so a block or unblock of an app Hearth's pause holds now waits until
  the app is resumed (made under the pause, the resume would undo a block, and an unblock would lift the pause).
  The browser and AI companion rules are Android's only (Family Safety's web filter covers browsers there).
- **Hearth only undoes its own blocks.** An app a parent already blocked in the Family Link app stays the parent's
  (Hearth's page shows "blocked by a parent in Family Link"); unblocking it in Hearth leaves it blocked there.
- **A block stays.** An app that isn't installed waits ("not installed: blocked when it shows up") and is blocked as soon
  as it appears in Family Link's app lists. One that left the device and comes back unblocked (installed again) is
  blocked again.
- **A parent's unblock in the Family Link app is kept.** A block Family Link confirmed (listed as blocked) that later
  shows unblocked while the app stays installed was taken back by a parent: Hearth records it ("unblocked by a parent
  in Family Link" on Hearth's page, event `hearth_app_unblocked_by_parent`) and doesn't block it again, until an adult
  blocks the app again in Hearth.
- **When Family Link doesn't take it.** A block call Family Link accepts but never lists is tried 3 times, a few minutes
  apart (about 10 minutes); then Hearth stops and the card says "Family Link didn't block <app>". `hearth_app_blocked`
  fires once, when Family Link lists the app blocked.
- **Holds leave a blocked app alone.** Only what Family Link lists as blocked (Hearth's confirmed blocks and a parent's)
  is left out of Hearth's holds; a block Hearth wants that Family Link doesn't list yet is still paused like any app.
  A budget, a pause, School time's apps or the schedule never pause or resume an app Family Link lists blocked: one Hearth had paused stays recorded as paused (its reason on Hearth's page is `blocked_app`) and Family
  Link's `resume_app` skips a blocked app anyway; once unblocked, it is let go as usual. `hearth.allow` doesn't lift a
  block, the MCP tools refuse to allow it, and `hearth.explain` lists it in `blocked_by` (`kind: blocked_app`).
- **Block browsers Hearth doesn't support** (option `block_unsupported_browsers`, off by default; Hearth's page > Apps >
  Blocked by Hearth). Hearth filters sites only in some browsers, one list kept in code (`SUPPORTED_BROWSERS`):
  - Chrome on Android: Family Link's site filters, and the blocklist Hearth syncs into them, apply in Chrome only.
  - Microsoft Edge on Windows and Xbox: Family Safety's web filter applies in Edge; with it on, Windows blocks every
    other browser and the Xbox only has Edge, so nothing more is blocked there.
  - Not Edge on Android: Family Safety's filter there works only while the kid is signed in to Edge with their
    Microsoft family account, which nothing on Android enforces, and Family Link's filters don't reach Edge.

  With the rule on, any other browser on a kid's Android devices is blocked as soon as Family Link lists it: a known
  browser's package (Samsung Internet and its beta, Firefox, Focus, Klar and Nightly, Opera, Opera Mini and GX, Brave,
  DuckDuckGo, Vivaldi, Tor Browser, Kiwi, UC Browser, Yandex, Puffin, Dolphin, Mi Browser, Ecosia, Silk, Aloha, Edge,
  Chrome's beta, dev and canary builds), or an app Hearth's app categories know as none of the ten kinds with a
  browser's name. The rule also blocks other app stores that install apps without Family Link's approval (the Galaxy
  Store, Amazon Appstore, Aptoide, APKPure, F-Droid, AppGallery, Uptodown, GetApps). An app an adult unblocks stays
  unblocked. A browser added to the supported list later, and everything when the rule is turned off, is unblocked,
  only where Hearth was the one that blocked it.
- **Block AI companion apps** (option `block_ai_companions`, **on** unless an adult turns it off; Configure > Blocked
  apps, next to the browser rule, or Hearth's page > Apps > Blocked by Hearth). AI companion and character role-play
  chat apps Hearth knows by package on a kid's Android devices are blocked as soon as Family Link lists them (why:
  `ai_companion`, "an AI companion app" on the page), with everything above (an adult's unblock is kept, a parent's
  own block stays theirs, one not installed waits):
  - only its package blocks (`AI_COMPANIONS`, each checked on Google Play): Character AI, Talkie, Chai, Replika, Nomi,
    Kindroid, PolyBuzz, Linky AI, Saylo, Botify AI, Paradot, EVA AI, HiWaifu, Romantic AI, PixelChat (by SpicyChat's
    maker; SpicyChat and CrushOn have no Play app Hearth could check);
  - an app that is one only by its name (Hearth's app catalog's or Family Link's, and Hearth's app categories'): "AI"
    followed by companion, girlfriend, boyfriend, friend, character, role-play, waifu, lover, soulmate or crush;
    "Character AI"; "chat with (AI) characters"; "virtual girlfriend/boyfriend"; "companion/girlfriend/waifu AI";
    "role-play AI/chat" ("AI chat" alone isn't enough: general assistants are named like that too) is **never
    blocked** by the rule. The adults get one notice per app and kid ("Sam: Pal: AI Friend may be an AI companion
    app"), with **Block** (`hearth.block_app` for that kid and app: an adult's block from then on) and **Not now**.
    Either way that app isn't asked about again for that kid (kept across restarts; Hearth's page lists them as
    `asked`). `hearth_ai_companion_asked` (`person`, `app`, `name`) fires for each.

  General assistants and tools are never blocked or asked about by this rule, whatever their names say: Google Gemini, Microsoft
  Copilot and Microsoft 365 Copilot, ChatGPT, Claude, Perplexity, Meta AI, Grok, and Google Chat; nor is an app whose
  name sounds like an assistant, a tool, a messaging or a school app, or one Hearth's app categories know as messaging
  or education. To block one of those, block it with `hearth.block_app`. Turning the rule off unblocks only what this
  rule blocked: the browser rule's blocks, an adult's and a parent's stay.
- **Hearth's page** (Apps > Blocked by Hearth): the rules, the browsers Hearth filters sites in, each kid's blocks (why,
  where it stands, Unblock), and Windows and Xbox: "covered by Family Safety web filtering: on", or a warning when a
  kid's Family Safety web filtering switch is off or not found. Every Android app's row in Every app has Block (every
  kid with Family Link). `hearth/config`'s `app_blocks` carries it all (each kid's `family_safety`: whether Xbox and
  Windows apps can be blocked for them).
- Events: `hearth_app_blocked` and `hearth_app_unblocked` (`person`, `app`) after each Family Link or Family Safety
  call.

### Outside app changes

When an app gets more room in a parental-controls app and Hearth didn't do it, every adult's phone is told
(`outside_apps.py`). The providers can't say who made a change, and a kid holding a parent's phone looks just like a
parent to them, so this is how such a change comes to light. Every provider is read into the same lists (installed,
blocked, time limits, paused, always allowed) and compared the same way:

| Provider | Read from | Always allowed means | The button blocks it with |
|---|---|---|---|
| Family Link | the kid's app list sensors | Always allowed | Hearth's own block (as `hearth.block_app`) |
| Family Safety | the kid's Applications sensor (Windows and Xbox apps) | (none) | Family Safety's `block_app` |
| Nintendo | each of the kid's Switches: `list_applications` (the integration's last poll), every 10 minutes | on the console's allow list (starts whatever its age rating); told once per console | `set_app_allowed` off ("Take off allow list") |

Every notice has one button: **Block again** for an unblock, **Block** for a limit, **Take off allow list** for a
Switch game. It runs `hearth.block_outside_app` (`source`: the list, as `<person>|family_link`,
`<person>|fs:<sensor>` or `nintendo:<device id>`; `app`), adults only, which takes only a list Hearth looks at.
Hearth never blocks again by itself: an adult decides.

**Stray app pauses.** An app can be left at Hearth's 1-minute Family Link pause after Hearth let go of it, with no
record in Family Link of the setting to put back (a Family Link before the fork's fix saved the pause itself when it
paused an app right after resuming it). `hearth.release_stray_pauses` (`person`; `limits`: minutes per package;
`dry_run`) puts each such app back to no app limit, or to the minutes given: apps Hearth paused in the last 7 days
(its action log), at a 1-minute limit that is on, not in Family Link's `paused_apps`, not blocked, and not held (or
possibly held) by Hearth now. It reads only whole With time limits and Blocked apps lists (never one cut short or
missing: writing a limit to a blocked app can unblock it), and refuses for 3 minutes after Hearth let go of a Family
Link hold of the kid's, while the list may still show a pause that was just resumed. An app whose call fails is named
in `failed` and the others still go back. Its calls are Hearth's own, so the adults aren't told about them.

**A list cut short.** Pausing every app (daily time out while an app stays open, e.g. Messages while away from adults)
moves each one into Family Link's With time limits list, which then outgrows Home Assistant's attribute limit and is
cut short (`truncated`). The apps installed are then read as the last whole read plus what the lists show, so Hearth
keeps the apps paused rather than swapping to the device lock and back. The last whole read is kept over a restart of
Home Assistant; with none yet, a With time limits list cut short reads as what it shows plus the apps Hearth holds.
A Blocked apps list that is missing or cut short is unknown, never "nothing is blocked": Hearth blocks and unblocks
nothing meanwhile, keeps out of its pauses and resumes the apps of the last whole list (kept over a restart) plus
the ones the list shows, and, when the list was never read whole, keeps the device lock rather than pausing every
other app.

- **Told:** an app unblocked (still installed); an app's time limit raised or taken off; an app made Always allowed
  or put on a Switch's allow list. The text says the app, what changed, where and when, e.g. "Pins was unblocked in
  Family Link, not by Hearth (5:40 PM)."
- **Not told:** tightening (a block, a lower limit), an app uninstalled, and Hearth's own changes: a call of the
  provider's that names the app (block, unblock, pause, resume or an app limit; Nintendo's `set_app_allowed`), while
  the call still runs (a pause or resume of 150 apps takes two minutes, and its changes show before it returns) and
  for 30 minutes after it ended, counted back from the last look at the list rather than from now (a list cut short
  for an hour is compared with the look before that hour). Every app of the call counts, however long its list (the
  action log's record keeps the first 50). Apps Hearth pauses are left out of the limit comparison before and after.
- Each list is compared with the last look (kept across restarts, so a change made while Home Assistant was down is
  told at the next look). Nothing is told at the first look, or while a list is missing or cut short.
- `hearth_outside_app_change` fires for each one (`person`, `provider`, `app`, `change`: `unblocked`, `limit_raised`,
  `limit_removed` or `always_allowed`, `before`, `after`), and the action log records it (`kind: outside_app_change`).
- A parent's unblock of an app Hearth blocked is still respected (Hearth doesn't block it again by itself); Block again
  makes it Hearth's block once more.

### Keeping the parents' apps in step

A parent's change in a first-party app (Family Link, the Nintendo app, Microsoft Family Safety) is an adult's decision:
Hearth adopts it and never writes over it or fights it. And Hearth's own "all screen time" opens Google's,
Microsoft's and the Switch's own limits too. Everything below is gated on what the installed integrations offer (a service there, an
attribute present), so an older Family Link or Family Safety keeps working as before.

**Bedtime** is kept in step from Hearth's weekly schedule, once an adult starts it: Family Link's weekly bedtime and
tonight's override, Family Safety's allowed hours per weekday and today's. A parent's bedtime change in either app is
followed tonight and offered for every week. See [Bedtime sync](#bedtime-sync).

**What the installed Family Safety can do.** New families get the integration's released version; Hearth finds what
it has from its services' schemas and its entities' attributes and uses what's there. Hearth's page (`hearth/config`)
has it as `capabilities.family_safety`: `installed`, `today_only` (set_screentime_intervals changes today only),
`weekday_hours` (it takes `day_of_week`), `hold_attributes` (Allowed Now and lock switches say whose a lock is),
`allowed_now` (Allowed Now sensors with the override in force), `lock_until` (lock_platform takes an end),
`xbox_extra_time`, `windows_extra_time`, `cancel_extra_time`, `pause_apps`, `request_events`, `pending_requests`,
`site_list_sync` (it keeps the website block list itself: `sync_site_list`) and `website_lists` (it has `get_sites`,
`block_website` and `remove_website`, so Hearth keeps the list). Family Safety's row under `parental_controls` adds
`reduced`: one line per thing Hearth does with less on this version (allowed hours put back by Hearth, a parent's
lock told from Hearth's own record, locks by whole hours that Hearth ends at midnight, requests read from the
sensors, ...), shown on the page under the integration as "Works with less on this version"; empty when it has it
all. It's not a problem to fix.

- **Compare and restore.** Letting go of a Family Link device lock puts the weekday's daily limit back only while that
  limit still reads 0 (what Hearth set); a Switch's Max screentime and Suspend software, only while the limit still
  reads 0. A limit a parent changed meanwhile stays (`kept_current`). Family Link's `resume_app` compares in Family
  Link itself; its answer (`results`: `restored`, `kept_current`, ...) is read and shown.
- **Parent grants.** A parent's change that lets a kid use what Hearth holds becomes a grant `{id, person, via
  (family_link, nintendo, family_safety), source ("from the Family Link app"), target {kind: device, app, switch or
  platform; value}, until, since, reason, endable, end_with}`; in the household summary an app's grant also has the
  app's `name` when Hearth knows it (its app catalog, or the kid's Family Link sensors). It lifts only the hold it came from (the child's Family
  Link device lock, the paused app, the Switch, a Family Safety platform), not a whole group everywhere as an allow
  does, and budgets keep counting. Grants are kept across restarts and end on their own; when one ends, enforcing goes
  on as usual. They show in `hearth.explain`'s `exceptions` (`type: "grant"`), the person's `exceptions` attribute,
  the household summary and Hearth's page. Seen while Hearth holds something:
  - Family Link: today's weekday limit raised (adopted: nothing is put back over it), until midnight; bonus time on a
    device (its `bonus_minutes` beyond what Hearth itself added), until the bonus is used up (the Active bonus sensor's
    `remaining_minutes` reaches 0 or it clears) or midnight; a device unlocked (`lock_override_code` 4), until midnight;
    an app a parent changed after Hearth paused it (the Apps with time limits sensor's `paused_apps`, `pause_intact`
    false), until midnight. Only a pause Family Link has once shown intact (`pause_intact` true) can be changed by a
    parent: Google takes some apps' 1-minute limit (the call succeeds) and never shows it. A pause still not shown 3
    minutes after Hearth's call didn't take: it's no grant, the kid's Family Link line says "Family Link didn't take
    the pause of …" (with the action log, once), the app stays as held and is paused again after 5 minutes, then
    after twice as long each time, up to an hour, until it shows. An app the child doesn't have (not in their app
    lists) never shows its pause, so its `pause_intact` is false too: that's never a grant. A `pause_app` that fails
    part-way (Family Link pauses the list app by app and stops at the first refusal) leaves its apps possibly paused:
    letting go resumes them too.
  - Nintendo: the Switch's Max screentime today raised, or bonus time (`time_extended`), until midnight (adopted).
  - Family Safety (its Allowed Now sensors' and lock switches' `hold`, `override`, `allow_until`): `hold: parent` with
    extra time (`allowUntil`) is a grant until `allow_until`; with no override left (a parent cancelled Hearth's lock),
    until midnight. A parent's own lock (`blockUntil`) is no grant but a **parent lock** (below).
    **Without the `hold` attribute** (the released Family Safety, upstream's 2.3.0) Hearth works out the same answer
    from what Family Safety shows in force (Allowed Now's `override` and `override_until`, else the platform's Lock
    switch) against its own record of what it asked for: when its lock ends (kept with what's held: `until` the next
    midnight, or by whole hours where `lock_platform` takes only `duration_hours`) and when the extra time it gave
    there ends. A lock ending when Hearth's does (within 2 minutes) while Hearth holds the platform is Hearth's, any
    other lock a parent's; extra time ending when Hearth's does is Hearth's (`bonus_ours`), any other a parent's;
    nothing in force while Hearth's lock should still be is a parent's unlock (unless Hearth's own extra time
    replaced the lock today). Unknown locks (Family Safety couldn't read them) are nobody's: no grant. What it can't
    tell: Family Safety shows no end for a Windows lock after it restarts, so a parent's Windows lock while Hearth
    holds Windows reads as Hearth's, and a lock from before this version (no end kept) is taken as Hearth's. The
    first-party rows say where the answer came from (`hold_from`: `attributes` or `hearth`).
  - A change right after Hearth's own call (a minute), or a limit that still shows what it was before Hearth's 0
    arrived, is Hearth's own and not a grant. Hearth's own bonuses are remembered, so they never count as a parent's.
  - After any write Hearth makes to Family Link, Family Safety or Nintendo (a hold or release, extra time, a bonus
    reset, moved allowed hours), that entity is refreshed once about 10 seconds later (`homeassistant.update_entity`,
    which asks the integration's coordinator), so what Hearth did shows within seconds rather than at the
    integration's next poll (a minute to five). One waiting refresh per entity; the refresh writes nothing. The Held
    by parental controls sensor and the summary change as soon as a hold or release call returns.
  - Event `hearth_parent_grant` (the grant) when one starts.
- **Ending a grant early.** `hearth.allow_end` with the grant's `id`. Hearth's page and the summary offer it only when
  it maps to a write in the parent's app (`endable`): a Family Link bonus (`familylink.reset_bonus`, else the device's
  Reset bonus button: `end_with: family_link_reset_bonus`), Family Safety extra time (`cancel_time_bonus`, then the
  platform is locked again: `family_safety_cancel_bonus`), or a Switch or platform a parent unlocked or raised (locked
  again by Hearth's hold: `relock`). A raised Family Link limit, an unlock or an app change is shown read-only there;
  the service still ends it, and Hearth holds again with the parent's value as the one to put back.
- **Hearth's "all screen time" in the parents' apps.** `hearth.allow` for group `all`, and extra time that gives All
  screen time back (it had none left), also give (the Switch also for an allow of a group it's held for):
  - Family Link: a today-only bonus (`familylink.add_time_bonus`) on each of the child's devices whose own daily limit
    would block within that time (Screen time remaining lower than the minutes needed; a device with no limit gets
    none), as much as is missing; once per allow.
  - Family Safety: extra time (its experimental `add_time_bonus`, `until` the allow's end or midnight) on the
    enforcer's platforms whose allowance would block (allowance minus used lower than the minutes needed): the Xbox,
    and Windows where the installed Family Safety takes `platform: Windows` (its service schema says so; releases
    before 2.3.0 are Xbox only, and Windows is then skipped quietly). It replaces Hearth's own lock there
    (`replace_lock` only when the platform's `hold` is Hearth's, from Family Safety's attribute or worked out as
    above, never over a parent's lock). When it ends is kept, so Family Safety showing it later is Hearth's own. Family Safety's answer says what became of that
    lock: with `hold_kept: true` (a Family Safety that keeps holds puts the lock back after the extra time) Hearth
    still holds the platform; with `hold_kept: false`, or upstream's `replaced_lock: true` without `hold_kept` (the
    extra time ended the lock), Hearth no longer holds it and doesn't let go of it again later; an answer with
    neither changes nothing. When Microsoft doesn't apply it,
    the person's status says Family Safety extra time is unavailable and it counts as not given; nothing fails.
    **A write that failed may have been applied anyway** (an error or a timeout after Microsoft took it, and a read
    back that couldn't tell): unless the service's schema refused it, Hearth keeps it as possibly given (person,
    platform, the `until` it asked for, the error, when; kept across a restart) and looks each minute for 10 minutes.
    Meanwhile extra time ending then counts as Hearth's, never a parent's grant. If Family Safety shows extra time on
    that platform ending when Hearth asked (within 2 minutes; a fork's `hold: bonus_ours` agrees), Hearth adopts it
    as its own extra time for its reason (so ending the allow cancels it through `cancel_time_bonus`, which checks
    what's in force first) and logs a WARNING naming the platform, the `until` asked for, the error and when it
    showed ("... was applied although its write failed ... A write Microsoft didn't confirm was applied anyway"),
    with no names or account ids: evidence for the Family Safety maintainer. If its reason already ended, it's
    cancelled that way at once. If nothing shows within the 10 minutes it's dropped (logged at INFO: not applied).
    Hearth never sends a cancel for extra time it can't see.
  - The Switch: Nintendo's extra playing time (`add_bonus_time`, today only) on each Switch Hearth holds for the kid
    whose own limit (Max screentime) would stop it sooner than Hearth: as many minutes as its Time remaining falls
    short (Nintendo's 5 at least, the installed integration's most at most: 30 on Home Assistant's own, 360 on the
    patched copy). For extra time, as long as Hearth now lets the Switch run (the fewest minutes left of the groups
    it's held for, also when All screen time has no limit); for an allow, until its end. An allow of a group the
    Switch is held for (Games) gives it on the Switch alone, since it opens the whole console. Extra playing time
    opens the Switch whatever holds it, and while it runs Nintendo refuses a new limit, so Hearth couldn't hold the
    Switch: it's given only where Hearth can cancel it again (`cancel_bonus_time`, the patched copy's, or the Switch's
    Cancel extra playing time button; without either, nothing is given and the kid's Switch line says so). It waits
    while Hearth holds the Switch (a pause, Sleep, another kid on a shared one) and is given once the hold is let go
    (as Family Link's waits). Before Hearth holds the Switch again, it cancels its own extra playing time (then holds),
    and the extra time it was for waits to be given again; a parent's extra playing time is theirs (the hold waits for
    it, as before). Nintendo moves the Switch's bedtime alarm for extra time that runs into it, so Hearth's never runs
    past the alarm, and none is given while the Switch is in its bedtime. What Hearth added today is kept per Switch
    before the call (`sw_added`, over a restart): an extension up to that much is Hearth's own, more is a parent's too.
  - Ending the allow early (`hearth.allow_end`) resets the Family Link bonus Hearth added (only where no parent's bonus
    came on top: `reset_bonus` ends every bonus of the day; without `reset_bonus` or the button it lapses at
    midnight) and cancels the Family Safety extra time Hearth gave (`cancel_time_bonus`, on each platform it gave it
    on), except where the platform's `hold` now reads `parent` (a parent's extra time or lock came since: kept,
    `extra_time_kept` in the status), and the Switch's extra playing time (only where no parent's came on top and no
    other extra time of Hearth's still needs it; else it lapses at midnight, Hearth's hold staying the real limit).
    Taking extra time back (`hearth.remove_bonus`) does the same.
- **First-party limits in explain.** `hearth.explain` also lists `device_limit` (a Family Link device's own daily limit
  reached with no bonus left, by its switch, with its `device` name, until midnight; a Family Safety platform that
  Microsoft's allowance or allowed hours stop, with its `platform`; or a Switch whose own limit is used up with no
  extra playing time, by its Max screentime entity, with its `device` name, until midnight, for what the Switch is
  held for) when Hearth isn't the one holding it, and `parent_lock` (a parent's own Family Safety lock, with its
  `platform`, until it ends), so explain says what the device does.
- **Requests answered in the Family Safety app.** `microsoft_family_safety_request_resolved` with `via: app` closes the
  matching ask as answered there (`answered_in: family_safety`): `outcome` `approved` or `denied` as such ("approved
  in the Family Safety app", "denied in the Family Safety app"); `unknown` (the request left Microsoft's list without
  Family Safety seeing how: answered in the Family Safety app or on the device) as status `handled`, shown as
  "handled outside Hearth (the Family Safety app or the device)", never as expired. `hearth_more_time_answered` says
  the same status. `via: service` (Hearth's own answer) is left alone. Family Link has no kid requests, so there's nothing to close there.
- **Requests without those events.** The released Family Safety (upstream's 2.3.0) fires neither
  `microsoft_family_safety_request` nor `_request_resolved`; it has each child's **Pending Requests** sensor (unique
  id `<entry>_<account>_pending_requests`: the count, and Microsoft's requests in `requests`). Hearth reads it for each
  child with a Family Safety enforcer, on every change and every minute, and tells requests apart by `id`: a new one
  becomes an ask exactly as the event makes it (platform, app name, requested time). One gone from the list is
  resolved once a fresh reading lacks it (the sensor written again by a Family Safety poll, so within one of its
  update intervals, plus a few seconds for the rest of that poll to land; a minute's check without a new poll doesn't
  count; back in the list before then, it isn't resolved), as "handled outside Hearth"; sooner,
  and as approved in the Family Safety app, when extra time newly shows on the request's platform for that kid within
  3 minutes of it leaving (the Allowed Now sensor's `allowUntil`, not extra time Hearth gave itself), with the minutes
  to that extra time's end. One Hearth answered itself is already closed. An unavailable or unknown sensor, or one
  without `requests`, changes nothing and isn't a reading; an id back in the list isn't resolved. The first reading of a child's sensor learns what's pending without announcing it; the ids known (and
  those resolved lately) are kept with Home Assistant's storage helper, so a restart announces nothing again and a
  request that came or went meanwhile is found. Where the fork's events fire too, each request is handled once,
  whichever comes first: an event marks its id known (or resolved), and an ask is made once per request id.
  `capabilities.family_safety` has `request_events` (its own events were seen here) and `pending_requests`.

#### Family Link backstop

Hearth's own holds are the real limit. On top of them Hearth keeps each kid's Family Link daily limit a little above
its own numbers (backstop.py), so a phone whose Hearth companion is off, or a device Hearth can't see, still stops near
the end of the day:

    Family Link daily limit today = the most screen time Family Link counted today on one of the kid's devices
                                    (not a TV) + Hearth's daily time left (bonus included) + each category's
                                    own bonus left + margin,
                                    rounded up to 5 minutes (at most 24 hours)

**Daily time out while a category stays open** (its own bonus left, or an allow of it): Family Link's devices stay
unlocked only when that category can be spent (in daily time, or with a limit) and the kid has an app of it installed;
then every installed app (Family Link's lists, no cap) is paused but that category's and the explicit system list
(dialer, contacts, Settings, Play services, Family Link and its helper, the Play Store, Hearth and Glint, by name, not by
the `com.android.` prefix, so Chrome is paused; the common keyboards and voice typing: Gboard, Samsung Keyboard,
SwiftKey, Fleksy, Grammarly's keyboard and Google's speech services, not the Google app; launchers, keyboards in System
screens and accessibility apps as always). Switching between the whole-device lock and per-app pauses holds the new
way first, so a failed pause keeps the device lock (tried again). The backstop is
then the device's minutes when it opened + what was open then (more given since adds on) + margin, rounded up to 5,
and never follows the device's minutes upward. When the bonus or allow ends or is used up, the whole-device lock is
back. Otherwise (a category that can't be spent, or none of its apps installed) the whole-device lock stays.

It's anchored on what Family Link itself counted, so it never sits below real use. Spending counted time (bonus
included, past a category's limit or not) leaves it steady: the device's minutes grow as Hearth's time left shrinks.
Time Hearth doesn't count (a category outside daily time, System screens, Unlimited) raises it. Example: 30 minutes
counted, then 150 on the phone while Unlimited: after Unlimited it is 180 + the time left + 30, never 180.

- On by default (Configure > Enforce: "Keep Family Link's daily limit as a backstop"); the margin is 30 minutes by
  default ("Backstop margin"). Off: Family Link's own limits are left as the parent set them.
- While Unlimited is on: a whole day (1440), and the same sum again as soon as it ends.
- A kid whose Family Link daily limit is switched off (the child's Daily limit switch is off, or unavailable) is left
  alone: nothing is written. With the daily limit off, Family Link stores a written limit as the weekday's own limit
  (every week) rather than today's override, so there's nothing to back up. A child with no such switch (an older Family
  Link) is backed up as usual.
- Written with hysteresis: when the value is higher than what Hearth wrote today, or more than 30 minutes lower; never
  below a device's minutes today + 5. Through `familylink.set_daily_limit` with the child's id alone (today's
  override on each of the child's devices that take a daily limit; Family Link's `time_limit_device_ids` skips Google
  TVs, which keep Family Link's limits off on purpose: Hearth holds a TV itself). The child's id is read from the
  entity's attributes and passed as a string, never templated (Home Assistant reads 21 digits as a number).
- Nothing is written while Hearth's whole-device hold is on (daily time used up: the limit is 0) or about to start,
  checked again right before each write; after the hold lets go the backstop is written again. The hold keeps the
  weekday's own limit (the weekday number's `weekly_minutes`, not its state, which reads today's override) and puts
  that back; a value read from the state that is the backstop's or a whole day is never put back as the weekday's.
- A parent's own change: the backstop is today's override, written each day, so it wins over a weekday limit changed in
  the Family Link app (and over a today's limit they set, at Hearth's next change). Switch it off to keep Family Link's
  own limits.
- With the backstop on, the schedule's day-off and half-day minutes go to Hearth's bonus time (and from there to Family
  Link), not onto Family Link's limit directly (`bonus_family_link`).

**Family Safety (Windows, Xbox):** bonus time is mirrored as extra time where Family Safety would stop the kid sooner,
as before. Family Safety's per-day limit (set_screentime_limit with a day of the week) is a weekly setting, not today's
only, so Hearth doesn't keep it as a backstop: writing it daily would change every later same weekday and need the
put-back machinery the day-off bonus uses (temporary_limit.py). The day-off bonus still raises it for that day when
chosen (bonus_family_safety).

### Places

Where each kid is, as a place's name: Hearth keeps no coordinates and shows nothing else. Places are Home Assistant
zones, set in Configure > Places (and on Hearth's page, Family > Places):

- **Home** is always `zone.home`.
- **School** is each kid's own: a zone per kid.
- **Favorite places**: any number (up to 20) of a zone and the name to show ("Practice", "Beach house"); each gets a
  key from its name (`practice`, `beach_house`).

Each kid (everyone in the household but its adults) has a **Place** sensor, `sensor.hearth_<person>_place`. Its state
is a place key (`home`, `school`, a favorite's key), `away` (anywhere else) or unknown; its attributes are `name` (the
place's name; "Unknown", or "No location" when there's nothing to go on), `since`, `source` (`family_link` or
`person`), `accuracy` (metres), `fresh` and `as_of`. Only the state and `name` are recorded (`since`, `source`,
`accuracy`, `fresh` and `as_of` are `_unrecorded_attributes`). An integration can't keep an entity's state itself out
of the recorder: exclude `sensor.hearth_*_place` in `recorder:` to keep no history of it at all.

Where it comes from, in order:

1. The kid's **Family Link location tracker** (`device_tracker.<kid>_family_link`: the one of the child of their
   Family Link enforcer, or the one picked in Configure > Places), while its `location_timestamp` is at most 20 minutes
   old. Its latitude and longitude are set against the places' zones (their radius); a reading whose `gps_accuracy` is
   worse than the radius of a zone it could be in is ignored.
2. Else the kid's **person** entity (`home`, `not_home` or a zone's name), as of when it changed.

A router's, Wi-Fi or Bluetooth tracker (eero and the like) is never used, even if picked. With neither, the place is
unknown: stale, or "No location" when there's no Family Link tracker and no usable person state.

A change needs **two consecutive readings that agree, or three minutes of them**; going back to the place last
confirmed counts at once, and a stale reading is unknown at once (unknown never ends anything). Each confirmed change
from one place to another fires **`hearth_place`** {person, from, to} (place keys only: no coordinates, no accuracy)
and ends what ends on it ([Exceptions](#exceptions)). Place rules (pause while at a place, say) aren't built.

### Presence

Places says which place a kid is at. **Presence** (`presence.py`) adds, per kid, facts every Hearth feature can share,
each with a `value` (yes, no or unknown; a place key for `at`, people's ids for `with`), `since`, `as_of` and `sure`
(whether the readings support it now, or it's only kept through an unsure or unknown stretch):

| Fact | Meaning |
|---|---|
| `at` | The place key, read from Places unchanged |
| `with` | The household people they're with (adults and kids) |
| `with_adult` | With at least one adult |
| `apart_from_adults` | Away from home and apart from every located adult |

Where the positions come from:

- **A kid**: their Family Link location tracker only (the one Places picks), by its `location_timestamp`. A fix counts
  for 45 minutes (a still phone repeats one fix for half an hour); past that the kid is unknown.
- **An adult** (role `adult` on Hearth's page): their person entity's coordinates. Home Assistant gives no fix time for
  those, so a position's age runs from when Hearth first saw it. An adult whose person is `home` stays located however
  old the position is (a phone lying still at home reports nothing for hours); one who isn't home is left out once the
  position is 90 minutes old. An adult at `home` without coordinates counts as the centre of `zone.home`, its radius as
  the accuracy. An adult who can't be located is left out while another one is; with no adult located, or the kid
  unknown, the facts are unknown.

A router's, Wi-Fi or Bluetooth tracker is never read, as in Places.

How the facts are decided, with hysteresis and dwell:

- **With** someone: the kid's latest fix is within 150 m plus both accuracies of that person's **track** around the
  fix's time (the line between their positions just before and after it). Kids' fixes come minutes apart, and in a car
  an adult's latest position is kilometres past the kid's last fix: comparing latest to latest would call them apart.
- **Apart** from an adult: for the whole last 5 minutes, the kid and the adult were more than 300 m apart after taking
  off both accuracies.
- Between the two is unsure, and **unsure changes nothing**: a fact keeps its value.
- **Away from home**: every fix of the last 5 minutes is surely outside `zone.home` (distance minus accuracy more than
  its radius) and the kid's confirmed place isn't `home`.
- **Unknown is never a change**: a fact that goes unknown keeps the value it last confirmed and fires nothing.
- **Nothing is confirmed while the household settles** after a start (as the time limits, 90 seconds).

A confirmed change fires **`hearth_presence`** {person, fact, value}, with no coordinates and no accuracy. The kid's
Place sensor gains `with` (people's ids) and `apart_from_adults`, both `_unrecorded_attributes`. Hearth's page shows a
kid who's out on their row ("Away · apart from adults since 6:47 PM · Messages open", or "Practice · with Alex"); an
adult's own place is never shown.

Privacy: coordinates stay in memory only (each kid's latest fixes and each adult's track of the last 15 minutes, gone
on a restart; a reload of the entry keeps them). The store `hearth.presence.<entry>` holds the facts (values, people's
ids, times), the standing rules' state and, per adult, a short salted hash of their last position with when it was
first seen: a restart restores every person entity with a new change time, and a position whose hash matches the
stored one keeps its stored age, so stale can't look fresh. No history is kept and coordinates are never logged. TVs
and kids' phones get nothing of it: only the effect on their own state document (an app not held).

### Messages when away from adults

The first standing rule on the presence layer, built in and **on by default** (Family > Places, `away_messages`):
**while a kid is away from home and apart from every adult, their text app isn't held by time limits**, so a kid out
with a friend can still arrange a ride home once their daily time is used up.

- **Opens** once `apart_from_adults` is confirmed: about 5 minutes after the kid is 300 m from every adult and outside
  Home.
- **Goes back** after **10 minutes in a row with an adult or at home** (with or without an adult there). Unsure or
  unknown starts the 10 minutes over. A wrong opening is harmless (Messages open with a parent in the car); a wrong
  closing breaks the point, so opening is quick and going back needs positive evidence. A change needs 5 minutes one
  way and 10 the other, so it can't open, close and open again within 15 minutes.
- **Unknown location keeps it as it is**, for at most **6 hours**: then it goes off, so a phone with location off
  can't keep Messages open for good.
- **The app**: Google Messages, else Samsung Messages, whichever the kid's Family Link lists show installed and not
  blocked (Google Messages when the lists aren't known), plus any app an adult adds for the kid
  (`away_messages_apps`, from their installed Messaging apps). Neither installed: the rule is idle.

**What it lifts: time limits only, never something an adult scheduled or switched on.**

| Hold | Lifted? |
|---|---|
| Daily time used up (Family Link's whole-device lock) | Yes: the text app stays open and every other app is paused instead, as a category's own bonus does |
| Messaging's own limit used up | Yes |
| School time's app pause | No |
| The weekly schedule (Homework, Sleep, School) | No |
| Bedtime (Family Link's own, or a lock entity) | No |
| An adult's pause (the family's, or of the app) | No |
| A block (`hearth.block_app`, or blocked in Family Link) | No |
| A parent's own Family Link app limit | No |

While anything in the "No" rows holds the app, or the kid's devices are locked, the whole-device lock stays as it is
rather than being swapped for a pause of every other app. Calls always work whatever the rule does: the dialer and
contacts are never paused and Family Link's lock screen allows calls.

**It writes nothing of its own**: never an allow. While it's on, the household's "what lifts a budget hold" answer
includes the app (`Lifted.open_apps`), which feeds the enforcer, Family Link's backstop (120 minutes for the open app)
and the kid's state documents (the app is left out of the held groups and listed in daily time's `except`). When it
goes off, the app is simply no longer in that answer: only what the rule lifted comes back, and an adult's own
`hearth.allow` or `hearth.pause` made meanwhile is untouched. Messages keeps counting toward daily time while there is
some left. Hearth's holds still go through its enforcer only: the presence layer calls no Family Link service.

Where it shows: `hearth.explain` moves the budget hold from `blocked_by` to `lifted` and lists the rule under
`exceptions` ({`id: "rule:away_messages"`, `app`, `apps`, `since`, `until: null`, `while`: {`apart: "adults"`, `text`:
"while Sam is out without an adult"}}); the Screen time today sensor's `exceptions.rules`; the kid's row on Hearth's
page; and the activity log (`kind: rule`, once when it opens and once when it goes back). There is no push
notification: it would fire on every outing. Over a restart it comes back on or off as it was.

The household's choices for this build:

- **Home alone**: no. It opens only away from home; a kid home alone keeps their limits.
- **A sleepover past bedtime**: not in this build. Family Link's bedtime still locks the phone (calls work); opening
  Messages through it needs Family Link's own "unlimited apps during downtime".
- **School time**: Messages stays paused during School time's app pause, though the kid is away without an adult. A
  kid at school is away every school day; School time ends mid-afternoon, so the way home is covered.

### School days and day types

Configure > School days says which budget applies (the first that answers: dates typed in, an entity, a calendar,
Monday to Friday within the school year). It also knows **half days**: dates typed in, an entity state (`half` or
`half_day` by default), or a calendar event with one of the half-day words. A half day takes the other-day budget
unless chosen otherwise (as before half days were known: a helper that says `half` wasn't a school day).

The household's **Day type** sensor says today's: `school`, `half_day`, `day_off` (a weekday of the school year that
isn't a school day), `weekend` or `no_school` (a weekday outside the school year). The **School day** binary sensor
has it as `day_type` too. The calendar and the dates are the household's own: they're typed in (or come from its
calendar), never part of Hearth.

### Schedule

#### The weekly schedule

Each kid has a **week** (Monday to Sunday) and two **special days**, the Day off and the Half day, edited on the
Schedule tab of Hearth's page (between Kids and Devices) or with the services below. Kept with Home Assistant's storage
helper (`hearth.weekly.<entry>`).

- **A day is a list of changes**, `["07:45", "school"]`: at that time the kid switches into that **mode**, which runs
  until the next change. Times snap to 15 minutes, a day holds at most 12 changes, and two neighbouring changes with
  the same mode merge (removing one lets the one before run on).
- **The night carries over.** The mode that ends a day runs past midnight into the next until that day's first
  change. **Bedtime** is the Sleep that ends the day; **wake** is the next day's first change, so a day off tomorrow
  lets the kid sleep in.
- **Modes are the household's** (at most 8): a name and what it allows while it's on. Sleep (`nothing`: a bedtime
  lock; "Keep apps that aren't screen time" on), School (`school`: a School time lock) and Free time (`everything`)
  are built in; Homework (closes Games, YouTube, Streaming and Social) and Wind down (closes Games and Social) are
  starters a household can change or remove. A mode of `some` closes the groups it names. Editing a mode changes it in
  every kid's schedule; removing one removes its changes.
- **Time each day** is per day, not per mode: one limit per group (minutes; `null` is no limit, 0 is none), counted
  as the two budgets were. Bonuses, chores, extra time and history work as before.
- **Which day a date uses** follows its day type ([School days and day types](#school-days-and-day-types)): a school
  day or a weekend day uses its weekday (an extra school day on a weekend uses Friday's); a day off and a weekday
  outside the school year (summer) use the Day off; a half day uses its weekday's changes with School ending at the
  Half day's "School ends at" time (12:00 by default), then whatever came after School, and the Day off's limits (or
  the weekday's).
- **Today only.** A change for today copies today's day and changes it (a later bedtime, Homework until 5, today's
  limits); it ends at midnight, and Back to the schedule (`hearth.resume_schedule`) ends it sooner. The weekly day
  stays as it is.
- **Copy** a day to other days (with or without its times or its limits), or a kid's week or one day to other kids.
  What's copied replaces what was there; every edit returns an undo token, and the page offers Undo.

**The migration, and a household that hasn't set one up.** Until an adult edits a kid's schedule, it is their two
budgets worked out when asked: the school-day budget on Monday to Friday, the other-day budget on Saturday, Sunday and
the Day off, the half day's limits as Configure > School days' `half_day_budget` says, and the half day's School ending
as many hours early as Configure > Schedule's `half_day_hours_early` says. It has **no changes**, so nothing of the
schedule holds anything: bedtime and School time come from the lock entities (Family Link's) exactly as before, and
the limits are the budgets. The first edit keeps that migration and changes it. From then on the two budgets
(`hearth.set_budget`, the budget numbers, the Kids tab's table) read Monday's and Saturday's limits and write Monday to
Friday, or Saturday, Sunday and the Day off. Configure > Schedule's day-off and half-day actions on Family Link (below)
carry on as they are.

**What Hearth holds for it.** Hearth's own holds, below, and once an adult starts it, the kid's bedtime and wake kept in
step in Family Link's bedtime and Family Safety's allowed hours ([Bedtime sync](#bedtime-sync)). School time, daily
limits and Nintendo's schedule aren't written from the schedule.

- **Sleep and School are locks.** The kid's state document says `locked`, with `lock` `{by: ["schedule"], kind:
  bedtime | school_time, until}`; an allow doesn't lift them (change today or take School off instead; a School time
  taken off with `hearth.school_time_off` lifts the schedule's School too). Family Safety's chosen platforms are
  locked and the Switch is held during them; Family Link keeps its own School time, and its bedtime follows the
  schedule's once bedtime sync is on. While Sleep holds and Family Link has no bedtime running for the kid, Hearth
  locks their Family Link devices whole itself (`sleep_locks_devices`): when none of their Bedtime active sensors names
  a window, or when one names a window but none is on once Sleep (or the end of a bedtime lift) has been on 10
  minutes. That's the cover for the gaps (a write that didn't take, a bedtime switched off in the app, a day off
  learned that morning). An adult's extra time at bedtime lifts Sleep while it lasts ([Extra time at
  bedtime](#extra-time-at-bedtime)).
- **A closed group** (Homework, Wind down) is a hold, as a group out of time is: on Hearth's TVs and phones it's a
  paused group, `{id: "schedule:games", name: "Games (Homework until 5 PM)", minutes_left: 0, apps, paused: {until,
  reason: "Homework", name}}`, so a device holds it and offers no ask for more; Family Link pauses its apps; Family
  Safety locks a chosen platform when one of its groups is closed and pauses the group's Xbox and Windows apps; the
  Switch is held when one of its groups is closed. `hearth.allow` for the group or an app lifts it. More minutes don't
  open it; its end does. Why: `schedule` in the summary's `sync`.
- **`next_lock`** is the schedule's next Sleep or School (`{at, by: "schedule", kind}`) when it comes before the lock
  entities' own (not a School that School time taken off today covers); a kid's Today line and the suggestions' cutoff use the schedule's bedtime.
- A **family pause** still locks everything, whatever the mode.

**Each kid's schedule now** is in the household summary and their state document as `schedule` (only while their
schedule has changes): `{mode {id, name, allows, since, until, closed}, next {at, mode, name}, bedtime {at, wake},
day {date, uses: mon… | day_off | half_day, changed_today}}`. Added fields only: the contract stays at 2.

**Entities and events.** `sensor.hearth_<kid>_mode` (an enum of the mode ids; attributes `name`, `since`, `until`,
`next` {at, mode}, `today_changed`, `source`: `schedule`, or `locks` while the schedule has no changes and the mode
comes from the lock entities) and `sensor.hearth_<kid>_bedtime` (a timestamp, tonight's bedtime, with `wake`).
`hearth_mode` {person, mode, mode_name, previous, until} fires when a kid's mode changes (within the minute), and on a
today-only change that changes it. `hearth_schedule_changed` {person, days, today_only, by: panel | service |
family_link | family_safety | import} fires on each edit (`family_link` and `family_safety`: tonight following a
parent's change in that app; `import`: the first bedtime sync's import).

**Services** (adults only, as every Hearth service):

| Service | Fields | Returns |
|---|---|---|
| `hearth.set_schedule` | `people`; `days` (`mon`…`sun`, `day_off`, `school_days`, `weekend`, `every_day`, and for bedtimes `school_nights` (Sunday to Thursday) and `weekend_nights` (Friday and Saturday)); `changes` [{at, mode}]; or `bedtime` and/or `wake` (the days' last Sleep and first change move; not with `changes`); `limits` {group: minutes or null} (merged: a group not given keeps its limit); `half_day_ends`; `half_day_limits` (`day_off` or `weekday`) | `undo`, each person's schedule |
| `hearth.copy_schedule` | `from`; `day` (empty: the whole week, to people); `to_people` or `to_days`; `times`, `limits` (both on by default) | `undo` |
| `hearth.change_today` | `people`; `bedtime`, or `mode` (from now) and `until` (the next change by default), or `changes`; `wake` (tomorrow morning only, with or without `bedtime`; refused with no bedtime tonight); `limits`; `reason` | `undo` per person |
| `hearth.resume_schedule` | `people` | `resumed` |
| `hearth.get_schedule` | `person`; `date` or `day` | the day: `changes`, `limits`, `bedtime`, `wake`, `uses`, `changed_today`, and `now` for today; `sync` (bedtime sync) for a kid it's for |
| `hearth.sync_bedtimes` | `people` (every kid with Family Link or Family Safety); `start_from`: `auto` (default), `hearth`, `family_link`, `family_safety`; `dry_run`; `stop`; `family_link_bedtime_on` | per kid: the preview (`state`, `start_from`, `import`, `family_link` and `family_safety` plans `[{day, scope, start, end, was, write}]`, `unsupported`, `switch_on`) and `started`, `undo` (an import); for a kid already in step, its sync status |
| `hearth.bedtime_offer` | `id`, `accept` | `person`, `accepted`, `day`, `undo` |

The page's WebSocket commands: `hearth/schedule/get`, `set`, `copy`, `undo`, `today`, `resume`, `mode`,
`mode/remove`, `bedtime` (`{person, scope: today | days, days, bedtime, wake}`), `sync` (status and the first sync's
preview), `sync/start` (start, check now, stop, or Family Link's bedtime back on) and `sync/offer` (administrators
only, as the rest of the page). `panel_view` gives each kid `bedtime` (`days` {mon…sun, day_off: {bedtime, wake}},
`tonight` {bedtime, wake, usual_bedtime, usual_wake, changed}) and `sync`.

School time, the daily limits and the Switch's schedule aren't written from the weekly schedule yet.

#### Bedtime sync

Bedtime sync (`bedtime_sync.py`) keeps each kid's bedtime and wake in step in Family Link's bedtime and Family Safety's
allowed hours, so the phones, tablets, Xbox and Windows follow the one schedule. Kept with Home Assistant's storage
helper (`hearth.bedtime_sync.<entry>`).

**The model: a weekly baseline plus a dated override.** The baseline is the plain week (Monday to Sunday as edited):
each weekday's **night** (its last change when that's a Sleep, until the next day's first change that allows
something) and each weekday's **window** (from the end of the night carried in to the start of the day's last Sleep;
a Sleep in the middle of the day isn't in either). The override is today's: today's night and window as today really
resolves (a tonight-only change, a tonight-only wake, a day off, a half day, tomorrow's day type). When today matches
its weekday, nothing dated is written.

- **Family Link**: one weekly slot per weekday (`familylink.set_bedtime`, weekly, `day` "1" Monday to "7" Sunday,
  keyed by the weekday the night starts on; its end is the next morning), exact to the minute; and a tonight-only
  override (`scope: today`, only ever with today's weekday) when tonight differs. Hearth expects Family Link's own
  strict mode (re-asserting hours set from Home Assistant) to be off: it would undo a parent's change before Hearth
  sees it.
- **Family Safety**: per platform of the kid's Family Safety enforcer (Windows, Xbox), one allowed window per weekday
  (`set_screentime_intervals` with `day_of_week`, 0 Sunday), **rounded outward to the half hour** (begin down, end up:
  a 9:15 PM bedtime allows until 9:30 PM). Hearth's own platform lock is exact to the minute during Sleep; the allowed
  hours are the backstop for when Home Assistant is down, and one stricter than Hearth would lock a kid Hearth says is
  free. Today's window differing from its weekday is written today only (`today_only: true`, put back by the
  integration at midnight); a Family Safety without `today_only` (upstream's) gets the weekday's setting, put back
  after midnight by Hearth as extra time's moved end is. Not on Windows while Family Safety keeps a saved schedule.
  The Xbox goes through the Xbox Family Settings sign-in; without it, the Xbox's targets fail and the rest goes on.

**The three lanes.**

| Lane | Service | On the page | Family Link | Family Safety |
|---|---|---|---|---|
| Tonight only | `hearth.change_today` (`bedtime`, `wake`) | "Change tonight" on the Bedtime card | `scope: today` | `today_only: true` |
| Every Wednesday | `hearth.set_schedule` (`days: [wed]`, `bedtime` / `wake`) | tap the Wed chip | that weekly slot only (and Tuesday's when Wednesday's wake moved) | `day_of_week` 3 only |
| Every day, school nights, weekend nights | `hearth.set_schedule` (`days: [every_day]`, `[school_nights]`, `[weekend_nights]`) | the chip sheet's "Apply to" | each slot that changed | each day that changed |

A tonight-only change ends at midnight (Family Link's override was that night's only; Family Safety's today-only is
put back at midnight); Back to the schedule or Undo ends it sooner, and the weekday's hours are written again today
only. A weekday changed for good while a tonight-only change is in force keeps tonight's: Family Safety's weekly write
drops a pending today-only value, so tonight's is written again after it. The Day off and the Half day aren't weekdays
in any app: editing them changes no baseline, only the override on the dates that use them. A day off known only on
the day (the school calendar) can't move last night's end any more: Hearth's Sleep still runs to the Day off's wake,
and the gap is held by Hearth's own device lock.

**By state, never by event.** A ledger keeps, per target (kid, service, platform, weekday, and one "today"), what
Hearth wants, what it last wrote (saved before the call), when, and when a reading first confirmed it. A write happens
only when the want differs from what was written (an edit, a new day, a day type change), on a bounded retry, or when
an adult asks ("Check now", "Put Hearth's back"); a reading never causes a write by itself, and a reading equal to
what was written is Hearth's own echo. A value no reading shows within 10 minutes didn't take: tried again after 5
minutes, then doubling to an hour; after three tries the adults are told once. A service not loaded yet is tried again
in 30 seconds; a schema refusal is `unsupported` and not retried. One target failing never stops another, another
service or another kid, and Hearth's own holds never wait for a sync. Writes are one at a time per kid, 2 seconds
apart, each followed by a refresh of the integration's entities. Nothing is written in the first minutes after Home
Assistant starts (as Hearth's other let-gos); then every target is read and compared: what Hearth wrote or wants is
in sync (a missing ledger entry is filled in), a confirmed value that differs is a parent's change made while Home
Assistant was off, an unconfirmed one is written again. The sync runs each minute, at 00:01, at 03:10 and when extra
time at bedtime ends.

**The first sync**, only after an adult confirms a preview. Every kid with a Family Link or Family Safety enforcer
starts in `review`: nothing is written to the apps, and Home Assistant's bell says "Bedtimes can now be kept in step".
The Bedtime card shows, per weekday, the bedtime and wake each kid would get and how many nights and days each app
gets; one button starts it (`hearth.sync_bedtimes`). The direction is chosen per kid and can be flipped:

- **A kid whose schedule has a Sleep** is pushed from Hearth.
- **A kid without one** (their mode comes from the lock entities) first **imports** the apps' bedtime into Hearth's
  schedule: Family Link's when its bedtime is on (each slot's start is that weekday's Sleep, its end the next day's
  wake), else Family Safety's (bedtime the earliest allowed end among the platforms, wake the latest begin). The Day
  off gets Saturday's wake and Sunday's bedtime, so no day is Sleep from start to end. Times snap to 15 minutes, and a
  time that moved is written back. The import is one edit with one undo token, and fires `hearth_schedule_changed`
  (`by: import`). Then the other service is written: the Xbox and Windows follow Family Link's hours.
- **A kid with neither** stays in `review` quietly until their schedule gets a Sleep.

**Family Link's bedtime switch.** When sync owns a kid's bedtime and Family Link's bedtime switch is off, the first
sync writes the seven weekly slots and then switches it on (`familylink.enable_bedtime`), as the preview says.
Hearth's whole-device lock stays only as the cover for the gaps.

**A change made in a parents' app** is an adult's: the latest change wins, Hearth never writes over it unasked, and it
shows on the "?" ("Bedtime 10 PM tonight · changed in Family Link · 8:05 PM", `note_origin` kind `bedtime`).

- A value is a parent's only when it was confirmed before, no write is pending, the last write is older than the
  quiet time (Family Link 3 minutes, Family Safety 1), the reading isn't Hearth's other writers' (a bedtime lift's
  moved start, extra time's moved end, Hearth's own today window of that weekday), and two readings a minute apart
  agree.
- **Today's weekday changed** (Family Link's slot, or a Family Safety platform's day): tonight follows it
  (`Week.change_today`, by the app; Family Link's end becomes tomorrow's wake), so every other service follows too,
  and the app it came from isn't written tonight. Plus an **offer**: make it every week.
- **Another weekday changed**: the offer only; still unanswered when that weekday comes, that night follows it.
- **Tonight only in the app** (Family Link's window tonight changed, its weekly slot not): tonight follows it, no
  offer.
- **Family Link's bedtime switched off**: tonight's bedtime is lifted (as extra time at bedtime does, until the
  wake), and Hearth doesn't switch it back on. The Bedtime card says "Bedtime is switched off in Family Link" with
  "Turn it back on" (`hearth.sync_bedtimes` with `family_link_bedtime_on`). From the next night Hearth's own Sleep
  holds, with its device lock.
- **A Family Safety day with several windows** can't be kept in step: `differs`, with "Put Hearth's back".

An **offer** is `{id, person, via, platform, day, bedtime, wake, was {bedtime, wake}, adoptable, at}`, told once to
the adults' phones with both answers as buttons. Accepting (`hearth.bedtime_offer`, `accept: true`) sets that weekday
in Hearth's schedule (every other service follows); declining writes Hearth's back to that app. Either drops tonight's
change the app's change made. An adult changing that weekday in Hearth meanwhile answers it too (Hearth's wins).

**Extra time at bedtime and other writers.** While extra time lifts a kid's bedtime, sync doesn't write Family Link's
tonight entry for them (weekly slots are still written); when the lift ends, it writes tonight's only if what the lift
put back isn't what tonight should be. While extra time has moved a Family Safety platform's end today, sync doesn't
write that platform's today window. A pause writes neither app's schedule.

**Limits.** Flagged on the card (`unsupported`), not synced; Hearth's own holds still apply:

- A weekday with no Sleep at its end: Family Link keeps the hours it has (it has no per-day off switch); Family Safety
  allows that day until midnight.
- A night that runs past the next day (a day that starts asleep and stays so): not a Family Link slot.
- A Sleep in the middle of the day: not written anywhere.

**Status and events.** Per target and per service (the worst of its targets): `in_sync`, `writing`, `waiting` (with
the reason and when it's tried next), `differs`, `failed`, `unsupported`, `off`. In the household summary and
`hearth.get_schedule` as `bedtime_sync` / `sync`: `{state: review | on | off, services: [{via, platform, status,
reason, next_try, days, tonight}], offers}`; `hearth.explain` adds `bedtime_sync` lines for each service not in step.
`hearth_bedtime_sync` fires `{person, action, via, platform, scope: weekly | today | switch, day, start, end, reason}`,
`action` one of `written`, `confirmed`, `failed`, `outside_change`, `offer`, `offer_answered`, `started`,
`stopped`; it carries no account or child ids. The page's capabilities gain `family_link` {`bedtime_weekly`,
`bedtime_today`} (its `set_bedtime` schema takes `scope`); without `bedtime_today`, tonight-only changes reach Family
Link only through Hearth's own holds. `hearth.sync_bedtimes` with `stop` sets a kid `off`: nothing more is written and
nothing is put back (the apps keep the hours they have).

#### Configure > Schedule

Configure > Schedule says what each day type does to the kids' Family Link (everyone with Family Link in Enforce, or
the people chosen):

- **Day off: School time off.** At 00:05 each kid's School time switch is turned off (`switch.turn_off`, which turns
  off the weekly School time with today's) and noted to be put back.
- **Half day: School time ends N hours early**, today only (`familylink.set_school_time`, scope `today`, from the
  weekly start to the weekly end less N), for a kid whose School time is on; one whose School time is off gets the
  early end when it's put back.
- **Extra minutes** on days off and on half days: as Family Link's daily limit for today (`familylink.set_daily_limit`
  with the child's id and no day: the weekday's limit plus the extra, an override that ends by itself; only while the
  child's daily limit is on), and/or as Hearth bonus minutes on a group. Family Link's way is the default, as that is
  what a household's own "extra hour" automation did: it raises the phone's own limit. A Hearth bonus raises a Hearth
  budget instead.
- **Family Safety (Windows, Xbox)** gets the same extra minutes, Family Link's way, when "Extra minutes as Family
  Safety's daily limits today" (`bonus_family_safety`) is on. It's off by default, apart from Family Link's, so a
  schedule set up before it existed doesn't start raising Windows and Xbox limits. For a kid with a Family Safety
  enforcer (the chosen people, or everyone with Family Safety), its Windows and Xbox platforms each get this weekday's
  limit plus the extra (at most 24 hours), through upstream's `microsoft_family_safety.set_screentime_limit` with the
  kid's entity (an older Family Safety: its account id), `day_of_week` (today's; Family Safety counts 0 as Sunday),
  `platform`, `hours` and `minutes`. The limit read is the integration's per-day limit number of the platform (Windows'
  "<name> Thursday Limit", unique id `<entry>_<account>_limit_thursday`; the Xbox's "<name> Xbox Thursday Limit",
  `<entry>_<account>_xbox_limit_thursday`, there once the kid's Xbox schedule is on): a parent's change of the weekday
  before Hearth's is what the extra goes on top of. A platform without a limit that day (24 hours) is left alone, as
  is Mobile (it has no weekday limit). The weekday's limit is a setting, not today's alone, so it's a **temporary
  limit** Hearth puts back itself, the same way as the Switch's (`temporary_limit.py`): before writing, it records the
  limit it added to, the one it writes, the day and weekday, the platform and the kid, kept across a restart and
  midnight (never added to twice). It puts the recorded weekday's limit back 2 minutes before midnight, at once when
  today's day off is called off (`hearth.school_time_off_cancel` for today, on a day off, for the people named or
  everyone; with or without School time taken off) or today's day type changes away from a day off or half day (then
  it isn't raised again that day; Family Link's extra minutes stay), or on the next start when Home Assistant was off
  then (the recorded weekday's, not the new day's). Only while the limit still reads Hearth's: a limit a parent changed
  since stays. The Xbox's write goes through the Xbox Family Settings sign-in and fails without it: a failed call is
  never taken as done (it's logged and tried again while it's still today, and nothing is put back for it), doesn't
  hold up Family Link or another kid, and the 06:00 check tells the adults about a platform still not raised. A Family
  Safety without `set_screentime_limit` is skipped quietly. School time has no Family Safety equivalent. These day-type
  actions don't touch the allowed hours (`set_screentime_intervals`): for a kid whose bedtime is kept in step, the
  allowed hours follow the weekly schedule's bedtime and wake through [Bedtime sync](#bedtime-sync) (a day off's later
  wake included, as a today-only window); otherwise they're left alone. `restore_today_only` is never used; today-only
  windows are written by bedtime sync and by extra time that runs past today's allowed hours (Extra time on one
  device, above). Nor does it use Family Safety's
  account lock switch (`lock_account`), which saves the limits it finds as its restore point: switched on on a bonus
  day, it would save (and later put back) the raised value. If a parent uses it then, Hearth's put-back still only
  fires while the limit reads Hearth's value.
- **Nintendo Switch** gets the same extra minutes when "Extra minutes on the Switch's limit today"
  (`bonus_nintendo`) is on (off by default, as Family Safety's). Each Switch of a chosen kid's Nintendo enforcer (its
  Max screentime today) gets today's limit plus the extra, at most 360 minutes (the Switch's own maximum), once a day:
  a Switch two kids share is raised once, for both. Nintendo has no today-only limit (the number is the Switch's
  setting of every day, or of this weekday), so Hearth puts it back itself, as the Nintendo enforcer does: 2 minutes
  before midnight, and only while the Switch still reads the limit Hearth set (a parent's change in the Nintendo app
  since stays). It's a temporary limit, as Family Safety's above: it keeps the limit it added to (with the day,
  weekday, device and bedtime) across a restart, so it never adds to its own value twice, a failed write isn't taken
  as done (tried again while it's still today), and if Home Assistant was off over midnight a Switch with a limit per weekday
  gets that weekday's limit and bedtime back through `nintendo_parental_controls.update_daily_restrictions`. A Switch
  with no limit (-1) is left alone, as is one at 360 already. While bonus time from the Nintendo app runs the Switch
  refuses a new limit, so Hearth waits. **While Hearth holds the Switch** (limit 0, for a budget or a pause) nothing is
  written to it: the extra goes into the limit the hold puts back, so letting go gives the raised limit, and a cancel
  or midnight takes it out again. A cancel (`hearth.school_time_off_cancel` for today on a day off, when it names all
  the Switch's kids) or today's day type changing away from a day off or half day puts the limit back at once, under
  the same rules, and it isn't raised again that day.
- `hearth.school_time_off` (`people`; `date`, today by default; `from`, a time; `reason`) does the same for anyone,
  any day; `hearth.school_time_off_cancel` (`people`, `date`) drops one not started, or puts one already off back from
  today.
- `hearth.set_school_time` (`people`; `days`: `mon`…`sun`, `school_days` (the default) or `every_day`; `start` and
  `end`, or `like` another kid; `switch_on`) sets the weekly Family Link School time of those weekdays
  (`familylink.set_school_time`, weekly scope, one call a day, recorded as Hearth's own with `why: school_hours`). A day
  already at those hours isn't written; with `like`, a day the other kid has no School time is skipped; Family Link
  refuses a day that has no School time slot yet, and one day failing doesn't stop the rest. `switch_on` switches the
  kids' School time on as a School time off is put back (below): on a school day, inside the window, pinned at once;
  kept over a restart. Answers, per kid, `set`, `same`, `failed`, `skipped` and `switch_on` (the date it may come on
  from, or `already`).
- `hearth.home_today` (`people`; `date`, a school or half day, today by default; `reason`) keeps kids home, a sick day:
  that day is a day off for them alone. Their weekly schedule and limits are the Day off's (the other days' budgets),
  and with Family Link their School time is taken off for the whole day, as `hearth.school_time_off` does. The household's
  day type doesn't change, and none of a day off's extra time is given. `hearth.home_today_cancel` (`people`, `date`)
  makes it a school day again; School time comes back as with `hearth.school_time_off_cancel` (which also cancels any
  other School time off of theirs that day). Each kid's **School today** sensor (`sensor.hearth_<kid>_school_today`:
  `school`, `half_day`, `off` or `home_today`, with today's School time window) is described in
  `docs/contracts/people-entities.md`.

**Putting School time back.** Switching School time on outside a kid's window opens a window from then until 23:59,
so Hearth switches it on only on a school day (or half day), inside the kid's own weekly window for today (read from
Family Link's time entities, and kept when it was turned off in case they read unknown meanwhile; N hours shorter on a
half day), and at once pins today's window to those hours (`set_school_time`, scope `today`). Each minute it checks
the devices' `schooltime_end` and pins again until they say the pinned end; then it's done. A kid whose window has
ended is left for the next school day. Switched on or pinned, it waits two minutes before doing either again (Family
Link is read once a minute).

**Checks.** At 06:00 a School time that should be off and isn't is turned off again, and the adults are told what
didn't apply (the extra time, too, Family Safety's by platform). At the watchdog time (10:00 by default) on a school
day, they're told about anyone whose School time is still off, unless it was taken off for today. "Told" is a
notification in Home Assistant and the schedule's phone (else the one that answers requests for more time). Each step
fires `hearth_schedule` (action:
`school_time_off`, `school_time_back`, `half_day`, `bonus`, `bonus_back`, `site_list`, `site_list_failed`; person;
details; for the website list `via`: `family_link` or `family_safety`; Family Safety's `bonus` and `bonus_back` have
`via: family_safety` and `platform`). Each action runs once a day; what's pending is kept across
restarts.

**Website block list** (Configure > Website block list): an https address, a time (07:30 by default) and the people
(everyone with Family Link or Family Safety by default). Every day at that time, Hearth calls `familylink.sync_site_list`
(entity: the person's Family Link entity, url) and `microsoft_family_safety.sync_site_list` (the person's Family Safety
entity or account id, url) for each, one after another; each side is on its own: a failure for one is logged, fires
`site_list_failed` (with `via`) and is tried again 5 minutes later, and the other side and the other people go on.
Those services add the list's new domains and remove only what the list itself added before. For example
`https://example.com/blocklist.txt`.

**A Family Safety without `sync_site_list`** (the released one, upstream's 2.3.0) is kept in step by Hearth itself,
with its `get_sites`, `block_website` and `remove_website`. The list is downloaded once per run (https only, redirects
not followed, at most 1 MiB and 2000 domains) and read as plain text, one domain per line, `#` comments allowed (a
hosts-file line such as `0.0.0.0 example.com` gives its last word); anything that isn't a plain domain is ignored.
For each kid, the blocked and allowed sites are read with `get_sites`; listed domains not blocked yet are blocked with
one `block_website` call (a domain that shares a site with an allowed one is left out); only domains Hearth itself
blocked from that list for that kid, and that the list has since dropped, are unblocked with `remove_website` (not
`allow_website`, which would put them on the allowed list). What Hearth added is kept with the schedule in Home
Assistant's storage, so a restart keeps it; a site removed by hand meanwhile isn't Hearth's any more, and sites
Hearth didn't add are never touched. A fork's own record of what its `sync_site_list` added is taken over the first
time. Nothing changes when the download fails or has no usable domain, when Microsoft's answer has lost every site
the list added, or when the list would take back more than half of what it added (at least 20): `site_list_failed`.
Family Safety tries every site and names the ones that failed, with Microsoft's error: Hearth's `site_list` event
then has `by: hearth`, `added`, `removed`, `kept`, `skipped_allowed` and `failed` (`[{site, error}]`), the failed ones
are logged and tried again the next day; when every site failed it's a `site_list_failed`, tried again 5 minutes
later. With neither service, Family Safety is skipped quietly.

**Copy websites** (`hearth.copy_sites`): copies a kid's websites between Family Link and Family Safety. `people`
(everyone with both in Configure > Enforce by default), `from` (`family_link`, `family_safety` or `both`, the
default), `lists` (`blocked`, the default, `allowed` or `both`), `dry_run` (false). Both sides are read with their
`get_sites`; a site is compared by its host (lowercase, no scheme, leading `www.` or `*.`, or trailing slash). It only
ever adds: a pattern with a path or another wildcard isn't copied (`not_copyable`: making it a whole site would widen
it), a site either side's list sync added is left to it (`skipped_from_list`), and a site blocked on one side and
allowed on the other stays as it is on both (`conflicts`). A blocked site goes to Family Link as its list sync writes a
domain (`*.example.org` and `example.org`, `block_site`), an allowed one as the site only (`allow_site`); Family Safety
gets the host (`block_website` / `allow_website`). Returns, per person, `{added_to_fl, added_to_fs}` (by list),
`skipped_from_list`, `conflicts` (`{site, family_link, family_safety}`), `not_copyable` (`{site, from, list}`), and
`error` when a side refused; a person without both sides (or with a Family Safety too old for `get_sites`) gets
`{"missing": [...]}`. With `dry_run` it says the same and writes nothing.

**Block a website** (`hearth.block_site`, `hearth.unblock_site`): an adult's own blocks of websites, next to the daily
list. `people` (everyone with Family Link or Family Safety in Configure > Enforce by default) and `sites` (one domain
or a list, such as `example.com`). A web address is cut down to its domain (lowercase, no scheme, path, port or
leading `www.`); an IP address, a wildcard or a bare suffix such as `co.uk` is refused. Each kid's sides are read
first with their `get_sites`. Family Link gets both `*.example.com` and `example.com` (`familylink.block_site`: Google
doesn't say whether the wildcard covers the bare domain); Family Safety gets the domain (`block_website`). Returns,
per person and side (`family_link`, `family_safety`), `done`, `already` and `failed` (`[{site, error}]`); a side that
fails is told and the other side and the other kids go on. What Hearth's block added is kept with the schedule (over a
restart and a reload) and shown on the kid's screen-time sensor, under `exceptions.blocked_sites` (`{family_link:
[...], family_safety: [...]}`); a site is recorded once its call succeeded. `hearth.unblock_site` removes only that
(`familylink.remove_site`, `remove_website`) and answers `done`, `already`, `failed` and `kept` (`[{site, reason}]`):
a block made in the Family Link or Family Safety app stays (`blocked outside Hearth`; with Family Link, a parent's own
`*.example.com` next to Hearth's `example.com` too, with its `patterns`), and so does a site the website list added
(`on the website list`). With the daily list: a hand block of a site the list added is Hearth's too, so when the list
drops it, it stays blocked (Hearth's own Family Safety sync leaves it out of what it takes back; around Family Link's
and a Family Safety fork's `sync_site_list`, Hearth reads the kid's sites before and blocks again right after what the
sync took out of a hand block); it is the hand block's alone from then on. A hand unblock of a site the list added
leaves it blocked and lets the list have it. A site blocked by hand before the list had it isn't the list's (the list
adds only what isn't blocked yet): a hand unblock removes it, and the next daily sync blocks it again as the list's.
Hearth's calls go to its action log as its own; outside changes (`outside_apps`) look at apps only, never at websites.

## Data out

### What a device gets

The answer to each status post carries the person's (or, on a TV, each profile's) **state document**:

```json
{
  "profiles": {
    "user:10": {
      "person": "person.sam",
      "groups": [
        {"id": "youtube", "name": "YouTube", "minutes_left": 25, "apps": ["com.thesiegs.hearthtube"]},
        {
          "id": "pause:group:games",
          "name": "Games (paused: Homework)",
          "minutes_left": 0,
          "apps": ["com.example.game"],
          "paused": {"until": "2026-10-26T19:30:00-05:00", "reason": "Homework", "name": "Games"}
        }
      ],
      "locked": true,
      "pause": {"until": "2026-10-26T19:00:00-05:00", "reason": "Dinner"},
      "lock": {"by": ["pause"], "kind": "pause", "kinds": ["pause"], "until": "2026-10-26T19:00:00-05:00"},
      "share_app_data": false,
      "request": {"id": "…", "status": "approved", "minutes": 15, "asked_minutes": 15, "group": "all"},
      "youtube_blocks": {"videos": [], "channels": [], "words": [], "labels": {}}
    }
  },
  "youtube_blocks": {"user:10": {"videos": [], "channels": [], "words": [], "labels": {}}},
  "people": {"user:10": "person.sam", "user:0:alex": "person.alex"},
  "adult_phones": {"user:0:alex": ["mobile_app_alex_phone"]},
  "parent_pins_version": "…",
  "version": "3f9c1a0b2d4e5f60",
  "contract": 3
}
```

`groups` lists only groups with a budget, and an adult's pauses of one app or group as groups with no time left and
`paused` (see [Pause and locks](#pause-and-locks)): hold them like any group out of time, but say it's paused and
**never offer to ask for more time for one**; a category that's off today (its limit 0, `time.categories` `closed`)
has `closed: true`: bonus time doesn't open it, so offer no ask for it either (an ask for it is refused, 400 `closed`);
`minutes_left` null is no limit; All screen time may carry `except`, the apps
it never holds (a Not screen time group's, and the accessibility apps). `never_held` (only when there are any) lists
the accessibility apps, which no group's `apps` holds: a device may spare them from a lock or a pause too. Each person's part is described under [Ask for more](#ask-for-more) and
[Pause and locks](#pause-and-locks); an allow of theirs that ends on a place is in `allow_ends` [{id, app, group,
until, text: "ends when you get home"}] (never where they are); a TV's also has every mapped profile's `youtube_blocks`, `people` (each mapped
profile of that TV by its own key, with its person: a notification's `for` may name a person, and the TV finds their
profile here), `adult_phones` (only when there are any: each mapped profile whose person is an adult on Hearth's page,
by the TV's own key, with the notify services of that person's companion apps, as for requests; the TV's phone
approval asks them when no phone was chosen for the profile on any TV of the household) and the
[parent PINs](#the-devices-side-of-the-api). Own-limit titles (`open_titles`) aren't built. A TV gets it in the answer to each post (at least every 2 minutes while it's
on); `version`, a hash of the content, lets it skip an unchanged one. This replaces `sensor.hearth_allowance`:
same meaning, from the integration instead of a template.

A **phone** gets its person's part of the same document, in the answer to each post and pushed when it changes (see
[Away from home](#away-from-home)). Each person's part also says `share_app_data`, always false since sharing app data was
retired (it replaced `tile_exchange_share` in contract 3, which is no longer sent). A phone's document (and `hearth/me`)
also has `category_values`, Hearth's own app-category values table, versioned `hearth.values/1`
([contracts/device-api.md](contracts/device-api.md#category_values-additive-within-contract-3)); a TV's doesn't.
Since contract 3 a device paired with a client also gets `client_settings`, `{"<scope>/<name>": "<etag>"}` for the
documents it may read ([contracts/client-settings.md](contracts/client-settings.md)): they're part of the document's
`version`, so a change to one wakes its wait and push ping. And `playing`: what they're
playing now, anywhere Hearth sees it, as in the household summary's `playing` (so a TV profile's part, a phone's and
`hearth/me` all have it).

**Pop-ups** (v1 built): `hearth.notify` (`devices`, `people`, `household`; `title`, `message`, optional `duration` in
seconds). It goes through [Attention](#attention) like every Hearth notice (announced as `hearth_notice` of kind
`notify`), so it's refused, like every `hearth.*` service, for a user who isn't an administrator or an adult on
Hearth's page (an automation's call, with no user, may). Targets:

- `devices`: a Hearth TV (its device or Hearth device id) gets it as a notice in its state document (`notices`), which
  pops up in its adult profiles; a TV whose Hearth doesn't show notices (cap `notices`), a panel or an unknown device is
  refused. A companion-app device gets a notification on that app. A paired Hearth phone has no message channel of its
  own: its person's companion apps get it.
- `people`: each person's companion apps (as the adults' phones get requests), and an adult's profiles on the TVs.
- `household`: everyone on Hearth's page (adults and kids) on their companion apps, and every TV that shows notices.

With `duration` it's taken off the phones and TVs then; without, a phone keeps it until it's swiped away and a TV for a
day. It answers the item keys, the notify services told and the TVs that show it; nobody to tell is an error. Not in
v1: **buttons** (`actions`), `position`, `image` and `camera`, and a pop-up in a kid's TV profile: the TV shows
Hearth's notices in adult profiles only, so that needs a change on the TV. The port 7676 pop-ups (Notifications for
Android TV) are unchanged and separate.

**Family pause**: `hearth.pause` (minutes, reason, people or everyone) and `hearth.pause_end`: the devices show the pause
and stop playing; replaces the hand-made pause helpers and scripts.

### Approvals

Not built yet (only [Ask for more](#ask-for-more) goes through the integration so far).

1. A device posts "profile P wants to log in on TV T" (or "the Parent PIN prompt is up").
2. The integration sends an actionable notification to the `mobile_app` devices of the persons allowed to approve
   (mapped to P, or every adult for the Parent PIN), and the matching `persistent_notification`.
3. Allow or Deny answers the device's waiting request (the answer to its next poll). The TV enters the saved PIN as it
   does now. The device never learns which phone answered, and needs no WebSocket or token.

Who can approve doesn't change.

### Household sync mailbox

Not built yet. [household-sync.md](https://github.com/theSiegs/HearthTV/blob/master/docs/household-sync.md): `POST .../household/outbox` and `GET .../household/inbox?since=<version>`,
sealed blobs the integration can't read (it never has the household key), kept with Home Assistant's storage helper so
they survive restarts, 2 MB per household, oldest dropped first. Pictures don't go through it. Devices still exchange
directly on the home network; the mailbox is for devices that are rarely on at the same time.

### Contract

`contract` (an integer, now 3) says which shape of the device API and the household summary this is: in the approved
pair answer, every status answer (`{"ok": true, "contract": 3, "state": {...}}`), every state document and the
summary. A device may send its own in its status (`contract`). It goes up only when a field changes meaning or type,
becomes required, or goes away; an added field doesn't change it, so a reader ignores fields it doesn't know. It's
apart from `version`, which changes with the content. A phone's person document also says `kind` (`kid`, `adult` or
`person`) and `kind_set` (whether an adult set it on Hearth's page). Only an adult (on Hearth's page) has a parent PIN.
The summary is for administrators and for adults on Hearth's page whose person is their Home Assistant user (without
pairing codes); `hearth.add_bonus` and `hearth.set_budget` take a group's name as well as its id. Contract 2 added the
summary's `headline`, `lines` and `actions` (per person) and `household` ([below](#contract-2-headline-lines-actions)):
added fields, so nothing of contract 1 changed, but the number went up so an app knows they're there.

Contract 3 is the generic client contract, written up in [contracts/device-api.md](contracts/device-api.md): a
device says which app it is (`client`, locked when an adult approves the pairing) and its own `checks`; `verify_pin`
answers a short-lived grant; paired apps keep small documents of their own in Hearth
([contracts/client-settings.md](contracts/client-settings.md)); `share_app_data` replaces `tile_exchange_share` (retired since: always false); and a
device's `catalog_categories` is no longer read. A paired app's own packages are never paused for its person, so no
app is named in Hearth's code any more.

### Ask for more

A device asks: `POST /api/hearth/device/<device_id>/ask` (header `X-Hearth-Secret`) with `{"minutes": 15 | 30 | 45 |
60, "group": ignored (bonus time has no category: every ask is "all"), "note": up to 120 characters, "profile_id": a TV's profile}` (a phone asks for its own
person; a TV for the profile's, the one in front when none is given). 200 `{"ok": true, "request": {id, status:
"pending", minutes, asked_minutes, group, expires}}`; 409 `already_open` with that request (one open per person); 429
`cooldown` with `retry_in` (10 minutes after "not now"); 404 `no_person`; 429 `too_often` past 10 asks and event posts a minute; 400 otherwise. A request is open 30 minutes.

The adults are told: `hearth_more_time_requested` (`id`, `person`, `person_name`, `minutes`, `group`, `note`,
`device_id`, `asked`, `expires`) and an actionable notification on the adults' phones (the
asked amount, the next one up, Not now: `HEARTH_MORE|<id>|<minutes>`, 0 for not now; see [The adults'
phones](#the-adults-phones)). The first answer wins, once: from a phone, Hearth's page, or `{"type": "hearth/approvals/answer", "request_id", "minutes" (1-600) |
"deny": true}` on the WebSocket, or the service `hearth.answer_request` (`request_id`; `minutes` 1-600 or `deny:
true`; returns the request as the device sees it; a second answer, or one to an expired request, is refused with a
validation error) (administrators, and adults on Hearth's page). An approval is bonus time today (as `hearth.add_time`: no category, whatever group was asked); the answer fires
`hearth_more_time_answered` (`id`, `person`, `status`, `minutes`, `by`: the user). The asking device sees it in the
person's state document: `request` {id, status: pending | approved | denied | expired, minutes (granted when
approved), asked_minutes, group, expires, answered (when it was answered or expired, null while pending)}, for two hours after.

#### The adults' phones

Every adult on Hearth's page gets requests for more time, suggestions chosen for phones (Pushed to phones) and chores done on each
of their Home Assistant companion apps: a `mobile_app` registration that their person follows as a device tracker
(`device_trackers`), or that their Home Assistant user registered. Its notify service is `notify.mobile_app_<device
name, slugified>`, as the companion app names it. The phone chosen in Configure > Watch for new apps (option
`ask_notify`) gets them too, each service once. Per adult, on Hearth's page (Apps > Where new apps are noticed, and
requests) or in Configure > Watch for new apps:

- `ask_notify_off`: a list of person entity ids whose phones get none (default: everyone on).
- `ask_deep_link`: a list of person entity ids whose Android phones open the deep link instead of Hearth's page.

A request's notification carries `data.tag: "hearth_more_<id>"`, `data.actions` as above, and what a tap opens:

| Phone | `data` |
|---|---|
| Android | `"clickAction": "/hearth?ask=<id>"`, or `"clickAction": "hearth://ask/<id>"` with `ask_deep_link` |
| iOS | `"url": "/hearth?ask=<id>"` (always the page) |
| Not a known companion app (`ask_notify` only) | both, `/hearth?ask=<id>` |

`/hearth?ask=<id>` opens Hearth's page on Today and scrolls to that request (highlighted), or says it was already
answered. `hearth://ask/<id>` is exactly that: scheme `hearth`, host `ask`, the request id as the path; an app that
handles it (Hearth's own phone app, Glint) answers through the WebSocket (`hearth/approvals/answer`). Once a request is
answered anywhere (a button, Hearth's page, the service, the WebSocket, Family Safety's own app) or expires, every phone
that would get it is sent `{"message": "clear_notification", "data": {"tag": "hearth_more_<id>"}}`.

#### Attention

Every notice Hearth gives goes through one layer (attention.py): an **item** with a `key`, a `title` and `text`, an
`urgency` (`info`, `notice`, `urgent`), an **audience**, buttons (`actions`: `{id, label, service, data}`), a `tag`
(the key when not given), whether it also goes to Home Assistant's bell, an expiry, and what it's `about` (`person`,
`group`). Audiences: `adults` (every adult's companion apps as above, with the `ask_notify` phone once),
`chosen_phone` (`ask_notify`), `schedule_phone` (the schedule's own notify service, else `ask_notify`), `admins` (the
bell only, so far), `person:<entity id>` (that person's companion apps), and `household` (everyone on Hearth's page)
and `devices` (chosen phones and TVs) for `hearth.notify`. Delivery adapters take it out: the
companion app (`delivery/companion.py`) and the bell (`delivery/bell.py`); an Echo later. An item with the same key or
tag replaces the one before; clearing a key or tag takes it off every channel it went to.

**The bell is for the household's own business.** Home Assistant's bell shows to everyone who uses Home Assistant, so
it gets only admin notices: a device waiting to pair or paired, a TV's rules taken, a Family Safety answer that failed,
the new apps' list and the schedule's checks. Nothing about a kid goes there (a request or offer and its note, where a
kid went, a chore done, a suggestion): those go to the adults' phones, and requests are answered there or on Hearth's
page.

Items are kept while the
household reloads (an options change), not over a restart: their sources put them back (requests have their own
store).

**Tags.** Every companion-app push carries `data.tag` starting with `hearth_`, so an app that shows Hearth's notices
(Glint) can tell them apart: `hearth_more_<request id>` (a request or an offer), `hearth_place_<person entity id>` (where a kid
went), `hearth_schedule_check` and `hearth_school_time_watchdog` (the schedule), `hearth_chore_<to-do item uid>` (a
chore done), `hearth_app_<package>` (a new app), `hearth_suggest:<person entity id>:<suggestion key>` (a suggestion
pushed to phones), `hearth_approve:<notice key>` (a TV notice's button waiting for a parent's phone). Bell-only notices keep their ids (`hearth_pairing_<id>`,
`hearth_paired_<device>`, `hearth_rules_<device>`, `hearth_more_fs_<request id>`, `hearth_new_apps`).

**Buttons.** A button with a service goes to the phone as `HEARTH_ACT|<item key>|<n>`: the service and its data stay in
Home Assistant. When it's pressed, the presser must be an adult (or an administrator), and one the item reached (a
user whose companion app, or whose person's, got it; any administrator for `admins`); the action then runs as them
(`Context(user_id)`), so a `hearth.*` service checks them as usual. Only services in the `hearth` domain run this
way; any other is refused (with a warning in the log). A press for an item that's gone (cleared, expired,
or from before a restart) is ignored. The older `HEARTH_MORE|` and `HEARTH_APP|` buttons work as before.

**On the TVs.** An item can also be for the TVs (`tv`): then it's in the state document of every TV that says it shows
notices (cap `notices`) as `notices` (see [The device's side of the API](#the-devices-side-of-the-api)), and the TV
shows it in its adult profiles only. So far that's the suggestions pushed to phones. A phone never gets them. A press
on the TV needs a Parent PIN or a parent's phone (`POST /notice`): with **a parent's phone**, the adults get an item of
its own (key `approve:<notice key>:<n>:<random>`, tag `hearth_approve:<notice key>`, never the bell): "Approve +30 min
for Sam?", "Sam's Video ran out. Asked on Kitchen.", with that one button and **Don't allow**. Its button runs as the
adult who taps it, as any item's (the adult check, then the reached check); either button takes it off every phone,
and so do the notice going, a newer ask for the same notice, or 10 minutes passing. The history says who answered
(`notice_answer`). A `hearth.notify` message is on the TVs too (household, chosen TVs, or an adult's profiles); an item
can be limited to chosen TVs (`tvs`).

**Announced.** Every item shown, updated or cleared is also fired on Home Assistant's bus as a `hearth_notice` event,
read-only: its key and tag, kind, urgency, title and text (the phone's words), audience (its kind and the person entity
ids it resolves to), what it's about, its buttons as labels only (`[{n, label}]`, never a service or its data), its
link and times. A router can pick it up and say it on a speaker in the room; answering stays with the phones, Hearth's
page and the TVs. Firing it never stops or slows a delivery. The payload and a sketch of a later answer service (not
built) are in [contracts/notice-event.md](contracts/notice-event.md).

#### A kid's own Home Assistant user

A kid (or anyone) with a Home Assistant user of their own, linked to their person (the person's `user_id`), may use
three WebSocket commands, and nothing else of Hearth's: every `hearth.*` service, `hearth/household`, its subscription,
`hearth/approvals/answer` and Hearth's page stay for administrators and adults (see [Security](#security)). None of the
three takes a person: it's always the caller's own, the person whose `user_id` is the connection's user.

**`{"type": "hearth/me"}`** answers that person's document, exactly what a paired phone of theirs gets in `state`
(see [What a device gets](#what-a-device-gets)), with `contract`. Kids, adults and anyone else with a person get their
own; nothing about other people, approvals or pairing is in it (`media_rooms` is the house's players, as every phone
gets). A user with no person (an administrator who isn't anyone, say) gets the error `not_found`; while Hearth is
loading (a restart, or a reload after an options change) the error is `not_set_up`, so try again shortly. None of these
commands takes a person or any other key: an extra key gets Home Assistant's `invalid_format`. Trimmed:

```json
{
  "person": {
    "person": "person.sam", "kind": "kid", "kind_set": true,
    "groups": [{"id": "all", "name": "All screen time", "minutes_left": 35, "apps": [], "except": ["com.example.music"]},
               {"id": "games", "name": "Games", "minutes_left": 10, "apps": ["com.example.game"]}],
    "locked": false,
    "next_lock": {"at": "2026-11-07T20:00:00-05:00", "by": "binary_sensor.sam_bedtime", "kind": "bedtime"},
    "share_app_data": false,
    "request": {"id": "q2X0aZ1b", "status": "pending", "minutes": 30, "asked_minutes": 30, "group": "all",
                "expires": "2026-11-07T18:30:00+00:00", "answered": null},
    "youtube_blocks": {"videos": [], "channels": [], "words": [], "labels": {}}
  },
  "media_rooms": [],
  "category_values": {"format": "hearth.values/1", "version": "9a0b1c2d3e4f5a6b", "categories": {}},
  "version": "3f1c2a9b0d4e5f67",
  "contract": 3
}
```

`pause`, `lock` and `allow_ends` come as in the state document when they apply.

For an adult (on Hearth's page) the document also has `client_settings`: the `device:<id>/agent-inbox` etag of each
Glint phone paired to them (`{}` with none), so a new agent request changes `version` and reaches Glint on
`hearth/me/subscribe` (see [Glint agents](#glint-agents)). Only the inbox is listed: Glint's own outbox and state writes
don't wake it.

**`{"type": "hearth/me/subscribe"}`** answers success, then sends the same document as an event at once and again
whenever it changes (its `version`), at most every 2 seconds. Errors as `hearth/me`.

**`{"type": "hearth/ask", "minutes": 15 | 30 | 45 | 60, "group": "all" or a group id, "app": a package, "note": text}`**
(all optional; `minutes` 15, `group` the app's group when an `app` is given, else `all`; `note` up to 120 characters)
asks for more time for the caller's own person, through the same pipeline as a device's `POST .../ask`: one open
request per person, the cooldown after "not now", the same amounts and groups, the same rate limit (10 a minute,
counted per user). The result has the body `POST .../ask` answers:

- `{"ok": true, "request": {id, status: "pending", minutes, asked_minutes, group, expires, answered}}`
- `{"ok": false, "error": "already_open", "request": {...the open one}}` (a 409 there)
- `{"ok": false, "error": "cooldown", "retry_in": seconds}` (a 429 there)

and these as WebSocket errors: `bad_request` (minutes not one of the four, or an unknown group), `too_often`,
`not_found` (no person), `not_set_up`. The adults see it as any request, with `"via": "home_assistant"`, `user_id`
(the asking user) and `app` (when given) in its approval and `hearth_more_time_requested`, and `device_id` empty; the
notification says "in the Home Assistant app". The answer reaches the kid in `hearth/me` (`request`), and in their
paired devices' state as always.

**From Family Safety:** a request made on an Xbox or a Windows PC (`microsoft_family_safety_request`) becomes a request
of the person whose Family Safety account it is (Configure > Enforce), once per request id, with `source:
"family_safety"`, `platform`, `app_name` and `requested_time` (as Microsoft gave it; its unit isn't documented, so
Hearth doesn't show it and the adult picks the minutes, 30 offered). It's answered as any other; Hearth then calls
`microsoft_family_safety.approve_request` (`extension_minutes`: the minutes, 15 to 480) or `deny_request`, and tells
the adults in a notification if that fails. It adds no Hearth bonus, starts no cooldown, isn't told to a Hearth device
and doesn't count as the person's open request.

### Pause and locks

`hearth.pause` (`minutes`, or `until` a time or date-time; `reason`; `people`, every kid by default; `ends_on`, see
[Exceptions](#exceptions)) holds the people until it ends or `hearth.pause_end` (`people`, everyone by default); a restart of Home Assistant
doesn't end it.
Adults are never paused (they have no limits in Hearth): an adult named is left out, and only adults is refused. It
answers who was paused, `{paused: [...], not_paused: [the adults named]}`. A paused person is locked, so a Hearth TV holds
their apps as for bedtime, and their state document says `pause` {until, reason}. Every person's document also says,
while they're locked, `lock` {by: the lock entities and/or "pause", kind: bedtime | school_time | pause | other
(the first that applies), kinds: all of them, until: when it ends, if known}, and `next_lock`
{at, by, kind: bedtime | school_time} for the next bedtime or school time today, from the lock entities' own
`bedtime_start`/`bedtime_end`/`schooltime_start`/`schooltime_end` (Family Link's; Family Safety's Downtime Active
sensors carry `downtime_start`/`downtime_end`, an older one `bedtime_start`/`bedtime_end`, and are a bedtime), so a
device can wind down. School time taken off today is never the `next_lock` (tonight's Sleep is, then). While extra
time lifts bedtime, `next_lock` is bedtime coming back when the lift ends (`{at: the lift's end, by: the bedtime lock
or "schedule", kind: bedtime}`), so a device that loses Home Assistant meanwhile brings bedtime back itself; not when
the lift lasts past the bedtime's own end. A family pause also locks a kid's Family Link devices whole, as daily
time used up does (a phone without a Hearth app has nothing else holding it), let go when it ends. Without
a push, a device learns of a pause with its next status answer: a TV within 2 minutes (it posts at least that often
while on), a phone at its next post.

#### Extra time at bedtime

An adult's extra time of All screen time given while a kid is in bedtime (`hearth.add_bonus`, the page's +15, +30 or
+1 h, an approved ask) **lifts bedtime** for that kid while it lasts, when All screen time then has minutes left
(without that, nothing is lifted). In bedtime: the weekly schedule's Sleep, one of the kid's lock entities that's a
bedtime (Family Link's Bedtime active, Family Safety's downtime), or Family Link's own bedtime on one of their devices.
Extra time of one group only (Games, say) and extra time on one device lift nothing; nor does an allow.

- **How long**: as many minutes from now as were given (more extra time adds on; never more than All screen time has
  left). It ends sooner when All screen time runs out again, or when an adult takes the extra time back
  (`hearth.remove_bonus` shortens it by what was taken). Then bedtime is back. `hearth_bedtime_lifted` {person,
  until} and `hearth_bedtime_back` {person} are fired.
- **Hearth's own**: the bedtime lock entities and the schedule's Sleep don't lock the kid: `locked` is false and
  there's no `lock` in their state document (Hearth's TVs and the phones let go), and Sleep's hold of Family Safety's
  platforms and the Switch is let go. A family pause and School time still hold. The person's state document and the
  household summary say **`bedtime_lifted`** `{since, until}` (local ISO times) while it lasts; Hearth's page shows
  "Bedtime paused until 9:45 for extra time".
- **Family Link's bedtime**: tonight's start moves to when the extra time ends, through `familylink.set_bedtime` with
  `scope: "today"` (a one-off override of today's weekday; the weekly schedule is left alone), `start_time` the end
  of the extra time (to the minute, rounded up), `end_time` tonight's end as it was, `day` today's ISO weekday. More
  extra time moves it again. When the lift ends, the start Hearth found is put back the same way, only while
  Family Link still reads Hearth's start (or the one it found): a start a parent changed in the Family Link app
  meanwhile is theirs and stays (`kept_current`, as for the daily limit). What Hearth moved is kept across restarts,
  so it's put back after one too; a move of another day isn't (that day's override is over). Hearth's page shows
  what was done in the kid's Family Link line (`bedtime_moved`, `bedtime`: `restored` or `kept_current`).
- **A Family Link bedtime already under way**: moving its start doesn't end it (the call succeeds and the phone stays
  locked). Bonus time does, as "Add time" in the Family Link app. So each of the kid's devices whose Bedtime active
  sensor is on gets `familylink.add_time_bonus` {`entity_id` the device's switch, `bonus_minutes` the minutes the lift
  has left, 1440 at most}, besides the moved start. More extra time gives the minutes more; a device that enters
  bedtime during the lift gets the rest then; a device a bonus already keeps open as long gets none. A failed call is
  tried again 5 minutes later, and the start is moved all the same. A bonus can't be shortened, so when the lift ends
  (its time is up, All screen time ran out, the extra time was taken back) Hearth ends it with `familylink.reset_bonus`
  (the device's Reset bonus button on an older Family Link). Family Link shows only a device's latest bonus: when that
  isn't one of the sizes Hearth gave for the lift, it's a parent's and stays (`bedtime_bonus_kept`), since a reset
  ends every bonus of the day on the device. The bonus is Hearth's own (never a "bonus time given in the Family Link
  app" grant), is in the activity log as Hearth's call, and gives no minutes in Hearth: it only opens Family Link's
  bedtime. What was given is kept across restarts, so nothing is given twice and it's reset after one too. Hearth's
  page has `bedtime_bonus` {device: minutes}, `bedtime_bonus_reset` and `bedtime_bonus_kept` in the kid's Family Link
  line. Without `familylink.add_time_bonus` (an older Family Link) only the start is moved, as before.
- **Which night**: Family Link keys a bedtime by the weekday it starts on, and a `today` override is for today's. So
  only a bedtime that starts today, before the extra time ends, is moved (from the child's Bedtime active sensors'
  `bedtime_start`/`bedtime_end`). After midnight the bedtime under way started yesterday: it's left alone, since an
  override of yesterday's weekday isn't known to reach a night already under way, and today's would move tonight's
  bedtime instead. Hearth's own locks are lifted all the same, and the phone opens by its bonus time (a device's, not
  a night's). A moved start is 23:59 at the latest (a start after midnight would read as a bedtime of this morning);
  a phone already in bedtime keeps going past midnight on its bonus, one whose bedtime hadn't started stops at 23:59.
- Family Safety's own downtime (Microsoft's) isn't moved: only Hearth's hold of the platforms is let go.

**One app or group.** `hearth.pause` with `app` (a package) or `group` (an id or name; `all` is the family pause) pauses
only that, for the people (every kid by default), for `minutes` or `until` a time (no `ends_on`). Nobody is locked:
the app or group's apps are held as a group out of time is, on every Hearth TV and phone (HearthTube too, in a group
that lists it), by Family Link and by Family Safety's Xbox and Windows apps, and the person's Switch when their
Nintendo enforcer covers the group (Games, say). A family pause holds the Switch too (see Enforce, Nintendo). The person's document has it as a group
`{id: "pause:group:<id>" or "pause:app:<package>", name: "<name> (paused: <reason>)", minutes_left: 0, apps,
paused: {until, reason, name}}`, so devices that know only groups hold it; Hearth TV's time's up card then says
"<name> is paused" with no ask for more. **No device should offer to ask for more time for a `paused` group**: more
time doesn't end it, only `hearth.pause_end` or its end does. An allow doesn't lift it, and `hearth.explain`
lists it as `pause` with its `app` or `group`. A person can have several, besides a family pause.
`hearth.pause_end` with the same `app` or `group` ends that one; without either (or with `group: all`) it ends only
the family pause.

### Household summary

For an adult's app on Home Assistant's own WebSocket (administrators, and adults on Hearth's page whose person is their
user, without pairing codes; no device secret, nothing extra for the
entities and services). `{"type": "hearth/household"}` answers once; `{"type": "hearth/household/subscribe"}` answers,
then sends the same object as an event whenever it changes, at most every 2 seconds (unsubscribe as usual). It holds:

- `people`: `id`, `name`, `kind` (as set on Hearth's page, `kind_set` true; else `kid` when they have limits, otherwise
  `person`), `tv_profiles`, `all`
  (the shared pool: All screen time's `used_minutes` and `minutes_left`), `groups` (each with a budget or use today),
  `locked` and `locked_by`, `playing` (one entry per thing on now, see [Now playing](#now-playing-entries) below;
  `target` as in `targets` below).
- `playing`: everyone's plays now, for a dashboard, oldest first: `person`, `name`, `item` (the title, else the app or
  package), and `kind`, `app`, `title`, `series`, `artist`, `episode`, `device`, `target`, `since`, `minutes`,
  `remaining`, `progress` and `text` as in each person's `playing`.
- `devices`: each Hearth TV and phone: `id`, `name`, `kind`, `connected`, `screen`, `app`, `media_title`, `media_app`,
  `profile` (a TV's), `kids_profile`, `media_player` and `person`.
- `approvals`: requests for more time (`type: "more_time"`, as the event above) and devices waiting to pair
  (`type: "pairing"`, `device_name`, `device_kind`, `code`, `expires`).
- each person also has `pause`, `lock` and `next_lock` as in their state document, and `held` / `held_by` (the
  other parental controls holding something of theirs now: `family_link`, `family_safety`, `nintendo`); each group
  also has `budget` (today's, null for none) and `bonus` (extra time given today).
- each person also has (new fields, nothing renamed): `allows` (their allows now), `grants` (parent grants, above),
  `first_party` (`family_link`: per device `device`, `daily_limit`, `minutes_left`, `bonus_left`, `reached`,
  `blocking`; `family_safety`: per platform `minutes_left`, `allowance_minutes`, `used_minutes`, `allowed_now`, `hold`,
  `parent_lock`, `blocking`; `nintendo`: per Switch of theirs (their Nintendo enforcer's, or one a source of theirs is
  on) `device_id`, `name`, `target`, `available`, `played_minutes`, `player_minutes` (their own player's on a shared
  Switch), `limit_minutes` (null: no limit), `minutes_left`, `extra_minutes` (-1: unlimited today), `suspended`,
  `playing`, `bedtime`, `last_synced`, `held_by_hearth`, `blocking` and `entities` (the Switch's entities by key);
  only what the integrations' entities give), `sync` (per parental control: `held`, `why` (each held item's reason:
  `budget`, `school_time` or `pause`), `names` (how to show each app held or let go of: its name, a guess from the
  package when none is known, never the package), `error`, `failed_at`, and `last`, what Hearth last did and whether
  it took: `{at, ok, held, let_go, outcomes {item: restored | kept_current | ...}, bonus_added, extra_time,
  parent_grant, reason, error}`; a failed hold or let-go's error is dropped once the parental control has nothing to
  hold and holds nothing, and any error once a call through it succeeds; the summary's lines skip an error over a day
  old) and
  `answered_elsewhere` (requests answered in the Family Safety app lately).
- each kid also has `place` {`name`, `fresh`} (where they are, by name only; [Places](#places)): every reader of the
  summary is an administrator or an adult. An allow and a pause that end on a place carry `ends_on` (above).
- each person also has `pauses`: an adult's pauses of one app or group, `[{app, group, name, until, reason}]` (`app`
  or `group` is null), apart from the family `pause`.
- each person also has `devices_today` `[{target, name, kind, minutes}]` (most first) and `apps_today` `[{package,
  name, minutes, groups}]` (an app's package, or `title:<id>` for a title; most first, at most 50): today's minutes as
  Hearth counts them, each device's time once. A device's `kind` is `tv`, `phone`, `xbox`, `windows`, `switch` or null
  (a `source:` sensor whose integration doesn't say: an Xbox integration's is `xbox`, Nintendo's `switch`, the
  companion app's `phone`). An app's `groups` are the group ids it counts in, in the household's order, without
  `all` (`["games"]`, `[]` for none). `target` is the device's id as in `targets` (below) where Hearth can tell:
  `hearth:<device_id>` for a Hearth TV or phone, `fl:<device id>` for a source that is one Family Link device's own
  Daily screen time sensor, `nintendo:<entity>` for a source on the same Home Assistant device as the person's
  Nintendo enforcer; any other source is `source:<id>` (a child's Family Link total for all their devices, say, or
  Family Safety's). An app's minutes are summed over the devices.
- each person with Family Link also has `school_time` {`start`, `end`} (local times) on a school or half day: today's
  School time window (a half day's ends early as configured). And `school_time_off` (only while there is one): School
  time taken off for them today (`hearth.school_time_off`), `[{id, date, from, reason, applied, ...}]`.
- each person whose locks (Configure > Locks) say `bedtime_start` and `bedtime_end` (Family Link's bedtime does) has
  `bedtime` {`start`, `end`}: tonight's bedtime and this morning's wake, local times on today's date (with more than
  one lock, the earliest bedtime and the latest wake). Hearth's page draws the day from wake to bedtime (6:00 to 22:00
  without it).
- each person also has `all_by_pool` `[{id, name, minutes}]`: All screen time's used minutes today split by pool, in
  the household's order of groups, then `{id: "other", name: "Other"}` for apps in no pool; they add up to
  `all.used_minutes` (a pool that isn't screen time is left out; empty when nothing is used). An app is in one pool,
  so nothing counts twice.
- each person also has `targets` `[{id, name, kind, via, groups}]`: their devices, for extra time on one device
  (above). `kind`: `tv`, `phone`, `xbox`, `windows` or `switch`; `via`: `hearth` (a Hearth TV with one of their
  profiles, or their Hearth phone), `family_link` (each Family Link device, `fl:<device id>`), `family_safety` (each
  platform their Family Safety reports, whether or not Hearth's enforcer holds it, `fs:xbox`, `fs:windows`) or `nintendo` (their Switch,
  `nintendo:<the enforcer's entity>`); `groups` true where one group can be held or given on that device alone
  (Hearth's own devices). A TV's `name` is as shown ("Kitchen" is "Kitchen TV"). `display_name` is how a person reads
  it, never a model id like `SM-X230` when a better one is known: the name given to its device in Home Assistant
  (`name_by_user`), else the name of the person's source counting it ("Sam's tablet"), else `name`. One handset that's both a Hearth phone and
  a Family Link device of theirs (the same name) is both: the Family Link one says `same_as` (the Hearth phone's id)
  and the Hearth phone `also` (`["fl:<id>"]`); show it once. Extra time there for one group goes on the Hearth phone;
  for All screen time give it on both if Family Link holds the phone too. Each target also says the time actually
  left there, worked out once for every surface (the page, the TV, Glint): `left` (minutes, the smaller of Hearth's
  limit there and the device's own; null when neither limits it), `left_by` (`hearth`, `google`, `microsoft` or
  `nintendo`: whose limit that is), `left_pool` (with `hearth`: the pool that binds, `all`, or `games` on an Xbox or
  Switch whose enforcer holds Games), `locked` (nothing runs there now) and `locked_kind` (`bedtime`, `school_time`,
  `pause`, `other`: a lock or pause of theirs; `out`: Hearth's time is up; `device_limit`: the device's own limit;
  `parent_lock`: a parent's own Family Safety lock; null when not locked). Hearth's limit is All screen time's
  minutes left, and on an Xbox or Switch also each pool its enforcer holds; extra time on that device adds to it (an
  allow there lifts it). The device's own is Family Link's daily limit, Microsoft's allowance or the Switch's limit
  (`first_party`), unless that number is Hearth's own hold. And `device_extras` `[{id, target, name, via, kind (bonus | allow | bedtime), group, until,
  minutes_left, reason}]`: that extra time now (`minutes_left`: a Hearth device's by its use, a Family Link bonus as
  given, the rest by the clock).
- each person also has `week`: their last 7 local days, newest first, today included: `[{date, minutes {<group id>:
  n}, out [group ids that ran out], bonus {<group id> (or `all` for extra time on one device): minutes}, asks,
  budget {<group id>: n | null}}]` (`date` is `YYYY-MM-DD`). Today's `minutes` are live (as `groups`, every group of
  the household); a past day's are the day's `day` record in [History](#history). A day with no record (before Hearth
  kept them, or Home Assistant down across more than one midnight) has `minutes` `{}`: unknown, not zero. `budget` is
  that day's budget per group of the household, without its bonus (null: no limit; add `bonus` for "of"): today's as
  counted, a past day's as recorded with its `day` record, and for a day recorded before budgets were (or not
  recorded) the budgets now for that day's type, from the dates typed in and the weekday rule of
  [School days](#school-days-and-day-types) (an entity's or calendar's answer is only ever today's).
- `groups`: every group of the household, budget or not today: `[{id, name, not_screen_time}]`.
- `not_screen_time`, `contract`, and `version` (changes with any of it).
- `media_rooms`: the house's media players by room, below.
- Contract 2: each person's `headline`, `lines` and `actions`, and the household's `household` {`headline`,
  `actions`, `suggestions`, `counts`}, below; and each person's `binding`, `day_line` and `state`, and each group's
  `state` and `limited` ([Dashboard fields](#dashboard-fields)).

#### Now playing entries

Each entry of a person's `playing` is one specific thing on now, the most specific known:

```json
{"kind": "video", "title": "Sleepytime", "series": "Bluey", "artist": null, "episode": "s2e4", "app": "HearthTube",
 "package": "com.thesiegs.hearthtube", "device": "Kitchen TV", "state": "playing", "target": "hearth:<device id>",
 "since": "2026-11-13T17:02:00+00:00", "minutes": 12, "remaining": 8, "progress": 0.6,
 "text": "bluey · s2e4 · 8 min left"}
```

- `kind`: `video` (a show, video or movie: a TV's media player in the options, else the device's own media session),
  `music` (a track: the player says music, or an artist without a show), `game` (a Switch's or a live source's title,
  or an app in the Games group) or `app`.
- `title`: the most specific thing: the episode's, video's or movie's title, the track, the game; null when only the
  app is known. `series`: a show's name (an episode's); `artist`: a track's; `episode`: `s2e4` (or `e4`) when the media
  player gives the numbers. `app` is the container (secondary), `since` when the play started (UTC).
- Time, worked out when the summary is: `remaining` (whole minutes) and `progress` (0 to 1) when the length is known:
  a media player's `media_duration`, `media_position` and `media_position_updated_at`, or a Hearth device's status
  `media_duration_s` with `media_position_s` as of `media_position_at` (epoch milliseconds; TV builds send these from
  now on). The position runs on while it plays and stands while it's paused. Else null. `minutes`: whole minutes since
  `since` (null for music, which has no time).
- `text`: short and lower case: `bluey · s2e4 · 8 min left`, `minecraft · 25 min`, `artist · track`.
- A device's own state document (and so its `/wait`) carries only the play itself (`kind`, `title`, `series`,
  `artist`, `episode`, `app`, `package`, `device`, `state`, `target`, `since`): never `minutes`, `remaining`,
  `progress` or `text`, which tick.
- Playing together: the same show (else the same title) on two devices. A Switch whose game Nintendo doesn't name
  (`Switch`) is together only with someone on the same console, never with a kid on another Switch.

A second parent who isn't an administrator (an adult on Hearth's page whose person is their Home Assistant user) reads
the whole summary, contract 2 included, without pairing codes: the household's headline and actions never mention a
device waiting to pair for them (Glint's H-3; covered by a test).

#### Contract 2: headline, lines, actions

Hearth decides what matters about each person now, and an app draws it, so a new kind of news or a new control shows
without a release of the app. Each item is `{text, level, key}`: `text` is short and lower case (`"youtube · 25
left"`), `level` is `calm`, `notice` or `urgent`, and `key` names the news, its kind and its subject (`low:youtube`,
`ask:<request id>`, `pause:<until>`), never a count: it stays the same while the minutes tick down and changes when the
news does, so an app can animate only real news.

The **headline** is the first of these that holds (glance.py), in this order:

| Level | News | Text | Key |
|---|---|---|---|
| urgent | a request for more time waits (or an offer) | `asks for 30 more · youtube` (`youtube ran out · give 30?`) | `ask:<id>` |
| urgent | a family pause | `paused · dinner till 6:30` | `pause:<until>` |
| urgent | out of All screen time (and no allow for all) | `out of time` | `out:all` |
| notice | locked now by bedtime, School time or another lock | `bedtime till 7:00` | `lock:<kind>:<until>` |
| notice | Google TV's own Kids daily limit holds them on a TV (Hearth can't lift it) | `google tv's own limit` | `google_limit:<tv name>` |
| notice | bedtime or School time starts within 15 minutes | `bedtime in 12 min` | `soon:<kind>:<at>` |
| notice | a group out, or under 10 minutes (fewest first) | `youtube · out`, `youtube · 7 left` | `out:<group>`, `low:<group>` |
| notice | an allow (`hearth.allow`) | `youtube allowed till 8:00` | `allow:<id>` |
| notice | School time taken off today | `no school time today` | `school_off:<id>` |
| notice | extra time on one device | `kitchen · 25 left there`, `xbox · open till 6:30`, `pixel · +30 in family link`, `tv · games open till 8:00` | `device_bonus:<target>` |
| notice | an adult's pause of one app or group | `youtube paused · homework till 7:00` | `paused:group:<id>`, `paused:app:<package>` |
| notice | a parent's grant: a bonus, an unlock or a changed daily limit, a Switch or a platform let go | `switch open · the nintendo app till 9:00` | `grant:<id>` |
| notice | Google's or Microsoft's own limit stops a device of theirs (Hearth isn't holding it) | `sam's phone · google's own limit`, `xbox · microsoft's own limit` | `device_limit:<entity or platform>` |
| notice | a parent's own Family Safety lock | `xbox locked in family safety till 7:00` | `parent_lock:<platform>` |
| notice | a parental control Hearth couldn't hold or let go through | `family link · didn't take` | `sync_error:<kind>` |
| calm | a request answered outside Hearth | `request approved in the Family Safety app`, `request handled outside Hearth (the Family Safety app or the device)` | `answered:<id>` |
| calm | the most-used group with a limit (All screen time only when it's the only one) | `youtube · 25 left` | `left:<group>` |
| calm | nothing else | `all clear` | `clear` |

Times are local, 12-hour, without am/pm; 12:00 at night and at midday are `midnight` and `noon` (`till midnight`).
Lengths of time are in one format everywhere (noiwid's): `45 min` under an hour, `2 h 10`, `1 h 05`, `3 h` from one;
before `left`, `more`, `of`, after `+` and `give` the bare number under an hour (`10 left`, `+15`, `give 30?`) and
the same format from one (`1 h 20 left`, `+1 h`, `asks for 1 h 30 more`). Keys never carry a count, so the format
changing moves no key.
**lines** are the rest of that list in the same order, then each group with a limit (All screen time first, `left`,
`low` or `out` as above), what's playing (`hearthtube · kitchen`, key `playing:<package>`), the next lock (`bedtime
at 9:00`, key `next:<kind>:<at>`) and, last, the app limits a parent changed in their own app (below); never the
headline again.

An app's limit a parent changed in the Family Link app is a standing grant: Hearth sees it again every day, so it's
`calm` and never the headline. Such grants with the same source and end are one line, by the app's name (never its
package; a readable guess from the package when no name is known): `roblox open · the family link app till
midnight` (key `grant:<id>`), two or three named (`youtube kids and roblox open · ...`, `a, b and c open · ...`),
more counted (`16 apps open · the family link app till midnight`); a line of two or more has the key
`grants:<via>:<until>:<apps>`, `<apps>` a short hash of the set of packages, so it stays while the set does.

**actions** are what an adult can do for the person now, each `{id, label, service, data, confirm?, primary?}`: an app
calls `service` with exactly `data`, with the adult's own Home Assistant sign-in, after asking `confirm` when it's set;
`primary` ones come first. The result shows in the next summary. Only what applies now is offered:

| id | When | service and data |
|---|---|---|
| `ask_yes:<id>` (primary), `ask_no:<id>` | a request waits | `hearth.answer_request` `{request_id, minutes: <asked>}` / `{request_id, deny: true}` |
| `bonus:<group>` | each group with a limit today, fewest minutes first; primary when it's out | `hearth.add_bonus` `{person, minutes: 15, group}` |
| `pause` (confirm) | not paused | `hearth.pause` `{people: [person], minutes: 30}` |
| `pause_end` | paused (the family pause) | `hearth.pause_end` `{people: [person]}` (ends that pause only) |
| `pause_end:group:<id>`, `pause_end:app:<package>` | an app or group paused | `hearth.pause_end` `{people: [person], group}` or `{people: [person], app}` |
| `device_bonus_end:<target>` (confirm) | extra time on that device | `hearth.allow_end` `{people: [person], device: <target>}` |
| `school_off` (confirm) | a school or half day, before the person's School time ends, and not taken off for them today | `hearth.school_time_off` `{people: [person]}` |
| `allow_end:<id>` (confirm) | an allow | `hearth.allow_end` `{people: [person], group}` or `{people: [person], app}` |
| `grant_end:<id>` (confirm) | a parent's grant that maps to a write in their app (`endable`) | `hearth.allow_end` `{id}` |

`household` is the same for the whole house: a `headline` (urgent: requests waiting, `alex asks for 30 more` or `2
asks waiting`; notice: a pause, `everyone paused till 6:30` or `sam paused till 6:30`; notice, administrators only: a
device waiting to pair; notice: kids out of time; calm: `all clear`) and `actions`: each waiting request's yes and no
(labelled with the kid's name), `pause_end` (`hearth.pause_end {}`, ends the family pause; app and group pauses stay) while anyone is paused, and
`pause_all` (`hearth.pause {minutes: 30}`, confirm) unless everyone is. Approving a device to pair isn't an action:
it's an administrator's step on Hearth's page, with no service. `counts` is what a tile's badge and a TV's top row
show, counted once here: `{asks, suggestions, pairings, paused, out, low, locked, held, suggestions_held, needs}`
(`asks`: requests for more time waiting; `suggestions`: the household's suggestions showing; `pairings`: devices
waiting to pair, as the reader sees them; `paused`: people under the family pause; `out`, `low`, `locked`, `held`: kids
whose `state` is that; `suggestions_held`: suggestions held back by a lock, the evening or a device not in use;
`needs`: kids with a request waiting or a suggestion showing, one row each on Hearth's page). `household` also lists
`suggestions_held` (below).

#### Dashboard fields

Decided here so every surface (the panel, a TV, Glint) shows the same pool, line and color; a surface picks its own
hues for each role, never the role.

- Each group has `state`: `paused` (an adult paused that group), `allowed` (an allow lifts it; an allow of All lifts
  every group), else by its `minutes_left`: `out` (0), `low` (under 10), `ok`, or `none` (no budget today). And
  `limited`: false when it has no budget today, so the TV and Glint hide it and the panel mutes it. `all` has them too.
- Each person has `binding`: `{"group": "games", "minutes_left": 10}` or null: the group that stops them first, out
  first, else the fewest minutes left, All screen time on a tie; a group an allow lifts or without a budget never
  binds. The give button targets it (`bonus:<group>` in `actions`).
- Each person has `day_line`, `{text, level, key}` like a line: `<All used> of <All budget + bonus> · <binding
  group> · <its left>`:

  | Case | text | level | key |
  |---|---|---|---|
  | a group binds | `2 h 10 of 3 h · games · 10 left` | calm (notice under 10) | `day:left:games` (`day:low:games`) |
  | All binds | `2 h 10 of 3 h · 50 left` | calm (notice under 10) | `day:left:all` |
  | a group out | `1 h 40 of 3 h · games out` | notice | `day:out:games` |
  | All out | `3 h of 3 h · out of time` | urgent | `day:out:all` |
  | no budget for All | `1 h 20 today · games · 10 left` | as above | as above |
  | nothing limited | `1 h 20 today · no limit` | calm | `day:none` |
  | an allow of All, nothing else limited | `1 h 20 today · allowed till 8:00` | notice | `day:allowed:all` |
  | the family pause | `paused · dinner till 6:30` | urgent | `day:pause:<until>` |
  | bedtime, School time or another lock | `bedtime till 7:00` | notice | `day:lock:<kind>:<until>` |

- Each person has `state`, the first that holds: `paused` (the family pause), `locked` (bedtime, School time or
  another lock now), `out` (the binding group is out), `held` (a first-party control holds a device of theirs:
  Hearth's hold through Family Link, Family Safety or Nintendo, their own limit, a parent's Family Safety lock, or
  Google TV's own Kids limit), `low` (the binding group under 10), `ok`, `none` (nothing limited today).

A trimmed example: a kid Alex who asked for more, is paused and is low on video, and Sam with nothing to report. The
whole summary, from a test (with a grant of Sam's from the Nintendo app added by hand), is
[examples/household-contract2.json](examples/household-contract2.json).

```json
{
  "contract": 3,
  "people": [
    {
      "id": "person.alex",
      "name": "Alex",
      "kind": "kid",
      "headline": {
        "text": "asks for 30 more · video",
        "level": "urgent",
        "key": "ask:h3RnR2dlNmQV"
      },
      "lines": [
        {
          "text": "paused · dinner till 6:30",
          "level": "urgent",
          "key": "pause:2026-11-06T18:30:11-08:00"
        },
        {
          "text": "video · 5 left",
          "level": "notice",
          "key": "low:video"
        },
        {
          "text": "screen time · 1 h 35 left",
          "level": "calm",
          "key": "left:all"
        }
      ],
      "actions": [
        {
          "id": "ask_yes:h3RnR2dlNmQV",
          "label": "yes 30",
          "service": "hearth.answer_request",
          "data": {
            "request_id": "h3RnR2dlNmQV",
            "minutes": 30
          },
          "primary": true
        },
        {
          "id": "ask_no:h3RnR2dlNmQV",
          "label": "no",
          "service": "hearth.answer_request",
          "data": {
            "request_id": "h3RnR2dlNmQV",
            "deny": true
          }
        },
        {
          "id": "bonus:video",
          "label": "+15 video",
          "service": "hearth.add_bonus",
          "data": {
            "person": "person.alex",
            "minutes": 15,
            "group": "video"
          }
        },
        {
          "id": "bonus:all",
          "label": "+15 screen time",
          "service": "hearth.add_bonus",
          "data": {
            "person": "person.alex",
            "minutes": 15,
            "group": "all"
          }
        },
        {
          "id": "pause_end",
          "label": "end the pause",
          "service": "hearth.pause_end",
          "data": {
            "people": [
              "person.alex"
            ]
          }
        }
      ]
    },
    {
      "id": "person.sam",
      "name": "Sam",
      "kind": "kid",
      "headline": {
        "text": "video · 50 left",
        "level": "calm",
        "key": "left:video"
      },
      "lines": [
        {
          "text": "screen time · 1 h 45 left",
          "level": "calm",
          "key": "left:all"
        },
        {
          "text": "bedtime at 9:00",
          "level": "calm",
          "key": "next:bedtime:2026-11-06T21:00:00-08:00"
        }
      ],
      "actions": [
        {
          "id": "bonus:video",
          "label": "+15 video",
          "service": "hearth.add_bonus",
          "data": {
            "person": "person.sam",
            "minutes": 15,
            "group": "video"
          }
        },
        {
          "id": "bonus:all",
          "label": "+15 screen time",
          "service": "hearth.add_bonus",
          "data": {
            "person": "person.sam",
            "minutes": 15,
            "group": "all"
          }
        },
        {
          "id": "pause",
          "label": "pause 30 min",
          "service": "hearth.pause",
          "data": {
            "people": [
              "person.sam"
            ],
            "minutes": 30
          },
          "confirm": "pause sam for 30 min?"
        }
      ]
    }
  ],
  "household": {
    "headline": {
      "text": "alex asks for 30 more",
      "level": "urgent",
      "key": "asks:h3RnR2dlNmQV"
    },
    "actions": [
      {
        "id": "ask_yes:h3RnR2dlNmQV",
        "label": "alex yes 30",
        "service": "hearth.answer_request",
        "data": {
          "request_id": "h3RnR2dlNmQV",
          "minutes": 30
        },
        "primary": true
      },
      {
        "id": "ask_no:h3RnR2dlNmQV",
        "label": "alex no",
        "service": "hearth.answer_request",
        "data": {
          "request_id": "h3RnR2dlNmQV",
          "deny": true
        }
      },
      {
        "id": "pause_end",
        "label": "end the pause",
        "service": "hearth.pause_end",
        "data": {}
      },
      {
        "id": "pause_all",
        "label": "pause everyone 30 min",
        "service": "hearth.pause",
        "data": {
          "minutes": 30
        },
        "confirm": "pause everyone for 30 min?"
      }
    ]
  }
}
```

`HEARTH_EXAMPLE_OUT=<file>` with the tests (`ha_tests/test_glance.py`) writes the full example again.

Hearth's page opens on a tab from its link: `/hearth#today`, `#kids`, `#devices`, `#apps`, `#family`, and
`#approvals` (Today, where requests for more time and devices waiting to pair are shown first).

#### Today on Hearth's page

Today follows the redesign of 2026-11-13, with the More time sheet of 2026-11-22: does anything need an adult, in one
sentence; one row per kid; what's playing; the rest one tap away. Every action applies at once with a 9-second
**Undo** instead of a confirm (a gift undoes with `hearth.remove_time`, a raise with `hearth.end_grant` of its origin, a
pause with `hearth.pause_end`, an allow with `hearth.allow_end`; ending an extra gives it back where it can be told
exactly; "Not today" and "No" to a request wait for their Undo to pass before they're sent, and are sent at once when
the page closes). The page is redrawn only when the summary changed (or the minute did), the toast lives outside the
redrawn part, and focus stays on the same button across a redraw.

- **The header**: "Today", "Tonight" once the earliest kid's cutoff has passed (their bedtime, else 9:00 pm), and one
  line: `11:00 pm · 2 of 3 in bedtime · Sam still up`; **Pause 30 min** pauses everyone at once (with Undo), and its
  caret opens the length (15, 30, 60 or 90 min, or until a time) and a reason.
- **For you**: requests and the suggestions showing, one row per kid (a request first, then a pool that ran out, then a
  device's own limit), each a sentence (`sentence`), a detail line and its buttons under the text (+15 min, the "+"
  box, Not today; a request: Give 30 min, 15 min, No), with "+1 more for Sam · See". Nothing waiting: one quiet line,
  "Nothing needs you" (or "Nothing needs you tonight"), with "6 suggestions held back · why" folding
  `household.suggestions_held` and each one's `why`.
- **Kids**: a row per kid, bedtime last and faded, in two lines that wrap, never cut off: the name and the big number
  (`1 h 10 left`, `12 min left`, `Bedtime`, `Free play`), then the reason or what's next (`Games done · bedtime 9:00`,
  `On Xbox · Minecraft`, `Till 7:00 am`). A ring around the person's picture, else the initial (two letters when two
  kids start the same: `Al`, `An`), showing daily time used of today's (amber when a category ran out, red when daily
  time did, indigo with a moon in bedtime, blue with a cap in School time). A **+15 min** button beside the row (its own
  target, not inside it) only when time is what stops them, they're awake, not in free play, before their cutoff and
  For you doesn't already have them.
- **Screens now**: what plays (Hearth's TVs and phones, consoles and Switches from `playing`), one row "Nothing
  playing · 3 TVs off · no console or Switch in use" when nothing does (it opens to the TVs); a TV on Hearth's home
  reads "Home screen", and a TV that's off has no profile.
- **Adults** get one muted line: `Adults today: Robin 2 h · Jordan 31 min · no limits`.
- **The kid's sheet** (a tap on their row): a bottom sheet on a phone (closed by the scrim, Esc, a swipe down from its
  head or ×), the column beside the list from 900 px of the page. The head: the name, a big `1 h 10 min left` (or the
  lock) and a why line ("Games: done for today (2 h used). Other apps still work. Bedtime 9:00.", a device stopped by
  its own limit, School time ahead). Their lock box (who set it; More time pauses bedtime while it lasts), their request
  or suggestions, then three buttons: **More time**, **Pause** (30 min at once, with Undo) and **⋯** (Allow an app…,
  No School time today while it's ahead, Free play…, Change limits). In bedtime or School time: **Allow an app**,
  **More time anyway** and ⋯. Allow an app finds any app the kid used today or Hearth knows, by typing.
  **Today's extras**: every extra still on, each with End (bonus time given, raised limits and free play by their
  origin with `hearth.end_grant`, allows, extra time on a device) and No School time today with Undo. **Today**: left
  first, `2 h 50 of 4 h` small, daily time split by category with each limit as a marker, and a read-only lane per
  limited category (`Games · Done · 2 h limit`) that opens to its apps (a console as "On Switch 2"). **Devices** grouped
  by what they're doing (`3 TVs, 2 tablets · Follows daily time · 31 min left`), each by its `display_name` without the
  kid's name, **Holds and notes** in plain sentences ("26 apps are allowed without a limit till midnight. Someone
  changed their limits in the Family Link app.", "Hearth is blocking 46 apps on Sam's Family Link devices because
  Games ran out."), **This week** and their to-do list.
- **More time** (one sheet for every kind of extra time: a second bottom sheet on a phone, a dialog on a wide page):
  **For** the category that's stopping them or **Anything** (other limited categories as "Or for: YouTube ·
  Streaming"; no row when the kid has no category limits), **+15 min / +30 min / +1 h**, a **rest of today** button,
  a line saying what the choice will do (and "25 min over: +30 leaves 5"), then **Take 15 min away** and **Free play
  until a time (not counted) ›** (until a time or turned off, with or without bedtime). One tap gives, with Undo; the
  toast says what happened ("+15 min of Games for Sam"). The page picks the service:

  | Choice | Daily time left? | Service |
  |---|---|---|
  | Anything +N | any | `hearth.add_time` (bonus time) |
  | A category +N | yes | `hearth.raise_cap` by N |
  | A category +N | no | `hearth.add_time` with `category` (its own bonus, past daily time) |
  | A category, rest of today | yes | `hearth.raise_cap` `no_cap` |
  | A category, rest of today | no | `hearth.unlimited` until the end of the day (a raise wouldn't help) |
  | Anything, rest of today | any | `hearth.unlimited` until the end of the day |
  | Take 15 min away | any | `hearth.remove_time` (only what was given today; it says when there's none) |

Family today, by pool is on the Family tab. Every length of time on the page is in the one format (`45 min`, `2 h
10`), and times of day as `till 6:30`. Ids (packages, entities) are only ever in a tooltip.

#### The family card (a TV's dashboard)

The integration serves a Lovelace card, `custom:hearth-family-card` (`frontend/hearth-family-card.js`), and adds it to
every dashboard as noiwid's Family Link and Family Safety integrations add theirs, so there is no resource to add. It
subscribes to the household summary and draws the spec's sections 2.1 to 2.6 for a TV across the room (big type,
buttons a remote reaches, arrow keys that move between them): the household headline, requests waiting (their yes
and no) and suggestions with their buttons, the family pause at the end of that row, one tile per kid (name, the All
bar colored by state, `day_line`, what's on, 7 bars for the last 7 days with the budget tick and out dots, and the
give button for the pool that binds), and each pool today with every kid's state in it. Groups without a budget today
are left out (decision 6). The text is the summary's, lower case as it comes. Only an administrator or an adult sees
it (the summary's own rule); a kid's sign-in gets "Hearth's family card is for adults." Buttons run as the signed-in
user, after the action's `confirm`.

To give a TV its view: Settings > Dashboards > Add dashboard > New dashboard from scratch, titled "Hearth TV" with the
URL `hearth-tv` (it can be hidden from the sidebar), then in its raw configuration editor:

```yaml
views:
  - title: Family
    path: family
    type: panel
    cards:
      - type: custom:hearth-family-card
        title: Family        # optional
        autofocus: true      # optional: focus the first button when it opens (the default)
```

Open `/hearth-tv/family` on the TV, signed in as an adult's user. After an update of Hearth, a restart of Home
Assistant fetches the new card.

#### Suggestions

Each person in the summary also has `suggestions`, and `household.suggestions` lists everyone's (with `person` and
`person_name`), out of All screen time first. A suggestion is what an adult will likely be asked for next, with the
answer ready: `{key, text, level, reason, minutes, group | device, actions}`.

| Reason | When | Text | Key |
|---|---|---|---|
| `group_out` | a group with a budget is out (and no allow lifts it) | `games ran out · give 15?` | `more:<group>` |
| `group_out` | All screen time is out: then only this one, since more of a group wouldn't open anything | `screen time ran out · give 30?` | `more:all` |
| `device_limit` | Google's, Microsoft's or Nintendo's own limit stops a device while Hearth's time isn't out | `xbox · microsoft's limit · give 15?` | `device:<target>` |

There's no suggestion while a request for it waits (its yes and no are the actions then), while extra time on that
device runs, or after an adult chose "not today". The amount is the household's own for that kid and group (Pushed to
phones), else what an adult usually gives them (History), else 15 minutes (30 for All screen time). The actions
are two amounts (`hearth.add_bonus`, the first `primary`) and "not today" (`hearth.dismiss_suggestion` with the key),
which puts it off until midnight. Each also has `sentence` and `detail`, for a page that writes sentences: "Sam's
YouTube time is up" / "Used 1 h 14 of 1 h · 1 h 45 of screen time left"; "Sam's Xbox is stopped by Microsoft's limit"
/ "Microsoft's own limit for today" (a device by its `display_name`).

**Held back.** A suggestion that wouldn't help now waits instead of showing (glance.hold_back): none while the kid is
in a lock (bedtime, School time) or paused, none after their bedtime starts (or from 21:00 to 6:00 when they have no
bedtime), and a device's own limit only while that device is in use (something plays there, or a request came from
it). At most one shows per kid, and none while a request of theirs waits: the rest wait as `more`. The held ones are in
each person's `suggestions_held` and in `household.suggestions_held` (with `person` and `person_name`): the suggestion
with `held` (`lock`, `paused`, `after_bedtime`, `after_cutoff`, `not_in_use` or `more`) and `why` ("in bedtime till
7:00", "after 9:00 pm", "not on the Xbox now"). The phones follow the same rules: a held suggestion isn't pushed (one
waiting only behind another of the kid's still is).

Extra time given by mistake comes back with `hearth.remove_bonus` (person, minutes, group: All screen time by
default), the page's Undo: it takes back up to the minutes given today, never more (their own budget stays, and
chores' minutes too), is logged as a negative bonus (`undo: true`), and when All screen time is none again, what Family
Link and Family Safety got for it goes too. Adults only, as every Hearth service.

##### Pushed to phones

Per kid and group (or one device of theirs), the household can have a suggestion also go to the adults' phones: in
the Kids tab of Hearth's page (Suggest to phones: All screen time and each group with a limit, a toggle and +15, +30,
+45 or +60), or Configure > Suggest more time to phones. Everything is off by default. The option is `suggest_push`:
`[{person, group | device, minutes?}]` (`minutes` one of 15, 30, 45, 60, the suggestion's first amount; without it,
the amount above).

- **Once a day.** A chosen suggestion is pushed when it appears (the household is looked at 10 seconds after it last
  changed), at most once a day per suggestion: each push is logged (`pushed`, with the suggestion's key), so a restart
  doesn't push it again. One put off today ("not today") isn't pushed.
- **The notification.** To every adult's phones (the `adults` audience, as requests), never the kid's and never Home
  Assistant's bell: title "Sam's YouTube ran out" (or "Sam's Xbox reached its own limit"), text "Give 30 more minutes
  today?", the suggestion's buttons ("+30 min", "+15 min", "Not today") as `HEARTH_ACT|suggest:<person>:<key>|<n>`,
  run as the adult who pressed one. Its item key is `suggest:<person entity id>:<suggestion key>`, its tag
  `hearth_suggest:<person entity id>:<suggestion key>`.
- **Off the phones.** When the suggestion goes (more time given anywhere, put off, the group no longer out, a new day,
  the pair no longer chosen), it's cleared on every phone. After a restart, one still on the phones gets its buttons
  back and is cleared the same way.
- **At most 6 an hour.** Past that, a suggestion isn't pushed (not later that day either); it's still in the household
  summary.

A group running out no longer makes an offered request (older Hearths' Configure > Offer more time, option
`offer_more`): its pairs become pushed pairs with their amounts when the household loads, so the adults get one
notification for it, not two. An offered request (`offered: true`) still works as before where one is made.

#### History

Hearth keeps 90 days of what happened with each person's time (history.py): a group running out (`out`), a request
(`ask`), an offer (`offer`), an answer (`answer`, with its status), a bonus to a group (`bonus`) or on one device
(`device_bonus`), a suggestion put off (`dismiss`), one pushed to the adults' phones (`pushed`, with its key) and a
TV notice's button an adult answered (`notice_answer`: `via` `pin` or `phone`, `by` the adult's person, else `user`
their user id, the notice's `key`, the button's `action` and the TV's `device`), what each person played (`played`:
`item` the title, game or app as shown, `device` where (a Hearth device id, `source:<id>` or `nintendo:<entity>`) and
`minutes`, once a play of a minute or more ends; one event per person, item and device a local day, a later play of
the same adding its minutes; at most 50 a person a day, kept 28 days; a play in progress when Home Assistant stops is
cut there), and each local day's final minutes
(`day`: `date` and `minutes` {group id: minutes, seconds / 60 rounded}, every group of the household), logged for every
person when the day turns. When Home Assistant was down at midnight, the first look after it starts records yesterday
from what the Hearth devices last posted for it and the live sources' timings (a totals sensor has started the new day
by then, so its time is missing; someone with only totals sources gets no record). Events hold entity ids, group ids, device ids, minutes and times,
never names or notes. Suggestions are sized from it: the most common bonus for a kid and group over the last 28 days,
once there are at least 3. Minutes per kid and group are already recorded by Home Assistant's statistics (each
group's Today sensor is `total_increasing`).

#### Activity

Hearth keeps a durable log of what it did (activity.py), 14 days, with Home Assistant's storage helper. The count is
capped per kind: at most 5,000 calls and 2,000 of each other kind, so a busy evening of calls never pushes out the
holds (`hearth.release_stray_pauses` reads a week of them). A routine read that changes nothing (the Nintendo
applications list, every 10 minutes) is recorded only when it fails:

- **Calls** to other integrations: every `familylink.*` (pauses and resumes, the backstop's `set_daily_limit`, blocks
  and unblocks, bonus time, bedtime and School time), `microsoft_family_safety.*`, `nintendo_parental_controls.*`,
  and the others Hearth makes (switches, buttons, notifications): `{at, kind: call, person, target (entity or device
  ids), service, args, why, result: ok | failed, error, duration_ms}`. Every call goes through one helper
  (`activity.call_service`; a test fails if a module calls `hass.services.async_call` itself). `args` keeps ids,
  minutes, times and packages only: never a message, a PIN or a token, and a notification's text not at all. The
  person is found from the entity or Family Link child the call names when the caller doesn't say.
- **Holds**: `{kind: hold_start | hold_end, person, target (a group, app or package ids), reason (daily_time, limit,
  budget, pause, school_time, blocked_app, time_given, parent_grant...), by (hearth, a parental control, or the adult's
  person entity)}`: Hearth's own (daily time or a limit used up, and given back), Pause screens, each parental
  control's hold and let go, and a parent's change in their own app that lifted one.
- **TV commands** (`tv_command`: the TV and profile) and **Glint inbox writes** (`glint_inbox`: the phone, the action
  and its request id).
- **Standing rules** (`rule`: Messages when away going on or off for a kid): `{person, target (its apps), reason:
  away_messages, result: opened | closed}`. Never where anyone was.

People and devices appear by their entity or device ids, never a name. Read it with `hearth.get_activity` {`person`,
`kind`, `since`, `until`, `limit` (200)} (response only; adults, as every Hearth service), the WebSocket
`hearth/activity` (same fields), or the page's Activity view (filter by kid; failures stand out).

**Debug logging.** Settings > Devices & services > Hearth > Enable debug logging turns on `custom_components.hearth`'s
debug lines (no manifest `loggers` entry is needed: that is for third-party libraries): what each source counted per
device, the time model's numbers per kid when they change, every call with its result and time, each hold started or
ended and why, the backstop's inputs, value and why it skipped a write, block tries and confirmations, and changes a
parent made in their own app. Lines name people by entity id, never a name or a token.

**Diagnostics** (Download diagnostics on Hearth's entry): the options, each kid's time, enforcement and backstop state
now, and the last 200 activity records. Tokens, PINs, names, Family Link child ids, emails, Wi-Fi names and places are
redacted, and each person's entity id (and any entity named after them) becomes person_1, person_2...

### Play on a TV

**Proposed for the TV; built in Home Assistant.** `hearth.play_on_tv` starts something on a paired Hearth TV, from an
automation, a dashboard or a phone (Glint calls it as any Home Assistant service): `device_id` (the TV's Hearth device
id, or its device in Home Assistant: a device selector gives that), `what` and, optionally, `profile`.

- `what` is a **YouTube video** (an 11-character id, or a `youtube.com` / `youtu.be` link), played in HearthTube; an
  **app** (its package name, `com.example.app`), opened; or any other **http(s) link**, opened as a link. Anything else
  (another scheme, `intent:`, `file:`, `javascript:`) is refused.
- `profile` is a TV profile id as that TV reports it (`user:10`, `user:0:alex`), or a person mapped to one of that TV's
  profiles. Without it, whoever is in front.
- Home Assistant can't reach a TV, so it **queues a one-shot command** in the TV's state document, and the TV takes it
  with its next status answer: within about 2 seconds after it posts, at least every 2 minutes while it's on. The
  service answers (when asked for a response) `{"id", "device_id", "expires"}`. A TV that hasn't posted in 15 minutes
  (not connected) is refused; a phone isn't a TV (a device whose caps say `commands.play` is played on as a TV is).
- **Hearth on a TV doesn't take plays yet**: it declares its caps without `commands.play` (`events` and `notices`), so
  the service refuses it at once ("its Hearth doesn't take plays") rather than queueing a command that would expire
  unanswered. A TV from before caps gets its kind's default, which still includes `commands.play`.
- A new play for the same TV replaces one still waiting (only the last ask is played). A command waits 3 minutes,
  then it's dropped. Commands are kept while the household reloads (an options change), not over a restart.
- `hearth_command_done` (`device_id`, `id`, `type: "play"`, `result`, `error`) tells how it went, once: `ok`, `failed`
  or `refused` as the TV says, `replaced` by a newer one, or `expired` when the TV never took it.

What the TV gets, in its state document (the document's `version` changes with it; always a list, empty when there's
nothing to do):

```json
"commands": [
  {"id": "k3Jx9QmT2bVw8LpZ", "type": "play", "video_id": "aBcDeFgHiJk", "profile_id": "user:10",
   "created": "2026-11-06T18:00:00+00:00", "expires": "2026-11-06T18:03:00+00:00"}
]
```

Exactly one of `video_id`, `package` or `url`; `profile_id` null for whoever is in front. What the TV must do
(not built yet; an added field, so `contract` stays 1, and a TV that doesn't know `commands` ignores it as before):

1. For each command whose `id` it hasn't run, and not past `expires` (by Home Assistant's clock, as near as the TV's
   is): run it once. Keep the ids it ran (or refused) until they're gone from the document, since the same command
   comes again in every answer until the TV says it's done.
2. `profile_id` other than the one in front: switch to it as a pick on Google TV's profile chooser would (a locked
   profile asks for its PIN or a phone's approval as usual); if that isn't done within the command's time, it's
   `failed`, `profile`. An unknown profile is `refused`, `no_profile`.
3. Play it as if picked on the TV, under the same rules: in a kids profile a held app, time that's up, a lock, a pause
   or a parent's YouTube block refuses it (`refused`, `held`, `locked` or `blocked`); a video goes to HearthTube
   (its own blocks and allowance apply there), never to YouTube's own app; an app that isn't installed is `failed`,
   `not_installed`; a link opens in what the TV has for it (in a kids profile only an app that profile may use).
   A TV whose screen is off may turn it on first, if it can; otherwise `failed`, `screen_off`.
4. Say what happened in its next status post, at once (as for any change):
   `"commands_done": [{"id": "k3Jx9QmT2bVw8LpZ", "result": "ok" | "failed" | "refused", "error": "held"}]` (a bare
   id means `ok`; `error` is a short reason, at most 64 characters; at most 20). Home Assistant drops those from the
   queue; an id it doesn't know is ignored, so saying one again is harmless.

### Media rooms

For a phone's "what's playing where" (Glint's Music), the household summary and every phone's state document (a kid's
too) carry `media_rooms`: `[{room, area_id, entity_id, also, kind, players}]`, rooms by name, then speaker groups.

- A home often has several `media_player` entities for one thing: an Echo and its "Now Playing" twin, a console and its
  Music Assistant player, a TV's remote and its Cast player. Entities are one **player** when one's entity_id or name
  is another's plus a known suffix (`_now_playing`, `_music_assistant`, `_media_player`, `_2`; " (Music Assistant)",
  " Now Playing", " Media Player"). A player's `entity_id` is the one to control (the integration closest to the thing:
  Android TV Remote, the receiver's own, Xbox, ESPHome, Alexa Media, Cast, then Music Assistant; an unavailable one
  last), and `also` holds its twins. `kind`: `tv` (a TV or console), `speaker` or `group`.
- `players`: every player in the room, each `{name, entity_id, also, kind}`. The room's own `entity_id`, `also` and
  `kind` are its first player's: its TV, else the first by name.
- A player counts in the room of its area (any twin's, the entity's or its device's). Players in no area are left out,
  but speaker groups ("Everywhere"), each listed as a room of its own (`kind: group`, named as the group). Hidden and
  disabled entities are left out.
- Read from Home Assistant's registries and entity names only, never from what's playing, so it changes only when the
  house's setup does. Without Hearth's integration, a phone groups players its own way.

Chores never join `approvals`: there is no approval step (see [To-do lists](#to-do-lists)).

## Away from home

TVs stay on the home network. A phone isn't always there, so `mobile` devices also get a **webhook** the integration
registers (`webhook.async_register`, not local-only), and, when Home Assistant Cloud is set up, a cloudhook URL for it.
The device's secret is still required on every call: knowing the URL isn't enough. (The webhook isn't built yet.)

**Push to phones (H-6, built in Home Assistant).** Home Assistant to the phone uses a push channel the phone holds open
([ntfy](https://ntfy.sh), per Hearth Mobile's design), carrying only "something changed"; the phone then fetches its
state with its secret. Optional and off unless the household names an ntfy server (Hearth's page, Devices > Push to
phones, or Configure > Push to phones): ntfy.sh or one of your own, `http(s)://host[:port][/path]`, without a user
name, password or query. Without one Home Assistant sends nothing and works as before; phones update at their next
status post.

- **A topic per phone.** Each phone gets its own random topic when it pairs (32 characters of `A-Z a-z 0-9 _ -`,
  as long as a secret: on a public server, whoever knows the topic can listen to it and post to it). Pairing again
  makes a new one; a phone paired before this got one when the household next loaded. TVs have none. (Who gets pings
  follows caps, see [Device status](#device-status): a device that says `push` gets a topic when the household next
  loads, and one that leaves it out of the caps it says gets no pings.)
- **Where the phone hears it.** The approved pair answer and every status answer to a phone carry `"push":
  {"server": "https://ntfy.example.com", "topic": "<topic>"}`, or `"push": null` while there's no server (an added
  field: `contract` stays 1). The status answer is the one to follow: the server can be set, changed or removed at any
  time.
- **When.** When the phone's state document has a `version` the phone hasn't had: not in a status answer (what a phone
  was just handed isn't news) and not in an earlier ping. Changes come together, so a ping goes 5 seconds after the
  first, and to one phone at most every 30 seconds (a later change waits out the rest, then goes). Home Assistant
  starting, or the household reloading, may ping each phone once.
- **What.** `POST <server>/<topic>` with the body `changed` (text/plain), nothing else: never a name, a number, the
  version or anything of the state. A failure is logged (without the topic) and not tried again: the next change, or
  the phone's next status post, catches up.
- **What the phone does** (Hearth Mobile, Glint; not built yet): subscribe to `<server>/<topic>` (ntfy's JSON stream,
  WebSocket or UnifiedPush), and on any message post its status with its secret as usual: the answer carries the
  state document. A ping that says anything but `changed` is treated the same: the message is never read for content.
  Away from home that post needs the webhook above; until it's built the phone catches up when it's back on the home
  network.

## Setting it up

**Hearth's page** (the Hearth entry in the sidebar, administrators only) does all of it in one place, with a guided
setup the first time: who's a kid and who's an adult, parent PINs, pairing TVs and phones (the code is checked and
approved on the page), TV profiles, screen time sources, daily limits, bedtime and school-time locks, other parental
controls, groups and their apps, school days, sharing app data and the push server for phones. Its **Today** tab
shows each kid's time left and what's playing, with buttons for extra time, and each TV and phone. It is
`custom_components/hearth/frontend/hearth-panel.js`, a plain custom element on the WebSocket commands in `panel.py`
(`hearth/config`, `hearth/config/set`, `hearth/budget`, `hearth/pairing`, `hearth/parent_pin`) and the household
summary; settings are saved to the entry's options as the Configure menu saves them, and budgets as the services set
them.

Each kid's card also pauses that kid alone (`hearth.pause` with `people`), ends an app or group pause, takes School time
off today (or puts it back), and opens **Today by device and app**: minutes per device with +15 on one device
(`hearth.add_bonus` with `device`) and the apps used most. The **Kids** tab has a card per Nintendo Switch of theirs
(today's play, the Switch's own limit, time left and extra time, playing now, last synced), with Hearth's extra time on
that Switch and, as the installed Nintendo integration allows, Nintendo's own extra playing time, its cancel and the
games' allow list, and **Suggest to phones**: per group with a limit (and All screen time), whether its suggestion
also goes to the adults' phones and the amount (`suggest_push` in `hearth/config` and `hearth/config/set`, checked:
a kid, a group id or a device, 15, 30, 45 or 60 minutes, each pair once; see [Pushed to phones](#pushed-to-phones)).
`hearth/config` says what the installed integration can do (`capabilities.nintendo`: `installed`,
`add_bonus`, `bonus_min`, `bonus_max`, `unlimited`, `cancel_bonus`, `list_apps`, `set_app_allowed`, found by probing
the services' own schemas, so core's 5 to 30 minutes and a patched copy's 5 to 360 or unlimited both show right) and
how each parental control is doing (`parental_controls`: each installed integration's entries and their state, and
Family Safety's Connection sensor), shown on **Devices** and, when one isn't working, on **Today**. The page's Nintendo
commands (`hearth/nintendo/bonus`, `hearth/nintendo/bonus_cancel`, `hearth/nintendo/apps`,
`hearth/nintendo/app_allowed`) take the kid and the Switch's device id, check the Switch is theirs and the service is
there, and refuse Nintendo's own extra time while Hearth holds that Switch (Hearth's extra time on it lets the hold go
instead; Nintendo's on a held Switch would read as a parent's change in the Nintendo app). See
[dashboard-parity.md](dashboard-parity.md) for how the page compares with the Family Link and Family Safety dashboards.

The Configure menu (Settings > Devices & services > Hearth > Configure) still has everything, as a menu:

**Who's who on the TVs**, **Add / Remove a screen time source**, **Add / Remove a title**, **Locks** (bedtime,
school time), **Enforce limits** (Family Link, Family Safety, Nintendo), **School days**, **Schedule**, **Places**, **Website
block list**, **Suggest more time to phones**, **Sort new apps**, **Watch for new apps**, **Add a group**, **Add apps to Video or Games**, **Not screen time**, **Remove a group**, **Tile
exchange sharing** and **Parent PINs**. (Suggested title matches and rules aren't built.)

Budgets aren't in the options: they're number entities, so a dashboard, a voice assistant or an automation can change
them like any other. Titles and groups are kept in the entry's options; budgets, bonuses and what's held with Home
Assistant's storage helper.

## Entities

Per Hearth device: as in [Kinds](#kinds).

Per person (a device of its own in Home Assistant, "Hearth: <person>"):

| Entity | Type |
|---|---|
| Screen time today | duration; attributes per device, per group, each group's apps and Not screen time groups |
| <group> today, for each group but All screen time | duration |
| <group> budget on school days / on other days | number (minutes, -1 for no limit) |
| <group> minutes left, for each group | duration |
| <group> bonus today | number (minutes) |

The budget and bonus numbers can be changed by an automation, an administrator or an adult on Hearth's page (as
Hearth's services, [Security](#security)); anyone else's change is refused with an error.
| Playing | sensor: the title or app now, and where |
| Playing together today | duration |
| Held by parental controls | sensor: what Family Link, Family Safety or Nintendo holds now |
| Locked | binary sensor |
| Place, for each kid | sensor: a place key, away or unknown (see [Places](#places)) |
| Mode, for each kid | sensor: the weekly schedule's mode now (see [Schedule](#schedule)) |
| Bedtime, for each kid | sensor: tonight's bedtime (timestamp), with `wake` |

Per household: **Playing together** and **School day** (binary sensors), **Apps to sort**, **Day type**. Open requests for more
time are in the household summary and on Hearth's page, not an entity.

Events: `hearth_budget_reached` (person, group, group_name), `hearth_more_time_requested` and
`hearth_more_time_answered` (as in [Ask for more](#ask-for-more)), `hearth_playing_together` (title, people, started
or ended), `hearth_enforced`, `hearth_new_app`, `hearth_parent_pin_used`, `hearth_parent_pin_locked_out`,
`hearth_schedule`, `hearth_chore_done`, `hearth_chore_reversed`, `hearth_place` (person, from, to), `hearth_mode` and
`hearth_schedule_changed` (see [Schedule](#schedule)), `hearth_tv_profile_changed` (see
[contracts/device-presence.md](contracts/device-presence.md)).

Per person with a TV profile: **Last video started** (see [A kids profile's YouTube](#a-kids-profiles-youtube)).

Services: `hearth.add_bonus`, `hearth.remove_bonus`, `hearth.set_budget`, `hearth.pause`, `hearth.pause_end`, `hearth.allow`,
`hearth.allow_end`, `hearth.explain`, `hearth.school_time_off`, `hearth.school_time_off_cancel`, `hearth.home_today`,
`hearth.home_today_cancel`, `hearth.set_schedule`,
`hearth.copy_schedule`, `hearth.change_today`, `hearth.resume_schedule`, `hearth.get_schedule` (see
[Exceptions](#exceptions) and [Schedule](#schedule)), `hearth.play_on_tv` (event
`hearth_command_done`, see [Play on a TV](#play-on-a-tv));
`hearth.get_watch_log`, `hearth.watch_digest`, `hearth.block_video`, `hearth.block_channel`, `hearth.block_word` and
their `unblock_` twins. Event `hearth_video_started`.

## The device's side of the API

What step 1 built. Every endpoint answers local network addresses only (403 otherwise) and answers JSON; errors are
`{"error": "<reason>"}`.

**Pairing.** Once the household is set up:

1. `POST /api/hearth/pair` with `{"device_id", "kind", "name", "model", "version", "nonce", "client"}` (`client` since contract 3, see [contracts/device-api.md](contracts/device-api.md); a malformed one is 400). `device_id` is the
   device's own stable id (8-64 of `A-Z a-z 0-9 _ -`, made once and kept); `kind` is `tv` (the default) or `mobile`;
   `nonce` is 32-128 of the same characters, random, made for this pairing and never shown. Answers
   `{"pairing_id", "code", "expires_in"}` (seconds, 600). The device shows `code`. 404 `not_set_up` when the household
   isn't set up, 429 `try_later` when this address asked in the last 10 seconds or five devices are already waiting,
   400 `bad_request` for a malformed body or an unknown kind.
2. Home Assistant shows a discovered **Hearth** device named `name`; an administrator checks the codes match and
   confirms. Asking again from the same device replaces its earlier request.
3. The device polls `GET /api/hearth/pair/<pairing_id>` with header `X-Hearth-Nonce: <nonce>` (every 2 seconds is
   plenty): `{"status": "pending"}` (or `{"status": "denied"}`), then once `{"status": "approved", "contract",
   "device_id", "secret", "person", "role", "urls": {"internal", "external"}}` (`role`: `kid`, `adult` or null; a URL
   null when unknown). After that, or once the request expires (10 minutes, or 2 minutes after approval), it's 404
   `unknown`. A wrong or missing nonce is 404 too. A phone's approved answer also says `push` (see
   [Away from home](#away-from-home)).
4. The device keeps `secret`, and nothing else of Home Assistant's.

**Tickets** (a paired TV only). `POST /api/hearth/device/<device_id>/ticket` with header `X-Hearth-Secret` and
`{"kind": "tv"}` (for another TV of its household) or `{"kind": "mobile", "person": "person.alex"}` (for a phone an
adult bound as that adult's; `person` must be an adult on Hearth's page, else 403 `not_an_adult`) answers
`{"ticket", "expires_in": 300}`. 403 `not_a_tv` from a phone; 429 `too_often` past the status rate, or `try_later` with
ten tickets outstanding. A ticket is single use and lives five minutes; Home Assistant keeps only its hash.
`POST /api/hearth/pair/redeem` with `{"ticket", "device_id", "kind", "name", "model", "version"}` pairs that device at
once and answers as an approved pairing does (step 3 above, `person` the ticket's). 404 `unknown` for a ticket that's
unknown, used, expired, of another kind, or whose TV was removed since; it's spent either way. Each redeemed ticket
fires `hearth_device_paired` (`device_id`, `name`, `kind`, `person`, `by`: the TV that vouched) and leaves a
notification.

**Status.** `POST /api/hearth/device/<device_id>/status` with header `X-Hearth-Secret: <secret>` and the status JSON
(see [Device status](#device-status)), at most 64 KB. 200 (below); 401 `not_paired` for an unknown device or
wrong secret (it was removed: stop posting and offer to pair again); 429 `too_often` past 20 posts a minute; 400
`bad_request`. A refused secret is a plain 401, never a failed Home Assistant login, so it doesn't count toward Home
Assistant's IP ban. The 200 answer carries the device's state document, `{"ok": true, "contract": 3, "state": {...}}` (see
[What a device gets](#what-a-device-gets)). Every device endpoint answers 503 `not_set_up` while the integration is
loading: try again, don't unpair. A TV with screen-time rules of its own (set before it was paired, household-sync.md "Screen time without Home
Assistant") sends them as `local_rules`, `{"<profile_id>": {"all": {"weekday", "weekend"}, "groups": [{"id",
"weekday", "weekend"}]}}`: once a profile is mapped to a kid who has no budgets yet, they become that kid's budgets
(only the groups Home Assistant has; bedtime isn't taken), with a notification. Each TV profile is taken or passed
over once, so a budget cleared later doesn't come back. A device may also send `app_categories`, `{"<package>": "game" | "video" | ...}`
(Android's category, lower case), which helps sort its apps into Video, Games, Social or Messaging. A TV's
document also carries `commands` (one-shot commands such as a play, see [Play on a TV](#play-on-a-tv)), and the TV
says which it ran in `commands_done`. A phone's answer also says `push` (its ntfy channel, or null; see [Away from
home](#away-from-home)).

**Notices** (a TV whose caps say `notices`; never a phone). Its state document carries `notices`, what the adults
should see on it (attention items for TVs, see [Attention](#attention); so far the suggestions pushed to phones),
oldest first:
`[{"key", "tag", "title", "message", "for"?, "urgency": "info" | "notice" | "urgent", "actions": [{"id": "0", "title"}],
"expires"?}]`. `for` is a person entity id from the document's `people` (that adult's profiles only); without it, every
adult profile, never a kid's. The TV shows them as Home Assistant notifications to it (a `tag` replaces one with the
same tag); one gone from the list is cleared. `actions` carry only a button's number and title, never a service. The
fields stay the same while the item does (no countdowns), so an unchanged notice doesn't wake the TV's wait; a new one,
or one gone, does. A TV without the cap gets no `notices`.

**Wait for a change** (any paired device). `GET /api/hearth/device/<device_id>/wait?version=<v>&timeout=<s>` with
the same header holds until the device's state document is no longer version `<v>` (the `version` of the last
document it got), then answers `{"changed": true}`; after `<s>` seconds (at most 55) with nothing changed it answers
`{"changed": false}`. A missing or old `<v>` answers changed at once. It never carries the document: on changed the
device posts its status and reads the state from that answer. One wait per device: a new one ends the previous with
`{"changed": false}`, and so does an options change (the integration reloads), so ask again. 401 and 503 as for
Status; 400 for a bad `timeout`. A TV holds one while it's paired and its screen is on, so a pause, a lock or an
answered request reaches it within seconds rather than at its next two-minute post; a phone holds one only while its
ask waits. An older integration answers 404: keep posting as before.

**Events** (a TV, or a device whose caps say `events`). `POST /api/hearth/device/<device_id>/events` with the same header and
`{"events": [...]}`, at most 50, each `{"type": "video_started", "profile_id", "t" (ms), "v" (video id), "title",
"ch" (channel name), "cid" (channel id), optional "pa" (true: a parent's PIN let it play past the limit or a lock)}`. `profile_id` is the TV's own key for the profile (`user:10`), resolved
with the TV it came from as in [TV profile keys](#tv-profile-keys). 200 `{"ok": true, "added": n}` once all are taken:
an entry of a profile mapped to no one, or one that isn't valid, is dropped, and a resend is harmless, so the TV marks
them all sent. 403 `not_a_tv` from a device without `events` (a phone, by default); 429 `too_often` past 10 posts a minute; 400 for more than 50 or a
malformed body.

**Parent PINs** (any paired device). Each adult on Hearth's page has their own (4 digits), set in Configure > Parent PINs or on Hearth's page, and kept as a salted
hash in the TV's form (`v2$<iterations>$<salt>$<hash>`, PBKDF2-HMAC-SHA256); any of them is a parent PIN.
`POST /api/hearth/device/<device_id>/verify_pin` with the same header and `{"pin": "<4 digits>"}`: 200
`{"ok": true, "person": "person.alex", "grant", "grant_expires": 120, "grant_writes": 8}` (the grant: contract 3, [contracts/device-api.md](contracts/device-api.md)) or `{"ok": false}`, and a right one fires `hearth_parent_pin_used`
(`device_id`, `person`). After 5 wrong PINs in a row the device waits 30 seconds, doubling with each further wrong one
up to an hour: the wrong answer that starts a wait says `retry_in` (seconds), and until it ends every try is 429
`{"error": "locked_out", "retry_in": s}`, the right PIN included. A right PIN clears the count. Each lockout fires
`hearth_parent_pin_locked_out` (`device_id`, `failures`, `retry_in`) for an automation to tell the adults. 404 `no_pin`
when none is set (the device uses its own); 400 for a `pin` that isn't a string. A phone never gets a hash.

A **TV** asks `verify_pin` too, and Home Assistant's answer (its lockout included) is final whenever it's reachable. To
check PINs with Home Assistant down, its state document carries `parent_pins`, `[{"person", "name", "hash",
"profiles"}]` (`profiles`: that adult's TV profiles), which replace the TV's own Parent PIN while it's paired; the TV keeps
them sealed with an Android Keystore key. They're sent only when they changed: the document always says
`parent_pins_version`, and the TV posts the version it keeps in its status (`parent_pins_version`); a document with the
version alone means its copy is current, and one with neither means Home Assistant has none (the TV keeps its last
ones, no longer managed). The TV keeps its own lockout too and posts `pin_lockouts` (how many it has had, only going up)
in its status; each rise fires `hearth_parent_pin_locked_out` (`device_id`, `lockouts`: how many new, `retry_in`: null).

**A notice's button** (a TV that shows notices). `POST /api/hearth/device/<device_id>/notice` with the same header and
`{"key": "<a notice's key>", "action": <its button's id as a number>, "pin": "<digits>"}` or `{..., "approval":
"phone"}` (exactly one of the two). A secret alone never runs a service:
- With `pin`: checked as `verify_pin` checks one (any adult's Parent PIN, the same lockout: wrong guesses here and
  there count together, and a right one fires `hearth_parent_pin_used`). The button's service then runs as that
  adult: as their person's Home Assistant user when it's an adult's or an administrator's, else as the household's
  own (no user, as an automation); the history names the adult either way. 200 `{"ok": true, "done": true}`.
- With `"approval": "phone"`: the adults' phones are asked (see [Attention](#attention), On the TVs), and an adult's
  tap there runs it as them. 200 `{"ok": true, "pending": "phone"}`; the notice going from the document is the TV's
  sign it was answered.

Only a button the TV was shown runs (a `hearth` service; the notice's own number). Errors: 404 `gone` (no such notice
in this TV's document now, or the TV doesn't declare `notices`); 403 `wrong_pin` (also when Home Assistant has no
Parent PIN), with `retry_after` (seconds) on the wrong one that starts a lockout and on every try until it ends, the
right PIN included; 400 `bad_request` (a malformed body, both or neither of `pin` and `approval`, a button that isn't
there or doesn't run); 429 `too_many` past 6 presses a minute; 401, 403 `not_local` and 503 as for Status; 500
`failed` when the service itself failed.

**A kid's to-do item** (a phone paired to a kid). `POST /api/hearth/device/<device_id>/todo_item` with the same header
and `{"entity_id": "<their list>", "uid": "<an item's>", "status": "completed" | "needs_action"}` checks one of the
kid's own items (`todo_lists` in the phone's state document) off or back, as the kid themselves: a chore's reward is
granted with no approval step and the adults are told with an Undo. 200 `{"ok": true, "entity_id", "uid", "status",
"granted"}`. Refusals carry `error`, `code` (the same) and a `message` to show: 400 `bad_request`; 403 `not_yours` (a
TV, a phone of an adult's or nobody's, another list); 404 `unknown_item`; 409 `undone` (an adult undid its reward)
and 409 `too_often` (the item's reward was earned 3 times today: tick, untick, tick again... An adult can still tick
it); 429 `too_often` past 20 check-offs a minute, counted apart from the phone's asks and events; 401, 403
`not_local` and 503 as for Status. The contract is in
[contracts/device-api.md](contracts/device-api.md#a-kids-to-do-list-additive-within-contract-3).

**Phone approval of a switch** (a TV; switch_approval.py). A paired TV asks the integration to have an adult allow a
switch into their PIN-locked Google TV profile from their phone, so it needs no Home Assistant token of its own:
- `POST /api/hearth/device/<device_id>/switch_approval` with the same header and `{"profile_id": "<the TV's profile
  key>", "phone": "mobile_app_…"}` (`phone` optional: the one chosen on the household's TVs). The profile must be
  mapped to a person who is an adult on Hearth's page. The phones asked are `phone` when Home Assistant has that
  notify service, else the person's companion apps (as `adult_phones`). Each gets "TV: switch to <name>'s profile?"
  with Allow and Deny (action ids `HEARTH_SWITCH_ALLOW_<id>` and `HEARTH_SWITCH_DENY_<id>`, `tag` `hearth-switch-<id>`,
  sticky, two minutes), and Home Assistant's own list gets the same request (under an id of its own, never the
  request's). Only an adult's answer counts (an administrator, or a user whose person is an adult); any other is
  ignored. 200 `{"ok": true, "request": {"id",
  "status": "pending"}, "phones": n, "expires": 120}`. `id` is 128 random bits (32 hex), used once. A TV's newer request
  withdraws its waiting one. Errors: 404 `no_person` (the profile is nobody's), 403 `not_adult`, 404 `no_phone`, 502
  `not_sent` (no phone took it), 400 `bad_request` (not a TV, no profile, a `phone` that isn't a companion app's), 429
  `too_often` (counted with Events), 401, 403 `not_local` and 503 as for Status.
- `GET /api/hearth/device/<device_id>/switch_approval/<id>?timeout=<s>` answers `{"ok": true, "request": {"id",
  "status"}}` as soon as the status isn't `pending`, or after `s` seconds (at most 55): `allowed`, `denied`, `expired`
  (no answer in two minutes) or `withdrawn`. A finished request stays readable for five minutes. 404 `gone` for no
  such request of this TV's (another TV's never shows).
- `DELETE` the same withdraws it (someone at the TV uses the remote, or the PIN screen went): it leaves the phones.

The first answer decides, and the notification then leaves every phone asked and Home Assistant's list. Anyone with
Home Assistant's companion app may answer (whoever holds the adult's phone); the log says who (their person, else
their user id), and `hearth_switch_approval` (`device_id`, `profile_id`, `person`, `answer`, `by`, `user_id`) tells
automations. On Allow the TV types the adult's saved Google TV PIN, only if that profile's PIN screen is still up.

**Entities**, per device, by kind as in [Kinds](#kinds). Screen time today is in seconds (shown in minutes), with
per-app, playing and (on a TV) per-profile attributes kept out of history. All but Connected are unavailable until the
first post and once the device has been quiet for 15 minutes; the last status is kept across restarts. Deleting the
device removes it from the household.

## MCP and voice

Hearth registers a Home Assistant **LLM API**, `hearth` ("Hearth", `llm_api.py`), so a language model can read the
household and act on it with the same rules as Hearth's page. Home Assistant offers it in two places:

- **MCP Server** (Settings > Devices & services > Add integration > Model Context Protocol Server). In its options,
  tick **Hearth** among the LLM APIs (with Assist, if you want both). A client (Claude, say) then uses
  `https://<home assistant>/api/mcp` with a long-lived access token or Home Assistant's OAuth; the token's user is
  who acts. `/api/mcp/hearth` serves Hearth's tools alone, for administrators only (Home Assistant's rule).
- **Assist** (Settings > Voice assistants > an assistant > its conversation agent's options, **Control Home
  Assistant**): tick **Hearth** among the LLM APIs. A chat in the Home Assistant app runs as the signed-in user; a
  voice satellite runs with no user.

**Who may use it.** Every call is checked, and the tools a model is offered follow from it:

- An **adult** (an administrator, or a user whose person is an adult on Hearth's page, as for the services): every
  tool. Actions act at once, run as that user (`Context(user_id)`), and answer with exactly what changed so the adult
  can correct it.
- **No user** (a voice satellite: Home Assistant can't tell who's speaking): nothing, unless **Let voice assistants
  use Hearth** is on (Hearth's page, People tab, or Configure > Voice assistants; `voice_assistants` in the options,
  off by default). With it on, the read tools answer, and an action is **not run**: the adults' phones get "Approve:
  give Sam 30 more minutes of Video today?" (asked by voice, and on which satellite) with the action's button and
  Don't allow, and the tool answers "Sent to your phone for approval". The first adult to tap it runs it as
  themselves, once; it comes off every phone then, on Don't allow, or after 10 minutes (key `voice:<id>`, tag
  `hearth_voice:<id>`, never on the bell). A spoken PIN isn't used: a kid in the room would hear it. Turning the
  option off takes every tool away from voice at once.
- **Anyone else** (a kid with a Home Assistant user of their own): no tools, and each tool refuses them anyway.

**Read tools** (from the household summary and `hearth.explain`; no pairing codes, TV profile keys or coordinates):

| Tool | What it answers |
|---|---|
| `hearth_get_household` | Each person today: All screen time and each group (used, left, budget, bonus), locked and by what, pause, bedtime and School time, playing, the headline; requests waiting; the Hearth devices |
| `hearth_get_person` | One person: the above with minutes per device and per app, allows, pauses, grants, extra time on one device, Google's and Microsoft's own limits, the last 7 days, and their devices' ids |
| `hearth_explain` | Why an app or group is (not) allowed now, until when, what holds it; says when a parent blocked the app in Family Link or Family Safety |
| `hearth_get_suggestions` | Hearth's suggestions (key, text, minutes, amounts) |
| `hearth_get_requests` | Requests for more time waiting, with their ids; those answered in a parent's own app lately |

**Action tools** (each a `hearth.*` service; people, groups, apps and devices by name or id):

| Tool | Service | Answers with |
|---|---|---|
| `hearth_add_bonus` | `add_bonus` (person, minutes -240 to 240, group, device) | the pool or group, minutes left now, today's budget and bonus; the device's extra id |
| `hearth_pause` / `hearth_pause_end` | `pause` / `pause_end` (people, minutes or until, app or group) | each person's pause now |
| `hearth_allow` / `hearth_allow_end` | `allow` / `allow_end` (one person, app or group, until, device) | the allow's id and end, and `explain` after it |
| `hearth_answer_request` | `answer_request` (request id, minutes or deny) | the answer, and minutes left |
| `hearth_dismiss_suggestion` | `dismiss_suggestion` | the suggestion put off today |
| `hearth_school_time_off` / `_cancel` | `school_time_off` / `school_time_off_cancel` | the ids, and the person's School time off |

Every answer also has `done` (in words), the service and its data, how to undo it, and `logged` (the history events
it made).

**What it never does.** There is no budget tool: lasting changes stay on Hearth's page. And Hearth never lets a kid
into an app or game a parent blocked: `hearth_allow` of an app listed in the kid's Family Link **Blocked Apps** sensor,
or reported blocked by Family Safety (other than an app Hearth's own pause blocked), is refused, and so is approving a
Family Safety request for a particular game or app (deny it, or answer it in the Family Safety app). Where the
Nintendo integration can list a Switch's games (`list_applications`), `hearth_allow` of a game on one of the kid's
Switches (by name or id) that isn't on that Switch's allow list is refused too: Nintendo blocks a game by its age
rating unless a parent allow-lists it, and Hearth can't see the rating. These checks are in the tools, not in what the
model is told.

**Audit.** History events an action logs carry `via` (`mcp` or `voice`) and `user` (the Home Assistant user who acted,
or who tapped Allow). An action that logs nothing of its own (a pause, an allow, School time off) logs an `assist`
event: the `tool` and what it did (app, group, minutes, device, until, date), never a reason. Home Assistant's
logbook also has the service call's user.

## Glint agents

Beside `hearth`, Hearth registers a second LLM API, **`glint`** ("Glint", `glint_api.py`), ticked on its own in the MCP
Server's or an Assist agent's options. It lets an agent read and change Glint (the phone home screen, Start) on the
household's phones without waking them, through a mailbox Hearth keeps for each Glint phone (`glint_agent.py`). The
contract is Glint's: `docs/contracts/glint-agent-ha.md` (version 1) in the Glint repository.

**The mailbox.** Three [client settings](contracts/client-settings.md) documents in the phone's own device scope, for
the Glint client it locked at pairing (`com.thesiegs.glint`, or its `.debug` / `.nightly` build):

| Name | `schema` | Written by | Read by |
|---|---|---|---|
| `agent-inbox` | `glint.agent-inbox/1` ("agent requests") | Hearth only (`updated_by: hearth`) | Glint |
| `agent-outbox` | `glint.agent-outbox/1` | Glint only | Hearth |
| `glint-state` | `glint.state/1` | Glint only | Hearth (the tools' reads) |

Neither the phone (device API) nor anyone on the WebSocket may write or delete the inbox (`forbidden`). On the
WebSocket the outbox and state are written only by the user whose person the phone is paired to (Glint, signed in as
them), and the three are read only by that user or, for a kid's phone, by an adult: never another adult's phone. A
kid's phone writes its outbox and state over the device API, and sees its inbox's etag in its state document. An
adult's Glint sees its inbox's etag in `hearth/me`.

A request is `{id, agent, user, user_name, origin, action, args, created, expires}`: `agent` is `mcp` (the MCP Server)
or `assist`, `origin` `text` for the MCP Server and `voice` for anything through Assist (a typed Assist chat can't be
told from a spoken one, so it counts as voice and Glint asks on the phone). At most **20** wait per phone and 32 KiB;
a 21st is refused with `inbox_full`. A request leaves the inbox when Glint's outbox holds a final result for it
(`applied`, `refused`, `expired`) or once past its `expires` (at most 24 hours; a `glint_dnd` for some minutes expires
with them). Hearth then fires **`glint_agent_done`** `{device_id, request, agent, action, status, said, undo, code}`,
once.

**Tools.** Each takes `phone` (a Glint phone's name, any case, or the name of the person whose only Glint phone it
is; optional with one). When several reachable phones share the name, the caller's own is used (the one seen last if
they have several), else the tool asks for the id; phones are listed as "name · person · last seen". Reads answer from
`glint-state` with its age ("as of 6:02 pm"). Writes add a request, ring the doorbell if one is linked, and wait up to 20 seconds:
then the tool answers with Glint's own `said` and `undo`, or `asked_on_phone` ("waiting for Alex to allow it on the
phone"), or `refused` with its `code`, or `queued` ("queued for Alex's phone: glint applies it the next time Start is
open (request r-…)"). A phone whose owner turned agents off (`channel: "off"`), or that has published no `glint-state`
at all, counts as off: every tool says so and nothing is queued. `glint_change_start` describes its ops from a phone's
`glint.hello` list when its state document carries one (`hello.actions` or `actions`), else Glint's own: add,
duplicate, move, resize, remove, restyle, stack, unstack, take_out, name_stack, deals_at, remove_page.

| Tool | Reads | Writes (request action) |
|---|---|---|
| `glint_get_start` | state `start` | |
| `glint_change_start` | | `start.change` `{ops}` |
| `glint_set_look` | state `look` (no `values`) | `look.set` `{values}` |
| `glint_notification_rules` | state `notify` (no `ops`) | `notify.change` `{ops}` |
| `glint_undo` | | `undo` `{undo?}` |
| `glint_activity` | state `activity`, the outbox's results, the requests waiting | |
| `glint_dnd` | | `phone.dnd` `{on, minutes? or until?}` |
| `glint_system_setting` | state `phone` (no arguments) | `phone.settings` `{values}`, `phone.sound` `{ringer?, volume?}` |

**Who may use it.** An adult (as for `hearth`): their own Glint phones and kids', never another adult's. A voice call
with no user, wherever the voice agent has `glint` ticked: adults' phones only, every write `origin: voice` (Glint asks
on the phone first). Anyone else: no tools. On a kid's phone Hearth refuses up front what Glint would refuse anyway:
any voice write (`voice_on_kid_phone`) and the loosening it can see (do not disturb off, any system setting or sound:
`needs_parent`). Each write logs an `assist` history event (`tool`, `device`, `request_id`, `via`, `user`).

**The doorbell (optional).** An adult links a Home Assistant companion app to a Glint phone (their own or a kid's) with
`{"type": "hearth/glint/bell", "device_id", "notify": "notify.mobile_app_<name>" | null}`; `hearth/glint/phones` lists
the phones they reach with their links. A write then also calls that service with `message: command_broadcast_intent`
and `data: {intent_package_name: <the phone's client>, intent_action: com.thesiegs.glint.action.AGENT_BELL,
intent_class_name: com.thesiegs.glint.start.agent.AgentBellReceiver}`: a hint only, carrying nothing; Glint reads its
inbox over its own connection.

**Forgetting a stale phone.** `{"type": "hearth/glint/forget", "device_id"}` (an adult, for their own phone or a
kid's; an administrator, for any phone; a phone that was paired and never seen counts, never a TV) removes it as deleting its device in Home Assistant does: its secret stops working, its documents and doorbell
link go, and its device entry is removed.

## Security

- A device's secret works on Hearth's endpoints only. A leaked one can post that device's status, events and
  requests for more time, and check PINs (with the lockout), never run a service or read a state. Secrets are stored hashed.
- TV endpoints answer local addresses only (checked on `request.remote`, not a header). The phone's webhook is the one
  way in from outside, and it needs the secret too.
- The mailbox holds ciphertext only.
- A phone's push topic only lets someone hear that something changed for it, or send a fake ping: the ping carries
  nothing, and the phone fetches with its secret, so a forged one costs it a status post.
- Approvals (not built yet): one-time request ids, two minutes, only the mapped persons can answer; denied or expired requests are
  cleaned up.
- Everything a device sends is untrusted: only known fields, lengths capped, control characters stripped, numbers
  bounded, never templated.
- Kids' devices hold no Home Assistant token.
- Pairing is the one step that needs an administrator, once: after that, a paired TV can vouch for other devices with
  tickets. A leaked TV secret could therefore pair another TV, or a phone for an adult on Hearth's page; each such
  pairing leaves a notification and fires `hearth_device_paired`, and deleting the device ends it. Tickets travel only
  inside the sealed household sync (TV to TV) or the paired, encrypted TV remote session.
- **Who may call Hearth's services.** Every `hearth.*` service checks its caller: a call with no user (an automation,
  or a script an automation started) may; so may an administrator, and a user whose person is an adult on Hearth's
  page (the rule that lets them read the household summary, auth.py). Anyone else (a kid with a Home Assistant user of
  their own) gets Home Assistant's Unauthorized error, for the read-only ones too (`explain`, `get_watch_log`,
  `watch_digest`): a kid doesn't read the watch log. A script a kid starts from a dashboard runs as the kid, so it's
  refused as well. The same goes for changing a person's budget and bonus number entities (`number.set_value`).
- **Assistants** (MCP Server, Assist) get Hearth's tools only for an adult, or for a voice satellite while Let voice
  assistants use Hearth is on, and then every action waits for an adult's tap on their phone (MCP and voice).
- **A kid's own user** may use `hearth/me`, `hearth/me/subscribe` and `hearth/ask`, which take no person: each is
  the caller's own person (whose `user_id` is theirs), so a kid reads and asks for themselves only.

## Migration

1. Ship the integration alongside the old paths; a paired device prefers the integration.
2. A paired TV stops posting to its old webhook and says so. The old automation, helpers and pool templates are left
   alone and listed as no longer used; the integration offers to remove only what it made.
3. What a household like this one has made by hand, and what takes its place:

   | By hand today | With the integration |
   |---|---|
   | Per-TV status helpers and webhook automations | each TV's device |
   | A YouTube pool (weekday and weekend helpers) and a per-kid "minutes left" template | a YouTube group with a school-day and other-day budget per kid |
   | Per-kid bonus helpers, reset at midnight | Bonus today |
   | Chores automations that add to the bonus | the same automations, calling `hearth.add_bonus` |
   | Pause helpers and start / end scripts | `hearth.pause`, `hearth.pause_end` |
   | `sensor.hearth_allowance` | the state document in each status answer |

   Each moves when an adult chooses, checked side by side in history for a few days first.
4. The webhook path and `sensor.hearth_allowance` are retired: Hearth TV no longer posts to a webhook or reads the
   sensor, and a webhook id an older version kept is forgotten. Pair the TV instead.

### Replacing hand-written automations

Hearth is meant to be the one place a kid's screen-time rules, exceptions and schedules live. Typical hand-written
automations, and what replaces each (the names here are examples):

| An automation that... | With Hearth |
|---|---|
| pauses Messages when `binary_sensor.<device>_school_time_active` turns on, resumes it when off | Configure > Enforce: Family Link, **During School time, pause these apps**. Disable the automation first: a resume from it would undo Hearth's pause, and the other way round. |
| pauses YouTube with `familylink.pause_app` when a "minutes left" template reaches 0 | Configure > Enforce: Family Link, with a YouTube group and its budget. Same reason: only one may pause and resume. |
| runs at 00:05 with a list of days off and half days, turns School time off, ends it early, adds an extra hour | Configure > School days (the dates as Days off and Half days) and Configure > Schedule |
| switches School time back on after a day off, every minute, inside each kid's window, with a 10:00 watchdog | Schedule (it puts School time back by itself) |
| a one-shot "no School time on Wednesday from noon" | `hearth.school_time_off` {people, date, from: "12:00"} |
| syncs a website list into Family Link every morning | Configure > Website block list |
| adds bonus minutes when a chore is checked off | a reward on the kid's to-do list item (Kids tab > Chores) |
| offers an adult "give 30 more?" when a kid's time runs out | Kids tab > Suggest to phones (or Configure > Suggest more time to phones) |
| resets bonus helpers at midnight | nothing: Bonus today starts at 0 each day |
| ends a family pause at a set time | `hearth.pause` with `until` |
| lets a kid use one app for homework | `hearth.allow` {people, app, until} |

For example, a day off for one kid from noon, and Messages for the rest of the afternoon:

```yaml
- action: hearth.school_time_off
  data:
    people: person.sam
    date: "2026-12-02"
    from: "12:00"
    reason: Early pickup
- action: hearth.allow
  data:
    people: person.alex
    app: com.google.android.apps.messaging
    until: school_time_end
    reason: Bus is late
```

And a dashboard button "why can't Sam open YouTube?":

```yaml
- action: hearth.explain
  data:
    person: person.sam
    group: youtube
  response_variable: why
```

The order matters for anything that pauses Family Link apps: turn the old automation off first (while nothing is
paused, in the evening say), then set Hearth's option. Never let a template build a Family Link child id: Home
Assistant reads the 21 digits as a number and loses some. Hearth passes it as text.

## Testing

- `pytest-homeassistant-custom-component`, in `ha_tests`: config flow, pairing (happy path, wrong nonce, too often,
  expiry), entities by kind, a removed device refused, oversized or malformed posts, rate limits, restart persistence,
  a device going quiet. Later: sources and counting-once rules, budgets and events, approvals, the mailbox's quota.
- Running them: Home Assistant's test tools need Linux. On Windows, a container: `docker run --rm -v <repo>:/src:ro
  python:3.14-slim`, then `pip install pytest-homeassistant-custom-component`, copy `custom_components`, `ha_tests`
  and `blueprints` out of `/src`, and run `python -m pytest` in `ha_tests`.
- One status fixture shared with Hearth's own tests, so the two sides can't drift (not yet).
- Manual: a real Home Assistant, a real TV, a phone, approval end to end.

## Releasing

`manifest.json` `version` is the release version, CalVer `YYYY.MM.NN` (`2026.12.01`), raised by hand with a
`## <version>` section in `CHANGELOG.md`. CI checks it with `python3 .github/scripts/integration_version.py`, and the
release workflow refuses a tag that isn't the manifest's version. Hearth TV has its own version in theSiegs/HearthTV.
A device reports its version
at pairing; the integration is to raise a repair issue when the two are too far apart (not built yet). HACS reads the release tag.

The integration's icon (`brand/icon.png`, 256x256, and `brand/icon@2x.png`, 512x512) is Hearth's launcher icon,
made by Hearth TV's `tool/generate_icons.py` (in theSiegs/HearthTV); Home Assistant 2026.3 and later shows a custom integration's own `brand/` images.

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
   `hearth.set_budget`, and the state document in each status answer (groups, locks, pause, requests, YouTube blocks,
   parent PINs; no titles yet).
2. **Done:** Hearth TV side: **Pair with Home Assistant** (Settings > Home Assistant), posting status to the
   integration (and no longer to the webhook) with each app's category, and each answer's minutes left as HearthTube's
   allowance (the fewest left in a group holding HearthTube).
3. People: the person mapping; per-person Screen time today and Playing from Hearth's own devices; play sessions.
4. Sources: Family Link, Family Safety, Nintendo, Xbox, Switch presence; counting once; titles; Playing together.
5. Groups, budgets, bonus, minutes left, `hearth_budget_reached`; the state document back to the TVs (replacing
   `sensor.hearth_allowance`).
6. Rules.
7. Ask for more and `hearth.pause` (done); `hearth.notify`; blueprints for the other services.
8. Approvals through the integration.
9. Hearth Mobile: pairing with a person, the webhook away from home, its state document.
10. The household mailbox.
11. The dashboard endpoint (only if worth it).

## Open questions

- **Family Link's per-device numbers:** a test phone (an emulator) once showed 1.2 minutes in Home Assistant against 2
  hours on the device. Check on a real phone before trusting them in budgets; the per-child total may be the safer
  source until then.
- **Enforcing per title on another service:** Family Safety pauses single Xbox and Windows apps listed in a group
  (their Family Safety ids); Nintendo still holds the whole Switch.
- **Together on a Switch:** friend presence (unofficial API; login goes through a third-party token server; breaks
  a few times a year) or the parental controls fallback (no third party, delay unmeasured). To test first: can the
  kids' supervised Switch users accept the watcher, how fast presence changes, whether two kids in Minecraft show the
  same game name, and whether Switch Minecraft also shows in the Xbox integration's now playing sensor.
- **Dashboard panel without a person's token:** can the integration serve a chosen user's dashboard config, or does the
  panel keep a non-admin user's token?
- **Video category:** Android's video category misses some apps (a TV's live channels, browsers); the built-in Video
  group has a starter list, to extend as needed.
- **Second household on one Home Assistant:** not planned.
- **Devices on another network segment:** Zeroconf won't cross it; keep the address-typed path.
