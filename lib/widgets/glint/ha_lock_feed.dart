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

import 'dart:async';

import 'package:flauncher/flauncher_channel.dart';
import 'package:flauncher/models/ha_lock_state.dart';
import 'package:flauncher/quiet_failure.dart';
import 'package:flutter/foundation.dart';

/// What Home Assistant's Hearth integration says about this profile's time ([HaLockState.none] without it): read at
/// once, again when the integration says something changed, and every [every].
class HaLockFeed extends ChangeNotifier {
  final Future<HaLockState> Function() _read;
  Timer? _timer;
  bool _disposed = false;
  HaLockState _state = HaLockState.none;

  HaLockFeed(this._read, {Duration every = const Duration(minutes: 1)}) {
    FLauncherChannel.haStateVersion.addListener(load);
    _timer = Timer.periodic(every, (_) => load());
    load();
  }

  HaLockState get state => _state;

  Future<void> load() async {
    try {
      final state = await _read();
      if (_disposed) return;
      _state = state;
      notifyListeners();
    } catch (err) {
      noteFailure('ha_lock_feed', err);
    }
  }

  @override
  void dispose() {
    _disposed = true;
    FLauncherChannel.haStateVersion.removeListener(load);
    _timer?.cancel();
    super.dispose();
  }
}
