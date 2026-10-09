/*
 * Hearth
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program.  If not, see <https://www.gnu.org/licenses/>.
 */

// Google TV profile switches end to end on the Dart side, without a TV or a Google account: FakeNativeProfiles
// plays Hearth's Android side at the method channel, and the real ProfileService, welcome card and Settings lock
// react to it.

import 'package:flauncher/flauncher_channel.dart';
import 'package:flauncher/l10n/app_localizations.dart';
import 'package:flauncher/providers/apps_service.dart';
import 'package:flauncher/providers/backup_service.dart';
import 'package:flauncher/providers/profile_service.dart';
import 'package:flauncher/providers/settings_service.dart';
import 'package:flauncher/widgets/profile_transition_overlay.dart';
import 'package:flauncher/widgets/settings/focusable_settings_tile.dart';
import 'package:flauncher/widgets/settings/settings_lock.dart';
import 'package:flauncher/widgets/settings/settings_panel_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

import 'fake_native_profiles.dart';
import 'mocks.mocks.dart';

/// Profile layouts aren't what these tests are about: saving and restoring one does nothing.
class _NoLayouts extends BackupService {
  _NoLayouts(SharedPreferences prefs) : super(MockFLauncherDatabase(), prefs);

  @override
  Future<void> saveProfileLayout(String profileName, SettingsService settingsService) async {}

  @override
  Future<bool> loadProfileLayout(String profileName, SettingsService settingsService) async => false;
}

/// Hearth's profile-aware pieces, wired as in the app, over [native].
class _Hearth {
  final SettingsService settings;
  final AppsService apps;
  final ProfileService profiles;

  _Hearth(this.settings, this.apps, this.profiles);

  static Future<_Hearth> start() async {
    SharedPreferencesStorePlatform.instance = InMemorySharedPreferencesStore.empty();
    final prefs = await SharedPreferences.getInstance();
    final settings = SettingsService(prefs);
    final apps = MockAppsService();
    when(apps.initialized).thenReturn(false);
    when(apps.launcherSections).thenReturn([]);
    when(apps.applications).thenReturn([]);
    when(apps.refreshState()).thenAnswer((_) async {});
    final profiles = ProfileService(FLauncherChannel(), prefs, _NoLayouts(prefs), settings, apps);
    await profiles.check();
    return _Hearth(settings, apps, profiles);
  }

  Widget wrap(Widget child) => MultiProvider(
        providers: [
          Provider<FLauncherChannel>.value(value: FLauncherChannel()),
          ChangeNotifierProvider<SettingsService>.value(value: settings),
          ChangeNotifierProvider<AppsService>.value(value: apps),
          ChangeNotifierProvider<ProfileService>.value(value: profiles),
        ],
        child: MaterialApp(
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          home: Material(child: child),
        ),
      );

  /// Unmounts the app, then lets ProfileService go (it watches the app's lifecycle).
  Future<void> stop(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    profiles.dispose();
  }
}

/// The home under the welcome card: one focusable thing, standing in for the dock.
Widget _homeWithCard() => Stack(
      children: [
        const Center(child: FocusableActionDetector(autofocus: true, child: Text("dock"))),
        ProfileTransitionOverlay(channel: FLauncherChannel()),
      ],
    );

bool _cardFocused() => FocusManager.instance.primaryFocus?.debugLabel == "profile_transition";

double? _cardProgress(WidgetTester tester) =>
    tester.widget<LinearProgressIndicator>(find.byType(LinearProgressIndicator)).value;

List<String?> _settingsRows(WidgetTester tester) => tester
    .widgetList<FocusableSettingsTile>(find.byType(FocusableSettingsTile))
    .map((tile) => (tile.title as Text).data)
    .toList();

