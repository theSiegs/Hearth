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

import 'package:flauncher/widgets/settings/applications_panel_page.dart';
import 'package:flauncher/widgets/settings/tv_power_settings_page.dart';
import 'package:flauncher/widgets/settings/system_settings_page.dart';
import 'package:flauncher/widgets/settings/home_assistant_page.dart';
import 'package:flauncher/widgets/settings/home_screen_settings_page.dart';
import 'package:flauncher/widgets/settings/notifications_settings_page.dart';
import 'package:flauncher/widgets/settings/profiles_settings_page.dart';
import 'package:flutter/material.dart';
import 'package:flauncher/l10n/app_localizations.dart';

import 'focusable_settings_tile.dart';
import 'settings_lock.dart';

/// The top of Settings: eight groups, each a page of its own.
class SettingsPanelPage extends StatelessWidget {
  static const String routeName = "settings_panel";

  const SettingsPanelPage({super.key});

  @override
  Widget build(BuildContext context) {
    AppLocalizations localizations = AppLocalizations.of(context)!;
    // In a kids profile only Profiles (switching) and Home screen (their own look) show, until a parent opens
    // Parent settings with the PIN; then everything shows until the panel closes, starting from Applications.
    final bool locked = settingsLocked(context);
    final bool justUnlocked = settingsUnlocked(context);

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 4, bottom: 8),
          child: Image.asset(
            "assets/logo.png",
            key: const Key("settings_logo"),
            height: 56,
            filterQuality: FilterQuality.medium,
            semanticLabel: "Hearth",
          ),
        ),
        const Divider(),
        Expanded(
          child: SingleChildScrollView(
            child: Column(
              children: [
                FocusableSettingsTile(
                  autofocus: !justUnlocked,
                  leading: const Icon(Icons.people_outline),
                  title: Text(localizations.profilesTitle, style: Theme.of(context).textTheme.bodyMedium),
                  trailing: Text(ProfilesSettingsPage.activeProfileLabel(context) ?? "", style: Theme.of(context).textTheme.bodySmall),
                  onPressed: () => Navigator.of(context).pushNamed(ProfilesSettingsPage.routeName),
                ),
                if (!locked)
                  FocusableSettingsTile(
                    autofocus: justUnlocked,
                    leading: const Icon(Icons.apps),
                    title: Text(localizations.applications, style: Theme.of(context).textTheme.bodyMedium),
                    onPressed: () => Navigator.of(context).pushNamed(ApplicationsPanelPage.routeName),
                  ),
                FocusableSettingsTile(
                  leading: const Icon(Icons.auto_awesome_mosaic_outlined),
                  title: Text(localizations.homeScreenTitle, style: Theme.of(context).textTheme.bodyMedium),
                  onPressed: () => Navigator.of(context).pushNamed(HomeScreenSettingsPage.routeName),
                ),
                if (!locked) ...[
                  FocusableSettingsTile(
                    leading: const Icon(Icons.notifications_active_outlined),
                    title: Text(localizations.notifications, style: Theme.of(context).textTheme.bodyMedium),
                    onPressed: () => Navigator.of(context).pushNamed(NotificationsSettingsPage.routeName),
                  ),
                  FocusableSettingsTile(
                    leading: const Icon(Icons.home_outlined),
                    title: Text("Home Assistant", style: Theme.of(context).textTheme.bodyMedium),
                    onPressed: () => Navigator.of(context).pushNamed(HomeAssistantPage.routeName),
                  ),
                  FocusableSettingsTile(
                    leading: const Icon(Icons.tv),
                    title: Text(localizations.tvPowerTitle, style: Theme.of(context).textTheme.bodyMedium),
                    onPressed: () => Navigator.of(context).pushNamed(TvPowerSettingsPage.routeName),
                  ),
                  FocusableSettingsTile(
                    leading: const Icon(Icons.settings_suggest_outlined),
                    title: Text(localizations.system, style: Theme.of(context).textTheme.bodyMedium),
                    onPressed: () => Navigator.of(context).pushNamed(SystemSettingsPage.routeName),
                  ),
                ],
                // A kids profile sees only its own things, and one way in for a parent
                if (locked)
                  FocusableSettingsTile(
                    leading: const Icon(Icons.lock_outline),
                    title: Text(localizations.parentSettingsTitle, style: Theme.of(context).textTheme.bodyMedium),
                    onPressed: () => unlockSettings(context),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }

}
