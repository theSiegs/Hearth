# Design: Hearth's first-run setup

> **Draft.** Hearth is in early development and this document is a draft: the flow, its screens and their wording
> may change. The English copy in §6 is a first version, and the other languages are machine translations.

Status: decided (owner decisions of 2026-10-09 are folded in, see §7), being built in the order of §8. Every
example name here is made up ("Alex", "Sam", "the TV", 192.0.2.10).

---

## 0. Summary

Hearth already had the parts of a setup flow, but they were scattered:
- the **Setup & permissions** checklist, now **Set up Hearth** (`setup_checklist_page.dart`: `SetupStep`,
  `loadSetupSteps`);
- the **Home Button Fix is off** dialog (`home_button_fix_check.dart`);
- adb fallback dialogs (`adb_command_dialog.dart`);
- the shuffled row-pad **parent PIN** (`parent_pin_dialog.dart`);
- the **phone QR** for Home Assistant (`ha_phone_setup_dialog.dart`);
- self-adb **Hearth on other profiles** (`family_apps_page.dart`);
- separate permission flows in Continue Watching, Notifications and Updates.

The setup flow is one full-screen flow that runs those same pieces in order:

**Welcome → Essentials (Home button, home app) → up to six optional feature cards (Turn on / Not now) → Finish**

- It resumes wherever it was left.
- It brings itself back to the front when Android reports a switch was turned on.
- After an update that adds features, it offers them through a home-screen chip (a full screen only when the
  update switched the Home button off).
- Kids' profiles never see it.

---

## 1. Inventory: what a new owner has to understand, grant or choose

Key:
- **Bounce** = Hearth opens an Android Settings screen and the user leaves Hearth.
- **In-app** = a system dialog over Hearth, or a Hearth screen.
- **Adb** = a computer, or Hearth's own loopback adb ("self-adb", once the parent approved "Allow debugging?").

| # | Item | What it gives | How it's granted | How Hearth detects it | Needed? | Without a TV-only path | Kids profile |
|---|---|---|---|---|---|---|---|
| 1 | **Default home app** | Hearth holds Android's Home role. Its reason ("keeps kids' profiles from blocking Hearth") is to be confirmed on the TV | Bounce: `Settings.ACTION_HOME_SETTINGS` → `MANAGE_DEFAULT_APPS_SETTINGS` → `ACTION_SETTINGS` | `isDefaultLauncher()` (Home role) | Essential, after #2 | – | Not shown |
| 2 | **Home Button Fix** (`LauncherAccessibilityService`) | Home opens Hearth. Also how Hearth notices profile switches, kids' profiles, bedtime / screen time, pop-ups over apps, Sleep when idle, remote-button remapping | Bounce: `ACTION_ACCESSIBILITY_SETTINGS`, list only (`ACCESSIBILITY_DETAILS_SETTINGS` doesn't resolve on Google TV): *Services* → *Hearth Home Button Fix* → Enable → OK | `getHomeButtonFixStatus()` → `enabled`, `seenBefore`, `listedButStopped`, `restricted` | **Essential** | Self-adb or a computer: `settings put secure enabled_accessibility_services …` | Not shown |
| 3 | **Restricted settings** | Not a feature. Android 13+ greys out accessibility switches for an APK installed from a downloaded file. Google TV has no "Allow restricted settings" item | Only adb (self-adb or a computer), or a store-style session install (`SessionInstaller`, `PACKAGE_SOURCE_STORE`) | The install source (LOCAL_FILE / DOWNLOADED_FILE), unless Hearth lifted the block itself on this install. Apps can't read the `ACCESS_RESTRICTED_SETTINGS` app-op (§7.3) | Blocks #2 and #4 | `appops set <pkg> ACCESS_RESTRICTED_SETTINGS allow`; the "Hearth Setup" installer (§9) avoids it | – |
| 4 | **Profile Pairing** (`ProfilePairingService`) | Netflix, Disney+, Apple TV, Max and Paramount+ open on the right profile | Bounce: same Accessibility list, *Hearth Profile Pairing* | `getProfilePairingStatus().enabled` | Optional | Same as #2 and #3 | Not shown |
| 5 | **Hearth voice** (TTS engine) | Lets Profile Pairing hear Netflix's profile screen. Other apps keep Google's voice | Bounce: `android.settings.TTS_SETTINGS`. Preferred engine → "Hearth voice" → OK | `getProfilePairingStatus().voiceDefault` | Optional, **only if Netflix is installed** | Per kids' user: `settings put --user N secure tts_default_synth …` | – |
| 6 | **Notification access** (`LauncherNotificationListenerService`) | Notifications bell, "what's playing", music info sent to Home Assistant | Bounce: `ACTION_NOTIFICATION_LISTENER_SETTINGS` (detail screen first where it exists) | `checkNotificationListenerPermission()` | Optional | `cmd notification allow_listener …` | – |
| 7 | **Pop-ups over other apps** (overlay) | Notification pop-ups over any app | Bounce: `ACTION_MANAGE_OVERLAY_PERMISSION` | `checkOverlayPermission()` | Optional, left in Settings | `appops set … SYSTEM_ALERT_WINDOW allow` | – |
| 8 | **Install apps / updates** | Hearth updates itself and installs and updates HearthTube | Bounce: `ACTION_MANAGE_UNKNOWN_APP_SOURCES` + `package:` | `checkInstallPermission()` | Optional, recommended | – | – |
| 9 | **Continue Watching** (Watch Next permission) | A row of what you were watching | **In-app** runtime permission dialog (`requestWatchNextPermission`) | `checkWatchNextPermission()` + `showContinueWatching` | Optional | `pm grant <pkg> com.android.providers.tv.permission.READ_WRITE_WATCH_NEXT_PROGRAMS` | The profile's own list |
| 10 | **Search** | Films and shows, "Watch on…" from TMDB | Nothing: the TMDB key is built into releases | – | Works already. Explained only | – | Adult titles already filtered |
| 11 | **Parent PIN** | Locks Hearth's Settings and app menus in kids' profiles; needed for saving streaming-app PINs | In-app: `ParentPinDialog` row pad, entered twice | `SettingsService.hasParentPin` | Optional, strongly suggested with kids' profiles | – | Kids see the pad when they open Parent settings |
| 12 | **Hearth on other profiles** (self-adb) | Hearth and HearthTube stay installed in kids' profiles, where Google TV would otherwise uninstall them at each profile start | In-app *Add* (`addHearthToProfiles`). Needs ADB debugging on, Hearth reaching `127.0.0.1:5555`, and the one-time **"Allow debugging?" → Always allow** | `getHearthProfilesState()` (throws until approved) | Optional, **only with kids' profiles** | `pm install-existing` + block-uninstall per profile | Kids' copy runs as the agent |
| 13 | **Look** | Card style, accent colour, wallpaper, dock | In-app (`LookSettingsPage` and its pages) | Settings values | Optional (defaults are good) | – | Kids change their own look in Settings. First visit gets Bing wallpaper |
| 14 | **Weather** | Weather in the top bar | In-app `WeatherLocationDialog` (Open-Meteo, no account) | Location set | Optional | – | – |
| 15 | **Home Assistant**: pop-ups | Doorbell, laundry etc. over any app | In-app toggle; in HA, "Notifications for Android TV / Fire TV" with the TV's address (port 7676) | `getHaNotificationsEnabled()` | Optional | – | Parent only |
| 16 | **Home Assistant**: dashboard panel | An HA dashboard slides in from the right | Phone QR (`HaPhoneSetupDialog`) or typed token | `getHaPanelConfig()` has a token | Optional | – | Parent only |
| 17 | **Home Assistant**: TV status | Reports app, playing, profile and screen time to an HA webhook | Phone QR page (address + webhook id), or typed in `HaStatusPage` | `getHaStatusConfig()` | Optional | – | – |
| 18 | **Sleep when idle** | TV goes to standby after N minutes with no remote presses (playing counts as activity) | In-app (`setIdleStandbyMinutes`) | `getIdleStandbyMinutes()` | Optional (default Off) | – | – |
| 19 | **Screensaver** | Google's Ambient mode (photos) | Bounce: `openScreensaverSettings()` | Can't be read | Optional | – | – |
| 20 | **Start on boot** | Hearth comes up after a restart | In-app switch (`setStartOnBoot`) | `startOnBoot` | On for everyone | – | – |
| 21 | **HearthTube + automatic updates** | YouTube app that follows Hearth's profiles, clock and bedtime | In-app (`UpdatesPage`, `CompanionUpdater`, session installer) | `getPackageVersion`, `isInstalledByHearth`, `autoUpdateEnabled()` | Optional | – | Through #12 |
| 22 | **Language** | Hearth's language, or the TV's | In-app `AppLanguagePage` | `appLocale` | Optional | – | – |
| 23 | **Backup** | Restore a saved setup | In-app `BackupRestorePage` | – | Optional (on Welcome) | – | – |
| 24 | Remote buttons, Back action, sections, usage access, overlay | Power-user settings | In Settings | – | Not in the flow. Mentioned on Finish | – | – |

