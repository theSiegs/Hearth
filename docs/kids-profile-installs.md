# Keeping Hearth and HearthTube in kids profiles

Notes from 2026-10-07/08. Android 14 (SDK 34), patch 2026-06-01, onn 4K Pro; kids users 10, 11, 12.

## What removes them (seen on the TV)

Not Family Link: Google TV's launcher running in the kid's profile user (`com.google.android.apps.tv.launcherx:coreservices`,
tags `TvProfileHelper` / `TvSystemBackend`, `b/427107950`). About 3 s after each profile start, and again whenever the
package changes, `setInstalledPackages` uninstalls for that user (`installed=false`) every non-system package that
isn't in `targetPackagesForProfile`, which is built from the kid's Play approvals. To watch it:

```
adb logcat -v threadtime | grep -E "b/427107950|TvProfileHelper|TvSystemBackend"
```

`pm install-existing --user N` puts an app back (one Family Link notification each time) until the next profile start.

## Why device admin keeps Hearth there

An active device admin can't be uninstalled for that user (`DeletePackageHelper`: `DELETE_FAILED_DEVICE_POLICY_MANAGER`)
and can't be suspended by anyone (`SuspendPackageHelper.canSuspendPackageForUser`: "has an active device admin").

## Lighter: block uninstall for that user (untested on the TV)

Android keeps a per-user "block uninstall" flag that does the same job without an admin:

- `PackageManagerService.setBlockUninstallForUser` only enforces `DELETE_PACKAGES`
  ([source](https://github.com/aosp-mirror/platform_frameworks_base/blob/android14-release/services/core/java/com/android/server/pm/PackageManagerService.java#L5825)),
  and adb's shell holds `DELETE_PACKAGES` and `INTERACT_ACROSS_USERS_FULL`
  ([Shell manifest](https://github.com/aosp-mirror/platform_frameworks_base/blob/android14-release/packages/Shell/AndroidManifest.xml#L190)).
  No `pm` command exposes it, so [tool/block_uninstall](../tool/block_uninstall/README.md) calls it through
  `app_process` as the shell user.
- An uninstall for a blocked user fails with `DELETE_FAILED_OWNER_BLOCKED` before anything is removed, and an
  all-users uninstall skips blocked users
  ([DeletePackageHelper](https://github.com/aosp-mirror/platform_frameworks_base/blob/android14-release/services/core/java/com/android/server/pm/DeletePackageHelper.java#L746)).
- It's saved per user in package-restrictions (`block-uninstall-packages`), so it should last through reboots;
  updates don't touch it (to confirm across a Hearth update, since Google TV re-checks then).
- No admin receiver needed, so it works for HearthTube too. It still costs one `install-existing` (one Family Link
  notification) per kid, once.

Screen time: `canSuspendPackageForUser` also refuses to suspend an uninstall-blocked package, except when the
caller is that user's device or profile owner
([source](https://github.com/aosp-mirror/platform_frameworks_base/blob/android14-release/services/core/java/com/android/server/pm/SuspendPackageHelper.java#L562)).
The kids users' profile owner is Google Play services. So if Google TV's launcher does the bedtime suspensions,
blocked apps stay open at bedtime as they do with device admin today (HearthTube already pauses on Hearth's
`screen_time_up`); if Play services does them, screen time still blocks them. logcat says which: `Cannot suspend
package "…": blocked by admin`.

What could still go wrong: Google TV's launcher might react to the failed uninstall differently from the device
admin failure (it logs "disabling/uninstalling"; disabling isn't stopped by this flag). Test with HearthTube in one
kid's profile first.

## The agent's jobs without Hearth in the kid's profile

- Continue Watching: `INTERACT_ACROSS_USERS` is `signature|privileged|development|role` on Android 14
  ([core manifest](https://github.com/aosp-mirror/platform_frameworks_base/blob/android14-release/core/res/AndroidManifest.xml#L3102)),
  so `adb shell pm grant com.leanbitlab.ltvL android.permission.INTERACT_ACROSS_USERS` works once Hearth declares it.
  Ordinary cross-user provider access needs only that (`ContentProviderHelper.checkContentProviderPermission`,
  `ALLOW_NON_FULL`), e.g. `content://10@android.media.tv/watch_next_program`. Untested: TvProvider's own checks, and
  the kid's user has to be running.
- Deep links in the kid's user: not checked; `startActivityAsUser` most likely needs `INTERACT_ACROSS_USERS_FULL`,
  which adb can't grant.
- Netflix pairing's text-to-speech relay has to stay in the kid's user.

## Ruled out

- Reinstalling at every profile start: a Family Link notification each time.
- System app status (Google TV skips system packages): needs root.
- Getting a non-Play package into `targetPackagesForProfile`: not researched to the end; the list comes from Play
  approvals.
