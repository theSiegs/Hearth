import 'package:flauncher/flauncher_channel.dart';
import 'package:flauncher/l10n/app_localizations.dart';
import 'package:flauncher/models/ha_lock_state.dart';
import 'package:flauncher/gradients.dart';
import 'package:flauncher/providers/wallpaper_service.dart';
import 'package:flauncher/widgets/glint/glint_faces.dart';
import 'package:flauncher/widgets/glint/glint_flip.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:provider/provider.dart';

import '../../mocks.mocks.dart';

void main() {
  final now = DateTime(2026, 11, 6, 19, 50);

  group("the time tile shows", () {
    test("nothing for an adult, or a kid with nothing coming", () {
      expect(TimeUpFace.shows(HaLockState.none, nothingToOpen: false, now: now), isFalse);
      final later = HaLockState(
          paired: true, kids: true, nextLockKind: HaLockKind.bedtime, nextLockAt: now.add(const Duration(hours: 2)));
      expect(TimeUpFace.shows(later, nothingToOpen: false, now: now), isFalse);
    });

    test("a hold, a bedtime within the hour, or nothing to open", () {
      expect(TimeUpFace.shows(const HaLockState(paired: true, kids: true, paused: true), nothingToOpen: false, now: now),
          isTrue);
      expect(
          TimeUpFace.shows(
              const HaLockState(paired: true, kids: true, timeUp: [HaTimeUpGroup("games", "Games")]),
              nothingToOpen: false,
              now: now),
          isTrue);
      final soon = HaLockState(
          paired: true, kids: true, nextLockKind: HaLockKind.bedtime, nextLockAt: now.add(const Duration(minutes: 40)));
      expect(TimeUpFace.shows(soon, nothingToOpen: false, now: now), isTrue);
      expect(TimeUpFace.shows(HaLockState.none, nothingToOpen: true, now: now), isTrue);
    });
  });

  Future<void> pumpFace(WidgetTester tester, TimeUpFace face) async {
    final ticker = GlintTicker(autoStart: false);
    addTearDown(ticker.dispose);
    final wallpaper = MockWallpaperService();
    when(wallpaper.gradient).thenReturn(FLauncherGradients.greatWhale);
    when(wallpaper.focusedAppColor).thenReturn(null);
    when(wallpaper.wallpaper).thenReturn(null);
    when(wallpaper.version).thenReturn(0);
    await tester.pumpWidget(MultiProvider(
      providers: [
        Provider<FLauncherChannel>.value(value: FLauncherChannel()),
        ChangeNotifierProvider<WallpaperService>.value(value: wallpaper),
      ],
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Material(
          child: GlintTickerScope(
            ticker: ticker,
            child: Center(child: SizedBox(width: 300, height: 140, child: face)),
          ),
        ),
      ),
    ));
  }

  testWidgets("a family pause says its reason and until when", (tester) async {
    await pumpFace(
        tester,
        TimeUpFace(
            state: HaLockState(
                paired: true, kids: true, paused: true, pauseReason: "Dinner", pauseUntil: DateTime(2026, 11, 6, 19))));
    expect(find.text("Paused: Dinner"), findsOneWidget);
    expect(find.text("Until 7:00 PM"), findsOneWidget);
  });

  testWidgets("bedtime coming says when", (tester) async {
    await pumpFace(
        tester,
        TimeUpFace(
            clock: () => now,
            state: HaLockState(
                paired: true, kids: true, nextLockKind: HaLockKind.bedtime, nextLockAt: DateTime(2026, 11, 6, 20, 30))));
    expect(find.text("Bedtime at 8:30 PM"), findsOneWidget);
  });

  testWidgets("nothing to open, without Home Assistant", (tester) async {
    await pumpFace(tester, const TimeUpFace(state: HaLockState.none, nothingToOpen: true));
    expect(find.text("Nothing to watch right now"), findsOneWidget);
  });

  test("a person's name as Family shows it", () {
    expect(ProfileFace.shownName("Alex Rivera"), "alex");
    expect(ProfileFace.shownName("Sam"), "sam");
    expect(ProfileFace.shownName("  "), "");
  });
}
