# Changelog

> **Draft.** Hearth is in early development and this document is a draft: features, settings and
> setup steps may change or be incomplete.

## Unreleased

### Home Assistant integration

- **A minute counts once it's over.** Daily time used and today's time left both count whole minutes used, so they add up to the day (half a minute in, a kid saw 0 used but a minute gone), and a kid is never held before the last minute is used.
- **A pool that's gone takes its entities with it.** When a pool is removed (the retired built-in Video pool, say), its budgets, bonus, today's time and minutes left go from Home Assistant on the next start instead of staying unavailable for good.
- **Forgetting a phone.** An administrator can forget any phone from Glint (`hearth/glint/forget`), and a phone paired and never seen can be forgotten too; an adult who isn't an administrator still forgets only their own phones and kids'. The device entry is removed the way Home Assistant 2027.8 expects.
- **Reloading Hearth no longer leaves a web session behind** (the app lookups' session is let go of on an unload instead of a close Home Assistant refuses).
- **Sharing app data is retired.** No app on the household's devices shares app data any more, so its setting is gone from Hearth's page and Configure, and the people chosen for it are removed from the settings once. Each person's `share_app_data` in the device document stays, always false, so apps that read it keep sharing off.
- **A restart never lets a kid out of time back in.** Right after Home Assistant starts, the parental controls load one by one and for a few seconds today's count looked short: a kid who was out of time showed an hour or more left and every hold let go and came back. A limit reached today now stays held until the sources have settled (90 seconds after Home Assistant is running), and opens on time after that if an adult gave more meanwhile.
- **Categories count whole minutes too**, as daily time does: a category isn't held half a minute before its limit, and its used and left add up to the limit.
- **"Until 00:00" set in the evening ends at midnight.** Changing today to Sleep until 00:00 put the kid in Sleep for all of the next day.

## 2026.11.26

### Home Assistant integration

- **The adults hear when a device's clock is changed.** When a kid's phone or tablet posts a status for another day than Hearth's (its clock moved), the adults get a notice once ("Sam's Pixel: its date was changed. Hearth keeps counting today's time by its own clock."), besides the failed clock check on the device's row. Today's counts are kept, as in 2026.11.24.

## 2026.11.25

### Home Assistant integration

- **A category off today stays off.** A category whose limit today is 0 is closed: bonus time (an adult's, a chore's, an approved ask) no longer opens it, and its minutes never use the bonus. Its own bonus, a raised limit or Unlimited still opens it, each given on purpose for it. Its entry in `time.categories` says `closed: true`, and the kid's line reads "Games are off today".

## 2026.11.24

### Home Assistant integration

- **Grant services answer their origin.** `hearth.add_time` (general or a category's), `hearth.raise_cap`, `hearth.unlimited`, `hearth.add_bonus` and `hearth.pause` (Pause screens) answer `origin_id` (and `origin_ids` per person), so a client can link to the grant or end it with `hearth.end_grant`. `hearth.pause` now answers at all.
- **The time model contract matches the code**: each origin's `end`, `time.by_category` and `time.uncounted`, `never_paused` with the keyboards, and exactly what `hearth.end_grant` and the device API's `end_grant` answer, including when nothing is left to end.
- **A phone's moved clock no longer wipes a kid's day.** Hearth judges the day by its own clock: a status for another day (the phone's clock moved forward or back) keeps the counts Hearth had and fails the device's new `hearth_clock` check, and within Hearth's day a device's counts never go down. Every status answer says Hearth's `day` (and `clock_off` when the device's differs).
- **Pause everyone pauses the kids.** `hearth.pause` without `people` (Hearth's page, a phone's "pause everyone", an assistant) holds every kid and never an adult; an adult named is left out, and the answer says who was paused (`paused`, `not_paused`). The household headline's "everyone paused" counts the kids.
- **An ended grant stays ended.** `hearth.end_grant` on an origin already ended is refused for good: it no longer becomes endable again, or takes minutes from newer bonus time. Each origin says `ended_at` and `ended_by` once it's over (ended, run out, or a pause replaced), and a status line's origin (`time.unlimited.origin`, `bonus_origin`, a raised category's) points at one still in effect, so after one of two Unlimited grants ends the other can be ended through it.
- **The clock app is never paused**: Google's, AOSP's, Samsung's, OnePlus's, OPPO's and LG's clock apps join the never-paused list, so a kid can always set an alarm.
- **"Sleep until 7:00" in the evening works.** `hearth.change_today` with a mode `until` a time earlier than now runs it past midnight until then tomorrow morning, where it failed with "It has to end after it starts".
- **Pairing a phone without an administrator beside you.** Each administrator's companion app gets "Alex's Glint (Pixel 9) wants to pair as an adult", with the code and Approve / Deny that work from the notification (`hearth.pairing_answer`, administrators only); the bell links to Hearth's page instead of Devices & services. A phone may say who it's for (`person_name`, `role`), and the pair answer lists who is asked (`approvers`). An adult in Hearth who isn't an administrator confirms their own phone with its code (`hearth/pairing` with `code`); a kid, or a user who isn't an adult in Hearth, can't.

## 2026.11.23

### Home Assistant integration

- **The Family Link backstop leaves a switched-off daily limit alone.** With a child's daily limit switched off in Family Link, Family Link stores a written limit as that weekday's own limit, every week, instead of today's override. Hearth now writes nothing for that child (and checks again right before each write).

## 2026.11.22

### Home Assistant integration

- **Block apps through Hearth.** `hearth.block_app` and `hearth.unblock_app` (Android package names; every kid with Family Link by default, or the kids you name) block an app through Family Link and keep the block: an app not installed yet is blocked when it shows up, and one installed again is blocked again. A block a parent takes back in the Family Link app is kept unblocked (shown on Hearth's page) until an adult blocks it again in Hearth. A block Family Link doesn't take is tried three times, then the card says so. Hearth only ever unblocks what it blocked, so a parent's own block in the Family Link app stays. An app Family Link lists as blocked is never paused or resumed by Hearth's budgets, pauses, School time or schedule, `hearth.allow` doesn't lift it, and `hearth.explain` names it (`blocked_by` kind `blocked_app`). Adults only, like Hearth's other services.
- **Block browsers Hearth doesn't support** (option `block_unsupported_browsers`, off by default). Hearth filters sites in Chrome on Android (Family Link's site filters) and in Microsoft Edge on Windows and Xbox (Family Safety's web filter). With the rule on, every other browser Hearth finds on a kid's Android devices (Samsung Internet, Firefox, Opera, Brave, DuckDuckGo, Vivaldi, Tor, Edge for Android and more, or an app Hearth's categories know as a browser) is blocked as soon as Family Link lists it, and so are app stores that skip Family Link's approval (the Galaxy Store and others). Edge on Android isn't supported: Family Safety filters it only while the kid is signed in to Edge, which nothing on Android enforces. A browser supported later, or everything when the rule goes off, is unblocked where Hearth blocked it.
- **Apps > Blocked by Hearth** on Hearth's page: the rule, where Hearth filters sites, each kid's blocks with Unblock, and Windows and Xbox shown as covered by Family Safety's web filtering (a warning when a kid's web filtering is off). Every Android app's row has Block.
- **One daily time, categories with limits, and bonus time.** Each kid has one **daily time** ("All screen time" is renamed); categories (Games, YouTube...) have an optional **limit** inside it ("Games: 2 h limit"), which never adds time. Before, "+30 games" raised Games only, and daily time could still run out first. Now there are three ways to give more:
  - **Bonus time** (`hearth.add_time`, `hearth.remove_time`): no category, spent anywhere; minutes past any category's limit come out of the same bonus. Chores, approved asks (from the TV, a phone, Glint or Hearth's page), the day-off bonus and adults all give bonus time, and every grant also reaches Family Link and Family Safety where they would stop the kid sooner.
  - **Raise limit** (`hearth.raise_cap`, `hearth.raise_cap_end`): one category, by or to some minutes or no limit, until a time; daily time is unchanged.
  - **Unlimited** (`hearth.unlimited`, `hearth.unlimited_end`): until a time or until turned off (always over at midnight). The minutes used meanwhile aren't counted, so daily time, limits and bonus pick up where they were ("Limits back on · 1 h 10 min left today"). Bedtime, School time and Pause screens still apply unless bedtime is included.
- **Messages is no longer exempt.** Google Messages and Samsung Messages are paused like any app (daily time or a limit used up, bedtime, Pause screens) and can be blocked with `hearth.block_app` (blocking, unlike pausing, makes Messages miss incoming texts; the page asks first). The Messaging category counts toward daily time. The dialer, contacts, Settings, Play services, Family Link and the Play Store stay open, so emergency calls always work. On the first start, `messaging` leaves the household's Not screen time list once: Hearth can't tell an adult's own choice from the old default, so put it back there if you meant it.
- **Activity: what Hearth did.** Every call Hearth makes to Family Link, Family Safety, Nintendo and other integrations, every hold it starts and ends, TV commands and Glint inbox writes are kept 14 days, by entity ids only, with their result and timing. Read them with `hearth.get_activity`, the `hearth/activity` command or the page's Activity view (failures stand out). Debug logging (the entry's Enable debug logging) explains each decision, and Download diagnostics gives the settings, each kid's state and the last 200 records, redacted.
- **A category's bonus.** `hearth.add_time` takes a `category`: "+15 min Messaging bonus" is usable only in Messaging, past daily time and Messaging's limit, and is spent before the general bonus. Kids see "Messaging: 15 min bonus left"; the page's category rows have Bonus 15 min next to Raise limit; the assistants' "15 more minutes of messaging" gives it. Family Link's backstop counts it, and while it lasts Family Link pauses the other apps instead of locking the phone. A raised limit reads "Games limit today: 3 h (raised)".
- **For Glint and other clients:** each origin has an `id`, `endable` and `end` (the service that ends it or takes back its unused part), and status lines link to it (`bonus_origin`, `origin`); the state document lists `never_paused`; an adult's phone can end one with `POST /api/hearth/device/<id>/end_grant`. Extra time on one device is unchanged.
- **Grants.** Every bonus, raised limit and Unlimited is its own grant: `hearth.end_grant` ends exactly one (a bonus's unused part, one raise, one Unlimited extension), and the others stay in effect. A "to" raise is now a floor (the highest wins). The state document's `time.by_category` splits today's counted minutes by category, each once.
- **Asks are for bonus time.** A kid asks for minutes, with no category; an approval is bonus time whatever an older device asked for.
- **Family Link backstop** (Configure > Enforce, on by default): each kid's Family Link daily limit today is kept at the most Family Link counted on one of their devices + Hearth's daily time left + 30 minutes (the margin is an option), so it never sits below real use; a whole day while Unlimited. Written only when it rises or drops by more than 30 minutes, never to a TV. Hearth's whole-device hold now puts back the weekday's own limit, never today's override. It wins over a weekday limit changed in the Family Link app; turn it off to keep Family Link's own limits.
- **Where it came from.** Bonus time, raised limits, Unlimited and Pause screens record who and what gave them ("Bonus +30 · added by Alex in Hearth · 3:05 PM"), in the state document, `hearth.explain` and Hearth's page.
- **`hearth.explain`** says an app's category and groups (no more `group: null` for an app), daily time and bonus left, raised limits and Unlimited.
- **New words everywhere.** "Daily time", "Games limit on school days", "Bonus time today", "Bonus time left" (a new sensor), "Raise limit", "Unlimited", and "Pause screens" for the family pause. Entity ids don't change. The assistants' tools are `hearth_add_time`, `hearth_raise_limit`, `hearth_unlimited` and `hearth_unlimited_end`.
- **Kept for one release:** `hearth.add_bonus` without a group is bonus time; with a category's group it raises that category's limit (`hearth.remove_bonus` likewise), and a category's "limit raised today" number is the older per-category bonus. On the first start, today's per-category bonuses become raised limits, once. Glint's contract: [docs/contracts/time-model.md](docs/contracts/time-model.md).

### Hearth TV

- **Ask for bonus time.** The time-up card asks for bonus time (no category). When a category's limit is reached and daily time is left, it says so: "Games are done for today · 40 min left for other things". The family pause reads "Screens paused".

## 2026.11.21

### Home Assistant integration

- **Hearth knows app categories itself; the shared App Facts catalog is retired.** What an app is (a game, YouTube, streaming, a companion app, System screens...) now comes from, first found: your own answer on Hearth's page, a starter list shipped with Hearth (the catalog's last confirmed answers and hand overrides on every platform, the System screens set, parental-control apps, big games: 400 apps), the app's genre in its store, then Home Assistant's default AI Task (or one you choose, or none). Hearth fetches no catalog, verifies no signatures and sends no proposals or corrections anywhere.
- **Store lookups.** When a kid first uses an app Hearth doesn't know, it looks the genre up once: Google Play's app page, the Microsoft Store's catalog (Windows and Xbox) or Steam. Only the public store id is sent, with no cookies; at most 100 a day, kept with the date and looked at again after 90 days. Only sure genres count as known (games, Social, Music, News, Maps, Photography, Productivity, Tools...); Communication, Entertainment, Education and the like are unclear. Turn lookups off on Hearth's page (Apps > App categories) or in Configure > App categories.
- **An AI for unclear apps.** By default Hearth asks Home Assistant's default AI Task (Settings > AI Task; a local Ollama works) about apps whose store genre is unclear, at most 20 a day, with structured output. What it sends goes to the model behind that AI Task: the app's name, store id and the store's one-line description only. Its answer is a guess, kept: it never puts an app in Messaging, Accessibility or System screens, and shows in Check these. Choose a specific AI Task entity or Off in Apps > App categories or Configure > App categories; both show which entity the guesses use. With no default AI Task in Home Assistant nothing is asked, and the starter list, store genres and your answers work as before.
- **Say what an app is.** Apps > Every app shows each app's kind and where it came from (set by you, Hearth's list, its store's genre, AI guess, not known yet), filters to AI guesses and apps not known, and lets you set what an app is next to its group. Saying what an app is takes back an earlier move of it, so its group follows; "Hearth decides" takes your answer back. The App categories card counts the apps by where their answer came from.
- **Moved over once.** On the first start the catalog's settings (`catalog_fetch`, `catalog_share`, `catalog_share_asked`, `catalog_url`, `catalog_relay`) and its kept copy are removed. Corrections you had queued to share become your answers; a catalog fetch you had turned off turns store lookups off. Your group map (`catalog_pools`) stays. The `hearth/catalog/correct` command is gone; `hearth/apps/category` sets an app's answer.

## 2026.11.20

### Hearth TV

- **On-screen and voice first, never a phone by default.** When the TV's keyboard is Google TV's phone keyboard (it can stay stuck after a phone goes away), Hearth TV's text boxes show Hearth TV's own on-screen keyboard with a mic key instead of telling you to type on a phone. Search has a mic button next to the box. **Type on your phone** is offered only while a phone has Hearth TV's remote open. A section's custom name now waits for OK before the keyboard comes up, like Hearth TV's other settings fields.
- **On-screen keyboard first** in Set up Hearth TV: one adb grant (Hearth TV runs it itself when the TV's debugging is on) lets Hearth TV put the TV's own on-screen keyboard back when a Hearth TV text box needs it and no phone is there.

## 2026.11.19

### Home Assistant integration

- **App Facts files are read whole.** A large catalog file that arrived in pieces could be cut short and then fail its SHA-256 check, so Hearth kept an old copy. It now reads each file to the end.
- **A TV knows each adult's phones.** A TV's state document now has `adult_phones`: for each of its profiles mapped to an adult on Hearth's page, the notify services of that person's companion apps (the same phones that get requests). Hearth TV's phone approval asks them when no phone was chosen on the TV.
- **Phone approval through the integration.** A paired TV asks the integration (`POST /api/hearth/device/<id>/switch_approval`, then reads or withdraws the request), which sends the adult's phones Allow and Deny, hears the first answer, takes the notification off every phone and tells the TV. Only the paired TV may ask, only for a profile mapped to an adult, and each request's id is random and used once. Anyone with the companion app may answer; the log and the new `hearth_switch_approval` event say who.
- **Works on the released Microsoft Family Safety (2.3.0).** Hearth no longer needs a Family Safety with today-only allowed hours or `hold` attributes; it uses them where the installed one has them:
  - Extra time that runs past today's allowed hours on Windows or the Xbox changes this weekday's hours where Family Safety can't change today's only, and Hearth puts them back itself after midnight (kept across a restart and a missed midnight), only while they still read Hearth's: a parent's change stays. On Windows they're never moved while Family Safety keeps a saved schedule (its account lock or limits off), which would keep Hearth's hours for good.
  - A parent's own lock, unlock or extra time in the Family Safety app is told from Hearth's by what Hearth asked for (when its lock and its extra time end) against what Family Safety shows in force. One gap: a parent's Windows lock while Hearth holds Windows reads as Hearth's.
- **Family Safety extra time whose write failed but was applied anyway** is no longer lost: Hearth watches for it for 10 minutes (across a restart), adopts it as its own extra time when Family Safety shows it (so it's never taken for a parent's, and ending the allow cancels it), and logs a warning with the platform, times and error to hand the Family Safety maintainer. Nothing shown: dropped. Hearth never cancels extra time it can't see.
- **Xbox and PC requests on the released Family Safety.** Without its request events, Hearth reads each kid's Pending Requests sensor: a new request becomes an ask as before, and one answered in the Family Safety app closes at the next Family Safety update that no longer lists it, or at once as approved when extra time shows on that platform as it leaves. A restart announces nothing again, an unavailable sensor resolves nothing, and with a Family Safety that also fires the events each request is handled once.
- **Locks end at midnight on the released Family Safety.** Its `lock_platform` takes whole hours only, so Hearth unlocks its own lock itself at midnight (caught up after a restart that missed it), only while the lock is still Hearth's: a parent's change since stays. A Family Safety whose lock takes an end keeps using it. On 2.3.0 an unlock cancels any lock in force; from the release with its #94 it puts back what the lock replaced.
- **Website block list on the released Family Safety.** It has no `sync_site_list`, so Hearth keeps the list itself: downloaded once a day (https only, size cap), each kid's sites read with `get_sites`, missing ones blocked with `block_website`, and only sites Hearth added that the list dropped unblocked with `remove_website`. What Hearth added is kept across restarts (a fork's own record is taken over once); sites it didn't add are never touched; sites that fail are reported one by one. A Family Safety with `sync_site_list` still does it alone.
- **Hearth's page says what's reduced.** Under Parental controls, Microsoft Family Safety lists what Hearth does with less on the installed version ("Works with less on this version"), and `hearth/config` has `capabilities.family_safety` (today_only, hold_attributes, lock_until, Windows extra time, website lists, ...).
- **App facts from its own address.** The shared app catalog is now read from `https://thesiegs.github.io/app-facts/` (the dataset's repository was renamed from glint-recipes). A `catalog_url` still set to the old default reads as the new one; any other URL is kept.
- **App facts retries a failed check.** A fetch that fails a check (a 404 or other error answer, a shard whose SHA-256 isn't the index's, an index listing no shards) is tried again after 10-15 minutes, then 20-30, then 40-60, at most three times a day, instead of waiting for the next daily time. The copy in use stays meanwhile; offline is still left to the next daily time; unloading the integration cancels a pending retry.

### Hearth TV

- **Phone approval no longer stops itself.** The OK that picked a profile on the chooser (its repeat, or a laggy remote's second press) withdrew the phone's request as soon as Google TV's PIN screen came up, so the phone never showed it. Now a digit withdraws it at once, but an arrow, OK, Back or Delete only once the PIN screen has been up for two seconds, and never a press that began before it came up.
- **Phone approval on every TV.** An adult's phone approval switch and chosen phone follow them to the household's other TVs, like their saved PINs (the Google TV PIN already did); the newest change wins, and the entries are signed like the Parent PIN's. A kids profile's are never shared.
- **No phone to pick with the Hearth integration.** When no phone was chosen, a TV paired with the integration asks the phones Home Assistant has for the profile's person ("Alex Phone (from Home Assistant)"); a phone chosen on any TV wins, and **My phones in Home Assistant** goes back to them. The Parent PIN's phone approval asks the same phones.
- **Phone approval without a token.** A TV paired with the Hearth integration has the integration ask the phone and reads the answer from it, so it no longer needs a Home Assistant token of its own for this. It falls back to its own token with an older or unreachable integration. Choosing from Home Assistant's full list of phones and the test notification still need the token; the Parent PIN's phone approval still uses it too.

## 2026.11.18

### Home Assistant integration

- **System screens never count.** Launchers, settings and other system screens (an `interface` answer in App Facts, or the built-in list) stay out of every pool, and a device's time from before it was paired is ignored.
- **Extra time at bedtime lifts bedtime while it lasts.** When an adult gives a kid extra time during bedtime, Hearth lifts bedtime for that long (Family Link's bedtime too, before midnight) and puts it back after; an adult's own change in the meantime is kept.
- **A today-only mode with an end keeps it** when the kid has no weekly schedule: Free time takes over at the end.
- **Glint agents.** A new `glint` LLM API lets Home Assistant's assistant and the MCP server read and change a paired Glint phone (Start, look, notification rules, undo, activity, Do Not Disturb, system settings) through a per-phone mailbox. Adults reach only their own phones and kids' phones; kid phones refuse voice writes and anything that loosens a limit; off on each phone until its owner turns it on (docs/home-assistant-integration.md, "Glint agents").
- **Media players ending in `_music` or `_music_display`** are recognized as twins of the TV they belong to.

### Hearth TV

- **Phones can control the TV without Home Assistant.** A phone app such as Glint pairs with a code the TV shows, then sees what's playing (title, art, position) and controls play/pause, seeking, volume and opening apps over the home network (docs/tv-remote-api.md). New phones follow kid rules: they can't open an app the profile on the TV can't open now. Settings > Family > Phones that control this TV lists them, says whose each is (a kid's phone, an adult's phone, or not this one) and removes one.
- **Remote API version 2, first part.** A phone app that says version 2 is told its role (none, a kid's or an adult's) and whether Home Assistant decides; it sees the minutes left for the app in front (a kid's phone only for its own kid), a kid's rules, minutes and lock, each kid's minutes on an adult's phone, and can ask for more time for its kid when Home Assistant decides (the answer comes back on the phone). A kid's phone can't open what the kid's own rules hold. Version 1 phones work as before. Not yet: phones bound once for every TV, a kid's phone use counting on the TV, asks and pauses without Home Assistant, and one-tap Home Assistant for an adult's phone (docs/tv-remote-api.md, "As built").

## 2026.11.17

### Home Assistant integration

- **A "+" box for more choices.** A suggestion on Today keeps its suggested amount and Dismiss; its second amount is now a square "+" that opens a small menu: +15 min, +30 min, +1 h and Unlock for today (an allow of that pool, or of that device for a device's own limit, until midnight). Each applies at once with the 6-second Undo; Unlock's Undo ends that allow. When the kid is already over, a line under the menu says by how much ("10 min over: +15 leaves 5"). The kid's sheet has the same box beside Give time, for the pool that stops them. Suggestions add `over` (minutes past the limit) to the household summary (added field: the contract stays at 2). Phones' suggestions are unchanged.
- **Any app can pair with Hearth (contract 3).** A device now says which app it is (`client`: its package, version and up to four companion packages of its own family), and the adult approving the pairing sees it there; it's locked with the pairing. That app and its companions are never paused for the device's person, unless the household or App facts put them in a pool. A device that later reports another app gets no exemption and a failed check ("App differs from pairing") until it pairs again. Phones paired before this update keep working; pairing them again lets their app manage its own settings in Hearth. The phone launcher stays on the built-in never-paused list until its phones have paired again.
- **Device checks.** A device may report up to ten health checks of its own (`checks`); Hearth shows them on the device's row on Hearth's page and fires `hearth_device_check_failed` when one turns false.
- **Settings an app keeps in Hearth.** Paired apps can keep small documents in Hearth, for the household, for one person or for one device (at most 64 KB each, 16 per scope, 1 MB per app), which Hearth stores and passes on without reading them: over the device API, on the WebSocket for adults (`hearth/client_settings/*`), with `hearth_client_settings_changed` on each change. A kid's device writes only its own device's documents; its person's need a parent PIN typed on it (a short grant from `verify_pin`: two minutes, eight writes), and household documents need an adult. Hearth's page shows what's kept for each app, with Remove. See docs/contracts/client-settings.md.
- **"Sharing app data"** replaces "Glint tile sharing": the same people are on (the setting moved, as it was, when Hearth starts), its card says what it does without naming an app, and each person's state document says `share_app_data` instead of `tile_exchange_share`.
- **App facts.** The shared app catalog's card is now "App facts", in plain words. A published index that leaves out the catalog (or lists no shards) no longer empties Hearth's copy: the copy stays. A device's `catalog_categories` is no longer read, since Hearth fetches the catalog itself.
- **New docs:** docs/contracts/device-api.md, client-settings.md and app-facts.md.

### Hearth TV

- **Hearth TV says which app it is when it pairs** (contract 3), so Home Assistant shows it in the pairing dialog and on the device row.

## 2026.11.16

### Home Assistant integration

- **A weekly schedule per kid, like a thermostat's.** A new Schedule tab (between Kids and Devices) gives each kid a week and two special days, the Day off and the Half day. A day is a list of changes ("at 7:45, School"), each running until the next, drawn as a 24-hour bar; the night carries over to the next morning, so bedtime is the Sleep that ends the day and wake is the next day's first change. Drag a handle to move a change (it snaps to 15 minutes; arrow keys move it too), pick its mode, add or remove changes, set the time each day per group, copy a day to other days or a kid's week to another kid, and Undo. "Today only" changes today and ends at midnight; Back to the schedule ends it sooner.
- **Modes are the family's.** Sleep, School and Free time are built in; Homework (Games, YouTube, Streaming and Social closed) and Wind down (Games and Social closed) are starters you can change or remove, and you can add your own (up to 8). Editing one changes it in every kid's schedule.
- **Limits per day.** The time each day replaces the two budgets (school days, other days). Nothing changes for a household that hasn't set up a schedule: until you edit a kid's, it's their school-day budget on Monday to Friday and their other-day budget on the weekend and the Day off, with no times, and bedtime and School time still come from Family Link. Summer weekdays use the Day off. The old budgets and their numbers keep working: they write Monday to Friday, or the weekend and the Day off.
- **Hearth holds the schedule itself.** Sleep and School lock Hearth's TVs and phones (`lock.by: ["schedule"]`) and hold the Xbox and the Switch; a mode that closes groups holds them as a paused group on Hearth's devices ("Games (Homework until 5 PM)", no ask for more), pauses their apps in Family Link, and locks the Xbox or holds the Switch when it closes their groups. An allow of the group lifts it. `next_lock` and Today's bedtime come from the schedule when it says sooner. Nothing is written to Family Link's, Family Safety's or Nintendo's own schedules yet.
- **New:** `sensor.hearth_<kid>_mode` and `sensor.hearth_<kid>_bedtime`; the events `hearth_mode` and `hearth_schedule_changed`; the services `hearth.set_schedule`, `hearth.copy_schedule`, `hearth.change_today`, `hearth.resume_schedule` and `hearth.get_schedule`; `schedule` per person in the household summary and the state document (added fields: the contract stays at 2).
- **Accessibility apps are never paused.** A new built-in group, Accessibility (Voice Access, Lookout, Live Transcribe, Sound Amplifier, TalkBack and any app the shared catalog confirms as accessibility, or an adult moves there), is Not screen time by default, and nothing of Hearth's pauses its apps: not All screen time running out, a pause of the app or a group, School time's apps, nor the schedule. It has no budget or bonus to set. The state document lists them in All screen time's `except` and in a new `never_held`, for a device that can spare them from a lock too.
- **Only a confirmed answer loosens a limit.** Messaging and Accessibility (outside All screen time by default) take an app only on an adult's move or list, Hearth's starter lists, or the shared catalog's confirmed answer. A device's own category (any app can declare one) or the catalog's suggestion no longer puts an app there: it counts in Other, and Check these asks about a suggested one. Apps already in Messaging through Hearth's starter list or an adult's list or move stay there.
- **A newer copy of the shared catalog ships with Hearth** (the bundled snapshot of 2026-11-14), so a new install no longer starts from one that called Chrome and Sound Amplifier messaging.

- **A suggestion's +amount opens time again.** When a group is already 10 minutes or more past its limit (counted time catching up, or extra time that didn't cover it), the suggestion offers enough to catch up plus the usual amount (25 and 40 for a kid 10 over), says how far over it is, and after an adult's give reads "still up" with the extra time shown. "Not today" on Today reads "Dismiss" (it hides the suggestion until tomorrow).

### Hearth TV

- **Updates wait while a kids profile is in use.** Hearth TV's automatic updates, its own and HearthTube's, no longer install while a Google TV kids profile's user is running, even in the background: a package change then can make Google TV take apps out of that profile and sign the kid out. They install once no kids profile runs (Hearth TV's own still only with the screen off), or anyway after waiting a week. HearthTube's check comes back every hour while it waits, and only the owner's Hearth TV installs. An update an adult installs from Settings → System → Updates doesn't wait. The log says `HearthUpdate: deferring …` while one waits.

## 2026.11.15

### Home Assistant integration

- **Today on Hearth's page, redesigned.** It answers "does anything need me?" in one sentence: For you shows at most one row per kid (a request first), each a plain sentence ("Sam's YouTube time is up") with +15 min, 30 min and Not today under it, or says "Nothing needs you tonight" with a fold of what's held back and why. Then one row per kid with a ring around the initial (Hearth's warm accent; indigo with a moon in bedtime, blue in School time) and one status line, no +15 during a lock or after their cutoff; Screens now (one row when nothing plays); and one muted line for the adults. A tap on a kid opens their sheet (a bottom sheet on a phone, a column beside the list on a wide screen): their lock and why time won't help, the actions that help now, today split by pool with lanes that open to their apps, devices grouped by what they're doing, exceptions in plain sentences, and only the days Hearth recorded. Every action applies at once with a 6-second Undo instead of a confirm. Family today, by pool moved to the Family tab.
- **Suggestions wait when they wouldn't help.** None while a kid is in bedtime, School time or a pause, none after their bedtime starts (or after 9:00 pm without one), and a device's own limit (Microsoft's, Google's, Nintendo's) only while that device is in use. At most one shows per kid. The adults' phones follow the same rules. The household summary adds `suggestions_held` (each with `held` and `why`), `sentence` and `detail` per suggestion, and `counts.suggestions_held` and `counts.needs`.
- **Devices by the names you gave them.** Each device in the summary's `targets` has a `display_name`: the name given to its device in Home Assistant, else the name of the source counting it, so a Family Link tablet reads "Sam's tablet", not "SM-X230".
- **Take back extra time.** `hearth.remove_bonus` takes back up to the minutes given today (never their own budget), logs it, and takes back what Family Link and Family Safety got for it. The page's Undo uses it.
- **No more "ran out" at midnight from yesterday's numbers.** A screen time sensor that hasn't updated since midnight (Family Link's, before its first poll of the day) no longer counts as today's, so a kid no longer runs out of a pool for a moment at midnight and the week no longer marks it out.
- **A kid's own to-do count on their phone.** The state document a kid's device reads carries `todo` {left, done, total} for their to-do list, so a phone can show "2 left" without reading the list.
- **Other tabs:** apps, sources and lock sensors show names first with their ids in a tooltip, test builds are hidden from Apps, Home Assistant users with nothing in Hearth fold under "Others in Home Assistant", and "Suggest to phones" reads "Send suggestions to adults' phones".

## 2026.11.14

### Home Assistant integration

- **The shared app catalog.** Hearth fetches Glint's signed catalog of app facts itself, once a day at a random time (ETag, Ed25519 with the two pinned keys, no rollbacks, SHA-256 per shard), keeps the last good copy for good and works offline, starting from a snapshot it ships with. It knows what an app is on phones, TVs, Xbox, Windows and Switch, and places a new app by an adult's move, the household's lists, Hearth's starter lists, the catalog's confirmed answer, the device's own category, the catalog's guess (only into a pool), then where its time came from. Companion apps (the Xbox app, a store) are never Games. Settings > Shared app catalog maps each kind of app to a group. An adult's move to Other now stays Other, even for a Switch or Xbox title.
- **Check these.** Hearth's Apps tab lists apps placed only on the catalog's guess, and apps where the catalog and the device disagree on whether it's a game. Right keeps one where it is; moving it works as before. Either way a later catalog change never moves it; Every app says "the shared catalog now says X" instead.
- **Sharing with the shared catalog, asked once.** Asked once on Hearth's page (HA administrators only): once a week, the store ids of public Windows apps the catalog lacks and the corrections an adult ticks, never who uses them, no usage or times, never messaging apps.
- **One pool per app; the built-in Video pool is retired.** An app now counts in one pool at most besides All screen time (where an adult moved it, else the pool whose list an adult put it in, else a starter list, else its Android category), so a YouTube minute is no longer also a Video minute. An app put in one pool's list leaves the others. On its first start Hearth moves an older household once and logs it: a household that budgeted Video (or moved an app to it) keeps "Video" as a pool of its own by the same id, so budgets, entities and history carry on; otherwise Video goes. Configure > Add apps to Games replaces Add apps to Video or Games.
- **Time use on Hearth's page.** Today shows a compact row per kid (a button only for a waiting request or a suggestion); a tap opens the kid's card, where the big ring is gone: All screen time is one bar split by pool plus "other", with the limit and today's extra time, a thin lane per pool on the same scale, the day from wake to bedtime with School time and the minutes used each hour, and a tile per device with the time actually left there and whose limit that is.
- **The household summary adds** each person's `all_by_pool` (All screen time's minutes by pool plus other, adding up), `bedtime` {start, end} from their lock entities, and per device in `targets` the time left there: `left`, `left_by` (hearth, google, microsoft or nintendo), `left_pool`, `locked` and `locked_kind`, worked out once for the page, the TV and Glint. Nothing is renamed or removed.
- **Each kid has a to-do list, with optional rewards.** `todo.hearth_<kid>` ("Sam's to-do") works with the to-do card, Assist and automations. Adults set it up in the Kids tab of Hearth's page: tasks once or repeating (every day, some weekdays, every N days, N days after last done), a time due, and a reward of minutes in a group or money. A reward is granted when the kid or an adult checks the item off, with no approval step; the adults' phones are told, with Undo. A sibling can't touch another kid's list, and a shared tablet or voice checks items off without a reward. Untick takes the reward back, and it's never given twice. Chore minutes count with Bonus today (`bonus_chores` in the summary), All screen time's also in Family Link and Family Safety, with an optional daily cap per group; money is a balance per kid. Configure > Chores earn time is gone: its lists' open items move in once.

## 2026.11.13

### Hearth TV

- **A kid's screen time without Home Assistant.** Hearth TV has its own rules for each kid, set in Settings > Family > Kids profiles > the kid > Screen time: minutes a day for All screen time, Games and YouTube (weekdays and weekends) and a bedtime. Holds, the time's up card, HearthTube's minutes and the bedtime heads-up work as they do with Home Assistant, and an app already open is closed when time runs out or bedtime starts. The rules and each kid's minutes are shared by every TV of the household. With Home Assistant paired, its rules win outright and the Screen time tile says so; an older YouTube limit becomes the kid's YouTube group and is replaced once the rules are saved.
- **Pairing one TV pairs the household.** Once one TV is paired with the Hearth integration, it pairs every other TV of the household on the network that isn't (with a single-use ticket, no code to type), and can pair an adult's phone the same way. A TV unpaired on purpose isn't paired again. A TV's own screen-time rules from before it was paired become a kid's first budgets in Home Assistant.
- **Pauses and answers in seconds.** A paired TV holds a long-poll to the Hearth integration while its screen is on, so a family pause, a lock or an answered request arrives within seconds instead of at the next two-minute status. With an older integration the TV keeps its two-minute status.
- **Other computers stay off the TV's debugging.** Hearth answers Android's "Allow debugging?" with Cancel for any computer but Hearth's own, so a kid can't let a computer on the home Wi-Fi in. Settings > Family > Allow a computer to connect takes the Parent PIN and leaves the prompt to the parent for two minutes.
- **One Parent PIN lockout for every pad.** Wrong Parent PINs count in one place for Hearth's pads, HearthTube's and a kid's through its agent: five free tries, then 30 seconds doubling up to an hour, kept across a restart of Hearth or the TV. Typing a new PIN a second time to confirm it no longer counts as a wrong one.
- **No more webhook status or `sensor.hearth_allowance`.** A TV reports to the Hearth integration only: the webhook automation, "create it in Home Assistant for me", the TV status page and the phone setup's webhook id are gone, and the setup's TV status step pairs the TV with the integration instead. A TV that isn't paired uses its own rules.
- **Continue Watching: an adult's titles can stay on their TV.** A switch in Settings > Continue Watching lets an adult keep what they watch off the household's other TVs.
- **Continue Watching: a kid's cards stay with their profile.** A kids profile's own rows (HearthTube's, say) no longer show to an adult who just switched in, and still show while Hearth can't tell who's on.
- **Hearth's notices on the TV.** Notices from the Hearth integration show in the Bell of adults' profiles like a Home Assistant notification (never in a kids profile), the same on every TV of the household; "info" waits in the Bell, the others pop up once. A notice's button asks for the Parent PIN (or an adult's phone, with phone approval on) and Home Assistant does the rest; the button never runs anything on the TV itself.
- **Where playback is.** The TV's status says how far into what's playing it is (`media_position_s`, as of `media_position_at`), from any app's playback, HearthTube's too, so Home Assistant can show the position without the TV reporting more often.
- **The dashboard panel is for adults only.** In a kids profile the Home Assistant panel (Hearth's own and the full dashboard) never opens: Right at the edge doesn't offer it, anything else that asks for it gets "Ask an adult", its row is gone from the profile's Home Assistant settings, and a panel left open closes when a kids profile comes on. A kids profile's setting can't turn it back on.
- **Home Assistant: a parent's app grants read as apps, together and calm.** In the household summary's lines (contract 2), an app a parent opened in the Family Link app is named ("youtube kids", from Hearth's app catalog, the kid's Family Link sensors or their apps today, else a guess from the package), never shown as its package. Grants from the same parent's app ending at the same time are one line: two or three by name ("youtube kids and roblox open · the family link app till midnight"), more as a count ("16 apps open · ..."), with a key that holds while the set does. These standing app limits are calm and listed last, never the headline; a parent's bonus, unlock, Switch or platform let go, and an adult's allow, are still news. Times at 12:00 say "midnight" and "noon". App grants in the summary carry the app's `name`.
- **No "Hi, Home" card after a profile PIN.** After a kid's profile was left for an adult's with Google TV's PIN, Hearth could take focus on the "Home" tab of Google TV's home for a profile pick and show "Hi, Home" for half a minute, with the remote doing nothing. Only the chooser's profile tiles count as picks now, and a pick that isn't a profile is dropped as soon as Google TV's home names who's on.
- **Continue Watching: no percentages.** The cards keep their progress bar; the "Playback percentage" badge and its switch are gone. The Kids profiles page's Fix no longer mentions Family Link notices.
- **A paused app says it's paused.** When an adult pauses one app or group in Home Assistant, Hearth TV's time's up card (also opened by HearthTube's "Ask for more time") says "YouTube is paused: Homework" and until when, with no asking for more, which wouldn't end it. Other groups out of time can still be asked for.

### Home Assistant integration

- **Hearth's page reads more plainly.** A kid's lock chip says what it is and when it ends ("School time till 3:00", "Bedtime till 7:00"), with the School time and bedtime entities only in its tooltip. Apps a parent opened in their own app are one chip, by name ("Pandora and Spotify open · Family Link till midnight", or "9 apps open · ..."), never package ids. Google's, Microsoft's and Nintendo's own limits and what Hearth last did fold under **Device limits**, apps by name and why ("holding Google Messages for School time"); its summary says when something didn't take or stops them.
- **Pausing only touches apps a kid has.** A group's budget, a pause or School time asks Family Link to pause only the apps installed on the kid's devices (from their Family Link app lists), not every app of the group. An app the kid doesn't have no longer shows up as opened by a parent in the Family Link app afterwards.
- **Old sync errors go away.** A parental control's "didn't take" clears once it has nothing to hold, as well as after the next call through it that works, and the household summary no longer makes news of one over a day old.
- **Only adults change budgets and bonus time.** Hearth's Budget and Bonus today number entities now refuse a change from a Home Assistant user who isn't an administrator or an adult on Hearth's page (a kid with their own user); automations still may.
- **Holds and releases show within seconds.** The Held by parental controls sensor and Hearth's page change as soon as a hold or release goes through, and Family Link, Family Safety or Nintendo is asked for fresh data once, about 10 seconds after each write Hearth makes there, instead of waiting for its next poll.
- **Assistants won't allow a restricted Switch game.** `hearth_allow` (MCP and voice) refuses a game on a kid's Switch that isn't on its allow list in the Nintendo app, where the Nintendo integration can list the Switch's games.

- **Hearth's page: Today as the dashboard spec draws it.** A **Suggested now** strip at the top holds the household's headline, requests waiting (+15 to +1 h) and suggestions with their buttons ("Sam · games ran out · give 15?" +15, +30, Not today), and keeps its height so the cards below don't jump. Each kid card shows the summary's today line (`2 h 10 of 3 h · games · 10 left`) and is colored by the kid's state; its give button goes to the pool that stops them first ("+15 games"), with All screen time and more under More; groups without a budget today are muted; what's on reads `bluey · s2e4 · 8 min left`. New on each card: **Last 7 days** (bars per day with the day's budget, extra time and what ran out; tap a day for its details, "no record" for a day without minutes; pool chips switch the bars) and **Today, hour by hour** from Home Assistant's statistics of the kid's Screen time today sensor. Below the TVs and phones, **Family today, by pool**. The page writes time in the one format (`2 h 10`, `45 min`, `till 6:30`).
- **A family card for a TV's dashboard.** The integration now serves `custom:hearth-family-card` on every dashboard (no resource to add): the household headline, requests and suggestions with their buttons, the family pause, a tile per kid (today line, All bar, what's on, the last 7 days, one give button) and each pool today, in big type with remote-friendly focus, for adults only. See docs/home-assistant-integration.md, The family card, for a `hearth-tv` dashboard.
- **Time reads the same everywhere.** The household summary's texts write time as `2 h 10 left`, `45 min`, `+1 h` and `till 6:30` instead of `130 left`; phone notifications offering more than an hour say `Give 1 h 30 more today?`.
- **The summary decides the dashboard's today line and colors.** Each person has `binding` (the pool that stops them first, which a give button targets), `day_line` (`2 h 10 of 3 h · games · 10 left`, or the pause or lock that replaces it) and `state` (ok, low, out, held, paused, locked, none); each group has `state` and `limited` (false without a budget, for surfaces that hide such groups). The household has `counts` (asks, suggestions, pairings, paused, and kids out, low, locked or held). Each day of `week` has its `budget` per group (recorded with the day from now on), each app of `apps_today` its `groups`, and each device of `devices_today` its `kind`.
- **Now playing says the one thing on and its time.** Each play is the most specific thing known: the episode, video, movie or track as `title`, with `series`, `artist` and `episode` (`s2e4`), and `kind` (video, music, game or app; an app in the Games group is a game). When the player gives its length, `remaining` and `progress` (`bluey · s2e4 · 8 min left`); else the minutes since it started (`minecraft · 25 min`); music has no time. Hearth TV builds may send `media_position_s` and `media_position_at` with `media_duration_s` for this. The `hearth_<person>_playing` sensor still shows the show's name.
- **Two kids on two Switches aren't "together" just because neither game is named.** A Switch that only says "Switch" plays together only with someone on the same console.
- **Now playing for everyone, kids and adults.** A kid on their Switch now shows as playing (the game when Nintendo's integration names it, else "Switch") and counts for playing together; Nintendo's own minutes still count the time. A TV with a media player in the options says the show and episode, not just the app, and "together" matches on the show. A phone without Hearth's app (a kid's Family Link phone, an adult's own) can show its app in use: turn on the companion app's **Last used app** and **Interactive** sensors on that phone and add the Last used app sensor as a source; it's playing only while the screen is on and never counts toward screen time. The household summary has a household-wide `playing` list (who, what, where, since when), each person's plays carry `title`, `episode` and `since`, and a person's own document (a TV profile's, a phone's, `hearth/me`) now says what they're playing. When a play ends, the history logs it as `played` (item, device, minutes; one a day per item and device, kept 28 days) for a later top-titles view.
- **Hearth for assistants (MCP and voice).** Hearth is now an LLM API in Home Assistant ("Hearth"): tick it in the MCP Server integration's options for Claude and other MCP clients, or in an Assist conversation agent's **Control Home Assistant** list. An adult can ask "how much YouTube does Sam have left?", "why can't she open that game?" or "what's waiting for me?", and give more time, pause or end a pause, allow an app or group, answer a request, put a suggestion off and take School time off; each acts at once, as that adult, and says exactly what changed (who, what, which device or pool, minutes, until) and how to undo it. Budgets can't be changed this way, and nothing lets a kid into an app or game a parent blocked in Family Link or Family Safety. Voice satellites (no signed-in user) get nothing unless **Let voice assistants use Hearth** is on (Hearth's page, People tab, or Configure > Voice assistants; off by default); then questions are answered, and actions go to the adults' phones to approve ("Sent to your phone for approval") and run as the adult who taps Allow, within 10 minutes. Hearth's history marks these actions `via` mcp or voice, with the user. See docs/home-assistant-integration.md, MCP and voice.
- **The last 7 days for each person.** The household summary now has each person's `week`: per day their minutes in each group, what ran out, extra time given and requests for more. Hearth records each day's minutes when the day ends (or when Home Assistant starts again after being down at midnight); days from before this release show no minutes.
- **A kid's phones lock even when Family Link's daily limit is switched off.** All screen time out of time now switches the kid's Family Link daily limit on while their devices are locked, and off again when there's time again (only if Hearth switched it on and it's still on).
- **Suggestions on the adults' phones.** In the Kids tab of Hearth's page, each kid's **Suggest to phones** picks which of their suggestions also go to the adults' phones (All screen time and each group with a limit, with +15, +30, +45 or +60); all off by default. When one appears ("Sam's YouTube ran out. Give 30 more minutes today?"), every adult's phone gets it once that day with two amounts and Not today, answered as the adult who pressed; it comes off every phone once more time is given, it's put off, the group isn't out any more or the day ends. At most 6 an hour. This replaces Configure > Offer more time (now Configure > Suggest more time to phones): its choices carry over with their amounts, and a group running out no longer also sends an offered request, so it's one notification, not two.
- **Suggestions on the TVs too, in adult profiles.** A suggestion that goes to the adults' phones also shows on the household's TVs while an adult's profile is on (never a kid's), once the TV's Hearth app shows Home Assistant's notices. A button pressed on the TV needs the Parent PIN, or a parent's phone: "Approve +30 min for Sam? Asked on Kitchen." with that button and Don't allow, run as the adult who taps it. It comes off the TV with the suggestion, and the phone's question after 10 minutes. Hearth's history says which adult answered.
- **Kids' news stays off Home Assistant's bell.** The bell shows to everyone who uses Home Assistant, so a kid's request for more time (and its note), an offer, where a kid went and chores done now go only to the adults' phones; requests are still answered there or on Hearth's page. The bell keeps the household's own business: pairing, a TV's rules taken, a Family Safety answer that failed, new apps to sort and the schedule's checks.
- **Devices can say what they can do.** A Hearth device's status may carry `caps` (`commands.play`, `events`, `push`, `notices`), so a phone can take plays or a TV pings when their apps learn to. A device that doesn't say keeps what its kind always had: a TV is played on and posts HearthTube's videos, a phone gets pings.
- **Every Hearth phone notification is tagged.** Chores done and the schedule's checks now carry a `hearth_...` tag like requests do (a chore's own, so each stays), so an app such as Glint can pick out Hearth's notifications. (Inside, every notice now goes through one delivery layer.)
- **Suggestions: the answer ready before the question.** When a kid's group runs out, the household summary suggests more of that group (or only All screen time, when that's what is out); when Google's, Microsoft's or Nintendo's own limit stops a device while Hearth's time isn't out, it suggests extra time on that device. Each suggestion has two amounts and "not today" (the new `hearth.dismiss_suggestion`). The amount is the household's own, else what an adult usually gives, else 15 minutes (30 for All screen time).
- **History.** Hearth keeps 90 days of what ran out, what was asked and offered, the answers, the bonuses and the suggestions put off, without names or notes. Suggestions are sized from it.
- **Hearth's page: one kid at a time.** Each kid's card can pause that kid alone (every TV, phone, Xbox and Switch of theirs), end an app or group pause, take School time off today or put it back, and open **Today by device and app**: minutes per device with +15 on one device, and the apps used most. Taken from the Family Link and Family Safety dashboards, done through Hearth so every device follows (docs/dashboard-parity.md).
- **Hearth's page: the Switch.** The Kids tab has a card per Nintendo Switch of a kid's: played today (their own player's on a shared Switch), the Switch's own limit, time left and extra time, playing now and last synced, with Hearth's extra time on that Switch, Nintendo's own extra playing time and its cancel, and the games' allow list, each only when the installed Nintendo integration has it (core takes 15 or 30 minutes; a patched copy more, "rest of today", cancel and the allow list). Nintendo's own extra waits while Hearth holds the Switch. The summary's `first_party` has a `nintendo` row per Switch, and an adult's app gets a "nintendo's own limit" line like Google's and Microsoft's.
- **Hearth's page: is each parental control working?** Devices lists Family Link, Family Safety and Nintendo with their state (and Family Safety's connection), and Today says so when one isn't loaded or Family Safety's connection is degraded.
- **Day-off extra minutes on Windows, the Xbox and the Switch.** Configure > Schedule has two new options, both off by default: "Extra minutes as Family Safety's daily limits today" (`bonus_family_safety`) and "Extra minutes on the Switch's limit today" (`bonus_nintendo`). On a day off or half day, a chosen kid's Windows and Xbox get this weekday's limit plus the extra (`microsoft_family_safety.set_screentime_limit` with `day_of_week`), and their Switch today's limit plus the extra (at most 360 minutes, once per shared Switch). Neither has a today-only limit, so Hearth records what it added to (kept across a restart) and puts it back itself: 2 minutes before midnight, at once when the day off is cancelled or the day type changes, or at the next start if Home Assistant was off; only while the limit still reads Hearth's, so a parent's change stays. A write that failed is tried again that day and reported at the 06:00 check (the Xbox's needs the Xbox Family Settings sign-in). While Hearth holds the Switch, the extra goes into the limit the hold puts back. Family Safety's `today_only` is not used; "Extra minutes as Family Link's daily limits today" stays Family Link's alone.
- **A family pause holds the Switch.** A family pause of a kid, or a pause of a group their Nintendo enforcer covers (Games by default), now holds their Switch too (limit 0, software suspended), let go when the pause ends or before midnight, and only for the one playing on a shared Switch. A parent's grant in the Nintendo app lifts it; an allow doesn't.
- **A kid with two Switches has a hold on each.** Each Switch is held and let go on its own; the person's status still shows one Nintendo line.
- **Family Safety's apps from its Applications sensor.** A kid's Family Safety Screen Time without an apps list now takes its per-app minutes from the same kid's Applications sensor (the Xbox's Screen Time takes only the Xbox's apps), counted as soon as it changes, and the app pickers offer those apps.
- **Extra time past a Family Safety platform's allowed hours.** Microsoft's extra time doesn't lift a platform's allowed hours, so a bonus at 21:45 ended at 22:00 anyway. Extra time from Hearth that runs past the end of today's allowed hours on Windows or the Xbox now moves that end to cover it, rounded up to the next half hour (Family Safety's `set_screentime_intervals` with `today_only`, which Family Safety puts back at midnight). Ended early, the old end goes back, unless a parent changed it since. And every platform a kid's Family Safety reports is now a target for extra time on one device (`fs:windows` for a PC Hearth doesn't hold, say), not only the ones Hearth's enforcer holds.
- **Family Safety extra time on Windows too.** Where Hearth gives Family Safety extra time (an allow of All screen time, extra time that gives it back, extra time on `fs:windows`), a kid whose Family Safety covers Windows now gets it on Windows as on the Xbox, when the installed Family Safety takes `platform: Windows` (one that doesn't is skipped quietly). Ending it early cancels only Hearth's own extra time: a parent's that came since is kept. Family Safety's answer says whether Hearth's lock is kept for after the extra time (`hold_kept`, or upstream's `replaced_lock`), so Hearth stops holding a platform only when that lock really ended.
- **A Family Safety request settled outside Hearth says so.** When a request made on an Xbox or a PC leaves Microsoft's list without Family Safety seeing how (answered in the Family Safety app or on the device), its Hearth request now closes as handled ("handled outside Hearth"), not as expired; one approved or denied there says which.
- **Family Safety without the web session.** Hearth follows the Microsoft integration, which now runs on its mobile token and the Xbox Family Settings service: extra time replaces a lock only when it's Hearth's own (never a parent's), an unlock that leaves extra time running is understood, and the minutes of an approved request are fitted to Family Safety's 15 minutes to 8 hours.
- **Steadier reloads.** Changing an option or reloading the integration waits for Hearth's running work (store writes, Family Link and Family Safety calls) before the new instance starts, the Parent PIN lockout is kept across a reload, and the app list is built once per status instead of once per group.
- **A parent's app grants read as apps, together and calm.** In the household summary's lines (contract 2), an app a parent opened in the Family Link app is named ("youtube kids", from Hearth's app catalog, the kid's Family Link sensors or their apps today, else a guess from the package), never shown as its package. Grants from the same parent's app ending at the same time are one line: two or three by name ("youtube kids and roblox open · the family link app till midnight"), more as a count ("16 apps open · ..."), with a key that holds while the set does. These standing app limits are calm and listed last, never the headline; a parent's bonus, unlock, Switch or platform let go, and an adult's allow, are still news. Times at 12:00 say "midnight" and "noon". App grants in the summary carry the app's `name`.
- **Extra time on one device.** `hearth.add_bonus` and `hearth.allow` take a `device` (`hearth:<id>`, `fl:<id>`, `fs:xbox`, `fs:windows`, `nintendo:<entity>`): minutes, or a group open until a time, on that device only, while the shared time keeps counting and every other device still reads it. A Hearth TV or phone shows what's left there; a Family Link device gets Google's bonus on it alone; the Xbox or a Windows PC is unlocked with Microsoft's extra time; a Switch is let go. Family Link, Family Safety and a Switch take All screen time only (their holds of a group are the whole account's). The household summary lists each person's `targets` and `device_extras`, with a line and an end action; `hearth.explain` names it; `hearth.allow_end` with `device` ends it. `hearth.add_bonus` with a device answers its id, so one bonus can be undone alone; `playing` names each device's target; TVs are named as shown ("Den TV"); a handset that's both a Hearth phone and a Family Link device is marked (`same_as` / `also`).
- **Today's minutes by device and by app in the household summary.** Each person has `devices_today` (Hearth TVs and phones, Family Link devices with their own sensor, a Switch, other sources) and `apps_today`, as Hearth counts them, so an adult's app can show where the time went without reading the sensors.
- **"No school time today" from an adult's app.** On a school or half day, until a kid's School time ends and unless it's already off, the household summary offers `school_off` (confirm) for them, calling `hearth.school_time_off`, and says their `school_time` window today.
- **Pause one app or group.** `hearth.pause` takes `app` or `group` (YouTube and HearthTube, say) and pauses only that, for some minutes or until a time, for the people chosen or everyone. Their Hearth TVs and phones hold it as a group with no time left, Family Link pauses its apps on phones and Family Safety its Xbox and Windows apps; an allow doesn't lift it and `hearth.explain` names it. `hearth.pause_end` with the same `app` or `group` ends just that one; without either, it ends only the family pause. The household summary lists each person's app and group pauses (`pauses`), with a line ("youtube paused · homework till 7:00") and an action to end each, and the household's groups (`groups`, budget or not), so an adult's app can show and end them.
- **A negative bonus takes time away.** `hearth.add_bonus` with negative minutes (and the panel's −15) did nothing unless a bonus had been given that day, because Bonus today stopped at 0. It now goes below 0, so the minutes left drop (to none at most) for today only.
- **Speakers in different rooms stay apart.** Two players of the same kind (for example two ESPHome voice satellites, whose entities are all called "Media Player") were taken for one player and shown in one room. A generic name no longer joins players, and players in different areas are never put together.
- **Music Assistant display players join their TV.** A player named like `<tv>_music_assistant_display` or "<TV> (Music Assistant Display)" is now grouped with its TV in the media rooms, as the other Music Assistant players are.
- **Explain names a parent's Family Link app limit.** When an app has a Family Link app limit a parent set (not one of Hearth's pauses) and it's used up on a device today, `hearth.explain` now lists it as `app_limit` (the app, the device, the limit and the minutes used) instead of saying the app is allowed. Hearth's allows and bonuses don't raise that limit: an adult raises or removes it in Family Link.
- **Requests reach every adult's phone.** Requests for more time, offers and chores done go to each adult on Hearth's page, on every Home Assistant companion app of theirs (found from their person), as well as the phone chosen in Configure; each adult can be switched off on Hearth's page. A tap opens Hearth's page at that request (`/hearth?ask=<id>`), or on Android the deep link `hearth://ask/<id>` for an adult who chose it. Once a request is answered anywhere, it leaves every phone.
- **A kid's own Home Assistant user.** A kid signed in to the Home Assistant app with their own user can read their own minutes left, locks and request (`hearth/me`, and `hearth/me/subscribe` for changes) and ask for more time (`hearth/ask`), the same way their TV or phone does, with the same one-open-request rule and the wait after "not now". Nothing else is open to them: the household, the answers and every `hearth.*` service stay with the adults.
- **Places.** Configure > Places (and Hearth's page): Home, each kid's School and favorite places, all Home Assistant zones. Each kid gets a Place sensor (home, school, a favorite's key, away or unknown) from their Family Link location while it's fresh (20 minutes), else their person in Home Assistant; never a router or Wi-Fi tracker. A change needs two agreeing readings or three minutes and fires `hearth_place`; Hearth keeps no coordinates. `hearth.allow`, `hearth.pause` and `hearth.school_time_off` take `ends_on` (`arrive` at or `leave` a place): it ends for each kid as they get there (or leave), with Hearth's extra time in Family Link and Family Safety taken back and the adults told; the time stays the cap, and an unknown place never ends anything. Hearth's page shows each kid's place and "until arriving home"; the household summary has each kid's `place`; a kid's own device only hears "ends when you get home".
- **The parents' own apps, kept in step.** A parent's change in the Family Link, Nintendo or Family Safety app is an adult's decision, and Hearth now adopts it: a limit a parent changed while Hearth held it is never put back over (Family Link's daily limit, the Switch's limit), and a bonus, a raised limit, an unlock, extra time or a changed app pause becomes a *grant* that lifts only that hold, shown with where it came from ("from the Family Link app") on Hearth's page, in the household summary and in `hearth.explain`. An adult can end one early (`hearth.allow_end` with its id) where that's a write in the parent's app (a bonus reset, extra time cancelled, the Switch or Xbox locked again). The other way, allowing All screen time (or giving it back with extra time) adds a Family Link bonus and Family Safety extra time where Google's or Microsoft's own limit would stop the device, and takes it back when the allow ends early. `hearth.explain` names Google's and Microsoft's own limits (`device_limit`) and a parent's own Family Safety lock (`parent_lock`); a Family Safety request answered in the Family Safety app closes its Hearth request. Hearth's page shows each kid's Google and Microsoft limits and what Hearth last did through each parental control, with errors.
- **Family Safety, closer to Family Link.** The Xbox/Windows lock names the child by the chosen entity and runs until midnight exactly (an older Family Safety is called as before), and an unlock that finds a parent's own lock leaves it. The daily website list syncs into Family Safety too, on its own. A request for more time made on an Xbox or a PC comes to Hearth like a TV's, and the answer goes back to Family Safety. A group can list Xbox and Windows apps: they're paused through Family Safety while the group is out of time. Family Safety's Downtime Active sensor works as a bedtime lock.
- **`hearth.copy_sites`** copies a kid's blocked (or allowed) websites between Family Link and Family Safety. It only adds, leaves list-synced sites and conflicts alone, and has a dry run.
- **The household summary, contract 2.** Each person in the summary now carries a `headline` (what an adult's app should say about them now: a request waiting, a pause, out of time, bedtime soon, a group running low, an allow, School time off, or the minutes left), the other `lines`, and the `actions` an adult can take right now as service calls (answer a request, +15 minutes, pause or end the pause, end an allow); the household gets its own headline and actions (pause everyone, end the pause, answer requests). Hearth picks them, so Glint shows new Hearth features without an update. Everything from contract 1 is unchanged.
- **`hearth.answer_request`** answers a request for more time (minutes, or not now) as a service; the first answer wins.
- **Only adults call Hearth's services.** Every `hearth.*` service now refuses a caller who isn't an administrator or an adult on Hearth's page (automations still may), so a kid with a Home Assistant user of their own can't give themselves time or read the watch log.
- **Exceptions.** `hearth.allow` lets people use an app or a group until a time (`end_of_day`, `school_time_end` or a time), with a reason: while it lasts Hearth holds it nowhere for them (TVs, phones, Family Link, the School-time pause), and it ends on its own. `hearth.allow_end` ends one early. `hearth.explain` answers why an app or a group is held for someone now (budget, bedtime, School time, a pause, the School-time pause) and until when. Each person's Screen time today sensor lists their exceptions.
- **School-time pauses.** Configure > Enforce, per person: during Family Link School time, pause these apps (Google Messages by default). Hearth is now the one owner of Family Link's pauses, so a School-time pause and a group out of time no longer undo each other.
- **The schedule.** School days know half days, and a Day type sensor says today's (school, half day, day off, weekend, no school). Configure > Schedule: on a day off, School time off for the day and put back at the start of the next school day, inside each kid's own window (never switched on outside it) with today's hours pinned; on a half day, School time ends some hours early; extra minutes on both, as Family Link's today-only limit and/or a Hearth bonus; a watchdog tells the adults when School time is still off on a school day. `hearth.school_time_off` (people, date, from) and `hearth.school_time_off_cancel`.
- **Website block list.** Configure > Website block list syncs a published list into each kid's Family Link every day at a set time (`familylink.sync_site_list`); one kid's failure doesn't stop the others.
- **Chores and offers.** Configure > Chores earn time: each chore checked off on a kid's to-do list adds its minutes (15, or the chore's "+N") to a group today. Configure > Offer more time: when a kid's group runs out, the adults are asked whether to give more, with the same buttons as a request.
- **Push to phones.** With an ntfy server set (Hearth's page, Devices > Push to phones, or Configure), Home Assistant pings a paired phone on its own random topic when its state changes, so it updates at once instead of at its next check. The ping says only "changed"; the phone fetches the rest with its secret. Off unless a server is set.
- **Play on a TV.** `hearth.play_on_tv` starts a YouTube video (in HearthTube), an app or a link on a Hearth TV, in a chosen profile if you like, from an automation, a dashboard or a phone. The TV takes it with its next status (within about 2 minutes while it's on) and `hearth_command_done` says how it went. Home Assistant's side only: the TV side is still to come.
- **Media rooms.** The household summary and every phone's state carry the house's media players by room (`media_rooms`), with an Echo's "Now Playing" twin, a console's Music Assistant player and the like put together under the one player to control, for Glint's Music to show what's playing where.
- **A shared Switch.** Nintendo's limits are the whole console's, so holding one kid held everyone. Now a kid's Nintendo hold can follow a "playing" sensor (on while they're the one playing): the Switch is held only while they play, and a brother or sister with time left can use it. With Nintendo's own data that can be up to about 10 minutes late either way. The Switch also waits out bonus time from the Nintendo app, and a weekday held past midnight gets its limit and bedtime back.
- **New apps sort themselves.** Nobody is asked any more: a new app goes to a group that lists it, else its kind (games, video, social, messaging; from the app, or a category a Glint phone sends), else Other. Hearth's page shows what was sorted lately and every app with its group, and moving one is a tap; your choice always wins. New built-in groups **Social** and **Messaging**; Messaging doesn't count as screen time unless you tick it.
- **Second parents; a TV's media player.** Second parents (adults on Hearth's page) can answer requests for more time; each TV can be given its media player on Hearth's page, for Glint's TV tile.
- **Ask for more time.** A kid's TV or phone asks for 15, 30, 45 or 60 more minutes; the adults get a notification (and a card on Hearth's page) with quick answers, the first answer wins, and the device hears it with its next status. One open request per kid, and a short wait after "not now".
- **Family pause.** `hearth.pause` (for some minutes or until a time, with a reason, everyone by default) holds the kids' Hearth devices; `hearth.pause_end` lets them go. Hearth's page has a Pause everyone bar.
- **Bedtime heads-up.** Each person's state says when their lock ends and when the next bedtime or school time starts (from Family Link's sensors), for devices to wind down; Hearth's page shows "Bedtime in 15 min".

## 2026.11.09 (pre-release)

- **The TV app is Hearth TV.** Hearth is now the name of the household system and its Home Assistant integration; the home screen app on the TV is **Hearth TV** (its name in Android's lists, the setup and the docs). Nothing to reinstall: the app, its id and the release files are the same. The integration shows Hearth's own icon in Home Assistant 2026.3 and later, and its version is now the release version.

## 2026.11.08 (pre-release)

- **Getting started says what's set in Google TV.** The setup's Your family card now starts with "Add everyone in Google TV": every adult and child is added as a profile in Google TV (Settings → Accounts & profiles), not in Hearth, and each kid's apps are picked in Google TV for their profile; Hearth can't show an app a kid's profile doesn't have. **Settings → System → Set up Hearth** keeps it under Google TV's own settings.
- **Leave Google's time limits off with Home Assistant.** On a TV paired with Hearth on Home Assistant, the setup says not to turn on Google TV's or Family Link's daily time limit or bedtime for a kid's TV profile: Google's own limit wins over Hearth, so extra time and approvals can't get past it. When the TV saw Google TV's own time's up screen in the last week, the step comes back and Set up Hearth says "Google TV's own limit is on".
- **The profile chooser survives a power-button wake.** With Log out when the TV sleeps, the chooser opened as the TV slept, but waking it with the power button brought up Google TV's own home (or the last kid's time's up screen) over it. Hearth now opens the chooser again a couple of seconds after the wake, once, unless someone already pressed a key or picked a profile, or Use Google TV's home is on.
- **Home Assistant notifications for one person, the same on every TV.** A notification's `for` can now name a profile's ref (`name:alex`) or a Home Assistant person (`person.alex`), which every TV resolves to its own profile for them. A profile number (`user:10`) still works, but only as that TV's own profile: the same number is someone else on another TV.
- **Other apps can ask for the time's up card.** `com.thesiegs.hearth.action.TIME_UP` (extras `package`, optional `group`) brings Hearth's home to the front with its time's up card and "ask for more" when the kid is out of time for that app, or just the home when nothing holds it. It works from a kids profile's own user too (through Hearth's agent there), for HearthTube's coming "Ask for more time" button. See docs/provider-contract.md.
- **Apps out of time look it on the home.** In a kids profile, an app whose group is out of time (or every app, during a family pause or a lock) shows grey and faded on the dock and in All apps, with a small "0 left" or clock badge. It can still be selected; pressing it shows the time's up card with "ask for more" and never opens the app. It looks normal again as soon as time comes back. Adults' profiles, groups without a limit and Hearth's own entries are never affected.
- **Google TV's own Kids daily limit is told apart.** When Google TV's own daily limit (set in Family Link or the TV's Kids profile) runs out, its time up screen blocks the whole profile whatever Hearth allows, and a Hearth bonus can't get past it. The TV now reports it (`google_time_up`), `hearth.explain` lists it as `google_tv_limit`, and the person's headline says "google tv's own limit". Hearth can't lift it: raise or turn off the profile's daily limit in Google TV (turning it off lets Hearth own the limits).

## 2026.11.07 (pre-release)

- **A kid's TV profile is the same kid on every TV.** Each TV numbers its profiles itself (one kid is profile 10 on one TV and 12 on the next), and Home Assistant mapped them by that number, so on a second TV one kid could get another's limits and count against their time. Hearth now tells Home Assistant who each profile is by its name, the same on every TV, and Home Assistant maps profiles by name (or, for a TV with an older Hearth, per TV).
- **Switching profiles no longer hangs on the welcome card.** A switch Google TV announced while Hearth was still checking the profile was missed: the "Hi" card stayed up for about 30 seconds, ignoring the remote, and then the previous kid's home showed. Hearth now checks again.
- **Home Assistant: TV profiles by name.** Hearth's page and Configure list each TV profile by name, once for all the TVs that have it. Old mappings by number no longer count; a repair issue asks an adult to pick the profiles again.
- **Home Assistant:** a TV's bigger status posts were sometimes refused (400) when they arrived in pieces; they're now read whole.

## 2026.11.06 (pre-release)

- **Time's up on the TV, with asking for more.** On a TV connected to Home Assistant, an app a kid can't open now shows Hearth's time's up card instead of a short message: why (a group's time is up, a family pause with its reason, bedtime, school time) and until when. When time is up and nothing else holds them, the kid can ask an adult for 15, 30, 45 or 60 more minutes right there, and the card shows the answer as it comes: waiting, an adult added time, not now (with a short wait before asking again) or no answer in time. The home's "Nothing to watch" card says the same.
- **A family pause holds the TV's apps** until it ends.
- **Bedtime heads-up on the TV.** A quiet note 15 and 5 minutes before a kid's bedtime or school time ("Bedtime in 15 min"), with no sound.

## 2026.11.05 (pre-release)

- **Parent PINs from Home Assistant are checked there.** A connected TV asks Home Assistant whether a PIN is an adult's, and its answer (and its lockout after wrong guesses) is final whenever it's reachable. The TV's copy of the PINs, for when Home Assistant is down, is now kept encrypted with an Android Keystore key (it was kept in the clear), and Home Assistant sends it again only when a PIN changes.

- **Home Assistant: Hearth's own page.** A Hearth entry in Home Assistant's sidebar (administrators only) with a guided setup and five tabs: **Today** (each kid's time left, what's playing, extra time in a tap, the TVs and phones), **Kids** (daily limits for school days and other days, screen time sources, bedtime and school-time locks, Family Link, Family Safety and Nintendo, YouTube's watch log and blocks), **Devices** (pair a TV or phone by checking its code, TV profiles), **Apps** (groups, their apps, what isn't screen time, new apps) and **Family** (kids and adults, each adult's parent PIN, Glint tile sharing, school days). It follows Home Assistant's theme and works on a phone.
- **Home Assistant:** the household summary for an adult's app (`hearth/household`, with a subscription), and a paired phone is told Home Assistant's addresses so it can sign in there.

## 2026.11.04 (pre-release)

- **A parent PIN for each adult, from Home Assistant.** Each adult's own 4-digit parent PIN is set in Home Assistant (Hearth > Configure > Parent PINs). A connected TV takes them in place of its own Parent PIN, accepts any adult's (HearthTube's PIN checks too), and shows **Set in Home Assistant** in Settings > Family. The TV keeps them, so they work with Home Assistant down; disconnected, it keeps the last ones until a PIN is set on the TV. Each lockout after wrong guesses is reported, and Home Assistant fires an event for it. A TV without the integration keeps its own PIN as before.
- **Home Assistant: phones check the parent PIN.** A paired phone asks Home Assistant whether a PIN is an adult's (`verify_pin`) and is told whose; it never gets a PIN. Wrong guesses lock it out for longer each time.
- **Home Assistant: tile exchange sharing.** A parent chooses whose phone may share with the launcher's tile exchange (Configure > Tile exchange sharing); the person's state says `tile_exchange_share`.
- **Home Assistant:** the Glint launcher and HearthTube Mobile are never paused.

## 2026.11.03 (pre-release)

- **Home Assistant: Not screen time.** A group (music, say) can be left out of All screen time (Configure > Not screen time): its minutes count only in the group, and its apps stay usable when All screen time runs out, on the TVs too. The Screen time today sensor lists each group's packages (`groups_apps`).
- **Home Assistant: All screen time locks Family Link devices.** When All screen time runs out, Family Link's daily limit for the day goes to 0 instead of pausing every app, so the apps a parent gave unlimited time (YouTube Music, say) still work; the limit is put back when there's time again, and before midnight. Apps with unlimited time are never paused for a group either.

## 2026.11.02 (pre-release)

- **Log out when the TV sleeps** is now on by default (every time the TV sleeps) on TVs where it was never set; a TV where it was chosen, or turned off, keeps that choice.

## 2026.11.01 (pre-release)

- **Log out when the TV sleeps** (was Lock when the TV wakes): the profile chooser now opens as the TV goes to sleep, or once it has slept the chosen time, so the next person never sees the last profile's home. It now logs out of kids profiles too; before, a TV left in a kid's profile woke straight into it.

## 2026.10.87 (pre-release)

- **Streaming app PINs**: Recent PIN entries names Google TV's PIN screen "Google TV" instead of its package, and the remote can scroll down through every entry. The note about whose PINs are on the page is gone.

## 2026.10.86 (pre-release)

- **Streaming app PINs**: the steps Hearth follows to type a saved PIN (Disney+, Netflix, Max, Apple TV, Paramount+'s content PIN, Google TV's PIN screen) are now a recipe file. Hearth carries its own and checks this repository for newer ones at most every 12 hours, so a fix after an app update reaches the TVs without a Hearth release. A fetched recipe can only do what the built-in ones can (press digit keys of that app's own keypad, move and press OK), and anything wrong with the file means Hearth's own are used. Keys are now pressed only in the app's own window and only on a complete keypad.
- **Phone approval and Parent PIN by phone** share one connection to Home Assistant while a request waits, and it reconnects if Home Assistant restarts meanwhile: an Allow pressed after the restart still counts.
- **Built on Flutter 3.47** (from 3.24), with current libraries: the database library moved off its end-of-life package. Nothing should look or work differently. Home Assistant panel images no longer fail now and then (the connection was closed before the picture was read).
- Many screens now share one implementation (cards' focus glow, choice dialogs, count pills, the phone setup pages' server), and a lot more of Hearth is covered by tests.

- **Time format**: the 12-hour choice without AM/PM (3:45) now shows 3:45 in the afternoon; it showed 15:45, like the 24-hour one.
- **Blocked notifications**: an app's **Unblock Notifications** badge wraps instead of running past the edge of its row.

## 2026.10.85 (pre-release)

- **Network in Settings.** **Settings > TV & power > Network** opens the TV's Wi-Fi and Ethernet settings, and shows how the TV is connected (Wi-Fi, Ethernet, no internet, VPN on). Google TV has no VPN settings of its own: a VPN is an app.
- **Who is on stays between Hearth and HearthTube (provider contract 9).** Hearth's profile provider now answers only HearthTube (signed with Hearth's key): another app on the TV can no longer read the active profile's name, whether it's a kids profile, its YouTube minutes or its bedtime lock.
- **Parent PIN**: five wrong tries in HearthTube lock the check for a minute even if Hearth restarts meanwhile; before, a restart gave five fresh tries.
- **A parent's channel to a kid's HearthTube (provider contract 8).** HearthTube tells Hearth each video a kids profile starts, and Hearth keeps the log per kid; the parent's blocked videos, channels and words go the other way and HearthTube applies them, locked against the kid. Read the log and edit the lists in **Settings > Family > Kids profiles > the kid** (**Videos started**, **Blocked on YouTube**), no Home Assistant needed; Home Assistant's own side is still to come.
- **Home Assistant notification buttons on every TV.** A notification's buttons ("Unlock door") are now in the Bell of every household TV, and in its pop-up on the other TVs. Pressed on any TV, the button runs once and the notification goes from every Bell: a TV with its own Home Assistant connection calls the service itself, any other asks the TV the notification was sent to, which runs only the button of its own copy and only within two minutes of the press. The buttons are checked again on every TV against the same limits, so an entry from another TV can't call anything Home Assistant's own notification couldn't. Kids' profiles still never see adults' notifications. In the Bell, a notification with buttons opens its options on Dismiss, so a stray OK never presses one.
- **Notifications in the Bell, across the household.** Home Assistant's notifications now also go in the notification Bell, and with household sync on in the Bell of every TV of the household; clearing one (or Clear all) clears it on all of them, and they leave after three days. Each shows only to the profile it's for: Home Assistant can name a person with `for` (a profile's name, Google account address or profile id), and one without goes to every adult. Kids' profiles see only what is sent to that kid. A `tag` replaces an earlier notification, and `clear_notification` with its tag clears it. Cameras stay in the pop-up; the server's limits are unchanged. A TV asking to join the household now shows in the Bell of every household TV, for adults, and Allow or Don't allow works on any of them (the first answer decides).
- **Household sync: joining is checked.** A TV asking to join now shows its six-digit code in the request on your TVs (the Bell and its Allow dialog): check it matches the new TV's screen before you choose Allow. Allowing no longer hands over Home Assistant by itself: a second question, **Also give it this TV's Home Assistant connection?**, follows, and no answer is no. The TVs' member list, removals and the Parent PIN are now signed by the TV that wrote them, and taken only from a TV that is on the list: a removed TV can't add or remove TVs or change the Parent PIN through a TV that hasn't heard of the removal, and no TV can add one in another's name. TVs on older builds keep syncing as before until they update.
- **Household sync**: a device on the network that opens a connection and then sends almost nothing can no longer hold up syncing: a connection gets 20 seconds to prove it's one of your TVs, off the thread that does the syncing, and only then is it let in.
- **Household sync: join requests** leave the Bells as soon as the TV that asked backs out or goes off, instead of waiting out the five minutes, and a device that asks again and again waits longer each time (up to an hour). A second request arriving while one waits no longer stops the first from being answered.
- **Household sync**: entries passed on in another TV's name with a made-up count can no longer keep that TV's real changes from arriving: each TV is believed about how many changes it wrote itself, and the made-up ones go when the TVs meet.
- **Household sync**: a TV asking to join can't be answered while a kids profile is on, even by a press that reaches the Bell some other way, and the copy of this TV's settings from before it joined is deleted after its 14 days even if no one opens the Household sync page.
- **Continue Watching** cards open only another app's screen, never one of Hearth's own and without handing out access to Hearth's files, and a card that came from another TV opens only in the app it's filed under.
- **Notifications in the Bell, across the household.** Home Assistant's notifications now also go in the notification Bell, and with household sync on in the Bell of every TV of the household; clearing one (or Clear all) clears it on all of them, and they leave after three days. Each shows only to the profile it's for: Home Assistant can name a person with `for` (a profile's name, Google account address or profile id), and one without goes to every adult. Kids' profiles see only what is sent to that kid. A `tag` replaces an earlier notification, and `clear_notification` with its tag clears it. Buttons and cameras stay in the pop-up; the server's limits are unchanged. A TV asking to join the household now shows in the Bell of every household TV, for adults, and Allow or Don't allow works on any of them (the first answer decides).
- **Dock**: it no longer shifts a little as the selection moves from app to app. A dock just too wide for the screen could scroll by a few pixels, and each app centred itself; now the dock never scrolls, and apps that don't quite fit are drawn a little smaller.
- **Home Assistant: the Hearth integration.** A Home Assistant integration of Hearth's own (`custom_components/hearth`, install from this repository) and **Settings > Home Assistant > Pair with Home Assistant** on the TV: the TV shows a code, an adult confirms it in Home Assistant, and the TV reports its status there with no token or webhook. Home Assistant gets each TV and each person (mapped from the TV profiles), screen time counted once across Hearth's TVs and other integrations' sensors (Family Link, Family Safety, Nintendo, Xbox, Switch presence), titles, playing together, groups with weekday and weekend budgets, bonuses and minutes left; the TV gets each profile's minutes left back, and HearthTube's YouTube allowance comes from them. School days decide which budget applies (a helper or entity, a calendar, typed-in dates, or Monday to Friday within the school year). When a group is out of time, a paired TV holds its apps in that kid's profile (they don't open from Hearth, and come back to Hearth's home when opened another way), Family Link pauses its Android apps and Microsoft Family Safety locks the Xbox (Configure > Enforce), and both are let go when the group has time again.
- **Home Assistant: Nintendo enforces too.** With the built-in Nintendo Switch Parental Controls integration, Configure > Enforce takes a person's Switch (its Max screentime today): while Games or All screen time is out of time, its limit is set to 0 with Suspend software on, and the limit and Suspend software it had are put back when there's time again (after a restart too, and before midnight, since the limit is the Switch's setting, not today's). A Switch's Used screen time added as a source counts as Games without choosing it.
- **Home Assistant: All screen time out of time holds the phone too.** Family Link now pauses every app Hearth knows of the person's (any group's, and any in their usage today on any device) when All screen time runs out; before, it held nothing then. Calls, texts and the system are still never paused.
- **Home Assistant**: a person's Screen time today and group sensors no longer go down a minute during the day, which Home Assistant's recorder warned about ("not strictly increasing"); they keep the highest shown today, after a restart too. A screen time source that turns unavailable keeps counting its last number today instead of dropping out.

- **Household sync: Parent PIN.** The household's TVs share one Parent PIN (as its salted hash, never the PIN). A TV that joins without one takes it; a change or removal on one TV, which needs the PIN there, reaches the others. A TV that had its own, different PIN when it joined keeps it until an adult chooses **Use your other TVs' Parent PIN** in Settings > Family and enters theirs.
- **Household sync: Continue Watching.** Each person's titles (what played, and Watch Next entries Hearth kept for them, with their deep link) follow them to the household's other TVs, in the background whenever Hearth's accessibility service runs. The newest play of a title wins, one finished anywhere drops its "continue" card everywhere, and a card taken out on one TV goes from the others. Titles from apps a TV doesn't have aren't shown there. Kids profiles' cards sync too, each only ever in that kid's own row, and a card from another TV brings its poster with it.
- **Continue Watching** cards without a poster Hearth can read (the app gave none, it's kept inside a kids profile, or it hasn't come from another TV yet) show the title's picture from TMDB instead, found the way search finds titles. Only an exact title match is used, never one TMDB marks adult, and YouTube and HearthTube videos aren't looked up.
- **Kids profiles' watch history**: what plays in a kids profile (title, episode, how far it got) is now kept for that kid, as it is for adults, so their Continue Watching also shows shows from apps that don't use Watch Next, and with household sync on it follows them to the other TVs (their own row only). It needs Hearth's notification access in that profile, which a parent's Fix in Settings > Profiles > Kids profiles now grants with the other permissions there.
- HearthTube and the kids profiles' agent check the Parent PIN in its salted form too; before, only the old form worked there.
- **Setup**: when your other TVs are in a household, a **Join your other TVs** screen comes right after the Home button and home app steps (it looks for a few seconds when the flow has just opened). Joining skips the look, Parent PIN and Profile Pairing screens, which come with the household; Hearth turns Profile Pairing's switch on itself when it can. **Ad tracking** is its own step right after, shown whenever some of it is still on, and walks through turning the TV's debugging on when it's off, so it's no longer skipped without a word. Starting a household moved to a step just before Finish, and Finish says whether the TV is in step with the others. The household texts no longer point to the removed Copy screens.
- **Household sync: looks and layouts** now merge setting by setting, row by row and app by app, the later change winning: change the accent on one TV and the dock on another and both stay. Taking another TV's look no longer clears which calendars and Watch Next programs a profile hides on this TV, and a profile set up only on this TV reaches the others without having to be on screen.
- **Household sync: hidden calendars follow the person.** The calendars a profile turns off for the top bar's date and time (its Calendars settings) are now the same on every TV of the household where the same Google account is, each calendar on its own, the later change winning. A calendar is now known by a key made from its account and itself rather than by this TV's number for it; calendars turned off before are moved to their keys the next time that profile's calendars are read. One turned off on a TV that alone has its account stays off for when it shows up on another. Without household sync, turning calendars off works as before.
- **Household sync: joining** shows what would change on this TV before anything does ("These will change on this TV: Alex: look, home layout, 1 saved PIN"), with **Join and use these**, **Don't join** and **Later**. A copy of this TV's looks, layouts, wallpapers, streaming profiles and saved PINs is kept for 14 days, and **Put back this TV's settings from before it joined** on the Household sync page restores it.
- **Home Assistant**: a TV paired with the Hearth integration, or given a new address or token, reports its status at once instead of at the next round (a paired TV without a webhook could otherwise wait for something to change).
- The code of the removed Copy profiles screens is gone (its network port and announcement with it).

## 2026.10.84 (pre-release)

- **Ad tracking**: when it's kept off but still on (Hearth's debugging not approved yet), the page shows **Turn it off now**, which does it after the TV asks once to allow debugging.
- Letting ad tracking back on also turns on any part of it found off, not only what Hearth turned off itself.

## 2026.10.83 (pre-release)

- **Ad tracking** (was "Google's ad sandbox", Settings > System): **Keep ad tracking off** is now on unless a parent turns it off, and covers the kids profiles too. The page and the setup step say what it is in plain words, without the shell commands.
- **Lock when the TV wakes** works after Hearth was updated or restarted while the TV slept; before, that wake went straight to the last profile.

## 2026.10.82 (pre-release)

- **Household sync** opens on the household's TVs: this TV first, then the others with whether they're on now or when they were last on. A TV asking to join shows there too (answered in the notification Bell). Choosing another TV opens a card with **Remove from household**. A TV not in a household lists the found household's TVs above **Join**.
- **Settings > Family** shows how the household stands beside Household sync: how many TVs, Off, Not set up, or Household found.

## 2026.10.81 (pre-release)

- **Uninstall Hearth** moved from Kids profiles to the end of **Settings > System**, since it takes Hearth off the whole TV (still taking it off the kids profiles first). The Kids profiles page now only talks about removing Hearth from them.
- Wording: "adult" instead of "grown-up" throughout; "parent" only for parental controls.

## 2026.10.80 (pre-release)

- Settings has a new **Family** group, right after Profiles, for what's the whole TV's: **Parent PIN** (first, as the rest leans on it), **Kids profiles**, **Profile Pairing** and **Household sync**. **Profiles** keeps only the profile on now: Switch profile, **Lock now**, **Lock when the TV wakes**, **Unlock from my phone** (was "Approve switches from my phone") and Streaming app PINs.
- Switching to an adult's profile: Hearth's "Hi" card covers Google TV's home while Hearth checks whose profile came on, instead of Google's home showing for a moment or two. As before, never while "Use Google TV's home" is on, and never over Google TV's chooser or PIN screen.

## 2026.10.79 (pre-release)

- Household sync: a join request that came while a kids profile was on now shows up, and pops up, as soon as an adult's profile comes on. Before, it stayed hidden until the next request.
- Household sync: the page shows "Looking for your other TVs…" for a few seconds before offering to start a household, so Start isn't offered while a household is still being found.
- The joining TV says "an adult's profile" instead of "a grown-up's profile".

## 2026.10.78 (pre-release)

- Household sync: a TV asking to join shows up in the **notification Bell** of the TV it asked, on grown-ups' profiles only, and pops up: its name, with **Allow** and **Don't allow**. No Parent PIN, no code to compare, no phone. The joining TV says which TV to allow it on and waits up to five minutes.
- Notifications: the Bell shows each app's real name (system apps no longer show as a package name like com.google.android...), reads the title and text of every notification style, and a tap goes where the app told Google TV it should, opening the app when the notification can't. A notification whose buttons change is updated, so a button pressed is the one shown. Newest first.

## 2026.10.77 (pre-release)

- Household sync is now the one way to keep TVs alike: the **Copy profiles to / from another TV** screens are gone, and so is typing another TV's address. Settings > Profiles opens **Household sync** directly. A new TV chooses Join the household, shows a code, and a parent allows it on their phone or on another TV's Household page.
- Household sync: kids profiles' looks, layouts and wallpapers sync too, like everyone else's.
- Profile Pairing no longer lists the spare user Android keeps ready for the next new profile (it showed as "Profile 13" or similar).
- About Hearth shows this TV's name.

## 2026.10.76 (pre-release)

- Household sync: a backup is kept in Backup & Restore before a profile first takes the household's look, layout or wallpaper on a TV, as a copy does.

## 2026.10.75 (pre-release)

- Household sync, version 2: each TV has its own key, kept in the Android Keystore, and the household is a list of its TVs that syncs like everything else. Two TVs sync only when each signs the exchange with a key on the other's list. Copying profiles with "Add this TV to my household" now hands the new TV a one-time invitation, good for an hour, instead of the household's key.
- Household sync: each other TV on the Household page has **Remove**, after the Parent PIN. A removed TV stops syncing with the rest at once, without a new key for the others, and is told it was removed the next time it tries. Leaving works the same way: the TV removes itself and hands that to the next TV it meets.
- Household sync: **Join the household** now works from the new TV alone. It asks one of your other TVs, shows a six-digit code, and waits while a parent allows it on their phone (with phone approval on) or on that TV's Household page. The code on the phone has to match the one on the screen. The household's Home Assistant settings come along when the new TV has none. The setup step's Join does the same.
- Household sync: each profile's **look, home layout and wallpaper pictures** now follow it to every TV in the household. A TV fits the household's layout to the apps it has, and keeps the household's apps it doesn't have, so they aren't lost for the other TVs. Only pictures someone picked move between TVs; Bing's photo of the day is a setting, and each TV downloads it.
- Household sync: a household from 2026.10.68 to 2026.10.74 converts on its own when its TVs update, keeping who is who.

## 2026.10.74 (pre-release)

- Household sync: a TV in no household now shows when your other TVs already have one, names them, and offers **Join the household** (the copy screen that takes the household's key from one of them), with starting a separate household as the second choice. The setup flow's "Sync with your other TVs" step does the same, so a later TV no longer starts a second household by mistake.
- Household sync: the Household page lists the **TVs in this household**: this TV, the ones on now, and when each of the others was last on. Each TV announces its name and writes an entry about itself that syncs, so every TV learns of the others even if they were never on together; a TV that leaves takes its entry away.

## 2026.10.73 (pre-release)

- **Update automatically** now updates Hearth itself too: it checks daily and installs a newer Hearth, without asking, while the TV's screen is off. Only the main user's Hearth does it.

## 2026.10.72 (pre-release)

- Google's ad sandbox: **Keep it off** no longer asks for the Parent PIN; only turning the sandbox back on does.
- Setup flow: when debugging is on, a step after the kids profiles shows the ad sandbox commands and turns it off with one press.

## 2026.10.71 (pre-release)

- Settings > System > **Google's ad sandbox**: **Keep it off** turns off Android's Privacy Sandbox (ad topics, on-device ad auctions and ad measurement, with on-device personalization and federated learning) for the TV's main user, and keeps it off: Hearth checks each time the TV wakes and turns off any part that came back on. It shows the commands first, asks for the Parent PIN if there is one, and turning it off again turns back on exactly what Hearth turned off.

## 2026.10.70 (pre-release)

- Remote buttons: **YouTube button opens HearthTube**, an opt-in switch shown when HearthTube is installed. The remote's YouTube button (Button 3 on Google TV remotes) then opens HearthTube instead of YouTube, in every profile. No button press is needed to set it up.

## 2026.10.69 (pre-release)

- Setup flow: a "Sync with your other TVs" step after the family steps starts a household on this TV (skipped on a TV already in one). Other TVs are added from their Copy screens.
- The Parent PIN prompt can be allowed from a parent's phone: with Home Assistant set up and **Approve switches from my phone** on, the phones of the adults who have it on get an Allow/Deny notification when a kids profile (or anything only a parent may do) asks for the Parent PIN. Typing the PIN still works.

## 2026.10.68 (pre-release)

- After a parent gives a kid more time, Hearth now takes over Google TV's home once the time-up lock clears (it used to stay on Google TV's home until the next profile or Home press).
- Kids profiles no longer list the Play Store: apps added there aren't on Google TV's approved list for the kid and get removed at the next update or restart. Parents add apps in Google TV's Manage apps; the user guide says how.
- Copy profiles between TVs: Streaming app PINs and Home Assistant settings can be ticked as soon as the screen opens (they said "Nothing to send" until a profile was ticked).
- Copy profiles between TVs ignores the spare user Android keeps ready for the next profile; it is no longer offered as a profile to send or to receive into.
- Household sync (first part): TVs can be put in a household, and then keep Profile Pairing choices and saved PINs in step over the home network, encrypted with a key only the household has. People are told apart by their Google account, not their name, so two profiles with the same name never mix. Settings > Profiles > Copy profiles between TVs > Household sync has the one switch; a TV joins by a copy with **Add this TV to my household** ticked. Not yet: the setup-flow step, Parent PIN and look-and-layout sync, Continue Watching, and the Home Assistant mailbox.
- Security: the Home Assistant token is kept encrypted with a key held by the TV's secure hardware, and the Parent PIN is kept as a salted slow hash instead of a plain one. Both are converted the first time they are used; nothing needs to be entered again. (A TV that receives a copied Parent PIN from a TV that has not updated yet still accepts it.)

## 2026.10.67 (pre-release)

- Set up from your phone (Home Assistant): the page now offers to set up TV status for you when you send an administrator's token, and says when it is done. The webhook ID field moved under "I already have a webhook ID".
- Hearth is English only: the 13 machine translations and the Settings > System > Language page are gone (an old language choice in a backup is ignored).

## 2026.10.66 (pre-release)

- TV status: **Create it in Home Assistant for me** (Settings > Home Assistant > TV status, and in the setup flow) makes the helpers and the automation for this TV in Home Assistant, with a new random webhook ID, and turns reporting on. It needs an administrator's token. The Home Assistant side of a TV's status is no longer a manual job.
- Wrong PINs on a PIN pad lock it for 30 seconds after five misses in a row, doubling each time up to five minutes. Hearth checks the certificate's host name when it talks to Home Assistant over https. A kids profile can't be given a Google TV PIN.

## 2026.10.65 (pre-release)

- Copy profiles between TVs on a new TV: with one grown-up profile on each TV, the copy goes onto it whatever the names (kids profiles still need the same name), and streaming PINs are only saved where a parent PIN guards them, this TV's or the one coming with the copy.

## 2026.10.64 (pre-release)

- Copy profiles between TVs can now also send wallpaper pictures (on by default), streaming app PINs, the Home Assistant settings and the parent PIN (each off until the sending parent chooses it, after the parent PIN; the receiving TV chooses again and asks for its own parent PIN). A PIN goes only to a profile paired with that streaming profile and never over one that works; Home Assistant gets a new token made by the sending TV for the other, not a copy of its own; the status webhook id isn't sent. Both TVs need this version.

- Approve switches from my phone: the request also shows as a Home Assistant notification, so someone who opens Home Assistant sees it, and tapping the push no longer opens Home Assistant and dismisses it (use Allow or Deny). A volume, power, media or held key no longer withdraws a request as if someone were typing the PIN.

## 2026.10.63 (pre-release)

- Copy profiles between TVs works on a TV that has no parent PIN yet (a new TV has none): it asks for the PIN only where one is set. 2026.10.62 refused with "Set a parent PIN first".

## 2026.10.62 (pre-release)

- Copy profiles between TVs (Settings > Profiles): a parent at two TVs copies a profile's look, home layout and Profile Pairing choices from one to the other over the home network. Both TVs show the same six digits and a parent says on each that they match before anything is sent. The receiving TV chooses where each profile goes, fits the layout to the apps it has, keeps a backup first (in Backup & Restore) and keeps pairing choices it already has. Streaming PINs, Home Assistant settings, the parent PIN and wallpaper pictures are not copied. Needs trying on two TVs.
- The Home button now turns off "Use Google TV's home" when it opens Hearth, so Hearth takes over after profile switches again.
- Hearth takes over the home after a profile pick even within two minutes of another profile's Google setup screens, and logs why it leaves Google TV's home in front when it does.
- The debugging prompt (to add Hearth to kids profiles) opens Developer options when they are on and only USB debugging is off, instead of telling you to unlock them again.
- Setting up Home Assistant from a phone seals the address, token and webhook id on their way to the TV, as the PIN page does. It needs a recent phone browser, opened from the QR code.
- Continue Watching is on by default (the row still waits for Watch Next access).

## 2026.10.61 (pre-release)

- Hearth on a kids profile no longer gets Hearth's adb key. Hearth in your own profile now re-checks the kids' copies once a day (keeps them from being removed, and lets them read Watch Next and the calendars), and tells a copy that still has the key to delete it; a copy does that the next time its profile starts. If Hearth is ever uninstalled without Settings > Profiles > Remove, the kids' copies stay: docs/development.md says how to release them.

## 2026.10.60 (pre-release)

- Waking the TV can open Google TV's profile chooser instead of the PIN screen: Settings > Profiles > Choose a profile when the TV wakes (every time, or after some minutes asleep). A profile with a PIN asks for it before it opens. It is off until you turn it on, and kids profiles are left alone.
- Disney+: a profile with a PIN is picked and its PIN screen is no longer taken for the profile picker, so the PIN can be typed.
- The Home Assistant panel draws no list of who is where for a map card; a person's tile shows the map when it is focused.
- The log says when Home Assistant took a phone-approval request.

## 2026.10.59 (pre-release)

- **Hearth now needs Android 9 or newer.** A TV on an older Android won't be offered this update.
- Hearth's link to Home Assistant (its notifications and the TV's status) keeps running when Android switches Home Button Fix off, for instance after an update. The pop-up itself still needs Home Button Fix: while it is off, Hearth tells Home Assistant it can't show one. Nothing new to set up.
- Hearth puts itself back on a kids profile by itself even when the TV's USB debugging switch reads off, as long as the TV still trusts Hearth.
- Failures that used to pass silently are now written to the log (never a name or a PIN), so a feature that quietly stays off can be traced.
- A call between Hearth's screens and the TV that failed could leave a setting waiting for good; it now ends with an error instead.

## 2026.10.58 (pre-release)

- Home Assistant's setup asks whether HearthTube may share the title and channel of what's playing (Settings > Home Assistant can change it later).
- Include pre-releases (Settings > Check for Updates) starts on in a pre-release build and off in a release build.
- The home's dock, frosted glass and background are Hearth's own and lighter on the TV; the connection indicator reads the network through a smaller, newer reader.
- "Adult" instead of "grown-up" throughout; the docs are up to date and sorted by who reads them.

## 2026.10.57 (pre-release)

- Approve switches from your phone (Settings > Profiles, in your own profile; needs Home Assistant and its phone app): when Google TV asks for your PIN to open your profile, your phone gets Allow and Deny, and Allow has Hearth enter your Google TV PIN. Typing the PIN with the remote always works too; a key pressed on the PIN screen withdraws the phone's request. Your Google TV PIN can be saved there or on the phone page.
- Shared streaming apps close on a switch between grown-ups even when the TV's USB debugging switch has turned itself off.

## 2026.10.56 (pre-release)

- Disney+: profiles with a PIN are found and picked too (Disney+ labels them differently).
- Streaming app PINs can be set from a phone: Settings > Profiles > Streaming app PINs > Set up PINs on your phone shows a QR code; the PINs typed on the phone are encrypted there, with a one-time key from the QR code, before they reach the TV.
- Remote keys respond faster: Hearth does less on the thread every remote key waits for (app images, Continue Watching, reading Google TV's profile chooser), and asks for focus and scroll events only while Google TV's own screens are up.
- Logs name nobody in Hearth's Flutter part either.

## 2026.10.55 (pre-release)

- Streaming app PINs belong to the Google TV profile that saved them: another profile paired with the same app profile no longer gets that PIN typed. In a grown-up's profile, Hearth types it only when that profile has its own Google TV PIN. Saved PINs move to the profiles paired with them; the app asks for its PIN until the Google TV PIN is on.
- After two PINs in a row that the app doesn't take, Hearth stops typing it until it's saved again. Changing a pairing that has a PIN needs the parent PIN and removes that PIN.
- Settings > Profiles > Streaming app PINs has one switch that turns PIN typing off, and lists the last 20 entries (app, time, outcome; never a name or a PIN). Before the first PIN is saved, a parent reads what Hearth will do, including that the services' terms may not allow it.
- Hearth doesn't type PINs in an app version listed in its repository as one its recipes don't handle (checked at most twice a day while a PIN is saved).
- Hearth and its helpers in the kids' profiles prove to each other that they share a key, without sending it; no other app on the TV can pose as either.
- Profile Pairing listens only to the app it's handling; its research mode ends by itself after 30 minutes. Logs show a stand-in instead of each person's name.

## 2026.10.54 (pre-release)

- Profile button: the remote's profile button opens the profile chooser straight away, and holding it locks your profile (Google TV's PIN screen). Where there's nothing to lock (no Google TV PIN), a hold opens the chooser. It's set up once in Settings > Remote buttons, where it can be changed or restored to Google TV's own. Kids' profiles keep Google TV's own handling.
- Profile switches: switching to a kid's profile shows the welcome card and gives Google TV its moment for bedtime, also when coming from a grown-up's profile. A switch between grown-ups isn't taken as cancelled while Google TV is still catching up. Hearth comes back when one of Google TV's screens (such as its PIN screen) closes onto Google's home, and when Home is pressed there. The volume bar, the keyboard and other pop-ups no longer stop Hearth from coming back. Fewer lost remote presses right after switching to a kid's profile.

## 2026.10.53 (pre-release)

- Security: Hearth's helper in a profile only opens other apps' public screens, never Hearth's own, and passes on no access to Hearth's files. Reading Netflix's and Apple TV's profile and PIN screens and tidying the Home Assistant address can no longer be slowed down by unusual text. The CI workflow only reads the repository.

## 2026.10.52 (pre-release)

- Paramount+ content PIN: save it once in Settings > Profiles > Streaming app PINs, and Hearth types it (behind its cover card) when a title asks for it, only in a grown-up's profile that has its own Google TV profile PIN. Kids' profiles and unlocked profiles keep Paramount+'s own prompt. A wrong PIN is reported, not retried.

## 2026.10.51 (pre-release)

- Weather: the forecast opens on a summary, today's in the day and tonight's from 5 PM (the sky, the high and low or tonight's low, the chance of rain or snow, now or tomorrow's high). OK goes on to the next hours, the next days and back.
- Calendar: without calendar access the date and time can still be selected, and OK asks for access.

## 2026.10.50 (pre-release)

- Home Assistant panel: selecting a person shows where they are on a small map, with home marked. The map is drawn from map pieces of the area around home, fetched once and kept on the TV, so the map service never learns where anyone is; someone farther away (or without a position) shows their status as before.

## 2026.10.49 (pre-release)

- YouTube time per day applies to kids' profiles only: a grown-up's profile is never limited or locked (a limit set on a grown-up's profile by an older Hearth is ignored). Each kid's is set on their page in Settings > Profiles > Kids' profiles.

## 2026.10.48 (pre-release)

- Home Assistant panel: no "Open the full dashboard" row (the setting to show Home Assistant's own page instead stays). App icons in the screen time cards are kept on the TV for 30 days and show offline too.

## 2026.10.47 (pre-release)

- Fixed: after Hearth's "Hi, <name>" card on a switch to a kid's profile, Hearth now takes over instead of leaving Google TV's kids home up.

## 2026.10.46 (pre-release)

- Kids' bedtime and time-up screens show again when switching to a kid's profile: Hearth gives Google TV's kids home the 3 seconds it needs (measured on the TV) and shows its own "Hi, <name>" card over it meanwhile.
- Home Assistant panel: app icons (pictures) in text cards and entity pictures on tiles; when a card the selection is on goes away (a player stops), the selection moves to the next one down.

## 2026.10.45 (pre-release)

- Profile photos: any profile without a PIN is photographed from Google TV's chooser when its tile is selected for a moment (the kids' photos fill in).

## 2026.10.44 (pre-release)

- The Home Assistant panel is now drawn by Hearth from your dashboard, so everything in it works with the remote: thermostats (− / + and modes), players (play/pause, skip, volume), lights (on/off, brightness), scenes, sensors, cards that show only when something is on, text cards with headings and icons, and where everyone is. Cards Hearth can't draw are left out; "Open the full dashboard" at the bottom shows Home Assistant's own page, and a setting can make that the default.

## 2026.10.43 (pre-release)

- Calendar: the date and time now show the TV's own Google calendars (each profile its own account's, kids' profiles included), with no Home Assistant needed. Choose calendars in Settings > Home screen > Status bar > Calendars. Needs calendar access (read only, stays on the TV).
- Data usage: select the data pill to see which apps used the TV's data (today, this week or this month with OK), the connection, and VPN; the pill says "No internet" when the TV is offline. On Ethernet, Android doesn't count data per app.
- Kids' profile photos are picked up on any visit to Google TV's profile chooser, not only a slow one.
- Continue Watching: an app that bounces straight back to Hearth (Paramount+ when already running) is opened again, unless a button was pressed.

## 2026.10.42 (pre-release)

- The selection lands where it should with the dock on or off: on the first app at the top (not an empty section) without the dock; after removing or hiding the selected app; after closing search results; when switching the dock in Settings (the selection stays in Settings); and moving the first app keeps the page at the top.

## 2026.10.41 (pre-release)

- The top bar's pills (profile name, data, weather, date and time) share one look: the same height and darkness. The weather pill shows just the current conditions (warnings like "Rain tomorrow" are off by default, under Status bar settings).
- Settings: Applications is now under Home screen.

## 2026.10.40 (pre-release)

- Fixed: switching to a grown-up's profile could leave Google TV's home up (after an account check, Hearth took a tab on Google TV's home for a new profile).

## 2026.10.39 (pre-release)

- Home Assistant settings: a text field only becomes editable after pressing OK on it, so moving through the page never opens the keyboard.

## 2026.10.38 (pre-release)

- Calendar: with Home Assistant set up, the date and time in the top bar show the rest of today's events when selected, and OK shows the next 7 days. Settings > Home Assistant > Calendars picks which calendars each profile shows. Without Home Assistant nothing changes.

## 2026.10.37 (pre-release)

- After switching to a grown-up's profile with its PIN, Hearth comes back instead of leaving Google TV's home up.
- Grown-ups aren't asked for the parent PIN while they're using the remote; it's asked again after five minutes without a button press. Kids' profiles always ask.
- Streaming apps shared by the grown-ups ask who's watching after a profile switch, so Profile Pairing picks the right app profile (Netflix opened in the last person's profile).
- Disney+ profiles with a PIN are recognized, so they can be matched and chosen in Profile Pairing.
- Continue Watching: an entry belongs to the profile that last had the app, even if another profile played it earlier.

## 2026.10.36 (pre-release)

- Kids' bedtime and time-up screens show again: Hearth gives Google TV's kids home a moment before covering it every time (it had stopped once the kid's apps looked unblocked, which kept Google from ever blocking them).
- Continue Watching in kids' profiles shows what the kid watched (Hearth's copy there couldn't read the list). Grown-ups' entries are no longer cut to the newest 20 before Hearth knows whose they are.
- An episode no longer shows twice in Continue Watching when the app names show and episode together.
- Home Assistant panel: each profile can pick its own dashboard and view from Home Assistant's list.

## 2026.10.35 (pre-release)

- Home while browsing the apps goes back to the dock, or to the first app at the top when the dock is off (it also ends a search). With the dock off, a profile switch now lands on the first app too.
- The Home Assistant panel opens at once: its dashboard loads in the background when the panel is on and stays loaded while it's closed (it's let go if Android runs short of memory).

## 2026.10.34 (pre-release)

- The remote's profile button opens Google TV's profile chooser again (Hearth was covering it with its home).
- Switching between grown-ups' profiles no longer falls back to the last profile when Google TV's home is slow to say who's logged in.
- After a profile switch that Google TV cancels, the selection goes back to the dock (or the first row without a dock), not the top bar.

## 2026.10.33 (pre-release)

- Kids' profiles: Hearth (and HearthTube, when it's installed) goes on every kids' profile from the setup flow, and new kids' profiles get it automatically. Settings → Profiles shows each kid as Ready or Needs a fix with one Fix button, and a page per kid with how Hearth stands there, HearthTube, and its YouTube time per day, set without switching profiles. HearthTube can be added to a kid from that page, even from inside the kid's profile.
- Streaming app PINs (Settings → Profiles): each profile sets its own, kids' profiles included (behind the parent PIN), without pairing by hand first.
- Pushing Hearth into grown-ups' profiles is gone (they share the TV's main user).

## 2026.10.32 (pre-release)

- With HearthTube installed, kids profiles watch YouTube only in HearthTube (where their YouTube time applies): YouTube's own app is hidden, and opening it anyway opens HearthTube. Grown-ups' profiles start with YouTube hidden too.

## 2026.10.31 (pre-release)

- Dismissing one notification no longer dismisses all of that app's notifications (Android's group summary no longer shows as a notification of its own).
- The weather shows in the top bar by default (once there's weather to show).

## 2026.10.30 (pre-release)

- After entering the PIN on Google TV's profile lock (when the TV wakes, or Lock Profile), Hearth comes back about a second sooner.

## 2026.10.29 (pre-release)

- YouTube allowance: no play time lost when a kids profile's helper is briefly disconnected; a Home Assistant lock (bedtime, school time) keeps Hearth's own minutes as Hearth's, with Home Assistant's message; Home Assistant can give its per-profile limits as the entity's state.
- Home Assistant status: usage goes out every 2 minutes while watching (changes still go out at once).

## 2026.10.28 (pre-release)

- YouTube time per day (Settings → Profiles; in a kids profile past the parent PIN): how long HearthTube may play a day for that profile. Hearth counts it on the TV; Home Assistant, if you use it, can add a limit shared with the family's other devices (the stricter wins). HearthTube enforces it once it has its matching update.
- Hearth keeps today's app and playing time per profile, and with Home Assistant set up sends it with the TV's status, along with when screen time came up or cleared.

## 2026.10.27 (pre-release)

- Continue Watching per profile, from Hearth's own history: what each profile plays is recorded on the TV (title, episode, how far it got), so its entries are its own, shows from apps that don't fill Google TV's Continue Watching list (Hulu, Paramount+) appear too, and an entry an app dropped when someone else used it (Netflix keeps only its current profile's) stays until that profile opens the app again.

## 2026.10.26 (pre-release)

- Grown-ups' profiles that share the TV's main user (Google accounts added in Google TV's chooser) are profiles of their own in Hearth: switching to one brings its own home, look, dock, name and photo, and its own Continue Watching (whatever was watched while it was on). Hearth knows whose profile is on from Google TV's home, which says who's logged in. The first switch to a new one waits about 15 seconds on Google TV's home.
- Weather forecast: the headings say Hourly and Daily.

## 2026.10.25 (pre-release)

- Weather forecast: with the top bar's weather selected, the coming hours show over the home; OK swaps them for the next five days.

## 2026.10.24 (pre-release)

- The Home button closes Settings, side panels, dialogs and the Home Assistant panel.
- One temperature unit for the whole TV, starting from its region's (Fahrenheit in the US).

## 2026.10.23 (pre-release)

- Groundwork for grown-up profiles that share the TV's main user: Hearth notes Google TV's profile switches in its log.

## 2026.10.22 (pre-release)

- Holding the profile button locks the profile again: Google TV's Verify it's you screen stays up, instead of the chooser opening over it.
- Letting go after holding OK no longer also counts as a press.

## 2026.10.21 (pre-release)

- Setup cards show each item with a check or an open circle for how it stands, and say Next, Leave it as it is / Set up what's missing, or Not now / Turn on.
- Google TV's spare, never-used profile no longer shows up as another adult's profile, and Hearth isn't put on it.
- The temperature is in Fahrenheit on TVs in the US (and the few other places that use it) until a unit is picked.

## 2026.10.20 (pre-release)

- Holding OK on an app always opens its menu; the held key no longer goes on to open Add to section.

## 2026.10.19 (pre-release)

- Blocking an app with Family Link (and unblocking it) no longer removes it from a kids' profile's dock and sections.

## 2026.10.18 (pre-release)

- First-run setup: a guided flow on a new TV (the Home button, the home app, then family, watching, a look for the home, smart home, TV & power and updates), Set up Hearth in Settings, and a chip on the home for anything left. TVs already set up aren't taken over.
- Four looks to start from: Hearth, Photo of the day, Calm dark and Bold.
- The phone setup page also takes a Home Assistant webhook ID for TV status.
- Start on boot is on unless it was turned off.

## 2026.10.17 (pre-release)

- "Use Google TV's home" in TV & power: a switch that leaves Google TV's own home in front until it's turned off. It replaces "Use Google TV for now" in System.

## 2026.10.16 (pre-release)

- A profile name Hearth got wrong after a failed switch corrects itself.

## 2026.10.15 (pre-release)

- Profile switching works normally again while a newly added profile can't start, and a wrong profile name corrects itself.

## 2026.10.14 (pre-release)

- Notifications can be opened, and their buttons pressed, from Hearth's notifications panel.
- A newly added Google TV profile can be switched to more reliably.
- Only HearthTube signed with Hearth's release key gets parent PIN checks.

## 2026.10.13 (pre-release)

- A newly added Google TV profile can be switched to: Hearth waits while Google TV sets it up.
- The fade behind Continue Watching and search reaches both edges of the screen.

## 2026.10.12 (pre-release)

- Continue Watching shows "See all" only once it has three programs.

## 2026.10.11 (pre-release)

- Settings, Inputs, Notifications and the Home Assistant panel no longer darken the home screen behind them.
- "Lock my profile" is now "Lock Profile".

## 2026.10.10 (pre-release)

**New signing key** (CN=Hearth). Builds up to 2026.10.09 were signed with the key inherited from the
project Hearth started from, so they can't update to this one: uninstall the old Hearth first.

## 2026.10.09 (pre-release)

**New app id.** Hearth is now `com.thesiegs.hearth` (it was `com.leanbitlab.ltvL`, inherited from LTvLauncher).
It installs as a new app: back up with the old Hearth (Settings → System → Backup & Restore), install this one,
restore, and uninstall the old one. See [docs/design/app-id-change.md](docs/design/app-id-change.md).

**Google TV profiles**
- Hearth knows the active profile from Google TV itself, with each profile's photo in the top bar, its own home
  layout, wallpaper and Continue Watching.
- Profile Pairing picks your profile in Netflix, Disney+, Apple TV, HBO Max and Paramount+, also in other
  profiles, and can type a saved profile PIN for you (Netflix, Disney+, Apple TV and HBO Max).
- Lock my profile, using Google TV's own profile lock: from Settings, by holding the profile button, from a remote
  button, or when the TV sleeps.

**Kids and families**
- Hearth on other profiles: puts Hearth and HearthTube on kids' and other adults' profiles and keeps them installed;
  Uninstall Hearth cleans them up first.
- Hearth stays out of the way of Google TV's bedtime and screen time screens.
- Kids see their own settings plus one "Parent settings" row; only risky settings ask for the parent PIN.

**Home screen**
- Search, in Continue Watching's spot: results show where to watch now and open in the app; adult titles never show.
- Row titles on a pill that darkens with the wallpaper; a dark fade behind details in Continue Watching and search.
- Each profile has its own wallpaper pictures; Bing's photo of the day updates the day it comes out; HearthTube can
  show Hearth's wallpaper.
- Many focus and navigation fixes: something is always selected, Left on a sub page goes back, the dock and
  Favorites keep the selection.

**Remote and TV**
- Remote buttons: press and hold actions, Home Assistant scenes and scripts, "Ask Google", lock my profile; remaps
  can apply only on Hearth's home screen.
- Hearth keeps HearthTube up to date.
- Include pre-releases (Settings → System → Updates, on by default): Hearth and HearthTube updates include early
  test builds. Every release is a pre-release while Hearth is in early development.
- Settings regrouped into eight sections.

**Home Assistant**
- The status webhook adds `profile_id`, a stable key for the profile, and kids screen time details.
- Pop-ups with live cameras and action buttons; phone setup by QR code.

**Everything else**
- Translated into 13 languages besides English.
- About shows the wallpaper photo's credit and the TMDB notice.

## 2026.10.05

The first Hearth release.

- New name, icon and banner.
- Favorites dock: a frosted bar along the bottom of a wallpaper-first home screen. Up brings in Continue Watching;
  Down brings the dock back.
- Continue Watching shows cover art again. Below the dock, apps wrap as a grid over a blurred wallpaper.
- Left at the left edge opens Settings; Right closes it. New Appearance settings for the dock.
- Persistent notifications can be dismissed. Updates pick the right APK for the device.

## Before Hearth

Hearth started from [LTvLauncher](https://github.com/leanbitlab-org/LtvLauncher), which descends from
[FLauncher](https://gitlab.com/flauncher/flauncher). Their history is in this repository's git log.
