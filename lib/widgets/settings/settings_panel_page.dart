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
import 'package:flauncher/widgets/settings/display_settings_page.dart';
import 'package:flauncher/widgets/settings/general_settings_page.dart';
import 'package:flauncher/widgets/settings/home_assistant_page.dart';
import 'package:flauncher/widgets/settings/interface_settings_page.dart';
import 'package:flauncher/widgets/settings/notifications_settings_page.dart';
import 'package:flauncher/widgets/settings/profiles_settings_page.dart';
import 'package:flauncher/widgets/settings/remote_search_settings_page.dart';
import 'package:flutter/material.dart';
import 'package:flauncher/l10n/app_localizations.dart';

import 'focusable_settings_tile.dart';

/// The top of Settings: eight groups, each a page of its own.
class SettingsPanelPage extends StatelessWidget {
  static const String routeName = "settings_panel";

  const SettingsPanelPage({super.key});

  @override
  Widget build(BuildContext context) {
    AppLocalizations localizations = AppLocalizations.of(context)!;

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
                  autofocus: true,
                  leading: const Icon(Icons.people_outline),
                  title: Text("Profiles", style: Theme.of(context).textTheme.bodyMedium),
                  trailing: Text(ProfilesSettingsPage.activeProfileLabel(context) ?? "", style: Theme.of(context).textTheme.bodySmall),
                  onPressed: () => Navigator.of(context).pushNamed(ProfilesSettingsPage.routeName),
                ),
                FocusableSettingsTile(
                  leading: const Icon(Icons.apps),
                  title: Text(localizations.applications, style: Theme.of(context).textTheme.bodyMedium),
                  onPressed: () => Navigator.of(context).pushNamed(ApplicationsPanelPage.routeName),
                ),
                FocusableSettingsTile(
                  leading: const Icon(Icons.auto_awesome_mosaic_outlined),
                  title: Text("Home screen", style: Theme.of(context).textTheme.bodyMedium),
                  onPressed: () => Navigator.of(context).pushNamed(InterfaceSettingsPage.routeName),
                ),
                FocusableSettingsTile(
                  leading: const Icon(Icons.settings_remote_outlined),
                  title: Text("Remote & search", style: Theme.of(context).textTheme.bodyMedium),
                  onPressed: () => Navigator.of(context).pushNamed(RemoteSearchSettingsPage.routeName),
                ),
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
                  title: Text(DisplaySettingsPage.title, style: Theme.of(context).textTheme.bodyMedium),
                  onPressed: () => Navigator.of(context).pushNamed(DisplaySettingsPage.routeName),
                ),
                FocusableSettingsTile(
                  leading: const Icon(Icons.settings_suggest_outlined),
                  title: Text(localizations.system, style: Theme.of(context).textTheme.bodyMedium),
                  onPressed: () => Navigator.of(context).pushNamed(GeneralSettingsPage.routeName),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

}
