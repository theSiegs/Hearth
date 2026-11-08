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
import 'package:flauncher/models/ha_lock_state.dart';
import 'package:flauncher/quiet_failure.dart';
import 'package:flauncher/widgets/settings/hearth_dialog.dart';
import 'package:flutter/material.dart';

/// Why a kids profile can't open an app now, as the Hearth integration for Home Assistant says it: a family pause
/// (its reason, until when), a bedtime or school time, or a group's time up today; and, when time is up and nothing
/// else holds the kid, a way to ask an adult for more (15, 30, 45 or 60 minutes) with the answer as it comes.
///
/// Without Home Assistant it shows [fallback] (nothing when that's null too) and no button: Hearth works as before.
class TimeUpCard extends StatefulWidget {
  final FLauncherChannel channel;

  /// The group whose time is up for the app just held (its name), if that's why the card is up.
  final String? heldGroup;

  /// The app just held was held by a family pause.
  final bool heldByPause;

  /// What it says when Home Assistant says nothing (the home's "Nothing to watch right now").
  final String? fallback;

  /// What was read before the card opened, so the first frame is complete (and its focus decided).
  final HaLockState? initial;

  /// The first ask button takes the focus.
  final bool autofocus;

  /// How often it looks again (and, while a request waits, asks Home Assistant for a fresh answer).
  final Duration refreshEvery;

  /// The time now (tests).
  final DateTime Function() clock;

  const TimeUpCard({
    super.key,
    required this.channel,
    this.heldGroup,
    this.heldByPause = false,
    this.fallback,
    this.initial,
    this.autofocus = false,
    this.refreshEvery = const Duration(seconds: 20),
    this.clock = DateTime.now,
  });

  @override
  State<TimeUpCard> createState() => _TimeUpCardState();
}

class _TimeUpCardState extends State<TimeUpCard> {
  late HaLockState _state = widget.initial ?? HaLockState.none;
  Timer? _timer;

  /// The request this card just made, until the integration's answers carry it.
  HaRequest? _asked;

  /// The cooldown the integration answered with (429 cooldown), when it's later than the request says.
  DateTime? _cooldownUntil;

  /// What went wrong with the last ask (l10n'd when built).
  String? _error;
  bool _asking = false;

  @override
  void initState() {
    super.initState();
    FLauncherChannel.haStateVersion.addListener(_load);
    _timer = Timer.periodic(widget.refreshEvery, (_) => _tick());
    if (widget.initial == null) _load();
  }

