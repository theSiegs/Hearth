import 'dart:convert';
import 'package:flutter/material.dart';

enum WeatherWarningType {
  none,
  rain,
  snow,
  storm,
}

class WeatherForecastItem {
  final int? minTemp;
  final int? maxTemp;
  final int? conditionCode;
  final int? humidity;
  final int? precipProbability;

  const WeatherForecastItem({
    this.minTemp,
    this.maxTemp,
    this.conditionCode,
    this.humidity,
    this.precipProbability,
  });

  factory WeatherForecastItem.fromJson(Map<String, dynamic> json) {
    return WeatherForecastItem(
      minTemp: WeatherData.parseTemperature(json['minTemp']),
      maxTemp: WeatherData.parseTemperature(json['maxTemp']),
      conditionCode: (json['conditionCode'] as num?)?.toInt(),
      humidity: (json['humidity'] as num?)?.toInt(),
      precipProbability: (json['precipProbability'] as num?)?.toInt(),
    );
  }
}

/// One hour of the forecast: when, how warm (°C) and what the sky does.
class WeatherHourItem {
  final DateTime time;
  final int? temp;
  final int? conditionCode;
  final int? precipProbability;

  const WeatherHourItem({required this.time, this.temp, this.conditionCode, this.precipProbability});

  /// From a feed's "hourly" entry (Breezy Weather's Gadgetbridge format and Hearth's own use the same keys; the
  /// timestamp is in seconds); null without one.
  static WeatherHourItem? fromJson(Map<String, dynamic> json) {
    final seconds = (json['timestamp'] as num?)?.toInt();
    if (seconds == null) return null;
    return WeatherHourItem(
      time: DateTime.fromMillisecondsSinceEpoch(seconds * 1000),
      temp: WeatherData.parseTemperature(json['temp']),
      conditionCode: (json['conditionCode'] as num?)?.toInt(),
      precipProbability: (json['precipProbability'] as num?)?.toInt(),
    );
  }
}

class WeatherData {
  final int? timestamp;
  final String? location;
  final int? currentTemp;
  final int? currentConditionCode;
  final String? currentCondition;
  final int? currentHumidity;
  final double? windSpeed;
  final int? todayMaxTemp;
  final int? todayMinTemp;
  final List<WeatherForecastItem> forecasts;

  /// The coming hours, earliest first (empty when the source gives none).
  final List<WeatherHourItem> hourly;

  // The first rain, snow or storm in the coming week, if any
  final WeatherWarningType warningType;

  /// The warning in English ("70% Rain today"). The status bar shows its own, in the app's language, from
  /// [warningType], [warningDayIndex], [warningDate] and [warningPrecipProbability].
  final String? warningText;
  final int? warningConditionCode;

  /// The forecast day the warning is for: 0 today, 1 tomorrow, and so on.
  final int? warningDayIndex;

  /// That day's date, for its weekday's name.
  final DateTime? warningDate;

  /// The chance of it in percent, when the forecast gives one above 0.
  final int? warningPrecipProbability;

  const WeatherData({
    this.timestamp,
    this.location,
    this.currentTemp,
    this.currentConditionCode,
    this.currentCondition,
    this.currentHumidity,
    this.windSpeed,
    this.todayMaxTemp,
    this.todayMinTemp,
    this.forecasts = const [],
    this.hourly = const [],
    this.warningType = WeatherWarningType.none,
    this.warningText,
    this.warningConditionCode,
    this.warningDayIndex,
    this.warningDate,
    this.warningPrecipProbability,
  });

  bool get hasWarning => warningType != WeatherWarningType.none;

  static const rainCodes = {500, 501, 502, 503, 504, 511, 520, 521, 522, 531};
  static const snowCodes = {600, 601, 602, 611, 612, 615, 616, 620, 621, 622};
  static const stormCodes = {200, 201, 202, 210, 211, 212, 221, 230, 231, 232};

  factory WeatherData.fromJsonString(String jsonString) {
    final Map<String, dynamic> json = jsonDecode(jsonString);
    return WeatherData.fromJson(json);
  }

  static int? parseTemperature(dynamic val) {
    if (val == null) return null;
    num? n;
    if (val is num) {
      n = val;
    } else if (val is String) {
      n = num.tryParse(val);
    }
    if (n == null) return null;
    // Gadgetbridge / Breezy Weather WeatherSpec sends temperatures in Kelvin (e.g., 300K for ~27°C).
    // If value > 100, treat as Kelvin and convert to Celsius.
    if (n > 100) {
      return (n - 273.15).round();
    }
    return n.round();
  }

