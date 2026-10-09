# Hearth's app id: com.leanbitlab.ltvL → com.thesiegs.hearth

Status: done (2026-10-09). The only TV running Hearth was moved by hand; the bridge build and the import were then
removed from the code.

Hearth started as a fork of LTvLauncher and kept its app id, `com.leanbitlab.ltvL`, so installs could update in
place. Hearth now has its own: **`com.thesiegs.hearth`** (debug builds `com.thesiegs.hearth.debug`), with the Java
package renamed to match. The signing key didn't change.

## What changed

| | Before | Now |
|---|---|---|
| App id | `com.leanbitlab.ltvL` | `com.thesiegs.hearth` |
| Java package / namespace | `com.leanbitlab.ltvL` | `com.thesiegs.hearth` |
| HearthTube's provider | `com.leanbitlab.ltvL.profile` | `com.thesiegs.hearth.profile` (contract unchanged, v5) |
| Components (adb, Settings) | `com.leanbitlab.ltvL/com.leanbitlab.ltvL.X` | `com.thesiegs.hearth/com.thesiegs.hearth.X` |

The updater only installs Hearth under its own id (it checks the downloaded APK's package).

## How the TV moved

For a time the code had a "bridge" build: the same code under the old id, which updated the old app in place and
handed its data (shared preferences, app_flutter, files, databases) to the new app through a provider only an app
signed with the same key could read; the new app imported it on its first start. With a single TV, the move was
done by adb:

1. Install the bridge over the old Hearth; install the new Hearth and start it once (it imported its data).
2. Turn the new Hearth's permissions on (each is per app id):

   ```sh
   P=com.thesiegs.hearth
   adb shell appops set $P ACCESS_RESTRICTED_SETTINGS allow
   adb shell settings put secure enabled_accessibility_services $P/$P.LauncherAccessibilityService:$P/$P.ProfilePairingService
   adb shell settings put secure accessibility_enabled 1
   adb shell cmd notification allow_listener $P/$P.LauncherNotificationListenerService
   adb shell settings put secure tts_default_synth $P
   adb shell appops set $P REQUEST_INSTALL_PACKAGES allow
   adb shell pm grant $P android.permission.READ_TV_LISTINGS
   adb shell cmd role add-role-holder android.app.role.HOME $P
   ```
3. In each kids profile's user N: `pm install-existing --user N com.thesiegs.hearth`, keep it installed
   (`KidsBlockUninstallMain com.thesiegs.hearth N true` via `app_process`), lift the old one's flag and
   `pm uninstall --user N com.leanbitlab.ltvL`.
4. `adb shell pm uninstall com.leanbitlab.ltvL`.

Streaming-app PINs can't move between app ids (they're sealed with the app's Keystore key); none were saved.

## Another TV still on the old id

Install Hearth (it starts empty), set it up again or restore a backup made with the old Hearth's Backup & restore,
turn on the permissions above, then uninstall the old app. The bridge is in the history (commits 69aa9b2 and
87e0921) if a data hand-over is ever needed again.

## HearthTube

HearthTube looks for `com.thesiegs.hearth` (and may still accept the old id, which is harmless): same signature
check, provider `com.thesiegs.hearth.profile`, and either id counts as "opened from Hearth".
