import 'dart:typed_data';

import 'package:flauncher/gradients.dart';
import 'package:flauncher/models/ha_lock_state.dart';
import 'package:flauncher/providers/wallpaper_service.dart';
import 'package:flauncher/widgets/glint/glance_feed.dart';
import 'package:flauncher/widgets/glint/glance_page.dart';
import 'package:flauncher/widgets/glint/glint_faces.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:provider/provider.dart';

import '../../mocks.mocks.dart';

void main() {
  final photo = Uint8List.fromList(List.filled(16, 1));
  const connection = (url: "http://ha.example:8123", token: "t");

  List<GlanceMember> familyItems(List<GlancePerson> people, Map<String, Uint8List?> photos) {
    final tiles = glanceTiles(lock: HaLockState.none, people: people, photos: photos, connection: connection);
    final family = tiles.firstWhere((t) => t.id == "family");
    // The tile's builder makes the family face; its members are what it shows
    return (family.build(_NoContext()) as GlanceFamilyFace).members;
  }

  test("a TV profile is looked for by the whole name, then the first name", () {
    expect(profileNamesFor("Alex Rivera"), ["Alex Rivera", "Alex"]);
    expect(profileNamesFor("Sam"), ["Sam"]);
    expect(profileNamesFor("  "), isEmpty);
  });

  test("the feed keeps Home Assistant's picture of each person", () {
    final parsed = GlanceHaFeed.parse('{"people": [["Alex", "home", "/api/image/serve/abc/512x512"], ["Sam", "home", ""]],'
        ' "lists": []}');
    expect(parsed.people.map((p) => p.picture), ["/api/image/serve/abc/512x512", null]);
  });

  test("faces in order: the TV profile photo, else Home Assistant's picture, else the initial", () {
    final items = familyItems(const [
      GlancePerson("Alex Rivera", "home", "/api/image/serve/abc/512x512"),
      GlancePerson("Robin", "away", "/api/image/serve/def/512x512"),
      GlancePerson("Sam", "school"),
    ], {"Alex Rivera": photo, "Robin": null, "Sam": null});
    final faces = [for (final i in items) i.face as PersonFace];
    expect(faces[0].photo, photo, reason: "the profile photo comes first");
    expect(faces[1].photo, isNull);
    expect(faces[1].picture!.uri.toString(), "http://ha.example:8123/api/image/serve/def/512x512");
    expect(faces[1].picture!.headers["Authorization"], "Bearer t");
    expect(faces[2].photo, isNull);
    expect(faces[2].picture, isNull, reason: "nothing to show: the initial");
    expect([for (final f in faces) f.key], [
      const ValueKey("face:Alex Rivera"),
      const ValueKey("face:Robin"),
      const ValueKey("face:Sam"),
    ]);
    expect([for (final i in items) i.name], ["Alex", "Robin", "Sam"], reason: "first names, capitalised");
  });

  testWidgets("everyone shows at once, each with their own face", (tester) async {
    final wallpaper = MockWallpaperService();
    when(wallpaper.gradient).thenReturn(FLauncherGradients.greatWhale);
    when(wallpaper.focusedAppColor).thenReturn(null);
    when(wallpaper.wallpaper).thenReturn(null);
    when(wallpaper.version).thenReturn(0);
    final items = familyItems(const [GlancePerson("alex", "home"), GlancePerson("Sam", "school")],
        {"alex": photo, "Sam": null});

    await tester.pumpWidget(ChangeNotifierProvider<WallpaperService>.value(
      value: wallpaper,
      child: MaterialApp(
        home: Material(
          child: Center(child: SizedBox(width: 420, height: 112, child: GlanceFamilyFace(members: items))),
        ),
      ),
    ));
    expect(find.text("Alex"), findsOneWidget);
    expect(find.text("Sam"), findsOneWidget);
    expect(find.text("school"), findsOneWidget);
    expect(find.byKey(const Key("person_face_photo")), findsOneWidget, reason: "Alex's photo stays with Alex");
    expect(find.byKey(const Key("person_face_initial")), findsOneWidget);
    expect(find.text("S"), findsOneWidget);
  });
}

/// The family tile's builder doesn't read its context.
class _NoContext extends Fake implements BuildContext {}
