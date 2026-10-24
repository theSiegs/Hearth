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
import 'share_pages.dart';

/// The other households [FLauncherChannel.getHouseholdStatus] heard on the network, each as its TVs' names.
List<List<String?>> householdsNearby(Map<dynamic, dynamic> status) => [
      for (final household in (status["nearby"] as List?) ?? const [])
        if (household is List && household.isNotEmpty) [for (final name in household) name is String ? name : null],
    ];

/// TVs' names for a sentence ("Kitchen, Office"); a TV that gave no name is "a Hearth TV".
String householdTvNames(AppLocalizations l, List<String?> names) {
  final named = names.whereType<String>().toSet().toList()..sort();
  final unnamed = names.length - names.whereType<String>().length;
  return [...named, if (unnamed > 0) l.householdUnnamedTvs(unnamed)].join(", ");
}

/// Settings > Profiles > Copy profiles between TVs > Household sync: whether this TV is in a household of TVs that keep
/// Profile Pairing and saved PINs in step, which TVs are in it, the one switch, and leaving. A TV in none sees a
/// household its other TVs have, to join. (Adding a TV is a copy: see ShareSendPage.)
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
    _channel.lookForHouseholds().catchError((Object err) => noteFailure('household_page', err));
    _refresh();
    _timer = Timer.periodic(const Duration(seconds: 3), (_) => _refresh());
  }

  @override
  void dispose() {
    _timer?.cancel();
    _channel.stopLookingForHouseholds().catchError((Object err) => noteFailure('household_page', err));
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

  /// Joining is a copy from one of the household's TVs: this TV's end of it.
  Future<void> _join() async {
    if (!await _allowed()) return;
    if (!mounted) return;
    await Navigator.of(context).pushNamed(ShareReceivePage.routeName);
    await _refresh();
  }

  /// Removes another TV, after asking (and the parent PIN where there is one).
  Future<void> _remove(AppLocalizations l, Map<dynamic, dynamic> member) async {
    final tvId = member["tvId"];
    if (tvId is! String) return;
    final name = (member["name"] as String?) ?? l.householdUnnamedTvs(1);
    final textTheme = Theme.of(context).textTheme;
    final go = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l.householdRemoveTitle(name)),
        content: SizedBox(width: 460, child: Text(l.householdRemoveBody, style: textTheme.bodyMedium)),
        actions: [
          // Keeping the TV is the safe choice, so it has the focus
          TextButton(autofocus: true, onPressed: () => Navigator.of(context).pop(false), child: Text(l.notNow)),
          TextButton(onPressed: () => Navigator.of(context).pop(true), child: Text(l.remove)),
        ],
      ),
    );
    if (go != true || !mounted || !await _allowed()) return;
    final removed = await _channel.removeHouseholdTv(tvId);
    if (!mounted) return;
    if (!removed) {
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(content: Text(l.householdRemoveFailed)));
    }
    await _refresh();
  }

  /// How a member is doing: this TV, on now, or when it was last on.
  String _memberStatus(AppLocalizations l, Map<dynamic, dynamic> member) {
    if (member["self"] == true) return l.householdThisTv;
    if (member["online"] == true) return l.householdOnNow;
    final at = (member["lastSeen"] as num?)?.toInt() ?? 0;
    if (at <= 0) return l.householdNotSeen;
    final then = DateTime.fromMillisecondsSinceEpoch(at);
    final now = DateTime.now();
    final days = DateTime(now.year, now.month, now.day).difference(DateTime(then.year, then.month, then.day)).inDays;
    return l.householdLastOn(days < 0 ? 0 : days);
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final textTheme = Theme.of(context).textTheme;
    final joined = _status["joined"] == true;
    final lost = _status["lost"] == true;
    final removed = _status["removed"] == true;
    final enabled = _status["enabled"] != false;
    final last = _status["lastResult"] as String?;
    final members = [for (final m in (_status["members"] as List?) ?? const []) if (m is Map) m];
    final nearby = householdsNearby(_status);
    Widget note(String text) =>
        Padding(padding: const EdgeInsets.fromLTRB(16, 4, 16, 12), child: Text(text, style: textTheme.bodySmall));
    return SettingsPage(
      title: l.householdTitle,
      children: [
        note(l.householdIntro),
        if (!joined && nearby.isNotEmpty) ...[
          // Another TV has a household: joining it comes first, so the TVs aren't split into two
          note(l.householdFound(householdTvNames(l, nearby.first))),
          FocusableSettingsTile(
            autofocus: true,
            leading: const Icon(Icons.login),
            title: Text(l.householdJoin, style: textTheme.bodyMedium),
            trailing: const Icon(Icons.chevron_right, color: Colors.white54),
            onPressed: _join,
          ),
          note(l.householdJoinHint),
          if (!lost)
            FocusableSettingsTile(
              leading: const Icon(Icons.add_home_outlined),
              title: Text(l.householdStartAnyway, style: textTheme.bodyMedium),
              onPressed: _start,
            ),
        ] else if (!joined) ...[
          note(lost ? l.householdLost : (removed ? l.householdRemoved : l.householdNone)),
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
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Text(l.householdMembers, style: textTheme.titleSmall),
          ),
          for (final member in members)
            FocusableSettingsTile(
              leading: Icon(Icons.tv, color: member["self"] == true || member["online"] == true ? null : Colors.white38),
              title: Text((member["name"] as String?) ?? l.householdUnnamedTvs(1), style: textTheme.bodyMedium),
              trailing: Text(_memberStatus(l, member), style: textTheme.bodySmall),
              onPressed: member["self"] == true ? null : () => _remove(l, member),
            ),
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
