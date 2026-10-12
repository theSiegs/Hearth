import 'package:flauncher/models/weather_data.dart';
import 'package:flauncher/providers/home_forecast.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test("the forecast opens on the summary each time, and OK goes on to hours, days and back", () {
    final forecast = HomeForecast();
    forecast.setShowing(true);
    expect(forecast.showing, isTrue);
    expect(forecast.view, ForecastView.summary);
    forecast.swap();
    expect(forecast.view, ForecastView.hourly);
    forecast.swap();
    expect(forecast.view, ForecastView.daily);
    expect(forecast.days, isTrue);
    forecast.swap();
    expect(forecast.view, ForecastView.summary);
    forecast.swap();
    forecast.setShowing(false);
    forecast.setShowing(true);
    expect(forecast.view, ForecastView.summary);
  });

  test("temperatures show in the TV's unit, with or without it", () {
    expect(WeatherData.formatDegrees(21), "21°C");
    expect(WeatherData.formatDegrees(21, useFahrenheit: true), "70°F");
    expect(WeatherData.formatDegrees(21, useFahrenheit: true, withUnit: false), "70°");
    expect(WeatherData.formatDegrees(null), "--°");
  });

  test("hourly entries from a feed come out earliest first, and ones without a time are left out", () {
    final weather = WeatherData.fromJson({
      "hourly": [
        {"timestamp": 200, "temp": 10},
        {"temp": 11},
        {"timestamp": 100, "temp": 9, "conditionCode": 800, "precipProbability": 0},
      ],
    });
    expect(weather.hourly.map((h) => h.temp), [9, 10]);
    expect(weather.hourly.first.conditionCode, 800);
  });
}
