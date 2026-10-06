# Home Assistant

Hearth works with [Home Assistant](https://www.home-assistant.io/) in four ways. All of them stay on your home
network. Set them up in **Hearth Settings → Home Assistant**.

| Feature | Direction | Needs |
|:---|:---|:---|
| [Notifications on the TV](#notifications-on-the-tv) | Home Assistant → TV | Home Button Fix on |
| [Dashboard panel](#dashboard-panel) | TV shows a dashboard | A long-lived access token |
| [Remote buttons](#remote-buttons) | TV → Home Assistant | The panel's token, Home Button Fix on |
| [TV status](#tv-status) | TV → Home Assistant | A webhook |

## Notifications on the TV

Hearth listens on port **7676** for the same pushes as Home Assistant's built-in
**Notifications for Android TV / Fire TV** integration, so you can use that integration as-is:

1. In Hearth: Settings → Home Assistant → turn on **Show Home Assistant notifications**. Pop-ups appear over any
   app and need Home Button Fix to be on.
2. In Home Assistant: add the *Notifications for Android TV / Fire TV* integration with the TV's address as the
   host (Hearth shows it on its Home Assistant page).
3. Use **Send a test notification** in Hearth to check the pop-up.

Only devices on your home network can send notifications.

### Camera and buttons (Hearth extras)

Hearth also accepts two fields the standard integration doesn't send:

- `camera`: a camera entity, shown live in the card (picture-in-picture style).
- `actions`: up to three buttons, each `{"title", "service", "data"}`, which run a Home Assistant action when
  pressed. The card always adds a **Close** button and starts on it, so a stray OK press does nothing.

Buttons run with the dashboard panel's access token, so set up the [panel](#dashboard-panel) first. Anyone holding
the remote can press them, so choose actions you're comfortable with anyone in the room running (and give the TV's
Home Assistant user only what it needs).

Send them with a `rest_command` (replace the TV's address):

```yaml
rest_command:
  hearth_family_room:
    url: "http://192.0.2.73:7676"
    method: post
    content_type: "application/x-www-form-urlencoded"
    payload: >-
      title={{ title | default('') | urlencode }}&msg={{ message | default('') | urlencode }}&camera={{ camera | default('') | urlencode }}&duration={{ duration | default(30) }}&actions={{ actions | default([]) | to_json | urlencode }}
```

Then, for example, in a doorbell automation:

```yaml
action: rest_command.hearth_family_room
data:
  title: Someone's at the door
  message: Front door
  camera: camera.front_door
  duration: 60
  actions:
    - title: Unlock
      service: lock.unlock
      data:
        entity_id: lock.front_door
    - title: Porch light
      service: light.toggle
      data:
        entity_id: light.porch
```

## Dashboard panel

Press **Right** at the right edge of the home screen to slide in a Home Assistant dashboard: scenes, lights,
climate, whatever you put on it. Left (when nothing is further left) or Back closes it.

The panel is **off for every profile until a grown-up turns it on** for that profile (Settings → Home Assistant →
*Right at the right edge opens the panel*).

To connect it:

1. In Home Assistant, create a **non-admin user for the TV** (for example "test TV"), log in as that user,
   and create a **long-lived access token** (profile page → Security).
2. In Hearth, choose **Set up from your phone** and scan the QR code with a phone on the same Wi-Fi. Paste the
   Home Assistant address and the token, and tap Send. (The page only works while the QR code is showing, and
   only once.) You can also type them on the TV.
3. Enter the **Dashboard** to show, as `<dashboard>/<view>` (for example `hearth-tv/family_room`). A dashboard
   made for the TV works best: a single column of tiles for that room.

## Remote buttons

In **Settings → Remote buttons**, any button can run a Home Assistant action on press or hold: choose
**Home Assistant…** and pick a scene, script, button or something to toggle. It uses the panel's token.

## TV status

Hearth can push what the TV is doing to a Home Assistant **webhook**: the app in front, what's playing (needs
notification access), the Google TV profile, whether it's a kids profile, kids screen-time locks, and screen on/off.
It sends on change and as a heartbeat, so Home Assistant needs no credentials for the TV.

In Settings → Home Assistant → *TV status for Home Assistant*, enter the Home Assistant address and the webhook ID
of an automation with a webhook trigger, then **Save status settings**.
