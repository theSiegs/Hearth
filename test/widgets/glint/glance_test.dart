import 'package:flauncher/models/ha_lock_state.dart';
import 'package:flauncher/widgets/glint/glance_feed.dart';
import 'package:flauncher/widgets/glint/glance_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group("GlanceHaFeed.parse", () {
    test("everyone by name (no place for someone with no tracker), away for not_home; lists with something left, most first", () {
      final parsed = GlanceHaFeed.parse(
        '{"people": [["Sam Rivera", "not_home"], ["Alex", "home"], ["Robin", "unavailable"], ["Kim", "Grandma_s"]],'
        ' "lists": [["Shopping", "0"], ["Chores", "3"], ["Packing", 5]]}',
      );
      expect([for (final p in parsed.people) "${p.name}: ${p.where}"], ["Alex: home", "Kim: Grandma s", "Robin: ", "Sam Rivera: away"]);
      expect([for (final l in parsed.lists) "${l.name}: ${l.open}"], ["Packing: 5", "Chores: 3"]);
    });

    test("already parsed, or nonsense", () {
      expect(GlanceHaFeed.parse({"people": [["Alex", "home"]]}).people.single.name, "Alex");
      expect(GlanceHaFeed.parse("not json").people, isEmpty);
      expect(GlanceHaFeed.parse(null).lists, isEmpty);
    });
  });

  group("the glance page's tiles", () {
    List<String> ids(List<GlanceTile> tiles) => [for (final t in tiles) t.id];

    test("without Home Assistant: today and the ways out", () {
      expect(ids(glanceTiles(lock: HaLockState.none)), ["today", "all-apps", "settings"]);
      expect([for (final t in glanceTiles(lock: HaLockState.none)) if (t.action) t.id], ["all-apps", "settings"]);
    });

    test("notifications are a small way out, not a tile", () {
      final tiles = glanceTiles(lock: HaLockState.none, notifications: const []);
      expect(tiles.firstWhere((t) => t.id == "notifications").action, isTrue);
    });

    test("a kid with Home Assistant: their time and minutes first, then today, the family and the lists", () {
      final tiles = glanceTiles(
        lock: const HaLockState(
          paired: true,
          kids: true,
          timeUp: [HaTimeUpGroup("games", "Games")],
          groups: [HaGroupLeft("games", "Games", 0), HaGroupLeft("all", "All screen time", 40)],
        ),
        people: const [GlancePerson("Alex Rivera", "home")],
        lists: const [GlanceList("Chores", 2)],
        haPanel: true,
      );
      expect(ids(tiles), ["time", "screen-time", "today", "family", "lists", "all-apps", "home-assistant", "settings"]);
    });

    test("an adult's page has no screen time tiles", () {
      final tiles = glanceTiles(
        lock: const HaLockState(paired: true, groups: [HaGroupLeft("all", "All screen time", 40)]),
      );
      expect(ids(tiles), isNot(contains("screen-time")));
    });
  });

  group("the glance page's grid", () {
    test("names are first names, capitalised", () {
      expect(glanceName("sam"), "Sam");
      expect(glanceName("Alex Rivera"), "Alex");
      expect(glanceName("  "), "");
    });

    test("on a 1080p TV every tile sits inside the safe area, below the top bar, and none overlap", () {
      const screen = Size(960, 540);
      for (var count = 1; count <= 6; count++) {
        final g = GlanceGrid.fit(screen, count);
        expect(g.scrolls, isFalse, reason: "$count tiles fit");
        final rects = [
          for (var i = 0; i < count; i++)
            Rect.fromLTWH(g.side + g.left(i), g.topInset + g.top(i), g.tileWidth, g.tileHeight),
        ];
        for (final r in rects) {
          expect(r.left, greaterThanOrEqualTo(screen.width * 0.05 - 0.01));
          expect(r.right, lessThanOrEqualTo(screen.width * 0.95 + 0.01));
          expect(r.top, greaterThanOrEqualTo(kToolbarHeight));
          expect(r.bottom, lessThanOrEqualTo(screen.height * 0.95 - GlanceGrid.actionsHeight - GlanceGrid.actionsGap + 0.01));
        }
        for (var a = 0; a < rects.length; a++) {
          for (var b = a + 1; b < rects.length; b++) {
            expect(rects[a].overlaps(rects[b]), isFalse, reason: "tiles $a and $b");
          }
        }
      }
      expect(GlanceGrid.fit(screen, 7).scrolls, isTrue, reason: "a fourth row scrolls rather than being cut off");
    });
  });
}
