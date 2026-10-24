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
import 'package:flauncher/flauncher_channel.dart';
import 'package:flauncher/quiet_failure.dart';
import 'package:provider/provider.dart';
import 'package:flauncher/l10n/app_localizations.dart';
import 'focusable_settings_tile.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'updates_page.dart';
import 'hearth_about_dialog.dart';
import 'setup_checklist_page.dart';
import 'backup_restore_page.dart';
import 'ad_sandbox_page.dart';
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
          leading: const Icon(Icons.checklist),
          title: Text(AppLocalizations.of(context)!.setupHearthTitle, style: Theme.of(context).textTheme.bodyMedium),
          onPressed: () => Navigator.of(context).pushNamed(SetupChecklistPage.routeName),
        ),
        FocusableSettingsTile(
          leading: const Icon(Icons.system_update_outlined),
          title: Text(AppLocalizations.of(context)!.updatesTitle, style: Theme.of(context).textTheme.bodyMedium),
          onPressed: () => Navigator.of(context).pushNamed(UpdatesPage.routeName),
        ),
        FocusableSettingsTile(
          leading: const Icon(Icons.settings_backup_restore),
          title: Text(localizations.backupAndRestore, style: Theme.of(context).textTheme.bodyMedium),
          onPressed: () => Navigator.of(context).pushNamed(BackupRestorePage.routeName),
        ),
        FocusableSettingsTile(
          leading: const Icon(Icons.privacy_tip_outlined),
          title: Text(localizations.adSandboxTitle, style: Theme.of(context).textTheme.bodyMedium),
          onPressed: () => Navigator.of(context).pushNamed(AdSandboxPage.routeName),
        ),
        FocusableSettingsTile(
          leading: const Icon(Icons.info_outline),
          title: Text(localizations.aboutFlauncher, style: Theme.of(context).textTheme.bodyMedium),
          onPressed: () {
            // Read once: the dialog's builder runs again as it opens, and a new read would start it over
            final info = _aboutInfo(context.read<FLauncherChannel>());
            showDialog(
              context: context,
              builder: (_) => FutureBuilder<(PackageInfo, String?)>(
                future: info,
                builder: (context, snapshot) => snapshot.connectionState == ConnectionState.done && snapshot.hasData
                    ? HearthAboutDialog(packageInfo: snapshot.data!.$1, tvName: snapshot.data!.$2)
                    : Container(),
              ),
            );
          },
        ),
      ],
    );
  }

  /// Hearth's version and this TV's name; the About page still opens when the name can't be read.
  static Future<(PackageInfo, String?)> _aboutInfo(FLauncherChannel channel) async {
    final info = await PackageInfo.fromPlatform();
    String? name;
    try {
      name = await channel.getTvName();
    } catch (err) {
      noteFailure('system_settings_page', err);
    }
    return (info, name);
  }
}
