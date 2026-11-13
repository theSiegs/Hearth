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
import 'package:flauncher/l10n/app_localizations.dart';
import 'package:flauncher/models/screen_time_rules.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'focusable_settings_tile.dart';
import 'settings_choice_tile.dart';
import 'settings_page.dart';

/// The Screen time tile on a kid's page: opens their rules, or says Home Assistant sets them (one line, nothing to
/// edit here then: one editor at a time).
class ScreenTimeTile extends StatefulWidget {
  final String profileKey;
  final bool autofocus;

  const ScreenTimeTile({super.key, required this.profileKey, this.autofocus = false});

  @override
  State<ScreenTimeTile> createState() => _ScreenTimeTileState();
}

class _ScreenTimeTileState extends State<ScreenTimeTile> {
  late final FLauncherChannel? _channel = context.read<FLauncherChannel?>();
  ({String? rules, bool homeAssistant, int youtubeMinutes})? _state;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final state = await _channel?.getLocalRules(widget.profileKey);
      if (mounted) setState(() => _state = state);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final textTheme = Theme.of(context).textTheme;
    final state = _state;
    final ha = state?.homeAssistant ?? false;
    final set = state != null && (state.rules != null || state.youtubeMinutes > 0);
    return FocusableSettingsTile(
      autofocus: widget.autofocus,
      leading: const Icon(Icons.timer_outlined),
      title: Text(l.screenTimeTitle, style: textTheme.bodyMedium),
      trailing: Text(ha ? l.screenTimeInHomeAssistant : (set ? l.screenTimeSet : l.screenTimeNone),
          style: textTheme.bodySmall),
      onPressed: state == null || ha
          ? null
          : () async {
              await Navigator.of(context).pushNamed(ScreenTimeRulesPage.routeName, arguments: widget.profileKey);
              _load();
            },
    );
  }
}

/// A kid's own screen-time rules, for a TV without Home Assistant: minutes a day for All screen time, Games and YouTube
/// (weekdays and weekends), and a bedtime. Saved as each choice is made; the household's other TVs take them.
class ScreenTimeRulesPage extends StatefulWidget {
  static const String routeName = "screen_time_rules";

  final String profileKey;

  const ScreenTimeRulesPage({super.key, required this.profileKey});

  @override
  State<ScreenTimeRulesPage> createState() => _ScreenTimeRulesPageState();
}

class _ScreenTimeRulesPageState extends State<ScreenTimeRulesPage> {
  /// No limit, in the choice dialog (whose null is Back).
  static const int _noLimit = -1;
  static const List<int> _minuteOptions = [_noLimit, 0, 15, 30, 45, 60, 90, 120, 180, 240];
  static final List<String?> _bedtimeStarts = [null, for (var m = 19 * 60; m <= 23 * 60; m += 30) _hhmm(m)];
  static final List<String> _bedtimeEnds = [for (var m = 5 * 60 + 30; m <= 9 * 60; m += 30) _hhmm(m)];

  late final FLauncherChannel _channel = context.read<FLauncherChannel>();
  ScreenTimeRules? _rules;

