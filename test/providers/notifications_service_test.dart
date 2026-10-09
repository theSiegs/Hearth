import 'dart:async';

import 'package:flauncher/providers/notifications_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

import '../mocks.mocks.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late MockFLauncherChannel mockChannel;
  late SharedPreferences prefs;
  late NotificationsService notificationsService;
  late StreamController<List<Map<dynamic, dynamic>>> streamController;

  // What the notification listener sends for a notification the user can dismiss
  Map<String, Object> clearable(String packageName, String key) =>
      {'key': key, 'packageName': packageName, 'title': 'Title $key', 'text': '', 'isClearable': true};

  setUp(() async {
    SharedPreferencesStorePlatform.instance = InMemorySharedPreferencesStore.empty();
    prefs = await SharedPreferences.getInstance();

    mockChannel = MockFLauncherChannel();
    streamController = StreamController<List<Map<dynamic, dynamic>>>.broadcast();

    // Default stubbing
    when(mockChannel.checkNotificationListenerPermission())
        .thenAnswer((_) async => false);
    when(mockChannel.requestNotificationListenerPermission())
        .thenAnswer((_) async => false);
    when(mockChannel.checkOverlayPermission())
        .thenAnswer((_) async => false);
    when(mockChannel.requestOverlayPermission())
        .thenAnswer((_) async => false);
    when(mockChannel.getActiveNotifications())
        .thenAnswer((_) async => []);
    when(mockChannel.addNotificationsChangedListener(any))
        .thenAnswer((invocation) {
          final listener = invocation.positionalArguments[0] as void Function(List<Map<dynamic, dynamic>>);
          final sub = streamController.stream.listen(listener);
          return sub;
        });
  });

  tearDown(() {
    streamController.close();
  });

  group('Initialization', () {
    test('initializes with default state when permission denied', () async {
      notificationsService = NotificationsService(mockChannel, prefs);
      
      while (!notificationsService.initialized) {
        await Future.delayed(Duration.zero);
      }

      expect(notificationsService.initialized, true);
      expect(notificationsService.hasPermission, false);
      expect(notificationsService.notifications, isEmpty);
      verify(mockChannel.checkNotificationListenerPermission()).called(1);
      verifyNever(mockChannel.getActiveNotifications());
      verifyNever(mockChannel.addNotificationsChangedListener(any));
    });

    test('fetches notifications and subscribes when permission granted', () async {
      when(mockChannel.checkNotificationListenerPermission())
          .thenAnswer((_) async => true);
      when(mockChannel.getActiveNotifications())
          .thenAnswer((_) async => [
                for (var i = 0; i < 2; i++) clearable('com.android.settings', 'settings_$i'),
                for (var i = 0; i < 5; i++) clearable('com.thesiegs.hearth', 'ltv_$i'),
              ]);

      notificationsService = NotificationsService(mockChannel, prefs);
      
      while (!notificationsService.initialized) {
        await Future.delayed(Duration.zero);
      }

      expect(notificationsService.initialized, true);
      expect(notificationsService.hasPermission, true);
      expect(notificationsService.getNotificationCount('com.android.settings'), 2);
      expect(notificationsService.getNotificationCount('com.thesiegs.hearth'), 5);
      verify(mockChannel.checkNotificationListenerPermission()).called(1);
      verify(mockChannel.getActiveNotifications()).called(1);
      verify(mockChannel.addNotificationsChangedListener(any)).called(1);
    });
  });

  group('Permission Changes', () {
    test('checkPermission updates state and notifies when changed', () async {
      notificationsService = NotificationsService(mockChannel, prefs);
      while (!notificationsService.initialized) {
        await Future.delayed(Duration.zero);
      }
      expect(notificationsService.hasPermission, false);

      // Change permission to true
      when(mockChannel.checkNotificationListenerPermission())
          .thenAnswer((_) async => true);

      bool notified = false;
      notificationsService.addListener(() {
        notified = true;
      });

      await notificationsService.checkPermission();

      expect(notificationsService.hasPermission, true);
      expect(notified, true);
    });

    test('both checks at once, as on resume, pick up newly granted permissions', () async {
      notificationsService = NotificationsService(mockChannel, prefs);
      while (!notificationsService.initialized) {
        await Future.delayed(Duration.zero);
      }
      when(mockChannel.checkNotificationListenerPermission()).thenAnswer((_) async => true);
      when(mockChannel.checkOverlayPermission()).thenAnswer((_) async => true);
      when(mockChannel.getActiveNotifications()).thenAnswer((_) async => [
            {'packageName': 'com.netflix.ninja', 'key': 'net_1', 'title': 'Netflix', 'isClearable': true},
          ]);

      final permission = notificationsService.checkPermission();
      final overlay = notificationsService.checkOverlayPermission();
      await Future.wait([permission, overlay]);

      expect(notificationsService.hasPermission, isTrue);
      expect(notificationsService.hasOverlayPermission, isTrue);
      expect(notificationsService.notifications.map((n) => n.key), ['net_1']);
      verify(mockChannel.addNotificationsChangedListener(any)).called(1);
    });
  });

  group('Notification Updates', () {
    test('stream updates trigger notifier with updated counts', () async {
      when(mockChannel.checkNotificationListenerPermission())
          .thenAnswer((_) async => true);
      
      notificationsService = NotificationsService(mockChannel, prefs);
      while (!notificationsService.initialized) {
        await Future.delayed(Duration.zero);
      }

      bool notified = false;
      notificationsService.addListener(() {
        notified = true;
      });

      // Push stream event
      streamController.add([
        clearable('com.android.settings', 'settings_0'),
      ]);
      await Future.delayed(Duration.zero);

      expect(notificationsService.getNotificationCount('com.android.settings'), 1);
      expect(notified, true);
    });

    test('ignores stream updates with identical counts to prevent redundant notifies', () async {
      when(mockChannel.checkNotificationListenerPermission())
          .thenAnswer((_) async => true);
      when(mockChannel.getActiveNotifications())
          .thenAnswer((_) async => [
                clearable('com.android.settings', 'settings_0'),
              ]);

      notificationsService = NotificationsService(mockChannel, prefs);
      while (!notificationsService.initialized) {
        await Future.delayed(Duration.zero);
      }

      int notifyCount = 0;
      notificationsService.addListener(() {
        notifyCount++;
      });

      // Push same stream event
      streamController.add([
        clearable('com.android.settings', 'settings_0'),
      ]);
      await Future.delayed(Duration.zero);

      expect(notifyCount, 0);
    });
  });

  group('Overlay Popup Settings', () {
    test('initializes with default overlay permission and toggle state', () async {
      notificationsService = NotificationsService(mockChannel, prefs);
      while (!notificationsService.initialized) {
        await Future.delayed(Duration.zero);
      }
      expect(notificationsService.hasOverlayPermission, false);
      expect(notificationsService.systemPopupEnabled, false);
    });

    test('toggles system popup state and saves to preferences', () async {
      notificationsService = NotificationsService(mockChannel, prefs);
      while (!notificationsService.initialized) {
        await Future.delayed(Duration.zero);
      }
      expect(notificationsService.systemPopupEnabled, false);

      await notificationsService.setSystemPopupEnabled(true);
      expect(notificationsService.systemPopupEnabled, true);

      await notificationsService.setSystemPopupEnabled(false);
      expect(notificationsService.systemPopupEnabled, false);
    });

    test('requests overlay permission from channel', () async {
      notificationsService = NotificationsService(mockChannel, prefs);
      while (!notificationsService.initialized) {
        await Future.delayed(Duration.zero);
      }

      await notificationsService.requestOverlayPermission();
      verify(mockChannel.requestOverlayPermission()).called(1);
    });
  });

  group('Notification Dismissal', () {
    test('dismiss cancels notification and refreshes', () async {
      when(mockChannel.checkNotificationListenerPermission())
          .thenAnswer((_) async => true);
      when(mockChannel.getActiveNotifications())
          .thenAnswer((_) async => [
                {'packageName': 'com.android.settings', 'key': 'key_1', 'isClearable': true},
              ]);
      when(mockChannel.dismissNotification(any))
          .thenAnswer((_) async => true);

      notificationsService = NotificationsService(mockChannel, prefs);
      while (!notificationsService.initialized) {
        await Future.delayed(Duration.zero);
      }

      expect(notificationsService.notifications.length, 1);
      expect(notificationsService.notifications[0].key, 'key_1');

      // Stub empty return for refresh
      when(mockChannel.getActiveNotifications())
          .thenAnswer((_) async => []);

      await notificationsService.dismiss('key_1');

      verify(mockChannel.dismissNotification('key_1')).called(1);
      verify(mockChannel.getActiveNotifications()).called(2); // Initial + refresh
      expect(notificationsService.notifications, isEmpty);
    });

    test('dismissAll cancels all notifications and refreshes', () async {
      when(mockChannel.checkNotificationListenerPermission())
          .thenAnswer((_) async => true);
      when(mockChannel.getActiveNotifications())
          .thenAnswer((_) async => [
                {'packageName': 'com.android.settings', 'key': 'key_1', 'isClearable': true},
                {'packageName': 'com.thesiegs.hearth', 'key': 'key_2', 'isClearable': true},
              ]);
      when(mockChannel.dismissAllNotifications())
          .thenAnswer((_) async => true);

      notificationsService = NotificationsService(mockChannel, prefs);
      while (!notificationsService.initialized) {
        await Future.delayed(Duration.zero);
      }

      expect(notificationsService.notifications.length, 2);

      // Stub empty return for refresh
      when(mockChannel.getActiveNotifications())
          .thenAnswer((_) async => []);

      await notificationsService.dismissAll();

      verify(mockChannel.dismissAllNotifications()).called(1);
      verify(mockChannel.getActiveNotifications()).called(2); // Initial + refresh
      expect(notificationsService.notifications, isEmpty);
    });
  });

  group('Persistent Notification & App Blocking', () {
    test('hidePersistentNotifications filters out non-clearable notifications', () async {
      when(mockChannel.checkNotificationListenerPermission())
          .thenAnswer((_) async => true);
      when(mockChannel.getActiveNotifications())
          .thenAnswer((_) async => [
                {'packageName': 'com.tcl.tv', 'key': 'tcl_bg', 'title': 'TCL Service', 'isClearable': false},
                {'packageName': 'com.google.android.youtube', 'key': 'yt_1', 'title': 'Video', 'isClearable': true},
              ]);

      notificationsService = NotificationsService(mockChannel, prefs);
      while (!notificationsService.initialized) {
        await Future.delayed(Duration.zero);
      }

      expect(notificationsService.hidePersistentNotifications, false);
      expect(notificationsService.notifications.length, 2);

      await notificationsService.setHidePersistentNotifications(true);

      expect(notificationsService.hidePersistentNotifications, true);
      expect(notificationsService.notifications.length, 1);
      expect(notificationsService.notifications.first.packageName, 'com.google.android.youtube');

      await notificationsService.setHidePersistentNotifications(false);
      expect(notificationsService.notifications.length, 2);
    });

    test('permanent notifications with no title or text are never listed or counted', () async {
      when(mockChannel.checkNotificationListenerPermission())
          .thenAnswer((_) async => true);
      when(mockChannel.getActiveNotifications())
          .thenAnswer((_) async => [
                // Google TV's own background entries: permanent and blank
                {'packageName': 'com.google.android.apps.tv.launcherx', 'key': 'gtv_1', 'title': '', 'text': '', 'isClearable': false},
                {'packageName': 'com.google.android.apps.tv.launcherx', 'key': 'gtv_2', 'isClearable': false},
                {'packageName': 'com.google.android.youtube', 'key': 'yt_1', 'title': 'Video', 'isClearable': true},
              ]);

      notificationsService = NotificationsService(mockChannel, prefs);
      while (!notificationsService.initialized) {
        await Future.delayed(Duration.zero);
      }

      expect(notificationsService.notifications.length, 1);
      expect(notificationsService.notifications.first.packageName, 'com.google.android.youtube');
    });

    test('blockPackage and unblockPackage filters out notifications from blocked apps', () async {
      when(mockChannel.checkNotificationListenerPermission())
          .thenAnswer((_) async => true);
      when(mockChannel.getActiveNotifications())
          .thenAnswer((_) async => [
                {'packageName': 'com.sony.dtv', 'key': 'sony_1', 'title': 'Sony', 'isClearable': false},
                {'packageName': 'com.llamalab.automate', 'key': 'auto_1', 'title': 'Automate', 'isClearable': false},
                {'packageName': 'com.netflix.ninja', 'key': 'net_1', 'title': 'Netflix', 'isClearable': true},
              ]);

      notificationsService = NotificationsService(mockChannel, prefs);
      while (!notificationsService.initialized) {
        await Future.delayed(Duration.zero);
      }

      expect(notificationsService.notifications.length, 3);
      expect(notificationsService.blockedPackages.contains('com.sony.dtv'), false);

      await notificationsService.blockPackage('com.sony.dtv');
      expect(notificationsService.blockedPackages.contains('com.sony.dtv'), true);
      expect(notificationsService.notifications.length, 2);
      expect(notificationsService.notifications.any((n) => n.packageName == 'com.sony.dtv'), false);

      await notificationsService.blockPackage('com.llamalab.automate');
      expect(notificationsService.notifications.length, 1);
      expect(notificationsService.notifications.first.packageName, 'com.netflix.ninja');

      await notificationsService.unblockPackage('com.sony.dtv');
      expect(notificationsService.notifications.length, 2);

      await notificationsService.unblockAllPackages();
      expect(notificationsService.blockedPackages, isEmpty);
      expect(notificationsService.notifications.length, 3);
    });
  });

  group('Dismissing persistent notifications', () {
    Map<String, Object> persistent(String key) =>
        {'key': key, 'packageName': 'com.thesiegs.hearthtube', 'title': 'Background service', 'text': '', 'isClearable': false};

    Future<NotificationsService> ready() async {
      when(mockChannel.checkNotificationListenerPermission()).thenAnswer((_) async => true);
      when(mockChannel.dismissNotification(any)).thenAnswer((_) async => true);
      final service = NotificationsService(mockChannel, prefs);
      while (!service.initialized) {
        await Future.delayed(Duration.zero);
      }
      return service;
    }

    test('hides a persistent notification on dismiss instead of asking Android to cancel it', () async {
      when(mockChannel.getActiveNotifications()).thenAnswer((_) async => [persistent('k1')]);
      final service = await ready();
      expect(service.notifications.map((n) => n.key), ['k1']);

      await service.dismiss('k1');

      expect(service.notifications, isEmpty);
      verifyNever(mockChannel.dismissNotification(any));
    });

    test('shows it again once its app has removed it and posts it anew', () async {
      when(mockChannel.getActiveNotifications()).thenAnswer((_) async => [persistent('k1')]);
      final service = await ready();
      await service.dismiss('k1');

      streamController.add([]);
      await Future.delayed(Duration.zero);
      streamController.add([persistent('k1')]);
      await Future.delayed(Duration.zero);

      expect(service.notifications.map((n) => n.key), ['k1']);
    });
  });
}
