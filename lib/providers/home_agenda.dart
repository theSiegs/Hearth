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

import 'package:flutter/foundation.dart';

/// What's left of today on the calendars, over the home in Continue Watching's spot: up while the top bar's date and
/// time have focus (as the weather's forecast is while the weather has it).
class HomeAgenda extends ChangeNotifier {
  bool _showing = false;

  /// Today's events are up.
  bool get showing => _showing;

  void setShowing(bool showing) {
    if (showing == _showing) return;
    _showing = showing;
    notifyListeners();
  }
}
