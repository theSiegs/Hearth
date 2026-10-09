/*
 * FLauncher
 * Copyright (C) 2024 LeanBitLab
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
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../providers/settings_service.dart';
import 'look_settings_page.dart';
import 'settings_choice_tile.dart';
import 'settings_page.dart';

class CardStylePage extends StatelessWidget {
  static const String routeName = "themes_panel";

  const CardStylePage({super.key});

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context)!;
    final current = context.select<SettingsService, String>((s) => s.themes);

    return SettingsPage(
      title: localizations.cardStyleTitle,
      children: [
        for (final MapEntry(key: value, value: label) in LookSettingsPage.cardStyles(localizations).entries)
          SettingsChoiceTile<String>(
            title: label,
            value: value,
            groupValue: current,
            onChanged: (value) => context.read<SettingsService>().setThemes(value),
          ),
      ],
    );
  }
}
