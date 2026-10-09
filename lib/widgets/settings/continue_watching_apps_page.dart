/*
 * FLauncher
 * Copyright (C) 2026 LeanBitLab
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

import 'package:flauncher/l10n/app_localizations.dart';
import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:flauncher/models/app.dart';
import 'package:flauncher/providers/apps_service.dart';
import 'package:flauncher/providers/settings_service.dart';
import 'package:flauncher/providers/watch_next_service.dart';
import 'package:flauncher/widgets/rounded_switch_list_tile.dart';
import 'app_icon.dart';
import 'blocked_apps_section.dart';
import 'settings_page.dart';

class ContinueWatchingAppsPage extends StatelessWidget {
  static const String routeName = "continue_watching_apps_panel";

  const ContinueWatchingAppsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final settingsService = context.watch<SettingsService>();
    final watchNextService = context.watch<WatchNextService>();
    final appsService = context.watch<AppsService>();

    final blockedPackages = settingsService.hiddenWatchNextPackages.toSet();

    final activePackages = watchNextService.programs.map((p) => p.packageName).toSet().toList();

    final allApps = List<App>.from(appsService.applications)
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

    final knownBlockedApps = allApps.where((a) => blockedPackages.contains(a.packageName)).toList();
    final knownBlockedPkg = knownBlockedApps.map((a) => a.packageName).toSet();
    final unknownBlockedPkg = blockedPackages.where((p) => !knownBlockedPkg.contains(p)).toList();

    return SettingsPage.custom(
      title: localizations.continueWatchingAppsTitle,
      // A long list: rows are built as they scroll into view
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        children: [
          BlockedAppsSection(
            title: localizations.cwAppsBlockedHeading(blockedPackages.length),
            apps: knownBlockedApps,
            missingPackages: unknownBlockedPkg,
            blockedLabel: localizations.cwAppsBlockedFromContinueWatching,
            unblockLabel: localizations.cwAppsUnblock,
            unblockAllLabel: localizations.cwAppsUnblockAllApps,
            appIcon: Icons.tv,
            emptyIcon: Icons.check_circle_outline,
            emptyTitle: localizations.cwAppsNoBlockedApps,
            emptyMessage: localizations.cwAppsNoBlockedAppsMessage,
            onUnblock: (pkg) => watchNextService.setPackageHidden(settingsService, pkg, false),
            onUnblockAll: () => watchNextService.unhideAll(settingsService),
          ),

          const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: Divider(),
          ),

          // --- APPS WITH CONTINUE WATCHING CONTENT ---
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  localizations.cwAppsWithContinueWatching,
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: theme.colorScheme.primary,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  localizations.cwAppsWithContinueWatchingHint,
                  style: const TextStyle(color: Colors.white54, fontSize: 11),
                ),
              ],
            ),
          ),

          if (activePackages.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.04),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.white12),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.info_outline, color: Colors.white60, size: 24),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        localizations.cwAppsNoActiveApps,
                        style: theme.textTheme.bodySmall?.copyWith(color: Colors.white60, height: 1.3),
                      ),
                    ),
                  ],
                ),
              ),
            )
          else
            ...activePackages.map((pkg) {
              final app = appsService.applications.firstWhereOrNull((a) => a.packageName == pkg);
              final appName = (app != null && app.name.isNotEmpty) ? app.name : pkg;
              final isBlocked = blockedPackages.contains(pkg);
              final count = watchNextService.programs.where((p) => p.packageName == pkg).length;

              return RoundedSwitchListTile(
                value: !isBlocked,
                onChanged: (allowed) => watchNextService.setPackageHidden(settingsService, pkg, !allowed),
                title: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(appName, style: theme.textTheme.bodyMedium),
                    const SizedBox(height: 2),
                    Text(
                      isBlocked
                          ? localizations.cwAppsBlockedFromContinueWatching
                          : localizations.cwAppsActiveItems(count),
                      style: TextStyle(
                        fontSize: 11,
                        color: isBlocked ? Colors.redAccent : Colors.white54,
                      ),
                    ),
                  ],
                ),
                secondary: AppIcon(pkg, size: 32, borderRadius: 6, placeholder: const Icon(Icons.tv, size: 32)),
              );
            }),

          const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: Divider(),
          ),

          // --- ALL INSTALLED APPLICATIONS ---
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  localizations.cwAppsAllInstalledApps,
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: theme.colorScheme.primary,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  localizations.cwAppsAllInstalledAppsHint,
                  style: const TextStyle(color: Colors.white54, fontSize: 11),
                ),
              ],
            ),
          ),

          ...allApps.map((app) {
            final isBlocked = blockedPackages.contains(app.packageName);

            return RoundedSwitchListTile(
              value: !isBlocked,
              onChanged: (allowed) => watchNextService.setPackageHidden(settingsService, app.packageName, !allowed),
              title: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(app.name, style: theme.textTheme.bodyMedium),
                  const SizedBox(height: 2),
                  Text(
                    isBlocked ? localizations.cwAppsBlocked : localizations.cwAppsAllowed,
                    style: TextStyle(
                      fontSize: 11,
                      color: isBlocked ? Colors.redAccent : Colors.white54,
                    ),
                  ),
                ],
              ),
              secondary: AppIcon(app.packageName, size: 32, borderRadius: 6, placeholder: const Icon(Icons.tv, size: 32)),
            );
          }),
        ],
      ),
    );
  }
}
