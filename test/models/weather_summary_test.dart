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

import 'package:flauncher/models/weather_data.dart';
import 'package:flauncher/models/weather_summary.dart';
import 'package:flutter_test/flutter_test.dart';

WeatherHourItem hour(DateTime time, int temp, int code, [int precip = 0]) =>
    WeatherHourItem(time: time, temp: temp, conditionCode: code, precipProbability: precip);

void main() {
  final today = DateTime(2026, 10, 11);
  final hours = [
    for (var h = 0; h < 36; h++)
      hour(today.add(Duration(hours: h)), 10 + (h % 24 > 12 ? 24 - h % 24 : h % 24) ~/ 2, 803),
  ];
  final weather = WeatherData(
    currentTemp: 15,
    currentConditionCode: 800,
    forecasts: const [
      WeatherForecastItem(minTemp: 9, maxTemp: 18, conditionCode: 803, precipProbability: 10),
      WeatherForecastItem(minTemp: 8, maxTemp: 20, conditionCode: 800),
    ],
    hourly: [
      ...hours.where((h) => h.time.hour != 15 || h.time.day != 11),
      hour(DateTime(2026, 10, 11, 15), 17, 500, 60),
    ]..sort((a, b) => a.time.compareTo(b.time)),
  );

  test("In the day: today's high and low, and the rest of today's sky and rain", () {
    final s = WeatherSummary.of(weather, DateTime(2026, 10, 11, 11, 20));
    expect(s.tonight, isFalse);
    expect(s.high, 18);
    expect(s.low, 9);
    // Rain at 15:00 with a 60% chance outweighs the clouds the rest of the day
    expect(s.conditionCode, 500);
    expect(s.precipProbability, 60);
    expect(s.current, 15);
    expect(s.tomorrowHigh, isNull);
  });

  test("In the evening: tonight's low until morning, and tomorrow's high", () {
    final s = WeatherSummary.of(weather, DateTime(2026, 10, 11, 19, 5));
    expect(s.tonight, isTrue);
    // The hours from 19:00 to 07:00 tomorrow
    final night = weather.hourly.where((h) =>
        !h.time.isBefore(DateTime(2026, 10, 11, 19)) && h.time.isBefore(DateTime(2026, 10, 12, 7)));
    expect(s.low, night.map((h) => h.temp!).reduce((a, b) => a < b ? a : b));
    expect(s.conditionCode, 803);
    expect(s.precipProbability, 0);
    expect(s.tomorrowHigh, 20);
    expect(s.high, isNull);
  });

  test("In the small hours it's still tonight, until this morning", () {
    final s = WeatherSummary.of(weather, DateTime(2026, 10, 12, 2));
    expect(s.tonight, isTrue);
    // Tomorrow is today's forecast now that the day has turned
    expect(s.tomorrowHigh, 18);
  });

  test("Without hourly data it falls back to the day's forecast and now", () {
    const daily = WeatherData(
      currentTemp: 12,
      currentConditionCode: 801,
      forecasts: [WeatherForecastItem(minTemp: 5, maxTemp: 14, conditionCode: 600, precipProbability: 70)],
    );
    final day = WeatherSummary.of(daily, DateTime(2026, 10, 11, 9));
    expect(day.conditionCode, 600);
    expect(day.precipProbability, 70);
    final night = WeatherSummary.of(daily, DateTime(2026, 10, 11, 21));
    expect(night.conditionCode, 801);
    expect(night.low, isNull);
  });
}
