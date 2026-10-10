import 'dart:typed_data';

class WatchNextProgram {
  final int id;
  final String packageName;
  final String title;
  final String description;
  final int watchNextType;
  final int lastEngagementTime;
  final int playbackPosition;
  final int duration;
  final String intentUri;
  final String posterArtUri;

  /// Reported by the active profile's Hearth agent from its own user: already this profile's, no owner to work out.
  final bool profileOwned;

  /// From Hearth's own user, which all the grown-ups' profiles share (one per Google account): the profile (its key)
  /// that had the app open when this was last watched. Null when Hearth doesn't know: the user's first profile's.
  final String? watchedBy;

  /// Downscaled poster art, filled in after the row first appears.
  Uint8List? posterBytes;

  WatchNextProgram({
    required this.id,
    required this.packageName,
    required this.title,
    required this.description,
    required this.watchNextType,
    required this.lastEngagementTime,
    required this.playbackPosition,
    required this.duration,
    required this.intentUri,
    required this.posterArtUri,
    this.profileOwned = false,
    this.watchedBy,
    this.posterBytes,
  });

  factory WatchNextProgram.fromMap(Map<dynamic, dynamic> map) {
    return WatchNextProgram(
      id: (map['id'] as num?)?.toInt() ?? 0,
      packageName: map['packageName'] as String? ?? '',
      title: map['title'] as String? ?? '',
      description: map['description'] as String? ?? '',
      watchNextType: (map['watchNextType'] as num?)?.toInt() ?? 0,
      lastEngagementTime: (map['lastEngagementTime'] as num?)?.toInt() ?? 0,
      playbackPosition: (map['playbackPosition'] as num?)?.toInt() ?? 0,
      duration: (map['duration'] as num?)?.toInt() ?? 0,
      intentUri: map['intentUri'] as String? ?? '',
      posterArtUri: map['posterArtUri'] as String? ?? '',
      profileOwned: map['profileOwned'] == true,
      watchedBy: map['watchedBy'] as String?,
    );
  }
}
