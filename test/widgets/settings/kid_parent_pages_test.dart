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
import 'package:flauncher/l10n/app_localizations.dart';
import 'package:flauncher/models/parent_channel.dart';
import 'package:flauncher/widgets/settings/kid_parent_pages.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

/// A kid's HearthTube log and the parent's blocked lists, as the Android side answers (provider contract 8).
class _ParentChannel extends FLauncherChannel {
  final List<StartedVideo> log;
  Map<String, dynamic> blocks;
  final List<Map<String, Object?>> calls = [];

  _ParentChannel({this.log = const [], Map<String, dynamic>? blocks})
      : blocks = blocks ?? {"own": {}, "ha": {}};

  @override
  Future<List<StartedVideo>> getStartedLog(String profileKey) async => log;

  @override
  Future<Map<dynamic, dynamic>> getParentBlocks(String profileKey) async => blocks;

  @override
  Future<bool> setParentBlock({
    required String profileKey,
    required String kind,
    required String id,
    String? label,
    required bool on,
  }) async {
    calls.add({"profileKey": profileKey, "kind": kind, "id": id, "label": label, "on": on});
    return true;
  }
}

void main() {
  Future<void> show(WidgetTester tester, _ParentChannel channel, Widget page) async {
    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(Provider<FLauncherChannel>.value(
      value: channel,
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(body: page),
      ),
    ));
    await tester.pumpAndSettle();
  }

  group('models', () {
    test('a started video reads from the Android side', () {
      final video = StartedVideo.fromMap({"t": 5000, "v": "abc123", "title": "T", "ch": "C", "cid": "UCx"})!;
      expect(video.timeMs, 5000);
      expect(video.channelId, "UCx");
      expect(StartedVideo.fromMap({"t": 1}), isNull);
    });

    test('blocked lists read, with labels, from both sources', () {
      final blocks = ParentBlocks.fromMap({
        "own": {
          "videos": [
            {"id": "abc123", "label": "A title"}
          ],
          "channels": [],
          "words": ["one"],
        },
        "ha": {
          "videos": [],
          "channels": [
            {"id": "UCx", "label": "UCx"}
          ],
          "words": [],
        },
      });
      expect(blocks.ownVideos.single.label, "A title");
      expect(blocks.ownWords.single.id, "one");
      expect(blocks.haChannels.single.id, "UCx");
      expect(blocks.blockedIds, {"abc123", "UCx"});
      expect(blocks.isEmpty, isFalse);
      expect(ParentBlocks.fromMap({}).isEmpty, isTrue);
    });
  });

  group('the log', () {
    testWidgets('lists what the kid started and blocks a channel from a row', (tester) async {
      final channel = _ParentChannel(log: const [
        StartedVideo(timeMs: 1793109900000, videoId: "abc123", title: "Sailing yacht", channel: "Boats Inc", channelId: "UCboats1"),
      ]);
      await show(tester, channel, const KidWatchLogPage(profileKey: "user:11"));

      expect(find.text("Sailing yacht"), findsOneWidget);
      await tester.tap(find.text("Sailing yacht"));
      await tester.pumpAndSettle();
      await tester.tap(find.text("Block the channel Boats Inc"));
      await tester.pumpAndSettle();

      expect(channel.calls.single,
          {"profileKey": "user:11", "kind": "channel", "id": "UCboats1", "label": "Boats Inc", "on": true});
    });

    testWidgets('an entry without a channel id only offers the video', (tester) async {
      final channel = _ParentChannel(log: const [StartedVideo(timeMs: 1793109900000, videoId: "abc123", title: "Old one")]);
      await show(tester, channel, const KidWatchLogPage(profileKey: "user:11"));

      await tester.tap(find.text("Old one"));
      await tester.pumpAndSettle();

      expect(find.text("Block this video"), findsOneWidget);
      expect(find.textContaining("Block the channel"), findsNothing);
      expect(find.text("Block this channel"), findsNothing);
    });

    testWidgets('an empty log says so', (tester) async {
      await show(tester, _ParentChannel(), const KidWatchLogPage(profileKey: "user:11"));

      expect(find.text("Nothing started yet."), findsOneWidget);
    });
  });

  group('the blocked lists', () {
    testWidgets('own blocks can be taken back, Home Assistant ones are only shown', (tester) async {
      final channel = _ParentChannel(blocks: {
        "own": {
          "videos": [
            {"id": "abc123", "label": "A title"}
          ],
          "channels": [],
          "words": ["one"],
        },
        "ha": {
          "videos": [],
          "channels": [
            {"id": "UCx", "label": "Some channel"}
          ],
          "words": [],
        },
      });
      await show(tester, channel, const KidBlocksPage(profileKey: "user:11"));

      expect(find.text("A title"), findsOneWidget);
      expect(find.text("Some channel"), findsOneWidget);
      expect(find.text("Home Assistant"), findsOneWidget);

      await tester.tap(find.text("Some channel"));
      await tester.pumpAndSettle();
      expect(channel.calls, isEmpty);

      await tester.tap(find.text("A title"));
      await tester.pumpAndSettle();
      await tester.tap(find.text("Remove"));
      await tester.pumpAndSettle();

      expect(channel.calls.single, {"profileKey": "user:11", "kind": "video", "id": "abc123", "label": "A title", "on": false});
    });

    testWidgets('nothing blocked says so', (tester) async {
      await show(tester, _ParentChannel(), const KidBlocksPage(profileKey: "user:11"));

      expect(find.text("Nothing is blocked."), findsOneWidget);
    });
  });
}
