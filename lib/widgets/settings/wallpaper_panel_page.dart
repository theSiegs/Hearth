/*
 * FLauncher
 * Copyright (C) 2021  Étienne Fesser
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
import 'package:flauncher/providers/wallpaper_service.dart';
import 'package:flauncher/widgets/settings/focusable_settings_tile.dart';
import 'package:flauncher/widgets/settings/gradient_panel_page.dart';
import 'package:flauncher/widgets/settings/settings_page.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flauncher/l10n/app_localizations.dart';

import 'package:flauncher/widgets/rounded_switch_list_tile.dart';

class WallpaperPanelPage extends StatelessWidget {
  static const String routeName = "wallpaper_panel";

  const WallpaperPanelPage({super.key});

  @override
  Widget build(BuildContext context) {
    AppLocalizations localizations = AppLocalizations.of(context)!;

    return Consumer2<SettingsService, WallpaperService>(
      builder: (_, settings, wallpaperService, __) => SettingsPage(
        title: localizations.wallpaper,
        children: [
          RoundedSwitchListTile(
            title: Text(localizations.wallpaperMatchSelectedApp),
            secondary: const Icon(Icons.palette_outlined),
            value: settings.matchSelectedAppBackground,
            onChanged: (value) => settings.setMatchSelectedAppBackground(value),
          ),
          RoundedSwitchListTile(
            title: Text(localizations.wallpaperBingPhotoOfTheDay),
            secondary: const Icon(Icons.photo_library_outlined),
            value: settings.bingWallpaperEnabled,
            onChanged: (value) => settings.setBingWallpaperEnabled(value),
          ),
          if (!settings.bingWallpaperEnabled)
            RoundedSwitchListTile(
              title: Text(localizations.timeBasedWallpaper),
              secondary: Icon(Icons.access_time),
              value: settings.timeBasedWallpaperEnabled,
              onChanged: (value) => settings.setTimeBasedWallpaperEnabled(value),
            ),
          if (settings.bingWallpaperEnabled) ...[
            FocusableSettingsTile(
              autofocus: true,
              leading: const Icon(Icons.refresh),
              title: Text(localizations.wallpaperRefreshNow),
              onPressed: () => wallpaperService.refreshBingWallpaper(),
            ),
            if (wallpaperService.bingWallpaperError)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Text(
                  localizations.wallpaperBingError,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.redAccent, fontSize: 12),
                ),
              ),
          ] else if (settings.timeBasedWallpaperEnabled) ...[
            FocusableSettingsTile(
              leading: Icon(Icons.wb_sunny),
              title: Text(localizations.pickDayWallpaper),
              onPressed: () => _pickWallpaper(context, (s) => s.pickWallpaperDay(), localizations),
            ),
            FocusableSettingsTile(
              leading: Icon(Icons.nights_stay),
              title: Text(localizations.pickNightWallpaper),
              onPressed: () => _pickWallpaper(context, (s) => s.pickWallpaperNight(), localizations),
            ),
          ] else ...[
            FocusableSettingsTile(
              autofocus: true,
              leading: Icon(Icons.gradient),
              title: Text(localizations.gradient, style: Theme.of(context).textTheme.bodyMedium),
              onPressed: () => Navigator.of(context).pushNamed(GradientPanelPage.routeName),
            ),
            FocusableSettingsTile(
              leading: Icon(Icons.insert_drive_file_outlined),
              title: Text(localizations.picture, style: Theme.of(context).textTheme.bodyMedium),
              onPressed: () => _pickWallpaper(context, (s) => s.pickWallpaper(), localizations),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _pickWallpaper(
      BuildContext context, Future<void> Function(WallpaperService) action, AppLocalizations localizations) async {
    try {
      await action(context.read<WallpaperService>());
    } on NoFileExplorerException {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          duration: Duration(seconds: 8),
          content: Row(
            children: [
              Icon(Icons.error_outline, color: Colors.red),
              SizedBox(width: 8),
              Text(localizations.dialogTextNoFileExplorer)
            ],
          ),
        ),
      );
    }
  }
}
