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

class ContinueWatchingCardSizePage extends StatelessWidget {
  static const String routeName = "continue_watching_card_size_panel";

  const ContinueWatchingCardSizePage({super.key});

  static const List<(int, String, String)> cardSizePresets = [
    (80, '80 dp • Extra Small', '142 × 80 dp'),
    (90, '90 dp • Very Small', '160 × 90 dp'),
    (100, '100 dp • Small', '178 × 100 dp'),
    (110, '110 dp • Compact', '196 × 110 dp'),
    (120, '120 dp • Medium Small', '213 × 120 dp'),
    (130, '130 dp • Medium', '231 × 130 dp'),
    (135, '135 dp • Standard (Default)', '240 × 135 dp'),
    (140, '140 dp • Medium Large', '249 × 140 dp'),
    (150, '150 dp • Large', '267 × 150 dp'),
    (160, '160 dp • Very Large', '284 × 160 dp'),
    (170, '170 dp • Extra Large', '302 × 170 dp'),
    (180, '180 dp • Huge', '320 × 180 dp'),
  ];

  @override
  Widget build(BuildContext context) {
    return Selector<SettingsService, int>(
      selector: (_, settingsService) => settingsService.continueWatchingCardHeight,
      builder: (context, currentHeight, _) {
        final settingsService = context.read<SettingsService>();
        return SettingsPage(
          title: AppLocalizations.of(context)!.cardSizeTitle,
          children: [
            for (final (height, title, subtitle) in cardSizePresets)
              SettingsChoiceTile<int>(
                title: title,
                subtitle: subtitle,
                value: height,
                groupValue: currentHeight,
                onChanged: (height) => settingsService.setContinueWatchingCardHeight(height),
              ),
          ],
        );
      },
    );
  }
}
