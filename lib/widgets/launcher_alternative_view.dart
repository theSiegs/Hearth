/*
 * FLauncher
 * Copyright (C) 2021  Oscar Rojas
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

import 'package:flauncher/providers/settings_service.dart';
import 'package:flauncher/widgets/date_time_widget.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class AlternativeLauncherView extends StatelessWidget {
  const AlternativeLauncherView({super.key});

  @override
  Widget build(BuildContext context) => Selector<SettingsService, (String, String)>(
    selector: (_, service) => (service.timeFormat, service.dateFormat),
    builder: (context, formats, _) {
      final (timeFormat, dateFormat) = formats;
      return Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _buildClock(context, timeFormat),
          const SizedBox(height: 16),
          DateTimeWidget(dateFormat,
            textStyle: Theme.of(context).textTheme.headlineLarge!.copyWith(
              fontSize: 56,
              fontWeight: FontWeight.w300,
              shadows: const [Shadow(color: Colors.black54, offset: Offset(1, 1), blurRadius: 12)],
            )
          )
        ],
      );
    },
  );

  Widget _buildClock(BuildContext context, String timeFormat) {
    const fontSize = 120.0;
    final mainStyle = Theme.of(context).textTheme.displayLarge!.copyWith(
      fontSize: fontSize,
      fontWeight: FontWeight.w200,
      letterSpacing: 2.0,
      shadows: const [Shadow(color: Colors.black54, offset: Offset(2, 2), blurRadius: 16)],
    );

    // Check if format has AM/PM (contains 'a')
    final hasAmPm = timeFormat.contains('a');
    if (!hasAmPm) {
      return DateTimeWidget(timeFormat, textStyle: mainStyle);
    }

    // Split: render time without AM/PM at full size, AM/PM at 35% size on same line
    final timeOnly = timeFormat.replaceAll(RegExp(r'\s*a\s*'), '').trim();
    final amPmStyle = mainStyle.copyWith(
      fontSize: fontSize * 0.35,
      fontWeight: FontWeight.w400,
      letterSpacing: 1.0,
    );

    return IntrinsicHeight(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          DateTimeWidget(timeOnly, textStyle: mainStyle),
          const SizedBox(width: 8),
          Column(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              DateTimeWidget('a', animate: false, textStyle: amPmStyle),
            ],
          ),
        ],
      ),
    );
  }
}
