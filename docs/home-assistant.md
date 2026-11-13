# Home Assistant

> **Draft.** Hearth TV is in early development and this document is a draft: features, settings and
> setup steps may change or be incomplete.

Hearth TV talks to Home Assistant these ways, each optional:

| | Direction | Needs |
|---|---|---|
| [Notifications](#notifications) | Home Assistant → TV | Its switch on, and Home Button Fix on |
| [Dashboard panel](#dashboard-panel) | TV shows Home Assistant | Address and an access token |
| [Hearth integration](#hearth-integration) | TV ↔ Home Assistant | The integration in Home Assistant, and pairing |
| [TV status](#tv-status) | TV → Home Assistant | The Hearth integration, paired |
| [Approve switches from a phone](#approve-switches-from-a-phone) | TV → a phone → TV | Address, token, and the companion app on the phone |

Everything stays on your home network: Hearth TV talks only to the address you give it, and accepts notifications
only from local addresses.

**Set up from your phone.** Typing a long access token with a remote is no fun. **Set up from your phone** shows a
QR code; it opens a one-time page served by the TV where you paste the address and token. The page only works while
the QR code is on screen. The page seals what it sends with a key that's only in the QR code's link (after the `#`,
which a browser never sends over the network), so the token can't be read on your network; it needs a recent phone
browser, opened from the QR code.


## Notifications

Pop-ups over any app: the doorbell, a finished wash, a reminder. Hearth TV speaks the protocol of the
"Notifications for Android TV / Fire TV" integration (PiPup style) on port **7676**.

Hearth TV's link to Home Assistant (this and the TV status below) keeps running even if Android switches Home Button Fix off,
for instance after an update. The pop-up itself is drawn by Home Button Fix, so while it is off Hearth TV answers
Home Assistant that it can't show one.

1. On the TV, turn on **Settings → Home Assistant → Notifications → Show Home Assistant notifications** (off until
   you do). In Home Assistant, add the **Notifications for Android TV / Fire TV** integration with the TV's IP
   address (the same page shows it).
2. Send a notification from an automation:

   ```yaml
   action: notify.tv
   data:
     title: Doorbell
     message: Someone is at the front door
     data:
       duration: 20
       position: center
   ```

These options work: `duration` (1–120 s), `position`, `bkgcolor`, an icon and an image. `fontsize`, `transparency`
and `interrupt` are accepted and ignored.

### Cameras and buttons

Hearth TV also takes two fields of its own, sent with a `rest_command`:

- `camera`: a camera entity shown live in the pop-up;
- `actions`: up to three buttons, each `{"title", "service", "data"}`, run with the dashboard panel's token.

```yaml
rest_command:
  tv_doorbell:
    url: "http://192.0.2.10:7676/"
    method: post
    content_type: "application/x-www-form-urlencoded"
    payload: >-
      title=Doorbell&msg=Someone%20is%20at%20the%20door&duration=30&camera=camera.front_door&actions={{
      [{"title": "Unlock", "service": "lock.unlock", "data": {"entity_id": "lock.front_door"}}]
      | to_json | urlencode }}
```

Buttons need the [dashboard panel](#dashboard-panel)'s token, since Hearth TV calls the service as that user. A button
whose `data` isn't an object is left out. The buttons are in the Bell too, on every TV of the household (below).

### In the Bell, and for one person

Every notification with a title or message also goes in the TV's notification Bell (it needs Notification access), and
with household sync on, in the Bell of every TV of the household; clearing it on one TV clears it on all. The Bell
keeps the title, the message and the buttons; the camera stays in the pop-up of the TV it was sent to. A button
pressed on any TV (in its Bell or pop-up) runs once and the notification goes from every Bell: a TV with its own Home
Assistant connection calls the service itself, any other asks the TV the notification was sent to, which calls it with
its token. That TV runs only a button of its own copy, by its number, and only if it hears of the press within two
minutes (an "Unlock" must not happen long after); later, the notification is only cleared. Buttons whose data is over
1,000 characters stay in that TV's pop-up only. A notification leaves the Bell after three days (on a TV not in a
household, or with sync off, also when Hearth TV restarts).

A notification is for every adult unless it says who it's for. Two more fields of Hearth TV's own, sent with a
`rest_command` as above:

- `for`: who it's for. Use one that means the same person on every TV:
  - the profile's **ref**, `name:` and its Google TV name in lower case with dashes (`name:alex`, `name:sam-rivera`),
    as the [Hearth integration](#hearth-integration) maps profiles;
  - a **person** in Home Assistant (`person.alex`): the TV finds the profile the Hearth integration maps to that person
    (on a paired TV; it learns the mapping with each status answer);
  - the profile's name as the TV shows it (`Alex`), or its Google account address.

  It shows only in that person's Bell, on every TV, and pops up only when their profile is on screen. A name, ref or
  person that two profiles of different people share is no one's; a `for` that is no profile on the TV gets a 404 and
  is shown to no one. A kids profile can be named too; otherwise kids' profiles see none of these.

  A profile id such as `user:10` still works, but only as **that TV's own** profile 10. Each TV numbers its profiles
  itself: user 10 on one TV can be Alex and on the next TV Sam. So never send the same `user:10` to several TVs; use
  the ref or the person. (`<device id>/user:10`, as the integration's options write it, is that TV's alone; another
  TV takes it as no one.)
- `tag`: names the notification. A later one with the same tag (and the same `for`) replaces it, and the message
  `clear_notification` with its tag clears it from every Bell. Without a tag, the same notification sent to several
  TVs at once is still one notification.

```yaml
rest_command:
  tv_parcel_for_alex:
    url: "http://192.0.2.10:7676/"
    method: post
    content_type: "application/x-www-form-urlencoded"
    payload: "title=Parcel&msg=Your%20parcel%20came&for=person.alex&tag=parcel"
  tv_homework_for_sam:
    url: "http://192.0.2.10:7676/"
    method: post
    content_type: "application/x-www-form-urlencoded"
    payload: "title=Homework&msg=Time%20to%20start%20your%20homework&for=name:sam&tag=homework"
  tv_parcel_clear:
    url: "http://192.0.2.10:7676/"
    method: post
    content_type: "application/x-www-form-urlencoded"
    payload: "msg=clear_notification&for=person.alex&tag=parcel"
```

Without `for` and `tag` a notification works as it always did: it pops up whichever profile is on.

## Dashboard panel

A Home Assistant dashboard one press away: **Right** at the right edge of the home opens it.

1. In Home Assistant, make a **non-admin user** for the TV, and log in as that user.
2. On its profile page, **Security** tab, create a **long-lived access token**.
3. In Hearth TV, enter the Home Assistant address and the token (or use **Set up from your phone**), and choose the
   dashboard (and which of its views) from the list Home Assistant gives.

Hearth TV draws the dashboard's cards itself, so every control is reachable with the remote: lights, switches, scenes,
covers, climate, media, cameras, and a person's whereabouts on a small map (drawn from map pieces fetched once and
kept on the TV, so the map service never learns where anyone is). It loads in the background once the home is up, so
the panel opens at once, and keeps app and entity pictures on the TV for 30 days. **Show the full dashboard instead**
shows Home Assistant's own page (the remote can't reach all of its controls).

The panel is on per Google TV profile, so kids profiles don't get it unless you turn it on there, and each profile can
have its own dashboard (**Dashboard for this profile**).

## Approve switches from a phone

With the dashboard panel's address and token set, an adult can have their phone approve a switch into their
PIN-locked Google TV profile (**Settings → Profiles → Unlock from my phone**, in their own profile; the row
is greyed out until Home Assistant is set up). They choose their phone, one of Home Assistant's `notify.mobile_app_…`
services, and save their Google TV PIN.

When Google TV's PIN screen comes up for that profile, Hearth TV:

1. listens on Home Assistant's WebSocket API for `mobile_app_notification_action` events, only while it waits (two
   minutes at most; one connection for every request that waits, made again if Home Assistant restarts meanwhile);
2. calls the phone's notify service with an actionable notification (Allow and Deny, a one-time action id, `tag`
   `hearth-approval-…`, high priority; tapping the notification itself does nothing and leaves it up, so only the
   buttons answer), and creates the same request as a Home Assistant notification (`persistent_notification.create`,
   id `hearth-approval-…`) so someone who opens Home Assistant sees it too;
3. on Allow, enters the saved Google TV PIN on Google's keypad, if that profile's PIN screen is still up; on Deny or
   no answer, leaves the PIN screen as it is. Either way both notifications are cleared when the request ends.

Typing the PIN with the remote always works: a digit, arrow, OK, Back or Delete pressed on the PIN screen withdraws the
request (volume, power and media keys, and a key held down, don't; the log line names the key and where it came from). A PIN Google
refuses isn't entered again until it's saved anew. **Send a test notification** checks the phone is reached.

### The Parent PIN, from a phone

The same switch and phone also let a parent allow the **Parent PIN** prompt (a kids profile opening Hearth TV's settings or an
app's menu, or an adult's profile changing something only a parent may) without typing the PIN. When that prompt opens,
Hearth TV sends an Allow/Deny notification (`tag` `hearth-parent-…`, action ids `HEARTH_PARENT_ALLOW_…` and
`HEARTH_PARENT_DENY_…`, a one-time id, two minutes) to the phone of **every adult profile that has approval on**; the
first answer decides. The notification names the profile and the TV. Allow closes the prompt as if the PIN had been entered
(an adult's profile also counts as "a parent is at the remote" for five minutes, like a typed PIN); Deny says so on the
prompt and leaves the PIN pad. The PIN pad always works, and closing the prompt withdraws the request from the phones.
Changing the Parent PIN itself, and the pads for new PINs, never use the phone. Needs no Google TV PIN saved.

## Hearth integration

Hearth TV pairs with Hearth's own integration for Home Assistant (`custom_components/hearth` in this repository; see
[home-assistant-integration.md](home-assistant-integration.md)). With it, the TV needs no token:

1. Install it (HACS custom repository, or copy the folder) and add it: Settings > Devices & services > Add
   integration > Hearth.
2. On the TV: **Settings > Home Assistant > Pair with Home Assistant**, enter Home Assistant's address, and choose
   **Pair**. The TV shows a 6-digit code.
3. In Home Assistant, Settings > Devices & services: under Discovered, open the TV, check it shows the same code, and
   confirm. The TV says it's paired.

Paired, the TV posts the [TV status](#tv-status) to the integration (with its own secret, made at pairing, which works
only on Hearth's endpoints), every 2 minutes at least. Pairing one TV of a household pairs its other TVs too. It also sends each app's Android category
(`app_categories`), for the integration's Video and Games. Each answer carries every profile's minutes left per group,
and the fewest left in a group holding HearthTube becomes the profile's YouTube allowance. **Unpair** forgets the pairing on the TV; deleting the TV's device in Home Assistant
removes it there (the TV unpairs itself once Home Assistant has refused its posts for about 10 minutes; a
restarting Home Assistant refuses them briefly).

## TV status

Paired with the Hearth integration, Hearth TV posts what the TV is doing there, when it changes (within a second or
two) and as a heartbeat; the integration turns it into each TV's device and entities. (An older way, posting to a
webhook automation, and reading `sensor.hearth_allowance`, is retired: pair the TV instead.) The status:

| Field | Value |
|---|---|
| `screen` | `on` or `off` |
| `state` | `playing`, `paused`, `idle` or `off` |
| `app`, `app_package` | the app in front |
| `media_app`, `media_title`, `media_artist`, `media_album`, `media_duration_s` | now playing, from any app's media session (needs notification access) |
| `media_position_s`, `media_position_at` | where playback is (seconds) and when that was read (epoch ms), from the same media session; Hearth works out the time left |
| `now_playing_available` | whether Hearth TV can see what's playing |
| `profile` | the Google TV profile's name |
| `profile_id` | a stable key for the profile on this TV (`user:<serial>`, or `user:<serial>:<account>` for another adult's account in the same user), unchanged by renames; the serial is this TV's own, so another TV has another key for the same profile |
| `profile_ref` | who the profile is across the household's TVs: `name:<slug>` of its Google TV name (`name:sam-lee`), the same on every TV; null until the TV has learned the name |
| `profiles` | every profile this TV knows, by its `profile_id`: `{"user:10": {"name": "…", "ref": "name:…", "kids": true}}` |
| `kids_profile` | `true` in a kids profile |
| `screen_time_up` | `true` while Google TV's bedtime or time's-up screen is showing |
| `google_time_up` | `true` while Google TV's own Kids daily limit holds the profile (its time up screen, not bedtime): Hearth TV can't lift it, only raising or turning off that limit in Google TV does |
| `screen_time_reason`, `screen_time_text`, `screen_time_minutes_left`, `screen_time_unlocks_at`, `screen_time_seen_at` | what that screen said |
| `screen_time_unlocks_at_iso` | the unlock time as the next such moment, in ISO 8601 with the TV's offset |
| `screen_time_event`, `screen_time_event_at` | `appeared` or `cleared`, and when (epoch ms): the last change, sent with every status until the next, so trigger on `screen_time_event_at` changing |
| `allowed_apps` | in a kids profile, the apps Family Link currently allows |
| `day` | the TV's local date (`YYYY-MM-DD`) the usage counts are for |
| `seconds_today`, `app_seconds_today`, `playing_seconds_today` | the active profile's usage today: seconds any app was in front with the screen on, seconds per app (package) in front, and seconds per app playing (media session). Hearth TV, Google TV's own screens and the screensaver don't count |
| `usage_today` | every profile's usage today: `{"<profile_id>": {"profile_name": "…", "profile_ref": "name:…", "seconds": n, "apps": {"<package>": n}, "playing": {"<package>": n}}}` |

The usage counts are cumulative for the day (a lost post loses nothing), kept across Hearth TV restarts, and start again
at local midnight.

**How often Hearth TV posts.** Within about 2 seconds of a change that matters (another app in front, play or pause, a
profile switch, the screen going on or off, screen time coming up or clearing); every 2 minutes while an app is in
front or playing, so the usage counts are never more than 2 minutes behind; otherwise every 10 minutes, so Home
Assistant can tell the TV is there. A status the same as the last one isn't sent again (the 10-minute one aside).

**HearthTube's titles.** HearthTube can put the playing video's title, channel and ID in its media session, so they
reach `media_title` and `media_artist` here. Hearth TV's Home Assistant setup asks whether to share them, and
**Settings → Home Assistant → Share what's playing in HearthTube** changes the answer later; HearthTube follows it.
Never asked, HearthTube shares (its own **Tell Home Assistant what's playing** switch, on by default).

**Where the playing time comes from.** HearthTube reports its own playing time, in every profile. Other apps' comes
from their media sessions, which Android only shows to a notification listener in the same Android user. In the TV's
main user that's Hearth TV itself (its notification access). A kids profile's apps play in that profile's own Android
user, so there it's Hearth TV's agent, which needs notification access granted in that user. A parent's **Fix**
(Settings → Family → Kids profiles) grants it over Hearth TV's own adb; by hand it's
`adb shell cmd notification allow_listener com.thesiegs.hearth/com.thesiegs.hearth.LauncherNotificationListenerService
<user id>`. Without it, that profile's `playing` lists HearthTube only (its `apps` time in front is counted either
way). In a kids profile the agent's notification access does nothing else: no pop-ups, nothing read but what's
playing. What plays (title, episode, how far it got) is kept on the TV for that kid's own watch history and
Continue Watching, and with household sync on it goes to the household's other TVs for that kid's row only; it isn't
sent to Home Assistant.

**Allowance for HearthTube.** Each answer from the integration carries every profile's minutes left; HearthTube gets
them through Hearth TV (see [provider-contract.md](provider-contract.md)). Without Home Assistant, Hearth TV's own
rules for each kid do the same (Settings → Family → Kids profiles → the kid → Screen time).
