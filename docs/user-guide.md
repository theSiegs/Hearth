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
again (never in a kids profile), or the **Home button needs a fix** chip if you chose Not now.

## Moving around

- **Left** at the left edge of the home opens Settings; **Right** closes it.
- **Right** at the right edge opens the Home Assistant panel, when it's set up.
- From the Favorites dock, **Up** brings in Continue Watching and search; **Down** brings the dock back.
- **Hold OK** on an app or a Continue Watching card for its options (move, hide, remove, app info).

## Home screen

**Favorites dock.** Apps in the Favorites section appear in a frosted dock along the bottom of the first screen.
Change its look in **Settings → Home screen → Look**, or turn it off to get plain rows.

**Continue Watching** shows what apps put in Google TV's Watch Next list, most recent first, with cover art. It shows
the current profile's own list. Hearth also keeps each profile's own history on the TV: what apps say is playing,
which adds shows from apps that don't use Watch Next (with the app's icon instead of cover art), and entries an app
dropped when someone else used it (Netflix lists only its current profile's), until that profile opens the app again. Choose which apps appear, the card size and how many in
**Settings → Home screen → Continue Watching**.

**Sections.** Arrange apps into sections (rows or grids), rename, reorder and hide them in
**Settings → Home screen → Sections**. Google TV's own Settings app is hidden by default; Hearth's
**Settings → TV & power → Google TV settings** opens it.

**Wallpaper.** Bing's photo of the day, your own pictures, a gradient, or black. Each profile has its own. The
photo's title and credit are in **About Hearth**.

**Status bar.** Clock and date (choose the format), weather, data usage (per day, week or
month), TV inputs (only on TVs that have their own, not on a streaming stick) and the notification bell. Select the
weather for today's (or, from 5 PM, tonight's) summary; OK goes on to the next hours and days. Select the data usage to see which apps used the TV's data (OK goes
from today to this week and this month), whether the TV is on Wi-Fi and if a VPN is on; it says "No internet" when
the TV has been offline for a few seconds. Android counts Wi-Fi and mobile data only, not Ethernet.

**Calendar.** With calendar access allowed (**Settings → Home screen → Status bar → Calendars**), the date and time
in the top bar can be selected: they show the rest of today's events, and OK shows the next 7 days. The events come
from the profile's own Google calendars synced to the TV; each profile turns its calendars on or off there. In a kids
profile, a parent's **Fix** (Settings → Profiles → Kids profiles) lets Hearth read that profile's calendars.

**Search.** Type or speak a title. Results show where you can watch it now, from US availability data (titles in
services you have come first). Netflix, Apple TV, HBO Max and Paramount+ open straight on the title; other services
open through Google TV's title page. Adult titles never appear. The voice button hands the search to Google's assistant;
"Ask Google" does the same for typed searches.

## Profiles

Hearth follows Google TV's own profiles; there's nothing extra to set up. Each profile has its own home layout,
wallpaper and Continue Watching. The profile button in the top bar opens Google TV's profile chooser.

Adults' profiles (Google accounts added in Google TV's chooser) share the TV's main user and its apps. Hearth
still gives each its own home: after a switch it reads who Google TV's home says is logged in (English only, for
now), so Google TV's home shows for a moment first. Their Continue Watching comes from the same apps, and each
profile sees what was watched while it was on. The first switch to an adult's profile Hearth hasn't seen waits
about 15 seconds on Google TV's home, in case it's a new kids profile Google TV is still setting up.

**Profile Pairing** (**Settings → Profiles → Profile Pairing**). When Hearth opens Netflix, Disney+, Apple TV,
HBO Max or Paramount+, it picks the app profile that matches your Google TV profile: by name, or the one you pair it
with. Open each app once from Hearth so it can learn the app's profiles.

**Streaming app PINs** (**Settings → Profiles → Streaming app PINs**). If an app profile has a PIN, save it here, and
Hearth types it behind a "logging in as" card when the app asks, never showing it.

