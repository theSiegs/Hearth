# Development

> **Draft.** Hearth is in early development and this document is a draft: features, settings and
> setup steps may change or be incomplete.

Hearth is a Flutter app (Dart, in `lib/`) with a native Android layer (Java, in `android/app/src/main/java/com/thesiegs/hearth/`)
that does everything Flutter can't: the accessibility services, Google TV profile tracking, Home Assistant servers,
installs, and the Watch Next provider.

## Requirements

- Flutter **3.24.5** (pinned in `pubspec.yaml`)
- JDK 17 and the Android SDK (compile and target SDK 35)
- A Google TV device or emulator. Profile features need Google TV; the Google TV emulator images work for most of it
  (see [Testing profiles](#testing-profiles)).

## Build and test

```sh
flutter pub get
flutter pub run build_runner build --delete-conflicting-outputs     # mocks and Drift code
dart run drift_dev schema generate drift_schemas/ test/generated_migrations/
flutter analyze
flutter test
```

On Windows, the database tests need SQLite: run `tool/fetch_sqlite_windows.ps1` once (it downloads `sqlite3.dll`
into `tool/windows/`, which git ignores).

```sh
flutter build apk --debug          # installs as com.thesiegs.hearth.debug, next to a release build
flutter build apk --release        # needs signing, below
```

A debug build is a separate app (`com.thesiegs.hearth.debug`), so it can sit next to the real one. To test Hearth as
the TV's launcher, install a release build.

Search artwork and where-to-watch details come from TMDB. Builds without a key work, with search finding titles
through Wikidata only (no artwork or availability); to include one, pass
`--dart-define=TMDB_API_KEY=<key>`. Never commit the key.

**Install on a Google TV** with `adb install -r --user 0 <apk>`, then turn the services back on (Set up Hearth
shows what's off). Reinstalling or force-stopping Hearth switches its accessibility services off.

## Project layout

| Path | What |
|---|---|
| `lib/main.dart`, `lib/flauncher_app.dart` | Start-up and providers |
| `lib/providers/` | State and services: apps, settings, wallpaper, Watch Next, profiles, search, updates, Home Assistant |
| `lib/widgets/` | Home screen, cards, dock, panels; `settings/` holds every settings page |
| `lib/flauncher_channel.dart` | The method channel to the Android side |
| `lib/l10n/` | Translations (`app_en.arb` is the source; 13 more locales) |
| `android/.../LauncherAccessibilityService.java` | Home Button Fix, profile tracking, screen time, remote remaps, idle sleep |
| `android/.../ProfilePairing*.java`, `*PinRecipe.java` | Profile Pairing and PIN entry for streaming apps |
| `android/.../Ha*.java` | Home Assistant notifications server, panel, status webhook, phone setup |
| `android/.../ProfileUsers.java`, `GoogleTvAccount.java`, `AppWatchers.java`, `Agent*.java`, `KidsProfiles.java`, `ProfileAppAccess.java` | Google TV profiles: kids' as Android users, grown-ups' as accounts in the owner's user (whose is on, from Google TV's home); whose Continue Watching entry is; Hearth on the kids' profiles |
| `android/.../ProfileProvider.java` | The provider HearthTube reads ([contract](provider-contract.md)) |
| `drift_schemas/` | Database schema history, for migration tests |
| `tool/` | Developer tools (below) |
| `docs/design/` | Design notes for the larger features |

The Dart package is still called `flauncher`, after the project Hearth descends from.

## Translations

Add every new string to `lib/l10n/app_en.arb` with a description, and to the other 13 locales. Android-side strings
live in `android/app/src/main/res/values*/strings*.xml`. Machine translations to check are listed in
[translations-to-review.md](translations-to-review.md). Hearth, HearthTube, Home Assistant, Google TV and app names
stay untranslated.

## Testing profiles

`tool/profilesim/` makes adult and kids Google TV profiles on an emulator without Google accounts, so profile
switches, bedtime and Hearth in other profiles can be tested without a real family's TV:

```powershell
.\tool\profilesim\build.ps1                                 # builds the test supervisor app
.\tool\profilesim\profiles.ps1 -Serial emulator-5554 add Kid -Kids
.\tool\profilesim\profiles.ps1 -Serial emulator-5554 switch 10
.\tool\profilesim\profiles.ps1 -Serial emulator-5554 bedtime 10 on
```

Other tools: `tool/kids_provision/` and `tool/block_uninstall/` (manual versions of Hearth on the kids' profiles, for
investigation), `tool/generate_icons.py` (app icon and TV banner).

## Releasing

1. Bump `version:` in `pubspec.yaml`: a date-style name and a higher build number (`2026.10.20+8120`).
2. Add release notes in `fastlane/metadata/android/en-US/changelogs/<build number>.txt`, and update
   [CHANGELOG.md](../CHANGELOG.md).
3. Commit, tag `v<name>` (annotated), and push the branch and tag.

`.github/workflows/release.yml` builds and signs the APKs (`Hearth-universal`, `-arm64-v8a`, `-armeabi-v7a`) and
publishes the GitHub release that the in-app updater reads. It needs the repository secrets `KEYSTORE_BASE64`,
`KEYSTORE_PASSWORD`, `KEY_ALIAS`, `KEY_PASSWORD` and `TMDB_API_KEY`. For now every release is published as a
pre-release, since Hearth is in early development; the in-app updater includes pre-releases by default (the
**Include pre-releases** switch), for Hearth and HearthTube alike. Once Hearth leaves early development, the
workflow can go back to making only tags with a `-` pre-releases. Every release must be signed with the same key, or installed copies can't update.

`.github/workflows/ci.yml` analyzes, tests and builds a debug APK on every push.

## Conventions

- Commit messages: `type(area): what changed, in plain words` (`fix(dock): moving an app inside the dock doesn't
  scroll the page`).
- Comments say why, not what. Keep the style of the file you're in.
- Never commit personal data: no real names, addresses, IPs or device names in code, tests, docs or commit messages.
  Use neutral examples ("Alex", "Sam", `192.0.2.10`).
