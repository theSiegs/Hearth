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
import 'package:flauncher/providers/setup_flow_service.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'focusable_settings_tile.dart';
import 'kid_profile_page.dart';
import 'settings_page.dart';

/// Settings > Profiles > Kids' profiles: whether Hearth (and HearthTube, when the owner has it) is on each kids'
/// profile, one Fix for any that got out of step, and taking Hearth off them before uninstalling it. The setup flow
/// puts Hearth there in the first place; after that Hearth puts itself on new kids' profiles too.
class KidsProfilesPage extends StatefulWidget {
  static const String routeName = "kids_profiles";

  /// How long Hearth's own adb may take, "Allow debugging?" included (as in the setup flow).
  static const Duration selfAdbLimit = Duration(minutes: 2);

  const KidsProfilesPage({super.key});

  /// One kids' profile in words: its name, how it stands in a word (with that word's colour), and what's on it or
  /// what's out of place.
  static ({String label, String status, String detail, Color? color}) describe(
      AppLocalizations l, KidsProfilesState state, KidProfile kid) {
    final name = kid.name;
    final label = name != null && name.isNotEmpty ? name : l.kidsProfilesUnnamed;
    final status = state.statusOf(kid);
    final detail = switch (status) {
      KidProfileStatus.ready => state.hearthTubeOnOwner ? l.kidsProfilesBothOn : l.kidsProfilesHearthOn,
      KidProfileStatus.hearthMissing => l.kidsProfilesHearthMissing,
      KidProfileStatus.notKept => l.kidsProfilesNotKept,
      KidProfileStatus.hearthTubeMissing => l.kidsProfilesHearthTubeMissing,
    };
    final ready = status == KidProfileStatus.ready;
    return (
      label: label,
      status: ready ? l.kidsProfilesReady : l.kidsProfilesNeedsFix,
      detail: detail,
      color: ready ? Colors.green : Colors.amber,
    );
  }

  @override
  State<KidsProfilesPage> createState() => _KidsProfilesPageState();
}

class _KidsProfilesPageState extends State<KidsProfilesPage> with WidgetsBindingObserver {
  late final FLauncherChannel _channel = context.read<FLauncherChannel>();
  KidsProfilesState? _state;

