# Hearth's app id: com.leanbitlab.ltvL → com.thesiegs.hearth

Status: built (branch `feature/app-id-change`), not released. Needs an on-TV test before the first release.

Hearth started as a fork of LTvLauncher and kept its app id, `com.leanbitlab.ltvL`, so installs could update in
place. Hearth now has its own: **`com.thesiegs.hearth`** (debug builds `com.thesiegs.hearth.debug`). Android treats
a new app id as a different app, so an existing TV has to *move*: install the new app, bring the data over, turn
its permissions on again, remove the old app. This page is that plan.

## What changed

| | Before | Now |
|---|---|---|
| applicationId | `com.leanbitlab.ltvL` (`.debug`) | `com.thesiegs.hearth` (`.debug`) |
| Java package / namespace | `com.leanbitlab.ltvL` | `com.thesiegs.hearth` (also in the bridge build) |
| Profile provider | `content://com.leanbitlab.ltvL.profile` | `content://com.thesiegs.hearth.profile` |
| FileProvider | `com.leanbitlab.ltvL.fileprovider` | `com.thesiegs.hearth.fileprovider` |
| Accessibility services | `com.leanbitlab.ltvL/.LauncherAccessibilityService`, `/.ProfilePairingService` | `com.thesiegs.hearth/com.thesiegs.hearth.LauncherAccessibilityService`, `…ProfilePairingService` |
| Notification listener | `com.leanbitlab.ltvL/.LauncherNotificationListenerService` | `com.thesiegs.hearth/com.thesiegs.hearth.LauncherNotificationListenerService` |
| TTS engine (Hearth voice) | `com.leanbitlab.ltvL` | `com.thesiegs.hearth` |
| Kids helper (app_process) | `com.leanbitlab.ltvL.KidsBlockUninstallMain` | `com.thesiegs.hearth.KidsBlockUninstallMain` (taken from the class, not a string) |
| Device admin (old protection) | `com.leanbitlab.ltvL/.AgentAdminReceiver` | `com.thesiegs.hearth/.AgentAdminReceiver` |

Unchanged: the signing keys (same release and debug certificates), the MethodChannel/EventChannel names
(`me.efesser.flauncher/...`, they never contained the app id), the provider contract (version 5), the release
asset names (`Hearth-<abi>-release.apk`), the GitHub repo.

`BuildConfig` carries `HEARTH_APP_ID`, `LEGACY_APP_ID` and `BRIDGE`; Dart has the same in `lib/hearth_ids.dart`.
Commands shown in the app (Setup & permissions, notifications, Home Button Fix) name components as
`<app id>/com.thesiegs.hearth.<Class>`, which is right in release, debug and bridge builds.

## The pieces of the move

### 1. The bridge build (old id, hands its data over)

The same code built under the old id: `-PhearthBridge=true` for Gradle, or `HEARTH_BRIDGE=true` in the environment
(`flutter build` passes the environment through). In the release workflow: run it by hand with **bridge** ticked;
its assets are named `Hearth-bridge-<abi>-release.apk`.

```sh
HEARTH_BRIDGE=true flutter build apk --release --target-platform android-arm --dart-define=TMDB_API_KEY=...
```

The bridge build differs from a normal one only in:
- `applicationId com.leanbitlab.ltvL`, so it updates the old app in place (same signature, higher version);
- `LegacyExportProvider` is enabled (manifest placeholder `legacyExportEnabled`), at
  `content://com.leanbitlab.ltvL.legacyexport`. `/files` lists every file under Hearth's data folders
  `shared_prefs/`, `app_flutter/`, `files/`, `databases/` (see `LegacyMove.movable`), and `/file?path=…` opens one
  read-only. **Only `com.thesiegs.hearth` may call it** (`.debug` from a debug bridge), and only when
  `PackageManager.checkSignatures` says it is signed with the same certificate; anyone else gets a
  `SecurityException`. No permission is declared, so install order doesn't matter;
