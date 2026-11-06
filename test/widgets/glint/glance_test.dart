import 'package:flauncher/models/ha_lock_state.dart';
import 'package:flauncher/widgets/glint/glance_feed.dart';
import 'package:flauncher/widgets/glint/glance_page.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group("GlanceHaFeed.parse", () {
    test("people by name, away for not_home; lists with something left, most first", () {
      final parsed = GlanceHaFeed.parse(
        '{"people": [["Sam Rivera", "not_home"], ["Alex", "home"], ["Robin", "unavailable"], ["Kim", "Grandma_s"]],'
        ' "lists": [["Shopping", "0"], ["Chores", "3"], ["Packing", 5]]}',
      );
      expect([for (final p in parsed.people) "${p.name}: ${p.where}"], ["Alex: home", "Kim: Grandma s", "Sam Rivera: away"]);
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

    test("without Home Assistant: the clock and the ways out", () {
      expect(ids(glanceTiles(lock: HaLockState.none)), ["clock", "all-apps", "settings"]);
    });

    test("a kid with Home Assistant: their time and minutes first, then the family and the lists", () {
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
      expect(ids(tiles), ["clock", "time", "screen-time", "family", "lists", "all-apps", "home-assistant", "settings"]);
    });

    test("an adult's page has no screen time tiles", () {
      final tiles = glanceTiles(
        lock: const HaLockState(paired: true, groups: [HaGroupLeft("all", "All screen time", 40)]),
      );
      expect(ids(tiles), isNot(contains("screen-time")));
    });
  });
}
