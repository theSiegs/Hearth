import 'package:flauncher/models/weather_data.dart';
import 'package:flauncher/providers/open_meteo_client.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const forecast = {
    "current": {"temperature_2m": 12.6, "relative_humidity_2m": 71, "weather_code": 3, "wind_speed_10m": 4.2},
    "daily": {
      "weather_code": [2, 63, 0],
      "temperature_2m_max": [15.2, 13.0, 18.4],
      "temperature_2m_min": [6.1, 8.8, 7.0],
      "precipitation_probability_max": [10, 85, 0],
      "relative_humidity_2m_mean": [70, 90, 60],
    },
  };

  test("converts an Open-Meteo forecast into the weather the status bar reads", () {
    final json = OpenMeteoClient.toGadgetbridgeWeather(forecast, "Chicago", now: DateTime(2026, 10, 4));
    final weather = WeatherData.fromJson(json);

    expect(weather.location, "Chicago");
    expect(weather.currentTemp, 13);
    expect(weather.currentConditionCode, 804);
    expect(weather.currentCondition, "Overcast");
    expect(weather.todayMaxTemp, 15);
    expect(weather.todayMinTemp, 6);
    expect(weather.forecasts.length, 3);

    // Moderate rain tomorrow becomes the rain warning
    expect(weather.hasWarning, isTrue);
    expect(weather.warningType, WeatherWarningType.rain);
    expect(weather.warningText, "85% Rain tomorrow");
  });

  test("carries the coming hours, in the feed's keys", () {
    final json = OpenMeteoClient.toGadgetbridgeWeather({
      ...forecast,
      "hourly": {
        "time": [1791640800, 1791644400],
        "temperature_2m": [12.4, 11.6],
        "weather_code": [61, 0],
        "precipitation_probability": [70, 5],
      },
    }, "Chicago", now: DateTime(2026, 10, 4));
    final weather = WeatherData.fromJson(json);
    expect(weather.hourly.length, 2);
    expect(weather.hourly.first.time, DateTime.fromMillisecondsSinceEpoch(1791640800 * 1000));
    expect(weather.hourly.first.temp, 12);
    expect(WeatherData.rainCodes, contains(weather.hourly.first.conditionCode));
    expect(weather.hourly.first.precipProbability, 70);
    expect(weather.hourly.last.conditionCode, 800);
  });

  test("maps WMO codes onto the condition codes warnings look for", () {
    expect(WeatherData.rainCodes, contains(OpenMeteoClient.wmoToOwm(61)));
    expect(WeatherData.rainCodes, contains(OpenMeteoClient.wmoToOwm(81)));
    expect(WeatherData.snowCodes, contains(OpenMeteoClient.wmoToOwm(75)));
    expect(WeatherData.snowCodes, contains(OpenMeteoClient.wmoToOwm(86)));
    expect(WeatherData.stormCodes, contains(OpenMeteoClient.wmoToOwm(95)));
    expect(OpenMeteoClient.wmoToOwm(0), 800);
  });

  test("place round-trips and builds a readable name", () {
    const place = WeatherPlace(name: "Springfield", region: "Illinois", country: "United States", latitude: 39.8, longitude: -89.6);
    final copy = WeatherPlace.fromJson(place.toJson());
    expect(copy.displayName, "Springfield, Illinois, United States");
    expect(copy.latitude, 39.8);
  });
}
