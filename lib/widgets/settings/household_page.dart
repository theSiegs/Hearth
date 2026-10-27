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
import 'package:flauncher/share/household_join.dart';
import 'package:flauncher/widgets/held_focus.dart';
import 'package:flauncher/widgets/parent_pin_dialog.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
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

/// Asks to join the household heard on the network, in a dialog that shows the code to check and follows the answer,
/// then what joining changes on this TV before it does (docs/household-sync.md, "Before joining"). True when this TV
/// joined (its own settings may still be held, when someone chose Later).
Future<bool> joinNearbyHousehold(BuildContext context, FLauncherChannel channel) async {
  final joined = await showDialog<bool>(
      context: context, barrierDismissible: false, builder: (_) => _JoinDialog(channel: channel));
  return joined == true;
}

/// What joining changes, for a TV that joined and holds the household's settings (Finish joining). True when it went
/// on or chose Later; false when it left again.
Future<bool> reviewHouseholdJoin(BuildContext context, FLauncherChannel channel) async {
  final joined = await showDialog<bool>(
      context: context, barrierDismissible: false, builder: (_) => _JoinDialog(channel: channel, reviewOnly: true));
  return joined != false;
}

/// The join code as both TVs show it: six digits in two groups, "626 952" (the Bell's request shows it so too).
String joinCodeText(String code) {
  final digits = code.replaceAll(RegExp(r"\s"), "");
  return digits.length == 6 ? "${digits.substring(0, 3)} ${digits.substring(3)}" : code.trim();
}

/// One profile's line in what joining changes: "Alex: look, home layout, 1 saved PIN".
String joinChangeLine(AppLocalizations l, JoinChange change) {
  final parts = [
    if (change.look) l.householdReviewLook,
    if (change.layout) l.householdReviewLayout,
    if (change.pictures > 0) l.householdReviewPictures(change.pictures),
    if (change.pairings > 0) l.householdReviewPairings(change.pairings),
    if (change.pins > 0) l.householdReviewPins(change.pins),
  ];
  return l.householdReviewProfile(change.name.isEmpty ? change.key : change.name, parts.join(", "));
}

class _JoinDialog extends StatefulWidget {
  final FLauncherChannel channel;

  /// Already joined: only what changes is shown.
  final bool reviewOnly;

  const _JoinDialog({required this.channel, this.reviewOnly = false});

  @override
  State<_JoinDialog> createState() => _JoinDialogState();
}

class _JoinDialogState extends State<_JoinDialog> {
  /// After this many looks (one a second) without the household's settings, the dialog says they haven't come.
  static const int notYetAfter = 30;

  String _state = "connecting";
  String? _via;

  /// The six digits both TVs worked out ("123 456"), which the request in the other TV's Bell shows too.
  String? _code;
  Timer? _timer;

  // Once allowed: what joining changes
  late final HouseholdJoinReviewer? _reviewer = context.read<HouseholdJoinReviewer?>();
  int _looked = 0;
  bool _notYet = false;
  bool _checking = false;
  bool _busy = false;
  bool _copyFailed = false;
  JoinPreview? _preview;

  /// Where the remote's focus belongs: Later once allowed (the safe choice), Cancel (or Close) before.
  final FocusNode _laterFocus = FocusNode(debugLabel: "householdJoinLater");
  final FocusNode _cancelFocus = FocusNode(debugLabel: "householdJoinCancel");

  FocusNode get _homeFocus => _state == "review" ? _laterFocus : _cancelFocus;

  @override
  void initState() {
    super.initState();
    if (widget.reviewOnly) {
      _review();
    } else {
      _begin();
    }
  }

