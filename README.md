<div align="center">

<img src="assets/logo.png" alt="Hearth" height="96">

# Hearth

**A calm, family-friendly home screen for Google TV and Android TV.**

[![Latest Release](https://img.shields.io/github/v/release/theSiegs/Hearth?style=flat-square&color=4f46e5&label=Release)](https://github.com/theSiegs/Hearth/releases/latest)
[![License: GPL v3](https://img.shields.io/badge/License-GPL_v3-blue.svg?style=flat-square)](LICENSE)

[Features](#features) • [Download](#download) • [Setup](#setup) • [Profile Pairing](docs/profile-pairing.md) • [Home Assistant](docs/home-assistant.md) • [Credits](#credits)

</div>

---

Hearth is a quiet, ad-free interface for Google TV: your wallpaper, a dock of favorites, and what you were
watching. It follows Google TV's own profiles, so each person (and each kid) gets their own home screen, and it
can open a number of apps (Disney+, Netflix and more) straight into the right profile. It has no ads, no
analytics and no trackers.

<!-- TODO screenshots: home with dock, Continue Watching, Settings panel, Setup checklist, Profile Pairing, HA panel -->

## Features

### Home screen
- **Wallpaper first.** A dock of favorite apps along the bottom; press Up for Continue Watching (with
  cover art, most recent first) and Down for all apps, as a grid over a blurred wallpaper.
- **Settings on the left, Home Assistant on the right.** Left at the left edge opens Settings; Right at the
  right edge opens your Home Assistant dashboard (if turned on for that profile).
- **Themes and appearance:** accent colors, card styles, day/night wallpapers, an OLED-friendly black background,
  and custom banners for apps that lack one.

### Made for families
- **Google TV profiles, followed automatically.** Hearth knows which Google TV profile is active and gives each
  one its own layout of apps and dock.
- **Kids profiles:** apps a kids profile hasn't approved stay hidden, and Hearth's settings need the parent PIN.
- **Profile Pairing:** when Hearth opens Netflix, Disney+, Apple TV, HBO Max or Paramount+, it picks the matching
  profile on the app's "Who's watching?" screen for you, behind an "Opening Netflix as John…" card. No more
  landing in the wrong profile, or kids in a grown-up one. [How it works](docs/profile-pairing.md)
  > [!WARNING]
  > Profile Pairing is a bit fragile. It reads each app's profile screen the way a screen reader would, so an app
  > update can change that screen and break pairing for that app until Hearth catches up. When it can't find its
  > way, Hearth leaves the app's own picker up. Pull requests that repair or add apps are welcome.
- **Sleep when idle:** put the TV to sleep after a stretch with no remote presses (playing video counts as
  activity).

### Home Assistant
- **Notifications on the TV**, compatible with Home Assistant's *Notifications for Android TV / Fire TV*
  integration, plus Hearth extras: a live camera picture in the card and up to three buttons that run
  Home Assistant actions (for example "Unlock the door" from a doorbell alert).
- **Dashboard panel:** a slide-in panel with your scenes and room controls, set up by scanning a QR code with
  your phone (no typing tokens with a remote).
- **Remote buttons:** map a remote button (press or hold) to a Home Assistant scene, script or toggle.
- **TV status** pushed to Home Assistant: the app in front, what's playing, the profile, screen on/off.

[Home Assistant guide](docs/home-assistant.md)

### Remote, apps and updates
- **Home Button Fix:** on Google TV the Home button opens Hearth instead of Google's home screen. Hearth warns
  you if Android switched it off (for example after an update).
- **Remote buttons:** remap buttons to apps, inputs, profiles, Home, Settings, sleep or Home Assistant.
- **Setup checklist:** every Android setting Hearth needs, with a card that tells you exactly what to pick on the
  next screen before it opens it.
- **Updates from inside Hearth,** installed the way app stores install them, so Android keeps Hearth's
  accessibility features switched on after an update. After the first update, later ones usually install
  without asking.
- **Companion apps:** install and update [HearthTube](https://github.com/theSiegs/HearthTube) (YouTube for
  Hearth) from Settings. HearthTube follows Hearth's profile, clock, language and wallpaper, and can check
  Hearth's parent PIN.
- **Notifications** panel and pop-ups, weather (built in, or from Breezy Weather), TV input switching, and daily
  automatic backups of your settings.

## Download

Get the latest APK from [Releases](https://github.com/theSiegs/Hearth/releases/latest):

| File | For |
|:---|:---|
| `Hearth-armeabi-v7a-release.apk` | Most streaming sticks: onn 4K, Fire TV Stick, older TVs (32-bit ARM) |
| `Hearth-arm64-v8a-release.apk` | Chromecast with Google TV, Nvidia Shield, newer TVs (64-bit ARM) |
| `Hearth-universal-release.apk` | Any device, if you're not sure (larger) |

Install it with a file manager or the Downloader app. Once installed, Hearth updates itself
(Settings → Check for Updates).

> [!NOTE]
> Android 13 and later "restrict" apps installed from a downloaded file, and Google TV has no on-screen way to lift
> that, so Hearth's accessibility features (Home Button Fix, Profile Pairing) may refuse to turn on after a first
> install from a downloaded APK. If that happens, run this once from a computer:
> `adb shell appops set com.leanbitlab.ltvL ACCESS_RESTRICTED_SETTINGS allow`.
> Updates installed from inside Hearth don't have this problem.

## Setup

Open **Settings → Setup checklist** and work down the list. Each step explains what to choose, then opens the
right Android screen:

| Step | Why |
|:---|:---|
| Hearth as the home app | Keeps kids profiles from blocking Hearth |
| Home Button Fix | The Home button opens Hearth |
| Notification access | Notifications and "now playing" |
| Installing updates | Hearth can update itself and install companion apps |
| Profile Pairing *(optional)* | Opens streaming apps in the right profile |
| Hearth voice *(optional)* | Lets Profile Pairing read Netflix's profile screen |

In a kids profile, ask a parent to approve Hearth in that profile's app list, and set a parent PIN in
**Settings → Parent PIN** from a grown-up profile.

<details>
<summary>Other ways to make Home open Hearth</summary>

- **Key Mapper:** map the remote's Home button to open Hearth with
  [Key Mapper](https://github.com/keymapperorg/KeyMapper).
- **Disable Google TV's home (advanced, at your own risk):**
  ```shell
  adb shell pm disable-user --user 0 com.google.android.apps.tv.launcherx
  adb shell pm disable-user --user 0 com.google.android.tungsten.setupwraith
  # undo:
  adb shell pm enable com.google.android.apps.tv.launcherx
  adb shell pm enable com.google.android.tungsten.setupwraith
  ```
  Google TV profiles and kids features depend on Google TV's home, so Hearth doesn't recommend this.
</details>

## Privacy

Hearth has no ads, analytics or trackers. It talks to the internet only to check GitHub for updates, and to
fetch weather if you turn weather on. Home Assistant features talk only to your own Home Assistant, on your
home network. Profile Pairing reads only the streaming apps' "Who's watching?" screens, only right after Hearth
opens them, and keeps nothing but the profile names it saw, on the TV.

**Hearth voice** is a text-to-speech engine inside Hearth that Profile Pairing uses to hear Netflix's profile
screen. It keeps nothing and sends nothing anywhere: what the streaming apps say goes only to Profile Pairing (and
is never read aloud), and every other app's speech is handed to Google's voice. Turning Profile Pairing off
switches this listening off too: Hearth voice then just passes all speech to Google's voice. To stop using it
entirely, choose Google again under Settings → Accessibility → Text to speech.
[More about Hearth voice](docs/profile-pairing.md#why-netflix-needs-hearth-voice)

## Credits

Hearth is a fork of [LTvLauncher](https://github.com/leanbitlab-org/LtvLauncher) by LeanBitLab, with ideas from
[Arc Launcher](https://github.com/meddouribadis/arclauncher) by Badis Meddouri. Both build on
[FLauncher](https://gitlab.com/flauncher/flauncher) by etienn01 and its [fork](https://github.com/osrosal/flauncher)
by osrosal. Thank you to all of them.

## License

GPL-3.0. See [LICENSE](LICENSE).
