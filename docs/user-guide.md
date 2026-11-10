# Hearth TV user guide

> **Draft.** Hearth TV is in early development and this document is a draft: features, settings and
> setup steps may change or be incomplete.

## Getting started

1. Install the APK from the [latest release](https://github.com/theSiegs/Hearth/releases/latest) (see the
   [README](../README.md#install)).
2. Open Hearth TV. Its first-run setup starts by itself: it makes the Home button open Hearth TV, makes Hearth TV the home
   app, and ends with what's on. When your other Hearth TVs are in a household, it next offers to join it (someone
   allows it in the notification Bell on one of those TVs), and everyone's looks, layouts, streaming profiles and saved
   PINs come to this TV. Skip anything; the home screen's **Finish setting up** chip and **Settings → System →
   Set up Hearth TV** carry on later.
3. **Settings → System → Set up Hearth TV** also lists each item below with its state. Each says why Hearth TV needs it
   and opens the Android screen where you turn it on.

| Item | What it's for |
|---|---|
| Hearth TV as the home app | Makes Hearth TV the TV's home app. It also keeps kids profiles from blocking Hearth TV. |
| Home Button Fix | Hearth TV's accessibility service. The Home button opens Hearth TV instead of Google TV's home, and Hearth TV follows profile switches, remote button remaps, idle sleep and Home Assistant pop-ups. |
| Notification access | Shows notifications in Hearth TV and lets it see what's playing. |
| Installing updates | Lets Hearth TV update itself and install its companion apps. |
| Profile Pairing | A second accessibility service that picks your profile in streaming apps (optional). |
| Hearth TV voice | A text-to-speech engine that lets Profile Pairing hear apps that announce their profile screens (optional). |

**Profiles are Google TV's.** Hearth TV doesn't make profiles: it follows Google TV's, and shows each person their own
home. Add every adult and every child as a profile in Google TV (**Settings → Accounts & profiles**). A kid's
profile gets its apps from Google TV too: for each kid, pick their apps in Google TV (**Settings → Accounts & profiles
→ the kid's profile → Apps**). Hearth TV can't show an app that a kid's profile doesn't have. The setup's **Your family**
card says this first, and **Set up Hearth TV** keeps it under **Google TV's own settings**.

**With Home Assistant running screen time**, leave Google's own time limits off: no daily time limit or bedtime for a
kid's TV profile, in Google TV or in Family Link. Google's own limit wins over Hearth TV: extra time and approvals can't
get past it, and Hearth TV shows "Google TV's own limit". A paired TV's setup has a step for it, and when Hearth TV saw
Google TV's own time's up screen in the last week, **Set up Hearth TV** says **Google TV's own limit is on**.

**"Restricted setting".** Android blocks accessibility services for apps installed outside the Play Store until you
allow it. The setup says so when it happens. With the TV's debugging on (Developer options), Hearth can lift the
block itself after showing you what it will run; otherwise run this once from a computer, then try again:

```sh
adb shell appops set com.thesiegs.hearth ACCESS_RESTRICTED_SETTINGS allow
```

**After an update** Android may switch the Home Button Fix off. Hearth TV notices and shows its Home button screen
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
the current profile's own list. Hearth TV also keeps each profile's own history on the TV: what apps say is playing,
which adds shows from apps that don't use Watch Next (with the title's picture from TMDB when Hearth TV finds an exact match, else the app's icon), and entries an app
dropped when someone else used it (Netflix lists only its current profile's), until that profile opens the app again.
A kids profile gets the same: once a parent's **Fix** (Settings → Family → Kids profiles) has let Hearth TV see
what plays there, what the kid watches is kept for their own row only, never an adult's or another kid's.
With household sync on, each person's titles follow them to the household's other TVs, kids' included (a kid's
only ever in their own row), with their cover art, and one taken out or finished on one TV goes from the others. Choose which apps appear, the card size and how many in
**Settings → Home screen → Continue Watching**.

**Sections.** Arrange apps into sections (rows or grids), rename, reorder and hide them in
**Settings → Home screen → Sections**. Google TV's own Settings app is hidden by default; Hearth TV's
**Settings → TV & power → Google TV settings** opens it, and **Network** there opens its Wi-Fi and
Ethernet settings, with how the TV is connected now beside it.

**Wallpaper.** Bing's photo of the day, your own pictures, a gradient, or black. Each profile has its own. The
photo's title and credit are in **About Hearth TV**.

**Status bar.** Clock and date (choose the format), weather, data usage (per day, week or
month), TV inputs (only on TVs that have their own, not on a streaming stick) and the notification bell. Select the
weather for today's (or, from 5 PM, tonight's) summary; OK goes on to the next hours and days. Select the data usage to see which apps used the TV's data (OK goes
from today to this week and this month), whether the TV is on Wi-Fi and if a VPN is on; it says "No internet" when
the TV has been offline for a few seconds. Android counts Wi-Fi and mobile data only, not Ethernet.

