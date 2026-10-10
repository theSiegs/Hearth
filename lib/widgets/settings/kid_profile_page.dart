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

import 'package:flauncher/l10n/app_localizations.dart';
import 'package:flauncher/models/kids_profiles.dart';
import 'package:flutter/material.dart';

import 'focusable_settings_tile.dart';
import 'kids_profiles_page.dart';
import 'profiles_settings_page.dart';
import 'settings_page.dart';

/// One kid, from Settings > Profiles > Kids' profiles: everything that's that child's own in one place, set by the
/// parent without switching to their profile. How Hearth stands on the profile (needing a fix: back to the list's
/// Fix), and their YouTube time per day in HearthTube.
class KidProfilePage extends StatelessWidget {
  static const String routeName = "kid_profile";

  /// What [KidProfilePage] pops with when the parent asks to fix the profile.
  static const String fix = "fix";

  final KidsProfilesState state;
  final KidProfile kid;

  const KidProfilePage({super.key, required this.state, required this.kid});

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final textTheme = Theme.of(context).textTheme;
    final (:label, :status, :detail, :color) = KidsProfilesPage.describe(l, state, kid);
    final ready = state.statusOf(kid) == KidProfileStatus.ready;
    return SettingsPage(
      title: label,
      children: [
        FocusableSettingsTile(
          autofocus: !ready,
          leading: const Icon(Icons.child_care),
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(detail, style: textTheme.bodyMedium),
              if (!ready) Text(l.kidsProfilesFixBody, style: textTheme.bodySmall?.copyWith(color: Colors.white54)),
            ],
          ),
          trailing: Text(ready ? status : l.kidsProfilesFix, style: textTheme.bodySmall?.copyWith(color: color)),
          onPressed: ready ? null : () => Navigator.of(context).pop(fix),
        ),
        if (kid.profileKey != null) YouTubeLimitTile(profileKey: kid.profileKey, autofocus: ready),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
          child: Text(l.kidProfileHint, style: textTheme.bodySmall?.copyWith(color: Colors.white54)),
        ),
      ],
    );
  }
}