  static String _hhmm(int minutes) =>
      "${(minutes ~/ 60).toString().padLeft(2, "0")}:${(minutes % 60).toString().padLeft(2, "0")}";

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final state = await _channel.getLocalRules(widget.profileKey);
    var rules = ScreenTimeRules.parse(state.rules);
    // The older YouTube limit (every day) starts the YouTube group, until the rules are saved
    if (state.rules == null && state.youtubeMinutes > 0 && mounted) {
      final name = AppLocalizations.of(context)!.screenTimeYouTube;
      rules = rules
          .withMinutes(ScreenTimeRules.youtube, state.youtubeMinutes, weekend: false, name: name)
          .withMinutes(ScreenTimeRules.youtube, state.youtubeMinutes, weekend: true, name: name);
    }
    if (mounted) setState(() => _rules = rules);
  }

  Future<void> _save(ScreenTimeRules rules) async {
    setState(() => _rules = rules);
    await _channel.setLocalRules(widget.profileKey, rules.toJson());
  }

  String _minutesLabel(AppLocalizations l, int? minutes) => minutes == null
      ? l.youTubeLimitNone
      : minutes == 0
          ? l.screenTimeNoneAllowed
          : l.youTubeLimitMinutes(minutes);

  String _timeLabel(String hhmm) {
    final parts = hhmm.split(":");
    return MaterialLocalizations.of(context).formatTimeOfDay(
        TimeOfDay(hour: int.parse(parts[0]), minute: int.parse(parts[1])),
        alwaysUse24HourFormat: MediaQuery.of(context).alwaysUse24HourFormat);
  }

  Future<void> _chooseMinutes(String group, String name, bool weekend) async {
    final l = AppLocalizations.of(context)!;
    final rules = _rules!;
    final current = rules.minutes(group, weekend: weekend) ?? _noLimit;
    final picked = await showChoiceDialog<int>(
      context,
      title: "$name · ${weekend ? l.screenTimeWeekends : l.screenTimeWeekdays}",
      options: _minuteOptions,
      isCurrent: (option) => option == current,
      label: (option) => _minutesLabel(l, option == _noLimit ? null : option),
      labelStyle: Theme.of(context).textTheme.bodyMedium,
    );
    if (picked == null || picked == current || !mounted) return;
    await _save(rules.withMinutes(group, picked == _noLimit ? null : picked, weekend: weekend, name: name));
  }

  Future<void> _chooseBedtimeStart() async {
    final l = AppLocalizations.of(context)!;
    final rules = _rules!;
    final bedtime = rules.bedtime;
    final picked = await showChoiceDialog<String>(
      context,
      title: l.bedtimeTitle,
      options: [for (final s in _bedtimeStarts) s ?? ""],
      isCurrent: (option) => option == (bedtime?.from ?? ""),
      label: (option) => option.isEmpty ? l.bedtimeOff : _timeLabel(option),
      labelStyle: Theme.of(context).textTheme.bodyMedium,
    );
    if (picked == null || !mounted) return;
    await _save(rules.withBedtime(picked.isEmpty
        ? null
        : (from: picked, to: bedtime?.to ?? "07:00", nights: bedtime?.nights ?? BedtimeNights.all)));
  }

  Future<void> _chooseBedtimeEnd() async {
    final l = AppLocalizations.of(context)!;
    final rules = _rules!;
    final bedtime = rules.bedtime!;
    final picked = await showChoiceDialog<String>(
      context,
      title: l.bedtimeUntil,
      options: _bedtimeEnds,
      isCurrent: (option) => option == bedtime.to,
      label: _timeLabel,
      labelStyle: Theme.of(context).textTheme.bodyMedium,
    );
    if (picked == null || !mounted) return;
    await _save(rules.withBedtime((from: bedtime.from, to: picked, nights: bedtime.nights)));
  }

  String _nightsLabel(AppLocalizations l, BedtimeNights nights) => switch (nights) {
        BedtimeNights.all => l.bedtimeNightsAll,
        BedtimeNights.weekdays => l.bedtimeNightsWeekdays,
        BedtimeNights.weekends => l.bedtimeNightsWeekends,
      };

  Future<void> _chooseNights() async {
    final l = AppLocalizations.of(context)!;
    final rules = _rules!;
    final bedtime = rules.bedtime!;
    final picked = await showChoiceDialog<BedtimeNights>(
      context,
      title: l.bedtimeNights,
      options: BedtimeNights.values,
      isCurrent: (option) => option == bedtime.nights,
      label: (option) => _nightsLabel(l, option),
      labelStyle: Theme.of(context).textTheme.bodyMedium,
    );
    if (picked == null || !mounted) return;
    await _save(rules.withBedtime((from: bedtime.from, to: bedtime.to, nights: picked)));
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final textTheme = Theme.of(context).textTheme;
    final rules = _rules;
    if (rules == null) {
      return SettingsPage(title: l.screenTimeTitle, children: const [Center(child: CircularProgressIndicator())]);
    }
    final small = textTheme.bodySmall?.copyWith(color: Colors.white54);
    Widget header(String text) => Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
          child: Text(text, style: textTheme.titleSmall),
        );
    List<Widget> group(String id, String name, {bool autofocus = false}) => [
          header(name),
          for (final weekend in [false, true])
            FocusableSettingsTile(
              autofocus: autofocus && !weekend,
              title: Text(weekend ? l.screenTimeWeekends : l.screenTimeWeekdays, style: textTheme.bodyMedium),
              trailing: Text(_minutesLabel(l, rules.minutes(id, weekend: weekend)), style: textTheme.bodySmall),
              onPressed: () => _chooseMinutes(id, name, weekend),
            ),
        ];
    final bedtime = rules.bedtime;
    return SettingsPage(
      title: l.screenTimeTitle,
      children: [
        Padding(padding: const EdgeInsets.fromLTRB(16, 0, 16, 8), child: Text(l.screenTimeHint, style: small)),
        ...group(ScreenTimeRules.all, l.screenTimeAll, autofocus: true),
        ...group(ScreenTimeRules.games, l.screenTimeGames),
        ...group(ScreenTimeRules.youtube, l.screenTimeYouTube),
        header(l.bedtimeTitle),
        FocusableSettingsTile(
          leading: const Icon(Icons.bedtime_outlined),
          title: Text(l.bedtimeTitle, style: textTheme.bodyMedium),
          trailing: Text(bedtime == null ? l.bedtimeOff : _timeLabel(bedtime.from), style: textTheme.bodySmall),
          onPressed: _chooseBedtimeStart,
        ),
        if (bedtime != null) ...[
          FocusableSettingsTile(
            title: Text(l.bedtimeUntil, style: textTheme.bodyMedium),
            trailing: Text(_timeLabel(bedtime.to), style: textTheme.bodySmall),
            onPressed: _chooseBedtimeEnd,
          ),
          FocusableSettingsTile(
            title: Text(l.bedtimeNights, style: textTheme.bodyMedium),
            trailing: Text(_nightsLabel(l, bedtime.nights), style: textTheme.bodySmall),
            onPressed: _chooseNights,
          ),
        ],
      ],
    );
  }
}
