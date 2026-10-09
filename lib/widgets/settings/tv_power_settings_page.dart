/*
 * FLauncher
 * Copyright (C) 2024 LeanBitLab
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
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flauncher/providers/apps_service.dart';
import 'package:flauncher/l10n/app_localizations.dart';
import 'focusable_settings_tile.dart';
import 'remote_search_settings_page.dart';
import 'setup_checklist_page.dart';
import 'settings_page.dart';

/// TV & power: the screensaver, sleeping when idle, and Android's own settings.
class TvPowerSettingsPage extends StatelessWidget {
  static const String routeName = "display_settings_panel";

  const TvPowerSettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    AppLocalizations localizations = AppLocalizations.of(context)!;

    return SettingsPage(
      title: localizations.tvPowerTitle,
      children: [
        FocusableSettingsTile(
          autofocus: true,
          leading: const Icon(Icons.screenshot_monitor),
          title: Text(localizations.tvPowerScreensaver, style: Theme.of(context).textTheme.bodyMedium),
          onPressed: () => context.read<FLauncherChannel>().openScreensaverSettings(),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 4),
          child: Text(
            localizations.tvPowerScreensaverNote,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.white54),
            textAlign: TextAlign.center,
          ),
        ),
        const _IdleStandbyTile(),
        // The remote: its buttons and what Back does on the home
        FocusableSettingsTile(
          leading: const Icon(Icons.settings_remote_outlined),
          title: Text(localizations.remoteAndSearchTitle, style: Theme.of(context).textTheme.bodyMedium),
          trailing: const Icon(Icons.chevron_right, color: Colors.white54),
          onPressed: () => Navigator.of(context).pushNamed(RemoteSearchSettingsPage.routeName),
        ),
        FocusableSettingsTile(
          leading: const Icon(Icons.settings_outlined),
          title: Text(localizations.systemSettings, style: Theme.of(context).textTheme.bodyMedium),
          onPressed: () => context.read<AppsService>().openSettings(),
        ),
      ],
    );
  }
}

/// Sleep after a stretch with no remote presses. Playback counts as activity; needs Home Button Fix (the
/// accessibility service) to see button presses.
class _IdleStandbyTile extends StatefulWidget {
  const _IdleStandbyTile();

  @override
  State<_IdleStandbyTile> createState() => _IdleStandbyTileState();
}

class _IdleStandbyTileState extends State<_IdleStandbyTile> {
  static const List<int> _options = [0, 15, 30, 60, 120, 240];
  late final FLauncherChannel _channel = context.read<FLauncherChannel>();
  int _minutes = 0;

  @override
  void initState() {
    super.initState();
    _channel.getIdleStandbyMinutes().then((m) {
      if (mounted) setState(() => _minutes = m);
    }).catchError((_) {});
  }

  static String _label(AppLocalizations l, int minutes) {
    if (minutes == 0) return l.tvPowerSleepOff;
    if (minutes < 60) return l.tvPowerMinutes(minutes);
    return l.tvPowerHours(minutes ~/ 60);
  }

  Future<void> _choose() async {
    final l = AppLocalizations.of(context)!;
    final int? picked = await showDialog<int>(
      context: context,
      builder: (context) => SimpleDialog(
        title: Text(l.tvPowerSleepWhenIdle),
        children: [
          // The current value is marked and selected as the dialog opens
          for (final option in _options)
            SimpleDialogOption(
              child: TextButton(
                autofocus: option == _minutes,
                onPressed: () => Navigator.of(context).pop(option),
                child: Row(
                  children: [
                    Icon(option == _minutes ? Icons.radio_button_checked : Icons.radio_button_unchecked, size: 20),
                    const SizedBox(width: 12),
                    Flexible(child: Text(_label(l, option), style: Theme.of(context).textTheme.bodyMedium)),
                  ],
                ),
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 8, 24, 0),
            child: Text(l.tvPowerSleepNote(SetupChecklistPage.breadcrumb(l)),
                style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.white54)),
          ),
        ],
      ),
    );
    if (picked == null) return;
    await _channel.setIdleStandbyMinutes(picked);
    if (mounted) setState(() => _minutes = picked);
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    return FocusableSettingsTile(
      leading: const Icon(Icons.bedtime_outlined),
      title: Text(l.tvPowerSleepWhenIdle, style: Theme.of(context).textTheme.bodyMedium),
      trailing: Text(_label(l, _minutes), style: Theme.of(context).textTheme.bodySmall),
      onPressed: _choose,
    );
  }
}