- its updater's "update" is the new Hearth (`expectedUpdatePackage`), installed through the session installer
  (store-sourced, so Android doesn't mark the new app "restricted");
- at each start it shows "Hearth is moving": install the new Hearth (opens Settings → Updates), or, once installed,
  **Open the new Hearth**.

Because the Java package is now `com.thesiegs.hearth`, the bridge's components are named
`com.leanbitlab.ltvL/com.thesiegs.hearth.X`. Android drops the old app's accessibility services, notification
listener and device-admin grant when it updates to the bridge (they named classes that no longer exist). That's
fine for the few minutes the bridge is in charge: the new Hearth gets them instead. Until then the Home button goes
to Google TV.

### 2. The import (new id)

`HearthApplication.onCreate` → `LegacyMove.runIfDue` runs at every process start, before anything reads a setting
or opens the database, and does something only when:
- this is the new id (not the bridge), in the owner's user (not a profile's agent), and
- it has never decided before (`shared_prefs/hearth_move.xml` has no state) and this Hearth has no data of its own
  yet (no `FlutterSharedPreferences.xml`, no `app_flutter/db.sqlite`), **or** Settings asked for it.

It then asks `com.leanbitlab.ltvL[.debug]` for `/files`, copies each file into a staging folder, and only when all
arrived replaces its own folders with them, so a failure leaves the new Hearth as it was.

