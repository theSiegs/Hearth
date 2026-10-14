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
import 'package:flauncher/models/data_usage.dart';
import 'package:flauncher/quiet_failure.dart';
import 'package:flutter/widgets.dart';

/// How the TV is connected, as Android's default network says.
enum NetworkType { wifi, wired, cellular, none }

/// The top bar's data usage: how the TV is connected (NetworkStatus on the Android side), whether it's offline, and
/// the data it used, which needs usage access.
class NetworkService extends ChangeNotifier with WidgetsBindingObserver {
  /// Without internet this long before [offline] says so: not for a blip, nor while Wi-Fi comes back after a sleep.
  static const Duration offlineGrace = Duration(seconds: 10);

  /// How often today's data usage is read while usage access is allowed.
  static const Duration usageEvery = Duration(minutes: 5);

  final FLauncherChannel _channel;
  StreamSubscription<Map<String, dynamic>>? _statusChanges;
  Timer? _offlineTimer;
  Timer? _usageTimer;

  NetworkType _networkType = NetworkType.none;
  bool _vpnActive = false;
  bool _internet = false;
  bool _known = false;
  bool _offline = false;
  bool _hasUsageStatsPermission = false;
  int _dailyDataUsage = 0;
  // Only the latest of overlapping reads counts
  int _permissionReads = 0;
  int _usageReads = 0;
  // Reads that answer after dispose are dropped
  bool _disposed = false;

  NetworkService(this._channel) {
    _channel.getNetworkStatus().then(_apply).catchError((Object _) {});
    try {
      _statusChanges = _channel.networkStatusChanges().listen(_apply, onError: (Object _) {});
    } catch (err) {
        noteFailure('network_service', err);
      // No Android side (tests)
    }
    _readPermission();
    WidgetsBinding.instance.addObserver(this);
  }

  NetworkType get networkType => _networkType;

  bool get vpnActive => _vpnActive;

  /// The connection reaches the internet (Android validated it).
  bool get hasInternetAccess => _internet;

  /// No internet for [offlineGrace] or longer: not connected, or connected and nothing gets through.
  bool get offline => _offline;

  bool get hasUsageStatsPermission => _hasUsageStatsPermission;

  /// Today's data, in bytes, as last read.
  int get dailyDataUsage => _dailyDataUsage;

  @visibleForTesting
  void applyStatus(Map<String, dynamic> status) => _apply(status);

  void _apply(Map<String, dynamic> status) {
    if (_disposed || status.isEmpty) return;
    _networkType = switch (status["type"]) {
      "wifi" => NetworkType.wifi,
      "wired" => NetworkType.wired,
      "cellular" => NetworkType.cellular,
      _ => NetworkType.none,
    };
    _vpnActive = status["vpn"] == true;
    _internet = status["internet"] == true;
    _known = true;
    if (_internet) {
      _offlineTimer?.cancel();
      _offlineTimer = null;
      _offline = false;
    } else if (!_offline) {
      _offlineTimer ??= Timer(offlineGrace, () {
        _offlineTimer = null;
        if (!_disposed && _known && !_internet) {
          _offline = true;
          notifyListeners();
        }
      });
    }
    notifyListeners();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Usage access may have been allowed in Android's settings meanwhile
    if (state == AppLifecycleState.resumed) refreshPermissionAndUsage();
  }

  Future<void> refreshPermissionAndUsage() => _readPermission();

  Future<void> requestPermission() => _channel.requestUsageStatsPermission();

  Future<void> _readPermission() async {
    final read = ++_permissionReads;
    bool allowed;
    try {
      allowed = await _channel.checkUsageStatsPermission();
    } catch (err) {
        noteFailure('network_service', err);
      return;
    }
    if (_disposed || read != _permissionReads) return;
    _hasUsageStatsPermission = allowed;
    if (allowed) {
      _readUsage();
      _usageTimer ??= Timer.periodic(usageEvery, (_) => _readUsage());
    } else {
      _usageTimer?.cancel();
      _usageTimer = null;
    }
    notifyListeners();
  }

  Future<void> _readUsage() async {
    final read = ++_usageReads;
    int bytes;
    try {
      bytes = await _channel.getDailyDataUsage();
    } catch (err) {
        noteFailure('network_service', err);
      return;
    }
    if (_disposed || read != _usageReads || bytes < 0) return;
    _dailyDataUsage = bytes;
    notifyListeners();
  }

  /// The data used in a period: "daily", "weekly" or "monthly"; -1 without usage access.
  Future<int> getDataUsageForPeriod(String period) => switch (period) {
        "weekly" => _channel.getWeeklyDataUsage(),
        "monthly" => _channel.getMonthlyDataUsage(),
        _ => _channel.getDailyDataUsage(),
      };

  /// The data used in a period, app by app; null without usage access.
  Future<DataUsageBreakdown?> getDataUsageByApp(String period) => _channel.getDataUsageByApp(period);

  @override
  void dispose() {
    _disposed = true;
    WidgetsBinding.instance.removeObserver(this);
    _statusChanges?.cancel();
    _offlineTimer?.cancel();
    _usageTimer?.cancel();
    super.dispose();
  }
}
