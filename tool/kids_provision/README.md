# kids_provision

Prototype of how Hearth keeps its **own** apps (Hearth, HearthTube) in Google TV kids profiles with no
computer, and — just as importantly — how it takes them back out again cleanly. See
[`kids-provision.sh`](kids-provision.sh) for the heavily-commented command logic, and
[docs/kids-profile-installs.md](../../docs/kids-profile-installs.md) for why the launcher removes them and
what was tested on the TV.

## The shape (what the Hearth app would do)

Two matching rows in **Settings → Setup & permissions**, both parent-initiated, nothing automatic:

- **"Add Hearth to kids' profiles"** → runs `add`: for each kid profile, `install-existing` Hearth + HearthTube
  and set the per-user block-uninstall flag. Explains first; lists what it did.
- **"Remove Hearth from kids' profiles"** → runs `remove`: for each kid profile, lift the flag **then**
  uninstall the copy. One press, no computer.
- A **state** view: which kid profiles currently have Hearth / HearthTube, so nothing is hidden.

It only ever touches Hearth's own two packages.

## Hearth as its own adb host (how `shell` is reached, no computer)

The steps need the `shell` uid (`INSTALL_PACKAGES`, `DELETE_PACKAGES`, `INTERACT_ACROSS_USERS_FULL`). Hearth
reaches it without a computer by being its own adb client:

- Hearth embeds an adb client (e.g. `dadb`) and connects to `127.0.0.1:5555` (verified reachable on-device).
- **Consent gate (one time):** the first connection raises the system **"Allow debugging?"** prompt for Hearth's
  key. The parent approves it on screen — this dialog works on Google TV. Nothing below can run until they do.
- Hearth then runs `kids-provision.sh`'s commands over that connection.
- It places the block-uninstall dex (from [`../block_uninstall`](../block_uninstall)) at
  `/data/local/tmp/block-uninstall.dex` first.

Reboot persistence: cleartext `5555` may not return after a reboot (`persist.adb.tcp.port` is unset), but
wireless debugging is enabled and persists, so a production build should speak the persistent wireless-debugging
(TLS) endpoint, paired once, rather than rely on `5555`. Confirm what is reachable on-device after a reboot.

## Safety: the orphan trap (proven on the TV)

A block-uninstall-protected copy **cannot be removed until the flag is lifted** — a shell uninstall of a
protected package returns `Failure [DELETE_FAILED_OWNER_BLOCKED]` (confirmed 2026-10-08 against HearthTube in a
kid profile; nothing was removed). Consequences baked into the design:

- `remove` always lifts the flag **before** uninstalling.
- **Uninstalling Hearth itself:** the parent must run **Remove** first. Hearth's Settings should block/ warn on
  its own uninstall until the kid copies are gone, because once Hearth is gone the flags can't be lifted from the
  device.
- **Manual undo if Hearth is already gone** (from any computer with adb to the TV), per kid user `N` and each
  package `P` in `com.leanbitlab.ltvL`, `com.thesiegs.hearthtube`:

  ```
  adb connect <tv-ip>:5555
  adb push block-uninstall.dex /data/local/tmp/block-uninstall.dex   # from tool/block_uninstall
  adb shell CLASSPATH=/data/local/tmp/block-uninstall.dex app_process /system/bin BlockUninstall P N false
  adb shell pm uninstall --user N P
  ```

## Device admin is deliberately NOT used here

Earlier builds protected Hearth with a no-policy device admin. That is **not** cleanly reversible without a
computer: `dpm remove-active-admin` throws `SecurityException` for a non-test admin, so an admin set by an app
that is later uninstalled is stuck short of a factory reset. This prototype protects **both** apps with the
block-uninstall flag only, so add and remove are a clean round trip from the `shell` user.

Cleanup note: a device admin was set on Hearth in users 10/11/12 during testing. To clear it with no computer,
Hearth should call `DevicePolicyManager.removeActiveAdmin()` on **itself** from its agent in each of those
profiles (an app may remove its own admin); shell cannot do it for a non-test admin.

## Status

Prototype / reference. The command sequences and the orphan-trap behavior are validated on the TV; the self-adb
transport (embedding `dadb`, the key-authorize flow, reboot/TLS handling) is the remaining piece to build in the
Hearth app. This lives under `tool/` so it does not collide with that app-layer work.
