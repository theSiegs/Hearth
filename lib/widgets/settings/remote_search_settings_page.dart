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

import 'package:flauncher/l10n/app_localizations.dart';
import 'package:flutter/material.dart';

import 'back_button_action_page.dart';
import 'focusable_settings_tile.dart';
import 'remote_buttons_page.dart';
import 'settings_page.dart';

/// The remote's buttons (remapping, what Back does on the home screen) and Hearth's search.
class RemoteSearchSettingsPage extends StatelessWidget {
  static const String routeName = "remote_search_settings";

  const RemoteSearchSettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context)!;
    final textTheme = Theme.of(context).textTheme;
    return SettingsPage(
      title: "Remote & search",
      children: [
        FocusableSettingsTile(
          autofocus: true,
          leading: const Icon(Icons.settings_remote_outlined),
          title: Text("Remote buttons", style: textTheme.bodyMedium),
          onPressed: () => Navigator.of(context).pushNamed(RemoteButtonsPage.routeName),
        ),
        FocusableSettingsTile(
          leading: const Icon(Icons.arrow_back),
          title: Text(localizations.backButtonAction, style: textTheme.bodyMedium),
          onPressed: () => Navigator.of(context).pushNamed(BackButtonActionPage.routeName),
        ),
      ],
    );
  }
}
