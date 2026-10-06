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

class AppearancePanelPage extends StatelessWidget {
  static const String routeName = "appearance_panel";

  const AppearancePanelPage({super.key});

  @override
  Widget build(BuildContext context) {
    final settingsService = context.watch<SettingsService>();
    final bodyMedium = Theme.of(context).textTheme.bodyMedium;
    final small = Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.white60);
    final dockEnabled = settingsService.dockEnabled;

    return Column(
      children: [
        Text("Appearance", style: Theme.of(context).textTheme.titleLarge),
        const Divider(),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            children: [
              RoundedSwitchListTile(
                autofocus: true,
                value: dockEnabled,
                onChanged: settingsService.setDockEnabled,
                title: Text("Favorites dock", style: bodyMedium),
                secondary: const Icon(Icons.call_to_action_outlined),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Text(
                  "Shows Favorites as a bar along the bottom of the home screen, with Continue Watching above it "
                  "and your other sections below. Its corners follow the theme.",
                  style: small,
                ),
              ),
              if (dockEnabled) ...[
                RoundedSwitchListTile(
                  value: settingsService.dockBlurEnabled,
                  onChanged: settingsService.setDockBlurEnabled,
                  title: Text("Frosted dock", style: bodyMedium),
                  secondary: const Icon(Icons.blur_on),
                ),
                RoundedSwitchListTile(
                  value: settingsService.dockDarkBackground,
                  onChanged: settingsService.setDockDarkBackground,
                  title: Text("Dark dock", style: bodyMedium),
                  secondary: const Icon(Icons.dark_mode_outlined),
                ),
                RoundedSwitchListTile(
                  value: settingsService.dockShadowEnabled,
                  onChanged: settingsService.setDockShadowEnabled,
                  title: Text("Dock shadow", style: bodyMedium),
                  secondary: const Icon(Icons.layers_outlined),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}
