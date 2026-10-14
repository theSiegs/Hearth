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
import 'package:flauncher/models/weather_summary.dart';
import 'package:flauncher/providers/home_forecast.dart';
import 'package:flauncher/providers/settings_service.dart';
import 'package:flauncher/providers/weather_service.dart';
import 'package:flauncher/widgets/title_pill.dart';
import 'package:flauncher/quiet_failure.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

/// The weather over the home, in Continue Watching's spot while the top bar's weather has focus: a summary of today
/// (tonight in the evening), then with OK on the weather the next hours, the next five days, and the summary again.
/// Nothing in it takes focus: the weather keeps it.
class WeatherForecastRow extends StatelessWidget {
  /// How many hours and days it shows.
  static const int hours = 10;
  static const int days = 5;

  const WeatherForecastRow({super.key});

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final weather = context.watch<WeatherService?>()?.weatherData;
    final view = context.watch<HomeForecast?>()?.view ?? ForecastView.summary;
    final fahrenheit = context.select<SettingsService, bool>((s) => s.useFahrenheit);
    if (weather == null) return const SizedBox.shrink();
    final now = DateTime.now();
    final summary = view == ForecastView.summary ? WeatherSummary.of(weather, now) : null;
    final tiles = switch (view) {
      ForecastView.summary => [_SummaryCard(summary: summary!, fahrenheit: fahrenheit)],
      ForecastView.hourly => _hourTiles(l, weather, now, fahrenheit),
      ForecastView.daily => _dayTiles(l, weather, now, fahrenheit),
    };
    const shadow = [Shadow(color: Colors.black54, offset: Offset(1, 1), blurRadius: 8)];
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          TitlePill(
            child: Text(
              l.weather.toUpperCase(),
              style: Theme.of(context)
                  .textTheme
                  .labelLarge!
                  .copyWith(color: Colors.white, letterSpacing: 1.0, shadows: TitlePill.textShadow),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            [
              if (weather.location != null && weather.location!.isNotEmpty) weather.location!,
              switch (view) {
                ForecastView.summary => summary!.tonight ? l.weatherSummaryTonight : l.weatherForecastToday,
                ForecastView.hourly => l.weatherForecastHourly,
                ForecastView.daily => l.weatherForecastDaily,
              },
            ].join(" · "),
            style: Theme.of(context).textTheme.headlineSmall!.copyWith(fontWeight: FontWeight.w700, shadows: shadow),
          ),
          Text(
            switch (view) {
              ForecastView.summary => l.weatherForecastShowHourly,
              ForecastView.hourly => l.weatherForecastShowDaily,
              ForecastView.daily => l.weatherForecastShowSummary,
            },
            style: Theme.of(context).textTheme.bodyLarge!.copyWith(color: Colors.white70, shadows: shadow),
          ),
          const SizedBox(height: 12),
          if (tiles.isEmpty)
            Text(l.weatherForecastNone,
                style: Theme.of(context).textTheme.bodyLarge!.copyWith(color: Colors.white70, shadows: shadow))
          else
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(children: [for (final tile in tiles) Padding(padding: const EdgeInsets.only(right: 12), child: tile)]),
            ),
        ],
      ),
    );
  }

  /// The coming hours, from this one.
  static List<Widget> _hourTiles(AppLocalizations l, WeatherData weather, DateTime now, bool fahrenheit) {
    final thisHour = DateTime(now.year, now.month, now.day, now.hour);
    final coming = weather.hourly.where((h) => !h.time.isBefore(thisHour)).take(hours).toList();
    return [
      for (final hour in coming)
        _ForecastTile(
          label: hour.time == thisHour ? l.weatherForecastNow : _hourLabel(l.localeName, hour.time),
          icon: WeatherData.iconFor(hour.conditionCode),
          main: WeatherData.formatDegrees(hour.temp, useFahrenheit: fahrenheit, withUnit: false),
          precip: hour.precipProbability,
        ),
    ];
  }

  /// Today and the next days.
  static List<Widget> _dayTiles(AppLocalizations l, WeatherData weather, DateTime now, bool fahrenheit) => [
        for (var i = 0; i < weather.forecasts.length && i < days; i++)
          _ForecastTile(
            label: i == 0 ? l.weatherForecastToday : _dayLabel(l.localeName, now.add(Duration(days: i))),
            icon: WeatherData.iconFor(weather.forecasts[i].conditionCode),
            main: WeatherData.formatDegrees(weather.forecasts[i].maxTemp, useFahrenheit: fahrenheit, withUnit: false),
            low: WeatherData.formatDegrees(weather.forecasts[i].minTemp, useFahrenheit: fahrenheit, withUnit: false),
            precip: weather.forecasts[i].precipProbability,
          ),
      ];

  static String _hourLabel(String locale, DateTime time) {
    try {
      return DateFormat.j(locale).format(time);
    } catch (err) {
        noteFailure('weather_forecast_row', err);
      return DateFormat.j("en_US").format(time);
    }
  }

  static String _dayLabel(String locale, DateTime date) {
    try {
      return DateFormat.E(locale).format(date);
    } catch (err) {
        noteFailure('weather_forecast_row', err);
      return DateFormat.E("en_US").format(date);
    }
  }
}

