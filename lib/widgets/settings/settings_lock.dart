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

import 'package:flauncher/providers/profile_service.dart';
import 'package:flauncher/widgets/parent_pin_dialog.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

/// Settings in a kids profile: open without the parent PIN, showing only what's the kid's own (switching profile,
/// the home screen's look) and a "Parent settings" row. The parent PIN there shows everything else (apps, the remote,
/// permissions, Home Assistant, Android's settings...) until the panel closes.
class SettingsUnlock extends InheritedNotifier<ValueNotifier<bool>> {
  const SettingsUnlock({super.key, required ValueNotifier<bool> super.notifier, required super.child});

  static ValueNotifier<bool>? _of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<SettingsUnlock>()?.notifier;

  /// The profile a parent unlocked Settings in: the unlock holds only while that profile is the active one, so it
  /// never carries over a switch to another kids profile with the panel still open.
  static final Expando<String> _unlockedFor = Expando<String>();

  static bool _holds(ValueNotifier<bool>? unlock, String? activeKey) =>
      unlock?.value == true && _unlockedFor[unlock!] == activeKey;
}

/// This part of Settings is locked here: a kids profile, not unlocked with the parent PIN since the panel opened.
bool settingsLocked(BuildContext context) {
  final kids = context.select<ProfileService?, bool>((p) => p?.isKidsProfile ?? false);
  final key = context.select<ProfileService?, String?>((p) => p?.activeProfileKey);
  return kids && !SettingsUnlock._holds(SettingsUnlock._of(context), key);
}

/// Asks for the parent PIN where Settings is locked; true when the locked part may open.
Future<bool> unlockSettings(BuildContext context) async {
  final unlock = context.getInheritedWidgetOfExactType<SettingsUnlock>()?.notifier;
  final profiles = context.read<ProfileService?>();
  if (SettingsUnlock._holds(unlock, profiles?.activeProfileKey)) return true;
  final kids = profiles?.isKidsProfile ?? false;
  final ok = await requireParent(context);
  if (ok && kids && unlock != null) {
    SettingsUnlock._unlockedFor[unlock] = profiles?.activeProfileKey;
    unlock.value = true;
  }
  return ok;
}

/// A parent unlocked Settings in this kids profile since the panel opened (the newly shown rows take focus).
bool settingsUnlocked(BuildContext context) => SettingsUnlock._holds(
    SettingsUnlock._of(context), context.select<ProfileService?, String?>((p) => p?.activeProfileKey));
