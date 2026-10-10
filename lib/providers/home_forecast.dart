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

/// The weather forecast over the home, in Continue Watching's spot: up while the top bar's weather has focus, and
/// either the next hours or the next days (OK on the weather swaps them).
class HomeForecast extends ChangeNotifier {
  bool _showing = false;
  bool _days = false;

  /// The forecast is up.
  bool get showing => _showing;

  /// It shows the next days rather than the next hours.
  bool get days => _days;

  /// Up while the weather has focus; it opens on the next hours each time.
  void setShowing(bool showing) {
    if (showing == _showing) return;
    _showing = showing;
    if (showing) _days = false;
    notifyListeners();
  }

  /// The next hours ⇄ the next days.
  void swap() {
    _days = !_days;
    notifyListeners();
  }
}
