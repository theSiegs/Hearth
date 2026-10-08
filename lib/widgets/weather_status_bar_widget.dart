import 'package:flauncher/providers/settings_service.dart';
import 'package:flauncher/providers/weather_service.dart';
import 'package:flauncher/widgets/focusable_tap.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

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

            String displayText;
            if (isWarning && weather.warningText != null) {
              displayText = "$tempText • ${weather.warningText}";
            } else {
              displayText = tempText;
            }

            final theme = Theme.of(context);

            return FocusableTap(
              focusNode: focusNode,
              onPressed: () => weatherService.openBreezyWeather(),
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
