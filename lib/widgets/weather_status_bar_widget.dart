import 'package:flauncher/l10n/app_localizations.dart';
import 'package:flauncher/models/weather_data.dart';
import 'package:flauncher/providers/home_forecast.dart';
import 'package:flauncher/providers/settings_service.dart';
import 'package:flauncher/providers/weather_service.dart';
import 'package:flauncher/widgets/focusable_tap.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

/// The coming rain, snow or storm in the app's language ("80% Rain today"), or null when there's none.
String? weatherWarningText(AppLocalizations localizations, WeatherData weather) {
  final dayIndex = weather.warningDayIndex;
  final date = weather.warningDate;
  if (dayIndex == null || date == null) return weather.warningText;
  final when = switch (dayIndex) { 0 => "today", 1 => "tomorrow", _ => "other" };
  final day = when == "other" ? _weekday(localizations.localeName, date) : "";
  final forecast = switch (weather.warningType) {
    WeatherWarningType.rain => localizations.weatherTextRain(when, day),
    WeatherWarningType.snow => localizations.weatherTextSnow(when, day),
    WeatherWarningType.storm => localizations.weatherTextStorm(when, day),
    WeatherWarningType.none => null,
  };
  if (forecast == null) return null;
  final chance = weather.warningPrecipProbability;
  return chance == null ? forecast : localizations.weatherTextChance(chance, forecast);
}

/// The weekday's short name ("Mon"), in English when the language's dates aren't loaded.
String _weekday(String locale, DateTime date) {
  try {
    return DateFormat.E(locale).format(date);
  } catch (_) {
    return DateFormat.E("en_US").format(date);
  }
}

class WeatherStatusBarWidget extends StatelessWidget {
  final FocusNode? focusNode;

  const WeatherStatusBarWidget({super.key, this.focusNode});

  @override
  Widget build(BuildContext context) {
    return Selector<SettingsService, (bool, bool, bool)>(
      selector: (_, settings) => (
        settings.showWeatherInStatusBar,
        settings.showWeatherWarnings,
        settings.useFahrenheit,
      ),
      builder: (context, settingsTuple, _) {
        final (showWeather, showWarnings, useFahrenheit) = settingsTuple;
        if (!showWeather) return const SizedBox.shrink();

        return Consumer<WeatherService>(
          builder: (context, weatherService, _) {
            final weather = weatherService.weatherData;
            if (weather == null) return const SizedBox.shrink();

            final bool isWarning = showWarnings && weather.hasWarning;
            final icon = weather.getConditionIcon();
            final tempText = weather.formatTemperature(useFahrenheit: useFahrenheit);
            final localizations = AppLocalizations.of(context)!;
            final warning = isWarning ? weatherWarningText(localizations, weather) : null;

            final String displayText = warning != null
                ? localizations.weatherWidgetTemperatureWithWarning(tempText, warning)
                : tempText;

            final theme = Theme.of(context);

            // Focused, the forecast shows over the home; OK swaps the next hours and the next days. Without a
            // forecast to show, OK opens Breezy Weather (when it's the source), as before.
            final forecast = context.read<HomeForecast?>();
            final hasForecast = weather.hourly.isNotEmpty || weather.forecasts.isNotEmpty;
            return FocusableTap(
              focusNode: focusNode,
              onFocusChange: (focused) => forecast?.setShowing(focused && hasForecast),
              onPressed: () => forecast != null && hasForecast ? forecast.swap() : weatherService.openBreezyWeather(),
              splashShape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              builder: (context, focused) => AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.3),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: focused
                        ? theme.colorScheme.primary
                        : Colors.white.withOpacity(0.12),
                    width: 1,
                  ),
                  boxShadow: focused
                      ? const [
                          BoxShadow(
                            color: Colors.black54,
                            blurRadius: 8,
                            spreadRadius: 1,
                          )
                        ]
                      : null,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      icon,
                      size: 20,
                      color: Colors.white,
                      shadows: const [
                        Shadow(color: Colors.black54, offset: Offset(0, 2), blurRadius: 4)
                      ],
                    ),
                    const SizedBox(width: 8),
                    Text(
                      displayText,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w400,
                        color: Colors.white,
                        shadows: [
                          Shadow(color: Colors.black54, offset: Offset(0, 2), blurRadius: 4)
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
}