Notes from the code that shape the flow:
- **Google TV can't jump to a single switch**, so each bounce step shows a short "what you'll see" picture first.
- **Changing accessibility services can make Google TV show its "Who's watching?" chooser.** The copy warns about it.
- **Without #2, Hearth doesn't know which profile is active or whether it's a kids' profile** (`service_running` = 0
  in the provider contract). That's why it's the first essential.
- `device_` keys in SharedPreferences are shared across profiles and never part of a per-profile layout
  (`BackupService.isDeviceLevelKey`). Setup state lives there, and is also kept out of full backups (§4.1).

---

## 2. Principles

1. **Built for the remote.** One decision per screen. The main button has focus when a screen opens. Left/Right moves
   between at most three buttons; Up reaches "Finish later". No typing unless a feature truly needs it (weather town),
   and the phone QR comes first wherever it exists.
2. **Few screens.** Essentials are 2 screens (plus a help screen only when something goes wrong). Each optional group is
   **one card**, and its steps appear only after "Turn on". The flow never asks for something that's already granted.
3. **Everything skippable and revisitable.** Every screen has *Not now* or *Skip*. Finish says where each thing lives in
   Settings, and Settings → System → **Set up Hearth** runs the flow again.
4. **Plain language.** Say what it does for the family ("The Home button opens Hearth"), not the mechanism
   ("accessibility service"). Android's own labels appear only where the user must find them on Android's screen, in
   quotes, exactly as Android shows them.
5. **Works with nothing granted.** The flow runs before Home Button Fix exists, so it can't rely on the Home key,
   profile detection or the overlay. It assumes the person at the TV is the owner.
6. **Resumable.** Leaving for an Android screen, pressing Home, a crash or a reboot all return to the same step, with its
   result checked again from the TV's state.
7. **Honest about what needs a computer, and about what Hearth does for you.** When Android blocks a switch, say so,
   offer the one adb command, and say what still works without it. When debugging is on, Hearth can run the named fix
   itself, but only after showing what it will run and the parent choosing to go ahead.
8. **The parent stays in charge.** Nothing here is reachable from a kids' profile without the parent PIN, and family
   features are explained before anything is installed in a child's profile.

---

## 3. The flow

### 3.1 Map

