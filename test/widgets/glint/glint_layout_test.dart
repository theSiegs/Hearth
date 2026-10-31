import 'package:flauncher/widgets/glint/glint_apps_page.dart';
import 'package:flauncher/widgets/glint/glint_flip.dart';
import 'package:flauncher/widgets/glint/glint_layout.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group("GlintLayout.pack", () {
    test("fills each column top to bottom before the next", () {
      final layout = GlintLayout.pack(List.filled(5, GlintSize.small));
      expect(layout.cells, const [GlintCell(0, 0), GlintCell(0, 1), GlintCell(0, 2), GlintCell(1, 0), GlintCell(1, 1)]);
      expect(layout.columns, 2);
    });

    test("small tiles fill the gap a big one leaves", () {
      // A 2x2 clock, a 3x2 poster: the row under them takes the small tiles, in order
      final layout = GlintLayout.pack(
          [GlintSize.medium, GlintSize.large, GlintSize.small, GlintSize.small, GlintSize.wide]);
      expect(layout.cells, const [
        GlintCell(0, 0), // clock
        GlintCell(2, 0), // poster beside it
        GlintCell(0, 2), // under the clock
        GlintCell(1, 2),
        GlintCell(2, 2), // under the poster
      ]);
      expect(layout.columns, 5);
    });

    test("a wide tile takes the first place it fits, even under a big one", () {
      final layout = GlintLayout.pack([GlintSize.medium, GlintSize.small, GlintSize.wide, GlintSize.wide]);
      expect(layout.cells, const [GlintCell(0, 0), GlintCell(0, 2), GlintCell(1, 2), GlintCell(2, 0)]);
    });

    test("a tile taller than the grid is cut to its height", () {
      final layout = GlintLayout.pack([const GlintSize(1, 5), GlintSize.small], rows: 3);
      expect(layout.cells, const [GlintCell(0, 0), GlintCell(1, 0)]);
    });

    test("nothing to place: no columns", () {
      expect(GlintLayout.pack(const []).columns, 0);
    });
  });

  group("GlintTicker", () {
    test("turns one tile at a time, the one that waited longest, no sooner than its pace", () {
      var now = DateTime(2026, 10, 31, 1);
      final ticker = GlintTicker(spacing: const Duration(days: 1), now: () => now);
      addTearDown(ticker.dispose);
      final a = ticker.join("a", faces: 3, pace: const Duration(seconds: 10));
      final b = ticker.join("b", faces: 2, pace: const Duration(seconds: 10));
      final single = ticker.join("single", faces: 1, pace: Duration.zero);

      ticker.step();
      expect((a.value, b.value), (0, 0), reason: "not yet due");

      now = now.add(const Duration(minutes: 1));
      ticker.step();
      ticker.step();
      expect(a.value + b.value, 2, reason: "both due: one each, one per step");
      expect(single.value, 0, reason: "a tile with one face never turns");
    });

    test("holds the selected tile and pauses while resting", () {
      var now = DateTime(2026, 10, 31, 1);
      final ticker = GlintTicker(spacing: const Duration(days: 1), now: () => now);
      addTearDown(ticker.dispose);
      final a = ticker.join("a", faces: 2, pace: Duration.zero);
      now = now.add(const Duration(minutes: 1));

      ticker.hold("a", true);
      ticker.step();
      expect(a.value, 0);

      ticker.hold("a", false);
      ticker.paused = true;
      ticker.step();
      expect(a.value, 0);

      ticker.paused = false;
      ticker.step();
      expect(a.value, 1);
      now = now.add(const Duration(minutes: 1));
      ticker.step();
      expect(a.value, 0, reason: "wraps round");
    });

    test("fewer faces than the shown index: back to the first", () {
      final ticker = GlintTicker(spacing: const Duration(days: 1));
      addTearDown(ticker.dispose);
      final a = ticker.join("a", faces: 3, pace: Duration.zero);
      a.value = 2;
      ticker.join("a", faces: 2, pace: Duration.zero);
      expect(a.value, 0);
    });
  });

  test("the app list's letters", () {
    expect(GlintAppsPage.letterOf("netflix"), "N");
    expect(GlintAppsPage.letterOf(" Apple TV"), "A");
    expect(GlintAppsPage.letterOf("9Now"), "#");
    expect(GlintAppsPage.letterOf(""), "#");
  });
}
