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

/// How Hearth stands on one kids' profile: everything it puts there is there (and kept, as far as Hearth could read),
/// or what's out of place.
enum KidProfileStatus {
  ready,

  /// Hearth itself isn't on it.
  hearthMissing,

  /// Google TV can remove a copy there at the profile's next start (the keep flag isn't set).
  notKept,

  /// The owner has HearthTube and this profile doesn't.
  hearthTubeMissing,
}

/// One kids' profile, from [FLauncherChannel.getKidsProfilesState].
class KidProfile {
  final int userId;

  /// What Hearth keeps the profile's own settings under ("user:11"), such as its YouTube limit.
  final String? profileKey;

  /// The profile's name as Hearth learned it from Google TV's chooser; null until it has.
  final String? name;

  /// Its user runs: it is the profile on now.
  final bool running;

  final bool hearth;
  final bool hearthTube;

  /// Whether each copy is kept (Google TV can't remove it); null when it wasn't read.
  final bool? hearthKept;
  final bool? hearthTubeKept;

  const KidProfile({
    required this.userId,
    this.profileKey,
    this.name,
    this.running = false,
    this.hearth = false,
    this.hearthTube = false,
    this.hearthKept,
    this.hearthTubeKept,
  });

  KidProfile.fromMap(Map<dynamic, dynamic> map)
      : userId = (map["userId"] as int?) ?? -1,
        profileKey = map["profileKey"] as String?,
        name = map["name"] as String?,
        running = map["running"] == true,
        hearth = map["hearth"] == true,
        hearthTube = map["hearthTube"] == true,
        hearthKept = map["hearthKept"] as bool?,
        hearthTubeKept = map["hearthTubeKept"] as bool?;

  /// HearthTube counts only when the owner has it ([hearthTubeOnOwner]): only then does a kids' profile get it.
  KidProfileStatus status({required bool hearthTubeOnOwner}) {
    if (!hearth) return KidProfileStatus.hearthMissing;
    if (hearthKept == false || (hearthTubeOnOwner && hearthTube && hearthTubeKept == false)) {
      return KidProfileStatus.notKept;
    }
    if (hearthTubeOnOwner && !hearthTube) return KidProfileStatus.hearthTubeMissing;
    return KidProfileStatus.ready;
  }
}

/// Hearth on the TV's kids' profiles, as [FLauncherChannel.getKidsProfilesState] reads it.
class KidsProfilesState {
  final List<KidProfile> kids;

  /// The owner has HearthTube, so the kids' profiles get it too.
  final bool hearthTubeOnOwner;

  /// A parent put Hearth on the kids' profiles and hasn't taken it off since: new ones get it by themselves.
  final bool keep;

  /// The TV trusts Hearth's adb key (a parent allowed "Allow debugging?"), so Fix won't ask.
  final bool trusted;

  /// The TV's debugging switch is on: Hearth's own adb needs it.
  final bool adbEnabled;

  const KidsProfilesState({
    this.kids = const [],
    this.hearthTubeOnOwner = false,
    this.keep = false,
    this.trusted = false,
    this.adbEnabled = false,
  });

  factory KidsProfilesState.fromMap(Map<dynamic, dynamic> map) => KidsProfilesState(
        kids: [
          for (final kid in (map["kids"] as List?) ?? const []) KidProfile.fromMap(kid as Map<dynamic, dynamic>),
        ],
        hearthTubeOnOwner: map["hearthTubeOnOwner"] == true,
        keep: map["keep"] == true,
        trusted: map["trusted"] == true,
        adbEnabled: map["adbEnabled"] == true,
      );

  KidProfileStatus statusOf(KidProfile kid) => kid.status(hearthTubeOnOwner: hearthTubeOnOwner);

  /// How many kids' profiles have something out of place.
  int get needingFix => kids.where((kid) => statusOf(kid) != KidProfileStatus.ready).length;

  /// There are kids' profiles, and Hearth is all there on each.
  bool get allReady => kids.isNotEmpty && needingFix == 0;
}
