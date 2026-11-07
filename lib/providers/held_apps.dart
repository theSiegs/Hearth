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

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../flauncher_channel.dart';
import '../quiet_failure.dart';

/// Why an app on the home can't open now.
class AppHold {
  /// The group whose time is up ("Games"); null while a family pause or a lock holds every app.
  final String? group;

  const AppHold(this.group);

  bool get all => group == null;

  @override
  bool operator ==(Object other) => other is AppHold && other.group == group;

  @override
  int get hashCode => group.hashCode;
}

/// The apps the active kids profile can't open now (a group out of time, a family pause, a lock; Home Assistant's
/// say, or Hearth's own YouTube limit without it), so the home shows them out of time. Pressing one shows the time's
/// up card instead of opening it. Always empty in an adult's profile, and never Hearth's own entries.
class HeldApps extends ChangeNotifier with WidgetsBindingObserver {
  final FLauncherChannel _channel;
  final Iterable<String> Function() _packages;
  final Listenable? _profile;
  Timer? _timer;
  bool _disposed = false;
  int _reads = 0;

  Map<String, AppHold> _held = const {};

  /// How often the holds are read again anyway (Hearth's own YouTube limit runs out without a word from anyone).
  static const Duration refreshEvery = Duration(minutes: 1);

  HeldApps(this._channel, this._packages, {Listenable? profile, bool start = true}) : _profile = profile {
    if (!start) return;
    WidgetsBinding.instance.addObserver(this);
    FLauncherChannel.haStateVersion.addListener(refresh);
    _profile?.addListener(refresh);
    _timer = Timer.periodic(refreshEvery, (_) => refresh());
    refresh();
  }

  @visibleForTesting
  void debugSetHeld(Map<String, AppHold> held) {
    _held = held;
    notifyListeners();
  }

  /// Why this app can't open now; null: it can.
  AppHold? holdOf(String packageName) => _held[packageName];

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) refresh();
  }

  Future<void> refresh() async {
    final read = ++_reads;
    Map<String, AppHold> found;
    try {
      final held = await _channel.getHeldApps(_packages().toSet().toList());
      found = {for (final e in held.entries) e.key: AppHold(e.value.isEmpty ? null : e.value)};
    } catch (err) {
      noteFailure('held_apps', err);
      return;
    }
    // A later read started meanwhile: its answer wins
    if (_disposed || read != _reads || mapEquals(found, _held)) return;
    _held = found;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    FLauncherChannel.haStateVersion.removeListener(refresh);
    _profile?.removeListener(refresh);
    super.dispose();
  }
}
