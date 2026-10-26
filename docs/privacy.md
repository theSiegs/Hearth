# Privacy

> **Draft.** Hearth is in early development and this document is a draft: features, settings and
> setup steps may change or be incomplete.

Hearth has no ads, analytics, crash reporting or trackers, and no Hearth account or server. Your settings, layouts,
profile pairings and backups stay on the TV. So does each profile's watch history: the titles apps say are playing,
and the Continue Watching entries Hearth keeps for each profile (forgotten after 90 days, or when you remove a card).
A kids profile's history is kept the same way, under that kid's profile only, and with household sync on it goes to
the household's other TVs for that kid's own row there (never an adult's or another kid's).
Calendar events are read from the TV when they show and aren't stored or sent anywhere.

## What Hearth connects to

Only for the features below, and only when they're on.

| Feature | Connects to | Sends |
|---|---|---|
| Bing wallpaper | `www.bing.com` | A request for the photo of the day |
| Weather | `api.open-meteo.com`, `geocoding-api.open-meteo.com` | The place you chose (or its coordinates) |
| Search | `www.wikidata.org`, `api.themoviedb.org`, `image.tmdb.org` | What you search for; the titles found |
| Continue Watching artwork | The image hosts the streaming apps name | Requests for those images, with no cookies or referrer, over https (http only on your home network); cached for 30 days |
| Continue Watching artwork, when a card has none Hearth can read | `www.wikidata.org`, `api.themoviedb.org`, `image.tmdb.org` | The card's title (not for YouTube or HearthTube videos); each title once, the answer kept on the TV |
| Updates | `api.github.com`, GitHub release downloads | A check for new releases of Hearth and HearthTube |
| Streaming app PINs | `raw.githubusercontent.com` (Hearth's repository) | A request for the list of app versions Hearth doesn't type PINs in, at most twice a day while a PIN is saved |
| Approve switches from my phone | Your Home Assistant | While Google TV's PIN screen waits for an answer: a notification to the phone you chose (whose profile, Allow and Deny), and a listen for its answer |
| Home Assistant map (people) | `tile.openstreetmap.org` | Requests for the map tiles around your home zone (about 17 km across), once, then kept on the TV; never a person's position |
| Home Assistant | The address you enter | Notifications' button actions, the dashboard, and TV status (see [Home Assistant](home-assistant.md)) |

Using the Breezy Weather app instead of Open-Meteo makes Hearth read weather from that app on the TV and connect to
nothing for it.

These services see the TV's IP address, like any website you visit. Search requests identify themselves as Hearth,
as Wikidata asks.

## What listens on the TV

- **Port 7676**, for Home Assistant notifications, only when they're on, and only from local network addresses.
- **The phone setup pages** (Home Assistant, streaming app PINs), only while their QR code is on screen, at a
  one-time secret link. The PIN page's QR code also carries a one-time key, after a `#` that browsers never send;
  the phone encrypts the PINs with it, so nothing else on the network can read them.
- **Copy profiles between TVs** (ports 8770 to 8774 and a `_hearth-share._tcp` announcement on the home network), only
  while the Copy profiles page is open on the sending TV. Both TVs must show the same six digits and a parent must say
  they match on both before anything is sent; the transfer is encrypted with a key made for that one copy and nothing
  is kept afterwards. Streaming PINs and the Home Assistant settings are sent only if the sending parent chooses them
  (Home Assistant gets a new token made for the other TV, never a copy of the sender's).
- **Port 47474 on the TV's own loopback address** (not the network), for Hearth's helpers in your kids profiles.
  Each helper and Hearth prove to each other that they share that helper's key without sending it, so no other app
  can pose as either.

## Permissions

| Permission | Why |
|---|---|
| Accessibility (Home Button Fix) | Opens Hearth when you press Home; follows Google TV profile switches and its screen time screens; remote button remaps; idle sleep; pop-ups. It reads Google TV's own screens, not your apps' content. |
| Accessibility (Profile Pairing) | Reads the profile screen of a streaming app that Hearth opened, picks your profile, and types its PIN if you saved one. It acts on a profile screen only when Hearth itself opened the app. The one exception is Paramount+'s content PIN, asked for when a title starts: if you saved it, Hearth types it then, in an adult's profile that has its own Google TV PIN. |
| Text-to-speech engine (Hearth voice) | Some apps only announce their profile screen out loud; Hearth voice lets Profile Pairing hear it, and passes all speech on to the TV's usual voice, so apps sound the same. Nothing is recorded or sent. |
| Notification access | Shows notifications in Hearth; sees what's playing for Continue Watching, each profile's watch history and usage today, and TV status. In a kids profile (a parent's Fix grants it there over adb, only for Hearth), lets Hearth's agent see what plays there (the title, episode and how far it got) for that kid's own watch history and Continue Watching, and for how long, for that profile's usage today. |
| Usage access | Knows which app is in front, for TV status and idle sleep; reads how much data the TV and each app used, for the data usage in the top bar (kept on the TV). |
| Install apps / delete apps | Updates Hearth and HearthTube; puts them on other profiles. |
| Display over other apps | Home Assistant pop-ups. |
| TV listings and Watch Next | Continue Watching and TV inputs. |
| Calendars (read only) | The date and time in the top bar show the active profile's Google calendars that are synced to the TV: only that profile's own account's calendars, read on the TV and sent nowhere. Hearth never adds or changes events. Asked for in Settings → Home screen → Status bar → Calendars; in a kids profile (whose Hearth can't show the request) a parent's Fix grants it there over adb, and only for Hearth. |
| Network state | The data usage's connection line (Wi-Fi, Ethernet, VPN, no internet). |
| Start at boot | Brings Hearth and its services back after a restart. |

**Hearth on the kids profiles** uses the TV's own debugging connection (Android asks you to allow it once) to install
Hearth's two apps in your kids profiles and keep them there, including a kids profile added later. It connects
only to the TV itself and only touches Hearth and HearthTube. Hearth's helpers in the kids profiles do not hold that
key (since 2026.10.61): Hearth, in your own profile, checks them once a day, keeps them installed, and lets them read
that profile's Watch Next and the calendars.
On a switch between adults' profiles, Hearth also closes streaming apps both profiles share, so each opens on its
own profile screen.

**Saved streaming PINs** are encrypted with a key kept in the TV's secure key store, which never leaves the TV. Each
belongs to the Google TV profile that saved it: no other profile gets it typed, even one paired with the same app
profile. In an adult's profile Hearth types it only when that profile has its own Google TV PIN, so nobody can
just switch to it and be let in. After two PINs in a row that the app doesn't take, Hearth stops until a new one is
saved, before the app would lock the profile. One switch in **Settings → Profiles → Streaming app PINs** stops
all typing, and the same page lists the last 20 entries (app, time and outcome, never a name or a PIN).
