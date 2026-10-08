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
import 'package:flauncher/models/app.dart';
import 'package:flauncher/providers/apps_service.dart';
import 'package:flauncher/providers/notifications_service.dart';
import 'package:flauncher/widgets/rounded_switch_list_tile.dart';
import 'package:flauncher/widgets/settings/app_icon.dart';
import 'package:flauncher/widgets/settings/blocked_apps_section.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class BlockedNotificationsPage extends StatelessWidget {
  static const String routeName = "blocked_notifications_panel";

  const BlockedNotificationsPage({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final localizations = AppLocalizations.of(context)!;

    return Consumer2<NotificationsService, AppsService>(
      builder: (context, notificationsService, appsService, _) {
        final blockedPackages = notificationsService.blockedPackages;
        final allApps = List<App>.from(appsService.applications)
          ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

        final blockedApps = allApps.where((a) => blockedPackages.contains(a.packageName)).toList();
        final knownBlockedPkg = blockedApps.map((a) => a.packageName).toSet();
        final unknownBlockedPkg = blockedPackages.where((p) => !knownBlockedPkg.contains(p)).toList();

        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 12.0),
              child: Row(
                children: [
                  Text(
                    localizations.blockedNotificationApps,
                    style: theme.textTheme.titleLarge,
                  ),
                ],
              ),
            ),
            const Divider(),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                children: [
                  BlockedAppsSection(
                    title: "${localizations.blockedNotificationApps} (${blockedPackages.length})",
                    apps: blockedApps,
                    missingPackages: unknownBlockedPkg,
                    blockedLabel: localizations.notificationsBlocked,
                    unblockLabel: localizations.unblockAppNotifications,
                    unblockAllLabel: localizations.unblockAll,
                    appIcon: Icons.android,
                    emptyIcon: Icons.notifications_active_outlined,
                    emptyTitle: localizations.noBlockedApps,
                    emptyMessage: localizations.noBlockedAppsDesc,
                    onUnblock: notificationsService.unblockPackage,
                    onUnblockAll: notificationsService.unblockAllPackages,
                  ),

                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 8),
                    child: Divider(),
                  ),

                  // --- ALL APPLICATIONS ---
                  Padding(
                    padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          localizations.applications,
                          style: theme.textTheme.titleSmall?.copyWith(
                            color: theme.colorScheme.primary,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          localizations.noBlockedAppsDesc,
                          style: theme.textTheme.bodySmall?.copyWith(color: Colors.white54),
                        ),
                      ],
                    ),
                  ),
                  ...allApps.map((app) {
                    final isBlocked = blockedPackages.contains(app.packageName);

                    return RoundedSwitchListTile(
                      value: !isBlocked,
                      onChanged: (allowed) {
                        if (allowed) {
                          notificationsService.unblockPackage(app.packageName);
                        } else {
                          notificationsService.blockPackage(app.packageName);
                        }
                      },
                      title: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(app.name, style: theme.textTheme.bodyMedium),
                          const SizedBox(height: 2),
                          Text(
                            isBlocked ? localizations.notificationsBlocked : localizations.notificationsAllowed,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: isBlocked ? Colors.redAccent : Colors.white54,
                            ),
                          ),
                        ],
                      ),
                      secondary: AppIcon(app.packageName, size: 32, borderRadius: 6),
                    );
                  }),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}
