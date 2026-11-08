import 'package:flauncher/gradients.dart';
import 'package:flauncher/l10n/app_localizations.dart';
import 'package:flauncher/models/ha_lock_state.dart';
import 'package:flauncher/providers/calendars.dart';
import 'package:flauncher/providers/wallpaper_service.dart';
import 'package:flauncher/widgets/glint/glance_feed.dart';
import 'package:flauncher/widgets/glint/glance_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:provider/provider.dart';

import '../../mocks.mocks.dart';

void main() {
  late MockWallpaperService wallpaper;
  setUp(() {
    wallpaper = MockWallpaperService();
    when(wallpaper.gradient).thenReturn(FLauncherGradients.greatWhale);
    when(wallpaper.focusedAppColor).thenReturn(null);
    when(wallpaper.wallpaper).thenReturn(null);
    when(wallpaper.version).thenReturn(0);
  });

  Widget app(Widget child, {double width = 420, double height = 114}) => ChangeNotifierProvider<WallpaperService>.value(
    value: wallpaper,
    child: MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: const Locale('en'),
      home: Material(child: Center(child: SizedBox(width: width, height: height, child: child))),
    ),
  );

  final now = DateTime(2026, 11, 6, 15);
  CalendarEvent event(String summary, int hour, {bool allDay = false}) => CalendarEvent(
    calendarId: "tv:1",
    calendarName: "Family",
    summary: summary,
    start: DateTime(2026, 11, 6, hour),
    end: DateTime(2026, 11, 6, hour + 1),
    allDay: allDay,
  );
  final events = [
    event("School pickup", 0, allDay: true),
    event("Piano", 15),
    event("Soccer", 17),
    event("Dinner", 18),
  ];

  group("Today", () {
    testWidgets("the next events at once, as many as fit, and how many more", (tester) async {
      await tester.pumpWidget(app(GlanceTodayFace(events: events, clock: () => now), height: 114));
      expect(find.text("School pickup"), findsOneWidget);
      expect(find.text("Piano"), findsOneWidget);
      expect(find.text("All day"), findsOneWidget);
      expect(find.text("Now"), findsOneWidget, reason: "Piano is on now");
      expect(find.text("+2 more"), findsOneWidget);

      await tester.pumpWidget(app(GlanceTodayFace(events: events, clock: () => now), height: 160));
      expect(find.text("Soccer"), findsOneWidget);
      expect(find.text("Dinner"), findsNothing, reason: "three at most");
      expect(find.text("+1 more"), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets("nothing left today says so", (tester) async {
      await tester.pumpWidget(app(GlanceTodayFace(clock: () => now)));
      expect(find.text("Nothing else on today"), findsOneWidget);
    });

    test("the tile has one face, so it never turns", () {
      final today = glanceTiles(lock: HaLockState.none, events: events, now: now).firstWhere((t) => t.id == "today");
      expect(today.faces, 1);
    });
  });

  group("To do", () {
    const chores = GlanceList("Chores", 4,
        entity: "todo.chores",
        next: [GlanceTodoItem("Dishes", "1"), GlanceTodoItem("Bins", "2"), GlanceTodoItem("Laundry", "3"), GlanceTodoItem("Beds", "4")]);
    const shopping = GlanceList("Shopping", 1, entity: "todo.shopping", next: [GlanceTodoItem("Milk", "5")]);

    testWidgets("a face per list: its name, how much is left, the first few things", (tester) async {
      await tester.pumpWidget(app(const GlanceListsFace(lists: [chores, shopping]), height: 160));
      expect(find.text("Chores"), findsOneWidget);
      expect(find.text("4 left"), findsOneWidget);
      expect(find.text("Dishes"), findsOneWidget);
      expect(find.text("Laundry"), findsOneWidget);
      expect(find.text("Beds"), findsNothing, reason: "the first few");
      expect(find.text("Milk"), findsNothing);
      expect(GlanceListsFace.facesOf(const [chores, shopping]), 2);

      await tester.pumpWidget(app(const GlanceListsFace(lists: [chores, shopping], face: 1), height: 160));
      await tester.pumpAndSettle();
      expect(find.text("Shopping"), findsOneWidget);
      expect(find.text("Milk"), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    test("no lists, no tile", () {
      expect(glanceTiles(lock: HaLockState.none).map((t) => t.id), isNot(contains("lists")));
    });

    testWidgets("in the view, OK marks the selected thing done; it stays, ticked", (tester) async {
      final marked = <String>[];
      await tester.pumpWidget(app(
        GlanceTodoView(
          lists: const [chores],
          onDone: (entity, item) async {
            marked.add("$entity ${item.uid}");
            return true;
          },
        ),
        width: 520,
        height: 400,
      ));
      await tester.pumpAndSettle();
      expect(find.text("Press OK on a thing to mark it done"), findsOneWidget);

      // The first thing has the selection; OK marks it done
      await tester.sendKeyEvent(LogicalKeyboardKey.select);
      await tester.pumpAndSettle();
      expect(marked, ["todo.chores 1"]);
      expect(find.text("Dishes"), findsOneWidget, reason: "it stays where it was");
      expect(find.byIcon(Icons.check_circle), findsOneWidget);
      expect(find.text("3 left"), findsOneWidget);

      // Again does nothing: it's done
      await tester.sendKeyEvent(LogicalKeyboardKey.select);
      await tester.pumpAndSettle();
      expect(marked, ["todo.chores 1"]);

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.sendKeyEvent(LogicalKeyboardKey.select);
      await tester.pumpAndSettle();
      expect(marked, ["todo.chores 1", "todo.chores 2"]);
    });

    testWidgets("when Home Assistant says no, the thing stays to do and the view says so", (tester) async {
      await tester.pumpWidget(app(
        GlanceTodoView(lists: const [chores], onDone: (_, _) async => false),
        width: 520,
        height: 400,
      ));
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.select);
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.check_circle), findsNothing);
      expect(find.text("Couldn't mark that done. Try again in a moment."), findsOneWidget);
    });

    testWidgets("without a way to mark things done, the lists are only read", (tester) async {
      await tester.pumpWidget(app(const GlanceTodoView(lists: [chores]), width: 520, height: 400));
      await tester.pumpAndSettle();
      expect(find.text("Dishes"), findsOneWidget);
      expect(find.text("Press OK on a thing to mark it done"), findsNothing);
      expect(FocusManager.instance.primaryFocus?.debugLabel, isNot("glance_todo_first"));
    });
  });
}
