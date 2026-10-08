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

import 'dart:async';
import 'dart:developer' as developer;
import 'dart:typed_data';

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
    FLauncherChannel.listenForProfileSwitching(switchingTo);
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
    _incomingExpiry?.cancel();
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
    final favorites = _appsService.favoritesCategory;
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

  /// SharedPreferences key prefix: this kids profile has had its first look (one per profile key).
  static const String kidsLookGivenKeyPrefix = "kids_look_given_";

  /// A kids profile starts with Bing's photo of the day as its wallpaper, once: after that its look is its own
  /// to change (in its Settings, past the parent PIN).
  Future<void> _giveKidsTheirFirstLook(String key) async {
    if (!_isKidsProfile || _sharedPreferences.getBool("$kidsLookGivenKeyPrefix$key") == true) return;
    await _settingsService.setBingWallpaperEnabled(true);
    await _sharedPreferences.setBool("$kidsLookGivenKeyPrefix$key", true);
  }

  Future<void> check() => _checking ??= _check().whenComplete(() {
        _checking = null;
        // Whatever this check found, its profile's layout is now in place
        final bool changed = !_settledOnce || _layoutReadyKey != _activeProfileKey;
        _settledOnce = true;
        _layoutReadyKey = _activeProfileKey;
        if (changed) notifyListeners();
      });

  bool _settledOnce = false;

  /// The first profile check since Hearth started is done (until then the home shows placeholders).
  bool get settledOnce => _settledOnce;

  String? _layoutReadyKey;

  /// This profile's layout has been restored (after a switch to it).
  bool layoutReadyFor(String key) => _layoutReadyKey == key;

  ProfileTransition? _transition;

  String? _incomingName;
  Uint8List? _incomingAvatar;
  Timer? _incomingExpiry;

  /// A profile picked in Google TV's chooser that the switch hasn't confirmed yet: its welcome card shows meanwhile.
  String? get incomingName => _incomingName;
  Uint8List? get incomingAvatar => _incomingAvatar;

  /// Google TV's chooser closed on [name]: show its welcome card now. The profile user takes a few seconds to
  /// settle; the check that follows confirms the switch (and the card carries on) or clears it.
  Future<void> switchingTo(String name) async {
    if (name == _activeProfileName) return;
    _incomingName = name;
    _incomingAvatar = null;
    _incomingExpiry?.cancel();
    // A pick Google TV didn't act on (Back out of a PIN prompt): the card goes away on its own
    _incomingExpiry = Timer(const Duration(seconds: 10), _clearIncoming);
    notifyListeners();
    try {
      final avatar = await _channel.getProfileAvatar(name);
      if (_incomingName == name && avatar.png != null) {
        _incomingAvatar = avatar.png;
        notifyListeners();
      }
    } catch (_) {}
  }

  void _clearIncoming() {
    _incomingExpiry?.cancel();
    if (_incomingName == null) return;
    _incomingName = null;
    _incomingAvatar = null;
    notifyListeners();
  }

  /// A switch to another profile that Hearth's home is still catching up with (see ProfileTransitionOverlay).
  ProfileTransition? get transition => _transition;

  /// The switch is complete (or given up on): the home shows.
  void endTransition(ProfileTransition transition) {
    if (_transition != transition) return;
    _transition = null;
    notifyListeners();
  }

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

    // A switch from one known profile to another (not Hearth starting up): the welcome card covers the catch-up
    if (_activeProfileKey != null && key != null && key != _activeProfileKey) {
      _transition = ProfileTransition(key, DateTime.now(), name ?? _incomingName, _incomingAvatar);
      _layoutReadyKey = null;
    }
    // Confirmed (the transition carries on) or not happening: either way the early card's job is done
    if (key != null && (key != _activeProfileKey || name == _incomingName)) _clearIncoming();
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
      await _giveKidsTheirFirstLook(key);
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
      await _giveKidsTheirFirstLook(key);
    } catch (e, stack) {
      developer.log("Failed to switch profile layout", name: "ProfileService", error: e, stackTrace: stack);
    }
  }
}

/// A switch to the profile [key], begun at [startedAt].
class ProfileTransition {
  final String key;
  final DateTime startedAt;

  /// The profile's name and photo as picked in the chooser, until Hearth has its own.
  final String? pickedName;
  final Uint8List? pickedAvatar;

  ProfileTransition(this.key, this.startedAt, [this.pickedName, this.pickedAvatar]);
}
