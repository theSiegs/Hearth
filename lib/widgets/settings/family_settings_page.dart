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

import 'dart:async';

import 'package:flauncher/flauncher_channel.dart';
import 'package:flauncher/l10n/app_localizations.dart';
import 'package:flauncher/models/kids_profiles.dart';
import 'package:flauncher/providers/settings_service.dart';
import 'package:flauncher/quiet_failure.dart';
import 'package:flauncher/widgets/parent_pin_dialog.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'focusable_settings_tile.dart';
import 'household_page.dart';
import 'kids_profiles_page.dart';
import 'profile_pairing_page.dart';
import 'settings_page.dart';

/// Settings > Family: what's the whole TV's rather than one profile's, a parent's to set. The parent PIN comes first,
/// as the rest leans on it; then the kids profiles, Profile Pairing (every profile in every streaming app) and the
/// household of TVs that keep all of it in step.
class FamilySettingsPage extends StatelessWidget {
  static const String routeName = "family_settings";

  const FamilySettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final textTheme = Theme.of(context).textTheme;
    final hasPin = context.select<SettingsService, bool>((s) => s.hasParentPin);
    final householdPin = context.select<SettingsService, bool>((s) => s.householdParentPinOffered != null);
    return SettingsPage(
      title: l.familyTitle,
      children: [
        FocusableSettingsTile(
          autofocus: !householdPin,
          leading: const Icon(Icons.lock_outline),
          title: Text(l.parentPinTitle, style: textTheme.bodyMedium),
          trailing: Text(hasPin ? l.parentPinOn : l.parentPinOff, style: textTheme.bodySmall),
          onPressed: () => _editParentPin(context),
        ),
        // This TV had its own Parent PIN when it joined the household, and the other TVs use another one
        if (householdPin)
          FocusableSettingsTile(
            autofocus: true,
            leading: const Icon(Icons.holiday_village_outlined, color: Colors.amber),
            title: Text(l.parentPinHouseholdUse, style: textTheme.bodyMedium),
            onPressed: () => _takeHouseholdPin(context),
          ),
        const _KidsProfilesTile(),
        // No PIN of its own: in a kids profile, Settings already took the parent PIN to get here, and adult profiles
        // are only reached past Google TV's PIN.
        FocusableSettingsTile(
          leading: const Icon(Icons.switch_account),
          title: Text(l.profilePairingTitle, style: textTheme.bodyMedium),
          trailing: const Icon(Icons.chevron_right, color: Colors.white54),
          onPressed: () => Navigator.of(context).pushNamed(ProfilePairingPage.routeName),
        ),
        // Every profile's look, layout, pairing choices and PINs, kept in step with the household's other TVs
        const _HouseholdTile(),
      ],
    );
  }

  /// The household's Parent PIN, entered here, becomes this TV's (so joining never replaced it unseen).
  Future<void> _takeHouseholdPin(BuildContext context) async {
    final l = AppLocalizations.of(context)!;
    final settings = context.read<SettingsService>();
    final pin = await showDialog<String>(
      context: context,
      builder: (_) => ParentPinDialog(
          title: l.parentPinHouseholdTitle,
          subtitle: l.parentPinHouseholdSubtitle,
          verify: settings.verifyHouseholdParentPin),
    );
    if (pin != null) await settings.takeHouseholdParentPin();
  }

  Future<void> _editParentPin(BuildContext context) async {
    final l = AppLocalizations.of(context)!;
    final settings = context.read<SettingsService>();
    if (settings.hasParentPin) {
      final current = await showDialog<String>(
        context: context,
        builder: (_) => ParentPinDialog(title: l.parentPinCurrent, verify: settings.verifyParentPin),
      );
      if (current == null || !context.mounted) return;
      final bool? remove = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(l.parentPinTitle),
          actions: [
            TextButton(onPressed: () => Navigator.of(context).pop(true), child: Text(l.parentPinRemove)),
            TextButton(
                autofocus: true, onPressed: () => Navigator.of(context).pop(false), child: Text(l.parentPinChange)),
          ],
        ),
      );
      if (remove == null || !context.mounted) return;
      if (remove) {
        await settings.setParentPin(null);
        // The streaming apps' profile PINs were saved under the parent PIN: they go with it
        if (context.mounted) await context.read<FLauncherChannel>().removeAllProfilePins();
        return;
      }
    }
    await chooseNewParentPin(context);
  }
}

