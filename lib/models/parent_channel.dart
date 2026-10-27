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

/// A video a kid's HearthTube started (provider contract 8, `report_started`).
class StartedVideo {
  final int timeMs;
  final String videoId;
  final String title;
  final String channel;

  /// Empty for an entry saved before HearthTube sent it.
  final String channelId;

  const StartedVideo({
    required this.timeMs,
    required this.videoId,
    this.title = "",
    this.channel = "",
    this.channelId = "",
  });

  /// From the Android side's map (t, v, title, ch, cid); null for one without a video.
  static StartedVideo? fromMap(Map<dynamic, dynamic> map) {
    final videoId = map["v"];
    if (videoId is! String || videoId.isEmpty) return null;
    return StartedVideo(
      timeMs: (map["t"] as num?)?.toInt() ?? 0,
      videoId: videoId,
      title: map["title"] as String? ?? "",
      channel: map["ch"] as String? ?? "",
      channelId: map["cid"] as String? ?? "",
    );
  }
}

/// One blocked video, channel or word: [id] is what's blocked, [label] what to show.
class BlockedThing {
  final String id;
  final String label;

  const BlockedThing(this.id, this.label);
}

/// What a parent blocked in a kid's HearthTube: "own" is set in Hearth, "ha" came from Home Assistant.
class ParentBlocks {
  final List<BlockedThing> ownVideos;
  final List<BlockedThing> ownChannels;
  final List<BlockedThing> ownWords;
  final List<BlockedThing> haVideos;
  final List<BlockedThing> haChannels;
  final List<BlockedThing> haWords;

  const ParentBlocks({
    this.ownVideos = const [],
    this.ownChannels = const [],
    this.ownWords = const [],
    this.haVideos = const [],
    this.haChannels = const [],
    this.haWords = const [],
  });

  static const ParentBlocks empty = ParentBlocks();

  bool get isEmpty =>
      ownVideos.isEmpty &&
      ownChannels.isEmpty &&
      ownWords.isEmpty &&
      haVideos.isEmpty &&
      haChannels.isEmpty &&
      haWords.isEmpty;

  /// The ids of the videos and channels blocked, from either source.
  Set<String> get blockedIds =>
      [...ownVideos, ...ownChannels, ...haVideos, ...haChannels].map((thing) => thing.id).toSet();

  static ParentBlocks fromMap(Map<dynamic, dynamic> map) {
    List<BlockedThing> things(Object? list, {required bool words}) {
      if (list is! List) return const [];
      return [
        for (final item in list)
          if (words && item is String)
            BlockedThing(item, item)
          else if (item is Map && item["id"] is String)
            BlockedThing(item["id"] as String, (item["label"] as String?) ?? item["id"] as String),
      ];
    }

    final own = map["own"] is Map ? map["own"] as Map : const {};
    final ha = map["ha"] is Map ? map["ha"] as Map : const {};
    return ParentBlocks(
      ownVideos: things(own["videos"], words: false),
      ownChannels: things(own["channels"], words: false),
      ownWords: things(own["words"], words: true),
      haVideos: things(ha["videos"], words: false),
      haChannels: things(ha["channels"], words: false),
      haWords: things(ha["words"], words: true),
    );
  }
}