```
Welcome ──► E2 Home button ──(blocked?)──► E2R "Android blocked this switch"
                  │                                   │
                  ▼                                   ▼
              E1 Home app
                  │
                  ▼
   ┌──── optional cards, in this order; each: [Not now] [Turn on] ────┐
   │ F1 Your family   → PIN → Profile Pairing → (Hearth voice) → (Kids' profiles)
   │ F2 Watching      → Continue Watching (dialog) → What's playing (notification access)
   │ F3 Your home     → pick a look (the card is the choice) → weather
   │ F4 Smart home    → pop-ups → dashboard (phone QR) → TV status (phone QR)
   │ F5 TV & power    → sleep when idle (the card is the choice), start on boot, screensaver link
   │ F6 Updates       → allow installs → HearthTube + automatic updates
   └───────────────────────────────────────────────────────────────────┘
                  ▼
               Finish
```

The Home button (E2) comes before the home app (E1): it's the step that makes Hearth the TV's home in practice on
Google TV, and it's what lets Hearth tell profiles apart.

Cards are hidden when they don't apply:
- **F1** shows only on Google TV (`launcherx` installed). Its Hearth voice step needs Netflix installed; its kids'
  profiles step needs at least one kids' profile: a profile user Android lists for Hearth that Family Link supervises
  (`ProfileUsers.isSupervised`). There is no "Do any kids use this TV?" question.
- **F4** always shows ("Do you use Home Assistant?").

**Progress strip:** across the top of every screen: `Essentials ● ●   Family ○   Watching ○   Home ○   Smart home ○
TV ○   Updates ○`. ● = done or on, ◌ = skipped, ○ = to come, ◉ = here. It isn't focusable.

**Frame:** a full-screen route (`SetupFlowPage`), not the Settings side panel: a centred card over the dimmed, blurred
home wallpaper (`CachedBlurBackdrop`). Sub-steps reuse the existing Settings widgets inside the same frame.

### 3.2 Screen by screen

**S0 Welcome**
- What Hearth is in one line. **Get started** (focused), **Set up later**.
- Under the buttons, two quiet links:
  - **Language: English (TV's language) ›** opens `AppLanguagePage`, then returns.
  - **Restore from a backup ›** opens `BackupRestorePage`. After a restore, F3 is skipped (the look came with the
    backup) and the flow goes on to the essentials: permissions are never in a backup.
- *Set up later* closes the flow and leaves the home-screen chip (§3.5). The flow doesn't open by itself again.

**E2 The Home button (Home Button Fix)**
- The most important screen. It says what the switch gives the family: the Home button opens Hearth; Hearth follows
  profile switches and kids' bedtime; pop-ups and the sleep timer work.
- A 3-step picture of Android's screen: scroll down to **Services**; select **"Hearth Home Button Fix"**; **Enable**,
  then **OK**.
- **Open Accessibility** (focused) calls `requestAccessibilityPermission()`.
- Before opening, the flow saves where it is and tells the Android side it's waiting for `home_button_fix` (§4.2).
  When `LauncherAccessibilityService.onServiceConnected` fires while it's waiting, Hearth **brings itself back to the
  front** on E2's result.
- Results on return:
  - **On:** "The Home button now opens Hearth." Tick, then on.
  - **Not on, blocked** (`restricted`): E2R.
  - **Not on, `listedButStopped`:** "Android lists it as on, but it isn't running. Turn it off and on again."
  - **Not on, otherwise:** "It's not on yet." **Try again** / **Skip**. Skip asks once: "Without it, the Home button
    opens Google TV, and Hearth can't tell when a kids' profile is in use."
  - **Screen wouldn't open:** the adb command dialog, with **Let Hearth do it** when debugging is on.
- A footer line: "If Google TV asks who's watching afterwards, choose your own profile."

**E2R Android blocked this switch**

Shown after a failed E2 or F1 try when Android may be blocking Hearth's switches: Hearth was installed from a
downloaded or local file and hasn't lifted the block itself since (§7.3 on why it can't read the block directly).
The copy says "if the switch was grey" because it's a strong guess, not a reading. Choices, in this order:
1. **Let Hearth fix it** (only when ADB debugging is on): Hearth shows what it will run (lift the block, then turn on
   Home Button Fix) and runs it through self-adb after the parent confirms. The first time, the TV asks "Allow
   debugging?"; the copy says to choose *Always allow*. This is the same approval F1's kids' step needs, so the parent
   sees it only once.
2. **With a computer:** the `appops` command, the TV's address for `adb connect`, and a short help line. Hearth checks
   every 2 seconds while this screen is open, and moves on by itself once the switch is on.
3. **Skip for now:** what still works (apps, look, search, Continue Watching) and what doesn't (Home button,
   profiles, pop-ups, sleep timer). The home-screen chip keeps a "Home button needs a fix" item.

**E1 Make Hearth the home app** (after E2)
- Skipped when `isDefaultLauncher()` is already true.
- One line on Android's picker, then **Choose Hearth** opens `openDefaultLauncherSettings()`.
- On return the flow checks again: yes → tick and on; no → "Not chosen yet", **Try again** / **Skip**.
- Its reason, "keeps kids' profiles from blocking Hearth", is the existing checklist text and must be confirmed on the
  TV (§8).

**F-cards (generic)**

Each card has an icon and title, a **one-line benefit**, "What's included" (2–4 bullets), **"What it needs"** (Android
switches, typing or a phone, about how long), and **Not now** / **Turn on** (focused).

*Turn on* runs the card's steps one at a time in the same frame. The strip shows `Watching 1/2`. Every step has its own
*Skip*. At the end the flow goes to the next card.
- *Not now* records `notNow` and moves on.
- An already-decided card shows its state ("On" / "Skipped") with **Change** / **Keep**.

