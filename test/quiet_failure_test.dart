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

import 'package:flauncher/quiet_failure.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late DebugPrintCallback original;
  late List<String> printed;

  setUp(() {
    original = debugPrint;
    printed = [];
    debugPrint = (String? message, {int? wrapWidth}) {
      if (message != null) printed.add(message);
    };
  });

  tearDown(() => debugPrint = original);

  test('names where it failed and the error type, never its message', () {
    noteFailure('weather', const FormatException('Alex Rivera at 192.0.2.10'));

    expect(printed, ['Hearth: weather failed: FormatException']);
  });

  test('a missing plugin, which every test sees, is not logged', () {
    noteFailure('weather', MissingPluginException('no plugin'));

    expect(printed, isEmpty);
  });
}
