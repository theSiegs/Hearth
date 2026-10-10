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
import 'package:flauncher/hearth_ids.dart';
import 'package:flauncher/l10n/app_localizations.dart';
import 'package:flauncher/widgets/settings/setup_checklist_page.dart';
import 'package:package_info_plus/package_info_plus.dart';

/// What's on, as the TV says right now: the setup flow reads it when it opens and again whenever a step may have
/// changed it (back from Android's settings). The same steps as Settings' checklist ([loadSetupSteps]).
class SetupSnapshot {
  final List<SetupStep> steps;

  /// The installed build's package (the debug build has its own), for the commands shown.
  final String packageName;

  /// The TV's debugging switch is on, so Hearth can run its own fixes.
  final bool adbEnabled;

  const SetupSnapshot({required this.steps, required this.packageName, this.adbEnabled = false});

  SetupStep step(SetupStepId id) => steps.firstWhere((step) => step.id == id);

  bool isDone(SetupStepId id) => step(id).done;

  static Future<SetupSnapshot> load(FLauncherChannel channel, AppLocalizations l) async {
    String packageName = kHearthAppId;
    try {
      packageName = (await PackageInfo.fromPlatform()).packageName;
    } catch (_) {}
    final steps = await loadSetupSteps(channel, packageName, l);
    bool adb = false;
    try {
      adb = await channel.isAdbEnabled();
    } catch (_) {}
    return SetupSnapshot(steps: steps, packageName: packageName, adbEnabled: adb);
  }
}
