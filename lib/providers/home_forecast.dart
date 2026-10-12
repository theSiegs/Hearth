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

/// Which forecast shows: a summary of today (or tonight), the next hours, or the next days.
enum ForecastView { summary, hourly, daily }

/// The weather forecast over the home, in Continue Watching's spot: up while the top bar's weather has focus. It
/// opens on a summary of today, or tonight in the evening; OK on the weather goes on to the next hours, the next
/// days, and back to the summary.
class HomeForecast extends ChangeNotifier {
  bool _showing = false;
  ForecastView _view = ForecastView.summary;

  /// The forecast is up.
  bool get showing => _showing;

  ForecastView get view => _view;

  /// It shows the next days.
  bool get days => _view == ForecastView.daily;

  /// Up while the weather has focus; it opens on the summary each time.
  void setShowing(bool showing) {
    if (showing == _showing) return;
    _showing = showing;
    if (showing) _view = ForecastView.summary;
    notifyListeners();
  }

  /// Summary → next hours → next days → summary.
  void swap() {
    _view = ForecastView.values[(_view.index + 1) % ForecastView.values.length];
    notifyListeners();
  }
}
