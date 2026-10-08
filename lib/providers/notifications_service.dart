import 'dart:async';
import 'package:collection/collection.dart';

import 'package:flutter/widgets.dart';
import 'package:flauncher/flauncher_channel.dart';
import 'package:shared_preferences/shared_preferences.dart';

class NotificationItem {
  final String key;
  final String packageName;
  final String title;
  final String text;
  final bool isClearable;

  NotificationItem({
    required this.key,
    required this.packageName,
    required this.title,
    required this.text,
    required this.isClearable,
  });

  factory NotificationItem.fromMap(Map<dynamic, dynamic> map) {
    return NotificationItem(
      key: map['key'] as String? ?? '',
      packageName: map['packageName'] as String? ?? '',
      title: map['title'] as String? ?? '',
      text: map['text'] as String? ?? '',
      isClearable: map['isClearable'] as bool? ?? false,
    );
  }
}

const String _hiddenPersistentKeysPref = 'hidden_persistent_notification_keys';

class NotificationsService extends ChangeNotifier with WidgetsBindingObserver {
  final FLauncherChannel _channel;
  Map<String, int> _notificationCounts = {};
  List<NotificationItem> _notifications = [];
  List<Map<dynamic, dynamic>> _rawList = [];
  bool _hasPermission = false;
  bool _hasOverlayPermission = false;
  bool _systemPopupEnabled = false;
  bool _hidePersistentNotifications = false;
  Set<String> _blockedPackages = {};

  /// Persistent notifications (foreground services and the like) that Android won't let a launcher
  /// cancel. Dismissing one hides it here until its app removes it.
  Set<String> _hiddenPersistentKeys = {};
  bool _initialized = false;
  StreamSubscription? _subscription;
  int _refreshCount = 0;
  final SharedPreferences _prefs;

  NotificationsService(this._channel, this._prefs) {
    _init();
    WidgetsBinding.instance.addObserver(this);
  }

  List<NotificationItem> get notifications => List.unmodifiable(_notifications);
  bool get hasPermission => _hasPermission;
  bool get hasOverlayPermission => _hasOverlayPermission;
  bool get systemPopupEnabled => _systemPopupEnabled;
  bool get hidePersistentNotifications => _hidePersistentNotifications;
  Set<String> get blockedPackages => Set.unmodifiable(_blockedPackages);
  @visibleForTesting
  bool get initialized => _initialized;

  int getNotificationCount(String packageName) {
    return _notificationCounts[packageName] ?? 0;
  }

  Future<void> _init() async {
    _systemPopupEnabled = _prefs.getBool('system_notifications_popup') ?? false;
    _hidePersistentNotifications = _prefs.getBool('hide_persistent_notifications') ?? false;
    final blockedList = _prefs.getStringList('blocked_notification_packages') ?? [];
    _blockedPackages = blockedList.toSet();
    _hiddenPersistentKeys = (_prefs.getStringList(_hiddenPersistentKeysPref) ?? []).toSet();

    _hasPermission = await _channel.checkNotificationListenerPermission();
    _hasOverlayPermission = await _channel.checkOverlayPermission();

    if (_hasPermission) {
      _updateNotificationCounts(await _channel.getActiveNotifications());

      _subscription ??= _channel.addNotificationsChangedListener((eventList) {
        _updateNotificationCounts(eventList);
      });
    }

    _initialized = true;
    notifyListeners();
  }

  Future<void> checkPermission() async {
    final bool allowed = await _channel.checkNotificationListenerPermission();
    final wasAllowed = _hasPermission;
    _hasPermission = allowed;

    if (allowed && (!wasAllowed || _subscription == null)) {
      _updateNotificationCounts(await _channel.getActiveNotifications());
      _subscription ??= _channel.addNotificationsChangedListener((eventList) {
        _updateNotificationCounts(eventList);
      });
    }

    notifyListeners();
  }

  Future<void> refreshNotifications() async {
    if (!_hasPermission) return;

    // Only the newest refresh applies, so an older list can't replace a newer one.
    final refresh = ++_refreshCount;
    final List<Map<dynamic, dynamic>> list = await _channel.getActiveNotifications();
    if (refresh != _refreshCount) return;

    _updateNotificationCounts(list);
  }

  void _updateNotificationCounts(List<Map<dynamic, dynamic>> list) {
    _rawList = list;
    // Forget hidden notifications once their app has removed them, so a new one shows again.
    final activeKeys = list.map((item) => item['key']).whereType<String>().toSet();
    if (_hiddenPersistentKeys.any((key) => !activeKeys.contains(key))) {
      _hiddenPersistentKeys = _hiddenPersistentKeys.intersection(activeKeys);
      _prefs.setStringList(_hiddenPersistentKeysPref, _hiddenPersistentKeys.toList());
    }
    _processNotifications();
  }

