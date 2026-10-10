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
import 'package:flauncher/providers/companion_updater.dart';
import 'package:flauncher/providers/setup_flow_service.dart';
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

  /// Android lets Hearth read what was being watched (Continue Watching).
  final bool watchNextAllowed;

  /// HearthTube, Hearth's companion app, is installed.
  final bool hearthTubeInstalled;

  /// Google TV, with its profiles: the family card shows only there.
  final bool googleTv;

  /// How many Family Link-supervised (kids') profiles Android lists.
  final int kidsProfiles;

  /// Netflix is installed: its profile screen needs Hearth voice.
  final bool netflix;

  const SetupSnapshot({
    required this.steps,
    required this.packageName,
    this.adbEnabled = false,
    this.watchNextAllowed = false,
    this.hearthTubeInstalled = false,
    this.googleTv = false,
    this.kidsProfiles = 0,
    this.netflix = false,
  });

  SetupStep step(SetupStepId id) => steps.firstWhere((step) => step.id == id);

  bool isDone(SetupStepId id) => step(id).done;

  /// Whether everything a card turns on is on already. [showContinueWatching]: the home shows the row;
  /// [hasParentPin]: a parent PIN is set; [kidsProtected]: how many kids' profiles Hearth was put on.
  bool cardOn(SetupCard card,
          {required bool showContinueWatching, required bool hasParentPin, required int kidsProtected}) =>
      cardOnFrom(
        card,
        watchNextAllowed: watchNextAllowed,
        showContinueWatching: showContinueWatching,
        notifications: isDone(SetupStepId.notifications),
        install: isDone(SetupStepId.install),
        hearthTubeInstalled: hearthTubeInstalled,
        googleTv: googleTv,
        hasParentPin: hasParentPin,
        pairing: isDone(SetupStepId.profilePairing),
        voice: !netflix || isDone(SetupStepId.voice),
        kids: kidsProfiles <= kidsProtected,
      );

  /// The rule behind [cardOn], for the home's checks that have no snapshot. A card that is a choice by itself (the
  /// look, TV & power) is never on until chosen. The family card counts as on away from Google TV, where it isn't
  /// shown. [voice]: Hearth voice is the preferred engine, or there's no Netflix to need it. [kids]: Hearth was put
  /// on every kids' profile from the flow (what's on them can't be read without Hearth's own adb), or there's none.
  static bool cardOnFrom(
    SetupCard card, {
    required bool watchNextAllowed,
    required bool showContinueWatching,
    required bool notifications,
    required bool install,
    required bool hearthTubeInstalled,
    required bool googleTv,
    required bool hasParentPin,
    required bool pairing,
    required bool voice,
    required bool kids,
  }) =>
      switch (card) {
        SetupCard.family => !googleTv || (hasParentPin && pairing && voice && kids),
        SetupCard.watching => watchNextAllowed && showContinueWatching && notifications,
        SetupCard.home || SetupCard.tv => false,
        SetupCard.updates => install && hearthTubeInstalled,
      };

  /// Which cards are all on already, read straight from the TV: for marking an install from before the flow, and the
  /// chip's count.
  static Future<Map<SetupCard, bool>> loadCardsOn(FLauncherChannel channel,
      {required bool showContinueWatching, required bool hasParentPin, required int kidsProtected}) async {
    final watchNext = await _safe(channel.checkWatchNextPermission, false);
    final notifications = await _safe(channel.checkNotificationListenerPermission, false);
    final install = await _safe(channel.checkInstallPermission, false);
    final tube = await _hearthTubeInstalled(channel);
    final family = await _safe(channel.getSetupFamilyState, <dynamic, dynamic>{});
    final pairing = await _safe(channel.getProfilePairingStatus, <dynamic, dynamic>{});
    return {
      for (final card in SetupCard.values)
        card: cardOnFrom(card,
            watchNextAllowed: watchNext,
            showContinueWatching: showContinueWatching,
            notifications: notifications,
            install: install,
            hearthTubeInstalled: tube,
            googleTv: family["googleTv"] == true,
            hasParentPin: hasParentPin,
            pairing: pairing["enabled"] == true,
            voice: family["netflix"] != true || pairing["voiceDefault"] == true,
            kids: ((family["kidsProfiles"] as int?) ?? 0) <= kidsProtected),
    };
  }

  static Future<T> _safe<T>(Future<T> Function() read, T fallback) async {
    try {
      return await read();
    } catch (_) {
      return fallback;
    }
  }

  static Future<bool> _hearthTubeInstalled(FLauncherChannel channel) =>
      _safe(() async => await channel.getPackageVersion(companionApps.first.packageName) != null, false);

  static Future<SetupSnapshot> load(FLauncherChannel channel, AppLocalizations l) async {
    String packageName = kHearthAppId;
    try {
      packageName = (await PackageInfo.fromPlatform()).packageName;
    } catch (_) {}
    final steps = await loadSetupSteps(channel, packageName, l);
    final family = await _safe(channel.getSetupFamilyState, <dynamic, dynamic>{});
    return SetupSnapshot(
      steps: steps,
      packageName: packageName,
      adbEnabled: await _safe(channel.isAdbEnabled, false),
      watchNextAllowed: await _safe(channel.checkWatchNextPermission, false),
      hearthTubeInstalled: await _hearthTubeInstalled(channel),
      googleTv: family["googleTv"] == true,
      kidsProfiles: (family["kidsProfiles"] as int?) ?? 0,
      netflix: family["netflix"] == true,
    );
  }
}
