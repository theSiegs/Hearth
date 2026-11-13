# Hearth's page and the parental control dashboards

The Family Link and Microsoft Family Safety integrations each ship an example Lovelace dashboard, and the Nintendo
Switch Parental Controls integration ships entities and actions without one. This page compares what they show and do
with Hearth's own page in Home Assistant's sidebar (`custom_components/hearth/frontend/hearth-panel.js`), and says what
Hearth took from them, what it left out and why.

Hearth is the one place a parent manages a kid's screen time across the TV (Hearth's own), phones and tablets (Family
Link), Windows and the Xbox (Family Safety) and the Switch (Nintendo). The integrations' dashboards each show one
service's view of one child; Hearth's page counts every device together and holds the others through their
integrations. So a feature is worth taking when it helps a parent act on a kid across devices, and not when it edits
a service's own rules behind Hearth's back.

## What each dashboard has

### Family Link (`examples/lovelace-dashboard.yaml`, `examples/weekly-limits-card.yaml`)

One masonry view per child, built from Marketplace cards (button-card, Mushroom, Bubble Card, card-mod, stack-in-card,
ApexCharts, Map Card and others), each entity id replaced by hand:

| Card | Shows / does |
|------|--------------|
| Screen time | Today's total, installed apps, blocked apps; toggles for Daily limit, Bedtime and School time |
| Per device (phone, tablet) | Used / daily limit bar, battery, lock switch; +15, +30, +60 bonus buttons and Reset bonus |
| Weekly limits | Mon to Sun: each day's quota and bedtime window, today highlighted; tap to change the quota, hold or double tap for bedtime |
| Location | The child's place name and a map, with a refresh button (GPS opt-in) |
| Incoming requests | A pending request with Approve and Deny; the README says Family Link doesn't expose requests, these came from another integration |
| Screen time per hour | A bar chart from a helper the integration doesn't create |
| Apps and usage | Installed, blocked, limited and device counts; the top 7 apps today with minutes |

The README adds a statistics graph for an app's minutes by hour, the app usage event, a blueprint that blocks an app
after some minutes a day, strict mode, Chrome site lists and the web filter, who may call and text, and ringing a
device.

### Microsoft Family Safety (`examples/dashboard.yaml`, `examples/family-safety-card.yaml`)

One decluttering template per child (button-card, vertical-stack-in-card, card-mod, Mushroom, decluttering-card):

| Part | Shows / does |
|------|--------------|
| Header | Child name, a connection pill (connected, degraded, disconnected) that opens the integration to sign in again, used / allowance; tapping the header toggles the account lock |
| Allowed window | Today's allowed hours |
| Tiles | Total time, blocked apps (blocked / all), pending requests |
| Requests | When there's one: the request, Approve (1 h) and Deny |
| Controls | Account lock, Windows lock, screen time limits on or off |
| Today's apps | The apps used today with minutes |
| Websites this week | Edge's most visited sites |
| Weekly limits | Mon to Sun: each day's allowance and allowed window, today highlighted |

The README adds Xbox and Windows allowed now, time remaining and downtime, platform locks, per-app blocks and limits,
web filtering and site lists, ask to buy, events for new and settled requests, and app usage sensors.

### Nintendo Switch Parental Controls (core, and the patched copy)

No dashboard. Per Switch: played today, screen time remaining, extended (extra) time, max screen time today, the
restriction mode (daily or each day of the week), Suspend software, bedtime alarm and end; per player: played today;
the patched copy adds playing now (console and player), Last synced, and a Cancel extra playing time button. Actions:
`add_bonus_time` (core 5 to 30 minutes; the patched copy 5 to 360 or -1 for unlimited today, with a response),
`cancel_bonus_time` (patched), `update_daily_restrictions`, `update_pin_code`, the usage reports, and on the patched
copy's allow-list branch `list_applications` and `set_app_allowed` (administrators only).

## What Hearth's page already had

- **Today:** each kid's time left on a ring (All screen time across every device), each group's bar, what's playing,
  locks, place, next bedtime or School time, +15/+30/+1 h and -15 for the whole pool; requests for more time from any
  source (Hearth's own, Home Assistant's app, Family Safety) with Not now and +15 to +60; a family pause; devices
  waiting to pair; each TV and phone and what's on it. Google's and Microsoft's own limits per device or platform,
  what Hearth last did through each parental control, grants a parent made in a first-party app (with an end button)
  and requests answered elsewhere.
