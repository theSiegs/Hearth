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

import 'package:flauncher/widgets/ha_panel/ha_panel_gate.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test("the Home Assistant panel is on for an adult who turned it on", () {
    expect(haPanelAllowed(enabled: true, kids: false), isTrue);
    expect(haPanelAllowed(enabled: false, kids: false), isFalse);
  });

  test("a kids profile never gets the Home Assistant panel, whatever its settings say", () {
    expect(haPanelAllowed(enabled: true, kids: true), isFalse);
    expect(haPanelAllowed(enabled: false, kids: true), isFalse);
  });
}
