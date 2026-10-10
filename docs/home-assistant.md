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
| `allowed_apps` | in a kids profile, the apps Family Link currently allows |

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
