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
import 'package:shared_preferences/shared_preferences.dart';

/// How long an automatic update waits for no kids profile to be running before it installs anyway.
const Duration updateDeferralCap = Duration(days: 7);

/// Whether an automatic update may install now: never while a Google TV kids profile's user is running (a package
/// change then can make Google TV take third-party apps out of that profile, signing the kid out), unless it has
/// waited [cap] since it was first held back ([waitingSince]).
bool mayInstallUpdateNow({
  required bool kidsUserRunning,
  required DateTime now,
  DateTime? waitingSince,
  Duration cap = updateDeferralCap,
}) {
  if (!kidsUserRunning) return true;
  if (waitingSince == null) return false;
  final waited = now.difference(waitingSince);
  return !waited.isNegative && waited >= cap;
}

/// Holds Hearth's automatic updates (its own and its companions') back while a kids profile is running, and remembers
/// since when each one waits (per package, across restarts), so that after [updateDeferralCap] it installs anyway.
/// An adult's own "Check for updates" or Install doesn't go through it.
class UpdateDeferral {
  static const String _keyPrefix = "update_waiting_since_";

  final SharedPreferences _sharedPreferences;
  final Future<bool> Function() _kidsUserRunning;
  final DateTime Function() _now;

  UpdateDeferral(this._sharedPreferences, this._kidsUserRunning, {DateTime Function()? now})
      : _now = now ?? DateTime.now;

  /// Since when [package]'s update waits, or null when it doesn't.
  DateTime? waitingSince(String package) {
    final millis = _sharedPreferences.getInt("$_keyPrefix$package");
    return millis == null ? null : DateTime.fromMillisecondsSinceEpoch(millis);
  }

  /// Whether [package]'s available update ([version]) may install now. When it may not, it's noted as waiting (from
  /// the first time) and logged.
  Future<bool> mayInstall(String package, String version) async {
    final now = _now();
    final since = waitingSince(package);
    final kids = await _kidsUserRunning();
    if (mayInstallUpdateNow(kidsUserRunning: kids, now: now, waitingSince: since)) {
      if (kids) {
        debugPrint("HearthUpdate: installing $package $version anyway: it waited ${now.difference(since!).inDays} "
            "days for no kids profile to be running");
      }
      return true;
    }
    if (since == null) await _sharedPreferences.setInt("$_keyPrefix$package", now.millisecondsSinceEpoch);
    final waited = since == null ? Duration.zero : now.difference(since);
    debugPrint("HearthUpdate: deferring $package $version while a kids profile is running (waited "
        "${waited.inHours} h of ${updateDeferralCap.inDays} days)");
    return false;
  }

  /// [package] is up to date or was installed: nothing waits.
  Future<void> done(String package) async {
    if (_sharedPreferences.containsKey("$_keyPrefix$package")) {
      await _sharedPreferences.remove("$_keyPrefix$package");
    }
  }
}