  factory WeatherData.fromJson(Map<String, dynamic> json) {
    final List<dynamic>? rawForecasts = json['forecasts'] as List<dynamic>?;
    final List<WeatherForecastItem> forecasts = rawForecasts != null
        ? rawForecasts
            .whereType<Map<String, dynamic>>()
            .map((e) => WeatherForecastItem.fromJson(e))
            .toList()
        : [];

    WeatherWarningType warningType = WeatherWarningType.none;
    String? warningText;
    int? warningConditionCode;
    int? warningDayIndex;
    DateTime? warningDate;
    int? warningPrecipProbability;

    const dayNames = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    final now = DateTime.now();

    for (int i = 0; i < forecasts.length && i < 7; i++) {
      final f = forecasts[i];
      final code = f.conditionCode;
      if (code == null) continue;

      if (rainCodes.contains(code) || snowCodes.contains(code) || stormCodes.contains(code)) {
        warningConditionCode = code;
        warningDayIndex = i;
        final targetDate = now.add(Duration(days: i));
        warningDate = targetDate;

        String dayText;
        if (i == 0) {
          dayText = "today";
        } else if (i == 1) {
          dayText = "tomorrow";
        } else {
          dayText = "on ${dayNames[targetDate.weekday - 1]}";
        }

        if (f.precipProbability != null && f.precipProbability! > 0) {
          warningPrecipProbability = f.precipProbability;
        }
        final precipString = warningPrecipProbability != null ? "$warningPrecipProbability% " : "";

        if (rainCodes.contains(code)) {
          warningType = WeatherWarningType.rain;
          warningText = "${precipString}Rain $dayText";
        } else if (snowCodes.contains(code)) {
          warningType = WeatherWarningType.snow;
          warningText = "${precipString}Snow $dayText";
        } else {
          warningType = WeatherWarningType.storm;
          warningText = "${precipString}Storm $dayText";
        }
        break;
      }
    }

    return WeatherData(
      timestamp: (json['timestamp'] as num?)?.toInt(),
      location: json['location'] as String?,
      currentTemp: parseTemperature(json['currentTemp']),
      currentConditionCode: (json['currentConditionCode'] as num?)?.toInt(),
      currentCondition: json['currentCondition'] as String?,
      currentHumidity: (json['currentHumidity'] as num?)?.toInt(),
      windSpeed: (json['windSpeed'] as num?)?.toDouble(),
      todayMaxTemp: parseTemperature(json['todayMaxTemp']),
      todayMinTemp: parseTemperature(json['todayMinTemp']),
      forecasts: forecasts,
      hourly: [
        for (final entry in (json['hourly'] as List<dynamic>? ?? const []).whereType<Map<String, dynamic>>())
          if (WeatherHourItem.fromJson(entry) case final WeatherHourItem hour) hour,
      ]..sort((a, b) => a.time.compareTo(b.time)),
      warningType: warningType,
      warningText: warningText,
      warningConditionCode: warningConditionCode,
      warningDayIndex: warningDayIndex,
      warningDate: warningDate,
      warningPrecipProbability: warningPrecipProbability,
    );
  }

  IconData getConditionIcon({bool isWarning = false}) =>
      iconFor(isWarning ? (warningConditionCode ?? currentConditionCode) : currentConditionCode);

  /// The icon for a condition code (OpenWeatherMap's, as the feeds give them).
  static IconData iconFor(int? code) {
    if (code == null) return Icons.cloud_outlined;

    if (code == 800) return Icons.wb_sunny_outlined;
    if (code == 801 || code == 802) return Icons.wb_cloudy_outlined;
    if (code == 803 || code == 804) return Icons.cloud_outlined;
    if (rainCodes.contains(code)) return Icons.grain_outlined;
    if (snowCodes.contains(code)) return Icons.ac_unit_outlined;
    if (stormCodes.contains(code)) return Icons.flash_on_outlined;
    if (code == 741 || code == 701 || code == 711 || code == 721 || code == 751) {
      return Icons.waves_outlined;
    }
    if (code == 771) return Icons.air_outlined;

    return Icons.cloud_outlined;
  }

  String formatTemperature({bool useFahrenheit = false}) => formatDegrees(currentTemp, useFahrenheit: useFahrenheit);

  /// A temperature given in °C as the TV shows it: "21°C", "70°F", or just "70°" without [withUnit].
  static String formatDegrees(int? celsius, {bool useFahrenheit = false, bool withUnit = true}) {
    if (celsius == null) return "--°";
    final value = useFahrenheit ? (celsius * 9 / 5 + 32).round() : celsius;
    return withUnit ? "$value°${useFahrenheit ? "F" : "C"}" : "$value°";
  }
}