  /// Joined: the household's settings are held here until someone sees what they change.
  void _review() {
    _timer?.cancel();
    _state = "review";
    _looked = 0;
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => _pollReview());
    _pollReview();
  }

  Future<void> _pollReview() async {
    if (_checking || _preview != null) return;
    _checking = true;
    try {
      final review = (await widget.channel.getHouseholdStatus())["review"];
      if (!mounted) return;
      // Not holding anything (it was settled elsewhere): nothing to show
      if (review is! Map) {
        _timer?.cancel();
        Navigator.of(context).pop(true);
        return;
      }
      if (review["ready"] != true) {
        if (!_notYet && ++_looked > notYetAfter) setState(() => _notYet = true);
        return;
      }
      final preview = await _reviewer?.joinPreview();
      if (!mounted || preview == null) return;
      _timer?.cancel();
      if (preview.isEmpty) {
        await _use(preview);
      } else {
        setState(() => _preview = preview);
      }
    } catch (err) {
      noteFailure('household_page', err);
    } finally {
      _checking = false;
    }
  }

  /// Join and use these: a copy is kept, then the household's settings come in.
  Future<void> _use(JoinPreview preview) async {
    setState(() => _busy = true);
    final ok = _reviewer != null ? await _reviewer.finishJoin(preview) : await widget.channel.finishHouseholdJoin();
    if (!mounted) return;
    if (ok) {
      Navigator.of(context).pop(true);
    } else {
      setState(() {
        _busy = false;
        _copyFailed = true;
      });
    }
  }

  /// Don't join: this TV leaves again, nothing of it changed.
  Future<void> _dontJoin() async {
    _timer?.cancel();
    setState(() => _busy = true);
    try {
      await widget.channel.leaveHousehold();
    } catch (err) {
      noteFailure('household_page', err);
    }
    if (mounted) Navigator.of(context).pop(false);
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
      if (!mounted || join is! Map || _state == "review") return;
      final state = join["state"] as String? ?? "none";
      setState(() {
        _state = state;
        _via = join["via"] as String?;
        _code = join["code"] as String?;
      });
      if (state != "connecting" && state != "waiting") _timer?.cancel();
      if (state == "joined") _review();
    } catch (err) {
      noteFailure('household_page', err);
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    // Closed while the request was under way (Back, or Cancel): it stops, so a later Allow can't join this TV
    _stopRequest();
    _laterFocus.dispose();
    _cancelFocus.dispose();
    super.dispose();
  }

  /// Back: Later once allowed (the TV stays held, and Finish joining is offered), else Cancel.
  void _back() {
    if (_state != "review") {
      _cancel();
    } else if (!_busy) {
      Navigator.of(context).pop(true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _back();
      },
      child: HeldFocus(home: () => _homeFocus, child: _build(context)),
    );
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

  Widget _build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    if (_state == "review") return _buildReview(l, Theme.of(context).textTheme);
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
        final code = _code;
        // The code to compare: the adult checks it against the request in the Bell before choosing Allow
        if (waiting && code != null && code.isNotEmpty) {
          body.addAll([
            const SizedBox(height: 20),
            Text(l.householdJoinCode, style: textTheme.bodySmall?.copyWith(color: Colors.white70)),
            const SizedBox(height: 4),
            Text(joinCodeText(code),
                key: const ValueKey("householdJoinCode"),
                style: textTheme.displayMedium?.copyWith(
                    fontWeight: FontWeight.w600, letterSpacing: 6, fontFeatures: const [FontFeature.tabularFigures()])),
            const SizedBox(height: 8),
            Text(l.householdJoinCodeHint, style: textTheme.bodySmall?.copyWith(color: Colors.white70)),
          ]);
        }
    }
    final over = _state == "denied" || _state == "failed";
    return AlertDialog(
      title: Text(title),
      content: SizedBox(
        width: 460,
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: body),
      ),
      actions: [
        TextButton(
            focusNode: _cancelFocus, autofocus: true, onPressed: _cancel, child: Text(over ? l.close : l.cancel)),
      ],
    );
  }

  /// What joining changes here, or waiting for the household's settings to come.
  Widget _buildReview(AppLocalizations l, TextTheme textTheme) {
    final preview = _preview;
    final body = <Widget>[];
    if (preview == null) {
      body.add(Row(children: [
        const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
        const SizedBox(width: 16),
        Expanded(child: Text(l.householdReviewWaiting, style: textTheme.bodyMedium)),
      ]));
      if (_notYet) {
        body.addAll([const SizedBox(height: 12), Text(l.householdReviewNotYet, style: textTheme.bodySmall)]);
      }
    } else {
      body.addAll([
        Text(l.householdReviewChanges, style: textTheme.bodyMedium),
        const SizedBox(height: 8),
        for (final change in preview.changed)
          Padding(
            padding: const EdgeInsets.only(left: 12, bottom: 4),
            child: Text(joinChangeLine(l, change), style: textTheme.bodyMedium),
          ),
        if (preview.parentPin)
          Padding(
            padding: const EdgeInsets.only(left: 12, bottom: 4),
            child: Text(l.householdReviewParentPin, style: textTheme.bodyMedium),
          ),
        if (preview.tvPins > 0)
          Padding(
            padding: const EdgeInsets.only(left: 12, bottom: 4),
            child: Text(l.householdReviewTvPins(preview.tvPins), style: textTheme.bodyMedium),
          ),
        const SizedBox(height: 12),
        Text(l.householdReviewKept, style: textTheme.bodySmall?.copyWith(color: Colors.white54)),
      ]);
    }
    if (_copyFailed) {
      body.addAll([const SizedBox(height: 12), Text(l.householdReviewFailed, style: textTheme.bodySmall)]);
    }
    return AlertDialog(
      title: Text(l.householdReviewTitle),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: body),
        ),
      ),
      actions: [
        TextButton(onPressed: _busy ? null : _dontJoin, child: Text(l.householdReviewCancel)),
        // Later is the safe choice: nothing changes here, and the page offers Finish joining
        TextButton(
          focusNode: _laterFocus,
          autofocus: true,
          onPressed: _busy ? null : () => Navigator.of(context).pop(true),
          child: Text(l.householdReviewLater),
        ),
        if (preview != null)
          TextButton(
            onPressed: _busy ? null : () => _use(preview),
            child: Text(l.householdReviewUse),
          ),
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

  /// Joined, and the household's settings held: what they change, then going on (or leaving again).
  Future<void> _finishJoining() async {
    await reviewHouseholdJoin(context, _channel);
    await _refresh();
  }

  /// This TV's settings from before it joined come back (with the parent PIN where there is one).
  Future<void> _restore() async {
    final l = AppLocalizations.of(context)!;
    final textTheme = Theme.of(context).textTheme;
    final reviewer = context.read<HouseholdJoinReviewer?>();
    final go = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l.householdRestore),
        content: SizedBox(width: 460, child: Text(l.householdRestoreBody, style: textTheme.bodyMedium)),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(true), child: Text(l.householdRestoreConfirm)),
          TextButton(autofocus: true, onPressed: () => Navigator.of(context).pop(false), child: Text(l.cancel)),
        ],
      ),
    );
    if (go != true || !mounted || !await _allowed()) return;
    var done = false;
    try {
      done = reviewer != null ? await reviewer.restoreJoinBackup() : await _channel.restoreHouseholdJoinBackup();
    } catch (err) {
      noteFailure('household_page', err);
    }
    if (!mounted) return;
    ScaffoldMessenger.maybeOf(context)
        ?.showSnackBar(SnackBar(content: Text(done ? l.householdRestoreDone : l.householdRestoreFailed)));
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
    final reviewing = _status["review"] is Map;
    final backupAt = (_status["joinBackupAt"] as num?)?.toInt() ?? 0;
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
          // Joined, and still holding the household's settings until someone sees what they change
          if (reviewing)
            FocusableSettingsTile(
              autofocus: true,
              leading: const Icon(Icons.fact_check_outlined, color: Colors.amber),
              title: twoLines(l.householdReviewPending, l.householdReviewPendingHint),
              trailing: const Icon(Icons.chevron_right, color: Colors.white54),
              onPressed: _finishJoining,
            ),
          // The household's TVs first: this one, then the others, those on now first
          heading(l.householdMembers),
          for (final member in members)
            FocusableSettingsTile(
              autofocus: !reviewing && member == (others.isNotEmpty ? others.first : null),
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
            autofocus: !reviewing && others.isEmpty,
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
          // The copy of this TV's settings from before it joined, while it's kept
          if (backupAt > 0)
            FocusableSettingsTile(
              leading: const Icon(Icons.settings_backup_restore),
              title: twoLines(
                  l.householdRestore,
                  l.householdRestoreHint(DateFormat.yMMMd(Localizations.localeOf(context).toString()).format(
                      DateTime.fromMillisecondsSinceEpoch(backupAt).add(HouseholdJoinReviewer.keptFor)))),
              onPressed: _restore,
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
