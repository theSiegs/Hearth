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

import 'package:flauncher/l10n/app_localizations.dart';
import 'dart:async';

import 'package:flauncher/flauncher_channel.dart';
import 'package:flauncher/providers/companion_updater.dart';
import 'package:flauncher/providers/settings_service.dart';
import 'package:flauncher/widgets/rounded_switch_list_tile.dart';
import 'package:flauncher/widgets/settings/updates_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _channel = MethodChannel('me.efesser.flauncher/method');

class _FakeCompanionUpdater extends Fake implements CompanionUpdater {
  final Completer<bool> autoUpdate = Completer();
  final List<bool> saved = [];

  @override
  Future<bool> autoUpdateEnabled() => autoUpdate.future;

  @override
  Future<void> setAutoUpdate(bool enabled) async => saved.add(enabled);

  @override
  Future<CompanionRelease?> latestRelease(CompanionApp app) async => null;
}

/// The switch on the row titled [title].
Finder _switchOf(String title) => find.descendant(
    of: find.ancestor(of: find.text(title), matching: find.byType(RoundedSwitchListTile)), matching: find.byType(Switch));

Future<SettingsService> _pumpPage(WidgetTester tester, _FakeCompanionUpdater updater) async {
  // Nothing installed: getPackageVersion answers null.
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(_channel, (call) async => null);
  addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(_channel, null));
  SharedPreferences.setMockInitialValues({});
  final settings = SettingsService(await SharedPreferences.getInstance());

  await tester.pumpWidget(MultiProvider(
    providers: [
      Provider<FLauncherChannel>.value(value: FLauncherChannel()),
      Provider<CompanionUpdater>.value(value: updater),
      ChangeNotifierProvider<SettingsService>.value(value: settings),
    ],
    child: const MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(body: UpdatesPage())),
  ));
  await tester.pumpAndSettle();
  return settings;
}

void main() {
  testWidgets("Update automatically is a switch once its setting has loaded", (tester) async {
    final updater = _FakeCompanionUpdater();
    await _pumpPage(tester, updater);

    expect(find.text("Updates"), findsOneWidget);
    expect(Focus.of(tester.element(find.text("Hearth"))).hasFocus, isTrue);
    expect(tester.widget<Switch>(_switchOf("Update automatically")).onChanged, isNull);
    await tester.tap(find.text("Update automatically"));
    expect(updater.saved, isEmpty);

    updater.autoUpdate.complete(false);
    await tester.pumpAndSettle();
    await tester.tap(find.text("Update automatically"));
    await tester.pumpAndSettle();

    expect(updater.saved, [true]);
    expect(tester.widget<Switch>(_switchOf("Update automatically")).value, isTrue);
  });

  testWidgets("Include pre-releases is on by default and saves the choice", (tester) async {
    final settings = await _pumpPage(tester, _FakeCompanionUpdater());

    expect(tester.widget<Switch>(_switchOf("Include pre-releases")).value, isTrue);
    expect(find.text("Early test builds of Hearth and HearthTube. They may be unfinished."), findsOneWidget);

    await tester.tap(find.text("Include pre-releases"));
    await tester.pumpAndSettle();

    expect(settings.updatesIncludePrereleases, isFalse);
    expect(tester.widget<Switch>(_switchOf("Include pre-releases")).value, isFalse);
  });
}
