# Hearth (formerly the theSiegs LTvLauncher fork) — Session Handoff

> **Current state (2026-10-05) — read this first; older sections below describe the first session.**
> - **Profiles are Google TV's own**, not LTv-managed: LTv's people button opens Google TV's account chooser; the
>   accessibility service learns the active profile name from that chooser's focus/click events. Kids profiles are
>   detected by Google TV suspending unapproved apps; LTv hides suspended apps. LTv's own profile/PIN screens from
>   session 1 were removed.
> - **Accessibility service** (`LauncherAccessibilityService`) does: Home button, bounce back after Google TV opens its
>   own home, never covers Google TV's screen-time/PIN/chooser screens, profile-name tracking, idle standby, remote
>   button remapping (`ButtonMapper`), Home Assistant pop-ups (`HaNotificationServer`/`HaNotificationOverlay`, port
>   7676, LAN only) and status push to a HA webhook (`HaStatusReporter`). Reinstalling/force-stopping LTv turns the
>   service off; re-enable it.
> - Also added: per-profile home layouts (`ProfileService` + `BackupService.save/loadProfileLayout`), daily auto
>   backup, parent PIN for settings in kids profiles, built-in Open-Meteo weather, "match selected app" background,
>   Ambient mode for screensaver settings, category layout persistence fix.
> - **Tests on Windows:** `tool/fetch_sqlite_windows.ps1`, then `flutter pub run build_runner build`, then
>   `dart run drift_dev schema generate drift_schemas/ test/generated_migrations/`, then `flutter test`.
> - **Release signing:** personal key outside the repo (`~/.android/ltv-release.jks`, passwords in git-ignored
>   `android/local.properties`). Deployed to the test onn 4K Pro (192.0.2.73).
> - **Renamed to Hearth** (repo `github.com/theSiegs/Hearth`; the old URL redirects). The application ID stays
>   `com.leanbitlab.ltvL` on purpose so installs upgrade in place. Icon and banner come from `tool/generate_icons.py`.
>   Upstream is the `upstream` remote (leanbitlab-org/LtvLauncher); arclauncher is the `arclauncher` remote.
> - **Continue Watching posters are back** (`WatchNextPosters.java`): upstream dropped remote artwork for privacy;
>   Hearth fetches it with no cookies/referrer, https only (http only on the LAN), downscaled and disk-cached 30 days.
>   **TODO:** fetch remote artwork anonymously (e.g. through a self-hosted image proxy on the home network) so the
>   artwork hosts don't see the TV's IP and what's on the row.
> - **Favorites dock** (branch `feature/modern-layout`, ported from arclauncher without its DB change): when Favorites
>   has apps, the first screen is wallpaper with Continue Watching and a frosted Favorites dock (`HomeDock`) along the
>   bottom; other sections follow below. Dock corners follow the theme (`dockRadiusForTheme`). Settings → Interface →
>   Appearance turns it off or changes blur/dark/shadow. While focus is on that first screen the page is held at the top
>   (cards otherwise centre themselves). The dock blur and gradient wallpapers are drawn once and cached (arclauncher perf work). Enhanced focus was skipped: LTv already has zoom, dimming and the double outline. Still to port: menus, other performance items, video wallpaper.
> - Debug builds install as a separate app (`com.leanbitlab.ltvL.debug`); to test the real launcher on the emulator,
>   install the release APK.

**Repo:** `C:\Users\alex\dev\Hearth` (formerly `dev\LtvLauncher`; local clone of `github.com/theSiegs/Hearth`, formerly `theSiegs/LtvLauncher`, a personal fork of `LeanBitLab/LtvLauncher`, itself a fork of the open-source `FLauncher` Android TV launcher — Flutter/Dart app + thin native Android layer)

