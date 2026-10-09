import 'package:flauncher/l10n/app_localizations.dart';
import 'package:flauncher/flauncher_channel.dart';
import 'package:flauncher/providers/apps_service.dart';
import 'package:flauncher/providers/tv_inputs_service.dart';
import 'package:flauncher/widgets/settings/remote_buttons_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:provider/provider.dart';

import '../../mocks.mocks.dart';

const _channel = MethodChannel('me.efesser.flauncher/method');

void main() {
  late MockTvInputsService tvInputsService;

  setUp(() {
    tvInputsService = MockTvInputsService();
    when(tvInputsService.inputs).thenReturn([]);
  });

  Future<void> pumpPage(WidgetTester tester) async {
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      _channel,
      (call) async => switch (call.method) {
        "getButtonMappings" =>
          '{"183":{"name":"KEYCODE_PROG_RED","short":{"type":"app","target":"com.thesiegs.hearthtube","label":"HearthTube"}}}',
        "getHaEntities" => "[]",
        _ => null,
      },
    );
    addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(_channel, null));

    await tester.pumpWidget(MultiProvider(
      providers: [
        Provider<FLauncherChannel>.value(value: FLauncherChannel()),
        ChangeNotifierProvider<AppsService>.value(value: MockAppsService()),
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
}
