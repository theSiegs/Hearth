# Hearth user guide

> **Draft.** Hearth is in early development and this document is a draft: features, settings and
> setup steps may change or be incomplete.

## Getting started

1. Install the APK from the [latest release](https://github.com/theSiegs/Hearth/releases/latest) (see the
   [README](../README.md#install)).
2. Open Hearth. Its first-run setup starts by itself: it makes the Home button open Hearth, makes Hearth the home
   app, and ends with what's on. Skip anything; the home screen's **Finish setting up** chip and **Settings → System →
   Set up Hearth** carry on later.
3. **Settings → System → Set up Hearth** also lists each item below with its state. Each says why Hearth needs it
   and opens the Android screen where you turn it on.

| Item | What it's for |
|---|---|
| Hearth as the home app | Makes Hearth the TV's home app. It also keeps kids profiles from blocking Hearth. |
| Home Button Fix | Hearth's accessibility service. The Home button opens Hearth instead of Google TV's home, and Hearth follows profile switches, remote button remaps, idle sleep and Home Assistant pop-ups. |
| Notification access | Shows notifications in Hearth and lets it see what's playing. |
| Installing updates | Lets Hearth update itself and install its companion apps. |
| Profile Pairing | A second accessibility service that picks your profile in streaming apps (optional). |
| Hearth voice | A text-to-speech engine that lets Profile Pairing hear apps that announce their profile screens (optional). |

**"Restricted setting".** Android blocks accessibility services for apps installed outside the Play Store until you
allow it. The setup says so when it happens. With the TV's debugging on (Developer options), Hearth can lift the
block itself after showing you what it will run; otherwise run this once from a computer, then try again:

```sh
adb shell appops set com.thesiegs.hearth ACCESS_RESTRICTED_SETTINGS allow
```

**After an update** Android may switch the Home Button Fix off. Hearth notices and shows its Home button screen
again (never in a kids' profile), or the **Home button needs a fix** chip if you chose Not now.

## Moving around

- **Left** at the left edge of the home opens Settings; **Right** closes it.
- **Right** at the right edge opens the Home Assistant panel, when it's set up.
- From the Favorites dock, **Up** brings in Continue Watching and search; **Down** brings the dock back.
- **Hold OK** on an app or a Continue Watching card for its options (move, hide, remove, app info).

## Home screen

**Favorites dock.** Apps in the Favorites section appear in a frosted dock along the bottom of the first screen.
Change its look in **Settings → Home screen → Look**, or turn it off to get plain rows.

**Continue Watching** shows what apps put in Google TV's Watch Next list, most recent first, with cover art. It shows
the current profile's own list. Choose which apps appear, the card size and how many in
**Settings → Home screen → Continue Watching**.

**Sections.** Arrange apps into sections (rows or grids), rename, reorder and hide them in
**Settings → Home screen → Sections**. Google TV's own Settings app is hidden by default; Hearth's
**Settings → TV & power → Google TV settings** opens it.

**Wallpaper.** Bing's photo of the day, your own pictures, a gradient, or black. Each profile has its own. The
photo's title and credit are in **About Hearth**.

**Status bar.** Clock and date (choose the format), weather, data usage (per day, week or
month), TV inputs and the notification bell.

**Search.** Type or speak a title. Results show where you can watch it now (titles in services you have come first)
and open straight in that app. Adult titles never appear. The voice button hands the search to Google's assistant;
"Ask Google" does the same for typed searches.

## Profiles

Hearth follows Google TV's own profiles; there's nothing extra to set up. Each profile has its own home layout,
wallpaper and Continue Watching. The profile button in the top bar opens Google TV's profile chooser.

**Profile Pairing** (**Settings → Profiles → Profile Pairing**). When Hearth opens Netflix, Disney+, Apple TV,
HBO Max or Paramount+, it picks the app profile that matches your Google TV profile: by name, or the one you pair it
with. Open each app once from Hearth so it can learn the app's profiles. If an app profile has a PIN, you can save it
in Hearth; Hearth types it behind a "logging in as" card and never shows it. Saved PINs are encrypted with a key
that never leaves the TV.

**Lock Profile** (**Settings → Profiles**). Uses Google TV's own profile lock, so Google TV asks for your
profile's PIN to come back. Turn the PIN on for your account in Google TV first. You can also:
- hold the profile button in the top bar;
- map a remote button to "Lock Profile";
- set **Lock when the TV sleeps** (every time, or after some minutes asleep).

In a kids profile, holding the profile button opens the profile chooser instead.

## Kids profiles

Hearth treats a profile as a kids profile when Family Link supervises it.

- **Screen time.** When Google TV shows its bedtime or "time's up" screen, Hearth stays out of the way and returns
  when the kid is allowed back. Remote button remaps pause while those screens show.
- **Parent PIN** (**Settings → Profiles → Parent PIN**). Kids see their own settings plus one "Parent settings" row;
  anything that could undo your setup asks for the PIN.
- **Hearth on other profiles** (**Settings → Profiles**). Google TV removes apps that didn't come from the Play
  Store from kids' profiles each time the profile starts. This puts Hearth and HearthTube on your kids' profiles and
  keeps them installed. It can also set up the TV's other adult profiles. The first time, the TV asks "Allow
  debugging?": choose **Always allow**. It only touches Hearth's own two apps, and you can undo it any time.
- **Uninstalling.** Use **Settings → Profiles → Hearth on other profiles → Uninstall Hearth**, which removes Hearth
  from the other profiles first. Uninstalling from Android's settings would leave copies behind in kids' profiles.

## The remote

**Settings → TV & power → Remote → Remote buttons.** Pick a button, then what a press and a hold do:

- open an app or a TV input;
- switch profile, or lock the profile;
- search by voice or keyboard;
- Home, sleep, or Android settings;
- run a Home Assistant scene, script, button or toggle.

A remap can apply everywhere or only on Hearth's home screen. Remote buttons need the Home Button Fix.

## TV & power

- **Screensaver.** Hearth uses Google TV's screensaver; choose Google Photos (and which albums) or another source
  there.
- **Sleep when idle.** Puts the TV to sleep after a time with no remote use. Playing video or music counts as
  activity.

## Home Assistant

**Settings → Home Assistant.** See [Home Assistant](home-assistant.md).

## Updates

**Settings → System → Updates.** Choose **Hearth** to check its GitHub releases for a newer version and install it.
The same page installs HearthTube and keeps it up to date: with **Update automatically** on, Hearth checks daily and
updates HearthTube when it's not in use. The first install asks Android for permission to install apps; after that,
updates go through without asking.

**Include pre-releases** (on by default) also offers early test builds, of both Hearth and HearthTube. While Hearth is
in early development every release is a pre-release, so leave it on to get updates. Turning it off never installs an
older version.

## Backup & restore

**Settings → System → Backup & Restore.** Hearth backs up its settings and layouts every day, and you can make a
backup at any time. Restore picks from the list of backups.

## Languages

Hearth is in English, Arabic, Chinese, French, German, Hindi, Italian, Japanese, Korean, Portuguese, Russian,
Spanish, Turkish and Ukrainian (**Settings → System → Language**). Most translations are machine-made; corrections
are welcome ([list of strings to review](translations-to-review.md)).

## When something's wrong

- **The Home button opens Google TV.** The Home Button Fix is off; the home screen shows **Home button needs a fix**.
  Turn it back on from there, or in **Set up Hearth**.
- **"Use Google TV for now"** (**Settings → System**) lets you use Google TV's home for a while without uninstalling
  Hearth. The Home button still brings Hearth back.
- **Profile Pairing stopped picking a profile.** The app may have changed its screens; you get the app's own picker
  instead. Open the app from Hearth again so it can relearn the profiles. A saved PIN the app stops accepting shows
  as "paused" in Profile Pairing until you enter it again.
