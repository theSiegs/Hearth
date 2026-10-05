/*
 * LTvLauncher
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

import 'dart:developer' as developer;

import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../flauncher_channel.dart';
import 'apps_service.dart';
import 'backup_service.dart';
import 'settings_service.dart';

/// Follows the active Google TV profile (as seen by the accessibility service) and gives each profile its own
/// home layout: on a switch, the outgoing profile's layout is saved and the incoming one's restored.
class ProfileService extends ChangeNotifier with WidgetsBindingObserver {
  static const String layoutOwnerKey = "device_layout_owner";

  final FLauncherChannel _channel;
  final SharedPreferences _sharedPreferences;
  final BackupService _backupService;
  final SettingsService _settingsService;
  final AppsService _appsService;

  String? _activeProfileName;
  bool _isKidsProfile = false;
  Future<void>? _checking;

  ProfileService(this._channel, this._sharedPreferences, this._backupService, this._settingsService, this._appsService) {
    WidgetsBinding.instance.addObserver(this);
    check();
  }

  String? get activeProfileName => _activeProfileName;

  bool get isKidsProfile => _isKidsProfile;

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // A profile switch always ends with the launcher coming back to the front.
    if (state == AppLifecycleState.resumed) check();
  }

  Future<void> check() => _checking ??= _check().whenComplete(() => _checking = null);

  Future<void> _check() async {
    String? name;
    bool kids = false;
    try {
      name = await _channel.getActiveProfileName();
      kids = await _channel.isKidsProfile();
    } catch (_) {
      return;
    }

    final bool changed = name != _activeProfileName || kids != _isKidsProfile;
    _activeProfileName = name;
    _isKidsProfile = kids;
    if (changed) notifyListeners();

    // Unknown profile (switched some way we couldn't see): leave the layout alone rather than guess.
    if (name == null) return;

    final String? owner = _sharedPreferences.getString(layoutOwnerKey);
    if (owner == name) return;

    try {
      if (owner != null) {
        await _backupService.saveProfileLayout(owner, _settingsService);
      }
      // A profile seen for the first time starts from the current layout.
      if (await _backupService.loadProfileLayout(name, _settingsService)) {
        await _appsService.refreshState();
      }
      await _sharedPreferences.setString(layoutOwnerKey, name);
    } catch (e, stack) {
      developer.log("Failed to switch profile layout", name: "ProfileService", error: e, stackTrace: stack);
    }
  }
}
