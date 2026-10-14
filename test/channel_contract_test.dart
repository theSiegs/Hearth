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

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The method channel's two ends have to agree: every call Dart makes needs a case on the Java side, and every case
/// has to answer (a call that is never answered leaves its Future waiting for good). The Java side is a plain
/// `switch`, so this reads its source.
void main() {
  final java = File('android/app/src/main/java/com/thesiegs/hearth/MainActivity.java').readAsStringSync();
  final dart = File('lib/flauncher_channel.dart').readAsStringSync();

  // The switch in onMethodCall, from its first case to the default
  final start = java.indexOf('private void onMethodCall');
  final end = java.indexOf('default -> result.notImplemented()', start);
  final switchSource = java.substring(start, end);

  // Each case: its names (case "a", "b" ->) and its body up to the next case
  final caseStart = RegExp(r'^\s{12}case ((?:"[A-Za-z]+"(?:,\s*)?)+)\s*->', multiLine: true);
  final cases = <String, String>{};
  final matches = caseStart.allMatches(switchSource).toList();
  for (var i = 0; i < matches.length; i++) {
    final bodyEnd = i + 1 < matches.length ? matches[i + 1].start : switchSource.length;
    final body = switchSource.substring(matches[i].end, bodyEnd);
    for (final name in RegExp(r'"([A-Za-z]+)"').allMatches(matches[i].group(1)!)) {
      cases[name.group(1)!] = body;
    }
  }

  final dartCalls = RegExp(r'''invoke(?:List|Map)?Method(?:<[^>]*>)?\(\s*["']([A-Za-z]+)["']''')
      .allMatches(dart)
      .map((m) => m.group(1)!)
      .toSet();

  test('the Java switch was read', () {
    expect(cases.length, greaterThan(100));
    expect(dartCalls.length, greaterThan(100));
  });

  test('every call Dart makes has a case on the Java side', () {
    expect(dartCalls.difference(cases.keys.toSet()), isEmpty);
  });

  test('every case answers, or hands the result on to something that does', () {
    final silent = cases.entries.where((e) => !RegExp(r'\bresult\b').hasMatch(e.value)).map((e) => e.key).toList();
    expect(silent, isEmpty);
  });
}