**F1 Your family** (Google TV only)
- **Benefit:** "Streaming apps open on the right person, and kids can't change Hearth."
- **F1.1 Parent PIN.** Skipped if one is set. Set and confirm with the row pad (`ParentPinDialog`, the logic of
  `ProfilesSettingsPage._editParentPin` made public).
- **F1.2 Profile Pairing switch.** Same layout as E2, selecting **"Hearth Profile Pairing"**; automatic return when
  `ProfilePairingService` connects; E2R if blocked. On success, a line on name matching ("Alex" goes with "Alex
  Morgan") and **Check pairings ›** (`ProfilePairingPage`).
- **F1.3 Hearth voice.** Only if Netflix is installed and F1.2 is on. Opens `openTextToSpeechSettings()`.
- **F1.4 Kids' profiles.** Only when Android lists a Family Link-supervised profile. Explains what is installed and
  that each kid gets a Family Link "app added" notice.
  - Debugging off (`Settings.Global.ADB_ENABLED` = 0) → **F1.4a "Turn on debugging"**: About → *Android TV OS build*
    7 times → Developer options → *USB debugging*. Detected on return.
  - Then **Add** runs `addHearthToProfiles`, which raises **"Allow debugging?"** (tick *Always allow*, then *Allow*).
    The result shows `FamilyAppsPage`'s per-profile rows.
  - Debugging stays on: the copy says Hearth needs it again for a new kids' profile and for Remove / Uninstall.

**F2 Watching**
- **Benefit:** "Pick up where you left off, and see what's playing."
- **F2.1 Continue Watching.** **Turn on** asks Android (`requestWatchNextPermission`, a system dialog) and turns the
  row on. Denied: the adb `pm grant` dialog with **Let Hearth do it** when debugging is on. *Not now* leaves the row
  hidden.
- **F2.2 What's playing and notifications.** Opens notification access; the flow is told when `onListenerConnected`
  fires while it's waiting for `notification_access`, and also checks on return. Adb fallback as above.
- **Search** is one info line on the card ("Search already works: press 🔍 on the home screen").

**F3 Your home** (the card *is* the decision)
- Four **looks** as large focusable tiles; focusing one previews it live behind the card:

  | Look | Cards | Accent | Wallpaper | Dock |
  |---|---|---|---|---|
  | **Hearth** (default) | Default | Purple | "Faraway River" gradient | Frosted |
  | **Photo of the day** | Premium | (kept) | Bing photo of the day | Frosted |
  | **Calm dark** | Minimal | White | Pitch black (OLED) | Dark |
  | **Bold** | Glow | Pink | "African Field" gradient | Frosted |

- **Use this look** or **Keep current**. **Customize ›** opens `LookSettingsPage` in the frame.
- The chosen look also becomes the starting look for **new adult profiles** (kids' profiles keep their own first look,
  Bing's photo).
- **F3.1 Weather:** "Show the weather?" → `WeatherLocationDialog` → **Skip**.

**F4 Smart home (Home Assistant)**
- **Benefit:** "Doorbell and other alerts on the TV, and your dashboard one press away." Buttons: **I use Home
  Assistant** / **Not now**.
- **F4.1 Pop-ups.** Turns on `setHaNotificationsEnabled(true)`, shows the integration name and this TV's address
  (e.g. 192.0.2.10), **Send a test**.
- **F4.2 Dashboard.** **Set up from your phone** (`HaPhoneSetupDialog`). Hint: a non-admin HA user made for the TV.
- **F4.3 TV status.** The phone page also takes the status address and webhook id, so nothing is typed on the TV.

**F5 TV & power** (the card *is* the decision)
- "Turn the TV off when nobody's watching?": **Off · 1 hour · 2 hours · 4 hours**. Without Home Button Fix the choices
  are greyed with a note pointing back to E2.
- **Start Hearth when the TV starts** (on; the default for everyone).
- **Choose screensaver photos ›** opens `openScreensaverSettings()`.

**F6 Updates**
- **Benefit:** "Hearth keeps itself and its companion apps up to date."
- **F6.1 Allow installs.** Skipped if already allowed. "Find Hearth and turn it on, then press Back."
- **F6.2 HearthTube.** "Install HearthTube?" with its description, **Install** (session installer) / **Not now**, then
  **Update automatically** (on).

**S9 Finish**
- "Hearth is ready." Two lists: **On** and **Set up later** (each with where it is in Settings).
- "More in Settings: remote buttons, sections, notifications and backup."
- **Go to my home** (focused) / **Open Settings**.
- Saves the flow version, clears the resume point and the chip.

### 3.3 Reuse summary

| Flow step | Existing code reused |
|---|---|
| E1, E2, F1.2, F1.3, F2.2, F6.1 | `SetupStep` + `loadSetupSteps`: the flow and the checklist share one source of steps and done-checks |
| E2R | `homeButtonFixRestricted` text, `showAdbCommandDialog`, `SelfAdb` |
| Lost after an update | Replaces the `HomeButtonFixCheck` dialog (§3.4) |
| F1.1 | `ParentPinDialog`, `_editParentPin` |
| F1.4 | `FamilyAppsPage` actions + status rows, `ProfileAppAccess` / `SelfAdb` |
| F2.1 | `requestWatchNextPermission`, the Continue Watching adb guide |
| F2.2 | `NotificationsService`, the notification access adb guide |
| F3 | `SettingsService` setters, `LookSettingsPage`, `WeatherLocationDialog` |
| F4 | `HaNotificationsPage`, `HaPhoneSetupDialog`, `HaStatusPage` |
| F5 | The idle-standby choices, `openScreensaverSettings`, `setStartOnBoot` |
| F6 | `UpdatesPage`, `CompanionUpdater`, `SessionInstaller` |
| S0 | `AppLanguagePage`, `BackupRestorePage` |

### 3.4 When it runs

| Trigger | What shows |
|---|---|
| **First launch** | No `device_setup_flow_version` and no sign of an earlier setup (Home Button Fix never seen, no parent PIN, no saved layout). Once the first profile check is done, if the profile isn't a kids' profile (or is unknown): the full flow from S0 |
| **Existing install, first build with the flow** | Not the flow. The version is saved, each card is marked from the TV's state (on, or `notNow`), and nothing else shows |
| **Update that adds features** | Each card has `introducedIn` (a flow version). A newer, undecided card shows in the home-screen **chip**, not as a takeover |
| **Update that switched Home Button Fix off** (`seenBefore && !enabled`) | The one full-screen case: E2 worded "The update turned the Home button off", then E2R when blocked. Replaces the old dialog. Shown in an adult profile only; in a kids' profile it waits for an adult one |
| **Rerun** | Settings → System → **Set up Hearth** (the renamed "Setup & permissions"): **Run setup again**, then the checklist rows grouped like the cards. A rerun starts at the essentials, skips what's done, and shows decided cards with **Change / Keep** |
| **Interrupted** | Home pressed, Hearth stopped, or a reboot mid-flow: the flow doesn't take over again by itself, except within 30 minutes of a step that sent the user to Android's settings (§4.2). The chip offers to continue |

**Kids' profiles:** no flow, no chip, no lost-fix screen. A parent who opens Parent settings with the PIN can still run
**Set up Hearth**; the steps act on the TV-wide state.

**Other adult profiles:** on a first visit, after the "Hi <name>" card, one card: "Pick a look for your home" (F3 only;
everything else is TV-wide and already done).

**Unknown profile** (Home Button Fix not on yet): assumed to be the owner.

### 3.5 The home-screen chip

- A small focusable chip in the top bar: **"Finish setting up · 3 left"**, or **"Home button needs a fix"** when the
  Home button was skipped or lost.
- Opens the flow at its resume point (or E2 for the fix).
- Hidden in kids' profiles. Holding OK on it offers **Don't show again** (`device_setup_chip_hidden`). Gone after Finish.

---

## 4. State and resumption

### 4.1 What's stored

All keys use the `device_setup_` prefix: shared by every profile, never in a per-profile layout, and **left out of
backups** (both written and restored), because a restored backup must not claim permissions or choices this TV
doesn't have.

| Key | Type | Meaning |
|---|---|---|
| `device_setup_flow_version` | int | Last flow version finished or dismissed (absent = never) |
| `device_setup_seen_version` | int | Newest `introducedIn` the user has been shown |
| `device_setup_resume` | JSON `{screen, mode, at, closed}` | Where to continue; `closed` once the user chose Finish later. Cleared at Finish |
| `device_setup_decisions` | JSON `{ "watching": {"state": "on\|notNow", "at": …}, … }` | User choices only. **Grants are never stored**: they're read live |
| `device_setup_chip_hidden` | bool | Chip dismissed |
| `device_setup_look` | string | The look chosen in F3, the starting look for new adult profiles |

**Android side**, in its own prefs file (`hearth_setup`), read by the services: `waiting_for` (`home_button_fix` /
`profile_pairing` / `notification_access`) and `waiting_since` (ignored after 15 minutes).

### 4.2 Surviving a bounce to Android's settings

1. Before opening a screen, the flow saves its resume point and the Android side's `waiting_for`.
2. **Automatic return:** `LauncherAccessibilityService.onServiceConnected`, `ProfilePairingService.onServiceConnected`
   and `LauncherNotificationListenerService.onListenerConnected` check `waiting_for`. If it matches and is fresh, they
   clear it and start `MainActivity` with `EXTRA_RESUME_SETUP`.
3. **Manual return:** Back from Android's screen resumes Hearth; the step checks again on `resumed`.
4. **Home pressed instead:** with Home Button Fix on, Hearth's home shows with the flow still on top. Without it,
   Google TV's home shows; the next time Hearth opens, a resume point from the last 30 minutes reopens the flow there.
   Otherwise only the chip.
5. **Hearth restarted or rebooted:** the same 30-minute rule.
6. **Google TV's profile chooser** after an accessibility change: the copy warns about it; the flow route survives
   because it sits above the home.

### 4.3 Things granted outside the flow

- Every step's *done* comes from live checks, never from stored decisions.
- When the flow opens it reads them all once: done steps are skipped and shown ●; a card whose steps are all done
  shows "On" with **Keep**; a card left at *Not now* that is now fully on is marked `on`.
- Something revoked later isn't nagged about, except Home Button Fix (essential), which brings back the chip or the
  lost-fix screen.

### 4.4 Self-adb fixes

Once the parent has approved "Allow debugging?" (or is about to, from the flow), Hearth may run these named fixes
through `SelfAdb`, each only after a confirmation that shows the exact commands:

| Fix | Command |
|---|---|
| Lift restricted settings | `appops set <pkg> ACCESS_RESTRICTED_SETTINGS allow` |
| Turn on Home Button Fix / Profile Pairing | `settings put secure enabled_accessibility_services <current>:<pkg>/<service>` and `settings put secure accessibility_enabled 1` |
| Allow Continue Watching | `pm grant <pkg> android.permission.READ_TV_LISTINGS` (the permission Hearth asks for in its dialog) |
| Allow notification access | `cmd notification allow_listener <pkg>/<pkg>.LauncherNotificationListenerService` |

The Android side builds the commands from a fixed list (no command text comes from Flutter), and keeps the other
accessibility services that are already on.

---

## 5. Wireframes

Notes for all screens: 1920×1080; background: the home's wallpaper, blurred and dimmed; card `#0F0F0F`, 20-px radius,
about 1100 px wide; accent = `SettingsService.accentColor` for the focused button, ticks and the current strip dot.
`[ ■ Turn on ■ ]` = focused button.

**Progress strip** (top of every flow screen, not focusable):
```
 Essentials ● ●   Family ○   Watching ○   Home ○   Smart home ○   TV ○   Updates ○        [ Finish later ]
```

### S0 Welcome
```
┌──────────────────────────────────────────────────────────────────────────────────────────────┐
│                                       [ Hearth logo ]                                        │
│                                    Welcome to Hearth                                         │
│             A home screen for the whole family: your apps, what you were watching,           │
│                         and the right profile in every streaming app.                        │
│                       ( Set up later )        [■■ Get started ■■]                            │
│                  Language: English (TV's language) ›      Restore from a backup ›            │
│                              Takes about 5 minutes. Skip anything.                           │
└──────────────────────────────────────────────────────────────────────────────────────────────┘
Focus: Get started (autofocus) ← Set up later. ↓ → Language → Restore. Back = Set up later.
```

### E2 Home button
```
 Essentials ◉ ○   Family ○   …                                                              [ Finish later ]
┌──────────────────────────────────────────────────────────────────────────────────────────────┐
│   Make the Home button open Hearth                                                           │
│   Google TV keeps its own home on the Home button. One switch in Android's settings          │
│   fixes that, and also lets Hearth:                                                          │
│     • follow profile switches and kids' bedtime                                              │
│     • show pop-ups and turn the TV off when idle                                             │
│   On the next screen:                                                                        │
│    ⓵ Scroll down to Services   ⓶ Select "Hearth Home Button Fix"   ⓷ Enable, then OK         │
│   Hearth comes back by itself when it's on. If Google TV asks who's watching, pick yourself. │
│                              ( Skip )        [■■ Open Accessibility ■■]                      │
└──────────────────────────────────────────────────────────────────────────────────────────────┘
Result states (same card, body swapped): ✓ success (auto on after 2 s); not yet (Skip / Try again);
stuck (Skip / Open Accessibility); skip check (Skip anyway / Try again).
```

### E2R Android blocked this switch
```
┌──────────────────────────────────────────────────────────────────────────────────────────────┐
│   ⚠  Android blocked this switch                                                             │
│   If the switch was grey, Android is blocking it because Hearth was installed from a         │
│   downloaded file. The TV has no setting to allow it.                                        │
│   ┌ With a computer ─────────────────────────────────────┐                                   │
│   │ adb connect 192.0.2.10                               │                                   │
│   │ adb shell appops set com.thesiegs.hearth \           │                                   │
│   │      ACCESS_RESTRICTED_SETTINGS allow                │                                   │
│   │ Then turn the switch on. Hearth notices on its own.  │                                   │
│   └──────────────────────────────────────────────────────┘                                   │
│   ( Skip for now )    ( Open Accessibility )    [■■ Let Hearth fix it ■■]*                   │
│   * only when debugging is on; otherwise Open Accessibility has focus                        │
│   Skipping: apps, search and Continue Watching still work. The Home button, profiles,        │
│   pop-ups and the sleep timer don't.                                                         │
└──────────────────────────────────────────────────────────────────────────────────────────────┘
```

### F-card (generic; F2 shown)
```
 Essentials ● ●   Watching ◉   TV ○   Updates ○                                            [ Finish later ]
┌──────────────────────────────────────────────────────────────────────────────────────────────┐
│   Watching                                                                                   │
│   Pick up where you left off, and see what's playing.                                        │
│   What's included                              What it needs                                 │
│    • Continue Watching on the home screen        • One question from Android                 │
│    • Notifications and what's playing            • One switch in Android settings            │
│                                                  • About 1 minute                            │
│   Search already works: press 🔍 on the home screen.                                         │
│                              ( Not now )        [■■ Turn on ■■]                              │
└──────────────────────────────────────────────────────────────────────────────────────────────┘
Decided already: ( Change ) [■ Keep ■] and a status line "On" / "Skipped".
```

### F3 Your home
```
│   Pick a look                         (the home behind the card previews the focused look)   │
│   ┌────────────┐   ┌────────────┐   ┌────────────┐   ┌────────────┐                          │
│   │  Hearth    │   │ Photo of   │   │ Calm dark  │   │   Bold     │                          │
│   └────────────┘   └────────────┘   └────────────┘   └────────────┘                          │
│              ( Keep current )    ( Customize › )    [■■ Use this look ■■]                    │
Focus: first tile (the current look). ←/→ across tiles. ↓ → Use this look.
```

### F5 TV & power
```
│   Turn the TV off when nobody's watching?                                                    │
│   After this long with no remote presses. Playing video or music counts as watching.         │
│        ( Off )   ( 1 hour )   [■ 2 hours ■]   ( 4 hours )                                    │
│   Start Hearth when the TV starts                                       [ ● on ]             │
│   Choose screensaver photos ›                                                                │
│                                                                    [■■ Next ■■]              │
```

### S9 Finish
```
│   ✓  Hearth is ready                                                                         │
│   On                                         Set up later (in Settings)                      │
│    ✓ Home button opens Hearth                 ○ Updates          Settings › System › Updates │
│    ✓ Continue Watching                                                                       │
│   More in Settings: remote buttons, sections, notifications and backup.                      │
│   Run this again anytime: Settings › System › Set up Hearth.                                 │
│                         ( Open Settings )        [■■ Go to my home ■■]                       │
```

### Home-screen chip
```
  ┌───────────────────────────────┐
  │ ⚙ Finish setting up · 3 left  │   12:40  Tue, Oct 8      (top bar)
  └───────────────────────────────┘
```

---

## 6. Copy (English, draft)

| Screen | Title | Body |
|---|---|---|
| S0 | Welcome to Hearth | A home screen for the whole family: your apps, what you were watching, and the right profile in every streaming app. Takes about 5 minutes; skip anything. |
| S0 links | — | "Language: {language} ›" · "Restore from a backup ›" |
| E2 | Make the Home button open Hearth | Google TV keeps its own home on the Home button. One switch in Android's settings fixes that, and also lets Hearth follow profile switches and kids' bedtime. |
| E2 steps | On the next screen | Scroll down to Services. Select "Hearth Home Button Fix". Turn on Enable, then OK. Hearth comes back by itself. If Google TV asks who's watching, choose yourself. |
| E2 done | The Home button now opens Hearth | — |
| E2 not yet | It's not on yet | Try again, or skip and do it later in Settings. |
| E2 stuck | It's on but not running | Android lists it as on, but it isn't running. Turn it off and on again. |
| E2 skip | Skip the Home button? | Without it, the Home button opens Google TV, and Hearth can't tell when a kids' profile is in use. |
| E2 lost | The update turned the Home button off | Android switches it off after some updates. Turn it back on in one step. |
| E2R | Android blocked this switch | If the switch was grey, it's because Hearth was installed from a downloaded file. The TV has no setting to allow it. |
| E2R skip line | — | Apps, search and Continue Watching still work. The Home button, profiles, pop-ups and the sleep timer don't. |
| E2R self-fix | Let Hearth fix it | The TV will ask "Allow debugging?". Choose Always allow, and Hearth will unblock its switch and turn it on. |
| E1 | Make Hearth your home app | Android will show a list of home apps. Choose Hearth. It keeps kids' profiles from blocking Hearth. |
| E1 done | Hearth is your home app | — |
| F1 | Your family | Streaming apps open on the right person, and kids can't change Hearth. |
| F1.1 | Choose a parent PIN | Kids need it to change Hearth. Pick four digits a child won't guess. |
| F1.2 | Pick the right profile in streaming apps | Hearth chooses each person's profile in Netflix, Disney+, Apple TV, Max and Paramount+. It needs one more switch on the same Android screen: "Hearth Profile Pairing". |
| F1.2 done | Profile Pairing is on | Hearth matches names by itself: "Alex" goes with "Alex Morgan". Each app's profiles appear after its "Who's watching?" screen has shown once. |
| F1.3 | One more step for Netflix | Netflix reads its profile screen aloud, so Hearth listens through its own voice. On the next screen, under Preferred engine, choose "Hearth voice", then OK. Other apps keep Google's voice. |
| F1.4 | Keep Hearth on your kids' profiles | Google TV removes apps it didn't install from kids' profiles each time they start. Hearth can protect itself and HearthTube there. Each child gets one Family Link "app added" notice; undo anytime in Settings. |
| F1.4a | Turn on debugging first | Hearth needs the TV's debugging switch to set up the kids' profiles. On the next screen (About), select "Android TV OS build" seven times. Then in Settings › System › Developer options, turn on USB debugging, and come back. Leave it on: Hearth needs it again for a new kids' profile. |
| F1.4 approve | Allow Hearth on this TV | The TV will ask "Allow debugging?". Tick Always allow, then Allow. You only do this once. |
| F2 | Watching | Pick up where you left off, and see what's playing. |
| F2.1 | Continue Watching | Show what you were watching in your apps on the home screen. Android will ask once; choose Allow. |
| F2.1 denied | Android didn't allow it | You can turn it on later in Settings › Home screen › Continue Watching. |
| F2.2 | What's playing and notifications | See your notifications and what's playing. On the next screen, select "Hearth Notification Service" and allow it. |
| F2 search line | — | Search already works: press 🔍 on the home screen. |
| F3 | Pick a look | You can change any part later in Settings › Home screen. |
| F3 other adult | Pick a look for your home | Each profile has its own home. Choose how yours looks. |
| F3.1 | Show the weather? | Choose your town. Only its location is sent, to Open-Meteo; no account. |
| F4 | Smart home | Doorbell and other alerts on the TV, and your Home Assistant dashboard one press away. |
| F4.1 | Home Assistant alerts | In Home Assistant, add "Notifications for Android TV / Fire TV" with this TV's address: {ip}. Then send a test. |
| F4.2 | Your dashboard on the TV | Scan with your phone, paste your Home Assistant address and a token, then Send. Use a Home Assistant user made for the TV, not an admin. |
| F4.3 | Tell Home Assistant what's on | The TV can send what's playing and the active profile to Home Assistant. Add the address and webhook id on the same phone page. |
| F5 | Turn the TV off when nobody's watching? | After this long with no remote presses. Playing video or music counts as watching. |
| F6 | Updates | Hearth keeps itself and its companion apps up to date. |
| F6.1 | Allow Hearth to install updates | On the next screen, find Hearth and turn it on, then press Back. |
| F6.2 | Install HearthTube? | A YouTube app made for Hearth: it follows your profiles, the clock style and kids' bedtime. |
| S9 | Hearth is ready | Anything you skipped is in Settings, and you can run this again from Settings › System › Set up Hearth. |
| Chip | Finish setting up · {n} left | — |
| Chip (fix) | Home button needs a fix | — |
| Settings row | Set up Hearth | Run setup again, or see what's on. |

---

## 7. Decisions (2026-10-09)

1. **Self-adb fixes: yes.** After "Allow debugging?" is approved, Hearth may run the named fixes of §4.4, each with a
   visible confirmation.
2. **Debugging stays on.** The flow doesn't suggest turning it off; it says Hearth needs it again for a new kids'
   profile and for Remove / Uninstall.
3. **Restricted detection: the real app-op**, asked for, but not possible: Android 13+ marks
   `ACCESS_RESTRICTED_SETTINGS` as an app-op apps may not read, their own included (`unsafeCheckOpNoThrow` throws
   "uid … does not have android.permission.MANAGE_APPOPS" on the Android 14 emulator). So E2R goes by the install
   source, and Hearth remembers when it lifted the block itself (self-adb) for the current install. A reading through
   self-adb (`appops get`) would work once debugging is approved, but connecting would raise "Allow debugging?" just
   to check, so it isn't done.
4. **"Hearth Setup" bootstrap installer: yes**, before any public release (§9).
5. **Default-home step: kept**, after E2, once its reason is confirmed on the TV.
6. **Kids' profiles are detected through Family Link supervision** of the profile users Android lists; no question.
7. **Looks:** the four of §3.2 F3; the flow's choice becomes the starting look for new adult profiles.
8. **Other adults' first visit:** one "Pick a look for your home" card.
9. **HA TV status from the phone QR page: yes** (address + webhook id).
10. **Defaults when skipped:** Continue Watching stays hidden after "Not now"; Start on boot is on for everyone.
11. **After an update:** only the home-screen chip, unless Home Button Fix was lost (then the full screen).
12. **Kids' profiles:** the lost-fix screen never shows in a kids' profile; it waits for an adult one.
13. **Streaming-app PINs:** Settings only, not in the flow.

---

## 8. Build order

1. **State + frame + essentials.** `device_setup_*` keys (kept out of backups); `SetupFlowPage` (strip, card frame,
   focus, Finish later); S0, E2, E2R, E1, S9; real restricted detection and the self-adb fixes. E1/E2 come from
   `loadSetupSteps`. Widget tests with a fake channel.
2. **Automatic return.** `waiting_for` on the Android side and the three connect hooks starting `MainActivity` with
   `EXTRA_RESUME_SETUP`.
3. **When it runs.** First launch, marking for existing installs, the chip, Settings → System → **Set up Hearth**,
   kids' suppression (including the lost-fix screen).
4. **Easy cards:** F2 Watching, F5 TV & power, F6 Updates.
5. **F3 Your home:** looks with live preview, weather, the starting look for new adult profiles, the other adults'
   first-visit card.
6. **F1 Your family:** PIN, Profile Pairing, Hearth voice, kids' profiles with the debugging guide and self-adb.
7. **F4 Smart home:** wraps the HA pages and phone QR; TV status on the phone page.
8. **"New in Hearth":** the `introducedIn` registry for later cards.

Where the build is (2026-10-09): steps 1 to 8 are built, with widget tests against a fake channel. How it turned out
where it differs from the screens above:
- **Card order on screen:** Essentials, then F1 Family (Google TV only), F2 Watching, F3 Your home, F4 Smart home,
  F5 TV & power, F6 Updates, as in the map.
- **Keep** on a card that's on goes through whatever of it isn't on yet (a skipped step, a kids' profile added since);
  Keep on a skipped card passes it.
- **F1.4** counts as done for as many kids' profiles as Android listed when Hearth was last put on them (from the flow
  or from Settings › Family apps), kept in `device_setup_kids_profiles`: what's on each profile can't be read without
  self-adb, and connecting just to check would raise "Allow debugging?". A kids' profile added later brings the
  family card back into the chip. F1.4a opens Android's About screen directly.
- **F3:** the home behind the card is barely dimmed and not blurred on the look screen, so the preview shows. A picture
  picked as the wallpaper stays in front of a gradient look until that look is chosen (choosing removes it). Customize
  opens Settings' Look page over the flow. Other grown-ups get the look card once the "Hi <name>" card is down.
- **F4.1** turns the pop-ups on with its own **Turn on** button, then offers the test. **F4.3:** the phone page has a
  third, optional field for the webhook ID; a webhook ID alone is enough (no token needed for TV status).
- **"New in Hearth":** a card whose `introducedIn` is newer than `device_setup_seen_version` and that nobody decided
  shows as "New in Hearth: <card>" (or a count) in the chip, even after the chip was hidden; opening or dismissing it
  marks it seen. Adding a card later: give it the next version there and in `SetupFlowService.currentVersion`.

To confirm on the TV:
- The Home role's reason (E1: "keeps kids' profiles from blocking Hearth").
- That a service bound by the system can bring Hearth to the front (automatic return), including the notification
  listener, and that the "Who's watching?" chooser doesn't break it.
- That `settings put secure enabled_accessibility_services` (self-adb) turns on a service whose switch Android
  greyed out, once the block is lifted, as it does from a computer.

---

## 9. The "Hearth Setup" bootstrap installer

A separate, tiny app that makes E2R rare: most new owners install Hearth through the Downloader app, which marks it
"restricted".

- **What it is:** a one-screen TV app ("Hearth Setup", its own app id) that the owner installs with Downloader in place
  of Hearth. It downloads the latest Hearth release APK from GitHub, checks it's signed with Hearth's release key,
  and installs it through a `PackageInstaller` session with `PACKAGE_SOURCE_STORE`, as Hearth's own updater does. An
  app installed that way isn't restricted, so Hearth's switches work.
- **What it needs:** "Install unknown apps" for Hearth Setup (one Android screen; it opens it with the same picture
  guide as F6.1). It never needs accessibility, so its own restriction doesn't matter.
- **After the install:** it opens Hearth (whose first-run flow starts) and offers to remove itself. Hearth's updater
  takes over from then on.
- **Kept small on purpose:** no settings, no background work, no network access beyond GitHub's release API and the
  APK download. The same copy and translations rules as Hearth.
- **Open points:** whether Hearth can update itself without a prompt when Hearth Setup is its installer of record
  (Android lets the installer of record update without asking); where its own APK is hosted (a release asset next to
  Hearth's); and a short Downloader code for it in the README.
