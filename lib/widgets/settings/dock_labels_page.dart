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

import 'package:flauncher/providers/settings_service.dart';
import 'package:flauncher/widgets/rounded_switch_list_tile.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flauncher/l10n/app_localizations.dart';
import 'settings_page.dart';

/// The favorites dock and the home screen's labels and focus outline (under Look).
class DockLabelsPage extends StatelessWidget {
  static const String routeName = "appearance_panel";

  const DockLabelsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context)!;
    final settingsService = context.watch<SettingsService>();
    final bodyMedium = Theme.of(context).textTheme.bodyMedium;
    final small = Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.white60);
    final dockEnabled = settingsService.dockEnabled;

    return SettingsPage(
      title: localizations.dockLabelsTitle,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      children: [
        RoundedSwitchListTile(
          autofocus: true,
          value: dockEnabled,
          onChanged: settingsService.setDockEnabled,
          title: Text(localizations.dockFavoritesDock, style: bodyMedium),
          secondary: const Icon(Icons.call_to_action_outlined),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: Text(localizations.dockFavoritesDockDescription, style: small),
        ),
        if (dockEnabled) ...[
          RoundedSwitchListTile(
            value: settingsService.dockBlurEnabled,
            onChanged: settingsService.setDockBlurEnabled,
            title: Text(localizations.dockFrosted, style: bodyMedium),
            secondary: const Icon(Icons.blur_on),
          ),
          RoundedSwitchListTile(
            value: settingsService.dockDarkBackground,
            onChanged: settingsService.setDockDarkBackground,
            title: Text(localizations.dockDark, style: bodyMedium),
            secondary: const Icon(Icons.dark_mode_outlined),
          ),
          RoundedSwitchListTile(
            value: settingsService.dockShadowEnabled,
            onChanged: settingsService.setDockShadowEnabled,
            title: Text(localizations.dockShadow, style: bodyMedium),
            secondary: const Icon(Icons.layers_outlined),
          ),
          RoundedSwitchListTile(
            value: settingsService.blurWallpaperBelowDock,
            onChanged: settingsService.setBlurWallpaperBelowDock,
            title: Text(localizations.dockBlurWallpaperBelow, style: bodyMedium),
            secondary: const Icon(Icons.lens_blur),
          ),
        ],
        const Divider(),
        RoundedSwitchListTile(
          value: settingsService.showCategoryTitles,
          onChanged: (value) => settingsService.setShowCategoryTitles(value),
          title: Text(localizations.showCategoryTitles, style: bodyMedium),
          secondary: const Icon(Icons.abc),
        ),
        RoundedSwitchListTile(
          value: settingsService.showCategoryAppCount,
          onChanged: (value) => settingsService.setShowCategoryAppCount(value),
          title: Text(localizations.showCategoryAppCount, style: bodyMedium),
          secondary: const Icon(Icons.numbers),
        ),
        RoundedSwitchListTile(
          value: settingsService.showAppNamesBelowIcons,
          onChanged: (value) => settingsService.setShowAppNamesBelowIcons(value),
          title: Text(localizations.showAppNamesBelowIcons, style: bodyMedium),
          secondary: const Icon(Icons.subtitles),
        ),
        RoundedSwitchListTile(
          value: settingsService.hideHighlightOutlineOnHomescreen,
          onChanged: (value) => settingsService.setHideHighlightOutlineOnHomescreen(value),
          title: Text(localizations.hideHighlightOutlineOnHomescreen, style: bodyMedium),
          secondary: const Icon(Icons.border_clear),
        ),
      ],
    );
  }
}
