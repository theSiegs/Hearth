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
import 'package:flutter/material.dart';

/// One hour of the glance page's forecast (°C).
class GlanceWeatherHour {
  final DateTime time;
  final double? temp;
  final IconData icon;
  const GlanceWeatherHour(this.time, this.temp, this.icon);
}

/// One day of the glance page's forecast (°C).
class GlanceWeatherDay {
  final DateTime date;
  final double? high, low;
  final IconData icon;
  const GlanceWeatherDay(this.date, this.high, this.low, this.icon);
}

/// The weather as the glance page's weather tile shows it, whichever source it came from: the TV's own weather
/// (Settings: a place for Open-Meteo, or Breezy Weather) or, when the TV has none, Home Assistant's weather entity.
/// Temperatures are in °C; [degrees] shows them in the TV's unit.
class GlanceWeather {
  final IconData icon;
  final String? condition;
  final double? temp, high, low;
  final List<GlanceWeatherHour> hours;
  final List<GlanceWeatherDay> days;

  const GlanceWeather({
    required this.icon,
    this.condition,
    this.temp,
    this.high,
    this.low,
    this.hours = const [],
    this.days = const [],
  });

  /// How many hours and days the tile shows.
  static const int hourCount = 4, dayCount = 4;

  /// The hours ahead: from the next hour, every [step] hours.
  static List<T> ahead<T>(List<T> all, DateTime Function(T) time, DateTime now, {int step = 2}) {
    final thisHour = DateTime(now.year, now.month, now.day, now.hour);
    final coming = [for (final h in all) if (time(h).isAfter(thisHour)) h];
    return [for (var i = 0; i < coming.length && i ~/ step < hourCount; i += step) coming[i]];
  }

  /// From the TV's own weather; null without a temperature.
  static GlanceWeather? fromHearth(WeatherData? w, DateTime now) {
    if (w == null || w.currentTemp == null) return null;
    final today = DateTime(now.year, now.month, now.day);
    return GlanceWeather(
      icon: WeatherData.iconFor(w.currentConditionCode),
      condition: (w.currentCondition?.trim().isEmpty ?? true) ? null : w.currentCondition!.trim(),
      temp: w.currentTemp?.toDouble(),
      high: w.todayMaxTemp?.toDouble(),
      low: w.todayMinTemp?.toDouble(),
      hours: [
        for (final h in ahead(w.hourly, (h) => h.time, now))
          GlanceWeatherHour(h.time, h.temp?.toDouble(), WeatherData.iconFor(h.conditionCode)),
      ],
      days: [
        for (var i = 1; i < w.forecasts.length && i <= dayCount; i++)
          GlanceWeatherDay(today.add(Duration(days: i)), w.forecasts[i].maxTemp?.toDouble(),
              w.forecasts[i].minTemp?.toDouble(), WeatherData.iconFor(w.forecasts[i].conditionCode)),
      ],
    );
  }

  /// From Home Assistant: a weather entity's state (its condition), temperature and unit, and the forecasts it sent
  /// (weather/subscribe_forecast: "datetime", "temperature", "templow", "condition"). Null without a temperature.
  static GlanceWeather? fromHa({
    required String state,
    required Object? temperature,
    String? unit,
    List<Object?> hourly = const [],
    List<Object?> daily = const [],
    required DateTime now,
  }) {
    final temp = haCelsius(temperature, unit);
    if (temp == null) return null;
    final hours = <GlanceWeatherHour>[];
    for (final f in hourly) {
      if (f is! Map) continue;
      final time = DateTime.tryParse("${f["datetime"]}")?.toLocal();
      if (time == null) continue;
      hours.add(GlanceWeatherHour(time, haCelsius(f["temperature"], unit), haIcon("${f["condition"]}")));
    }
    final today = DateTime(now.year, now.month, now.day);
    final days = <GlanceWeatherDay>[];
    double? high, low;
    for (final f in daily) {
      if (f is! Map) continue;
      final time = DateTime.tryParse("${f["datetime"]}")?.toLocal();
      if (time == null) continue;
      final date = DateTime(time.year, time.month, time.day);
      if (date == today) {
        high = haCelsius(f["temperature"], unit);
        low = haCelsius(f["templow"], unit);
      } else if (date.isAfter(today) && days.length < dayCount) {
        days.add(GlanceWeatherDay(
            date, haCelsius(f["temperature"], unit), haCelsius(f["templow"], unit), haIcon("${f["condition"]}")));
      }
    }
    return GlanceWeather(
      icon: haIcon(state),
      condition: haCondition(state),
      temp: temp,
      high: high,
      low: low,
      hours: ahead(hours, (h) => h.time, now),
      days: days,
    );
  }

  /// A Home Assistant temperature in °C.
  static double? haCelsius(Object? value, String? unit) {
    final v = value is num ? value.toDouble() : double.tryParse("${value ?? ""}");
    if (v == null) return null;
    return (unit ?? "").toUpperCase().contains("F") ? (v - 32) * 5 / 9 : v;
  }

  /// Home Assistant's conditions, as words.
  static String? haCondition(String state) => switch (state) {
    "clear-night" => "Clear",
    "cloudy" => "Cloudy",
    "exceptional" => "Unusual weather",
    "fog" => "Fog",
    "hail" => "Hail",
    "lightning" => "Thunderstorms",
    "lightning-rainy" => "Thunderstorms",
    "partlycloudy" => "Partly cloudy",
    "pouring" => "Heavy rain",
    "rainy" => "Rain",
    "snowy" => "Snow",
    "snowy-rainy" => "Sleet",
    "sunny" => "Sunny",
    "windy" || "windy-variant" => "Windy",
    _ => null,
  };

  /// Home Assistant's conditions, as icons (the ones Hearth's weather uses).
  static IconData haIcon(String state) => switch (state) {
    "clear-night" => Icons.nightlight_outlined,
    "sunny" => Icons.wb_sunny_outlined,
    "partlycloudy" => Icons.wb_cloudy_outlined,
    "rainy" || "pouring" || "hail" => Icons.grain_outlined,
    "snowy" || "snowy-rainy" => Icons.ac_unit_outlined,
    "lightning" || "lightning-rainy" => Icons.flash_on_outlined,
    "fog" => Icons.waves_outlined,
    "windy" || "windy-variant" => Icons.air_outlined,
    _ => Icons.cloud_outlined,
  };

  /// A °C temperature in the TV's unit, "70°".
  static String degrees(double? celsius, {required bool fahrenheit}) {
    if (celsius == null) return "--°";
    return "${(fahrenheit ? celsius * 9 / 5 + 32 : celsius).round()}°";
  }
}