  @override
  void dispose() {
    FLauncherChannel.haStateVersion.removeListener(_load);
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final state = await widget.channel.getHaLockState();
      if (mounted) setState(() => _state = state);
    } catch (err) {
      noteFailure('time_up_card', err);
    }
  }

  void _tick() {
    if (!mounted) return;
    // While a request waits, a fresh status answer brings its answer within seconds rather than minutes
    if (_request?.isWaitingAt(widget.clock()) ?? false) {
      unawaited(widget.channel.refreshHaStatus().catchError((err) => noteFailure('time_up_card', err)));
    }
    _load();
  }

  /// The latest request: the integration's, unless this card asked since and it doesn't know of that one yet.
  HaRequest? get _request {
    final known = _state.request;
    if (_asked == null || known?.id == _asked!.id) return known;
    return _asked;
  }

  Duration? _cooldownLeft(DateTime now) {
    final fromRequest = _request?.status == HaRequestStatus.denied
        ? HaLockState(request: _request).cooldownLeftAt(now)
        : null;
    final fromAnswer = _cooldownUntil?.difference(now);
    final left = [fromRequest, fromAnswer].whereType<Duration>().where((d) => d > Duration.zero);
    return left.isEmpty ? null : left.reduce((a, b) => a > b ? a : b);
  }

  Future<void> _ask(int minutes) async {
    if (_asking) return;
    setState(() {
      _asking = true;
      _error = null;
    });
    Map<dynamic, dynamic> answer;
    try {
      answer = await widget.channel.askForMoreTime(minutes, group: _state.askGroupFor(widget.heldGroup));
    } catch (err) {
      noteFailure('time_up_card', err);
      answer = {"ok": false, "error": "failed"};
    }
    if (!mounted) return;
    setState(() {
      _asking = false;
      final request = answer["request"];
      if (request is Map) _asked = HaRequest.fromMap(request);
      final error = answer["ok"] == true ? null : answer["error"] as String?;
      switch (error) {
        case null:
        case "already_open":
          break;
        case "cooldown":
          final retryIn = answer["retryIn"];
          _cooldownUntil = widget.clock().add(Duration(seconds: retryIn is int ? retryIn : 600));
        case "no_person":
          _error = "no_person";
        case "unreachable":
        case "not_paired":
          _error = "unreachable";
        default:
          _error = "failed";
      }
    });
  }

  String _time(BuildContext context, DateTime at) => MaterialLocalizations.of(context).formatTimeOfDay(
      TimeOfDay.fromDateTime(at),
      alwaysUse24HourFormat: MediaQuery.maybeAlwaysUse24HourFormatOf(context) ?? false);

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final now = widget.clock();
    final state = _state;

    IconData icon = Icons.nightlight_round;
    String? title;
    DateTime? until;
    if (state.paused || widget.heldByPause) {
      icon = Icons.pause_circle_outline;
      title = state.pauseReason != null ? l10n.timeUpPaused(state.pauseReason!) : l10n.timeUpPausedNoReason;
      until = state.pauseUntil;
    } else if (state.lockKind != null) {
      (icon, title) = switch (state.lockKind!) {
        HaLockKind.bedtime => (Icons.nightlight_round, l10n.timeUpBedtime),
        HaLockKind.schoolTime => (Icons.school_outlined, l10n.timeUpSchoolTime),
        HaLockKind.pause => (Icons.pause_circle_outline, l10n.timeUpPausedNoReason),
        HaLockKind.other => (Icons.lock_outline, l10n.timeUpLocked),
      };
      until = state.lockUntil;
    } else if (widget.heldGroup != null) {
      icon = Icons.hourglass_bottom;
      title = l10n.timeUpForGroup(widget.heldGroup!);
    } else if (state.timeUp.isNotEmpty) {
      icon = Icons.hourglass_bottom;
      title = l10n.timeUpForGroup(state.timeUp.map((g) => g.name).join(", "));
    } else {
      title = widget.fallback;
    }

    return Column(
      key: const Key("time_up_card"),
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: Colors.white70, size: 40),
        if (title != null) ...[
          const SizedBox(height: 12),
          Text(title,
              key: const Key("time_up_title"),
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white, fontSize: 24)),
        ],
        if (until != null) ...[
          const SizedBox(height: 6),
          Text(l10n.timeUpUntil(_time(context, until)),
              key: const Key("time_up_until"), style: const TextStyle(color: Colors.white70, fontSize: 16)),
        ],
        if (state.canAsk) ..._askSection(context, l10n, now),
      ],
    );
  }

  List<Widget> _askSection(BuildContext context, AppLocalizations l10n, DateTime now) {
    final request = _request;
    final waiting = request?.isWaitingAt(now) ?? false;
    final cooldown = _cooldownLeft(now);
    final String? status = switch (_error) {
      "no_person" => l10n.askNoPerson,
      "unreachable" => l10n.askUnreachable,
      "failed" => l10n.askFailed,
      _ => cooldown != null
          ? l10n.askCooldown(minutesRoundedUp(cooldown))
          : waiting
              ? l10n.askWaiting(request!.askedMinutes ?? request.minutes ?? 0)
              : request == null
                  ? null
                  : request.isExpiredAt(now)
                      ? l10n.askExpired
                      : switch (request.status) {
                          HaRequestStatus.approved => l10n.askApproved(request.minutes ?? 0),
                          HaRequestStatus.denied => l10n.askDenied,
                          _ => null,
                        },
    };
    final enabled = !waiting && cooldown == null && !_asking && _error != "no_person";
    return [
      const SizedBox(height: 20),
      Text(l10n.askForMoreTime, style: const TextStyle(color: Colors.white, fontSize: 16)),
      const SizedBox(height: 10),
      Wrap(
        spacing: 10,
        runSpacing: 10,
        alignment: WrapAlignment.center,
        children: [
          for (final (i, minutes) in HaLockState.askMinutes.indexed)
            Opacity(
              opacity: enabled ? 1 : 0.45,
              child: FocusableDialogButton(
                key: Key("ask_$minutes"),
                icon: Icons.more_time,
                label: l10n.askMinutes(minutes),
                compact: true,
                autofocus: widget.autofocus && i == 0,
                // Stays focusable while it can't ask, so the selection doesn't fall off the card
                onPressed: () {
                  if (enabled) _ask(minutes);
                },
              ),
            ),
        ],
      ),
      if (status != null) ...[
        const SizedBox(height: 12),
        Text(status,
            key: const Key("ask_status"),
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white70, fontSize: 15)),
      ],
    ];
  }
}

/// The time's up card over the home, after an app picked there was held ([group]: its group's name; null: a family
/// pause, unless [heldByPause] says otherwise: the Glint home opens it from its time tile with nothing held). Read
/// first, so the focus lands on the first ask button when the kid can ask, else on Close.
Future<void> showTimeUpDialog(BuildContext context, FLauncherChannel channel, String? group,
    {bool? heldByPause, String? fallback}) async {
  HaLockState state;
  try {
    state = await channel.getHaLockState();
  } catch (err) {
    noteFailure('time_up_card', err);
    state = HaLockState.none;
  }
  if (!context.mounted) return;
  await showDialog<void>(
    context: context,
    builder: (dialogContext) => HearthDialogFrame(
      width: 520,
      padding: const EdgeInsets.fromLTRB(28, 28, 28, 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TimeUpCard(
            channel: channel,
            heldGroup: group,
            // Nothing named and no pause: a lock (bedtime, School time) holds it, as the card then says
            heldByPause: heldByPause ?? (group == null && (state.paused || state.lockKind == null)),
            fallback: fallback,
            initial: state,
            autofocus: state.canAsk,
          ),
          const SizedBox(height: 20),
          FocusableDialogButton(
            key: const Key("time_up_close"),
            icon: Icons.close,
            label: AppLocalizations.of(dialogContext)!.close,
            autofocus: !state.canAsk,
            onPressed: () => Navigator.of(dialogContext).pop(),
          ),
        ],
      ),
    ),
  );
}
