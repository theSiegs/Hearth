import 'dart:io';

import 'package:flauncher/flauncher_channel.dart';
import 'package:flauncher/gradients.dart';
import 'package:flauncher/models/watch_next_program.dart';
import 'package:flauncher/models/weather_data.dart';
import 'package:flauncher/providers/apps_service.dart';
import 'package:flauncher/providers/calendars.dart';
import 'package:flauncher/providers/notifications_service.dart';
import 'package:flauncher/providers/settings_service.dart';
import 'package:flauncher/providers/wallpaper_service.dart';
import 'package:flauncher/providers/watch_next_service.dart';
import 'package:flauncher/widgets/glint/glint_faces.dart';
import 'package:flauncher/widgets/glint/glint_flip.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:provider/provider.dart';

import '../../mocks.dart';
import '../../mocks.mocks.dart';

/// Every Glint face drawn once, for a person to look at (not an assertion: text renders differently on each OS).
/// Run with GLINT_GALLERY=1 and --update-goldens; the picture lands in test/widgets/glint/gallery.png.
void main() {
  testWidgets("Glint faces gallery", (tester) async {
    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.reset);
    await _loadFonts(tester);

    final settings = MockSettingsService();
    when(settings.timeFormat).thenReturn("h:mm");
    when(settings.dateFormat).thenReturn("EEE, MMM d");
    final wallpaper = MockWallpaperService();
    when(wallpaper.gradient).thenReturn(FLauncherGradients.greatWhale);
    when(wallpaper.focusedAppColor).thenReturn(null);
    when(wallpaper.wallpaper).thenReturn(null);
    when(wallpaper.version).thenReturn(0);
    when(wallpaper.appColor(any)).thenAnswer((_) async => const Color(0xFFB0281E));
    final apps = MockAppsService();
    when(apps.getApp(any)).thenReturn(fakeApp(packageName: "com.example.tv", name: "Example TV"));
    final watchNext = MockWatchNextService();
    final ticker = GlintTicker(autoStart: false);
    addTearDown(ticker.dispose);

    final program = WatchNextProgram(
      id: 1,
      packageName: "com.example.tv",
      title: "The Long Night",
      description: "Season 2 · Episode 4",
      watchNextType: 0,
      lastEngagementTime: 0,
      playbackPosition: 1200,
      duration: 3000,
      intentUri: "",
      posterArtUri: "",
    );
    final now = DateTime.now();
    final event = CalendarEvent(
      calendarId: "1",
      calendarName: "Family",
      summary: "Piano lesson",
      start: now.add(const Duration(hours: 2)),
      end: now.add(const Duration(hours: 3)),
      allDay: false,
      color: 0xFF4F8EF7,
    );
    final weather = WeatherData(
      location: "Springfield",
      currentTemp: 61,
      currentConditionCode: 1,
      currentCondition: "Partly cloudy",
      todayMaxTemp: 66,
      todayMinTemp: 48,
      forecasts: const [],
      hourly: const [],
    );
    final note = NotificationItem(
      key: "k",
      packageName: "com.example.door",
      appLabel: "Doorbell",
      title: "Someone's at the front door",
      text: "Package delivered",
      isClearable: true,
    );

    Widget sized(double w, double h, Widget child) => SizedBox(width: w, height: h, child: child);
    await tester.pumpWidget(MultiProvider(
      providers: [
        Provider<FLauncherChannel>.value(value: FLauncherChannel()),
        ChangeNotifierProvider<SettingsService>.value(value: settings),
        ChangeNotifierProvider<WallpaperService>.value(value: wallpaper),
        ChangeNotifierProvider<AppsService>.value(value: apps),
        ChangeNotifierProvider<WatchNextService>.value(value: watchNext),
      ],
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        home: Material(
          child: Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(colors: [Color(0xFF6B4A2E), Color(0xFF2E3A4F)]),
            ),
            padding: const EdgeInsets.all(40),
            child: GlintTickerScope(
              ticker: ticker,
              child: Wrap(spacing: 8, runSpacing: 8, children: [
                sized(230, 230, const ClockFace()),
                sized(350, 230, ContinueWatchingFace(programs: [program])),
                sized(230, 230, WeatherFace(data: weather)),
                sized(230, 111, CalendarFace(events: [event])),
                sized(230, 111, NotificationsFace(items: [note, note])),
                sized(111, 111, const ProfileFace(name: "Alex")),
                sized(230, 111, AppFace(app: fakeApp(packageName: "com.example.tv", name: "Example TV"), category: null, wide: true)),
                sized(111, 111, AppFace(app: fakeApp(packageName: "com.example.b", name: "Music"), category: null)),
                sized(111, 111, const AllAppsFace()),
                sized(111, 111, const SettingsFace()),
                sized(111, 111, const SearchFace()),
              ]),
            ),
          ),
        ),
      ),
    ));
    await tester.pump(const Duration(milliseconds: 100));
    await expectLater(find.byType(MaterialApp), matchesGoldenFile("gallery.png"));
  }, skip: Platform.environment["GLINT_GALLERY"] != "1");
}

Future<void> _loadFonts(WidgetTester tester) async {
  await tester.runAsync(() async {
    final selawik = FontLoader("Selawik");
    for (final f in ["light", "regular", "semibold"]) {
      selawik.addFont(Future.value(ByteData.sublistView(File("assets/fonts/selawik_$f.ttf").readAsBytesSync())));
    }
    await selawik.load();
    final root = Platform.environment["FLUTTER_ROOT"];
    final dir = root == null ? null : Directory("$root/bin/cache/artifacts/material_fonts");
    if (dir != null && dir.existsSync()) {
      final roboto = FontLoader("Roboto");
      for (final f in dir.listSync().whereType<File>().where((f) => f.path.toLowerCase().contains("roboto-"))) {
        roboto.addFont(Future.value(ByteData.sublistView(f.readAsBytesSync())));
      }
      await roboto.load();
      final icons = FontLoader("MaterialIcons");
      final iconFile = File("$root/bin/cache/artifacts/material_fonts/materialicons-regular.otf");
      if (iconFile.existsSync()) {
        icons.addFont(Future.value(ByteData.sublistView(iconFile.readAsBytesSync())));
        await icons.load();
      }
    }
  });
}