/// One hour or day: when, the sky, the temperature (a day's high over its low) and the chance of rain or snow.
class _ForecastTile extends StatelessWidget {
  final String label;
  final IconData icon;
  final String main;
  final String? low;
  final int? precip;

  const _ForecastTile({required this.label, required this.icon, required this.main, this.low, this.precip});

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Container(
      width: 112,
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.35),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withOpacity(0.12)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label, style: text.bodyMedium!.copyWith(color: Colors.white70), maxLines: 1, overflow: TextOverflow.ellipsis),
          const SizedBox(height: 8),
          Icon(icon, size: 34, color: Colors.white),
          const SizedBox(height: 8),
          Text(main, style: text.titleLarge!.copyWith(fontWeight: FontWeight.w700)),
          if (low != null) Text(low!, style: text.bodyMedium!.copyWith(color: Colors.white60)),
          const SizedBox(height: 4),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.water_drop_outlined, size: 14, color: (precip ?? 0) > 0 ? Colors.lightBlueAccent : Colors.white38),
              const SizedBox(width: 2),
              Text("${precip ?? 0}%",
                  style: text.bodySmall!.copyWith(color: (precip ?? 0) > 0 ? Colors.lightBlueAccent : Colors.white38)),
            ],
          ),
        ],
      ),
    );
  }
}

/// Today, or tonight: the sky and the temperatures that matter then, the chance of rain or snow, and now (or, tonight,
/// tomorrow's high).
class _SummaryCard extends StatelessWidget {
  final WeatherSummary summary;
  final bool fahrenheit;

  const _SummaryCard({required this.summary, required this.fahrenheit});

  static String conditionName(AppLocalizations l, int? code) {
    if (code == null) return l.weatherConditionCloudy;
    if (code == 800) return l.weatherConditionClear;
    if (code == 801 || code == 802) return l.weatherConditionPartlyCloudy;
    if (WeatherData.rainCodes.contains(code)) return l.weatherConditionRain;
    if (WeatherData.snowCodes.contains(code)) return l.weatherConditionSnow;
    if (WeatherData.stormCodes.contains(code)) return l.weatherConditionStorm;
    if (code == 701 || code == 711 || code == 721 || code == 741 || code == 751) return l.weatherConditionFog;
    if (code == 771) return l.weatherConditionWind;
    return l.weatherConditionCloudy;
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final text = Theme.of(context).textTheme;
    String deg(int? c) => WeatherData.formatDegrees(c, useFahrenheit: fahrenheit, withUnit: false);
    final temps = summary.tonight ? l.weatherSummaryLow(deg(summary.low)) : l.weatherSummaryHighLow(deg(summary.high), deg(summary.low));
    final lines = [
      if ((summary.precipProbability ?? 0) > 0) l.weatherSummaryPrecip("${summary.precipProbability}"),
      if (summary.tonight && summary.tomorrowHigh != null) l.weatherSummaryTomorrowHigh(deg(summary.tomorrowHigh)),
      if (summary.current != null) l.weatherSummaryNow(deg(summary.current)),
    ];
    return Container(
      key: const Key("weather_summary"),
      constraints: const BoxConstraints(minWidth: 420, maxWidth: 640),
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.35),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withOpacity(0.12)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(WeatherData.iconFor(summary.conditionCode), size: 64, color: Colors.white),
          const SizedBox(width: 20),
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(conditionName(l, summary.conditionCode),
                    style: text.headlineSmall!.copyWith(fontWeight: FontWeight.w700)),
                Text(temps, style: text.titleLarge!.copyWith(color: Colors.white)),
                const SizedBox(height: 6),
                for (final line in lines)
                  Text(line, style: text.bodyLarge!.copyWith(color: Colors.white70)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
