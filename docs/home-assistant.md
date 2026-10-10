# Home Assistant

> **Draft.** Hearth is in early development and this document is a draft: features, settings and
> setup steps may change or be incomplete.

Hearth talks to Home Assistant three ways, each set up in **Settings → Home Assistant** and each optional:

| | Direction | Needs |
|---|---|---|
| [Notifications](#notifications) | Home Assistant → TV | Home Button Fix on |
| [Dashboard panel](#dashboard-panel) | TV shows Home Assistant | Address and an access token |
| [TV status](#tv-status) | TV → Home Assistant | Address and a webhook ID |

Everything stays on your home network: Hearth talks only to the address you give it, and accepts notifications
only from local addresses.

**Set up from your phone.** Typing a long access token with a remote is no fun. **Set up from your phone** shows a
QR code; it opens a one-time page served by the TV where you paste the address and token. The page only works while
the QR code is on screen.

## Notifications

Pop-ups over any app: the doorbell, a finished wash, a reminder. Hearth speaks the protocol of the
"Notifications for Android TV / Fire TV" integration (PiPup style) on port **7676**.

1. In Home Assistant, add the **Notifications for Android TV / Fire TV** integration with the TV's IP address
   (Settings → Home Assistant → Notifications shows it).
2. Send a notification from an automation:

   ```yaml
   action: notify.living_room_tv
   data:
     title: Doorbell
     message: Someone is at the front door
     data:
       duration: 20
       position: center
   ```

The usual options work: `duration` (1–120 s), `position`, `fontsize`, `transparency`, `bkgcolor`, `interrupt`, an
icon and an image.

### Cameras and buttons

Hearth also takes two fields of its own, sent with a `rest_command`:

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

Buttons need the [dashboard panel](#dashboard-panel)'s token, since Hearth calls the service as that user.

## Dashboard panel

A Home Assistant dashboard one press away: **Right** at the right edge of the home opens it.

1. In Home Assistant, make a **non-admin user** for the TV, and log in as that user.
2. On its profile page, **Security** tab, create a **long-lived access token**.
3. In Hearth, enter the Home Assistant address and the token (or use **Set up from your phone**), and optionally the
   dashboard to show (its URL path, e.g. `dashboard-tv`; empty shows the default one).

The panel is on for the current Google TV profile only, so kids' profiles don't get it unless you turn it on there.

## TV status

Hearth posts what the TV is doing to a Home Assistant webhook, when it changes (within a second or two) and every
10 minutes as a heartbeat. Home Assistant needs no credentials for the TV.

1. In Home Assistant, create an automation with a **Webhook** trigger and note its webhook ID.
2. In Hearth, enter the Home Assistant address and the webhook ID.

Hearth posts JSON to `<address>/api/webhook/<webhook ID>`:

| Field | Value |
|---|---|
| `screen` | `on` or `off` |
| `state` | `playing`, `paused`, `idle` or `off` |
| `app`, `app_package` | the app in front |
| `media_app`, `media_title`, `media_artist`, `media_album`, `media_duration_s` | now playing, from any app's media session (needs notification access) |
| `now_playing_available` | whether Hearth can see what's playing |
| `profile` | the Google TV profile's name |
| `profile_id` | a stable key for the profile (`user:<serial>`, or `user:<serial>:<account>` for another grown-up's account in the same user), unchanged by renames |
| `kids_profile` | `true` in a kids profile |
| `screen_time_up` | `true` while Google TV's bedtime or time's-up screen is showing |
| `screen_time_reason`, `screen_time_text`, `screen_time_minutes_left`, `screen_time_unlocks_at`, `screen_time_seen_at` | what that screen said |
| `screen_time_unlocks_at_iso` | the unlock time as the next such moment, in ISO 8601 with the TV's offset |
| `screen_time_event`, `screen_time_event_at` | `appeared` or `cleared`, and when (epoch ms): the last change, sent with every status until the next, so trigger on `screen_time_event_at` changing |
| `allowed_apps` | in a kids profile, the apps Family Link currently allows |
| `day` | the TV's local date (`YYYY-MM-DD`) the usage counts are for |
| `seconds_today`, `app_seconds_today`, `playing_seconds_today` | the active profile's usage today: seconds any app was in front with the screen on, seconds per app (package) in front, and seconds per app playing (media session). Hearth, Google TV's own screens and the screensaver don't count |
| `usage_today` | every profile's usage today: `{"<profile_id>": {"profile_name": "…", "seconds": n, "apps": {"<package>": n}, "playing": {"<package>": n}}}` |

The usage counts are cumulative for the day (a lost post loses nothing), kept across Hearth restarts, and start again
at local midnight.

**How often Hearth posts.** Within about 2 seconds of a change that matters (another app in front, play or pause, a
profile switch, the screen going on or off, screen time coming up or clearing); every 2 minutes while an app is in
front or playing, so the usage counts are never more than 2 minutes behind; otherwise every 10 minutes, so Home
Assistant can tell the TV is there. A status the same as the last one isn't sent again (the 10-minute one aside).
Each post runs your webhook automation once.

**Where the playing time comes from.** HearthTube reports its own playing time, in every profile. Other apps' comes
from their media sessions, which Android only shows to a notification listener in the same Android user. In the TV's
main user that's Hearth itself (its notification access). A kids profile's apps play in that profile's own Android
user, so there it's Hearth's agent, which needs notification access granted in that user, once, over adb:
`adb shell cmd notification allow_listener com.thesiegs.hearth/com.thesiegs.hearth.LauncherNotificationListenerService
<user id>`. Without it, that profile's `playing` lists HearthTube only (its `apps` time in front is counted either
way). In a kids profile the agent's notification access does nothing else: no pop-ups, nothing read or kept but what's
playing and for how long.

**Allowance for HearthTube (optional).** Hearth enforces a daily YouTube limit on its own (Settings → Profiles →
YouTube time per day). Home Assistant can add its say, e.g. a pool shared with the family's phones and tablets:
with the Home Assistant panel's address and token set, Hearth reads `sensor.hearth_allowance` about once a minute.
Its attribute `profiles`, or else its state as JSON (a template helper made in the UI can't have attributes), maps a
`profile_id` to `{"youtube_minutes_left": int or null, "schedule_locked": bool, "message": optional text}`; a
profile it doesn't list has no limit from it, and `{}` means none. A state that isn't such a map (unknown,
unavailable) is treated as unreadable: what Hearth read earlier that day still counts. The stricter of the two counts, and
HearthTube gets the result through Hearth (see [provider-contract.md](provider-contract.md)).

A minimal automation that keeps the current app in a helper:

```yaml
triggers:
  - trigger: webhook
    webhook_id: tv-status-example
    allowed_methods: [POST]
    local_only: true
actions:
  - action: input_text.set_value
    target:
      entity_id: input_text.tv_app
    data:
      value: "{{ trigger.json.app or 'Home' }}"
```

Use a long random webhook ID: anyone on your network who knows it can post to it.
