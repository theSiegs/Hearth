# Keeping Hearth and HearthTube in kids profiles

Notes from 2026-10-07/08. Android 14 (SDK 34), patch 2026-06-01, onn 4K Pro; kids users 10, 11, 12 (plus a new kid
user 13 being set up). Google TV launcher `com.google.android.apps.tv.launcherx` versionName 1.0.988926538
(versionCode 828391). The removal mechanism below is verified from the launcher's own code (pulled from the device and
disassembled) and from live logcat, not just inference.

## What removes them (verified)

Not Family Link: Google TV's launcher, running in the kid's profile user
(`com.google.android.apps.tv.launcherx:coreservices`, classes `ManagedProfilePackageInstaller`, `TvProfileHelper`,
`TvSystemBackend`, all logging under `b/427107950`). At every profile start (~3 s in) and whenever a package changes,
it reconciles the user's installed apps against a `targetPackagesForProfile` list:

- `TvProfileHelper.setInstalledPackages(targetPackagesForProfile)` /
  `ManagedProfilePackageInstaller.applyPackageInstallToManagedProfile(requiredPackages)`.
- A package in the target set but not installed in the user → `PackageInstaller.installExistingPackage` (the APK
  already lives in user 0, so no download). Log: `calling installExistingPackage for packageName=…`.
- An installed package NOT in the target set → `setPackageInstalled(requestedEnabled=false)`, which reads
  `ApplicationInfo.flags & FLAG_SYSTEM` and branches (log: `disabling/uninstalling packageName=… (isSystem=%b)`):
  - **system** app → `PackageManager.setApplicationEnabledSetting(pkg, DISABLED)` (disabled, not removed);
  - **non-system** app (Hearth, HearthTube) → `PackageInstaller.uninstall(pkg, …)` → `installed=false` for that user.
    There is **no** hide/disable fallback for non-system apps — just the uninstall.

Where the target list comes from: a GMS **supervision** check, not a list on the device we can edit
(`ManagedProfileDelegateService: Check supervision failed`; the launcher calls a `profileApi`). In practice it is the
set of apps approved for the child, which today is sourced from Play.

Watch it live (two devices attached, so `-s`):
```
adb -s <tv> logcat -v threadtime | grep -E "b/427107950|TvProfileHelper|TvSystemBackend|Not removing|Cannot suspend"
```
Per-user state: a non-system app not in the target is `installed=false` for the kid user (`pm list packages --user N`
omits it; `pm list packages -u --user N` still lists it because the APK belongs to user 0). `pm install-existing
--user N <pkg>` puts it back (one Family Link notification each) until that profile next starts.

## What keeps them in — both need adb

Both are set over adb and then persist across reboots (no adb at each boot), but a **new** kid profile needs the step
again — that per-profile adb is exactly the dependency we want to remove.

### Device admin (live now for Hearth)
Hearth holds a no-policy device-admin receiver (`com.leanbitlab.ltvL/.AgentAdminReceiver`) in users 10/11/12
(alongside the GMS profile owner, `com.google.android.gms/.kids.account.receiver.ProfileOwnerReceiver`). An active
admin can't be uninstalled or suspended:
- `DeletePackageHelper` → `DELETE_FAILED_DEVICE_POLICY_MANAGER`; seen live: `PackageManager: Not removing package
  com.leanbitlab.ltvL: has active device admin`.
- `SuspendPackageHelper.canSuspendPackageForUser` → "has an active device admin".

Set with `dpm set-active-admin --user N com.leanbitlab.ltvL/.AgentAdminReceiver`. Downsides: adb per profile; and
because an active admin can't be suspended, Google TV's bedtime suspend can't touch it (Hearth handles bedtime itself
via its own `screen_time_up`).

