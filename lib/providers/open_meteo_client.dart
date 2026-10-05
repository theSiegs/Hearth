/*
 * LTvLauncher
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

import 'dart:convert';
import 'dart:io';

/// A place picked for weather. Only its coordinates are ever sent to Open-Meteo.
class WeatherPlace {
  final String name;
  final String? region;
  final String? country;
  final double latitude;
  final double longitude;

  const WeatherPlace({required this.name, this.region, this.country, required this.latitude, required this.longitude});

  String get displayName => [name, region, country].where((p) => p != null && p.isNotEmpty).join(", ");

  Map<String, dynamic> toJson() =>
      {"name": name, "region": region, "country": country, "latitude": latitude, "longitude": longitude};

  factory WeatherPlace.fromJson(Map<String, dynamic> json) => WeatherPlace(
        name: json["name"] as String,
        region: json["region"] as String? ?? json["admin1"] as String?,
        country: json["country"] as String?,
        latitude: (json["latitude"] as num).toDouble(),
        longitude: (json["longitude"] as num).toDouble(),
      );
}

/// Built-in weather from Open-Meteo (free, no API key or account). Responses are converted to the
/// Gadgetbridge weather JSON that Breezy Weather broadcasts, so the rest of the app reads one format.
class OpenMeteoClient {
  final HttpClient Function() _httpClientFactory;

  OpenMeteoClient({HttpClient Function()? httpClientFactory}) : _httpClientFactory = httpClientFactory ?? HttpClient.new;

  Future<List<WeatherPlace>> searchPlaces(String query) async {
    if (query.trim().length < 2) return [];
    final uri = Uri.https("geocoding-api.open-meteo.com", "/v1/search",
        {"name": query.trim(), "count": "8", "language": "en", "format": "json"});
    final json = await _getJson(uri);
    final results = json["results"] as List<dynamic>? ?? [];
    return results.whereType<Map<String, dynamic>>().map(WeatherPlace.fromJson).toList();
  }

  Future<String> fetchWeatherJson(WeatherPlace place) async {
    final uri = Uri.https("api.open-meteo.com", "/v1/forecast", {
      "latitude": place.latitude.toStringAsFixed(3),
      "longitude": place.longitude.toStringAsFixed(3),
      "current": "temperature_2m,relative_humidity_2m,weather_code,wind_speed_10m",
      "daily": "weather_code,temperature_2m_max,temperature_2m_min,precipitation_probability_max,relative_humidity_2m_mean",
      "wind_speed_unit": "ms",
      "timezone": "auto",
      "forecast_days": "7",
    });
    return jsonEncode(toGadgetbridgeWeather(await _getJson(uri), place.name));
  }

  Future<Map<String, dynamic>> _getJson(Uri uri) async {
    final client = _httpClientFactory();
    try {
      client.connectionTimeout = const Duration(seconds: 15);
      final request = await client.getUrl(uri);
      final response = await request.close().timeout(const Duration(seconds: 20));
      final body = await response.transform(utf8.decoder).join();
      if (response.statusCode != 200) {
        throw HttpException("Open-Meteo returned ${response.statusCode}", uri: uri);
      }
      return jsonDecode(body) as Map<String, dynamic>;
    } finally {
      client.close();
    }
  }

  /// Open-Meteo forecast response → Gadgetbridge weather JSON. Temperatures stay in °C (the parser accepts both);
  /// forecasts[0] is today, matching how warnings are worded.
  static Map<String, dynamic> toGadgetbridgeWeather(Map<String, dynamic> response, String locationName,
      {DateTime? now}) {
    final current = response["current"] as Map<String, dynamic>? ?? {};
    final daily = response["daily"] as Map<String, dynamic>? ?? {};
    List<dynamic> series(String key) => daily[key] as List<dynamic>? ?? const [];

    final codes = series("weather_code");
    final maxTemps = series("temperature_2m_max");
    final minTemps = series("temperature_2m_min");
    final precip = series("precipitation_probability_max");
    final humidity = series("relative_humidity_2m_mean");
    num? at(List<dynamic> list, int i) => i < list.length ? list[i] as num? : null;

    final int? currentCode = (current["weather_code"] as num?)?.toInt();
    return {
      "timestamp": ((now ?? DateTime.now()).millisecondsSinceEpoch / 1000).round(),
      "location": locationName,
      "currentTemp": (current["temperature_2m"] as num?)?.round(),
      "currentConditionCode": currentCode == null ? null : wmoToOwm(currentCode),
      "currentCondition": currentCode == null ? null : wmoDescription(currentCode),
      "currentHumidity": (current["relative_humidity_2m"] as num?)?.round(),
      "windSpeed": (current["wind_speed_10m"] as num?)?.toDouble(),
      "todayMaxTemp": at(maxTemps, 0)?.round(),
      "todayMinTemp": at(minTemps, 0)?.round(),
      "forecasts": [
        for (int i = 0; i < codes.length; i++)
          {
            "minTemp": at(minTemps, i)?.round(),
            "maxTemp": at(maxTemps, i)?.round(),
            "conditionCode": codes[i] == null ? null : wmoToOwm((codes[i] as num).toInt()),
            "humidity": at(humidity, i)?.round(),
            "precipProbability": at(precip, i)?.round(),
          },
      ],
    };
  }

  /// WMO weather interpretation codes (Open-Meteo) → OpenWeatherMap condition codes (Gadgetbridge).
  static int wmoToOwm(int wmo) {
    switch (wmo) {
      case 0: return 800;
      case 1: return 801;
      case 2: return 802;
      case 3: return 804;
      case 45: case 48: return 741;
      case 51: return 300;
      case 53: return 301;
      case 55: return 302;
      case 56: case 57: case 66: case 67: return 511;
      case 61: return 500;
      case 63: return 501;
      case 65: return 502;
      case 71: case 77: return 600;
      case 73: return 601;
      case 75: return 602;
      case 80: return 520;
      case 81: return 521;
      case 82: return 522;
      case 85: return 620;
      case 86: return 621;
      case 95: return 211;
      case 96: case 99: return 202;
      default: return 800;
    }
  }

  static String wmoDescription(int wmo) {
    if (wmo == 0) return "Clear";
    if (wmo <= 2) return "Partly cloudy";
    if (wmo == 3) return "Overcast";
    if (wmo == 45 || wmo == 48) return "Fog";
    if (wmo >= 51 && wmo <= 57) return "Drizzle";
    if (wmo >= 61 && wmo <= 67) return "Rain";
    if (wmo >= 71 && wmo <= 77) return "Snow";
    if (wmo >= 80 && wmo <= 82) return "Rain showers";
    if (wmo == 85 || wmo == 86) return "Snow showers";
    return "Thunderstorm";
  }
}
