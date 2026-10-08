/*
 * FLauncher
 * Copyright (C) 2021  Étienne Fesser
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

import 'package:flauncher/providers/apps_service.dart';
import 'package:flauncher/providers/settings_service.dart';
import 'package:flauncher/providers/profile_service.dart';
import 'package:flauncher/widgets/settings/applications_panel_page.dart';
import 'package:flauncher/widgets/settings/home_screen_settings_page.dart';
import 'package:flauncher/widgets/settings/system_settings_page.dart';
import 'package:flauncher/widgets/settings/tv_power_settings_page.dart';
import 'package:flauncher/widgets/settings/notifications_settings_page.dart';
import 'package:flauncher/widgets/settings/focusable_settings_tile.dart';
import 'package:flauncher/widgets/settings/home_assistant_page.dart';
import 'package:flauncher/widgets/settings/profiles_settings_page.dart';
import 'package:flauncher/widgets/settings/remote_search_settings_page.dart';
import 'package:flauncher/widgets/settings/hearth_about_dialog.dart';
import 'package:flauncher/widgets/settings/settings_panel_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flauncher/l10n/app_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:package_info_plus_platform_interface/package_info_data.dart';
import 'package:package_info_plus_platform_interface/package_info_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:provider/provider.dart';

import '../../mocks.mocks.dart';

/// The top level's rows and the pages they open.
const _rows = {
  "Profiles": ProfilesSettingsPage.routeName,
  "Applications": ApplicationsPanelPage.routeName,
  "Home screen": HomeScreenSettingsPage.routeName,
  "Remote & search": RemoteSearchSettingsPage.routeName,
  "Notifications": NotificationsSettingsPage.routeName,
  "Home Assistant": HomeAssistantPage.routeName,
  "TV & power": TvPowerSettingsPage.routeName,
  "System": SystemSettingsPage.routeName,
};

void main() {
  setUpAll(() async {
    final binding = TestWidgetsFlutterBinding.ensureInitialized();
    binding.window.physicalSizeTestValue = Size(1280, 720);
    binding.window.devicePixelRatioTestValue = 1.0;
    // Scale-down the font size because the font 'Ahem' used when running tests is much wider than Roboto
    binding.platformDispatcher.textScaleFactorTestValue = 0.8;
  });

  testWidgets("shows the Hearth logo and no Settings heading", (tester) async {
    final settingsService = MockSettingsService();
    final appsService = MockAppsService();
    when(appsService.launcherSections).thenReturn([]);
    when(appsService.applications).thenReturn([]);
    when(settingsService.appHighlightAnimationEnabled).thenReturn(true);

    await _pumpWidgetWithProviders(tester, settingsService, appsService);

    expect(find.byKey(Key("settings_logo")), findsOneWidget);
    expect(find.text("Settings"), findsNothing);
  });

  testWidgets("the top level is the eight groups, in order", (tester) async {
    await _pumpWidgetWithProviders(tester, _settings(), _apps());

    final titles = tester
        .widgetList<FocusableSettingsTile>(find.byType(FocusableSettingsTile))
        .map((tile) => ((tile.title as Text).data))
        .toList();
    expect(titles, _rows.keys.toList());
  });

  for (final MapEntry(key: title, value: route) in _rows.entries) {
    testWidgets("'$title' opens its page", (tester) async {
      await _pumpWidgetWithProviders(tester, _settings(), _apps());

      await tester.ensureVisible(find.text(title));
      await tester.pumpAndSettle();
      await tester.tap(find.text(title));
      await tester.pumpAndSettle();
      expect(find.byKey(Key(route)), findsOneWidget);
    });
  }

  testWidgets("in a kids profile, Settings shows the kid's own groups and Parent settings", (tester) async {
    final profiles = MockProfileService();
    when(profiles.isKidsProfile).thenReturn(true);
    when(profiles.activeProfileName).thenReturn("Sam");
    await _pumpWidgetWithProviders(tester, _settings(), _apps(), profiles: profiles);

    final titles = tester
        .widgetList<FocusableSettingsTile>(find.byType(FocusableSettingsTile))
        .map((tile) => ((tile.title as Text).data))
        .toList();
    expect(titles, ["Profiles", "Home screen", "Parent settings"]);

    // No parent PIN set yet: it says to ask a parent, and nothing more shows
    await tester.tap(find.text("Parent settings"));
    await tester.pumpAndSettle();
    expect(find.text("Ask a parent"), findsOneWidget);
  });

  testWidgets("in a grown-up profile nothing is locked", (tester) async {
    final profiles = MockProfileService();
    when(profiles.isKidsProfile).thenReturn(false);
    when(profiles.activeProfileName).thenReturn("Alex");
    await _pumpWidgetWithProviders(tester, _settings(), _apps(), profiles: profiles);

    expect(find.text("Parent settings"), findsNothing);
    expect(find.text("System"), findsOneWidget);
  });

  testWidgets("System has About", (tester) async {
    final settingsService = _settings();
    when(settingsService.accentColor).thenReturn(const Color(0xFF7C4DFF));
    PackageInfoPlatform.instance = _MockPackageInfoPlatform();
    await _pumpWidgetWithProviders(tester, settingsService, _apps(), home: const SystemSettingsPage());

    await tester.ensureVisible(find.text("About Hearth"));
    await tester.pumpAndSettle();
    await tester.tap(find.text("About Hearth"));
    await tester.pumpAndSettle();
    expect(find.byType(HearthAboutDialog), findsOneWidget);
  });

  testWidgets("TV & power opens Android settings", (tester) async {
    final appsService = _apps();
    await _pumpWidgetWithProviders(tester, _settings(), appsService, home: const TvPowerSettingsPage());

    await tester.ensureVisible(find.text("System settings"));
    await tester.pumpAndSettle();
    await tester.tap(find.text("System settings"));
    await tester.pumpAndSettle();
    verify(appsService.openSettings());
  });
}

MockSettingsService _settings() {
  final settingsService = MockSettingsService();
  when(settingsService.appHighlightAnimationEnabled).thenReturn(true);
  return settingsService;
}

MockAppsService _apps() {
  final appsService = MockAppsService();
  when(appsService.launcherSections).thenReturn([]);
  when(appsService.applications).thenReturn([]);
  return appsService;
}

Future<void> _pumpWidgetWithProviders(
  WidgetTester tester,
  SettingsService settingsService,
  AppsService appsService, {
  Widget? home,
  ProfileService? profiles,
}) async {
  when(settingsService.hasParentPin).thenReturn(false);
  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<SettingsService>.value(value: settingsService),
        ChangeNotifierProvider<AppsService>.value(value: appsService),
        if (profiles != null) ChangeNotifierProvider<ProfileService>.value(value: profiles),
      ],
      builder: (_, __) => MaterialApp(
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        routes: {
          for (final route in [..._rows.values])
            route: (_) => Container(key: Key(route)),
        },
        home: Material(child: home ?? const SettingsPanelPage()),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

class _MockPackageInfoPlatform with MockPlatformInterfaceMixin implements PackageInfoPlatform {
  @override
  Future<PackageInfoData> getAll({String? baseUrl}) async => PackageInfoData(
        appName: "Hearth",
        packageName: "com.leanbitlab.ltvL",
        version: "1.0.0",
        buildNumber: "1",
        buildSignature: "",
      );
}