- **Kids:** daily limits per group for school days and other days, screen time sources, bedtime and School time locks,
  which parental controls hold the kid when time runs out (Family Link, Family Safety platforms and groups, a Switch
  and a shared Switch's player), extra time for one group, and HearthTube's watch log with video, channel and word
  blocks.
- **Devices, Apps, Family:** pairing, TV profiles, push to phones, app groups and where new apps go, who's who,
  parent PINs, school days, places, Glint tile sharing.

## What Hearth took, and why

| From | Taken | How it's done in Hearth |
|------|-------|-------------------------|
| Both: per-child lock (account lock, device switch) | **Pause one kid** from their card, and end it | `hearth.pause` with `people`: their TVs, phones (Family Link), Xbox and Windows (Family Safety) and Switch are held together, not one service at a time |
| Family Link: per-device bonus buttons | **+15 on one device**, under Today by device and app | `hearth.add_bonus` with `device`: extra time there only, the shared pool keeps counting |
| Both: today's apps with minutes | **Today by device and app** on the kid's card: minutes per device and the 8 apps used most | The summary's `devices_today` and `apps_today`, every device counted once |
| Family Link: School time toggle | **No School time today** and putting it back | `hearth.school_time_off` and `school_time_off_cancel`: today only, never the weekly setting |
| Family Safety: connection pill | **Parental controls status** on Devices, and a notice on Today when one isn't loaded or Family Safety's connection isn't connected | `parental_controls` in `hearth/config`: each installed integration's entries and Family Safety's Connection sensor |
| Both: app pauses shown with the child | **App and group pauses** as chips with an end button | `hearth.pause_end` with the app or group |
| Nintendo (no dashboard) | **A Switch card per kid** (Kids tab) and a Switch line on their Today card | See below |

### The Switch

For each Switch of a kid's (the one their Nintendo enforcer holds, or one a screen time source of theirs is on):

- today's play, and on a shared Switch their own player's; the Switch's own limit, time left on it, extra time
  today; playing now, Suspend software, bedtime alarm, last synced; whether Hearth holds it or its own limit stops it
  (that also becomes a line in the adult's app, as Google's and Microsoft's own limits are);
- **Hearth's extra time on this Switch** (+15, +30, +60), which lets Hearth's hold go there;
- **Nintendo's own extra playing time**, past the Switch's own limit: the amounts the installed integration takes
  (15 and 30 with core; 15 to 120 and "Rest of today" with the patched copy), and **Cancel extra** with the patched
  copy. Not while Hearth holds the Switch: Hearth's hold sets its limit to 0, and Nintendo's extra on top would read as
  a parent's change in the Nintendo app, so the page offers Hearth's extra time instead;
- **Games and the allow list** with the patched copy's `list_applications`, and a tick per game with
  `set_app_allowed` (confirmed first: an allowed game starts past the age rating restriction).

What the integration can do is found at runtime (`capabilities.nintendo` in `hearth/config`): each action is offered
only when its service is there, and the extra-time amounts by probing `add_bonus_time`'s own schema, so the page
follows core or the patched copy without a setting, and shows no Switch card without the Nintendo integration.

## What Hearth left out, and why

| Left out | Why |
|----------|-----|
| Weekly limits strips (Family Link quotas and bedtimes, Family Safety allowances and windows) | Hearth's limits are per group for school days and other days, across every device; Hearth holds the services' own limits when its pool is out. Editing each service's weekly rules from Hearth's page would be a second set of rules that fights the first |
| Daily limit and Bedtime toggles, Family Safety's screen time limits switch | The service's own rules: Hearth reads bedtime and School time as locks (Kids tab) and holds devices itself. "No School time today" is the today-only exception a parent needs |
| Approve and Deny buttons per service | Hearth's page already answers every request, Family Safety's included, with the minutes chosen; Family Link exposes no requests |
| Location map and refresh | Hearth keeps no coordinates by design and shows a place's name only (Places) |
| Statistics graphs of one service's sensors | Today's hour-by-hour chart and the last 7 days are on each kid's card now, from Hearth's own Screen time today sensor and the summary's `week`; a graph of one service's sensor can still be added from the README to any dashboard |
| Installed, blocked and limited app counts | Counts of one service's lists; Hearth's Apps tab shows every app and its group across devices |
| Websites visited, web filter, site lists | Not screen time; Hearth's website block list and `hearth.copy_sites` cover the block lists |
| Battery, ring the device, who may call and text, ask to buy | One service's device features, not screen time; they stay on the integration's own entities |
| Strict mode, Switch PIN, `update_daily_restrictions` | Each makes the service's own settings authoritative, which is Hearth's job; changing them from the page would undo Hearth's holds |
| Family Link "Reset bonus" | Hearth's own extra time and grants already end through `hearth.allow_end` and the grant chips; a separate reset would cancel a parent's bonus Hearth didn't give |

## To check on a real install

- Today: a kid's card shows Pause (with a length), and End once paused; "No School time today" on a school day, its
  chip with × after; Today by device and app opens with a +15 per device; a Switch line under Google's and Microsoft's.
- Kids: the Switch card's numbers against the Nintendo app; Hearth's +15 on the Switch while games are out of time
  lets the Switch go; Nintendo's +15 while not held reaches the console (Last synced moves, with the patched copy);
  with core installed only +15 and +30 show.
- Devices: the parental controls card; stop an integration (or sign Family Safety out) and Today shows the notice
  after a reload of the page.
