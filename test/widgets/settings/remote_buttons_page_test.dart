import 'dart:convert';

import 'package:flauncher/l10n/app_localizations.dart';
import 'package:flauncher/flauncher_channel.dart';
import 'package:flauncher/providers/apps_service.dart';
import 'package:flauncher/providers/tv_inputs_service.dart';
import 'package:flauncher/widgets/settings/remote_buttons_page.dart';
import 'package:flauncher/widgets/settings/focusable_settings_tile.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:provider/provider.dart';

import '../../mocks.dart';
import '../../mocks.mocks.dart';

const _channel = MethodChannel('me.efesser.flauncher/method');

void main() {
  late MockTvInputsService tvInputsService;
  late MockAppsService appsService;
  late List<String> saved;

  setUp(() {
    tvInputsService = MockTvInputsService();
    when(tvInputsService.inputs).thenReturn([]);
    appsService = MockAppsService();
    when(appsService.applications)
        .thenReturn([fakeApp(packageName: AppsService.hearthTube, name: "HearthTube")]);
    saved = [];
  });

  Future<void> pumpPage(WidgetTester tester,
      {String mappings =
          '{"183":{"name":"KEYCODE_PROG_RED","short":{"type":"app","target":"com.thesiegs.hearthtube","label":"HearthTube"}}}'}) async {
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      _channel,
      (call) async {
        switch (call.method) {
          case "getButtonMappings":
            return mappings;
          case "setButtonMappings":
            saved.add(call.arguments as String);
            return null;
          case "getHaEntities":
            return "[]";
        }
        return null;
      },
    );
    addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(_channel, null));

    await tester.pumpWidget(MultiProvider(
      providers: [
        Provider<FLauncherChannel>.value(value: FLauncherChannel()),
        ChangeNotifierProvider<AppsService>.value(value: appsService),
        ChangeNotifierProvider<TvInputsService>.value(value: tvInputsService),
      ],
      child: const MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(body: RemoteButtonsPage())),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets("lists remapped buttons with readable names", (tester) async {
    await pumpPage(tester);

    expect(find.text("Remote buttons"), findsOneWidget);
    expect(find.text("Remap a button"), findsOneWidget);
    expect(find.textContaining("Red\nPress: HearthTube"), findsOneWidget);
    expect(find.textContaining("Hold: Normal"), findsOneWidget);
  });

  testWidgets("a Home Assistant action without Home Assistant says where to set it up", (tester) async {
    await pumpPage(tester);

    await tester.tap(find.textContaining("Red\nPress: HearthTube"));
    await tester.pumpAndSettle();
    await tester.tap(find.text("Press: HearthTube"));
    await tester.pumpAndSettle();
    await tester.tap(find.text("Home Assistant…"));
    await tester.pumpAndSettle();

    expect(find.text("Connect Home Assistant first"), findsOneWidget);
    expect(
      find.text("Set up the Home Assistant panel (Settings > Home Assistant > Dashboard panel > Set up from your "
          "phone), then try again."),
      findsOneWidget,
    );
    expect(Focus.of(tester.element(find.text("OK"))).hasFocus, isTrue);
  });

  group("YouTube button opens HearthTube", () {
    Icon checkbox(WidgetTester tester) => tester.widget<Icon>(find.descendant(
        of: find.ancestor(of: find.text("YouTube button opens HearthTube"), matching: find.byType(FocusableSettingsTile)).first,
        matching: find.byWidgetPredicate((w) =>
            w is Icon && (w.icon == Icons.check_box || w.icon == Icons.check_box_outline_blank))));

    testWidgets("is off until chosen, then maps the YouTube button to HearthTube", (tester) async {
      await pumpPage(tester, mappings: "{}");
      expect(checkbox(tester).icon, Icons.check_box_outline_blank);

      await tester.tap(find.text("YouTube button opens HearthTube"));
      await tester.pumpAndSettle();

      expect(checkbox(tester).icon, Icons.check_box);
      expect(json.decode(saved.single), {
        "190": {
          "name": "KEYCODE_BUTTON_3",
          "short": {"type": "app", "target": "com.thesiegs.hearthtube", "label": "HearthTube"},
        }
      });
      expect(find.textContaining("YouTube button\nPress: HearthTube"), findsOneWidget);
    });

    testWidgets("turned off, the YouTube button does its normal job again", (tester) async {
      await pumpPage(tester,
          mappings: '{"190":{"name":"KEYCODE_BUTTON_3","short":{"type":"app","target":"com.thesiegs.hearthtube"}}}');
      expect(checkbox(tester).icon, Icons.check_box);

      await tester.tap(find.text("YouTube button opens HearthTube"));
      await tester.pumpAndSettle();

      expect(json.decode(saved.single), isEmpty);
      expect(checkbox(tester).icon, Icons.check_box_outline_blank);
    });

    testWidgets("isn't offered without HearthTube", (tester) async {
      when(appsService.applications).thenReturn([]);
      await pumpPage(tester);
      expect(find.text("YouTube button opens HearthTube"), findsNothing);
    });
  });
}
