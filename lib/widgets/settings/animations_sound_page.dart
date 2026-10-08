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

import 'package:flauncher/providers/settings_service.dart';
import 'package:flauncher/widgets/rounded_switch_list_tile.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flauncher/l10n/app_localizations.dart';
import 'settings_page.dart';

/// Animations and the key click (under Look). The label and outline switches that used to be here are with the dock.
class AnimationsSoundPage extends StatelessWidget {
  static const String routeName = "misc_panel";
  static const String title = "Animations & sound";

  const AnimationsSoundPage({super.key});

  @override
  Widget build(BuildContext context) {
    AppLocalizations localizations = AppLocalizations.of(context)!;
    SettingsService settingsService = Provider.of(context);

    return SettingsPage(
      title: title,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      children: [
        RoundedSwitchListTile(
          autofocus: true,
          value: settingsService.appHighlightAnimationEnabled,
          onChanged: (value) => settingsService.setAppHighlightAnimationEnabled(value),
          title: Text(localizations.appCardHighlightAnimation, style: Theme.of(context).textTheme.bodyMedium),
          secondary: const Icon(Icons.filter_center_focus),
        ),
        RoundedSwitchListTile(
          value: settingsService.appKeyClickEnabled,
          onChanged: (value) => settingsService.setAppKeyClickEnabled(value),
          title: Text(localizations.appKeyClick, style: Theme.of(context).textTheme.bodyMedium),
          secondary: const Icon(Icons.notifications_active),
        ),
        RoundedSwitchListTile(
          value: settingsService.appSelectorTransitionAnimationEnabled,
          onChanged: (value) => settingsService.setAppSelectorTransitionAnimationEnabled(value),
          title: Text(localizations.appSelectorTransitionAnimation, style: Theme.of(context).textTheme.bodyMedium),
          secondary: const Icon(Icons.animation),
        ),
      ],
    );
  }
}
