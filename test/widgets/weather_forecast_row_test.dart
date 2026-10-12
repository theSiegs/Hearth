/*
 * Hearth
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program.  If not, see <https://www.gnu.org/licenses/>.
 */

import 'package:flauncher/l10n/app_localizations.dart';
import 'package:flauncher/models/weather_data.dart';
import 'package:flauncher/providers/home_forecast.dart';
import 'package:flauncher/providers/settings_service.dart';
import 'package:flauncher/providers/weather_service.dart';
import 'package:flauncher/widgets/weather_forecast_row.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:provider/provider.dart';

import '../mocks.mocks.dart';

void main() {
  testWidgets("Opens on the summary; OK goes on to the next hours", (tester) async {
    final now = DateTime.now();
    final weather = MockWeatherService();
    when(weather.weatherData).thenReturn(WeatherData(
      location: "Springfield",
      currentTemp: 15,
      currentConditionCode: 800,
      forecasts: const [
        WeatherForecastItem(minTemp: 9, maxTemp: 18, conditionCode: 800),
        WeatherForecastItem(minTemp: 8, maxTemp: 20, conditionCode: 800),
      ],
      hourly: [
        for (var h = 0; h < 30; h++)
          WeatherHourItem(
              time: DateTime(now.year, now.month, now.day, now.hour).add(Duration(hours: h)),
              temp: 12,
              conditionCode: 800,
              precipProbability: 0),
      ],
    ));
    final settings = MockSettingsService();
    when(settings.useFahrenheit).thenReturn(false);
    final forecast = HomeForecast()..setShowing(true);
    await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider<WeatherService?>.value(value: weather),
        ChangeNotifierProvider<SettingsService>.value(value: settings),
        ChangeNotifierProvider<HomeForecast?>.value(value: forecast),
      ],
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale("en"),
        home: const Scaffold(body: WeatherForecastRow()),
      ),
    ));
    expect(find.byKey(const Key("weather_summary")), findsOneWidget);
    expect(find.text("Clear"), findsOneWidget);
    expect(find.text("OK: hourly"), findsOneWidget);
    final evening = now.hour >= 17 || now.hour < 4;
    expect(find.textContaining(evening ? "Tonight" : "Today"), findsOneWidget);

    forecast.swap();
    await tester.pump();
    expect(find.byKey(const Key("weather_summary")), findsNothing);
    expect(find.text("OK: daily"), findsOneWidget);
    forecast.swap();
    await tester.pump();
    expect(find.text("OK: summary"), findsOneWidget);
  });
}
