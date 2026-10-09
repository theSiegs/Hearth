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

  /// The heights to pick from, each with its card's width and its size's name in the current language.
  static List<(int height, int width, String name)> cardSizePresets(AppLocalizations localizations) => [
        (80, 142, localizations.cwCardSizeExtraSmall),
        (90, 160, localizations.cwCardSizeVerySmall),
        (100, 178, localizations.cwCardSizeSmall),
        (110, 196, localizations.cwCardSizeCompact),
        (120, 213, localizations.cwCardSizeMediumSmall),
        (130, 231, localizations.cwCardSizeMedium),
        (135, 240, localizations.cwCardSizeStandardDefault),
        (140, 249, localizations.cwCardSizeMediumLarge),
        (150, 267, localizations.cwCardSizeLarge),
        (160, 284, localizations.cwCardSizeVeryLarge),
        (170, 302, localizations.cwCardSizeExtraLarge),
        (180, 320, localizations.cwCardSizeHuge),
      ];

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context)!;
    return Selector<SettingsService, int>(
      selector: (_, settingsService) => settingsService.continueWatchingCardHeight,
      builder: (context, currentHeight, _) {
        final settingsService = context.read<SettingsService>();
        return SettingsPage(
          title: localizations.cardSizeTitle,
          children: [
            for (final (height, width, name) in cardSizePresets(localizations))
              SettingsChoiceTile<int>(
                title: localizations.cwCardSizeOption(height, name),
                subtitle: localizations.cwCardSizeDimensions(width, height),
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
