import 'package:flauncher/l10n/app_localizations.dart';
import 'package:flauncher/providers/settings_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A SettingsService over empty (or [values]) preferences.
Future<SettingsService> freshSettings([Map<String, Object> values = const {}]) async {
  SharedPreferences.setMockInitialValues(values);
  return SettingsService(await SharedPreferences.getInstance());
}

/// [home] in an English MaterialApp under [settings], with [routes] as named pages a tile may open.
Widget settingsTestApp(SettingsService settings, Widget home, {Map<String, WidgetBuilder> routes = const {}}) =>
    ChangeNotifierProvider<SettingsService>.value(
      value: settings,
      child: MaterialApp(
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('en'),
        routes: routes,
        home: Scaffold(body: home),
      ),
    );

/// Whether the focus is on (or inside) the widget that shows [text].
bool hasFocusOn(WidgetTester tester, String text) => Focus.of(tester.element(find.text(text))).hasFocus;
