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
import 'package:package_info_plus/package_info_plus.dart';
import 'updates_page.dart';
import 'hearth_about_dialog.dart';
import 'setup_checklist_page.dart';
import 'backup_restore_page.dart';
import 'app_language_page.dart';
import 'package:flauncher/flauncher_channel.dart';
import 'settings_page.dart';

class SystemSettingsPage extends StatelessWidget {
  static const String routeName = "general_settings_panel";

  const SystemSettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    AppLocalizations localizations = AppLocalizations.of(context)!;

    return SettingsPage(
      title: localizations.system,
      children: [
        FocusableSettingsTile(
          autofocus: true,
          leading: const Icon(Icons.language),
          title: Text(localizations.appLanguage, style: Theme.of(context).textTheme.bodyMedium),
          onPressed: () => Navigator.of(context).pushNamed(AppLanguagePage.routeName),
        ),
        FocusableSettingsTile(
          leading: const Icon(Icons.checklist),
          title: Text(SetupChecklistPage.title, style: Theme.of(context).textTheme.bodyMedium),
          onPressed: () => Navigator.of(context).pushNamed(SetupChecklistPage.routeName),
        ),
        FocusableSettingsTile(
          leading: const Icon(Icons.system_update_outlined),
          title: Text(UpdatesPage.title, style: Theme.of(context).textTheme.bodyMedium),
          onPressed: () => Navigator.of(context).pushNamed(UpdatesPage.routeName),
        ),
        FocusableSettingsTile(
          leading: const Icon(Icons.tv_outlined),
          title: Text("Use Google TV for now", style: Theme.of(context).textTheme.bodyMedium),
          onPressed: () => FLauncherChannel().openGoogleTvHome(),
        ),
        FocusableSettingsTile(
          leading: const Icon(Icons.settings_backup_restore),
          title: Text(localizations.backupAndRestore, style: Theme.of(context).textTheme.bodyMedium),
          onPressed: () => Navigator.of(context).pushNamed(BackupRestorePage.routeName),
        ),
        FocusableSettingsTile(
          leading: const Icon(Icons.info_outline),
          title: Text(localizations.aboutFlauncher, style: Theme.of(context).textTheme.bodyMedium),
          onPressed: () => showDialog(
            context: context,
            builder: (_) => FutureBuilder<PackageInfo>(
              future: PackageInfo.fromPlatform(),
              builder: (context, snapshot) => snapshot.connectionState == ConnectionState.done && snapshot.hasData
                  ? HearthAboutDialog(packageInfo: snapshot.data!)
                  : Container(),
            ),
          ),
        ),
      ],
    );
  }
}
