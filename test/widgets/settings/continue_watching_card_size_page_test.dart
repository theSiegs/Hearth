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

import 'package:flauncher/providers/settings_service.dart';
import 'package:flauncher/widgets/settings/continue_watching_card_size_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

void main() {
  testWidgets("starts on the saved height and saves the one picked", (tester) async {
    SharedPreferencesStorePlatform.instance = InMemorySharedPreferencesStore.withData({
      "flutter.continue_watching_card_size": "150",
    });
    final settingsService = SettingsService(await SharedPreferences.getInstance());

    await tester.pumpWidget(ChangeNotifierProvider<SettingsService>.value(
      value: settingsService,
      child: const MaterialApp(home: Scaffold(body: ContinueWatchingCardSizePage())),
    ));
    await tester.pumpAndSettle();

    expect(Focus.of(tester.element(find.text("150 dp • Large"))).hasFocus, isTrue);

    await tester.ensureVisible(find.text("110 dp • Compact"));
    await tester.pumpAndSettle();
    await tester.tap(find.text("110 dp • Compact"));
    await tester.pumpAndSettle();

    expect(settingsService.continueWatchingCardHeight, 110);
  });
}
