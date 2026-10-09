import 'dart:math';

import 'package:flauncher/l10n/app_localizations.dart';
import 'package:flauncher/providers/profile_service.dart';
import 'package:flauncher/providers/settings_service.dart';
import 'package:flauncher/widgets/parent_pin_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:provider/provider.dart';

import '../mocks.mocks.dart';

void main() {
  late MockSettingsService settings;
  late MockProfileService profile;
  bool? allowed;

  setUp(() {
    settings = MockSettingsService();
    profile = MockProfileService();
    allowed = null;
  });

  Future<void> pump(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 2.0; // TVs lay out at ~960x540
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider<SettingsService>.value(value: settings),
        ChangeNotifierProvider<ProfileService>.value(value: profile),
      ],
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async => allowed = await requireParent(context),
            child: const Text("open"),
          ),
        ),
      ),
    ));
    await tester.tap(find.text("open"));
    await tester.pumpAndSettle();
  }

  testWidgets("adult profiles go straight through", (tester) async {
    when(profile.isKidsProfile).thenReturn(false);
    await pump(tester);
    expect(allowed, isTrue);
  });

  testWidgets("kids profile without a parent PIN is turned away", (tester) async {
    when(profile.isKidsProfile).thenReturn(true);
    when(settings.hasParentPin).thenReturn(false);
    await pump(tester);

    expect(find.text("Ask a parent"), findsOneWidget);
    await tester.tap(find.text("OK"));
    await tester.pumpAndSettle();
    expect(allowed, isFalse);
  });

  testWidgets("kids profile needs the right parent PIN", (tester) async {
    when(profile.isKidsProfile).thenReturn(true);
    when(settings.hasParentPin).thenReturn(true);
    when(settings.verifyParentPin(any)).thenAnswer((i) => i.positionalArguments[0] == "2468");
    await pump(tester);

    for (final digit in ["1", "1", "1", "1"]) {
      await tester.tap(find.text(digit));
      await tester.pump();
    }
    expect(find.text("WRONG PIN"), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 500));
    expect(allowed, isNull);

    for (final digit in ["2", "4", "6", "8"]) {
      await tester.tap(find.text(digit));
      await tester.pump();
    }
    await tester.pumpAndSettle();
    expect(allowed, isTrue);
  });

  testWidgets("the remote's number keys type the PIN too", (tester) async {
    when(profile.isKidsProfile).thenReturn(true);
    when(settings.hasParentPin).thenReturn(true);
    when(settings.verifyParentPin(any)).thenAnswer((i) => i.positionalArguments[0] == "2468");
    await pump(tester);

    for (final key in [
      LogicalKeyboardKey.digit2,
      LogicalKeyboardKey.digit4,
      LogicalKeyboardKey.digit6,
      LogicalKeyboardKey.digit8,
    ]) {
      await tester.sendKeyEvent(key);
      await tester.pump();
    }
    await tester.pumpAndSettle();
    expect(allowed, isTrue);
  });

  testWidgets("the row pad: Up/Down pick a row, Left/OK/Right its first/middle/last digit, ⌫ under the rows",
      (tester) async {
    // The same seed shuffles the same way here as in the dialog
    final places = [for (int d = 0; d <= 9; d++) "$d", "", ""]..shuffle(Random(7));
    final rows = [for (int r = 0; r < 4; r++) places.sublist(r * 3, r * 3 + 3)];
    String? result;
    await tester.pumpWidget(MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Builder(
        builder: (context) => TextButton(
          onPressed: () async => result = await showDialog<String>(
              context: context, builder: (_) => ParentPinDialog(title: "PIN", random: Random(7))),
          child: const Text("open"),
        ),
      ),
    ));
    await tester.tap(find.text("open"));
    await tester.pumpAndSettle();

    // Each digit as remote keys from row 0: Down to its row, then Left/OK/Right, then back Up to row 0
    Future<void> enter(String digit) async {
      final row = rows.indexWhere((r) => r.contains(digit));
      final place = rows[row].indexOf(digit);
      for (int i = 0; i < row; i++) {
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      }
      await tester.sendKeyEvent(
          [LogicalKeyboardKey.arrowLeft, LogicalKeyboardKey.select, LogicalKeyboardKey.arrowRight][place]);
      for (int i = 0; i < row; i++) {
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      }
      await tester.pump();
    }

    await enter("9");
    // ⌫ is under the last row: it takes the 9 back
    for (int i = 0; i < 4; i++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    }
    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    for (int i = 0; i < 4; i++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    }
    for (final digit in "2468".split("")) {
      await enter(digit);
    }
    await tester.pumpAndSettle();
    expect(result, "2468");
  });
}