| Moves | Stays behind / reset |
|---|---|
| Every setting (Flutter's prefs), sections, apps, spacers (the database) | `ltv_agents`, `ltv_agent`, `ltv_agent_wallpaper`: agent keys and state for other profiles; the new agents get new ones |
| Per-profile layouts and settings (`app_flutter/profile_layouts`) | `hearth_wallpaper`: what was sent to the agents (sent again) |
| Wallpapers, per-profile picture folders, profile avatars | caches (posters, icons cache), WebView data (the HA panel signs in again only if it used cookies) |
| Profile Pairing choices, profile users, profile lock, screen time state | Streaming-app PINs: see below |
| Home Assistant (URL, token, status/notification settings: `ltv_device`), remote button mappings | The "Home Button Fix was on" flag (the move notice asks instead) |
| Parent PIN (a hash in Flutter's prefs), weather, idle standby | |
| Hearth's own adb key (`files/selfadb`), so the TV doesn't ask "Allow debugging?" again | |

**PINs.** `PinVault` seals each streaming-app PIN with a non-exportable Android Keystore key, which belongs to the
old app and can't leave it. The import keeps each entry without its sealed PIN, status `reenter`: Profile Pairing
shows "Enter it again (Hearth moved)", never types it (`PinVault.has` is false), and the pad opens straight away to
enter it again. The parent PIN itself moves (it's a hash, not a Keystore secret).

Outcomes, kept in `hearth_move.xml` and shown by `HearthMoveCheck` once:
- `imported`: "Hearth has moved": what came over, how many PINs to enter again, and buttons **Setup &
  permissions** and **Remove the old Hearth**;
- `unavailable`: the old Hearth is installed but has no export (not the bridge yet) or refused: update it to the
  bridge, then Settings → Backup & restore → **Bring over from the old Hearth**;
- `failed`: the reason, and the same retry;
- `none`: no old Hearth when the new one first started (or it was already set up).

Backup & restore shows **Bring over from the old Hearth** and **Remove the old Hearth** while the old app is on
the TV. Bringing over again sets the state to `requested` and restarts Hearth through `RestartActivity` (a
`:restart` process), so the import again runs before anything has read a setting; it replaces the new Hearth's data.

### 3. Removing the old Hearth

**Remove the old Hearth** (`ProfileAppAccess.replaceLegacy`, through Hearth's own adb, with the parent's PIN in a
kids profile): for each other profile user that has the old Hearth, install the new one there
(`pm install-existing`), give it the keep-installed flag if the old one had it, lift the old one's flag, uninstall
the old one from that user; then `pm uninstall com.leanbitlab.ltvL`. Without Hearth's own adb it opens Android's
uninstall screen for the old app instead; the old copies in other profiles then remove themselves (their agent
sees the owner's old Hearth gone, `AgentService.maybeSelfClean`), and the new Hearth is added to those profiles in
Settings → Profiles → Family apps.

### 4. Updates from now on

- The new Hearth's updater ignores assets with "bridge" in the name (`isHearthUpdateAsset`) and installs a
  download only when `PackageManager.getPackageArchiveInfo` says it is `com.thesiegs.hearth`
  (`UpdateError.wrongApp` otherwise). It never offers the old id's APK.
- The bridge build's updater offers the newest non-bridge release, i.e. the new Hearth, and checks that the APK is
  `com.thesiegs.hearth` too.
- Hearth from before the bridge (2026.10.05 and older) picks *any* APK of the newest release for its ABI. If the
  first new-id release comes out before a TV is on the bridge, that TV installs the new Hearth beside the old one
  without its data (the new one then says the old one is too old to hand over). So: **release the bridge first,
  get every TV onto it, then release the new id.**

## Release plan

1. Merge this branch. Bump the version (`pubspec.yaml`), changelog `fastlane/metadata/android/en-US/changelogs/<code>.txt`.
2. **Bridge release** `vYYYY.MM.DD` (e.g. v2026.10.12): Actions → Release APK → Run workflow, tag name, **bridge**
   ticked. Assets: `Hearth-bridge-{universal,armeabi-v7a,arm64-v8a}-release.apk`. TVs on Hearth ≤ 2026.10.x update to
   it in place from Settings → Updates.
3. Once every TV is on the bridge: **new-id release** with a higher version (e.g. `vYYYY.MM.DD` a day later, or the
   same date with `+build`), normal tag push or Run workflow without bridge. Assets `Hearth-<abi>-release.apk`.
4. On each TV: the bridge offers the new Hearth; install, open, follow the move notice (below).
5. Release HearthTube with the two-authority support (section below) before or with step 3; until then HearthTube
   only sees the old Hearth, which stops answering once removed.

## Moving a TV (exact steps)

Example TV address 192.0.2.10; use the TV's own. Before starting: **Settings → Backup & restore → Export backup**
in the old Hearth (the rollback below needs it).

### A. In the app (the normal way)

1. Old Hearth → Settings → Updates → Hearth → install the bridge version (it updates in place).
2. Bridge: "Hearth is moving" → Updates → Hearth → install the new Hearth (Android asks once: it's a new app).
3. Bridge: "Open the new Hearth". The new Hearth copies everything as it starts and shows "Hearth has moved".
4. **Setup & permissions** in the new Hearth, turn on each step (see the list in C).
5. "Hearth has moved" (or Backup & restore) → **Remove the old Hearth**.
6. Profile Pairing → enter the streaming PINs again (the ones marked "Enter it again").
7. Restart the TV once (the new Hearth takes over the Home Assistant notification port 7676 and the phone setup
   ports from the old one, which held them until it was removed).

### B. By adb (sideloading)

```sh
adb connect 192.0.2.10:5555
# 1. the bridge over the old Hearth (same key: an in-place update)
adb install -r Hearth-bridge-armeabi-v7a-release.apk
# 2. the new Hearth
adb install Hearth-armeabi-v7a-release.apk
# 3. start it once: it imports as it starts
adb shell am start -n com.thesiegs.hearth/com.thesiegs.hearth.MainActivity
adb logcat -d -s HearthMove     # "moved N files (… bytes) from com.leanbitlab.ltvL …; K PINs to enter again"
```

### C. What the new Hearth needs again (each is per app id)

Setup & permissions lists them with their status; the adb equivalents:

```sh
P=com.thesiegs.hearth
# Android 13+: only if the accessibility switches are greyed out ("restricted setting")
adb shell appops set $P ACCESS_RESTRICTED_SETTINGS allow
# Home Button Fix + Profile Pairing (check what's on first: this REPLACES the list)
adb shell settings get secure enabled_accessibility_services
adb shell settings put secure enabled_accessibility_services $P/$P.LauncherAccessibilityService:$P/$P.ProfilePairingService
adb shell settings put secure accessibility_enabled 1
# Notifications
adb shell cmd notification allow_listener $P/$P.LauncherNotificationListenerService
# Hearth voice as the text-to-speech engine
adb shell settings put secure tts_default_synth $P
# Install unknown apps (self-update, HearthTube), usage access, overlays
adb shell appops set $P REQUEST_INSTALL_PACKAGES allow
adb shell appops set $P GET_USAGE_STATS allow
adb shell appops set $P SYSTEM_ALERT_WINDOW allow
# Continue Watching from the profiles' users (only if it was granted to the old Hearth)
adb shell pm grant $P android.permission.INTERACT_ACROSS_USERS
# Home app, where the TV allows another one (most Google TVs don't: Home Button Fix covers it)
adb shell cmd role add-role-holder android.app.role.HOME $P
```

Kids profiles (only when "Remove the old Hearth" couldn't use Hearth's own adb), for each profile user N
(`adb shell pm list users`):

```sh
NEW=$(adb shell pm path com.thesiegs.hearth | tr -d '\r' | cut -d: -f2)
adb shell pm install-existing --user N com.thesiegs.hearth
adb shell CLASSPATH=$NEW app_process /system/bin com.thesiegs.hearth.KidsBlockUninstallMain com.thesiegs.hearth N true
adb shell CLASSPATH=$NEW app_process /system/bin com.thesiegs.hearth.KidsBlockUninstallMain com.leanbitlab.ltvL N false
adb shell pm uninstall --user N com.leanbitlab.ltvL
```

Then the old Hearth, everywhere:

```sh
adb shell pm uninstall com.leanbitlab.ltvL
```

Also check: Home Assistant automations or dashboards that name Hearth's package (`com.leanbitlab.ltvL`) need the
new one; Hearth's webhook and token themselves move unchanged. HearthTube was installed by the old Hearth, so the
new Hearth's first HearthTube update asks once (Android's "installer of record" is still the old app).

## HearthTube: what to change (separate repo, not changed here)

HearthTube trusts Hearth by package name + signing certificate and reads `content://com.leanbitlab.ltvL.profile`.
During the transition a TV has the old Hearth, the new one, or (for a few minutes) both. HearthTube should:

1. **Package visibility** (AndroidManifest `<queries>`): add `<package android:name="com.thesiegs.hearth" />` and
   `<package android:name="com.thesiegs.hearth.debug" />` next to the existing `com.leanbitlab.ltvL` entries.
   Without it Android hides the new Hearth from HearthTube and nothing below works.
2. **Trusted Hearth packages**: `com.thesiegs.hearth`, `com.leanbitlab.ltvL` (and both `.debug` in debug builds),
   with the **same certificate check** as today (release
   `0438047b1a5eefe8693cad8f2b57189a418337bbcbd3c7dbdb79d20884beaf6e`, debug
   `6748528ff4d17fd57c30b6c5d522c467920d9951ea5d208597f91b66df9a2bfe`, SHA-256 of the signing certificate).
3. **Provider**: authorities in order of preference `com.thesiegs.hearth.profile`, then
   `com.leanbitlab.ltvL.profile` (debug: the `.debug.profile` ones). Use the first for which
   `PackageManager.resolveContentProvider(authority, 0)` returns a `ProviderInfo` whose `packageName` is a trusted
   Hearth package with a trusted certificate. Prefer the new one even when both answer. `query(/active)`,
   `openFile(/wallpaper)`, `call("verify_parent_pin")` and the `/active` observer all go to that authority.
4. **Re-pick** the authority when it stops answering or a package changes (re-resolve on `onResume`, or on
   `ACTION_PACKAGE_ADDED`/`ACTION_PACKAGE_REMOVED` for those packages), moving the content observer with it, so
   HearthTube follows the TV from the old Hearth to the new one without a restart.
5. **Launched from Hearth**: `Activity.getLaunchedFromPackage()` and the HOME-resolve check accept any trusted
   Hearth package.
6. Nothing else changes: same columns, same contract version (5), same meaning of `updates_hearthtube`. Once every
   TV has moved, the old package and authority can be dropped in a later HearthTube release.

## Rollback

- **Before "Remove the old Hearth"**: nothing of the old app was changed except that it's the bridge build. Uninstall
  the new one (`adb shell pm uninstall com.thesiegs.hearth`) and keep using the bridge; it is the old Hearth, with
  its own data. Turn its services on again; note their names are now
  `com.leanbitlab.ltvL/com.thesiegs.hearth.LauncherAccessibilityService` (and `…ProfilePairingService`,
  `…LauncherNotificationListenerService`).
- **After the old one is removed**: reinstall an old-id release (the bridge, or 2026.10.05) with `adb install`, and
  restore the backup exported before the move (Backup & restore → Import backup). Native settings that the backup
  doesn't carry (Home Assistant, Profile Pairing choices, button mappings) have to be set again, as do the PINs.
- **A bad new-id release**: fix forward; an old-id APK can't update the new app (different app id).

## On-TV test plan

Use a spare TV or the emulator first if possible. With a backup exported:

1. Old Hearth 2026.10.x on the TV with: a few sections, a profile with its own layout and wallpaper picture, Profile
   Pairing set for one app with a saved PIN, Home Assistant set up, a parent PIN, HearthTube installed, Hearth added
   to a kids profile.
2. Install the bridge (`adb install -r Hearth-bridge-…apk`). Expect: same home, same data; "Hearth is moving" at
   start; Home Button Fix and the notification listener are off (expected). `adb shell dumpsys package
   com.leanbitlab.ltvL | grep -i legacyexport` shows the provider.
3. A third-party app can't read the export: `adb shell content query --uri content://com.leanbitlab.ltvL.legacyexport/files`
   must fail with "only handed to the new Hearth" (shell isn't the new Hearth).
4. Updates → Hearth offers the new-id release (or `adb install` it). Open it from the bridge's dialog.
   `adb logcat -d -s HearthMove` shows the file count. Expect "Hearth has moved" with the right old version and PIN
   count; sections, per-profile layouts and wallpapers, Profile Pairing choices, HA (send a test notification after
   step 6), parent PIN, weather all as before.
5. Setup & permissions: turn everything on (as a store-sourced session install the accessibility switches should
   not be greyed out). Check Home, profile switch detection, notifications, Hearth voice.
6. Remove the old Hearth: kids profile now has `com.thesiegs.hearth` (kept: `KidsBlockUninstallMain … com.thesiegs.hearth N`
   prints `blockUninstall=true`) and no `com.leanbitlab.ltvL`; `adb shell pm list packages com.leanbitlab` is empty.
   Restart the TV; HA notifications arrive.
7. Profile Pairing shows "Enter it again (Hearth moved)" for the saved PIN; enter it; opening the app types it.
8. Switch to the kids profile: the new Hearth's agent connects (Continue Watching for that profile, its wallpaper);
   Google TV doesn't remove it at the next profile start.
9. Updates → Hearth: "up to date" (no bridge APK offered). HearthTube: with the updated HearthTube it follows the
   new Hearth (profile, wallpaper, parent PIN); with the old HearthTube it falls back to its own behaviour.
10. (Before step 6.) Backup & restore → Bring over from the old Hearth appears while the old app is installed;
    using it restarts Hearth and replaces its data with the old Hearth's again.
