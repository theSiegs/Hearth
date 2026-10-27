/// What joining a household would change on this TV (docs/household-sync.md, "Before joining"), for one profile: its
/// look, layout and wallpaper pictures (the app's), its streaming app profile choices and saved PINs (the Java side's).
class JoinChange {
  final String key;
  final String name;
  final bool kids;
  final bool look;
  final bool layout;
  final int pictures;
  final int pairings;
  final int pins;

  const JoinChange({
    required this.key,
    required this.name,
    this.kids = false,
    this.look = false,
    this.layout = false,
    this.pictures = 0,
    this.pairings = 0,
    this.pins = 0,
  });

  bool get any => look || layout || pictures > 0 || pairings > 0 || pins > 0;
}

/// Everything joining would change here: per profile, the Parent PIN (when this TV has none and the household has
/// one), and saved PINs that are the whole TV's.
class JoinPreview {
  final List<JoinChange> profiles;
  final bool parentPin;
  final int tvPins;

  const JoinPreview({required this.profiles, this.parentPin = false, this.tvPins = 0});

  /// The profiles that change.
  List<JoinChange> get changed => [for (final p in profiles) if (p.any) p];

  /// Nothing here would change: joining goes on without asking.
  bool get isEmpty => changed.isEmpty && !parentPin && tvPins == 0;
}

/// Shows and settles what joining changes, and puts this TV's settings back afterwards (HouseholdLooksService does it).
abstract class HouseholdJoinReviewer {
  /// How long the copy of this TV's settings from before it joined is kept.
  static const Duration keptFor = Duration(days: 14);

  /// What the household's settings would change here; null while this TV doesn't hold them, or they haven't come.
  Future<JoinPreview?> joinPreview();

  /// Keeps a copy of what [preview] would change, then lets the household's settings in. False when that failed.
  Future<bool> finishJoin(JoinPreview preview);

  /// When the copy from before joining was made, while it's kept; null when there is none.
  Future<DateTime?> joinBackupAt();

  /// Puts the copy back (looks, layouts, pictures, pairings and PINs) and drops it. False when it couldn't be.
  Future<bool> restoreJoinBackup();
}