  void _processNotifications() {
    final Map<String, int> newCounts = {};
    final List<NotificationItem> newNotifications = [];

    for (final item in _rawList) {
      final String? pkg = item['packageName'] as String?;
      if (pkg == null) continue;

      if (_blockedPackages.contains(pkg)) {
        continue;
      }

      final notification = NotificationItem.fromMap(item);
      // Permanent and blank (Google TV's own background entries): nothing to show or dismiss, so never list them.
      if (!notification.isClearable && notification.title.trim().isEmpty && notification.text.trim().isEmpty) continue;
      if (!notification.isClearable &&
          (_hidePersistentNotifications || _hiddenPersistentKeys.contains(notification.key))) {
        continue;
      }
      newNotifications.add(notification);
      if (notification.isClearable) {
        newCounts[pkg] = (newCounts[pkg] ?? 0) + 1;
      }
    }

    // Direct comparison to avoid unnecessary notifies
    bool changed = false;
    if (_notificationCounts.length != newCounts.length) {
      changed = true;
    } else {
      for (final key in newCounts.keys) {
        if (_notificationCounts[key] != newCounts[key]) {
          changed = true;
          break;
        }
      }
    }

    if (!changed) {
      if (_notifications.length != newNotifications.length) {
        changed = true;
      } else {
        for (int i = 0; i < _notifications.length; i++) {
          if (_notifications[i].key != newNotifications[i].key ||
              _notifications[i].title != newNotifications[i].title ||
              _notifications[i].text != newNotifications[i].text ||
              _notifications[i].isClearable != newNotifications[i].isClearable) {
            changed = true;
            break;
          }
        }
      }
    }

    if (changed || !_initialized) {
      _notificationCounts = newCounts;
      _notifications = newNotifications;
      notifyListeners();
    }
  }

  Future<void> setHidePersistentNotifications(bool hide) async {
    _hidePersistentNotifications = hide;
    await _prefs.setBool('hide_persistent_notifications', hide);
    _processNotifications();
  }

  Future<void> blockPackage(String packageName) async {
    if (!_blockedPackages.contains(packageName)) {
      _blockedPackages.add(packageName);
      await _prefs.setStringList('blocked_notification_packages', _blockedPackages.toList());
      _processNotifications();
    }
  }

  Future<void> unblockPackage(String packageName) async {
    if (_blockedPackages.contains(packageName)) {
      _blockedPackages.remove(packageName);
      await _prefs.setStringList('blocked_notification_packages', _blockedPackages.toList());
      _processNotifications();
    }
  }

  Future<void> unblockAllPackages() async {
    if (_blockedPackages.isNotEmpty) {
      _blockedPackages.clear();
      await _prefs.setStringList('blocked_notification_packages', []);
      _processNotifications();
    }
  }

  Future<bool> requestPermission() async {
    return await _channel.requestNotificationListenerPermission();
  }

  Future<bool> openAppNotificationSettings() async {
    return await _channel.openAppNotificationSettings();
  }

  Future<void> checkOverlayPermission() async {
    final bool allowed = await _channel.checkOverlayPermission();
    if (_hasOverlayPermission != allowed) {
      _hasOverlayPermission = allowed;
      notifyListeners();
    }
  }

  Future<bool> requestOverlayPermission() async {
    return await _channel.requestOverlayPermission();
  }

  Future<void> setSystemPopupEnabled(bool enabled) async {
    _systemPopupEnabled = enabled;
    await _prefs.setBool('system_notifications_popup', enabled);
    notifyListeners();
  }

  Future<void> dismiss(String key) async {
    final notification = _notifications.firstWhereOrNull((n) => n.key == key);
    if (notification != null && !notification.isClearable) {
      // Android ignores a launcher's request to cancel these, so hide it on our side.
      await _hidePersistent([key]);
      return;
    }
    final bool success = await _channel.dismissNotification(key);
    if (success) {
      await refreshNotifications();
    }
  }

  Future<void> dismissAll() async {
    final persistentKeys = _notifications.where((n) => !n.isClearable).map((n) => n.key).toList();
    if (persistentKeys.isNotEmpty) {
      await _hidePersistent(persistentKeys);
    }
    final bool success = await _channel.dismissAllNotifications();
    if (success) {
      await refreshNotifications();
    }
  }

  Future<void> _hidePersistent(List<String> keys) async {
    _hiddenPersistentKeys.addAll(keys);
    await _prefs.setStringList(_hiddenPersistentKeysPref, _hiddenPersistentKeys.toList());
    _processNotifications();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      checkPermission();
      checkOverlayPermission();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _subscription?.cancel();
    super.dispose();
  }
}
