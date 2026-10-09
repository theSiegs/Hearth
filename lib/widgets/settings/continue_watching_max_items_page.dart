/*
 * FLauncher
 * Copyright (C) 2026 LeanBitLab
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
import 'settings_choice_tile.dart';
import 'settings_page.dart';

class ContinueWatchingMaxItemsPage extends StatelessWidget {
  static const String routeName = "continue_watching_max_items_panel";

  const ContinueWatchingMaxItemsPage({super.key});

  static const List<(int, String, String)> maxItemsPresets = [
    (5, '5 Items', 'Display up to 5 recent items'),
    (10, '10 Items', 'Display up to 10 recent items'),
    (15, '15 Items', 'Display up to 15 recent items • Default'),
    (20, '20 Items', 'Display up to 20 recent items'),
    (0, 'Unlimited', 'Display all available items'),
  ];

  @override
  Widget build(BuildContext context) {
    return Selector<SettingsService, int>(
      selector: (_, settingsService) => settingsService.continueWatchingMaxItems,
      builder: (context, currentCount, _) {
        final settingsService = context.read<SettingsService>();

        return SettingsPage(
          title: AppLocalizations.of(context)!.maxItemsTitle,
          children: [
            for (final (count, title, subtitle) in maxItemsPresets)
              SettingsChoiceTile<int>(
                title: title,
                subtitle: subtitle,
                value: count,
                groupValue: currentCount,
                onChanged: settingsService.setContinueWatchingMaxItems,
              ),
          ],
        );
      },
    );
  }
}
