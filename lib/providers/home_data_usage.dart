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
import 'package:flutter/foundation.dart';

/// The TV's data app by app, over the home in Continue Watching's spot: up while the top bar's data usage has focus
/// (as the weather's forecast while the weather has it). It opens on the top bar's period; OK on the data usage goes
/// on to the next (today, this week, this month).
class HomeDataUsage extends ChangeNotifier {
  static const List<String> periods = [dataUsageDaily, dataUsageWeekly, dataUsageMonthly];

  bool _showing = false;
  String _period = dataUsageDaily;

  /// The data usage is up.
  bool get showing => _showing;

  /// Its period: [dataUsageDaily], [dataUsageWeekly] or [dataUsageMonthly].
  String get period => _period;

  /// Up while the data usage has focus; it opens on [period] (the top bar's) each time.
  void setShowing(bool showing, {String period = dataUsageDaily}) {
    if (showing == _showing) return;
    _showing = showing;
    if (showing) _period = periods.contains(period) ? period : dataUsageDaily;
    notifyListeners();
  }

  /// Today → this week → this month → today.
  void nextPeriod() {
    _period = periods[(periods.indexOf(_period) + 1) % periods.length];
    notifyListeners();
  }
}