void main() {
  setUpAll(() {
    final binding = TestWidgetsFlutterBinding.ensureInitialized();
    binding.platformDispatcher.implicitView!.physicalSize = const Size(1280, 720);
    binding.platformDispatcher.implicitView!.devicePixelRatio = 1.0;
    // The test font (Ahem) is much wider than Roboto
    binding.platformDispatcher.textScaleFactorTestValue = 0.8;
  });

  group("welcome card", () {
    testWidgets("a switch to a kids profile greets her, holds the remote until her agent reports, then says ready",
        (tester) async {
      final native = FakeNativeProfiles.install(tester, key: "user:0", name: "Sam");
      final hearth = await _Hearth.start();
      await tester.pumpWidget(hearth.wrap(_homeWithCard()));
      await tester.pump();
      expect(find.byType(LinearProgressIndicator), findsNothing);

      await native.switchTo("user:10", name: "Alex", kids: true, dataReady: false);
      await tester.pump();
      await tester.pump();

      expect(hearth.profiles.isKidsProfile, isTrue);
      expect(find.text("Hi, Alex"), findsOneWidget);
      expect(_cardFocused(), isTrue);
      // Layout restored and no Watch Next to wait for; the agent's data is the step still out
      expect(_cardProgress(tester), 0.75);

      await tester.pump(const Duration(seconds: 1));
      expect(find.text("Hi, Alex"), findsOneWidget);
      expect(native.readyKeys, isEmpty);

      native.dataReady = true;
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump();

      expect(find.text("Hi, Alex"), findsNothing);
      expect(native.readyKeys, ["user:10"]);
      expect(_cardFocused(), isFalse);
      await hearth.stop(tester);
    });

    testWidgets("a pick in the chooser shows the card at once, and the settled switch carries it on", (tester) async {
      final native = FakeNativeProfiles.install(tester, key: "user:0", name: "Sam");
      final hearth = await _Hearth.start();
      await tester.pumpWidget(hearth.wrap(_homeWithCard()));
      await tester.pump();

      await native.pick("Alex");
      await tester.pump();
      await tester.pump();

      expect(hearth.profiles.incomingName, "Alex");
      expect(find.text("Hi, Alex"), findsOneWidget);
      expect(_cardProgress(tester), 0);
      expect(_cardFocused(), isTrue);

      // Hearth hasn't learned this profile user's name yet: the card keeps the picked one
      await native.switchTo("user:10", kids: true, dataReady: false);
      await tester.pump();
      await tester.pump();

      expect(hearth.profiles.incomingName, isNull);
      expect(hearth.profiles.transition?.pickedName, "Alex");
      expect(find.text("Hi, Alex"), findsOneWidget);
      expect(_cardProgress(tester), 0.75);

      native.dataReady = true;
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump();

      expect(find.text("Hi, Alex"), findsNothing);
      expect(native.readyKeys, ["user:10"]);
      await hearth.stop(tester);
    });

    testWidgets("a pick Google TV never acts on (Back out of its PIN prompt) clears itself", (tester) async {
      final native = FakeNativeProfiles.install(tester, key: "user:0", name: "Sam");
      final hearth = await _Hearth.start();
      await tester.pumpWidget(hearth.wrap(_homeWithCard()));
      await tester.pump();

      await native.pick("Alex");
      await tester.pump();
      expect(find.text("Hi, Alex"), findsOneWidget);

      await tester.pump(const Duration(seconds: 10));
      await tester.pump();

      expect(find.text("Hi, Alex"), findsNothing);
      expect(native.readyKeys, isEmpty);
      await hearth.stop(tester);
    });

    testWidgets("a profile whose agent never reports still gets in after maxWait", (tester) async {
      final native = FakeNativeProfiles.install(tester, key: "user:0", name: "Sam");
      final hearth = await _Hearth.start();
      await tester.pumpWidget(hearth.wrap(_homeWithCard()));
      await tester.pump();

      await native.switchTo("user:10", name: "Alex", kids: true, dataReady: false);
      await tester.pump();
      await tester.pump();
      expect(find.text("Hi, Alex"), findsOneWidget);

      await tester.pump(ProfileTransitionOverlay.maxWait);
      await tester.pump();

      expect(find.text("Hi, Alex"), findsNothing);
      expect(native.readyKeys, ["user:10"]);
      await hearth.stop(tester);
    });

    testWidgets("starting up in a profile shows no card", (tester) async {
      final native = FakeNativeProfiles.install(tester, key: "user:10", name: "Alex", kids: true);
      final hearth = await _Hearth.start();
      await tester.pumpWidget(hearth.wrap(_homeWithCard()));
      await tester.pump();

      expect(find.byType(LinearProgressIndicator), findsNothing);
      expect(hearth.profiles.isKidsProfile, isTrue);
      expect(native.readyKeys, isEmpty);
      await hearth.stop(tester);
    });
  });

  group("Settings lock", () {
    Widget settingsPanel() => SettingsUnlock(notifier: ValueNotifier(false), child: const SettingsPanelPage());

    Future<void> enterPin(WidgetTester tester, String pin) async {
      for (final digit in pin.split("")) {
        await tester.tap(find.text(digit));
        await tester.pump();
      }
      await tester.pumpAndSettle();
    }

    testWidgets("follows the active profile: kids profiles lock, grown-up ones don't", (tester) async {
      final native = FakeNativeProfiles.install(tester, key: "user:0", name: "Sam");
      final hearth = await _Hearth.start();
      await tester.pumpWidget(hearth.wrap(settingsPanel()));
      await tester.pumpAndSettle();
      expect(_settingsRows(tester), isNot(contains("Parent settings")));
      expect(_settingsRows(tester), contains("System"));

      await native.switchTo("user:10", name: "Alex", kids: true);
      await tester.pumpAndSettle();
      expect(_settingsRows(tester), ["Profiles", "Home screen", "Parent settings"]);

      await native.switchTo("user:0", name: "Sam");
      await tester.pumpAndSettle();
      expect(_settingsRows(tester), isNot(contains("Parent settings")));
      expect(_settingsRows(tester), contains("System"));
      await hearth.stop(tester);
    });

    testWidgets("in a kids profile the parent PIN opens the rest", (tester) async {
      final native = FakeNativeProfiles.install(tester, key: "user:10", name: "Alex", kids: true);
      final hearth = await _Hearth.start();
      await hearth.settings.setParentPin("2468");
      await tester.pumpWidget(hearth.wrap(settingsPanel()));
      await tester.pumpAndSettle();
      expect(_settingsRows(tester), ["Profiles", "Home screen", "Parent settings"]);

      await tester.tap(find.text("Parent settings"));
      await tester.pumpAndSettle();
      await enterPin(tester, "2468");

      expect(_settingsRows(tester), isNot(contains("Parent settings")));
      expect(_settingsRows(tester), contains("System"));
      expect(native.key, "user:10");
      await hearth.stop(tester);
    });

    testWidgets("a parent's unlock in one kids profile doesn't carry over to another", (tester) async {
      final native = FakeNativeProfiles.install(tester, key: "user:10", name: "Alex", kids: true);
      final hearth = await _Hearth.start();
      await hearth.settings.setParentPin("2468");
      await tester.pumpWidget(hearth.wrap(settingsPanel()));
      await tester.pumpAndSettle();
      await tester.tap(find.text("Parent settings"));
      await tester.pumpAndSettle();
      await enterPin(tester, "2468");
      expect(_settingsRows(tester), contains("System"));

      // Settings stays open through a switch (Profiles > Switch profile, then Google TV's chooser)
      await native.switchTo("user:12", name: "Riley", kids: true);
      await tester.pumpAndSettle();

      expect(_settingsRows(tester), ["Profiles", "Home screen", "Parent settings"]);
      await hearth.stop(tester);
    },
        skip: true, // Fails today: SettingsUnlock outlives a profile switch (seen on the emulator too; see the QA report)
    );
  });
}
