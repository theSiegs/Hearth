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

import 'package:flauncher/flauncher_channel.dart';
import 'package:flauncher/providers/profile_service.dart';
import 'package:flauncher/providers/settings_service.dart';
import 'package:flauncher/widgets/parent_pin_dialog.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'focusable_settings_tile.dart';
import 'profile_pairing_page.dart';
import 'settings_lock.dart';
import 'settings_page.dart';

/// Google TV profiles, Profile Pairing in the streaming apps, and the parent PIN.
class ProfilesSettingsPage extends StatelessWidget {
  static const String routeName = "profiles_settings";

  const ProfilesSettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final hasPin = context.select<SettingsService, bool>((s) => s.hasParentPin);
    final bool locked = settingsLocked(context);
    return SettingsPage(
      title: "Profiles",
      children: [
        FocusableSettingsTile(
          autofocus: true,
          leading: const Icon(Icons.people_outline),
          title: Text("Switch profile", style: textTheme.bodyMedium),
          trailing: Text(activeProfileLabel(context) ?? "", style: textTheme.bodySmall),
          onPressed: () => FLauncherChannel().openProfileChooser(),
        ),
        // No PIN of its own: in a kids profile, Settings already took the parent PIN to get here, and
        // grown-up profiles are only reached past Google TV's PIN.
        if (!locked)
          FocusableSettingsTile(
            leading: const Icon(Icons.switch_account),
            title: Text("Profile Pairing", style: textTheme.bodyMedium),
            onPressed: () => Navigator.of(context).pushNamed(ProfilePairingPage.routeName),
          ),
        if (!locked)
          FocusableSettingsTile(
            leading: const Icon(Icons.lock_outline),
            title: Text("Parent PIN", style: textTheme.bodyMedium),
            trailing: Text(hasPin ? "On" : "Off", style: textTheme.bodySmall),
            onPressed: () => _editParentPin(context),
          ),
      ],
    );
  }

  /// The signed-in Google TV profile's name, when Hearth knows it (and there is a ProfileService).
  static String? activeProfileLabel(BuildContext context) {
    try {
      return context.select<ProfileService, String?>((p) => p.activeProfileName);
    } on ProviderNotFoundException {
      return null;
    }
  }

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
            TextButton(
                autofocus: true, onPressed: () => Navigator.of(context).pop(false), child: const Text("Change PIN")),
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