**Goal (Alex's words):** A Google TV front end that's as native-acting/looking as possible, but without ads, tracking, recommendations, or other common privacy issues — plus future Home Assistant integration (device/camera status), per-profile startup selection, and (stretch goal) auto-selecting the matching profile in first-party apps like Netflix when switching TV profiles.

**Target device:** Onn 4K Google TV box, flashed via ADB sideload.

## Why this fork, not Projectivy Launcher

Projectivy Launcher (`spocky/miproja1`) was the user's first idea, but that GitHub repo is *only* JSON device configs + an issue tracker — the actual launcher app is closed-source. No app code to modify. LtvLauncher was chosen instead specifically because it's fully open source (Flutter/Dart + Java native layer) and forkable.

## Privacy audit (done before building anything)

- The **release** manifest ships with **no `INTERNET` permission** by default — Flutter only injects it into debug/profile builds. That's a real, OS-enforced guarantee, not just "we don't call anything."
- No analytics/crash/telemetry SDKs anywhere in `pubspec.yaml` or Gradle files.
- Weather comes from the separately-installed **Breezy Weather** app via local broadcast/content-provider — no direct weather API call.
- "Continue Watching" reads Android's local `WatchNext` TV content provider (populated on-device by apps like Netflix) — never phones anywhere. Off by default. **User said this is fine, keep it.**
- This session **re-added `INTERNET` and `REQUEST_INSTALL_PACKAGES`** to the release manifest — explicitly approved by the user ("phoning out is allowed for launcher purposes, not for ad or third-party purposes"). Only used for: (a) fetching Bing's daily wallpaper image, (b) checking/downloading GitHub Releases for self-update. Nothing else calls out.

## What was built this session

### 1. Cleanup
Deleted `android/app/src/main/java/me/efesser/flauncher/` — a dead duplicate of the native package left over from the pre-fork namespace (`applicationId` is `com.leanbitlab.ltvL`; the old package was unreferenced but still compiled into the APK).

### 2. Profile picker at startup
- `lib/models/profile.dart` — `Profile` model (id, name, avatar color, optional per-profile accent color override, optional PIN hash).
- `lib/providers/profile_service.dart` — `ProfileService` (ChangeNotifier). **Deliberately stored in `SharedPreferences` as JSON, not in the Drift/SQLite schema** — adding a Drift table requires regenerating `database.drift.dart` via `build_runner`, and the goal was to avoid schema-migration risk on a first pass. This matches how every other setting in the app is already stored.
- `lib/widgets/profile/profile_picker_screen.dart` — "Who's watching?" full-screen gate, shown at launch whenever there's >1 profile or one PIN-locked profile. Single unlocked profile = zero behavior change, no gate shown.
- `lib/widgets/profile/pin_entry_dialog.dart` — D-pad-navigable numeric PIN keypad, reused for unlock and for set/confirm-new-PIN flows.
- `lib/widgets/profile/manage_profiles_page.dart` — Settings → Profiles: add/rename/recolor/delete, set/clear PIN per profile. Registered as a route in `lib/widgets/settings/settings_panel.dart`; entry point added in `settings_panel_page.dart`.
- Wired into `lib/main.dart` (new provider) and `lib/flauncher_app.dart` (the `home:` widget is now gated behind `ProfileService.profileConfirmedThisSession`).
- **Known scope limit (flagged to user, not yet done):** categories/apps shown are still shared across all profiles. Per-profile accent color applies on switch; per-profile category/app filtering would need real surgery on `apps_service.dart` (~1,100 lines) and was deferred as its own follow-up.

### 3. Bing "Photo of the Day" wallpaper
- Added to `lib/providers/wallpaper_service.dart`: fetches `bing.com/HPImageArchive.aspx` metadata, downloads the `_1920x1080.jpg` variant, caches to disk, refreshes once/day (checked hourly while the app is running, via existing lifecycle-aware Timer pattern already used for weather/watch-next).
- New setting `bingWallpaperEnabled` in `lib/providers/settings_service.dart`.
- UI toggle + "Refresh Now" + error state added to `lib/widgets/settings/wallpaper_panel_page.dart`. Mutually exclusive with time-based/gradient/picture wallpaper options (same pattern the original time-based toggle already used).

### 4. Self-update from GitHub Releases
- `lib/providers/update_service.dart` — checks `api.github.com/repos/theSiegs/LtvLauncher/releases/latest`, compares the release tag to the installed version (`package_info_plus`), downloads the `.apk` release asset, hands it to the system installer.
- Native additions in `android/app/src/main/java/com/leanbitlab/ltvL/MainActivity.java`: `checkInstallPermission`, `requestInstallPermission`, `installApk` (via `FileProvider`, since direct `file://` URIs don't work across the scoped-storage boundary on modern Android).
- New `<provider>` (`FileProvider`) + `android/app/src/main/res/xml/provider_paths.xml` in the manifest, pointing at the app's external-files `updates/` directory (matches where `UpdateService` downloads the APK).
- UI: `lib/widgets/settings/update_dialog.dart`, reachable from Settings → "Check for Updates" (shows changelog, download progress, install button).
- This mirrors the GitHub-Releases-as-update-channel model already used for Alex's SmartTube/YouTube+ fork, just implemented directly against the GitHub API instead of a separate update-manifest file.

## Build/test verification (this was NOT skipped)

No Flutter SDK existed on this machine at session start. With the user's explicit go-ahead:

1. Cloned Flutter via git, then **checked out tag `3.24.5`** specifically — matches the version pinned in `pubspec.yaml`'s `environment:` block. (Latest stable, 3.47.6, requires a newer Gradle/AGP than this project uses; rather than drag the whole Android build toolchain forward, matched what's actually pinned.) SDK lives at `C:\Users\alex\dev\tools\flutter`.
2. Android SDK was already present (`C:\Users\alex\AppData\Local\Android\sdk`) with platform-tools, build-tools, JDK 17 — just had to accept licenses (`flutter doctor --android-licenses`).
3. `flutter build apk --debug --target-platform android-arm64` → **succeeded**, 51MB APK. Confirms the Dart changes, the native Java changes, and the manifest/FileProvider changes all compile and link correctly together.
4. `flutter analyze` → clean in `lib/` (zero errors; only pre-existing lint debt like deprecated `withOpacity`/`MaterialState` and non-camelCase legacy constants, none of it mine).
5. `flutter pub run build_runner build` (generates mockito mocks, which are gitignored) then `flutter test` → found and **fixed two real regressions**: 6 existing tests (`wallpaper_service_test.dart`, `wallpaper_panel_page_test.dart`) mocked `SettingsService` without stubbing the new `bingWallpaperEnabled` getter, causing `MissingStubError`. Added the missing stubs; all pass now.
6. The 20 remaining failures were `Failed to load dynamic library 'sqlite3.dll'` (Drift tests on a Windows host with no native SQLite). This is now fixed: `test/flutter_test_config.dart` loads `tool/windows/sqlite3.dll` on Windows (the DLL is gitignored; `tool/fetch_sqlite_windows.ps1` downloads it from sqlite.org). `database_migration_test.dart` also needs `test/generated_migrations/`, which is gitignored and built from `drift_schemas/` the same way CI does it: `dart run drift_dev schema generate drift_schemas/ test/generated_migrations/`.

**Net state right now: builds clean, analyzes clean, all 294 tests pass (2 skipped upstream).**

## New dependency
`crypto: ^3.0.3` added to `pubspec.yaml` (used for PIN hashing in `ProfileService`). Resolved fine under both Flutter 3.24.5 and 3.47.6.

## Not started yet (explicitly deferred, not forgotten)

1. **Netflix (etc.) auto-profile-select.** No public API exists for this on any first-party streaming app. The only real mechanism is Android's `AccessibilityService` reading the target app's on-screen profile tiles and tapping the one matching the active TV profile's name. The native layer already has an `AccessibilityService` (`LauncherAccessibilityService.java`), currently only used to intercept the Home key — it would need real per-app logic layered on top. Caveats already flagged to the user: fragile (breaks on app UI updates), only matters when Netflix doesn't already remember a per-device profile, and Accessibility is itself a broad, privacy-sensitive permission (though everything stays on-device). Plan was: build it for Netflix first as a proof of concept, decide whether to generalize.
2. **Home Assistant integration** (view/get updates on devices & cameras). Explicitly a "plan-ahead" item per the user, not started. Architecturally it fits the existing pattern well — the app already has multiple status-bar widgets pulling from local services (network, weather, data usage); a camera/device widget hitting a local HA REST/WebSocket instance would slot in the same way, no cloud dependency required.
3. **Per-profile category/app filtering** — see scope-limit note above under Profiles.

## File manifest (new or touched this session)

**New:**
- `lib/models/profile.dart`
- `lib/providers/profile_service.dart`
- `lib/providers/update_service.dart`
- `lib/widgets/profile/profile_picker_screen.dart`
- `lib/widgets/profile/pin_entry_dialog.dart`
- `lib/widgets/profile/manage_profiles_page.dart`
- `lib/widgets/settings/update_dialog.dart`
- `android/app/src/main/res/xml/provider_paths.xml`

**Modified:**
- `lib/main.dart` (new providers)
- `lib/flauncher_app.dart` (startup profile gate; also briefly touched/reverted a `DialogTheme`→`DialogThemeData` fix — left as original `DialogTheme` since that's correct for the pinned Flutter 3.24.5)
- `lib/providers/settings_service.dart` (`bingWallpaperEnabled`)
- `lib/providers/wallpaper_service.dart` (Bing wallpaper fetch/refresh logic)
- `lib/flauncher_channel.dart` (new channel methods: install-permission check/request, installApk)
- `lib/widgets/settings/wallpaper_panel_page.dart` (Bing toggle UI)
- `lib/widgets/settings/settings_panel_page.dart` (Profiles + Check for Updates entries)
- `lib/widgets/settings/settings_panel.dart` (ManageProfilesPage route)
- `android/app/src/main/java/com/leanbitlab/ltvL/MainActivity.java` (install-permission + installApk methods)
- `android/app/src/main/AndroidManifest.xml` (`INTERNET`, `REQUEST_INSTALL_PACKAGES`, `FileProvider`)
- `pubspec.yaml` (`crypto` dependency)
- `test/providers/wallpaper_service_test.dart`, `test/widgets/settings/wallpaper_panel_page_test.dart` (mock stub fixes)

**Deleted:**
- `android/app/src/main/java/me/efesser/flauncher/` (dead duplicate package, 11 files)

## Environment notes for whoever picks this up

- Flutter SDK: `C:\Users\alex\dev\tools\flutter`, currently checked out at tag `3.24.5` (detached HEAD) to match the project pin. Add to PATH: `export PATH="$PATH:/c/Users/alex/dev/tools/flutter/bin"` (bash) or equivalent.
- Android SDK already configured at `C:\Users\alex\AppData\Local\Android\sdk`; licenses accepted.
- Before running tests on a fresh checkout: `flutter pub run build_runner build --delete-conflicting-outputs` (mocks), `dart run drift_dev schema generate drift_schemas/ test/generated_migrations/` (migration helpers), and on Windows `powershell tool/fetch_sqlite_windows.ps1` (sqlite3.dll).
- Nothing has been committed to git yet this session — all changes are in the working tree only.
