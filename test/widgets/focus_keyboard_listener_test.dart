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

import 'package:flauncher/widgets/focus_keyboard_listener.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late List<String> calls;

  Future<void> pump(WidgetTester tester) async {
    calls = [];
    await tester.pumpWidget(MaterialApp(
      home: FocusKeyboardListener(
        onPressed: (_) {
          calls.add("pressed");
          return KeyEventResult.handled;
        },
        onLongPress: (_) {
          calls.add("long press");
          return KeyEventResult.handled;
        },
        onLongPressReleased: (_) => calls.add("released"),
        builder: (_) => const Focus(autofocus: true, child: SizedBox()),
      ),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets("a held OK's action that opens another app's screen waits until OK is let go", (tester) async {
    await pump(tester);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.select);
    await tester.pump(const Duration(milliseconds: 600));
    expect(calls, ["long press"]);
    await tester.sendKeyRepeatEvent(LogicalKeyboardKey.select);
    await tester.pump();
    expect(calls, ["long press"]);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.select);
    await tester.pump();
    expect(calls, ["long press", "released"]);
  });

  testWidgets("a short press is a press, not a release of a long press", (tester) async {
    await pump(tester);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.select);
    await tester.pump(const Duration(milliseconds: 100));
    await tester.sendKeyUpEvent(LogicalKeyboardKey.select);
    await tester.pump(const Duration(milliseconds: 600));
    expect(calls, ["pressed"]);
  });

  testWidgets("the menu key counts as a long press, released like one", (tester) async {
    await pump(tester);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.contextMenu);
    await tester.pump();
    expect(calls, ["long press"]);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.contextMenu);
    await tester.pump();
    expect(calls, ["long press", "released"]);
  });
}
