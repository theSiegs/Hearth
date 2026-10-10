# Privacy

> **Draft.** Hearth is in early development and this document is a draft: features, settings and
> setup steps may change or be incomplete.

Hearth has no ads, analytics, crash reporting or trackers, and no Hearth account or server. Your settings, layouts,
profile pairings and backups stay on the TV. So does each profile's watch history: the titles apps say are playing,
and the Continue Watching entries Hearth keeps for each profile (forgotten after 90 days, or when you remove a card).

## What Hearth connects to

Only for the features below, and only when they're on.

| Feature | Connects to | Sends |
|---|---|---|
| Bing wallpaper | `www.bing.com` | A request for the photo of the day |
| Weather | `api.open-meteo.com`, `geocoding-api.open-meteo.com` | The place you chose (or its coordinates) |
| Search | `www.wikidata.org`, `api.themoviedb.org`, `image.tmdb.org` | What you search for; the titles found |
| Continue Watching artwork | The image hosts the streaming apps name | Requests for those images, with no cookies or referrer, over https (http only on your home network); cached for 30 days |
| Updates | `api.github.com`, GitHub release downloads | A check for new releases of Hearth and HearthTube |
| Home Assistant | The address you enter | Notifications' button actions, the dashboard, and TV status (see [Home Assistant](home-assistant.md)) |

Using the Breezy Weather app instead of Open-Meteo makes Hearth read weather from that app on the TV and connect to
nothing for it.

These services see the TV's IP address, like any website you visit. Search requests identify themselves as Hearth,
as Wikidata asks.

## What listens on the TV

- **Port 7676**, for Home Assistant notifications, only when they're on, and only from local network addresses.
- **The phone setup page**, only while its QR code is on screen, at a one-time secret link.

## Permissions

| Permission | Why |
|---|---|
| Accessibility (Home Button Fix) | Opens Hearth when you press Home; follows Google TV profile switches and its screen time screens; remote button remaps; idle sleep; pop-ups. It reads Google TV's own screens, not your apps' content. |
| Accessibility (Profile Pairing) | Reads the profile screen of a streaming app that Hearth opened, picks your profile, and types its PIN if you saved one. It acts only when Hearth itself opened the app. |
| Text-to-speech engine (Hearth voice) | Some apps only announce their profile screen out loud; Hearth voice lets Profile Pairing hear it, and passes all speech on to the TV's usual voice, so apps sound the same. Nothing is recorded or sent. |
| Notification access | Shows notifications in Hearth; sees what's playing for Continue Watching and TV status. |
| Usage access | Knows which app is in front, for TV status and idle sleep. |
| Install apps / delete apps | Updates Hearth and HearthTube; puts them on other profiles. |
| Display over other apps | Home Assistant pop-ups. |
| TV listings and Watch Next | Continue Watching and TV inputs. |
| Network and Wi-Fi state | The data usage and network shortcuts. |
| Start at boot | Brings Hearth and its services back after a restart. |

**Hearth on other profiles** uses the TV's own debugging connection (Android asks you to allow it once) to install
Hearth's two apps in other profiles and keep them there. It connects only to the TV itself and only touches Hearth
and HearthTube.

**Saved streaming PINs** are encrypted with a key kept in the TV's secure key store, which never leaves the TV.
