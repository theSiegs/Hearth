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
  String? _via;
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
        _via = join["via"] as String?;
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
    final waiting = _state == "waiting";
    final via = _via != null && _via!.isNotEmpty ? _via! : l.householdJoinViaAny;
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
        title = waiting ? l.householdJoinWaitTitle(via) : l.householdJoin;
        body = [Text(waiting ? l.householdJoinWaitBody(via) : l.householdJoinFinding, style: textTheme.bodyMedium)];
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

/// Settings > Family > Household sync: whether this TV is in a household of TVs that keep every profile in step,
/// which TVs are in it (first, each with a card to remove it), the one switch, and leaving. A TV in none sees the
/// household its other TVs have, and its TVs, to join.
class HouseholdPage extends StatefulWidget {
  static const String routeName = "household";

  const HouseholdPage({super.key});

  @override
  State<HouseholdPage> createState() => _HouseholdPageState();
}

class _HouseholdPageState extends State<HouseholdPage> {
  late final FLauncherChannel _channel = context.read<FLauncherChannel?>() ?? FLauncherChannel();
  Map<dynamic, dynamic> _status = const {};
  Timer? _timer;

  /// How long a TV in no household listens for one before offering to start its own, so Start isn't offered while
  /// the other TVs are still answering.
  static const Duration lookFor = Duration(seconds: 6);

  /// Still listening: no household heard yet, and [lookFor] not over.
  bool _looking = true;

  @override
  void initState() {
    super.initState();
    _channel.lookForHouseholds().catchError((Object err) => noteFailure('household_page', err));
    _refresh();
    // Every second while listening, so a household heard shows at once; every 3 after
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => _refresh());
    Future.delayed(lookFor, () {
      if (!mounted) return;
      _timer?.cancel();
      _timer = Timer.periodic(const Duration(seconds: 3), (_) => _refresh());
      setState(() => _looking = false);
    });
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

  /// Another TV's card: how it's doing, and taking it out of the household (with the parent PIN where there is one).
  Future<void> _openMember(AppLocalizations l, Map<dynamic, dynamic> member) async {
    final tvId = member["tvId"];
    if (tvId is! String) return;
    final name = (member["name"] as String?) ?? l.householdUnnamedTvs(1);
    final textTheme = Theme.of(context).textTheme;
    final remove = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(name),
        content: SizedBox(
          width: 460,
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(memberStatus(l, member), style: textTheme.bodyMedium),
            const SizedBox(height: 12),
            Text(l.householdRemoveBody, style: textTheme.bodySmall?.copyWith(color: Colors.white54)),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(true), child: Text(l.householdRemoveTv)),
          // Keeping the TV is the safe choice, so Close has the focus
          TextButton(autofocus: true, onPressed: () => Navigator.of(context).pop(false), child: Text(l.close)),
        ],
      ),
    );
    if (remove != true || !mounted || !await _allowed()) return;
    final removed = await _channel.removeHouseholdTv(tvId);
    if (!mounted) return;
    if (!removed) {
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(content: Text(l.householdRemoveFailed)));
    }
    await _refresh();
  }

  /// How a member is doing: this TV, on now, or when it was last on.
  static String memberStatus(AppLocalizations l, Map<dynamic, dynamic> member) {
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
    final asking = _status["asking"] as String?;
    final members = [for (final m in (_status["members"] as List?) ?? const []) if (m is Map) m];
    final others = members.where((m) => m["self"] != true).toList();
    final nearby = householdsNearby(_status);
    Widget note(String text) =>
        Padding(padding: const EdgeInsets.fromLTRB(16, 4, 16, 12), child: Text(text, style: textTheme.bodySmall));
    Widget heading(String text) =>
        Padding(padding: const EdgeInsets.fromLTRB(16, 12, 16, 4), child: Text(text, style: textTheme.titleSmall));
    // A TV shown but not chosen: the found household's, for knowing what joining means
    Widget tvRow(String name) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 26),
          child: Row(children: [
            const Icon(Icons.tv, size: 20, color: Colors.white54),
            const SizedBox(width: 16),
            Text(name, style: textTheme.bodyMedium),
          ]),
        );
    Widget twoLines(String title, String detail) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(title, style: textTheme.bodyMedium),
            Text(detail, style: textTheme.bodySmall?.copyWith(color: Colors.white54)),
          ],
        );
    return SettingsPage(
      title: l.householdTitle,
      children: [
        if (_status.isEmpty || (!joined && nearby.isEmpty && _looking)) ...[
          note(l.householdIntro),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: Row(children: [
              const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
              const SizedBox(width: 16),
              Text(l.householdLooking, style: textTheme.bodyMedium),
            ]),
          ),
        ] else if (!joined && nearby.isNotEmpty) ...[
          // Another TV has a household: joining it comes first, so the TVs aren't split into two
          note(l.householdFound),
          heading(l.householdNearby),
          for (final name in nearby.first) tvRow(name ?? l.householdUnnamedTvs(1)),
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
          note(l.householdIntro),
        ] else if (!joined) ...[
          note(l.householdIntro),
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
          // The household's TVs first: this one, then the others, those on now first
          heading(l.householdMembers),
          for (final member in members)
            FocusableSettingsTile(
              autofocus: member == (others.isNotEmpty ? others.first : null),
              leading: Icon(Icons.tv, color: member["self"] == true || member["online"] == true ? null : Colors.white38),
              title: Text((member["name"] as String?) ?? l.householdUnnamedTvs(1), style: textTheme.bodyMedium),
              trailing: Text(memberStatus(l, member), style: textTheme.bodySmall),
              onPressed: member["self"] == true ? null : () => _openMember(l, member),
            ),
          // A TV waiting to be let in, answered only from the Bell
          if (asking != null && asking.isNotEmpty)
            FocusableSettingsTile(
              leading: const Icon(Icons.tv, color: Colors.amber),
              title: twoLines(asking, l.householdAskingHint),
              trailing: Text(l.householdAsking, style: textTheme.bodySmall?.copyWith(color: Colors.amber)),
            ),
          const SizedBox(height: 8),
          FocusableSettingsTile(
            autofocus: others.isEmpty,
            leading: const Icon(Icons.sync),
            title: last != null && last.isNotEmpty
                ? twoLines(l.householdSwitch, l.householdLast(last))
                : Text(l.householdSwitch, style: textTheme.bodyMedium),
            trailing: Icon(enabled ? Icons.check_box : Icons.check_box_outline_blank),
            onPressed: () => _toggle(!enabled),
          ),
          FocusableSettingsTile(
            leading: const Icon(Icons.sync_alt),
            title: Text(l.householdSyncNow, style: textTheme.bodyMedium),
            onPressed: enabled ? () => _channel.syncHouseholdNow() : null,
          ),
          const Divider(),
          note(l.householdAddHint),
          FocusableSettingsTile(
            leading: const Icon(Icons.logout),
            title: Text(l.householdLeave, style: textTheme.bodyMedium),
            onPressed: _leave,
          ),
          note(l.householdIntro),
        ],
      ],
    );
  }
}
