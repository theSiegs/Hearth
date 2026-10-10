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
import 'package:flauncher/widgets/title_pill.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

/// The weather over the home, in Continue Watching's spot while the top bar's weather has focus: the next hours, or
/// (after OK on the weather) the next five days. Nothing in it takes focus: the weather keeps it.
class WeatherForecastRow extends StatelessWidget {
  /// How many hours and days it shows.
  static const int hours = 10;
  static const int days = 5;

  const WeatherForecastRow({super.key});

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final weather = context.watch<WeatherService?>()?.weatherData;
    final showDays = context.watch<HomeForecast?>()?.days ?? false;
    final fahrenheit = context.select<SettingsService, bool>((s) => s.useFahrenheit);
    if (weather == null) return const SizedBox.shrink();
    final now = DateTime.now();
    final tiles = showDays ? _dayTiles(l, weather, now, fahrenheit) : _hourTiles(l, weather, now, fahrenheit);
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
              showDays ? l.weatherForecastDaily : l.weatherForecastHourly,
            ].join(" · "),
            style: Theme.of(context).textTheme.headlineSmall!.copyWith(fontWeight: FontWeight.w700, shadows: shadow),
          ),
          Text(
            showDays ? l.weatherForecastShowHourly : l.weatherForecastShowDaily,
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
    } catch (_) {
      return DateFormat.j("en_US").format(time);
    }
  }

  static String _dayLabel(String locale, DateTime date) {
    try {
      return DateFormat.E(locale).format(date);
    } catch (_) {
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
