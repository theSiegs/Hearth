import 'dart:async';

import 'package:flauncher/widgets/settings/ha_phone_setup_dialog.dart';
import 'package:flauncher/widgets/settings/phone_setup_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../mocks.mocks.dart';
import 'settings_test_app.dart';

const _link = "http://192.0.2.10:8299/setup?t=abc#key=secret";

/// The phone page's start, stop and done, as the dialog calls them.
class _FakePage {
  final Completer<String?> started = Completer();
  var starts = 0;
  var stops = 0;
  var checks = 0;
  bool received = false;
  Object? failStart;

  Future<String?> start() {
    starts++;
    if (failStart != null) return Future.error(failStart!);
    return started.future;
  }

  Future<void> stop() async => stops++;

  Future<bool> done() async {
    checks++;
    return received;
  }
}

/// Opens [dialog] from a page and keeps what it popped with.
Future<List<bool?>> _open(WidgetTester tester, Widget dialog) async {
  final results = <bool?>[];
  await tester.pumpWidget(settingsTestApp(
    await freshSettings(),
    Builder(
      builder: (context) => TextButton(
        onPressed: () async => results.add(await showDialog<bool>(context: context, builder: (_) => dialog)),
        child: const Text("open"),
      ),
    ),
  ));
  await tester.tap(find.text("open"));
  await tester.pump();
  return results;
}

PhoneSetupDialog _dialog(_FakePage page) => PhoneSetupDialog(
      title: "Set up from your phone",
      scanText: "Scan it",
      start: page.start,
      stop: page.stop,
      done: page.done,
    );

void main() {
  group("PhoneSetupDialog", () {
    testWidgets("waits for the page, then shows its QR code and the link without the phone's key", (tester) async {
      final page = _FakePage();
      await _open(tester, _dialog(page));

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.byType(QrImageView), findsNothing);
      expect(page.starts, 1);

      page.started.complete(_link);
      await tester.pump();
      await tester.pump();

      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.byType(QrImageView), findsOneWidget);
      expect(find.text("http://192.0.2.10:8299/setup?t=abc"), findsOneWidget);
      expect(find.textContaining("secret"), findsNothing);
      expect(find.text("Scan it"), findsOneWidget);
      expect(hasFocusOn(tester, "Close"), isTrue);

      await tester.tap(find.text("Close"));
      await tester.pumpAndSettle();
    });

    testWidgets("asks every second and closes with true once the phone has sent it", (tester) async {
      final page = _FakePage();
      final results = await _open(tester, _dialog(page));
      page.started.complete(_link);
      await tester.pump();
      await tester.pump();

      await tester.pump(const Duration(seconds: 1));
      await tester.pump(const Duration(seconds: 1));
      expect(page.checks, 2);
      expect(results, isEmpty);

      page.received = true;
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();
      expect(results, [true]);
      expect(page.stops, 1, reason: "the page ends with the dialog");

      // No more asking once it's closed
      final checks = page.checks;
      await tester.pump(const Duration(seconds: 3));
      expect(page.checks, checks);
    });

    testWidgets("without a network it says so and doesn't ask", (tester) async {
      final page = _FakePage();
      await _open(tester, _dialog(page));
      page.started.complete(null);
      await tester.pump();
      await tester.pump();

      expect(find.text("This TV isn't on the home network, so the phone can't reach it."), findsOneWidget);
      expect(find.byType(QrImageView), findsNothing);
      await tester.pump(const Duration(seconds: 3));
      expect(page.checks, 0);

      await tester.tap(find.text("Close"));
      await tester.pumpAndSettle();
    });

    testWidgets("a page that fails to start counts as no network", (tester) async {
      final page = _FakePage()..failStart = PlatformException(code: "ERROR");
      await _open(tester, _dialog(page));
      await tester.pump();
      await tester.pump();

      expect(find.text("This TV isn't on the home network, so the phone can't reach it."), findsOneWidget);
      await tester.tap(find.text("Close"));
      await tester.pumpAndSettle();
    });

    testWidgets("Close ends the page and closes with false", (tester) async {
      final page = _FakePage();
      final results = await _open(tester, _dialog(page));
      page.started.complete(_link);
      await tester.pump();
      await tester.pump();

      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(results, [false]);
      expect(page.stops, 1);
    });
  });

  group("HaPhoneSetupDialog", () {
    testWidgets("runs Home Assistant's phone page through the channel", (tester) async {
      final channel = MockFLauncherChannel();
      var received = false;
      when(channel.startHaSetup()).thenAnswer((_) async => _link);
      when(channel.stopHaSetup()).thenAnswer((_) async {});
      when(channel.getHaSetupReceived()).thenAnswer((_) async => received);

      final results = await _open(tester, HaPhoneSetupDialog(channel: channel));
      await tester.pump();
      await tester.pump();

      verify(channel.startHaSetup()).called(1);
      expect(find.text("Set up from your phone"), findsOneWidget);
      expect(find.textContaining("paste the Home Assistant address and access token"), findsOneWidget);
      expect(find.byType(QrImageView), findsOneWidget);

      received = true;
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();
      expect(results, [true]);
      verify(channel.getHaSetupReceived()).called(greaterThanOrEqualTo(1));
      verify(channel.stopHaSetup()).called(1);
    });
  });
}
