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
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:flauncher/providers/apps_service.dart';
import 'package:flauncher/l10n/app_localizations.dart';
import 'focusable_settings_tile.dart';

/// TV & power: the screensaver, sleeping when idle, and Android's own settings.
class DisplaySettingsPage extends StatelessWidget {
  static const String routeName = "display_settings_panel";
  static const String title = "TV & power";

  const DisplaySettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    AppLocalizations localizations = AppLocalizations.of(context)!;

    return Column(
      children: [
        Text(title, style: Theme.of(context).textTheme.titleLarge),
        const Divider(),
        Expanded(
          child: SingleChildScrollView(
            child: Column(
              children: [
                FocusableSettingsTile(
                  autofocus: true,
                  leading: const Icon(Icons.screenshot_monitor),
                  title: Text("Screensaver (Google Photos)", style: Theme.of(context).textTheme.bodyMedium),
                  onPressed: () => _openScreensaverSettings(),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 4),
                  child: Text(
                    "Hearth uses Google TV's screensaver. Choose Google Photos (and which albums) or another source "
                    "there.",
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.white54),
                    textAlign: TextAlign.center,
                  ),
                ),
                const _IdleStandbyTile(),
                FocusableSettingsTile(
                  leading: const Icon(Icons.settings_outlined),
                  title: Text(localizations.systemSettings, style: Theme.of(context).textTheme.bodyMedium),
                  onPressed: () => context.read<AppsService>().openSettings(),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _openScreensaverSettings() async {
    const platform = MethodChannel('me.efesser.flauncher/method');
    platform.invokeMethod('openScreensaverSettings');
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
  int _minutes = 0;

  @override
  void initState() {
    super.initState();
    FLauncherChannel().getIdleStandbyMinutes().then((m) {
      if (mounted) setState(() => _minutes = m);
    }).catchError((_) {});
  }

  static String _label(int minutes) {
    if (minutes == 0) return "Off";
    if (minutes < 60) return "$minutes min";
    return minutes == 60 ? "1 hour" : "${minutes ~/ 60} hours";
  }

  Future<void> _choose() async {
    final int? picked = await showDialog<int>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text("Sleep when idle"),
        children: [
          for (final option in _options)
            SimpleDialogOption(
              child: Text(_label(option), style: Theme.of(context).textTheme.bodyMedium),
              onPressed: () => Navigator.of(context).pop(option),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 8, 24, 0),
            child: Text("Playing video or music counts as activity. Needs Home Button Fix (Settings > System > Setup & permissions).",
                style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.white54)),
          ),
        ],
      ),
    );
    if (picked == null) return;
    await FLauncherChannel().setIdleStandbyMinutes(picked);
    if (mounted) setState(() => _minutes = picked);
  }

  @override
  Widget build(BuildContext context) => FocusableSettingsTile(
        leading: const Icon(Icons.bedtime_outlined),
        title: Text("Sleep when idle", style: Theme.of(context).textTheme.bodyMedium),
        trailing: Text(_label(_minutes), style: Theme.of(context).textTheme.bodySmall),
        onPressed: _choose,
      );
}
