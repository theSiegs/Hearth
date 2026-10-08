# Research: Hearth and HearthTube in Google TV kids profiles

Where the research stands, for picking it up in another session. Findings so far:
[docs/kids-profile-installs.md](../../kids-profile-installs.md). Pages already read (or that couldn't be read):
[leads.md](leads.md).

## The question

Keep Hearth (`com.leanbitlab.ltvL`, the per-profile agent) and HearthTube (`com.thesiegs.hearthtube`) installed and
usable in each kids profile's Android user, without the Play Store and ideally without device admin. Alex hasn't
objected to device admin; he rejected reinstalling at every profile start (one Family Link notification each time).

## Observed on the test TV (2026-10-07, logs captured)

- onn 4K Pro, Android 14 (SDK 34), patch 2026-06-01. Kids profiles 10 (Jordan), 11 (Josephine), 12 (Riley):
  Google TV profile users backed by each kid's own supervised Google account; profile owner is Google Play services;
  Family Link restrictions such as `no_config_credentials`, `no_grant_admin`.
- The remover is Google TV's launcher inside the kid's user: process `com.google.android.apps.tv.launcherx:coreservices`,
  tags `TvProfileHelper` / `TvSystemBackend`, bug tag `b/427107950`. At every profile start (about 3 s in: 20:39:45
  start, 20:39:48 uninstall) `setInstalledPackages` compares the user's apps with `targetPackagesForProfile` and logs
  `UNINSTALLING package=com.leanbitlab.ltvL because it is NOT in target packagesForProfile`, then
  `disabling/uninstalling … (isSystem=false)`. It runs again when the package changes (21:44:20, right after a Hearth
  update).
- Jordan's target list: netflix.ninja, amazonvideo.livingroom, appletv, cbs.ott, disneyplus, youtube.tv, plus system
  packages. Built from Play approvals only.
- Result is `installed=false` for that user: `pm list packages -u --user 10` still lists it (the APK is the owner's),
  `pm list packages --user 10` doesn't.
- Installs mid-session (`pm install-existing --user N`, one Family Link notification each) survive until that
  profile's next start.
- Device admin (`AgentAdminReceiver`, no policies) blocks every removal, including the one after an update, and
  survives reboots and updates. Active in users 10, 11, 12 now. HearthTube has no admin receiver and is removed at
  every start.
- Agent jobs: Netflix pairing needs Hearth as the kid user's text-to-speech engine (can't move to the owner's user;
  screencap of other users fails). The kid's Continue Watching needs their Watch Next, unreadable from the owner's user
  without `INTERACT_ACROSS_USERS` (untested). Main activities open from the owner's user via LauncherApps; deep links
  need the agent. Disney+ pairing works with no agent (picked Jordan).
- Watch it: `adb logcat -v threadtime | grep -E "b/427107950|TvProfileHelper|TvSystemBackend"` during a switch.

## Settled from AOSP (android14-release)

- Shell can set the per-user block-uninstall flag (`setBlockUninstallForUser` only needs `DELETE_PACKAGES`); a blocked
  uninstall fails with `DELETE_FAILED_OWNER_BLOCKED`; blocked packages also can't be suspended except by the user's
  device/profile owner. `tool/block_uninstall` sets it. Details and links in docs/kids-profile-installs.md.
- `INTERACT_ACROSS_USERS` is `signature|privileged|development|role`, so `pm grant` works; ordinary cross-user content
  provider access needs only it.
- Supervision profile owner: `com.google.android.gms/.kids.account.receiver.ProfileOwnerReceiver`
  (`cmd overlay lookup android android:string/config_defaultSupervisionProfileOwnerComponent`).
- Developer verification (2026): adb installs are exempt; outside Play, enforcement covers phones and tablets in
  select regions; a free limited-distribution account covers up to 20 devices.

## Open, in priority order

1. Does block-uninstall hold against launcherx? Test with HearthTube in one kid's user: watch for
   `DELETE_FAILED_OWNER_BLOCKED`, and check launcherx doesn't fall back to disabling it ("disabling/uninstalling").
   Then across a reboot and a HearthTube update.
2. launcherx teardown (pull its APK from the TV, jadx): how `targetPackagesForProfile` is built, every exemption
   besides `isSystem`, what it does when the uninstall fails, whether it or Play services suspends apps at bedtime.
3. Who suspends at bedtime (launcherx or Play services)? Decides whether screen time still covers uninstall-blocked
   apps. logcat at bedtime: `Cannot suspend package "…": blocked by admin`.
4. Cross-user agent jobs: `INTERACT_ACROSS_USERS` + `content://10@android.media.tv/watch_next_program` (TvProvider's
   own checks); deep links into another user without `INTERACT_ACROSS_USERS_FULL`.
5. Community reports of `b/427107950` / `TvProfileHelper` removing sideloaded apps, now that pages load (the cloud
   session couldn't reach XDA, Google Nest Community, Reddit, support.google.com).

## Continuing it

Research agents can pick up the open questions above from a session on a computer with the TV on adb. Keep the
agents to read-only adb commands (`pm list`/`pm path`, `adb pull` of APKs, `dumpsys`, `logcat -d`,
`cmd overlay lookup`); tests that change the TV stay with you.
