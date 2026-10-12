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

import 'weather_data.dart';

/// The weather's first view: today in the day, tonight from the evening on. Temperatures in °C.
class WeatherSummary {
  /// From this hour on it's about tonight (until [morningHour] the next day); before it, about today.
  static const int eveningHour = 17;

  /// Tonight lasts until this hour; until then, it's still tonight (the small hours belong to the night before).
  static const int morningHour = 4;

  /// Tonight's forecast runs to this hour of the morning.
  static const int wakeHour = 7;

  final bool tonight;

  /// Today's high (null tonight).
  final int? high;

  /// Today's low, or tonight's.
  final int? low;

  /// What the sky does most of the time it covers.
  final int? conditionCode;

  /// The highest chance of rain or snow in that time, in percent.
  final int? precipProbability;

  /// The temperature now.
  final int? current;

  /// Tomorrow's high (tonight only).
  final int? tomorrowHigh;

  const WeatherSummary({
    required this.tonight,
    this.high,
    this.low,
    this.conditionCode,
    this.precipProbability,
    this.current,
    this.tomorrowHigh,
  });

  static WeatherSummary of(WeatherData weather, DateTime now) {
    final tonight = now.hour >= eveningHour || now.hour < morningHour;
    final thisHour = DateTime(now.year, now.month, now.day, now.hour);
    if (!tonight) {
      final today = weather.forecasts.isNotEmpty ? weather.forecasts.first : null;
      final midnight = DateTime(now.year, now.month, now.day + 1);
      final rest = _between(weather, thisHour, midnight);
      return WeatherSummary(
        tonight: false,
        high: today?.maxTemp ?? weather.todayMaxTemp,
        low: today?.minTemp ?? weather.todayMinTemp,
        conditionCode: _mostOf(rest) ?? today?.conditionCode ?? weather.currentConditionCode,
        precipProbability: _maxPrecip(rest) ?? today?.precipProbability,
        current: weather.currentTemp,
      );
    }
    // Before dawn it's still last night: it runs to this morning; in the evening, to tomorrow morning
    final morning = now.hour < morningHour
        ? DateTime(now.year, now.month, now.day, wakeHour)
        : DateTime(now.year, now.month, now.day + 1, wakeHour);
    final night = _between(weather, thisHour, morning);
    final temps = [for (final h in night) if (h.temp != null) h.temp!];
    final tomorrowIndex = now.hour < morningHour ? 0 : 1;
    final tomorrow = weather.forecasts.length > tomorrowIndex ? weather.forecasts[tomorrowIndex] : null;
    return WeatherSummary(
      tonight: true,
      low: temps.isNotEmpty ? temps.reduce((a, b) => a < b ? a : b) : tomorrow?.minTemp,
      conditionCode: _mostOf(night) ?? weather.currentConditionCode,
      precipProbability: _maxPrecip(night),
      current: weather.currentTemp,
      tomorrowHigh: tomorrow?.maxTemp,
    );
  }

  static List<WeatherHourItem> _between(WeatherData weather, DateTime from, DateTime until) =>
      [for (final h in weather.hourly) if (!h.time.isBefore(from) && h.time.isBefore(until)) h];

  static int? _maxPrecip(List<WeatherHourItem> hours) {
    final values = [for (final h in hours) if (h.precipProbability != null) h.precipProbability!];
    return values.isEmpty ? null : values.reduce((a, b) => a > b ? a : b);
  }

  /// The condition most of the hours have; rain, snow or a storm wins if it's in any hour with at least a 40% chance.
  static int? _mostOf(List<WeatherHourItem> hours) {
    for (final h in hours) {
      final code = h.conditionCode;
      if (code != null &&
          (h.precipProbability ?? 0) >= 40 &&
          (WeatherData.rainCodes.contains(code) ||
              WeatherData.snowCodes.contains(code) ||
              WeatherData.stormCodes.contains(code))) {
        return code;
      }
    }
    final counts = <int, int>{};
    for (final h in hours) {
      if (h.conditionCode != null) counts[h.conditionCode!] = (counts[h.conditionCode!] ?? 0) + 1;
    }
    if (counts.isEmpty) return null;
    return counts.entries.reduce((a, b) => b.value > a.value ? b : a).key;
  }
}