/// Kids profiles: how many need a fix, read as the page opens (what Android lists; no adb).
class _KidsProfilesTile extends StatefulWidget {
  const _KidsProfilesTile();

  @override
  State<_KidsProfilesTile> createState() => _KidsProfilesTileState();
}

class _KidsProfilesTileState extends State<_KidsProfilesTile> {
  late final FLauncherChannel? _channel = context.read<FLauncherChannel?>();
  KidsProfilesState? _state;

  @override
  void initState() {
    super.initState();
    _read();
  }

  Future<void> _read() async {
    try {
      final map = await _channel?.getKidsProfilesState();
      if (mounted && map != null) setState(() => _state = KidsProfilesState.fromMap(map));
    } catch (err) { noteFailure('family_settings_page', err); }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final textTheme = Theme.of(context).textTheme;
    final state = _state;
    final needing = state?.needingFix ?? 0;
    return FocusableSettingsTile(
      leading: const Icon(Icons.child_care),
      title: Text(l.kidsProfilesTitle, style: textTheme.bodyMedium),
      trailing: state == null || state.kids.isEmpty
          ? const Icon(Icons.chevron_right, color: Colors.white54)
          : Text(needing > 0 ? l.kidsProfilesNeedFixCount(needing) : l.kidsProfilesReady,
              style: textTheme.bodySmall?.copyWith(color: needing > 0 ? Colors.amber : Colors.green)),
      onPressed: () async {
        await Navigator.of(context).pushNamed(KidsProfilesPage.routeName);
        _read();
      },
    );
  }
}

/// Household sync: how many TVs, Off, Not set up, or a household found to join; read as the page opens.
class _HouseholdTile extends StatefulWidget {
  const _HouseholdTile();

  @override
  State<_HouseholdTile> createState() => _HouseholdTileState();
}

class _HouseholdTileState extends State<_HouseholdTile> {
  late final FLauncherChannel? _channel = context.read<FLauncherChannel?>();
  Map<dynamic, dynamic>? _status;

  /// How often it's read again while shown: a TV that just joined lists the household's other TVs once their entries
  /// come, which can be after this page opened.
  static const Duration refreshEvery = Duration(seconds: 5);
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _read();
    _timer = Timer.periodic(refreshEvery, (_) => _read());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _read() async {
    try {
      final status = await _channel?.getHouseholdStatus();
      if (mounted && status != null) setState(() => _status = status);
    } catch (err) { noteFailure('family_settings_page', err); }
  }

  /// The state in a word or two; null before it's read.
  static String? summary(AppLocalizations l, Map<dynamic, dynamic>? status) {
    if (status == null || status.isEmpty) return null;
    if (status["joined"] == true) {
      if (status["enabled"] == false) return l.householdSummaryOff;
      final members = (status["members"] as List?)?.length ?? 0;
      return l.householdSummaryTvs(members < 1 ? 1 : members);
    }
    return householdsNearby(status).isNotEmpty ? l.householdSummaryFound : l.householdSummaryNone;
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final textTheme = Theme.of(context).textTheme;
    final text = summary(l, _status);
    return FocusableSettingsTile(
      leading: const Icon(Icons.holiday_village_outlined),
      title: Text(l.householdTitle, style: textTheme.bodyMedium),
      trailing: text == null
          ? const Icon(Icons.chevron_right, color: Colors.white54)
          : Text(text, style: textTheme.bodySmall),
      onPressed: () async {
        await Navigator.of(context).pushNamed(HouseholdPage.routeName);
        _read();
      },
    );
  }
}
