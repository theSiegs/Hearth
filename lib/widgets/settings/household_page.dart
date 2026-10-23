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
import 'package:flauncher/providers/settings_service.dart';
import 'package:flauncher/quiet_failure.dart';
import 'package:flauncher/widgets/parent_pin_dialog.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'focusable_settings_tile.dart';
import 'settings_page.dart';

/// Settings > Profiles > Copy profiles between TVs > Household sync: whether this TV is in a household of TVs that keep
/// Profile Pairing and saved PINs in step, the one switch, and leaving. (Adding a TV is a copy: see ShareSendPage.)
class HouseholdPage extends StatefulWidget {
  static const String routeName = "household";

  const HouseholdPage({super.key});

  @override
  State<HouseholdPage> createState() => _HouseholdPageState();
}

class _HouseholdPageState extends State<HouseholdPage> {
  final FLauncherChannel _channel = FLauncherChannel();
  Map<dynamic, dynamic> _status = const {};
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _refresh();
    _timer = Timer.periodic(const Duration(seconds: 3), (_) => _refresh());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _refresh() async {
    try {
      final status = await _channel.getHouseholdStatus();
      if (mounted) setState(() => _status = status);
    } catch (err) {
      noteFailure('household_page', err);
    }
  }

  /// A parent, then the action: the parent PIN where this TV has one.
  Future<bool> _allowed() async {
    if (!context.read<SettingsService>().hasParentPin) return true;
    final allowed = await requireParentPin(context);
    return allowed && mounted;
  }

  Future<void> _start() async {
    if (!await _allowed()) return;
    await _channel.createHousehold();
    await _refresh();
  }

  Future<void> _toggle(bool on) async {
    if (!on && !await _allowed()) return;
    await _channel.setHouseholdEnabled(on);
    await _refresh();
  }

  Future<void> _leave() async {
    if (!await _allowed()) return;
    await _channel.leaveHousehold();
    await _refresh();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final textTheme = Theme.of(context).textTheme;
    final joined = _status["joined"] == true;
    final lost = _status["lost"] == true;
    final enabled = _status["enabled"] != false;
    final peers = (_status["peers"] as List?)?.length ?? 0;
    final last = _status["lastResult"] as String?;
    Widget note(String text) =>
        Padding(padding: const EdgeInsets.fromLTRB(16, 4, 16, 12), child: Text(text, style: textTheme.bodySmall));
    return SettingsPage(
      title: l.householdTitle,
      children: [
        note(l.householdIntro),
        if (!joined) ...[
          note(lost ? l.householdLost : l.householdNone),
          if (!lost)
            FocusableSettingsTile(
              autofocus: true,
              leading: const Icon(Icons.add_home_outlined),
              title: Text(l.householdStart, style: textTheme.bodyMedium),
              onPressed: _start,
            ),
          note(l.householdAddHint),
        ] else ...[
          note(l.householdIn),
          FocusableSettingsTile(
            autofocus: true,
            leading: const Icon(Icons.sync),
            title: Text(l.householdSwitch, style: textTheme.bodyMedium),
            trailing: Icon(enabled ? Icons.check_box : Icons.check_box_outline_blank),
            onPressed: () => _toggle(!enabled),
          ),
          note(l.householdPeers(peers)),
          if (last != null && last.isNotEmpty) note(l.householdLast(last)),
          FocusableSettingsTile(
            leading: const Icon(Icons.sync_alt),
            title: Text(l.householdSyncNow, style: textTheme.bodyMedium),
            onPressed: enabled ? () => _channel.syncHouseholdNow() : null,
          ),
          FocusableSettingsTile(
            leading: const Icon(Icons.logout),
            title: Text(l.householdLeave, style: textTheme.bodyMedium),
            onPressed: _leave,
          ),
          note(l.householdAddHint),
        ],
      ],
    );
  }
}
