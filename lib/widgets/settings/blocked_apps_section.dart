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

import 'package:flauncher/models/app.dart';
import 'package:flutter/material.dart';

import 'app_icon.dart';
import 'focusable_settings_tile.dart';

/// The top of a block list: a heading, a row per blocked app that unblocks it, and one that unblocks them all. With
/// nothing blocked, a card says so instead.
class BlockedAppsSection extends StatelessWidget {
  /// The heading, with the count.
  final String title;

  /// Blocked apps that are installed.
  final List<App> apps;

  /// Blocked packages that aren't installed (any more); they show by package name.
  final List<String> missingPackages;

  /// Under each blocked app's name.
  final String blockedLabel;
  final String unblockLabel;
  final String unblockAllLabel;

  /// For apps without an icon, and for missing packages.
  final IconData appIcon;

  final IconData emptyIcon;
  final String emptyTitle;
  final String emptyMessage;

  final ValueChanged<String> onUnblock;
  final VoidCallback onUnblockAll;

  const BlockedAppsSection({
    super.key,
    required this.title,
    required this.apps,
    required this.missingPackages,
    required this.blockedLabel,
    required this.unblockLabel,
    required this.unblockAllLabel,
    required this.appIcon,
    required this.emptyIcon,
    required this.emptyTitle,
    required this.emptyMessage,
    required this.onUnblock,
    required this.onUnblockAll,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
          child: Text(
            title,
            style: theme.textTheme.titleSmall?.copyWith(
              color: theme.colorScheme.primary,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        if (apps.isEmpty && missingPackages.isEmpty)
          _nothingBlocked(theme)
        else ...[
          for (final app in apps)
            _blockedRow(
              theme,
              AppIcon(app.packageName, size: 32, borderRadius: 6, placeholder: Icon(appIcon, size: 32)),
              app.name,
              app.packageName,
            ),
          for (final packageName in missingPackages)
            _blockedRow(theme, Icon(appIcon, size: 32), packageName, packageName),
          FocusableSettingsTile(
            leading: const Icon(Icons.clear_all, color: Colors.orange),
            title: Text(
              unblockAllLabel,
              style: theme.textTheme.bodyMedium?.copyWith(color: Colors.orange),
            ),
            onPressed: onUnblockAll,
          ),
        ],
      ],
    );
  }

  Widget _nothingBlocked(ThemeData theme) => Padding(
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
              Icon(emptyIcon, color: Colors.green, size: 28),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      emptyTitle,
                      style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      emptyMessage,
                      style: theme.textTheme.bodySmall?.copyWith(color: Colors.white54),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );

  Widget _blockedRow(ThemeData theme, Widget icon, String name, String packageName) => FocusableSettingsTile(
        leading: icon,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(name, style: theme.textTheme.bodyMedium),
            const SizedBox(height: 2),
            Text(
              blockedLabel,
              style: theme.textTheme.bodySmall?.copyWith(color: Colors.redAccent),
            ),
          ],
        ),
        trailing: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: Colors.red.withOpacity(0.15),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.redAccent.withOpacity(0.5)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.lock_open, size: 14, color: Colors.redAccent),
              const SizedBox(width: 4),
              Text(
                unblockLabel,
                style: const TextStyle(
                  color: Colors.redAccent,
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
        onPressed: () => onUnblock(packageName),
      );
}