  /// The tile whose job is running (Hearth's own adb), whose row shows it; the others wait.
  _Job? _busy;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refresh();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refresh();
  }

  /// What Android lists first (quick, no adb), then whether the copies are kept, when the TV trusts Hearth's key.
  Future<void> _refresh() async {
    KidsProfilesState state;
    try {
      state = KidsProfilesState.fromMap(await _channel.getKidsProfilesState());
    } catch (_) {
      state = const KidsProfilesState();
    }
    if (!mounted) return;
    setState(() => _state = state);
    if (state.kids.isEmpty || !state.trusted || !state.adbEnabled) return;
    try {
      final checked = KidsProfilesState.fromMap(await _channel.getKidsProfilesState(checkProtection: true));
      if (mounted) setState(() => _state = checked);
    } catch (_) {}
  }

  Future<void> _fix() async {
    final l = AppLocalizations.of(context)!;
    final flow = context.read<SetupFlowService?>();
    bool adb = false;
    try {
      adb = await _channel.isAdbEnabled();
    } catch (_) {}
    if (!mounted) return;
    if (!adb) {
      await _askForDebugging();
      return;
    }
    final ok = await _run(_Job.fix, _channel.fixKidsProfiles);
    if (!mounted) return;
    if (!ok) {
      await _showMessage(l.kidsProfilesFailedTitle, [l.kidsProfilesFailedBody, l.kidsProfilesFailedRetry]);
      return;
    }
    // The setup flow's kids' step and its chip count the kids' profiles Hearth was put on
    final state = _state;
    if (state != null && state.allReady) await flow?.setKidsProtected(state.kids.length);
  }

  /// One kid's own page (their YouTube time, how Hearth stands there); Fix from there runs here.
  Future<void> _openKid(KidsProfilesState state, KidProfile kid) async {
    final result = await Navigator.of(context).pushNamed(KidProfilePage.routeName, arguments: (state, kid));
    if (!mounted) return;
    if (result == KidProfilePage.fix) {
      await _fix();
    } else {
      await _refresh();
    }
  }

  Future<void> _remove() async {
    final l = AppLocalizations.of(context)!;
    final go = await _confirm(title: l.kidsProfilesRemoveTitle, lines: [l.kidsProfilesRemoveBody], action: l.remove);
    if (go != true || !mounted) return;
    if (!await _run(_Job.remove, _channel.removeHearthFromKidsProfiles) && mounted) {
      await _showMessage(l.kidsProfilesFailedTitle, [l.kidsProfilesFailedBody, l.kidsProfilesFailedRetry]);
    }
  }

  /// Uninstall Hearth the safe way: take it off the kids' profiles first (so nothing is left behind there), then open
  /// Android's uninstall screen for Hearth itself. If that can't run yet, stop and ask for the approval rather than
  /// uninstall with copies left behind.
  Future<void> _uninstallHearth() async {
    final l = AppLocalizations.of(context)!;
    final go = await _confirm(
      title: l.kidsProfilesUninstallTitle,
      lines: [l.kidsProfilesUninstallBody, l.kidsProfilesUninstallWhyHere],
      action: l.uninstall,
    );
    if (go != true || !mounted) return;
    if (!await _run(_Job.uninstall, _channel.removeHearthFromKidsProfiles)) {
      if (mounted) {
        await _showMessage(l.kidsProfilesApprovalFirstTitle,
            [l.kidsProfilesApprovalFirstBody, l.kidsProfilesApprovalFirstRetry]);
      }
      return;
    }
    await _channel.uninstallHearth();
  }

  /// Runs one of Hearth's own adb jobs, then reads the profiles again. False when it couldn't run (most likely
  /// "Allow debugging?" wasn't allowed).
  Future<bool> _run(_Job which, Future<List<String>> Function() job) async {
    setState(() => _busy = which);
    bool ok;
    try {
      await job().timeout(KidsProfilesPage.selfAdbLimit);
      ok = true;
    } catch (_) {
      ok = false;
    }
    await _refresh();
    if (mounted) setState(() => _busy = null);
    return ok;
  }

  /// Hearth's own adb needs the TV's debugging switch: what to do, and the way to Android's About screen.
  Future<void> _askForDebugging() async {
    final l = AppLocalizations.of(context)!;
    final open = await _confirm(title: l.setupFlowDebugTitle, lines: [l.setupFlowDebugBody], action: l.setupFlowDebugOpen);
    if (open != true) return;
    try {
      await _channel.openDeviceInfoSettings();
    } catch (_) {}
  }

  Future<bool?> _confirm({required String title, required List<String> lines, required String action}) {
    final textTheme = Theme.of(context).textTheme;
    return showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: SizedBox(
          width: 460,
          // Longer languages can run past the screen's height
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final line in lines) ...[
                  Text(line, style: textTheme.bodyMedium),
                  const SizedBox(height: 10),
                ],
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(context).pop(false), child: Text(AppLocalizations.of(context)!.notNow)),
          TextButton(autofocus: true, onPressed: () => Navigator.of(context).pop(true), child: Text(action)),
        ],
      ),
    );
  }

  Future<void> _showMessage(String title, List<String> lines) {
    final textTheme = Theme.of(context).textTheme;
    return showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: SizedBox(
          width: 460,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final line in lines) ...[
                  Text(line, style: textTheme.bodyMedium),
                  const SizedBox(height: 10),
                ],
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
              autofocus: true,
              onPressed: () => Navigator.of(context).pop(),
              child: Text(AppLocalizations.of(context)!.ok)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final textTheme = Theme.of(context).textTheme;
    final state = _state;
    if (state == null) {
      return SettingsPage.custom(title: l.kidsProfilesTitle, body: const Center(child: CircularProgressIndicator()));
    }
    final needsFix = state.needingFix > 0;
    final note = !state.trusted
        ? l.kidsProfilesApproval
        : state.keep
            ? l.kidsProfilesAutoOn
            : null;
    return SettingsPage(
      title: l.kidsProfilesTitle,
      children: [
        if (state.kids.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
            child: Text(l.kidsProfilesNone, style: textTheme.bodySmall?.copyWith(color: Colors.white54)),
          ),
        // One row per kids' profile: its name, what's on it, and how it stands in a word
        for (final (index, kid) in state.kids.indexed)
          Builder(builder: (context) {
            final (:label, :status, :detail, :color) = KidsProfilesPage.describe(l, state, kid);
            return FocusableSettingsTile(
              autofocus: index == 0 && !needsFix,
              leading: const Icon(Icons.child_care),
              title: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(label, style: textTheme.bodyMedium),
                  Text(detail, style: textTheme.bodySmall?.copyWith(color: Colors.white54)),
                ],
              ),
              trailing: Text(status, style: textTheme.bodySmall?.copyWith(color: color)),
              onPressed: _busy != null ? null : () => _openKid(state, kid),
            );
          }),
        if (needsFix)
          FocusableSettingsTile(
            autofocus: true,
            leading: const Icon(Icons.build_outlined),
            title: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(l.kidsProfilesFix, style: textTheme.bodyMedium),
                Text(l.kidsProfilesFixBody, style: textTheme.bodySmall?.copyWith(color: Colors.white54)),
              ],
            ),
            trailing: _trailing(_Job.fix),
            onPressed: _busy != null ? null : _fix,
          ),
        if (note != null && state.kids.isNotEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
            child: Text(note, style: textTheme.bodySmall?.copyWith(color: Colors.white54)),
          ),
        const Divider(),
        FocusableSettingsTile(
          autofocus: state.kids.isEmpty,
          leading: const Icon(Icons.group_remove_outlined),
          title: Text(l.kidsProfilesRemoveTitle, style: textTheme.bodyMedium),
          trailing: _trailing(_Job.remove),
          onPressed: _busy != null ? null : _remove,
        ),
        FocusableSettingsTile(
          leading: const Icon(Icons.delete_outline),
          title: Text(l.kidsProfilesUninstallTitle, style: textTheme.bodyMedium),
          trailing: _trailing(_Job.uninstall),
          onPressed: _busy != null ? null : _uninstallHearth,
        ),
      ],
    );
  }

  /// A tile's end: a spinner while its job runs.
  Widget _trailing(_Job job) => _busy == job
      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
      : const Icon(Icons.chevron_right, color: Colors.white54);
}

enum _Job { fix, remove, uninstall }
