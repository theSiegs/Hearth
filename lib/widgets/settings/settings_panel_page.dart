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

import 'package:flauncher/widgets/settings/home_assistant_page.dart';
import 'package:flauncher/widgets/settings/remote_buttons_page.dart';
import 'package:flauncher/providers/settings_service.dart';
import 'package:flauncher/widgets/parent_pin_dialog.dart';
import 'package:flauncher/providers/apps_service.dart';
import 'package:flauncher/flauncher_channel.dart';
import 'package:flauncher/widgets/settings/accessibility_page.dart';
import 'package:flauncher/widgets/settings/applications_panel_page.dart';
import 'package:flauncher/widgets/settings/donate_dialog.dart';
import 'package:flauncher/widgets/settings/flauncher_about_dialog.dart';
import 'package:flauncher/widgets/settings/interface_settings_page.dart';
import 'package:flauncher/widgets/settings/display_settings_page.dart';
import 'package:flauncher/widgets/settings/notifications_settings_page.dart';
import 'package:flauncher/widgets/settings/general_settings_page.dart';
import 'package:flauncher/widgets/settings/update_dialog.dart';
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';
import 'package:flauncher/l10n/app_localizations.dart';

import 'focusable_settings_tile.dart';

class SettingsPanelPage extends StatelessWidget {
  static const String routeName = "settings_panel";

  const SettingsPanelPage({super.key});

  @override
  Widget build(BuildContext context) {
    AppLocalizations localizations = AppLocalizations.of(context)!;

    return Column(
      children: [
        Text(localizations.settings, style: Theme.of(context).textTheme.titleLarge),
        const Divider(),
        Expanded(
          child: SingleChildScrollView(
            child: Column(
              children: [
                FocusableSettingsTile(
                  autofocus: true,
                  leading: const Icon(Icons.people_outline),
                  title: Text("Profiles", style: Theme.of(context).textTheme.bodyMedium),
                  onPressed: () => FLauncherChannel().openProfileChooser(),
                ),
                FocusableSettingsTile(
                  leading: const Icon(Icons.lock_outline),
                  title: Text("Parent PIN", style: Theme.of(context).textTheme.bodyMedium),
                  trailing: Text(
                    context.select<SettingsService, bool>((s) => s.hasParentPin) ? "On" : "Off",
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  onPressed: () => _editParentPin(context),
                ),
                FocusableSettingsTile(
                  leading: const Icon(Icons.apps),
                  title: Text(localizations.applications, style: Theme.of(context).textTheme.bodyMedium),
                  onPressed: () => Navigator.of(context).pushNamed(ApplicationsPanelPage.routeName),
                ),
                FocusableSettingsTile(
                  leading: const Icon(Icons.auto_awesome_mosaic_outlined),
                  title: Text(localizations.interface, style: Theme.of(context).textTheme.bodyMedium),
                  onPressed: () => Navigator.of(context).pushNamed(InterfaceSettingsPage.routeName),
                ),
                FocusableSettingsTile(
                  leading: const Icon(Icons.tv),
                  title: Text(localizations.displayAndScreensaver, style: Theme.of(context).textTheme.bodyMedium),
                  onPressed: () => Navigator.of(context).pushNamed(DisplaySettingsPage.routeName),
                ),
                FocusableSettingsTile(
                  leading: const Icon(Icons.notifications_active_outlined),
                  title: Text(localizations.notifications, style: Theme.of(context).textTheme.bodyMedium),
                  onPressed: () => Navigator.of(context).pushNamed(NotificationsSettingsPage.routeName),
                ),
                FocusableSettingsTile(
                  leading: const Icon(Icons.settings_suggest_outlined),
                  title: Text(localizations.system, style: Theme.of(context).textTheme.bodyMedium),
                  onPressed: () => Navigator.of(context).pushNamed(GeneralSettingsPage.routeName),
                ),
                FocusableSettingsTile(
                  leading: const Icon(Icons.accessibility_new),
                  title: Text(localizations.accessibility, style: Theme.of(context).textTheme.bodyMedium),
                  onPressed: () => Navigator.of(context).pushNamed(AccessibilityPage.routeName),
                ),
                FocusableSettingsTile(
                  leading: const Icon(Icons.settings_remote_outlined),
                  title: Text("Remote buttons", style: Theme.of(context).textTheme.bodyMedium),
                  onPressed: () => Navigator.of(context).pushNamed(RemoteButtonsPage.routeName),
                ),
                FocusableSettingsTile(
                  leading: const Icon(Icons.home_outlined),
                  title: Text("Home Assistant", style: Theme.of(context).textTheme.bodyMedium),
                  onPressed: () => Navigator.of(context).pushNamed(HomeAssistantPage.routeName),
                ),
                FocusableSettingsTile(
                  leading: const Icon(Icons.favorite_rounded),
                  title: Text("Support & Donate", style: Theme.of(context).textTheme.bodyMedium),
                  onPressed: () => showDialog(
                    context: context,
                    builder: (_) => const DonateDialog(),
                  ),
                ),
                FocusableSettingsTile(
                  leading: const Icon(Icons.system_update_outlined),
                  title: Text("Check for Updates", style: Theme.of(context).textTheme.bodyMedium),
                  onPressed: () => showDialog(
                    context: context,
                    builder: (_) => const UpdateDialog(),
                  ),
                ),
                const Divider(),
                FocusableSettingsTile(
                  leading: const Icon(Icons.settings_outlined),
                  title: Text(localizations.systemSettings, style: Theme.of(context).textTheme.bodyMedium),
                  onPressed: () => context.read<AppsService>().openSettings(),
                ),
                FocusableSettingsTile(
                  leading: const Icon(Icons.info_outline),
                  title: Text(localizations.aboutFlauncher, style: Theme.of(context).textTheme.bodyMedium),
                  onPressed: () => showDialog(
                    context: context,
                    builder: (_) => FutureBuilder<PackageInfo>(
                      future: PackageInfo.fromPlatform(),
                      builder: (context, snapshot) => snapshot.connectionState == ConnectionState.done && snapshot.hasData
                          ? LTvLauncherAboutDialog(packageInfo: snapshot.data!)
                          : Container(),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  /// Parent PIN guards launcher settings and app menus in Google TV kids profiles.
  Future<void> _editParentPin(BuildContext context) async {
    final settings = context.read<SettingsService>();
    if (settings.hasParentPin) {
      final current = await showDialog<String>(
        context: context,
        builder: (_) => ParentPinDialog(title: "Current parent PIN", verify: settings.verifyParentPin),
      );
      if (current == null || !context.mounted) return;
      final bool? remove = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text("Parent PIN"),
          actions: [
            TextButton(onPressed: () => Navigator.of(context).pop(true), child: const Text("Remove PIN")),
            TextButton(autofocus: true, onPressed: () => Navigator.of(context).pop(false), child: const Text("Change PIN")),
          ],
        ),
      );
      if (remove == null || !context.mounted) return;
      if (remove) {
        await settings.setParentPin(null);
        return;
      }
    }
    final first = await showDialog<String>(
      context: context,
      builder: (_) => const ParentPinDialog(
          title: "New parent PIN", subtitle: "Needed to change the launcher in Google TV kids profiles"),
    );
    if (first == null || !context.mounted) return;
    final second = await showDialog<String>(
      context: context,
      builder: (_) => ParentPinDialog(title: "Enter the PIN again", verify: (pin) => pin == first),
    );
    if (second != null) {
      await settings.setParentPin(first);
    }
  }
}
