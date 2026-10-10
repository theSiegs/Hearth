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

import 'package:flauncher/flauncher_app.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<int Function()> pumpButton(WidgetTester tester) async {
    int presses = 0;
    await tester.pumpWidget(MaterialApp(
      shortcuts: hearthActivateShortcuts(WidgetsApp.defaultShortcuts),
      home: Scaffold(
        body: TextButton(autofocus: true, onPressed: () => presses++, child: const Text("Add to")),
      ),
    ));
    await tester.pumpAndSettle();
    return () => presses;
  }

  for (final key in activateKeys) {
    testWidgets("${key.keyLabel} presses once per press, not again while held", (tester) async {
      final presses = await pumpButton(tester);

      await tester.sendKeyDownEvent(key);
      await tester.pumpAndSettle();
      expect(presses(), 1);

      // A held key repeats: what has focus by then (a menu that opened under the held key) isn't pressed
      await tester.sendKeyRepeatEvent(key);
      await tester.sendKeyRepeatEvent(key);
      await tester.pumpAndSettle();
      expect(presses(), 1);

      await tester.sendKeyUpEvent(key);
      await tester.sendKeyDownEvent(key);
      await tester.pumpAndSettle();
      expect(presses(), 2);
      await tester.sendKeyUpEvent(key);
    });
  }

  test("the other default shortcuts stay as they are", () {
    final shortcuts = hearthActivateShortcuts(WidgetsApp.defaultShortcuts);
    for (final entry in WidgetsApp.defaultShortcuts.entries) {
      final activator = entry.key;
      if (activator is SingleActivator && activateKeys.contains(activator.trigger)) continue;
      expect(shortcuts[activator], entry.value);
    }
  });
}