**Notification Bell.** The bell lists the TV's notifications, and Home Assistant's (which also pop up over what's
playing). With household sync on, Home Assistant's are in the Bell on every TV of the household, and clearing one
clears it on all of them. Each shows only to the profile it's for: one Home Assistant sends to a person (see
[Home Assistant](home-assistant.md#notifications)) only to them, one sent to no one in particular to every adult, and
kids' profiles only what is sent to that kid. A TV asking to join the household shows in the Bell of every household
TV, for adults, and **Allow** or **Don't allow** works on any of them; the first answer decides. The Bell needs
Notification access.

**Calendar.** With calendar access allowed (**Settings → Home screen → Status bar → Calendars**), the date and time
in the top bar can be selected: they show the rest of today's events, and OK shows the next 7 days. The events come
from the profile's own Google calendars synced to the TV; each profile turns its calendars on or off there. In a kids
profile, a parent's **Fix** (Settings → Family → Kids profiles) lets Hearth TV read that profile's calendars.

**Search.** Type or speak a title. Results show where you can watch it now, from US availability data (titles in
services you have come first). Netflix, Apple TV, HBO Max and Paramount+ open straight on the title; other services
open through Google TV's title page. Adult titles never appear. The voice button hands the search to Google's assistant;
"Ask Google" does the same for typed searches.

## Profiles

Hearth TV follows Google TV's own profiles; there's nothing extra to set up. Each profile has its own home layout,
wallpaper and Continue Watching. The profile button in the top bar opens Google TV's profile chooser.

Adults' profiles (Google accounts added in Google TV's chooser) share the TV's main user and its apps. Hearth TV
still gives each its own home: after a switch it reads who Google TV's home says is logged in (English only, for
now), so Google TV's home shows for a moment first. Their Continue Watching comes from the same apps, and each
profile sees what was watched while it was on. The first switch to an adult's profile Hearth TV hasn't seen waits
about 15 seconds on Google TV's home, in case it's a new kids profile Google TV is still setting up.

**Profile Pairing** (**Settings → Family → Profile Pairing**). When Hearth TV opens Netflix, Disney+, Apple TV,
HBO Max or Paramount+, it picks the app profile that matches your Google TV profile: by name, or the one you pair it
with. Open each app once from Hearth TV so it can learn the app's profiles.

**Streaming app PINs** (**Settings → Profiles → Streaming app PINs**). If an app profile has a PIN, save it here, and
Hearth TV types it behind a "logging in as" card when the app asks, never showing it.

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
- After two PINs in a row the app doesn't take (one, for Paramount+'s content PIN), Hearth TV stops typing it until you save it again. If an app's PIN screen
  changes, Hearth TV pauses for that app until an update, and Hearth TV's repository can turn an app version off.
- PINs are encrypted with a key that never leaves the TV. The first time, a screen explains what Hearth TV will do,
  including that streaming services' terms may not allow an app to do this for you.

**Lock now** (**Settings → Profiles**). Uses Google TV's own profile lock, so Google TV asks for your
profile's PIN to come back. Turn the PIN on for your account in Google TV first. You can also:
- hold the profile button in the top bar;
- hold the remote's profile button (a press opens the profile chooser straight away). Hearth TV sets this button up
  once in **Settings → TV & power → Remote → Remote buttons**, where you can change it, or restore it to Google TV's
  own (the chooser only);
