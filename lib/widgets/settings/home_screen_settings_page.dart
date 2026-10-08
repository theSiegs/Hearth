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
import 'package:flauncher/l10n/app_localizations.dart';
import 'focusable_settings_tile.dart';
import 'settings_lock.dart';
import 'settings_page.dart';
import 'launcher_sections_panel_page.dart';
import 'continue_watching_settings_page.dart';
import 'wallpaper_panel_page.dart';
import 'look_settings_page.dart';
import 'status_bar_panel_page.dart';

class HomeScreenSettingsPage extends StatelessWidget {
  static const String routeName = "interface_settings_panel";
  static const String title = "Home screen";

  const HomeScreenSettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    AppLocalizations localizations = AppLocalizations.of(context)!;
    final bool locked = settingsLocked(context);

    return SettingsPage(
      title: title,
      children: [
        // Sections are a parent's to change (as on the home screen itself): hidden in a locked kids profile
        if (!locked)
          FocusableSettingsTile(
            autofocus: true,
            leading: const Icon(Icons.category),
            title: Text(localizations.launcherSections, style: Theme.of(context).textTheme.bodyMedium),
            onPressed: () => Navigator.of(context).pushNamed(LauncherSectionsPanelPage.routeName),
          ),
        FocusableSettingsTile(
          autofocus: locked,
          leading: const Icon(Icons.play_circle_outline),
          title: Text(localizations.continueWatching, style: Theme.of(context).textTheme.bodyMedium),
          onPressed: () => Navigator.of(context).pushNamed(ContinueWatchingSettingsPage.routeName),
        ),
        FocusableSettingsTile(
          leading: const Icon(Icons.style_outlined),
          title: Text("Look", style: Theme.of(context).textTheme.bodyMedium),
          onPressed: () => Navigator.of(context).pushNamed(LookSettingsPage.routeName),
        ),
        FocusableSettingsTile(
          leading: const Icon(Icons.wallpaper_outlined),
          title: Text(localizations.wallpaper, style: Theme.of(context).textTheme.bodyMedium),
          onPressed: () => Navigator.of(context).pushNamed(WallpaperPanelPage.routeName),
        ),
        FocusableSettingsTile(
          leading: const Icon(Icons.tips_and_updates),
          title: Text(localizations.statusBar, style: Theme.of(context).textTheme.bodyMedium),
          onPressed: () => Navigator.of(context).pushNamed(StatusBarPanelPage.routeName),
        ),
      ],
    );
  }
}
