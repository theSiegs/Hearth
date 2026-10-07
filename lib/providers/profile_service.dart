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
import 'dart:typed_data';

import 'package:collection/collection.dart';

import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../flauncher_channel.dart';
import '../models/app.dart';
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
    // A switch can land while Hearth is already in front
    FLauncherChannel.listenForProfileChanges(check);
    check();
  }

  String? get activeProfileName => _activeProfileName;

  String? _activeProfileKey;

  /// The active profile's lasting key ("user:11"): set before its name is known, unchanged by renames.
  String? get activeProfileKey => _activeProfileKey;

  bool get isKidsProfile => _isKidsProfile;

  Uint8List? _avatar;
  String? _avatarName;
  int _avatarModified = 0;

  /// The active profile's Google TV photo (PNG), once Hearth has seen it in the profile chooser.
  Uint8List? get activeProfileAvatar => _avatar;

  /// Whether the photo changed.
  Future<bool> _loadAvatar(String? name) async {
    if (name == null) {
      final bool had = _avatar != null;
      _avatar = null;
      _avatarName = null;
      return had;
    }
    try {
      final avatar = await _channel.getProfileAvatar(name);
      if (name == _avatarName && avatar.modified == _avatarModified) return false;
      _avatar = avatar.png;
      _avatarName = name;
      _avatarModified = avatar.modified;
      return true;
    } catch (_) {
      return false;
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // A profile switch always ends with the launcher coming back to the front.
    if (state == AppLifecycleState.resumed) {
      // Kids profiles' blocked apps change with approvals and with bedtime/screen-time limits, and Android doesn't
      // always say so: re-read them whenever Hearth comes back, so the dock never offers a blocked app.
      if (_isKidsProfile) _appsService.refreshState();
      check();
    }
  }

  /// A profile can open none of its Favorites (a kids profile, where Google TV blocks unapproved apps), which
  /// would leave it without a dock: start its dock with the apps it can open.
  Future<void> _fillEmptyDock() async {
    if (!_isKidsProfile || !_appsService.initialized) return;
    final favorites = _appsService.categories.firstWhereOrNull((c) => c.name == 'Favorites');
    // What the dock holds, not what it shows: at bedtime Google TV blocks every app and the dock shows none
    bool inDock(App a) => favorites != null && a.categoryOrders.containsKey(favorites.id);
    if (_appsService.applications.any((a) => inDock(a) && a.approved && !a.hidden)) return;
    final apps = _appsService.applications
        // Approved rather than unblocked, for the same reason
        .where((a) => !a.hidden && a.approved && !inDock(a) && a.packageName != 'com.android.vending')
        .toList();
    if (apps.isEmpty) return;
    final dock = favorites ?? await _appsService.getOrCreateFavoritesCategory();
    await _appsService.addAllToCategory(apps.take(6), dock);
  }

  Future<void> check() => _checking ??= _check().whenComplete(() => _checking = null);

  Future<void> _check() async {
    String? name;
    String? key;
    bool kids = false;
    try {
      name = await _channel.getActiveProfileName();
      key = await _channel.getActiveProfileKey();
      kids = await _channel.isKidsProfile();
    } catch (_) {
      return;
    }

    bool changed = name != _activeProfileName || key != _activeProfileKey || kids != _isKidsProfile;
    _activeProfileName = name;
    _activeProfileKey = key;
    _isKidsProfile = kids;
    changed = await _loadAvatar(name) || changed;
    if (changed) notifyListeners();

    // Unknown profile (Hearth can't tell yet): leave the layout alone rather than guess.
    if (key == null) return;

    // Layouts are saved under the profile's key; before keys they were saved under its name, so an owner that is
    // this profile's name is this profile, and a layout saved under the name is its own.
    final String? owner = _sharedPreferences.getString(layoutOwnerKey);
    if (owner == key || (owner != null && owner == name)) {
      if (owner != key) await _sharedPreferences.setString(layoutOwnerKey, key);
      await _fillEmptyDock();
      return;
    }

    try {
      if (owner != null) {
        await _backupService.saveProfileLayout(owner, _settingsService);
      }
      // A profile seen for the first time starts from the current layout.
      if (await _backupService.loadProfileLayout(key, _settingsService) ||
          (name != null && await _backupService.loadProfileLayout(name, _settingsService))) {
        await _appsService.refreshState();
      }
      await _sharedPreferences.setString(layoutOwnerKey, key);
      await _fillEmptyDock();
    } catch (e, stack) {
      developer.log("Failed to switch profile layout", name: "ProfileService", error: e, stackTrace: stack);
    }
  }
}