- map another remote button to "Lock now";
- set **Log out when the TV sleeps** (every time, or after some minutes asleep): Hearth TV opens Google TV's profile
  chooser as the TV goes to sleep (or once it has slept that long), so whoever turns it on next picks who's watching,
  and a profile with a PIN asks for it before it opens. It works from kids profiles too; leaving one is still up to
  Google TV's kids lock. It is on (every time) until you choose otherwise. When the power button wakes the TV, Google
  TV starts its own home over the chooser; a couple of seconds later Hearth TV opens the chooser again, once, unless
  someone already pressed a key or picked a profile (or **Use Google TV's home** is on).

**Approve switches from my phone** (**Settings → Profiles → Unlock from my phone**, in your own profile; needs Home Assistant and its phone
app). When Google TV asks for your PIN to open your profile, your phone gets a notification with Allow and Deny.
Allow, and Hearth TV enters your Google TV PIN; Deny, or no answer, leaves Google's PIN screen as it is. The PIN can always
be typed with the remote instead: pressing a key on the PIN screen withdraws the phone's request. Choose your phone and
save your Google TV PIN on that page (or on the phone page from Streaming app PINs). A PIN Google refuses isn't typed
again until it's saved anew.

In a kids profile, or a profile without a Google TV PIN, holding the profile button opens the profile chooser
instead. In a kids profile the remote's profile button always does Google TV's own job.

**Your other TVs** (**Settings → Family → Household sync**). Hearth TVs in a household keep each person's look, home
layout (the dock, rows, hidden apps), wallpaper pictures, streaming app profile choices, saved PINs and Continue
Watching in step, and share one Parent PIN; each TV keeps its own name, Home Assistant connection and Home Button Fix.
A person is the same person on every TV by their Google account. When two TVs change different things, both keep
theirs; when they change the same thing, the later change wins. An app that isn't installed on a TV is left off its
home, and comes back where the person put it once it's installed.

- **Joining.** On a TV that isn't in the household, choose **Join the household**, then allow it in the notification
  Bell of the TV it names.
- **Before anything changes**, the new TV lists what the household's settings would change on it ("Alex: look, home
  layout, 1 saved PIN"). **Join and use these** goes on, **Don't join** leaves the household again with nothing
  changed, and **Later** waits (choose **Finish joining** on the Household sync page when ready).
- **Putting it back.** For 14 days after joining, **Put back this TV's settings from before it joined** on the same
  page restores what the TV had. What's put back is the newest change, so your other TVs take it too for the same
  people; to keep one TV different, leave the household instead.

## Kids profiles

Hearth TV treats a profile as a kids profile when Family Link supervises it.

- **Screen time.** When Google TV shows its bedtime or "time's up" screen, Hearth TV stays out of the way and returns
  when the kid is allowed back. Remote button remaps pause while those screens show.
- **Parent PIN** (**Settings → Family → Parent PIN**). Kids see their own settings plus one "Parent settings" row;
  anything that could undo your setup asks for the PIN. With household sync on, the household's TVs share one Parent
  PIN: a TV that joins without one takes it, and a change on one TV reaches the others. A TV that had its own,
  different PIN when it joined keeps it until you choose **Use your other TVs' Parent PIN** in **Settings → Family**
  and enter theirs. With Hearth's Home Assistant integration, each adult can have their own parent PIN, set in Home
  Assistant (**Hearth → Configure → Parent PINs**): a connected TV takes them in place of its own, any adult's works,
  and **Settings → Family → Parent PIN** says **Set in Home Assistant**. The TV keeps them, so they work while Home
  Assistant is down; if it's disconnected, it keeps the last ones until you set a PIN on the TV again.
  Five wrong PINs in a row make every PIN pad on the TV (Hearth's and HearthTube's) wait 30 seconds, then twice as
  long after each further wrong one, up to an hour; restarting the TV doesn't end the wait, and the right PIN clears it.
- **Other computers stay out.** Hearth keeps the TV's debugging on for its own setup, so a computer on your Wi-Fi
  could ask to control the TV. When the TV asks "Allow debugging?" for any computer but Hearth itself, Hearth answers
  Cancel and says so. To let one in (yours, to install a build), choose **Settings → Family → Allow a computer to
  connect** and enter the Parent PIN: for the next two minutes the prompt is yours to answer.
- **YouTube only in HearthTube.** With HearthTube installed, a kids profile watches YouTube only there, where its
  YouTube time applies: YouTube's own app is hidden, and if it opens anyway (a voice search, a link) HearthTube opens
  over it. Adults' profiles start with YouTube's app hidden too; show it again from its app options if you want it.
- **Apps on the kids profiles.** Google TV keeps a list of the apps a parent has approved for each kid and removes
  every other app from the kid's profile: after any app is installed or updated on the TV, when the TV starts, and
  at many profile starts. Apps added from the Play Store inside a kids profile aren't on that list, so they are
  removed. Hearth TV hides the Play Store in kids profiles for that reason. Add an app for a kid from your own profile:
  Settings > Accounts & Sign In > the kid > Manage apps (it asks for your Google PIN). Google TV then installs it in
  the kid's profile, and it shows up in the kid's Hearth TV.
- **Hearth TV on the kids profiles.** Hearth TV puts itself (and HearthTube) back on the kids profiles and keeps them there,
  using the TV's own debugging connection. The setup does this once:
  - When the TV asks "Allow debugging?", choose **Always allow**.
  - Leave debugging on, and in Developer options also turn on **Disable adb authorization timeout**, so the TV keeps
    trusting Hearth TV (Google TV turns the debugging switch off by itself over time).
  - Each kid gets one Family Link "app added" notice. Hearth TV only touches its own two apps.

  A kids profile you add later gets Hearth TV too, once you've switched away from it. The same connection lets Hearth TV
  close the streaming apps adults share when the profile changes, so they ask who's watching.
- **Kids profiles** (**Settings → Family → Kids profiles**) shows each kid as **Ready** or **Needs a fix**, with
  one **Fix** for those that need it. Select a kid to manage what's theirs without switching to their profile:
  - **YouTube time per day**: how long HearthTube may play each day. With Home Assistant (optional), a limit shared
    with the family's other devices can count too, and the stricter one wins. Adults have no YouTube limit.
  - **HearthTube**: **Get HearthTube** installs it (on the TV, then for that kid), and while that kid's profile is on,
    **HearthTube settings** opens HearthTube's own settings for them, behind the parent PIN.
- **Removing Hearth TV from kids profiles.** **Remove Hearth TV from kids profiles** takes Hearth TV and HearthTube off
  them, and Hearth TV stops adding itself to new ones; Hearth TV stays on your profile.
- **Uninstalling.** Use **Settings → System → Uninstall Hearth TV**: it takes Hearth TV off the kids profiles first.
  Android's own uninstall would leave copies behind there.

## The remote

**Settings → TV & power → Remote → Remote buttons.** Pick a button, then what a press and a hold do:

- open an app or a TV input;
- switch profile, or lock the profile;
- search by voice or keyboard;
- Home, sleep, or Android settings;
- run a Home Assistant scene, script, button or toggle.

A remap can apply everywhere or only on Hearth TV's home screen. Remote buttons need the Home Button Fix.

With HearthTube installed, the same page has **YouTube button opens HearthTube** (off until you turn it on). The
remote's YouTube button then opens HearthTube instead of YouTube, in every profile; in a kids profile it opens the
kid's own HearthTube. Turn it off to give the button back to YouTube.

## TV & power

- **Screensaver.** Hearth TV uses Google TV's screensaver; choose Google Photos (and which albums) or another source
  there.
- **Sleep when idle.** Puts the TV to sleep after a time with no remote use. Playing video or music counts as
  activity.
- **Use Google TV's home.** Hearth TV stays out of the way and Google TV's own home shows, until you press the Home button
  (which opens Hearth TV and turns this off) or turn it off here.

## Home Assistant

**Settings → Home Assistant.** See [Home Assistant](home-assistant.md).

## Updates

**Settings → System → Updates.** Choose **Hearth TV** to check its GitHub releases for a newer version and install it.
The same page installs HearthTube and keeps it up to date: with **Update automatically** on, Hearth TV checks daily and
updates HearthTube when it's not in use, and Hearth TV itself while the TV's screen is off (installing restarts the home).
The first install asks Android for permission to install apps; after that, updates go through without asking.

**Include pre-releases** also offers early test builds, of both Hearth TV and HearthTube. It starts on in a pre-release
of Hearth TV and off in a release, and is set that way again when Hearth TV moves from one kind to the other. While Hearth TV
is in early development every release is a pre-release, so leave it on to get updates. Turning it off never installs an
older version.

## Backup & restore

**Settings → System → Backup & Restore.** Hearth TV backs up its settings and layouts every day, and you can make a
backup at any time. Restore picks from the list of backups.

## Ad tracking

**Settings → System → Ad tracking.** Google can learn what you like from the apps you use and use it for ads
(Android's Privacy Sandbox: ad topics, on-device ad auctions and ad measurement, with on-device personalization and
federated learning). **Keep ad tracking off** is on unless you turn it off: Hearth TV turns these parts off for every
profile on the TV, kids profiles included, through its own debugging connection. The setup flow offers the same step
right after the Home button and home app steps whenever some of it is on; with the TV's debugging off, it first walks
through turning debugging on (which the kids profiles step then reuses). Google can turn them back on from its servers or with a module
update, so Hearth TV checks again when the TV wakes (the kids profiles every few hours). That check needs the TV to
already trust Hearth TV's debugging key, so it never shows "Allow debugging?". Play Store, voice and casting keep working.
Turning the switch off turns these parts back on, and asks for the Parent PIN if there is one.

## Languages

Hearth TV is in English only.

## When something's wrong

- **The Home button opens Google TV.** The Home Button Fix is off; the home screen shows **Home button needs a fix**.
  Turn it back on from there, or in **Set up Hearth TV**.
- **Use Google TV's home** (**Settings → TV & power**) leaves Google TV's own home in front until you press Home or turn it off,
  without uninstalling Hearth TV. The Home button opens Hearth TV and turns it off.
- **Profile Pairing stopped picking a profile.** The app may have changed its screens; you get the app's own picker
  instead. Open the app from Hearth TV again so it can relearn the profiles.
- **A saved PIN isn't typed.** **Streaming app PINs** says why: "not accepted twice" (save it again), "paused" (the
  app's PIN screen changed; an update will fix it), or nothing saved for this profile. In an adult's profile, the
  profile needs its own Google TV PIN. **Recent PIN entries** shows what happened each time.
- **An app opens on someone else's profile after a switch.** The TV's debugging has stopped trusting Hearth TV, so it
  can't close the app on the switch: see Kids profiles above.
