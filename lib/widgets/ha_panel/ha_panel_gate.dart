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

import 'package:flauncher/providers/profile_service.dart';
import 'package:flauncher/providers/settings_service.dart';
import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';

/// The Home Assistant panel (Hearth's own, and the full dashboard) is for adults: a kids profile never gets it,
/// whatever its settings say. On only when the profile turned it on and isn't a kids profile.
bool haPanelAllowed({required bool enabled, required bool kids}) => enabled && !kids;

/// Whether the home's edges open the Home Assistant panel for the profile that's on ([haPanelAllowed]).
bool haPanelAvailable(BuildContext context) => haPanelAllowed(
      enabled: context.read<SettingsService>().haPanelEnabled,
      kids: isKidsProfileOn(context),
    );

/// The profile that's on is a kids profile (false while Hearth can't tell, or with no profiles to ask).
bool isKidsProfileOn(BuildContext context) => context.read<ProfileService?>()?.isKidsProfile ?? false;
