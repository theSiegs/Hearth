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

## No-adb path being pursued: the Hearth agent as the in-profile installer

Hearth already has the two pieces (so this is extension, not new infrastructure):
- `AgentHub` — owner-Hearth listens on `127.0.0.1:47474`; each kid-user agent connects over loopback, the one channel
  users share (JSON lines today; can carry APK bytes).
- `SessionInstaller` — installs an APK into the **current** user via a store-source `PackageInstaller` session
  (`PACKAGE_SOURCE_STORE`, `USER_ACTION_NOT_REQUIRED` for updates of apps Hearth installed). An agent calling it
  installs into its own kid user with no adb (unknown sources is on for users 10/11; off for 12).

Design, per existing profile where Hearth is present:
1. **Hearth self-protects, no adb:** on first run in the kid user the agent fires `ACTION_ADD_DEVICE_ADMIN` for
   `AgentAdminReceiver`; the parent taps Activate once on screen (`no_grant_admin` doesn't block this). The reconcile
   then keeps Hearth ("has active device admin") with no adb and no block-uninstall flag.
2. **HearthTube, no adb:** owner-Hearth streams `HearthTube.apk` to the agent over `AgentHub`; the agent reinstalls it
   with `SessionInstaller` on each profile start (the agent already starts with the profile via `BootReceiver`), since
   the reconcile removes it ~3 s after start.

Hard limit (honest): loopback can't bootstrap a user that has **no Hearth yet** — `AgentHub.launchAgent` starts the
agent only `if Hearth is installed there`. So the **first** Hearth copy in a brand-new profile still needs one manual
placement (adb `install-existing`, or Play approval). After that one touch the profile self-sustains with no further
adb. (This is where a one-command "adb once per new profile" helper fits.)

De-risk results (2026-10-08, on the TV):
- **On-screen device-admin activation is impossible in a kids profile.** `ACTION_ADD_DEVICE_ADMIN` resolves to
  `com.android.tv.settings/.deviceadmin.DeviceAdminAdd` only in user 0; in user 11 it returns "No activity found" even
  though `com.android.tv.settings` is installed there — the activity is suppressed for the supervised user. So an
  in-profile app has nothing to launch; device admin can only be set over adb (`dpm set-active-admin`). (`dpm
  remove-active-admin` from shell also refuses a non-test admin, so Hearth's admin can't be cleared that way either.)
- Therefore there is **no fully no-adb persistence** on Google TV kids profiles: device admin and block-uninstall both
  need adb, the on-screen admin prompt doesn't exist in the kid user, and a per-start reinstall loop needs an
  already-persisting in-profile Hearth (circular). The floor is **one privileged action per profile.**

Making that floor painless (the recommendation):
- **One command per new profile:** `pm install-existing --user N` + set block-uninstall (via tool/block_uninstall)
  for both apps. Block-uninstall is lighter than device admin (no admin UI, nothing else to manage) and survives
  reboots; screen time is handled in-app (Hearth's `screen_time_up`), which both apps already honor.
- **Hands-off via Home Assistant:** the TV has no ADB integration in HA today (`androidtv` domain absent). Adding HA's
  Android Debug Bridge integration (network adb to the TV) lets an automation run that one command on a trigger or
  schedule, so new profiles self-heal with no computer. The block-uninstall step needs tool/block_uninstall's
  `app_process` + dex present on the TV (persists in `/data/local/tmp`); alternatively use `dpm set-active-admin` (a
  plain command, no dex) for Hearth and give HearthTube its own no-policy admin receiver.
- The loopback/agent install (AgentHub + SessionInstaller) can still reduce steps — once Hearth is adb-protected, the
  agent can install/maintain HearthTube over loopback — but it cannot remove the one adb action that first protects
  Hearth.

### Best "no computer" path: Hearth as its own adb host (Shizuku-style self-adb)

The one privileged action per profile needs the `shell` uid, but the adb *host* doesn't have to be a computer — it
can be Hearth itself. Verified on the TV (2026-10-08): `adbd` listens on `*:5555`, an on-device process reaches
`127.0.0.1:5555` (loopback probe connected, `rc=0`), `service.adb.tcp.port=5555`, and `adb_wifi_enabled=1`.

Design:
- Hearth (user 0) embeds an adb client (e.g. the `dadb` library) in its native layer and connects to
  `127.0.0.1:5555`.
- One-time: the first connection raises the system "authorize this debugging key?" prompt. The parent approves it
  on screen — and unlike `DeviceAdminAdd`, this dialog does exist and work on Google TV (it is how a PC gets
  authorized). Hearth's key is then trusted.
- Thereafter Hearth runs, as `shell`, the same commands used here for each kid user: `pm install-existing --user N`
  (both apps) + `dpm set-active-admin --user N com.leanbitlab.ltvL/.AgentAdminReceiver` (Hearth) and the
  block-uninstall step for HearthTube (or give HearthTube its own no-policy admin receiver). `shell` holds
  `INSTALL_PACKAGES`/`DELETE_PACKAGES`/`INTERACT_ACROSS_USERS_FULL`, so cross-user provisioning works.

Result: Hearth self-provisions every kid profile, including new ones, with no computer and no Home Assistant — only
the one on-screen key approval at setup.

Open items:
- Reboot persistence: `persist.adb.tcp.port` is empty, so cleartext 5555 may not return after a reboot on its own;
  `adb_wifi_enabled=1` persists, so a robust build should speak the persistent wireless-debugging (TLS, Android 11+)
  endpoint, paired once, rather than rely on 5555. Confirm what is reachable from on-device after a reboot.
- This is a deliberate privileged-helper capability (owner-authorized adb key); scope it behind an explicit setup
  step in Hearth.

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
- "The APK is in user 0, so it's in every user": the APK is device-wide, so `install-existing`/`installExistingPackage`
  are instant with no byte transfer (the loopback design needn't ship the APK). But the per-user `installed` bit is
  **not** automatic and still needs a privileged flip — proof: HearthTube is `installed=false` in users 10/12 right
  now while present in user 0. User 13 shows both apps only because it is a half-created profile with no profile owner
  or restrictions yet, so no reconcile has run; a finalized supervised profile would strip them.
