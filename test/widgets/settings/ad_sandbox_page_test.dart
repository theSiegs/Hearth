import 'package:flauncher/flauncher_channel.dart';
import 'package:flauncher/l10n/app_localizations.dart';
import 'package:flauncher/providers/settings_service.dart';
import 'package:flauncher/widgets/parent_pin_dialog.dart';
import 'package:flauncher/widgets/settings/ad_sandbox_page.dart';
import 'package:flauncher/widgets/settings/focusable_settings_tile.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:provider/provider.dart';

import '../../mocks.mocks.dart';

const _channel = MethodChannel('me.efesser.flauncher/method');
const _packages = [
  "com.android.adservices.api",
  "com.android.ondevicepersonalization.services",
  "com.android.federatedcompute.services",
];

void main() {
  late MockSettingsService settings;
  late bool keptOff;
  late List<String> installed;
  late List<bool> runs;
  late bool fails;
  late bool stillOn;

  setUp(() {
    settings = MockSettingsService();
    when(settings.hasParentPin).thenReturn(false);
    keptOff = false;
    installed = List.of(_packages);
    runs = [];
    fails = false;
    stillOn = false;
  });

  Future<void> pumpPage(WidgetTester tester) async {
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(_channel, (call) async {
      switch (call.method) {
        case "getAdSandbox":
          return {"keptOff": keptOff, "installed": installed, "on": keptOff && !stillOn ? <String>[] : installed};
        case "getAdSandboxCommands":
          final off = call.arguments == true;
          return [for (final p in installed) off ? "pm disable-user --user 0 $p" : "pm enable --user 0 $p"];
        case "setAdSandboxKeptOff":
          if (fails) throw PlatformException(code: "SELF_ADB", message: "not allowed");
          runs.add(call.arguments as bool);
          keptOff = call.arguments as bool;
          return <String>[];
      }
      return null;
    });
    addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(_channel, null));
    await tester.pumpWidget(MultiProvider(
      providers: [
        Provider<FLauncherChannel>.value(value: FLauncherChannel()),
        ChangeNotifierProvider<SettingsService>.value(value: settings),
      ],
      child: const MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(body: AdSandboxPage())),
    ));
    await tester.pumpAndSettle();
  }

  IconData checkbox(WidgetTester tester) => tester
      .widget<Icon>(find.descendant(
          of: find.ancestor(of: find.text("Keep ad tracking off"), matching: find.byType(FocusableSettingsTile)).first,
          matching: find.byWidgetPredicate(
              (w) => w is Icon && (w.icon == Icons.check_box || w.icon == Icons.check_box_outline_blank))))
      .icon!;

  testWidgets("kept off but still on: Turn it off now does it, with no commands to read", (tester) async {
    keptOff = true;
    stillOn = true;
    await pumpPage(tester);
    expect(find.text("Ad tracking"), findsOneWidget);
    expect(find.text("Still on on this TV. Choose Turn it off now."), findsOneWidget);
    expect(find.textContaining("pm "), findsNothing);
    stillOn = false;
    await tester.tap(find.text("Turn it off now"));
    await tester.pumpAndSettle();
    expect(runs, [true]);
    expect(find.text("Off on this TV."), findsOneWidget);
    expect(find.text("Turn it off now"), findsNothing);
  });

  testWidgets("turning it on runs at once, with no PIN, and says it's off", (tester) async {
    when(settings.hasParentPin).thenReturn(true);
    await pumpPage(tester);
    expect(checkbox(tester), Icons.check_box_outline_blank);
    expect(find.text("On. Turn on Keep ad tracking off to stop it."), findsOneWidget);
    await tester.tap(find.text("Keep ad tracking off"));
    await tester.pumpAndSettle();
    expect(find.byType(ParentPinDialog), findsNothing);
    expect(find.textContaining("pm "), findsNothing);
    expect(runs, [true]);
    expect(checkbox(tester), Icons.check_box);
    expect(find.text("Off on this TV."), findsOneWidget);
  });

  testWidgets("letting ad tracking back on asks for the parent PIN", (tester) async {
    when(settings.hasParentPin).thenReturn(true);
    keptOff = true;
    await pumpPage(tester);
    await tester.tap(find.text("Keep ad tracking off"));
    await tester.pumpAndSettle();
    expect(find.byType(ParentPinDialog), findsOneWidget);
    expect(runs, isEmpty);
  });

  testWidgets("without a parent PIN, turning the switch off lets it back on", (tester) async {
    keptOff = true;
    await pumpPage(tester);
    await tester.tap(find.text("Keep ad tracking off"));
    await tester.pumpAndSettle();
    expect(runs, [false]);
    expect(checkbox(tester), Icons.check_box_outline_blank);
  });

  testWidgets("says so when Hearth's debugging doesn't answer", (tester) async {
    fails = true;
    await pumpPage(tester);
    await tester.tap(find.text("Keep ad tracking off"));
    await tester.pumpAndSettle();
    expect(find.text("Hearth couldn't do it"), findsOneWidget);
  });

  testWidgets("a TV without it has no switch", (tester) async {
    installed = [];
    await pumpPage(tester);
    expect(find.text("This TV doesn't have Google's ad tracking."), findsOneWidget);
    expect(find.text("Keep ad tracking off"), findsNothing);
  });
}
