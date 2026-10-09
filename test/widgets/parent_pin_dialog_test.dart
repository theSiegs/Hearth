import 'package:flauncher/l10n/app_localizations.dart';
import 'package:flauncher/providers/profile_service.dart';
import 'package:flauncher/providers/settings_service.dart';
import 'package:flauncher/widgets/parent_pin_dialog.dart';
import 'package:flutter/material.dart';
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
}
