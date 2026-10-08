import 'package:flauncher/l10n/app_localizations.dart';
import 'package:flauncher/providers/settings_service.dart';
import 'package:flauncher/widgets/settings/accent_color_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets("select on a swatch makes it the accent colour", (tester) async {
    SharedPreferences.setMockInitialValues({});
    final settingsService = SettingsService(await SharedPreferences.getInstance());
    await tester.pumpWidget(ChangeNotifierProvider.value(
      value: settingsService,
      child: const MaterialApp(
        localizationsDelegates: [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(body: AccentColorPage()),
      ),
    ));
    await tester.pumpAndSettle();

    expect(Focus.of(tester.element(find.text("Purple"))).hasFocus, isTrue);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();
    expect(Focus.of(tester.element(find.text("Teal"))).hasFocus, isTrue);

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(settingsService.accentColorHex, ACCENT_COLOR_TEAL);
  });
}