### Block-uninstall flag (lighter; now tested)
Per-user "block uninstall" flag; no admin receiver, so it also works for HearthTube:
- `PackageManagerService.setBlockUninstallForUser` needs only `DELETE_PACKAGES`, which adb's shell holds
  ([source](https://github.com/aosp-mirror/platform_frameworks_base/blob/android14-release/services/core/java/com/android/server/pm/PackageManagerService.java#L5825),
  [Shell manifest](https://github.com/aosp-mirror/platform_frameworks_base/blob/android14-release/packages/Shell/AndroidManifest.xml#L190)).
  No `pm` verb exposes it, so [tool/block_uninstall](../tool/block_uninstall/README.md) calls it via `app_process` as
  shell.
- A blocked uninstall returns `DELETE_FAILED_OWNER_BLOCKED` before anything is removed
  ([DeletePackageHelper](https://github.com/aosp-mirror/platform_frameworks_base/blob/android14-release/services/core/java/com/android/server/pm/DeletePackageHelper.java#L746)).
  The launcher's only removal path for a non-system app is `PackageInstaller.uninstall` (above), so the flag stops it,
  and there is no disable fallback for a non-system app.
- **Tested on the TV (2026-10-08):** HearthTube with `blockUninstall=true` in user 11 and **no** device admin survived
  a user stop/start (logcat 23:59 "stop user 11 due to finish user" → 00:00 HearthTube `SplashActivity`/
  `BrowseActivity` running in u11), while users 10/12 (flag false) had it removed. Persists across reboot (saved in
  package-restrictions `block-uninstall-packages`). Still to confirm: across a HearthTube update, and whether bedtime
  still suspends it — `canSuspendPackageForUser` allows the user's profile owner (GMS) to suspend even a
  block-uninstalled package, so screen time likely still applies; watch for `Cannot suspend package "…": blocked by
  admin` at bedtime.

## No-adb options (the goal) — verdict

The only durable, no-adb way to keep a sideloaded app in a kids profile is to get it into `targetPackagesForProfile`,
i.e. genuinely **approved for the child**. The launcher auto-installs an approved app that's present in user 0
(`installExistingPackage`) and keeps it — no adb, and it would apply to new profiles automatically. Admin and
block-uninstall only fight the reconcile from the side and need adb per profile.

Can a parent approve a non-Play app without adb? **Current evidence: no, not on Google TV.**
- Family Link approvals are Play-Store-based
  ([Manage your child's Google Play apps](https://support.google.com/families/answer/7103028?hl=en)); Google TV's kids
  "Manage apps" is a checklist of the child's apps
  ([Use parental controls on Google TV](https://support.google.com/googletv/answer/10070481?hl=en)); a sideloaded app
  did not appear in a child's Manage apps even with "allow third party apps" on
  ([SmartTube #4132, 2024](https://github.com/yuliskov/SmartTube/issues/4132)). No source shows a sideloaded app being
  approvable for a GTV kids profile.
- **Worth confirming on this setup (no adb, parent phone):** Family Link app → the child → Controls → Signed-in
  devices → the TV → look for an app list / "unknown sources"; and on the TV, owner profile → Settings → the child →
  Manage apps. If Hearth/HearthTube appear with an Allow toggle, approve them and check they survive a profile switch.
  (Expected to fail per the evidence, but it's the cheapest no-adb test, and Google changes this.)

Per-user restrictions on this TV (`dumpsys user`, 2026-10-08): users 10 and 11 have unknown sources **on**
(`no_install_unknown_sources` absent); user 12 has it **off**; user 13 (new) has no restrictions yet. All established
kid users carry `no_grant_admin`, `no_config_credentials`, `no_add_managed_profile`, `no_remove_user`,
`no_config_location`, `no_add_clone_profile`.

On-device device-admin route (no computer), enabled by unknown sources being on: in principle, sideload Hearth inside
a kid profile and activate `AgentAdminReceiver` via the on-screen `ACTION_ADD_DEVICE_ADMIN` prompt; the next reconcile
then sees an active admin and keeps it. `no_grant_admin` does **not** block this — it governs admin-*user* status in
multi-user Android, not activating a device-admin component
([AOSP UserManager](https://android.googlesource.com/platform/frameworks/base/+/master/core/java/android/os/UserManager.java),
[API 34 diff](https://developer.android.com/sdk/api_diff/34/changes/android.os.UserManager)). Real bottlenecks, both
untested: (1) you need an installer **inside** the kid profile to place the APK (a kids profile normally has only
approved apps and no browser/file-manager, and approving one is itself Play-only), and (2) you must reach the
device-admin consent screen in the locked-down, PIN-gated kids UI, within the ~3 s before the reconcile removes the
freshly-sideloaded app. If an approved in-profile installer exists, this is worth a hands-on test; otherwise the
install step has no no-adb trigger.

Realistic no-adb route if approval is required: a **private/closed Google Play testing track** with just these two
apps. That makes them real Play apps that can be approved for the child, after which the launcher keeps them with zero
adb (including on new profiles) and screen time still applies. Costs: a Play Console account; the kid copy updates via
Play (the owner copy can stay on GitHub + in-app updater). Verify first: whether a supervised child account can
join/receive a closed-track app (supervised accounts may not opt into testing tracks).

## The agent's jobs without Hearth in the kid's profile

Still needs a one-time adb grant and can't cover everything, so it doesn't remove the adb dependency:
- Continue Watching: `INTERACT_ACROSS_USERS` is `signature|privileged|development|role` on Android 14, so
  `pm grant com.leanbitlab.ltvL android.permission.INTERACT_ACROSS_USERS` (adb, once) lets the owner-user Hearth read
  `content://N@android.media.tv/watch_next_program`. Untested; the kid user must be running.
- Deep links into the kid user likely need `INTERACT_ACROSS_USERS_FULL` (adb can't grant).
- Netflix pairing's text-to-speech relay must run in the kid user, so it can't move out.

## Ruled out

- Reinstalling at every profile start: a Family Link notification each time.
- System-app status (the launcher skips system packages): needs root.
- Injecting into `targetPackagesForProfile` on-device: the list is a GMS supervision decision, not a local list.
- Family Link approving a sideloaded app on TV: no evidence it is possible (see above).
- Unknown sources alone (on for users 10/11): it lets an app be *installed* without adb, but the reconcile matches by
  **package name**, not install source, so a self-sideloaded app is still uninstalled at the next profile start
  (proven: HearthTube with `installerPackageName=null` was removed from users 10/12). It only helps combined with the
  on-device device-admin route above.
