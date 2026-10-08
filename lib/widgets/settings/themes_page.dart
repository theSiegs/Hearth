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

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flauncher/l10n/app_localizations.dart';

import '../../providers/settings_service.dart';
import 'look_settings_page.dart';
import 'settings_choice_tile.dart';

class ThemesPage extends StatelessWidget {
  static const String routeName = "themes_panel";

  const ThemesPage({super.key});

  @override
  Widget build(BuildContext context) {
    AppLocalizations localizations = AppLocalizations.of(context)!;
    final current = context.select<SettingsService, String>((s) => s.themes);

    return Column(
      children: [
        Text(localizations.themes, style: Theme.of(context).textTheme.titleLarge),
        const Divider(),
        Expanded(
          child: SingleChildScrollView(
            child: Column(
              children: [
                for (final MapEntry(key: value, value: title) in LookSettingsPage.cardStyles.entries)
                  SettingsChoiceTile<String>(
                    title: title,
                    value: value,
                    groupValue: current,
                    onChanged: (value) => context.read<SettingsService>().setThemes(value),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