- Apps: Netflix, Disney+, Apple TV and HBO Max (a profile's PIN), and Paramount+'s content PIN (asked when a title
  starts; saved once for the TV, typed only in an adult's profile that has a Google TV PIN).
- Each Google TV profile sees and saves only its own PINs, and a PIN is typed only for the profile that saved it.
  In an adult's profile, only when that profile has its own Google TV PIN (otherwise anyone could switch to it and
  be let in): until then you'll see the app's own PIN screen. A kid's PIN is saved past the parent PIN.
- Saving a PIN for a profile matched by name pairs the two for good. Changing a pairing that has a PIN needs the
  parent PIN and removes the PIN.
- **Set up PINs on your phone** shows a QR code: the phone lists this profile's apps, and the PINs typed there are
  encrypted on the phone, with a one-time key from the QR code, before they reach the TV.
- **Type saved PINs** turns all of it off for the TV; the apps then ask as usual.
- **Recent PIN entries** lists the last 20 (app, time, outcome; never a name or a PIN).
- After two PINs in a row the app doesn't take, Hearth stops typing it until you save it again. If an app's PIN screen
  changes, Hearth pauses for that app until an update, and Hearth's repository can turn an app version off.
- PINs are encrypted with a key that never leaves the TV. The first time, a screen explains what Hearth will do,
  including that streaming services' terms may not allow an app to do this for you.

**Lock Profile** (**Settings → Profiles**). Uses Google TV's own profile lock, so Google TV asks for your
profile's PIN to come back. Turn the PIN on for your account in Google TV first. You can also:
- hold the profile button in the top bar;
- hold the remote's profile button (a press opens the profile chooser straight away). Hearth sets this button up
  once in **Settings → TV & power → Remote → Remote buttons**, where you can change it, or restore it to Google TV's
  own (the chooser only);
- map another remote button to "Lock Profile";
- set **Choose a profile when the TV wakes** (every time, or after some minutes asleep): the TV opens Google TV's
  profile chooser when it wakes, and a profile with a PIN asks for it before it opens. It is off until you turn it
  on, and kids profiles are left alone.

**Approve switches from my phone** (**Settings → Profiles**, in your own profile; needs Home Assistant and its phone
app). When Google TV asks for your PIN to open your profile, your phone gets a notification with Allow and Deny.
Allow, and Hearth enters your Google TV PIN; Deny, or no answer, leaves Google's PIN screen as it is. The PIN can always
be typed with the remote instead: pressing a key on the PIN screen withdraws the phone's request. Choose your phone and
save your Google TV PIN on that page (or on the phone page from Streaming app PINs). A PIN Google refuses isn't typed
again until it's saved anew.

In a kids profile, or a profile without a Google TV PIN, holding the profile button opens the profile chooser
instead. In a kids profile the remote's profile button always does Google TV's own job.

**Copy profiles between TVs** (**Settings → Profiles**, in your own profile). Sets a new TV up like another one: a
profile's look, home layout (which apps, in what order, the dock), wallpaper pictures and Profile Pairing choices go from
one TV to the other, over your home network. The parent on the sending TV can also send the streaming app PINs, the
Home Assistant settings and the parent PIN. Be at both TVs. On the TV that has the profiles, open **Copy profiles to another TV**
and choose which; on the other, open **Copy profiles from another TV** and choose the first (it is found by name, or
type the address the first TV shows). Both TVs show the same six digits: if they match on both screens, say so on both,
and the copy goes. The receiving TV then shows where each profile goes (a profile with the same name and kind here, or
**Don't copy**; a kids profile never goes onto a grown-up's, nor the other way round) and what to take.

- Only the apps installed on the receiving TV are placed; the others are left out and counted.
- A streaming app profile choice the receiving TV already has is kept as it is.
- A backup of the receiving TV is made first and listed in **Backup & Restore**, so a copy can be undone there.
- The sending TV chooses what goes along under **Also send**. Wallpaper pictures are on by default; streaming app PINs,
  Home Assistant and the parent PIN are off until chosen, and choosing one asks for the parent PIN where the TV has one.
  The receiving TV chooses again what it takes, and asks for its parent PIN before saving any of the three.
- PINs go only to a profile that has that streaming profile paired, a PIN that already works on the receiving TV is
  kept, and a kids profile never gets a Google TV PIN. They are checked on the receiving TV and never shown.
- Home Assistant: the sending TV has Home Assistant make a **new** long-lived token for the other TV (named "Hearth
  copy from …" with the date; see it, or remove it, in your Home Assistant profile). The sender's own token is never
  sent. The TV status webhook id isn't sent either: it belongs to one TV's automation, so each TV needs its own.
- A Home Assistant or parent PIN the receiving TV already has is replaced only if it is checked on that TV (it says
  "replaces this TV's").
- It works the same with no kids profiles, no parent PIN or no Home Assistant: what a TV doesn't have shows as
  "Nothing to send" there, and a copy is then just the look, layout, pictures and pairings. A new TV with no parent PIN
  can take the sender's along with its PINs (a PIN is only saved where a parent PIN guards it), and a new TV with one
  grown-up profile puts the copied grown-up's profile on it whatever the names; kids profiles go only to the same name.
- Nothing is kept afterwards: no key, no list of TVs.
- If the digits don't match, nothing is sent. Someone else on your network who connects can't get anything without a
  parent saying the digits match.

## Kids profiles

Hearth treats a profile as a kids profile when Family Link supervises it.

- **Screen time.** When Google TV shows its bedtime or "time's up" screen, Hearth stays out of the way and returns
  when the kid is allowed back. Remote button remaps pause while those screens show.
- **Parent PIN** (**Settings → Profiles → Parent PIN**). Kids see their own settings plus one "Parent settings" row;
  anything that could undo your setup asks for the PIN.
- **YouTube only in HearthTube.** With HearthTube installed, a kids profile watches YouTube only there, where its
  YouTube time applies: YouTube's own app is hidden, and if it opens anyway (a voice search, a link) HearthTube opens
  over it. Adults' profiles start with YouTube's app hidden too; show it again from its app options if you want it.
- **Apps on the kids profiles.** Google TV keeps a list of the apps a parent has approved for each kid and removes
  every other app from the kid's profile: after any app is installed or updated on the TV, when the TV starts, and
  at many profile starts. Apps added from the Play Store inside a kids profile aren't on that list, so they are
  removed. Hearth hides the Play Store in kids profiles for that reason. Add an app for a kid from your own profile:
  Settings > Accounts & Sign In > the kid > Manage apps (it asks for your Google PIN). Google TV then installs it in
  the kid's profile, and it shows up in the kid's Hearth.
- **Hearth on the kids profiles.** Hearth puts itself (and HearthTube) back on the kids profiles and keeps them there,
  using the TV's own debugging connection. The setup does this once:
  - When the TV asks "Allow debugging?", choose **Always allow**.
  - Leave debugging on, and in Developer options also turn on **Disable adb authorization timeout**, so the TV keeps
    trusting Hearth (Google TV turns the debugging switch off by itself over time).
  - Each kid gets one Family Link "app added" notice. Hearth only touches its own two apps.

  A kids profile you add later gets Hearth too, once you've switched away from it. The same connection lets Hearth
  close the streaming apps adults share when the profile changes, so they ask who's watching.
- **Kids profiles** (**Settings → Profiles → Kids profiles**) shows each kid as **Ready** or **Needs a fix**, with
  one **Fix** for those that need it. Select a kid to manage what's theirs without switching to their profile:
  - **YouTube time per day**: how long HearthTube may play each day. With Home Assistant (optional), a limit shared
    with the family's other devices can count too, and the stricter one wins. Adults have no YouTube limit.
  - **HearthTube**: **Get HearthTube** installs it (on the TV, then for that kid), and while that kid's profile is on,
    **HearthTube settings** opens HearthTube's own settings for them, behind the parent PIN.
- **Uninstalling.** Use **Settings → Profiles → Kids profiles → Uninstall Hearth**: it takes Hearth off the kids
  profiles first. Android's own uninstall would leave copies behind there. **Remove Hearth from kids profiles** does
  only that first part, and Hearth stops adding itself to new ones.

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
- **Use Google TV's home.** Hearth stays out of the way and Google TV's own home shows, until you press the Home button
  (which opens Hearth and turns this off) or turn it off here.

## Home Assistant

**Settings → Home Assistant.** See [Home Assistant](home-assistant.md).

## Updates

**Settings → System → Updates.** Choose **Hearth** to check its GitHub releases for a newer version and install it.
The same page installs HearthTube and keeps it up to date: with **Update automatically** on, Hearth checks daily and
updates HearthTube when it's not in use. The first install asks Android for permission to install apps; after that,
updates go through without asking.

**Include pre-releases** also offers early test builds, of both Hearth and HearthTube. It starts on in a pre-release
of Hearth and off in a release, and is set that way again when Hearth moves from one kind to the other. While Hearth
is in early development every release is a pre-release, so leave it on to get updates. Turning it off never installs an
older version.

## Backup & restore

**Settings → System → Backup & Restore.** Hearth backs up its settings and layouts every day, and you can make a
backup at any time. Restore picks from the list of backups.

## Languages

Hearth is in English only.

## When something's wrong

- **The Home button opens Google TV.** The Home Button Fix is off; the home screen shows **Home button needs a fix**.
  Turn it back on from there, or in **Set up Hearth**.
- **Use Google TV's home** (**Settings → TV & power**) leaves Google TV's own home in front until you press Home or turn it off,
  without uninstalling Hearth. The Home button opens Hearth and turns it off.
- **Profile Pairing stopped picking a profile.** The app may have changed its screens; you get the app's own picker
  instead. Open the app from Hearth again so it can relearn the profiles.
- **A saved PIN isn't typed.** **Streaming app PINs** says why: "not accepted twice" (save it again), "paused" (the
  app's PIN screen changed; an update will fix it), or nothing saved for this profile. In an adult's profile, the
  profile needs its own Google TV PIN. **Recent PIN entries** shows what happened each time.
- **An app opens on someone else's profile after a switch.** The TV's debugging has stopped trusting Hearth, so it
  can't close the app on the switch: see Kids profiles above.
