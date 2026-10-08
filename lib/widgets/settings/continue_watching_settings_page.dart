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

import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';

import 'package:flauncher/l10n/app_localizations.dart';
import 'package:flauncher/providers/settings_service.dart';
import 'package:flauncher/providers/watch_next_service.dart';
import 'package:flauncher/widgets/rounded_switch_list_tile.dart';
import 'adb_command_dialog.dart';
import 'continue_watching_apps_page.dart';
import 'continue_watching_card_size_page.dart';
import 'continue_watching_max_items_page.dart';
import 'focusable_settings_tile.dart';
import 'settings_page.dart';

class ContinueWatchingSettingsPage extends StatefulWidget {
  static const String routeName = "continue_watching_settings_panel";

  const ContinueWatchingSettingsPage({super.key});

  @override
  State<ContinueWatchingSettingsPage> createState() => _ContinueWatchingSettingsPageState();
}

class _ContinueWatchingSettingsPageState extends State<ContinueWatchingSettingsPage> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && mounted) {
      context.read<WatchNextService>().refresh();
    }
  }

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context)!;
    final settingsService = context.watch<SettingsService>();
    final watchNextService = context.watch<WatchNextService>();

    final cardHeight = settingsService.continueWatchingCardHeight;
    // The heights of the sizes that had names before a height could be picked
    final sizeName = const {112: 'Compact', 135: 'Standard', 157: 'Large'}[cardHeight];
    final sizeLabel = sizeName == null ? '$cardHeight dp' : '$cardHeight dp ($sizeName)';

    final maxItems = settingsService.continueWatchingMaxItems;
    final maxItemsLabel = maxItems <= 0 ? 'Unlimited' : '$maxItems items';

    final blockedCount = settingsService.hiddenWatchNextPackages.length;
    final hiddenProgramsCount = settingsService.hiddenWatchNextProgramIds.length;

    return SettingsPage(
      title: localizations.continueWatching,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      children: [
        RoundedSwitchListTile(
          autofocus: true,
          value: settingsService.showContinueWatching,
          onChanged: (value) async {
            if (value) {
              final hasPermission = await watchNextService.checkPermission();
              if (!context.mounted) return;
              if (!hasPermission) {
                final granted = await watchNextService.requestPermission();
                if (!context.mounted) return;
                if (!granted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(localizations.permissionDeniedContinueWatching),
                      duration: const Duration(seconds: 3),
                    ),
                  );
                }
              }
            }
            settingsService.setShowContinueWatching(value);
          },
          title: Text(localizations.showContinueWatchingOnHome, style: Theme.of(context).textTheme.bodyMedium),
          subtitle: Text(localizations.continueWatchingDescription),
          secondary: const Icon(Icons.play_circle_outline),
        ),
        if (settingsService.showContinueWatching) ...[
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 4),
            child: Divider(),
          ),
          FocusableSettingsTile(
            leading: const Icon(Icons.aspect_ratio_outlined),
            title: Text('Card Size', style: Theme.of(context).textTheme.bodyMedium),
            trailing: Text(
              sizeLabel,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.white70),
            ),
            onPressed: () => Navigator.of(context).pushNamed(ContinueWatchingCardSizePage.routeName),
          ),
          FocusableSettingsTile(
            leading: const Icon(Icons.format_list_numbered_outlined),
            title: Text('Maximum Items', style: Theme.of(context).textTheme.bodyMedium),
            trailing: Text(
              maxItemsLabel,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.white70),
            ),
            onPressed: () => Navigator.of(context).pushNamed(ContinueWatchingMaxItemsPage.routeName),
          ),
          RoundedSwitchListTile(
            value: settingsService.continueWatchingShowProgress,
            onChanged: (v) => settingsService.setContinueWatchingShowProgress(v),
            title: Text('Playback Progress Bar', style: Theme.of(context).textTheme.bodyMedium),
            secondary: const Icon(Icons.linear_scale_outlined),
          ),
          RoundedSwitchListTile(
            value: settingsService.continueWatchingShowPercentage,
            onChanged: (v) => settingsService.setContinueWatchingShowPercentage(v),
            title: Text('Playback Percentage', style: Theme.of(context).textTheme.bodyMedium),
            secondary: const Icon(Icons.percent_outlined),
          ),
          RoundedSwitchListTile(
            value: settingsService.continueWatchingShowDescription,
            onChanged: (v) => settingsService.setContinueWatchingShowDescription(v),
            title: Text('Episode & Video Details', style: Theme.of(context).textTheme.bodyMedium),
            secondary: const Icon(Icons.subtitles_outlined),
          ),
          FocusableSettingsTile(
            leading: const Icon(Icons.apps_outlined),
            title: Text('Apps with Continue Watching', style: Theme.of(context).textTheme.bodyMedium),
            trailing: Text(
              blockedCount > 0 ? '$blockedCount blocked' : 'Manage',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: blockedCount > 0 ? Colors.orange : Colors.grey,
                  ),
            ),
            onPressed: () => Navigator.of(context).pushNamed(ContinueWatchingAppsPage.routeName),
          ),
          if (hiddenProgramsCount > 0)
            FocusableSettingsTile(
              leading: const Icon(Icons.restore, color: Colors.orangeAccent),
              title: Text(
                'Restore Hidden Programs',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Colors.orangeAccent),
              ),
              trailing: Text(
                '$hiddenProgramsCount hidden',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.orangeAccent),
              ),
              onPressed: () async {
                await settingsService.clearHiddenWatchNextPrograms();
                await watchNextService.refresh();
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('All hidden programs restored')),
                  );
                }
              },
            ),
        ],
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 4),
          child: Divider(),
        ),
        FocusableSettingsTile(
          leading: const Icon(Icons.security),
          title: Text(
            localizations.notificationAccess.replaceAll('Notification', 'Watch Next'),
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          trailing: Text(
            watchNextService.hasPermission ? localizations.granted : localizations.permissionRequired,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: watchNextService.hasPermission ? Colors.green : Colors.orange,
                  fontWeight: FontWeight.bold,
                ),
          ),
          onPressed: () async {
            final has = await watchNextService.checkPermission();
            if (!has && context.mounted) {
              final granted = await watchNextService.requestPermission();
              if (!granted && context.mounted) {
                _showWatchNextPermissionGuide(context);
              }
            }
          },
        ),
      ],
    );
  }

  Future<void> _showWatchNextPermissionGuide(BuildContext context) async {
    final packageInfo = await PackageInfo.fromPlatform();
    final packageName = packageInfo.packageName;
    if (!context.mounted) return;

    showAdbCommandDialog(
      context,
      title: 'Watch Next Access (ADB Required)',
      message:
          'Android TV requires the READ_WRITE_WATCH_NEXT_PROGRAMS permission for launchers to read and display Continue Watching rows from installed apps.\n\n'
          'To grant this permission, connect your TV via ADB and run:',
      command: 'adb shell pm grant $packageName com.android.providers.tv.permission.READ_WRITE_WATCH_NEXT_PROGRAMS',
    );
  }
}
