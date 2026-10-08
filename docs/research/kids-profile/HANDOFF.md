# Handoff: Hearth on other Google TV profiles (implementation)

Branch `ccr-5410d51e-vof0qr` (pushed). Built by the research session; to be ported/merged into `master` by the app
session. Background and the device evidence behind the design: [README.md](README.md) and
[../../kids-profile-installs.md](../../kids-profile-installs.md).

## Integration status (verified)

Merging this branch into `master` (at `ac1ffcb`) is **conflict-free** — checked with `git merge-tree`. The only file
both sides edit is `lib/widgets/settings/settings_panel.dart` (this branch adds the `FamilyAppsPage` route near the
other route cases; `master`'s settings-lock work edits the imports block and the `build()` wrapper) and it
**auto-merges** (different regions). Re-run the check if `master` moves a lot before the port:
`git merge-tree --write-tree master ccr-5410d51e-vof0qr` (exit 0 = clean).

## What it does

A parent-controlled feature: put Hearth + HearthTube on the TV's other Google TV profiles, and take them off again.
Supervised kids' profiles are **kept installed** (a per-user block-uninstall flag, because Google TV's launcher
strips non-Play apps at each profile start); other adult profiles get a **plain install** (convenience; the launcher
leaves them alone), gated by an on-by-default setting. Reachable, reversible, and self-healing on uninstall.

## Files

New (no merge risk):
- `android/app/src/main/java/com/leanbitlab/ltvL/ProfileAppAccess.java` — orchestrator (`addToProfiles(..,keepInstalled,confirmedByParent)`, `removeFromProfiles`, `state`, `cleanupUser`). Only touches Hearth's two packages; add/remove require `confirmedByParent`; remove lifts the flag before uninstalling.
- `.../KidsBlockUninstallMain.java` — per-user block-uninstall flag helper, run as shell via `app_process` (kept by a `-keep` rule in `proguard-rules.pro`).
- `.../SelfAdb.java` — loopback adb transport (dadb) + `keyMaterial()` for the key-share.
- `lib/widgets/settings/family_apps_page.dart` — the "Hearth on other profiles" screen.
- `tool/kids_provision/`, `tool/block_uninstall/`, `docs/kids-profile-installs.md`, `docs/research/kids-profile/*`.

Changed:
- `.../MainActivity.java` — channel cases `addHearthToProfiles(includeAdults)`, `removeHearthFromProfiles`, `getHearthProfilesState`, `uninstallHearth`, `openGoogleTvHome`; supervised/adult profile enumeration + display names.
- `.../AgentHub.java`, `.../AgentService.java` — share owner's adb key to agents; agent self-clean when Hearth is uninstalled.
- `.../LauncherAccessibilityService.java` — `autoTakeOverAllowed()` + `allowGoogleTvTemporarily()` for "Use Google TV for now" (auto-bounce pauses; the Home button still returns to Hearth).
- `android/app/build.gradle` — `dev.mobile:dadb:1.2.10` (confirm version).
- `lib/flauncher_channel.dart` — Dart wrappers for the channel methods.
- `lib/providers/settings_service.dart` — `pushToAdultProfiles` (default true).
- `lib/widgets/settings/settings_panel.dart` (route), `general_settings_page.dart` ("Use Google TV for now"), `setup_checklist_page.dart` ("Hearth on other profiles" entry).

## Validated here

- Pure-Java core (`ProfileAppAccess` incl. `cleanupUser`, `KidsBlockUninstallMain`) compiles against android-35.
- `flutter analyze` clean for every changed Dart file (the only project analyze errors are pre-existing `test/`
  mock/migration-schema ones needing `build_runner` + drift schema gen).
- Kids add/orphan-trap/remove/re-add lifecycle validated on an Android-14 emulator via `tool/kids_provision`.

## Needs a device build/test (owner session)

- The dadb transport: confirm `dev.mobile:dadb` version and the Kotlin/Java interop (`AdbKeyPair.Companion` vs
  `@JvmStatic`) at first Gradle build; prefer the persistent wireless-debugging endpoint over cleartext 5555.
- The one-time on-screen "Allow debugging?" key-authorize, and the whole self-adb path.
- The **agent self-clean** end to end (shared key → detect owner gone → release flags).
- **Adult-profile enumeration on a real 2-adult TV** (getUserProfiles + supervision filter) — no test device yet.
- R8 `-keep` actually preserving `KidsBlockUninstallMain` in a release build.
- Whether bedtime suspension still covers a block-uninstalled app (HearthTube pauses in-app regardless).
- Cleanup of the device admins set on users 10/11/12 during testing (agent `removeActiveAdmin` — owner session owns).

## Tradeoff accepted by the owner

Each profile agent stores a copy of a device-wide, shell-capable adb key in app-private storage (needed so an agent
can self-clean after Hearth is uninstalled). Low risk on a family LAN; see the discussion in chat.
