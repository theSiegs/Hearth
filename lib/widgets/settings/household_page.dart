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

/// Asks to join the household heard on the network, in a dialog that shows the code to check and follows the answer.
/// True when this TV joined.
Future<bool> joinNearbyHousehold(BuildContext context, FLauncherChannel channel) async {
  final joined = await showDialog<bool>(
      context: context, barrierDismissible: false, builder: (_) => _JoinDialog(channel: channel));
  return joined == true;
}

class _JoinDialog extends StatefulWidget {
  final FLauncherChannel channel;

  const _JoinDialog({required this.channel});

  @override
  State<_JoinDialog> createState() => _JoinDialogState();
}

class _JoinDialogState extends State<_JoinDialog> {
  String _state = "connecting";
  String? _code;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _begin();
  }

  Future<void> _begin() async {
    try {
      final started = await widget.channel.requestHouseholdJoin();
      if (!mounted) return;
      if (!started) {
        setState(() => _state = "failed");
        return;
      }
      _timer = Timer.periodic(const Duration(seconds: 1), (_) => _poll());
    } catch (err) {
      noteFailure('household_page', err);
      if (mounted) setState(() => _state = "failed");
    }
  }

  Future<void> _poll() async {
    try {
      final join = (await widget.channel.getHouseholdStatus())["join"];
      if (!mounted || join is! Map) return;
      final state = join["state"] as String? ?? "none";
      setState(() {
        _state = state;
        _code = join["code"] as String?;
      });
      if (state != "connecting" && state != "waiting") _timer?.cancel();
      if (state == "joined") Navigator.of(context).pop(true);
    } catch (err) {
      noteFailure('household_page', err);
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    // Closed while the request was under way (Back, or Cancel): it stops, so a later Allow can't join this TV
    _stopRequest();
    super.dispose();
  }

  void _stopRequest() {
    if (_state == "connecting" || _state == "waiting") {
      _state = "none";
      widget.channel.cancelHouseholdJoin().catchError((Object err) => noteFailure('household_page', err));
    }
  }

  void _cancel() {
    _stopRequest();
    Navigator.of(context).pop(false);
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final textTheme = Theme.of(context).textTheme;
    final waiting = _state == "waiting" && _code != null;
    final String title;
    final List<Widget> body;
    switch (_state) {
      case "denied":
        title = l.householdJoin;
        body = [Text(l.householdJoinDenied, style: textTheme.bodyMedium)];
      case "failed":
        title = l.householdJoin;
        body = [Text(l.householdJoinFailed, style: textTheme.bodyMedium)];
      default:
        title = waiting ? l.householdJoinWaitTitle : l.householdJoin;
        body = waiting
            ? [
                // The code is what the parent checks against the phone: large, alone on its line
                Text(_code!, style: textTheme.displaySmall),
                const SizedBox(height: 16),
                Text(l.householdJoinWaitBody, style: textTheme.bodyMedium),
              ]
            : [Text(l.householdJoinFinding, style: textTheme.bodyMedium)];
    }
    final over = _state == "denied" || _state == "failed";
    return AlertDialog(
      title: Text(title),
      content: SizedBox(
        width: 460,
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: body),
      ),
      actions: [
        TextButton(autofocus: true, onPressed: _cancel, child: Text(over ? l.close : l.cancel)),
      ],
    );
  }
}

/// Settings > Profiles > Household sync: whether this TV is in a household of TVs that keep every profile in step,
/// which TVs are in it, the one switch, and leaving. A TV in none sees a household its other TVs have, to join.
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

  /// Joining: this TV asks one of the household's, and a parent allows it on a phone or on that TV.
  Future<void> _join() async {
    await joinNearbyHousehold(context, _channel);
    await _refresh();
  }

  /// Another TV's request to join, answered here (allowing takes the parent PIN where this TV has one).
  Future<void> _answer(bool allow) async {
    if (allow && !await _allowed()) return;
    try {
      await _channel.answerHouseholdJoin(allow);
    } catch (err) {
      noteFailure('household_page', err);
    }
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
    final request = _status["joinRequest"];
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
          if (request is Map) ...[
            // Another TV is waiting on a parent's answer: it comes first, with the code to check
            note(l.householdJoinRequest(request["name"] as String? ?? l.householdUnnamedTvs(1), request["code"] as String? ?? "")),
            FocusableSettingsTile(
              autofocus: true,
              leading: const Icon(Icons.check),
              title: Text(l.householdJoinAllow, style: textTheme.bodyMedium),
              onPressed: () => _answer(true),
            ),
            FocusableSettingsTile(
              leading: const Icon(Icons.close),
              title: Text(l.householdJoinDeny, style: textTheme.bodyMedium),
              onPressed: () => _answer(false),
            ),
          ],
          note(l.householdIn),
          FocusableSettingsTile(
            autofocus: request is! Map,
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
