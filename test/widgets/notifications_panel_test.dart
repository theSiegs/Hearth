import 'dart:typed_data';

import 'package:flauncher/l10n/app_localizations.dart';
import 'package:flauncher/providers/apps_service.dart';
import 'package:flauncher/providers/notifications_service.dart';
import 'package:flauncher/widgets/settings/notifications_panel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:provider/provider.dart';

import '../mocks.mocks.dart';

void main() {
  setUpAll(() async {
    final binding = TestWidgetsFlutterBinding.ensureInitialized();
    binding.platformDispatcher.implicitView!.physicalSize = const Size(1280, 720);
    binding.platformDispatcher.implicitView!.devicePixelRatio = 1.0;
    binding.platformDispatcher.textScaleFactorTestValue = 0.8;
  });

  Future<MockNotificationsService> pumpWith(WidgetTester tester, NotificationItem item) async {
    final notifications = MockNotificationsService();
    final apps = MockAppsService();
    when(notifications.notifications).thenReturn([item]);
    when(notifications.hidePersistentNotifications).thenReturn(false);
    when(notifications.open(any, action: anyNamed('action'))).thenAnswer((_) async => true);
    when(apps.applications).thenReturn([]);
    when(apps.getAppIcon(any)).thenAnswer((_) async => Uint8List(0));
    await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider<NotificationsService>.value(value: notifications),
        ChangeNotifierProvider<AppsService>.value(value: apps),
      ],
      child: const MaterialApp(
        localizationsDelegates: [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
        ],
        home: NotificationsPanel(),
      ),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.text(item.title));
    await tester.pumpAndSettle();
    return notifications;
  }

  bool focused(WidgetTester tester, String label) =>
      Focus.of(tester.element(find.descendant(of: find.byType(AlertDialog), matching: find.text(label)))).hasFocus;

  NotificationItem doorbell({required bool careful}) => NotificationItem(
        key: 'hearth:notice:ha:0123abcd|',
        packageName: 'com.thesiegs.hearth',
        appLabel: 'Home Assistant',
        title: 'Doorbell',
        text: 'Someone is at the door',
        isClearable: true,
        actions: const [NotificationAction(0, 'Unlock door'), NotificationAction(1, 'Ignore')],
        carefulActions: careful,
      );

  testWidgets("a Home Assistant notification's options open on Dismiss, never on a button that acts on the home",
      (tester) async {
    final notifications = await pumpWith(tester, doorbell(careful: true));
    expect(find.text('Unlock door'), findsOneWidget);
    expect(focused(tester, 'Dismiss'), isTrue);
    expect(focused(tester, 'Unlock door'), isFalse);

    // Pressed on purpose, it goes to the TV with its number
    await tester.tap(find.text('Unlock door'));
    await tester.pumpAndSettle();
    verify(notifications.open('hearth:notice:ha:0123abcd|', action: 0)).called(1);
  });

  testWidgets("an app's notification still opens its options on its first button", (tester) async {
    await pumpWith(tester, doorbell(careful: false));
    expect(focused(tester, 'Unlock door'), isTrue);
    expect(focused(tester, 'Dismiss'), isFalse);
  });
}
