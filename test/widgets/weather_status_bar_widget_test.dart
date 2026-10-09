import 'package:flauncher/l10n/app_localizations.dart';
import 'package:flauncher/models/weather_data.dart';
import 'package:flauncher/providers/settings_service.dart';
import 'package:flauncher/providers/weather_service.dart';
import 'package:flauncher/widgets/weather_status_bar_widget.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
import 'package:mockito/mockito.dart';
import 'package:provider/provider.dart';

import '../mocks.mocks.dart';

void main() {
  late MockSettingsService mockSettingsService;
  late MockWeatherService mockWeatherService;

  final testWeatherWithWarning = WeatherData.fromJsonString('''
  {
    "currentTemp": 27,
    "currentConditionCode": 800,
    "currentCondition": "Clear",
    "forecasts": [
      {
        "conditionCode": 500,
        "precipProbability": 80,
        "minTemp": 20,
        "maxTemp": 30
      }
    ]
  }
  ''');

  setUp(() {
    mockSettingsService = MockSettingsService();
    mockWeatherService = MockWeatherService();

    when(mockSettingsService.showWeatherInStatusBar).thenReturn(true);
    when(mockSettingsService.useFahrenheit).thenReturn(false);
    when(mockWeatherService.hasWeather).thenReturn(true);
    when(mockWeatherService.weatherData).thenReturn(testWeatherWithWarning);
  });

  Widget createWidgetUnderTest({Locale? locale}) {
    return MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: locale,
      home: Scaffold(
        body: MultiProvider(
          providers: [
            ChangeNotifierProvider<SettingsService>.value(value: mockSettingsService),
            ChangeNotifierProvider<WeatherService>.value(value: mockWeatherService),
          ],
          child: const WeatherStatusBarWidget(),
        ),
      ),
    );
  }

  testWidgets('renders harmonized styling when weather warnings is disabled', (tester) async {
    when(mockSettingsService.showWeatherWarnings).thenReturn(false);

    await tester.pumpWidget(createWidgetUnderTest());

    expect(find.text('27°C'), findsOneWidget);

    final textWidget = tester.widget<Text>(find.text('27°C'));
    expect(textWidget.style?.color, Colors.white);
    expect(textWidget.style?.fontWeight, FontWeight.w400);

    final iconWidget = tester.widget<Icon>(find.byType(Icon));
    expect(iconWidget.icon, Icons.wb_sunny_outlined);
    expect(iconWidget.color, Colors.white);

    final container = tester.widget<AnimatedContainer>(find.byType(AnimatedContainer));
    final boxDecoration = container.decoration as BoxDecoration;
    final border = boxDecoration.border as Border;
    expect(border.top.color, Colors.white.withOpacity(0.12));
    expect(border.top.width, 1.0);
  });

  testWidgets('renders harmonized styling and current icon when weather warnings is enabled', (tester) async {
    when(mockSettingsService.showWeatherWarnings).thenReturn(true);

    await tester.pumpWidget(createWidgetUnderTest());

    // Warning text is included in displayText without altering colors/outline/icon
    expect(find.text('27°C • 80% Rain today'), findsOneWidget);

    final textWidget = tester.widget<Text>(find.text('27°C • 80% Rain today'));
    expect(textWidget.style?.color, Colors.white);
    expect(textWidget.style?.fontWeight, FontWeight.w400);

    // Current condition icon remains sunny, not overridden by warning
    final iconWidget = tester.widget<Icon>(find.byType(Icon));
    expect(iconWidget.icon, Icons.wb_sunny_outlined);
    expect(iconWidget.color, Colors.white);

    // Border remains subtle white with width 1.0, not amber
    final container = tester.widget<AnimatedContainer>(find.byType(AnimatedContainer));
    final boxDecoration = container.decoration as BoxDecoration;
    final border = boxDecoration.border as Border;
    expect(border.top.color, Colors.white.withOpacity(0.12));
    expect(border.top.width, 1.0);
  });

  testWidgets('says the warning in the app\'s language', (tester) async {
    when(mockSettingsService.showWeatherWarnings).thenReturn(true);

    await tester.pumpWidget(createWidgetUnderTest(locale: const Locale('de')));
    await tester.pumpAndSettle();

    expect(find.text('27°C • 80 % Regen heute'), findsOneWidget);
  });

  testWidgets('names the weekday of a warning later in the week', (tester) async {
    when(mockSettingsService.showWeatherWarnings).thenReturn(true);
    when(mockWeatherService.weatherData).thenReturn(WeatherData(
      currentTemp: 27,
      currentConditionCode: 800,
      warningType: WeatherWarningType.storm,
      warningText: "Storm on Thu",
      warningConditionCode: 211,
      warningDayIndex: 3,
      warningDate: DateTime(2026, 10, 8), // a Thursday
    ));

    await tester.pumpWidget(createWidgetUnderTest());
    await tester.pumpAndSettle();
    expect(find.text('27°C • Storm on Thu'), findsOneWidget);

    await tester.pumpWidget(createWidgetUnderTest(locale: const Locale('de')));
    await tester.pumpAndSettle();
    // The weekday's short name as the language's date data has it ("Do" or "Do.")
    expect(find.text('27°C • Gewitter am ${DateFormat.E('de').format(DateTime(2026, 10, 8))}'), findsOneWidget);
  });
}
