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

import 'dart:async';

import 'package:flauncher/providers/companion_updater.dart';
import 'package:flauncher/widgets/settings/updates_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

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

void main() {
  testWidgets("Update automatically is a switch once its setting has loaded", (tester) async {
    // Nothing installed: getPackageVersion answers null.
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(_channel, (call) async => null);
    addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(_channel, null));
    final updater = _FakeCompanionUpdater();

    await tester.pumpWidget(Provider<CompanionUpdater>.value(
      value: updater,
      child: const MaterialApp(home: Scaffold(body: UpdatesPage())),
    ));
    await tester.pumpAndSettle();

    expect(find.text(UpdatesPage.title), findsOneWidget);
    expect(Focus.of(tester.element(find.text("Hearth"))).hasFocus, isTrue);
    expect(tester.widget<Switch>(find.byType(Switch)).onChanged, isNull);
    await tester.tap(find.text("Update automatically"));
    expect(updater.saved, isEmpty);

    updater.autoUpdate.complete(false);
    await tester.pumpAndSettle();
    await tester.tap(find.text("Update automatically"));
    await tester.pumpAndSettle();

    expect(updater.saved, [true]);
    expect(tester.widget<Switch>(find.byType(Switch)).value, isTrue);
  });
}
