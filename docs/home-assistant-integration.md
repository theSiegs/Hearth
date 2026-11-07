# Hearth integration for Home Assistant (design draft)

> **Design draft, partly built.** In `custom_components/hearth`: household setup, pairing, a device per Hearth TV or
> phone with its status entities, people, screen time sources (totals and live), titles, counting once, playing
> together, groups, budgets, bonuses, minutes left and the state document (see [Build order](#build-order) and
> [The device's side of the API](#the-devices-side-of-the-api)). Hearth TV pairs and reports to it; Hearth
> Mobile doesn't yet. The rest is
> written so another person or agent can pick it up: what Hearth does with Home Assistant today, what the integration
> should be, and what is still undecided. Read [home-assistant.md](home-assistant.md) first (what exists) and
> [household-sync.md](household-sync.md) (the mailbox's first user).

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
   address it has (typed; finding it by Zeroconf, `_home-assistant._tcp`, isn't built), asks to pair and shows a 6-digit code.
3. Home Assistant shows a discovered **Hearth** device with that name. An administrator checks the codes match and
   confirms. For a `mobile` device the confirm step also asks **whose device** it is (a person).
4. The device gets its own secret, once. That is the only thing of Home Assistant's it keeps. Pairing again gives a
   new secret and ends the old one; deleting the device in Home Assistant ends it at once.

The legacy **Set up from your phone** page stays for the webhook-and-token path.

## Data in

### Device status

Each device posts its status: when something changes (within about 2 seconds) and as a heartbeat (a paired TV every 2
minutes, a phone as its battery allows). The body is the JSON a TV already posts to its webhook
([home-assistant.md](home-assistant.md#tv-status)), so there is no second contract; a phone posts the fields that fit
it (`screen`, `app`, `app_package`, `media_*`, `day`, `seconds_today`, `app_seconds_today`, `playing_seconds_today`).
The integration keeps only known fields, cleaned, and keeps the last status across restarts. **Connected** turns off
after 15 minutes without a post; the device's other entities show unavailable then.

### A kids profile's YouTube

What a kids profile started in HearthTube comes up, and what a parent blocks here goes down to it (the design is
HearthTube's `docs/parent-channel.md`). Home Assistant is the second place for it: Hearth keeps the log and its own
lists without it (Settings > Family > Kids profiles > the kid).

- **Up**: after each status post, a TV posts the started videos Home Assistant hasn't had to
  `/api/hearth/device/<id>/events` (see [The device's side of the API](#the-devices-side-of-the-api)), only from the
  last day. They're kept per person (a kid on two TVs is one log, the newest 2,000), and each new one fires
  `hearth_video_started` (person, time, video_id, title, channel, channel_id, url, device).
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
| Xbox, Windows | [Microsoft Family Safety](https://github.com/noiwid/HAFamilySafety) (HACS) | `sensor.<child>_screen_time` (minutes today, the whole account) and `sensor.<device>_screen_time` per device | polled, 5 minutes by default (30 s to an hour) |
| Nintendo Switch | [Nintendo Switch parental controls](https://www.home-assistant.io/integrations/nintendo_parental_controls) (built in) | Used screen time and Screen time remaining per Switch (minutes; added as a source, its time is games unless chosen otherwise). Whole-console: on a shared Switch, use each player's playing-time sensor as the source instead. Per-app minutes (its usage report service) aren't read yet | polled every 60 s; the Switch must be online; its values aren't marked unavailable when an update fails |
| Nintendo Switch, live | Switch friend presence: HACS [Nintendo-Switch-Presence](https://github.com/itsfatlum/Nintendo-Switch-Presence), fed by a self-hosted [nxapi](https://github.com/samuelthomas2774/nxapi) presence server and a watcher account | what each kid's Switch is playing now | 30-60 s |
| Xbox, live | Home Assistant's Xbox integration | now playing per gamer | about a minute |

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

## Limits

### Groups

A budget is set on a **group**: a set of apps and titles whose minutes count together. Built in:

- **All screen time**: everything not excluded by a rule.
- **Video**: video apps (Android's video category, plus any an adult adds).
- **Games**: as above.
- **Social** and **Messaging**: social and messaging apps (a starter list, Android's category, plus any an adult adds).
  Messaging is Not screen time (below) unless an adult puts it in.

An adult can add groups: **YouTube** (YouTube and HearthTube, on every device) is the household's pool today. A
minute counts toward every group its app or title is in, so a YouTube minute is taken from YouTube, Video and All
screen time. A device's time is up when **any** group it's playing from is used up.

**Not screen time** (Configure > Not screen time): a group whose minutes don't count toward All screen time, music
say. Its minutes still count in the group itself (and its own budget, if it has one, still applies), but not in All
screen time, and its apps stay usable when All screen time runs out: Family Link's lock spares them only if a parent
gave them unlimited time there, and Hearth TV is told them (the All group's `except` list). The person's Screen
time today sensor lists each group's packages (`groups_apps`) and these groups (`not_screen_time`).

### Budgets

Per person and group, number entities an adult (or an automation) sets:

- a daily **budget** (one for school days and one for other days, as Configure > School days says; -1 is no limit);
- **Bonus today** (minutes, back to 0 at midnight).

From them, per person and group: **Minutes left** (budget + bonus - counted today, never below 0) and the event
`hearth_budget_reached` (person, group, group_name) when it reaches 0, and again if a bonus reopened it. A **shared
budget** could also span people (one pool the siblings draw from), with its own Minutes left (not built yet).

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
- **Offer more** (Configure > Offer more time): when one of a kid's chosen groups runs out, the adults get the same
  actionable notification the other way round ("Sam's YouTube is used up. Give Sam 30 more minutes today?"). Nothing
  is asked of the kid and their devices aren't told about it; "Not now" starts no cooldown.
- **Chores** (Configure > Chores earn time): per person, a to-do list, a group and what a chore is worth (15 minutes
  by default, or the chore's own "+N": "Dishes +30"). Each item checked off adds its minutes once and is removed from
  the list; `hearth_chore_done` (person, chore, group, minutes) and the adults' phone are told.
- **Automations, a dashboard button**: call `hearth.add_bonus`.

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
    the weekday's setting. An app with unlimited time is never paused for a group either. Calls, texts, the system and
    the parental controls' own apps are never paused for a group.

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
    account id as `account_id`), and the lock runs `until` the next local midnight. An older Family Safety that takes
    neither gets the account sensor's `user_id` and `duration_hours`, as before. An unlock answered with
    `hold_expired`, `left_parent_override` (a parent's own lock stays) or `not_locked` is fine: nothing of Hearth's is
    left. **Xbox and Windows apps in a group:** a group may list Family Safety's app ids (`x:...` Xbox, `appx:...` or
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

    Nintendo's limits are the whole console's: there's no limit per child. On a **shared Switch**, choose the person's
    "playing" sensor (an entity that's on while they're the one playing: the rebuilt Nintendo integration's per-player
    playing sensor, or friend presence) and the Switch is held only while it's on, so a brother or sister with time left
    can play. Nintendo reports play about every 10 minutes, so with its sensor the hold can start and end that late;
    friend presence is about a minute. Two kids held on one Switch share the hold: it's put back only when neither is.
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
- Bedtime, School time itself and a family pause still lock the person. An allow lifts Hearth's holds, not those
  locks: a TV can't open one app through a lock without a change on the TV, and Family Link's own bedtime still locks
  the phone. To lift School time, take it off (`hearth.school_time_off`).
- `hearth.explain` (`person`; `app` or `group`), response only: `{allowed, until, blocked_by: [{kind, by, until}],
  lifted, exceptions, school_time_off}`. `kind` is `budget` (by the group, until midnight), `bedtime`, `school_time`
  or `other` (by the lock entity, until it says), `pause` (until, reason) or `school_time_apps` (by the Family Link
  entity, until School time ends) or `google_tv_limit` (by the TV's device id, with its `device` name, until null; see
  below). `place` is kept for place rules (none are built yet: a place only ends an exception so far). `until` is when it's allowed again (the latest of the blocks, null when one doesn't
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
  `grants` (below) and `school_time_off` (what's taken off and when it's put back).

### Keeping the parents' apps in step

A parent's change in a first-party app (Family Link, the Nintendo app, Microsoft Family Safety) is an adult's decision:
Hearth adopts it and never writes over it or fights it. And Hearth's own "all screen time" opens Google's and
Microsoft's own limits too. Everything below is gated on what the installed integrations offer (a service there, an
attribute present), so an older Family Link or Family Safety keeps working as before.

- **Compare and restore.** Letting go of a Family Link device lock puts the weekday's daily limit back only while that
  limit still reads 0 (what Hearth set); a Switch's Max screentime and Suspend software, only while the limit still
  reads 0. A limit a parent changed meanwhile stays (`kept_current`). Family Link's `resume_app` compares in Family
  Link itself; its answer (`results`: `restored`, `kept_current`, ...) is read and shown.
- **Parent grants.** A parent's change that lets a kid use what Hearth holds becomes a grant `{id, person, via
  (family_link, nintendo, family_safety), source ("from the Family Link app"), target {kind: device, app, switch or
  platform; value}, until, since, reason, endable, end_with}`. It lifts only the hold it came from (the child's Family
  Link device lock, the paused app, the Switch, a Family Safety platform), not a whole group everywhere as an allow
  does, and budgets keep counting. Grants are kept across restarts and end on their own; when one ends, enforcing goes
  on as usual. They show in `hearth.explain`'s `exceptions` (`type: "grant"`), the person's `exceptions` attribute,
  the household summary and Hearth's page. Seen while Hearth holds something:
  - Family Link: today's weekday limit raised (adopted: nothing is put back over it), until midnight; bonus time on a
    device (its `bonus_minutes` beyond what Hearth itself added), until the bonus is used up (the Active bonus sensor's
    `remaining_minutes` reaches 0 or it clears) or midnight; a device unlocked (`lock_override_code` 4), until midnight;
    an app a parent changed after Hearth paused it (the Apps with time limits sensor's `paused_apps`, `pause_intact`
    false), until midnight.
  - Nintendo: the Switch's Max screentime today raised, or bonus time (`time_extended`), until midnight (adopted).
  - Family Safety (its Allowed Now sensors' and lock switches' `hold`, `override`, `allow_until`): `hold: parent` with
    extra time (`allowUntil`) is a grant until `allow_until`; with no override left (a parent cancelled Hearth's lock),
    until midnight. A parent's own lock (`blockUntil`) is no grant but a **parent lock** (below).
  - A change right after Hearth's own call (a minute), or a limit that still shows what it was before Hearth's 0
    arrived, is Hearth's own and not a grant. Hearth's own bonuses are remembered, so they never count as a parent's.
  - Event `hearth_parent_grant` (the grant) when one starts.
- **Ending a grant early.** `hearth.allow_end` with the grant's `id`. Hearth's page and the summary offer it only when
  it maps to a write in the parent's app (`endable`): a Family Link bonus (`familylink.reset_bonus`, else the device's
  Reset bonus button: `end_with: family_link_reset_bonus`), Family Safety extra time (`cancel_time_bonus`, then the
  platform is locked again: `family_safety_cancel_bonus`), or a Switch or platform a parent unlocked or raised (locked
  again by Hearth's hold: `relock`). A raised Family Link limit, an unlock or an app change is shown read-only there;
  the service still ends it, and Hearth holds again with the parent's value as the one to put back.
- **Hearth's "all screen time" in the parents' apps.** `hearth.allow` for group `all`, and extra time that gives All
  screen time back (it had none left), also give:
  - Family Link: a today-only bonus (`familylink.add_time_bonus`) on each of the child's devices whose own daily limit
    would block within that time (Screen time remaining lower than the minutes needed; a device with no limit gets
    none), as much as is missing; once per allow.
  - Family Safety: extra time (its experimental `add_time_bonus`, `until` the allow's end or midnight) on the
    enforcer's platforms whose allowance would block (allowance minus used lower than the minutes needed). It replaces
    Hearth's own lock there (`released_hold`). When Microsoft doesn't apply it, the person's status says Family Safety
    extra time is unavailable; nothing fails.
  - Ending the allow early (`hearth.allow_end`) resets the Family Link bonus Hearth added (only where no parent's bonus
    came on top: `reset_bonus` ends every bonus of the day; without `reset_bonus` or the button it lapses at
    midnight) and cancels the Family Safety extra time (`cancel_time_bonus`).
- **First-party limits in explain.** `hearth.explain` also lists `device_limit` (a Family Link device's own daily limit
  reached with no bonus left, by its switch, with its `device` name, until midnight; or a Family Safety platform that
  Microsoft's allowance or allowed hours stop, with its `platform`) when Hearth isn't the one holding it, and
  `parent_lock` (a parent's own Family Safety lock, with its `platform`, until it ends), so explain says what the
  device does.
- **Requests answered in the Family Safety app.** `microsoft_family_safety_request_resolved` with `via: app` closes the
  matching ask as answered there (`answered_in: family_safety`; shown as "answered in the Family Safety app"); `via:
  service` (Hearth's own answer) is left alone. Family Link has no kid requests, so there's nothing to close there.

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
- `hearth.school_time_off` (`people`; `date`, today by default; `from`, a time; `reason`) does the same for anyone,
  any day; `hearth.school_time_off_cancel` (`people`, `date`) drops one not started, or puts one already off back from
  today.

**Putting School time back.** Switching School time on outside a kid's window opens a window from then until 23:59,
so Hearth switches it on only on a school day (or half day), inside the kid's own weekly window for today (read from
Family Link's time entities, and kept when it was turned off in case they read unknown meanwhile; N hours shorter on a
half day), and at once pins today's window to those hours (`set_school_time`, scope `today`). Each minute it checks
the devices' `schooltime_end` and pins again until they say the pinned end; then it's done. A kid whose window has
ended is left for the next school day. Switched on or pinned, it waits two minutes before doing either again (Family
Link is read once a minute).

**Checks.** At 06:00 a School time that should be off and isn't is turned off again, and the adults are told what
didn't apply (the extra time, too). At the watchdog time (10:00 by default) on a school day, they're told about anyone
whose School time is still off, unless it was taken off for today. "Told" is a notification in Home Assistant and the
schedule's phone (else the one that answers requests for more time). Each step fires `hearth_schedule` (action:
`school_time_off`, `school_time_back`, `half_day`, `bonus`, `site_list`, `site_list_failed`; person; details; for
the website list `via`: `family_link` or `family_safety`). Each action runs once a day; what's pending is kept across
restarts.

**Website block list** (Configure > Website block list): an https address, a time (07:30 by default) and the people
(everyone with Family Link or Family Safety by default). Every day at that time, Hearth calls `familylink.sync_site_list`
(entity: the person's Family Link entity, url) and `microsoft_family_safety.sync_site_list` (the person's Family Safety
entity or account id, url; skipped quietly while Family Safety has no such service) for each, one after another; each
side is on its own: a failure for one is logged, fires `site_list_failed` (with `via`) and is tried again 5 minutes
later, and the other side and the other people go on. Those services add the list's new domains and remove only what
the list itself added before. For example `https://example.com/blocklist.txt`.

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

## Data out

### What a device gets

The answer to each status post carries the person's (or, on a TV, each profile's) **state document**:

```json
{
  "profiles": {
    "user:10": {
      "person": "person.sam",
      "groups": [{"id": "youtube", "name": "YouTube", "minutes_left": 25, "apps": ["com.thesiegs.hearthtube"]}],
      "locked": true,
      "pause": {"until": "2026-10-26T19:00:00-05:00", "reason": "Dinner"},
      "lock": {"by": ["pause"], "kind": "pause", "kinds": ["pause"], "until": "2026-10-26T19:00:00-05:00"},
      "tile_exchange_share": false,
      "request": {"id": "…", "status": "approved", "minutes": 15, "asked_minutes": 15, "group": "all"},
      "youtube_blocks": {"videos": [], "channels": [], "words": [], "labels": {}}
    }
  },
  "youtube_blocks": {"user:10": {"videos": [], "channels": [], "words": [], "labels": {}}},
  "people": {"user:10": "person.sam", "user:0:alex": "person.alex"},
  "parent_pins_version": "…",
  "version": "3f9c1a0b2d4e5f60",
  "contract": 1
}
```

`groups` lists only groups with a budget; `minutes_left` null is no limit; All screen time may carry `except`, the apps
it never holds (a Not screen time group's). Each person's part is described under [Ask for more](#ask-for-more) and
[Pause and locks](#pause-and-locks); an allow of theirs that ends on a place is in `allow_ends` [{id, app, group,
until, text: "ends when you get home"}] (never where they are); a TV's also has every mapped profile's `youtube_blocks`, `people` (each mapped
profile of that TV by its own key, with its person: a notification's `for` may name a person, and the TV finds their
profile here) and the [parent PINs](#the-devices-side-of-the-api). Own-limit titles (`open_titles`) aren't built. A TV gets it in the answer to each post (at least every 2 minutes while it's
on); `version`, a hash of the content, lets it skip an unchanged one. This replaces `sensor.hearth_allowance`:
same meaning, from the integration instead of a template.

A **phone** gets its person's part of the same document, in the answer to each post and pushed when it changes (see
[Away from home](#away-from-home)). Each person's part also says `tile_exchange_share`: whether a parent let their
phone share with its launcher's tile exchange (Configure > Tile exchange sharing; false unless chosen).

**Pop-ups** (not built yet): `hearth.notify` (target: devices, a person's devices, or the household; `title`, `message`, `duration`,
`position`, `image`, `camera`, up to three `actions`). On a TV it's Hearth TV's pop-up; on a phone, a notification.
Actions call a Home Assistant service as a user the household chose, not with any device's secret.

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

Not built yet. [household-sync.md](household-sync.md): `POST .../household/outbox` and `GET .../household/inbox?since=<version>`,
sealed blobs the integration can't read (it never has the household key), kept with Home Assistant's storage helper so
they survive restarts, 2 MB per household, oldest dropped first. Pictures don't go through it. Devices still exchange
directly on the home network; the mailbox is for devices that are rarely on at the same time.

### Contract

`contract` (an integer, now 2) says which shape of the device API and the household summary this is: in the approved
pair answer, every status answer (`{"ok": true, "contract": 1, "state": {...}}`), every state document and the
summary. A device may send its own in its status (`contract`). It goes up only when a field changes meaning or type,
becomes required, or goes away; an added field doesn't change it, so a reader ignores fields it doesn't know. It's
apart from `version`, which changes with the content. A phone's person document also says `kind` (`kid`, `adult` or
`person`) and `kind_set` (whether an adult set it on Hearth's page). Only an adult (on Hearth's page) has a parent PIN.
The summary is for administrators and for adults on Hearth's page whose person is their Home Assistant user (without
pairing codes); `hearth.add_bonus` and `hearth.set_budget` take a group's name as well as its id. Contract 2 added the
summary's `headline`, `lines` and `actions` (per person) and `household` ([below](#contract-2-headline-lines-actions)):
added fields, so nothing of contract 1 changed, but the number went up so an app knows they're there.

### Ask for more

A device asks: `POST /api/hearth/device/<device_id>/ask` (header `X-Hearth-Secret`) with `{"minutes": 15 | 30 | 45 |
60, "group": "all" or a group id, "note": up to 120 characters, "profile_id": a TV's profile}` (a phone asks for its own
person; a TV for the profile's, the one in front when none is given). 200 `{"ok": true, "request": {id, status:
"pending", minutes, asked_minutes, group, expires}}`; 409 `already_open` with that request (one open per person); 429
`cooldown` with `retry_in` (10 minutes after "not now"); 404 `no_person`; 429 `too_often` past 10 asks and event posts a minute; 400 otherwise. A request is open 30 minutes.

The adults are told: `hearth_more_time_requested` (`id`, `person`, `person_name`, `minutes`, `group`, `note`,
`device_id`, `asked`, `expires`), a notification in Home Assistant, and an actionable one on the adults' phones (the
asked amount, the next one up, Not now: `HEARTH_MORE|<id>|<minutes>`, 0 for not now; see [The adults'
phones](#the-adults-phones)). The first answer wins, once: from a phone, Hearth's page, or `{"type": "hearth/approvals/answer", "request_id", "minutes" (1-600) |
"deny": true}` on the WebSocket, or the service `hearth.answer_request` (`request_id`; `minutes` 1-600 or `deny:
true`; returns the request as the device sees it; a second answer, or one to an expired request, is refused with a
validation error) (administrators, and adults on Hearth's page). More time is extra time today (as `add_bonus`); the answer fires
`hearth_more_time_answered` (`id`, `person`, `status`, `minutes`, `by`: the user). The asking device sees it in the
person's state document: `request` {id, status: pending | approved | denied | expired, minutes (granted when
approved), asked_minutes, group, expires, answered (when it was answered or expired, null while pending)}, for two hours after.

#### The adults' phones

Every adult on Hearth's page gets requests for more time, offers (Configure > Offer more time) and chores done on each
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
    "tile_exchange_share": false,
    "request": {"id": "q2X0aZ1b", "status": "pending", "minutes": 30, "asked_minutes": 30, "group": "all",
                "expires": "2026-11-07T18:30:00+00:00", "answered": null},
    "youtube_blocks": {"videos": [], "channels": [], "words": [], "labels": {}}
  },
  "media_rooms": [],
  "version": "3f1c2a9b0d4e5f67",
  "contract": 2
}
```

`pause`, `lock` and `allow_ends` come as in the state document when they apply.

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

`hearth.pause` (`minutes`, or `until` a time or date-time; `reason`; `people`, everyone by default; `ends_on`, see
[Exceptions](#exceptions)) holds the people until it ends or `hearth.pause_end` (`people`, everyone by default). A paused person is locked, so a Hearth TV holds
their apps as for bedtime, and their state document says `pause` {until, reason}. Every person's document also says,
while they're locked, `lock` {by: the lock entities and/or "pause", kind: bedtime | school_time | pause | other
(the first that applies), kinds: all of them, until: when it ends, if known}, and `next_lock`
{at, by, kind: bedtime | school_time} for the next bedtime or school time today, from the lock entities' own
`bedtime_start`/`bedtime_end`/`schooltime_start`/`schooltime_end` (Family Link's; Family Safety's Downtime Active
sensors carry `bedtime_start`/`bedtime_end` too and are a bedtime), so a device can wind down. Without
a push, a device learns of a pause with its next status answer: a TV within 2 minutes (it posts at least that often
while on), a phone at its next post.

### Household summary

For an adult's app on Home Assistant's own WebSocket (administrators, and adults on Hearth's page whose person is their
user, without pairing codes; no device secret, nothing extra for the
entities and services). `{"type": "hearth/household"}` answers once; `{"type": "hearth/household/subscribe"}` answers,
then sends the same object as an event whenever it changes, at most every 2 seconds (unsubscribe as usual). It holds:

- `people`: `id`, `name`, `kind` (as set on Hearth's page, `kind_set` true; else `kid` when they have limits, otherwise
  `person`), `tv_profiles`, `all`
  (the shared pool: All screen time's `used_minutes` and `minutes_left`), `groups` (each with a budget or use today),
  `locked` and `locked_by`, `playing`.
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
  `parent_lock`, `blocking`; only what the integrations' entities give), `sync` (per parental control: `held`,
  `error`, `failed_at`, and `last`, what Hearth last did and whether it took: `{at, ok, held, let_go, outcomes
  {item: restored | kept_current | ...}, bonus_added, extra_time, parent_grant, reason, error}`) and
  `answered_elsewhere` (requests answered in the Family Safety app lately).
- each kid also has `place` {`name`, `fresh`} (where they are, by name only; [Places](#places)): every reader of the
  summary is an administrator or an adult. An allow and a pause that end on a place carry `ends_on` (above).
- `not_screen_time`, `contract`, and `version` (changes with any of it).
- `media_rooms`: the house's media players by room, below.
- Contract 2: each person's `headline`, `lines` and `actions`, and the household's `household` {`headline`,
  `actions`}, below.

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
| notice | a parent's grant | `switch open · the nintendo app till 9:00` | `grant:<id>` |
| notice | Google's or Microsoft's own limit stops a device of theirs (Hearth isn't holding it) | `sam's phone · google's own limit`, `xbox · microsoft's own limit` | `device_limit:<entity or platform>` |
| notice | a parent's own Family Safety lock | `xbox locked in family safety till 7:00` | `parent_lock:<platform>` |
| notice | a parental control Hearth couldn't hold or let go through | `family link · didn't take` | `sync_error:<kind>` |
| calm | a request answered in the Family Safety app | `answered in the Family Safety app` | `answered:<id>` |
| calm | the most-used group with a limit (All screen time only when it's the only one) | `youtube · 25 left` | `left:<group>` |
| calm | nothing else | `all clear` | `clear` |

Times are local, 12-hour, without am/pm. **lines** are the rest of that list in the same order, then each group with a
limit (All screen time first, `left`, `low` or `out` as above), what's playing (`hearthtube · kitchen`, key
`playing:<package>`) and the next lock (`bedtime at 9:00`, key `next:<kind>:<at>`); never the headline again.

**actions** are what an adult can do for the person now, each `{id, label, service, data, confirm?, primary?}`: an app
calls `service` with exactly `data`, with the adult's own Home Assistant sign-in, after asking `confirm` when it's set;
`primary` ones come first. The result shows in the next summary. Only what applies now is offered:

| id | When | service and data |
|---|---|---|
| `ask_yes:<id>` (primary), `ask_no:<id>` | a request waits | `hearth.answer_request` `{request_id, minutes: <asked>}` / `{request_id, deny: true}` |
| `bonus:<group>` | each group with a limit today, fewest minutes first; primary when it's out | `hearth.add_bonus` `{person, minutes: 15, group}` |
| `pause` (confirm) | not paused | `hearth.pause` `{people: [person], minutes: 30}` |
| `pause_end` | paused | `hearth.pause_end` `{people: [person]}` |
| `allow_end:<id>` (confirm) | an allow | `hearth.allow_end` `{people: [person], group}` or `{people: [person], app}` |
| `grant_end:<id>` (confirm) | a parent's grant that maps to a write in their app (`endable`) | `hearth.allow_end` `{id}` |

`household` is the same for the whole house: a `headline` (urgent: requests waiting, `alex asks for 30 more` or `2
asks waiting`; notice: a pause, `everyone paused till 6:30` or `sam paused till 6:30`; notice, administrators only: a
device waiting to pair; notice: kids out of time; calm: `all clear`) and `actions`: each waiting request's yes and no
(labelled with the kid's name), `pause_end` (`hearth.pause_end {}`, ends every pause) while anyone is paused, and
`pause_all` (`hearth.pause {minutes: 30}`, confirm) unless everyone is. Approving a device to pair isn't an action:
it's an administrator's step on Hearth's page, with no service.

A trimmed example: a kid Alex who asked for more, is paused and is low on video, and Sam with nothing to report. The
whole summary, from a test (with a grant of Sam's from the Nintendo app added by hand), is
[examples/household-contract2.json](examples/household-contract2.json).

```json
{
  "contract": 2,
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
          "text": "screen time · 95 left",
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
          "text": "screen time · 105 left",
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
  (not connected) is refused; a phone isn't a TV.
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

Chore claims will join `approvals` when they exist.

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
  makes a new one; a phone paired before this got one when the household next loaded. TVs have none.
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
controls, groups and their apps, school days, Glint tile sharing and the push server for phones. Its **Today** tab
shows each kid's time left and what's playing, with buttons for extra time, and each TV and phone. It is
`custom_components/hearth/frontend/hearth-panel.js`, a plain custom element on the WebSocket commands in `panel.py`
(`hearth/config`, `hearth/config/set`, `hearth/budget`, `hearth/pairing`, `hearth/parent_pin`) and the household
summary; settings are saved to the entry's options as the Configure menu saves them, and budgets as the services set
them.

The Configure menu (Settings > Devices & services > Hearth > Configure) still has everything, as a menu:

**Who's who on the TVs**, **Add / Remove a screen time source**, **Add / Remove a title**, **Locks** (bedtime,
school time), **Enforce limits** (Family Link, Family Safety, Nintendo), **School days**, **Schedule**, **Places**, **Website
block list**, **Chores earn time**, **Offer more time**, **Sort new apps**, **Watch for new apps**, **Add a group**, **Add apps to Video or Games**, **Not screen time**, **Remove a group**, **Tile
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
| Playing | sensor: the title or app now, and where |
| Playing together today | duration |
| Held by parental controls | sensor: what Family Link, Family Safety or Nintendo holds now |
| Locked | binary sensor |
| Place, for each kid | sensor: a place key, away or unknown (see [Places](#places)) |

Per household: **Playing together** and **School day** (binary sensors), **Apps to sort**, **Day type**. Open requests for more
time are in the household summary and on Hearth's page, not an entity.

Events: `hearth_budget_reached` (person, group, group_name), `hearth_more_time_requested` and
`hearth_more_time_answered` (as in [Ask for more](#ask-for-more)), `hearth_playing_together` (title, people, started
or ended), `hearth_enforced`, `hearth_new_app`, `hearth_parent_pin_used`, `hearth_parent_pin_locked_out`,
`hearth_schedule`, `hearth_chore_done`, `hearth_place` (person, from, to).

Per person with a TV profile: **Last video started** (see [A kids profile's YouTube](#a-kids-profiles-youtube)).

Services: `hearth.add_bonus`, `hearth.set_budget`, `hearth.pause`, `hearth.pause_end`, `hearth.allow`,
`hearth.allow_end`, `hearth.explain`, `hearth.school_time_off`, `hearth.school_time_off_cancel` (see
[Exceptions](#exceptions) and [Schedule](#schedule)), `hearth.play_on_tv` (event
`hearth_command_done`, see [Play on a TV](#play-on-a-tv));
`hearth.get_watch_log`, `hearth.watch_digest`, `hearth.block_video`, `hearth.block_channel`, `hearth.block_word` and
their `unblock_` twins. Event `hearth_video_started`.

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
   plenty): `{"status": "pending"}` (or `{"status": "denied"}`), then once `{"status": "approved", "contract",
   "device_id", "secret", "person", "role", "urls": {"internal", "external"}}` (`role`: `kid`, `adult` or null; a URL
   null when unknown). After that, or once the request expires (10 minutes, or 2 minutes after approval), it's 404
   `unknown`. A wrong or missing nonce is 404 too. A phone's approved answer also says `push` (see
   [Away from home](#away-from-home)).
4. The device keeps `secret`, and nothing else of Home Assistant's.

**Status.** `POST /api/hearth/device/<device_id>/status` with header `X-Hearth-Secret: <secret>` and the status JSON
(see [Device status](#device-status)), at most 64 KB. 200 (below); 401 `not_paired` for an unknown device or
wrong secret (it was removed: stop posting and offer to pair again); 429 `too_often` past 20 posts a minute; 400
`bad_request`. A refused secret is a plain 401, never a failed Home Assistant login, so it doesn't count toward Home
Assistant's IP ban. The 200 answer carries the device's state document, `{"ok": true, "contract": 1, "state": {...}}` (see
[What a device gets](#what-a-device-gets)). Every device endpoint answers 503 `not_set_up` while the integration is
loading: try again, don't unpair. A device may also send `app_categories`, `{"<package>": "game" | "video" | ...}`
(Android's category, lower case), which helps sort its apps into Video, Games, Social or Messaging. A TV's
document also carries `commands` (one-shot commands such as a play, see [Play on a TV](#play-on-a-tv)), and the TV
says which it ran in `commands_done`. A phone's answer also says `push` (its ntfy channel, or null; see [Away from
home](#away-from-home)).

**Events** (a TV only). `POST /api/hearth/device/<device_id>/events` with the same header and
`{"events": [...]}`, at most 50, each `{"type": "video_started", "profile_id", "t" (ms), "v" (video id), "title",
"ch" (channel name), "cid" (channel id)}`. `profile_id` is the TV's own key for the profile (`user:10`), resolved
with the TV it came from as in [TV profile keys](#tv-profile-keys). 200 `{"ok": true, "added": n}` once all are taken:
an entry of a profile mapped to no one, or one that isn't valid, is dropped, and a resend is harmless, so the TV marks
them all sent. 403 `not_a_tv` from a phone; 429 `too_often` past 10 posts a minute; 400 for more than 50 or a
malformed body.

**Parent PINs** (any paired device). Each adult on Hearth's page has their own (4 digits), set in Configure > Parent PINs or on Hearth's page, and kept as a salted
hash in the TV's form (`v2$<iterations>$<salt>$<hash>`, PBKDF2-HMAC-SHA256); any of them is a parent PIN.
`POST /api/hearth/device/<device_id>/verify_pin` with the same header and `{"pin": "<4 digits>"}`: 200
`{"ok": true, "person": "person.alex"}` or `{"ok": false}`, and a right one fires `hearth_parent_pin_used`
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

**Entities**, per device, by kind as in [Kinds](#kinds). Screen time today is in seconds (shown in minutes), with
per-app, playing and (on a TV) per-profile attributes kept out of history. All but Connected are unavailable until the
first post and once the device has been quiet for 15 minutes; the last status is kept across restarts. Deleting the
device removes it from the household.

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
- Pairing is the one step that needs an administrator.
- **Who may call Hearth's services.** Every `hearth.*` service checks its caller: a call with no user (an automation,
  or a script an automation started) may; so may an administrator, and a user whose person is an adult on Hearth's
  page (the rule that lets them read the household summary, auth.py). Anyone else (a kid with a Home Assistant user of
  their own) gets Home Assistant's Unauthorized error, for the read-only ones too (`explain`, `get_watch_log`,
  `watch_digest`): a kid doesn't read the watch log. A script a kid starts from a dashboard runs as the kid, so it's
  refused as well.
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
4. After a release or two of both, the webhook path is documented as legacy.

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
| adds bonus minutes when a chore is checked off | Configure > Chores earn time |
| offers an adult "give 30 more?" when a kid's time runs out | Configure > Offer more time |
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

`manifest.json` `version` is the release version, pubspec's name without the build number (`2026.11.08`): set it with
`python3 .github/scripts/integration_version.py --write` after bumping `pubspec.yaml`, and CI and the release workflow
refuse a mismatch. A device reports its version
at pairing; the integration is to raise a repair issue when the two are too far apart (not built yet). HACS reads the release tag.

The integration's icon (`brand/icon.png`, 256x256, and `brand/icon@2x.png`, 512x512) is Hearth's launcher icon,
made by `tool/generate_icons.py`; Home Assistant 2026.3 and later shows a custom integration's own `brand/` images.

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
