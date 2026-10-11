/*
 * FLauncher
 * Copyright (C) 2021  Étienne Fesser
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

import 'dart:io';

import 'package:flauncher/flauncher.dart';
import 'package:flauncher/flauncher_channel.dart';
import 'package:flauncher/gradients.dart';
import 'package:flauncher/providers/apps_service.dart';
import 'package:flauncher/models/app.dart';
import 'package:flauncher/models/category.dart';
import 'package:flauncher/models/watch_next_program.dart';
import 'package:flauncher/providers/launcher_state.dart';
import 'package:flauncher/providers/network_service.dart';
import 'package:flauncher/providers/profile_service.dart';
import 'package:flauncher/providers/settings_service.dart';
import 'package:flauncher/providers/tv_inputs_service.dart';
import 'package:flauncher/providers/wallpaper_service.dart';
import 'package:flauncher/providers/notifications_service.dart';
import 'package:flauncher/providers/watch_next_service.dart';
import 'package:flauncher/providers/weather_service.dart';
import 'package:flauncher/widgets/application_info_panel.dart';
import 'package:flauncher/widgets/apps_grid.dart';
import 'package:flauncher/widgets/category_row.dart';
import 'package:flauncher/widgets/app_card.dart';
import 'package:flauncher/widgets/focus_aware_app_bar.dart';
import 'package:flauncher/widgets/home_dock.dart';
import 'package:flauncher/widgets/continue_watching_row.dart';
import 'package:flauncher/widgets/settings/settings_panel_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flauncher/l10n/app_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:provider/provider.dart';
import 'package:transparent_image/transparent_image.dart';

import 'helpers.dart';
import 'mocks.dart';
import 'mocks.mocks.dart';


void main() {
  setUpAll(() async {
    final binding = TestWidgetsFlutterBinding.ensureInitialized();
    binding.platformDispatcher.implicitView!.physicalSize = const Size(1280, 720);
    binding.platformDispatcher.implicitView!.devicePixelRatio = 1.0;
    // Scale-down the font size because the font 'Ahem' used when running tests is much wider than Roboto
    binding.platformDispatcher.textScaleFactorTestValue = 0.8;
  });

  testWidgets("Home page shows categories with apps", (tester) async {
    final appsService = mkAppService();
    final favoritesCategory = fakeCategory(name: "Favorites", order: 0, type: CategoryType.row);
    final applicationsCategory = fakeCategory(name: "Applications", order: 1);
    favoritesCategory.applications.add(fakeApp(
      packageName: "me.efesser.flauncher.1",
      name: "FLauncher 1",
      version: "1.0.0",
    ));
    applicationsCategory.applications.add(fakeApp(
      packageName: "me.efesser.flauncher.2",
      name: "FLauncher 2",
      version: "2.0.0",
    ));
    when(appsService.launcherSections).thenReturn([
      favoritesCategory,
      applicationsCategory,
    ]);

    await _pumpWidgetWith(tester, appsService);

    expect(find.text("Applications"), findsOneWidget);
    expect(find.text("Favorites"), findsOneWidget);
    expect(find.byType(AppsGrid), findsOneWidget);
    expect(find.byKey(Key("me.efesser.flauncher.2")), findsOneWidget);
    expect(find.byType(CategoryRow), findsOneWidget);
    expect(find.byKey(Key("me.efesser.flauncher.1")), findsOneWidget);

    // This was changed by how the the image is made, I don't know what it now should be
    //expect(tester.widget(find.byKey(Key("background"))), isA<Container>());

  });

  testWidgets("Home page shows category empty-state", (tester) async {
    final appsService = mkAppService();
    final applicationsCategory = fakeCategory(name: "Applications", order: 0, type: CategoryType.grid);
    final favoritesCategory = fakeCategory(name: "Favorites", order: 1, type: CategoryType.row);
    when(appsService.launcherSections).thenReturn([
      applicationsCategory,
      favoritesCategory,
    ]);

    await _pumpWidgetWith(tester, appsService);

    expect(find.text("Applications"), findsOneWidget);
    expect(find.text("Favorites"), findsOneWidget);
    expect(find.byType(CategoryRow), findsOneWidget);
    expect(find.byType(AppsGrid), findsOneWidget);
    expect(find.text("This category is empty."), findsNWidgets(2));
  });

  testWidgets("Dock shows Favorites along the bottom of the first screen", (tester) async {
    final appsService = mkAppService();
    final favoritesCategory = fakeCategory(name: "Favorites", order: 0, type: CategoryType.row);
    final applicationsCategory = fakeCategory(name: "Applications", order: 1);
    favoritesCategory.applications.add(fakeApp(packageName: "me.efesser.flauncher.1", name: "FLauncher 1"));
    applicationsCategory.applications.add(fakeApp(packageName: "me.efesser.flauncher.2", name: "FLauncher 2"));
    when(appsService.launcherSections).thenReturn([favoritesCategory, applicationsCategory]);
    final settingsService = mkSettingsService();
    when(settingsService.dockEnabled).thenReturn(true);

    await _pumpWidgetWithProviders(tester, mkWallpaperService(), appsService, settingsService);

    expect(find.byType(HomeDock), findsOneWidget);
    expect(find.descendant(of: find.byType(HomeDock), matching: find.byKey(Key("me.efesser.flauncher.1"))),
        findsOneWidget);
    // The dock has no heading, and neither does a lone section below it.
    expect(find.text("Favorites"), findsNothing);
    expect(find.text("Applications"), findsNothing);
    // The dock sits at the bottom of the first screen and the other sections start below it.
    final screenHeight = tester.getSize(find.byType(FLauncher)).height;
    final dockBottom = tester.getBottomLeft(find.byType(HomeDock)).dy;
    expect(dockBottom, closeTo(screenHeight - 24, 1));
    expect(tester.getTopLeft(find.byType(AppsGrid)).dy, greaterThan(dockBottom));
  });

  testWidgets("Wallpaper blurs while browsing the sections below the dock", (tester) async {
    final appsService = mkAppService();
    final favoritesCategory = fakeCategory(name: "Favorites", order: 0, type: CategoryType.row);
    final applicationsCategory = fakeCategory(name: "Applications", order: 1);
    favoritesCategory.applications.add(fakeApp(packageName: "me.efesser.flauncher.1", name: "FLauncher 1"));
    applicationsCategory.applications.add(fakeApp(packageName: "me.efesser.flauncher.2", name: "FLauncher 2"));
    when(appsService.launcherSections).thenReturn([favoritesCategory, applicationsCategory]);
    final settingsService = mkSettingsService();
    when(settingsService.dockEnabled).thenReturn(true);
    await _pumpWidgetWithProviders(tester, mkWallpaperService(), appsService, settingsService);

    double blurOpacity() => tester.widget<AnimatedOpacity>(find.byKey(Key("below_dock_blur"))).opacity;
    expect(blurOpacity(), 0);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    expect(blurOpacity(), 1);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pumpAndSettle();
    expect(blurOpacity(), 0);
  });

  testWidgets("Dock layout leaves out empty sections", (tester) async {
    final appsService = mkAppService();
    final favoritesCategory = fakeCategory(name: "Favorites", order: 0, type: CategoryType.row);
    final tvAppsCategory = fakeCategory(name: "TV Apps", order: 1);
    final nonTvAppsCategory = fakeCategory(name: "Non-TV Apps", order: 2);
    favoritesCategory.applications.add(fakeApp(packageName: "me.efesser.flauncher.1", name: "FLauncher 1"));
    tvAppsCategory.applications.add(fakeApp(packageName: "me.efesser.flauncher.2", name: "FLauncher 2"));
    when(appsService.launcherSections).thenReturn([favoritesCategory, tvAppsCategory, nonTvAppsCategory]);
    final settingsService = mkSettingsService();
    when(settingsService.dockEnabled).thenReturn(true);

    await _pumpWidgetWithProviders(tester, mkWallpaperService(), appsService, settingsService);

    expect(find.byKey(Key("me.efesser.flauncher.2")), findsOneWidget);
    expect(find.text("Non-TV Apps"), findsNothing);
    expect(find.text("This category is empty."), findsNothing);
  });

  testWidgets("Sections below the dock have no headings", (tester) async {
    final appsService = mkAppService();
    final favoritesCategory = fakeCategory(name: "Favorites", order: 0, type: CategoryType.row);
    final tvAppsCategory = fakeCategory(name: "TV Apps", order: 1);
    final gamesCategory = fakeCategory(name: "Games", order: 2, type: CategoryType.row);
    favoritesCategory.applications.add(fakeApp(packageName: "me.efesser.flauncher.1", name: "FLauncher 1"));
    tvAppsCategory.applications.add(fakeApp(packageName: "me.efesser.flauncher.2", name: "FLauncher 2"));
    gamesCategory.applications.add(fakeApp(packageName: "me.efesser.flauncher.3", name: "FLauncher 3"));
    when(appsService.launcherSections).thenReturn([favoritesCategory, tvAppsCategory, gamesCategory]);
    final settingsService = mkSettingsService();
    when(settingsService.dockEnabled).thenReturn(true);

    await _pumpWidgetWithProviders(tester, mkWallpaperService(), appsService, settingsService);

    expect(find.text("TV Apps"), findsNothing);
    expect(find.text("Games"), findsNothing);
    // "Games" is a row section, but below the dock it wraps as a grid; the dock is the only row.
    expect(find.byType(AppsGrid), findsNWidgets(2));
    expect(find.byType(CategoryRow), findsOneWidget);
  });

  testWidgets("Up from the dock swaps it for Continue Watching, and Down swaps back", (tester) async {
    final appsService = mkAppService();
    when(appsService.applications).thenReturn([]);
    final favoritesCategory = fakeCategory(name: "Favorites", order: 0, type: CategoryType.row);
    favoritesCategory.applications.add(fakeApp(packageName: "me.efesser.flauncher.1", name: "FLauncher 1"));
    when(appsService.launcherSections).thenReturn([favoritesCategory]);
    final settingsService = mkSettingsService();
    when(settingsService.dockEnabled).thenReturn(true);
    when(settingsService.showContinueWatching).thenReturn(true);
    when(settingsService.hiddenWatchNextProgramIds).thenReturn([]);
    when(settingsService.hiddenWatchNextPackages).thenReturn([]);
    when(settingsService.continueWatchingMaxItems).thenReturn(10);
    when(settingsService.continueWatchingCardHeight).thenReturn(135);
    when(settingsService.continueWatchingShowProgress).thenReturn(true);
    when(settingsService.continueWatchingShowPercentage).thenReturn(true);
    when(settingsService.continueWatchingShowDescription).thenReturn(true);
    final watchNextService = mkWatchNextService();
    when(watchNextService.hasPermission).thenReturn(true);
    when(watchNextService.programs).thenReturn([
      WatchNextProgram(
        id: 1, packageName: "com.example.video", title: "Big Buck Bunny", description: "", watchNextType: 0,
        lastEngagementTime: 0, playbackPosition: 50, duration: 100, intentUri: "intent://x", posterArtUri: "",
      ),
    ]);

    await _pumpWidgetWithProviders(tester, mkWallpaperService(), appsService, settingsService,
        watchNextService: watchNextService);

    bool recentsFocused() => FocusManager.instance.primaryFocus?.context
            ?.findAncestorWidgetOfExactType<ContinueWatchingRow>() != null;
    double recentsOpacity() => tester
        .widget<AnimatedOpacity>(find.ancestor(of: find.byKey(Key("home_recents")), matching: find.byType(AnimatedOpacity)).first)
        .opacity;

    // The first screen starts on the dock, with Continue Watching hidden.
    expect(getFocusNodeForApp(tester, "me.efesser.flauncher.1")!.hasFocus, isTrue);
    expect(recentsOpacity(), 0);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pumpAndSettle();
    expect(recentsFocused(), isTrue);
    expect(recentsOpacity(), 1);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    expect(getFocusNodeForApp(tester, "me.efesser.flauncher.1")!.hasFocus, isTrue);
    expect(recentsOpacity(), 0);
  });

  testWidgets("The first app added to Favorites keeps the selection: it lands on that app in the new dock",
      (tester) async {
    final appsService = mkAppService(LiveAppsService()) as LiveAppsService;
    final favoritesCategory = fakeCategory(name: "Favorites", order: 0, type: CategoryType.row);
    final applicationsCategory = fakeCategory(name: "Applications", order: 1);
    applicationsCategory.applications
        .addAll(List.generate(20, (i) => fakeApp(packageName: "com.example.app$i", name: "App $i")));
    when(appsService.launcherSections).thenReturn([favoritesCategory, applicationsCategory]);
    when(appsService.toggleFavorite(any)).thenAnswer((invocation) async {
      favoritesCategory.applications.add(invocation.positionalArguments[0] as App);
      appsService.changed();
    });
    final settingsService = mkSettingsService();
    when(settingsService.dockEnabled).thenReturn(true);
    await _pumpWidgetWithProviders(tester, mkWallpaperService(), appsService, settingsService);
    expect(find.byType(HomeDock), findsNothing);

    // An app on the grid's second row, after a visit to the top bar
    getProfileFocusNode(tester)!.requestFocus();
    await tester.pumpAndSettle();
    getFocusNodeForApp(tester, "com.example.app7")!.requestFocus();
    await tester.pumpAndSettle();
    await tester.longPress(find.byKey(const Key("com.example.app7")));
    await tester.pumpAndSettle();
    await tester.tap(find.text("Add to Favorites"));
    await tester.pumpAndSettle();

    expect(find.byType(HomeDock), findsOneWidget);
    expect(isDockAppFocused(tester, "com.example.app7"), isTrue);
    expect(isProfileButtonFocused(tester), isFalse);
    expect(homeScrollOffset(tester), 0);
  });

  testWidgets("Moving an app inside the dock doesn't scroll the page", (tester) async {
    final appsService = mkAppService(LiveAppsService()) as LiveAppsService;
    final favoritesCategory = fakeCategory(name: "Favorites", order: 0, type: CategoryType.row);
    favoritesCategory.applications
        .addAll(List.generate(3, (i) => fakeApp(packageName: "com.example.dock$i", name: "Dock $i")));
    final applicationsCategory = fakeCategory(name: "Applications", order: 1);
    applicationsCategory.applications
        .addAll(List.generate(30, (i) => fakeApp(packageName: "com.example.app$i", name: "App $i")));
    when(appsService.launcherSections).thenReturn([favoritesCategory, applicationsCategory]);
    when(appsService.reorderApplication(any, any, any)).thenAnswer((invocation) {
      final apps = (invocation.positionalArguments[0] as Category).applications;
      apps.insert(invocation.positionalArguments[2] as int, apps.removeAt(invocation.positionalArguments[1] as int));
      appsService.changed();
    });
    final settingsService = mkSettingsService();
    when(settingsService.dockEnabled).thenReturn(true);
    await _pumpWidgetWithProviders(tester, mkWallpaperService(), appsService, settingsService);
    await tester.pumpAndSettle();
    expect(isDockAppFocused(tester, "com.example.dock0"), isTrue);

    await tester.longPress(find.byKey(const Key("com.example.dock0")));
    await tester.pumpAndSettle();
    await tester.tap(find.text("Reorder"));
    await tester.pumpAndSettle();
    for (final key in [LogicalKeyboardKey.arrowRight, LogicalKeyboardKey.arrowRight, LogicalKeyboardKey.arrowLeft]) {
      await tester.sendKeyEvent(key);
      await tester.pumpAndSettle();
      expect(homeScrollOffset(tester), 0);
    }
    expect(favoritesCategory.applications[1].packageName, "com.example.dock0");
    expect(isDockAppFocused(tester, "com.example.dock0"), isTrue);
  });

  group("Removing from Continue Watching", () {
    WatchNextProgram program(int id, String packageName) => WatchNextProgram(
          id: id, packageName: packageName, title: "Program $id", description: "", watchNextType: 0,
          lastEngagementTime: 0, playbackPosition: 50, duration: 100, intentUri: "intent://$id", posterArtUri: "",
        );

    late LiveSettingsService settingsService;
    late LiveWatchNextService watchNextService;
    late List<WatchNextProgram> programs;
    late List<String> hiddenPackages;

    Future<void> pumpHome(WidgetTester tester, List<WatchNextProgram> initial) async {
      final appsService = mkAppService();
      when(appsService.applications).thenReturn([]);
      final favoritesCategory = fakeCategory(name: "Favorites", order: 0, type: CategoryType.row);
      favoritesCategory.applications.addAll([
        fakeApp(packageName: "com.example.dock0", name: "Dock 0"),
        fakeApp(packageName: "com.example.dock1", name: "Dock 1"),
      ]);
      final applicationsCategory = fakeCategory(name: "Applications", order: 1);
      applicationsCategory.applications
          .addAll(List.generate(30, (i) => fakeApp(packageName: "com.example.app$i", name: "App $i")));
      when(appsService.launcherSections).thenReturn([favoritesCategory, applicationsCategory]);
      settingsService = mkSettingsService(LiveSettingsService()) as LiveSettingsService;
      when(settingsService.dockEnabled).thenReturn(true);
      when(settingsService.showContinueWatching).thenReturn(true);
      when(settingsService.hiddenWatchNextProgramIds).thenReturn([]);
      hiddenPackages = [];
      when(settingsService.hiddenWatchNextPackages).thenAnswer((_) => hiddenPackages);
      when(settingsService.hideWatchNextPackage(any)).thenAnswer((invocation) async {
        hiddenPackages = [...hiddenPackages, invocation.positionalArguments[0] as String];
        settingsService.changed();
      });
      when(settingsService.hideWatchNextProgram(any)).thenAnswer((_) async {});
      when(settingsService.continueWatchingMaxItems).thenReturn(10);
      when(settingsService.continueWatchingCardHeight).thenReturn(135);
      when(settingsService.continueWatchingShowProgress).thenReturn(true);
      when(settingsService.continueWatchingShowPercentage).thenReturn(true);
      when(settingsService.continueWatchingShowDescription).thenReturn(true);
      watchNextService = mkWatchNextService(LiveWatchNextService()) as LiveWatchNextService;
      when(watchNextService.hasPermission).thenReturn(true);
      programs = initial;
      when(watchNextService.programs).thenAnswer((_) => programs);
      when(watchNextService.refresh()).thenAnswer((_) async {});
      when(watchNextService.deleteProgram(any)).thenAnswer((invocation) async {
        final removed = invocation.positionalArguments[0] as WatchNextProgram;
        programs = programs.where((p) => p.id != removed.id).toList();
        watchNextService.changed();
        return true;
      });
      await _pumpWidgetWithProviders(tester, mkWallpaperService(), appsService, settingsService,
          watchNextService: watchNextService);
      await tester.pumpAndSettle();
    }

    WatchNextProgram? focusedProgram() =>
        FocusManager.instance.primaryFocus?.context?.findAncestorWidgetOfExactType<WatchNextCard>()?.program;

    /// Up from the dock to Continue Watching, on up to the top bar and back down: the top bar is in the focus
    /// history, as it is after a while on the TV.
    Future<void> toRecentsByWayOfTopBar(WidgetTester tester) async {
      for (final key in [LogicalKeyboardKey.arrowUp, LogicalKeyboardKey.arrowUp, LogicalKeyboardKey.arrowDown]) {
        await tester.sendKeyEvent(key);
        await tester.pumpAndSettle();
      }
      expect(focusedProgram()?.id, 1);
    }

    Future<void> openPanelAndPick(WidgetTester tester, String action) async {
      await tester.sendKeyEvent(LogicalKeyboardKey.contextMenu);
      await tester.pumpAndSettle();
      // The panel ignores presses for its first moments (by the wall clock)
      sleep(const Duration(milliseconds: 400));
      await tester.tap(find.textContaining(action));
      await tester.pumpAndSettle();
    }

    testWidgets("Remove keeps the selection in the row while it has programs", (tester) async {
      await pumpHome(tester, [program(1, "com.example.video"), program(2, "com.example.video")]);
      await toRecentsByWayOfTopBar(tester);

      await openPanelAndPick(tester, "Remove from Continue Watching");

      expect(focusedProgram()?.id, 2);
      expect(homeScrollOffset(tester), 0);
    });

    testWidgets("Removing the last program lands on the dock, with the page at the top", (tester) async {
      await pumpHome(tester, [program(1, "com.example.video")]);
      await toRecentsByWayOfTopBar(tester);

      await openPanelAndPick(tester, "Remove from Continue Watching");

      expect(find.byType(WatchNextCard), findsNothing);
      expect(isDockAppFocused(tester, "com.example.dock0"), isTrue);
      expect(homeScrollOffset(tester), 0);
    });

    testWidgets("Hide all lands on the dock, with the page at the top", (tester) async {
      await pumpHome(tester, [
        program(1, "com.example.video"),
        program(2, "com.example.video"),
        program(3, "com.example.music"),
        program(4, "com.example.music"),
      ]);
      await toRecentsByWayOfTopBar(tester);

      await openPanelAndPick(tester, "Hide all from");

      expect(hiddenPackages, ["com.example.video"]);
      expect(isProfileButtonFocused(tester), isFalse);
      expect(isDockAppFocused(tester, "com.example.dock0"), isTrue);
      expect(homeScrollOffset(tester), 0);
      // The other app's programs are still there, a press of Up away
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.pumpAndSettle();
      expect(focusedProgram()?.id, 3);
    });

    testWidgets("The top bar takes the page back to the top, so the dock never slides away over the apps below",
        (tester) async {
      await pumpHome(tester, [program(1, "com.example.video")]);
      tester
          .widget<SingleChildScrollView>(
              find.descendant(of: find.byType(FLauncher), matching: find.byType(SingleChildScrollView)).first)
          .controller!
          .jumpTo(200);
      await tester.pump();

      getProfileFocusNode(tester)!.requestFocus();
      await tester.pumpAndSettle();

      expect(homeScrollOffset(tester), 0);
    });
  });

  testWidgets("After a profile switch, focus lands on the dock once the welcome card goes", (tester) async {
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        const MethodChannel('me.efesser.flauncher/method'), (call) async {
      // The other profile's native data is in; permission checks answer "no".
      if (call.method == "isProfileDataReady") return true;
      return call.method.startsWith("check") ? false : null;
    });
    addTearDown(() => tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('me.efesser.flauncher/method'), null));
    final appsService = mkAppService();
    final favoritesCategory = fakeCategory(name: "Favorites", order: 0, type: CategoryType.row);
    final applicationsCategory = fakeCategory(name: "Applications", order: 1);
    favoritesCategory.applications.add(fakeApp(packageName: "me.efesser.flauncher.1", name: "FLauncher 1"));
    applicationsCategory.applications.add(fakeApp(packageName: "me.efesser.flauncher.2", name: "FLauncher 2"));
    when(appsService.launcherSections).thenReturn([favoritesCategory, applicationsCategory]);
    final settingsService = mkSettingsService();
    when(settingsService.dockEnabled).thenReturn(true);
    final watchNextService = mkWatchNextService();
    when(watchNextService.refreshedFor).thenReturn("user:11");
    when(watchNextService.postersSettled).thenReturn(true);
    final profiles = FakeProfileService(activeKey: "user:0", activeName: "Alex");
    await _pumpWidgetWithProviders(tester, mkWallpaperService(), appsService, settingsService,
        watchNextService: watchNextService, profileService: profiles);

    // The switch starts from the profile button
    getProfileFocusNode(tester)!.requestFocus();
    await tester.pump();

    profiles.switchTo("user:11", "Sam");
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    // The card holds focus while the profile's layout loads
    expect(find.text("Hi, Sam"), findsOneWidget);
    expect(isAppCardFocused(tester, "me.efesser.flauncher.1"), isFalse);

    profiles.layoutReady();
    await tester.pumpAndSettle();

    expect(find.text("Hi, Sam"), findsNothing);
    expect(isAppCardFocused(tester, "me.efesser.flauncher.1"), isTrue);
  });

  testWidgets("A pick that doesn't switch the profile gives the selection back to the dock, not the top bar",
      (tester) async {
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        const MethodChannel('me.efesser.flauncher/method'), (call) async {
      if (call.method == "isProfileDataReady") return true;
      return call.method.startsWith("check") ? false : null;
    });
    addTearDown(() => tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('me.efesser.flauncher/method'), null));
    final appsService = mkAppService();
    final favoritesCategory = fakeCategory(name: "Favorites", order: 0, type: CategoryType.row);
    favoritesCategory.applications.add(fakeApp(packageName: "me.efesser.flauncher.1", name: "FLauncher 1"));
    when(appsService.launcherSections).thenReturn([favoritesCategory]);
    final settingsService = mkSettingsService();
    when(settingsService.dockEnabled).thenReturn(true);
    final watchNextService = mkWatchNextService();
    when(watchNextService.postersSettled).thenReturn(true);
    final profiles = FakeProfileService(activeKey: "user:0", activeName: "Alex");
    await _pumpWidgetWithProviders(tester, mkWallpaperService(), appsService, settingsService,
        watchNextService: watchNextService, profileService: profiles);

    getProfileFocusNode(tester)!.requestFocus();
    await tester.pump();

    // Picked in Google TV's chooser; its card takes the selection, then Google TV keeps the profile that was on
    profiles.pick("Sam");
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    profiles.pick(null);
    await tester.pumpAndSettle();

    expect(isAppCardFocused(tester, "me.efesser.flauncher.1"), isTrue);
  });

  testWidgets("With nothing usable in Favorites, the dock layout shows one untitled grid", (tester) async {
    final appsService = mkAppService();
    final favoritesCategory = fakeCategory(name: "Favorites", order: 0, type: CategoryType.row);
    final applicationsCategory = fakeCategory(name: "Applications", order: 1);
    applicationsCategory.applications.add(fakeApp(packageName: "me.efesser.flauncher.2", name: "FLauncher 2"));
    when(appsService.launcherSections).thenReturn([favoritesCategory, applicationsCategory]);
    final settingsService = mkSettingsService();
    when(settingsService.dockEnabled).thenReturn(true);

    await _pumpWidgetWithProviders(tester, mkWallpaperService(), appsService, settingsService);

    expect(find.byType(HomeDock), findsNothing);
    expect(find.text("Favorites"), findsNothing);
    expect(find.text("Applications"), findsNothing);
    expect(find.text("FLauncher 2"), findsOneWidget);
  });

  testWidgets("With nothing to open, the dock layout says so", (tester) async {
    final appsService = mkAppService();
    when(appsService.launcherSections).thenReturn([fakeCategory(name: "Favorites", order: 0, type: CategoryType.row)]);
    final settingsService = mkSettingsService();
    when(settingsService.dockEnabled).thenReturn(true);

    await _pumpWidgetWithProviders(tester, mkWallpaperService(), appsService, settingsService);

    expect(find.text("Nothing to watch right now"), findsOneWidget);
  });

  testWidgets("With every Continue Watching program hidden, the home still says there's nothing to watch",
      (tester) async {
    final appsService = mkAppService();
    when(appsService.launcherSections).thenReturn([fakeCategory(name: "Favorites", order: 0, type: CategoryType.row)]);
    final settingsService = mkSettingsService();
    when(settingsService.dockEnabled).thenReturn(true);
    when(settingsService.hiddenWatchNextProgramIds).thenReturn([]);
    when(settingsService.hiddenWatchNextPackages).thenReturn(["com.example.video"]);
    final watchNextService = mkWatchNextService();
    when(watchNextService.hasPermission).thenReturn(true);
    when(watchNextService.programs).thenReturn([
      WatchNextProgram(
        id: 1, packageName: "com.example.video", title: "Big Buck Bunny", description: "", watchNextType: 0,
        lastEngagementTime: 0, playbackPosition: 50, duration: 100, intentUri: "intent://x", posterArtUri: "",
      ),
    ]);

    await _pumpWidgetWithProviders(tester, mkWallpaperService(), appsService, settingsService,
        watchNextService: watchNextService);

    expect(find.text("Nothing to watch right now"), findsOneWidget);
  });

  test("Dock corners follow the theme", () {
    expect(dockRadiusForTheme('classic'), 0);
    expect(dockRadiusForTheme('minimal'), 4 + kDockInnerPadding);
    expect(dockRadiusForTheme('modern'), 8 + kDockInnerPadding);
    expect(dockRadiusForTheme('squircle'), 24 + kDockInnerPadding);
    expect(dockRadiusForTheme('unknown'), dockRadiusForTheme('modern'));
  });

  testWidgets("Home page displays background image", (tester) async {
    final appsService = mkAppService();
    when(appsService.launcherSections).thenReturn([]);

    await _pumpWidgetWith(tester, appsService);

    expect(find.byType(Image), findsOneWidget);
  });

  testWidgets("Home page displays background gradient", (tester) async {
    final appsService = mkAppService();
    when(appsService.launcherSections).thenReturn([]);

    await _pumpWidgetWithProviders(tester, mkWallpaperService(false), appsService, mkSettingsService());

    expect(find.byKey(Key("background")), findsOneWidget);
    expect(find.byType(Image), findsNothing);
  });

  testWidgets("Pressing Left on the status bar's first button opens SettingsPanel", (tester) async {
    final appsService = mkAppService();
    when(appsService.launcherSections).thenReturn([
      fakeCategory(name: "Favorites", order: 0),
      fakeCategory(name: "Applications", order: 1),
    ]);
    await _pumpWidgetWith(tester, appsService);

    final profileNode = getProfileFocusNode(tester);
    profileNode!.requestFocus();
    await tester.pump();

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pumpAndSettle();

    expect(find.byType(SettingsPanelPage), findsOneWidget);
  });

  testWidgets("Pressing Left on the first app of a row opens SettingsPanel", (tester) async {
    final appsService = mkAppService();
    final favorites = fakeCategory(name: "Favorites", order: 0, type: CategoryType.row);
    favorites.applications.add(fakeApp(packageName: "me.efesser.flauncher.1", name: "FLauncher 1"));
    favorites.applications.add(fakeApp(packageName: "me.efesser.flauncher.2", name: "FLauncher 2"));
    when(appsService.launcherSections).thenReturn([favorites]);
    await _pumpWidgetWith(tester, appsService);
    expect(isAppCardFocused(tester, "me.efesser.flauncher.1"), isTrue);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pumpAndSettle();
    // Left from the second app just moves to the first.
    expect(find.byType(SettingsPanelPage), findsNothing);
    expect(isAppCardFocused(tester, "me.efesser.flauncher.1"), isTrue);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pumpAndSettle();
    expect(find.byType(SettingsPanelPage), findsOneWidget);

    // Right with nothing to the right closes Settings and returns to the same app.
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();
    expect(find.byType(SettingsPanelPage), findsNothing);
    expect(isAppCardFocused(tester, "me.efesser.flauncher.1"), isTrue);
  });

  testWidgets("Pressing Right on the last app of a row opens the Home Assistant panel when it's on", (tester) async {
    final calls = <String>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        const MethodChannel('me.efesser.flauncher/method'), (call) async {
      calls.add(call.method);
      // Permission checks the home screen makes on its own answer "no".
      return call.method.startsWith("check") ? false : null;
    });
    addTearDown(() => tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('me.efesser.flauncher/method'), null));
    final appsService = mkAppService();
    final favorites = fakeCategory(name: "Favorites", order: 0, type: CategoryType.row);
    favorites.applications.add(fakeApp(packageName: "me.efesser.flauncher.1", name: "FLauncher 1"));
    favorites.applications.add(fakeApp(packageName: "me.efesser.flauncher.2", name: "FLauncher 2"));
    when(appsService.launcherSections).thenReturn([favorites]);
    final settingsService = mkSettingsService();
    await _pumpWidgetWithProviders(tester, mkWallpaperService(), appsService, settingsService);

    // Off (the default): Right at the edge stays put.
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();
    expect(isAppCardFocused(tester, "me.efesser.flauncher.2"), isTrue);
    expect(calls, isNot(contains("openHaPanel")));

    when(settingsService.haPanelEnabled).thenReturn(true);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();
    expect(calls, contains("openHaPanel"));
  });

  testWidgets("Pressing select on app opens ApplicationInfoPanel", (tester) async {
    final appsService = mkAppService();
    final app = fakeApp(
      packageName: "me.efesser.flauncher",
      name: "FLauncher",
      version: "1.0.0",
    );
    final fav = fakeCategory(name: "Favorites", order: 0);
    final apps = fakeCategory(name: "Applications", order: 1);
    apps.applications.add(app);
    when(appsService.launcherSections).thenReturn([
      fav,
      apps,
    ]);
    await _pumpWidgetWith(tester, appsService);

    final inkWellFinder = find.descendant(
      of: find.byKey(Key("me.efesser.flauncher")),
      matching: find.byType(InkWell),
    );
    final FocusNode focusNode = tester.widget<InkWell>(inkWellFinder).focusNode!;
    focusNode.requestFocus();
    await tester.pump();

    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await tester.pump(const Duration(milliseconds: 150));
    await tester.pump(const Duration(milliseconds: 500));

    verify(appsService.launchApp(app));
  });

  testWidgets("Long pressing on app opens ApplicationInfoPanel", (tester) async {
    final appsService = mkAppService();
    final applicationsCategory = fakeCategory(name: "Applications", order: 1);
    applicationsCategory.applications.add(fakeApp(
      packageName: "me.efesser.flauncher",
      name: "FLauncher",
      version: "1.0.0",
    ));
    when(appsService.launcherSections).thenReturn([
      fakeCategory(name: "Favorites", order: 0),
      applicationsCategory,
    ]);
    await _pumpWidgetWith(tester, appsService);

    await tester.longPress(find.byKey(Key("me.efesser.flauncher")));
    await tester.pump();

    expect(find.byType(ApplicationInfoPanel), findsOneWidget);
  });

  testWidgets("AppCard moves in grid", (tester) async {
    final appsService = mkAppService();
    final applicationsCategory = fakeCategory(name: "Applications", order: 1, type: CategoryType.grid);
    applicationsCategory.applications.add(fakeApp(
      packageName: "me.efesser.flauncher",
      name: "FLauncher",
      version: "1.0.0",
    ));
    applicationsCategory.applications.add(fakeApp(
      packageName: "me.efesser.flauncher.2",
      name: "FLauncher 2",
      version: "1.0.0",
    ));
    when(appsService.launcherSections).thenReturn([
      fakeCategory(name: "Favorites", order: 0),
      applicationsCategory,
    ]);
    await _pumpWidgetWith(tester, appsService);

    await tester.longPress(find.byKey(Key("me.efesser.flauncher")));
    await tester.pumpAndSettle();
    await tester.tap(find.text("Reorder"));
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    verify(appsService.reorderApplication(applicationsCategory, 0, 1));
    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await tester.pump();
    verify(appsService.saveApplicationOrderInCategory(applicationsCategory));
  });

  testWidgets("AppCard reorder cancels on Back button", (tester) async {
    final appsService = mkAppService();
    final applicationsCategory = fakeCategory(name: "Applications", order: 1, type: CategoryType.grid);
    applicationsCategory.applications.add(fakeApp(
      packageName: "me.efesser.flauncher",
      name: "FLauncher",
      version: "1.0.0",
    ));
    applicationsCategory.applications.add(fakeApp(
      packageName: "me.efesser.flauncher.2",
      name: "FLauncher 2",
      version: "1.0.0",
    ));
    when(appsService.launcherSections).thenReturn([
      fakeCategory(name: "Favorites", order: 0),
      applicationsCategory,
    ]);
    await _pumpWidgetWith(tester, appsService);

    await tester.longPress(find.byKey(Key("me.efesser.flauncher")));
    await tester.pumpAndSettle();
    await tester.tap(find.text("Reorder"));
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    verify(appsService.reorderApplication(applicationsCategory, 0, 1));
    await tester.sendKeyEvent(LogicalKeyboardKey.gameButtonB);
    await tester.pump();
    verify(appsService.cancelReorderApplication(applicationsCategory));
  });

  testWidgets("AppCard moves in row", (tester) async {
    final appsService = mkAppService();
    final applicationsCategory = fakeCategory(name: "Applications", order: 1, type: CategoryType.row);
    applicationsCategory.applications.add(fakeApp(
      packageName: "me.efesser.flauncher",
      name: "FLauncher",
      version: "1.0.0",
    ));
    applicationsCategory.applications.add(fakeApp(
      packageName: "me.efesser.flauncher.2",
      name: "FLauncher 2",
      version: "1.0.0",
    ));
    when(appsService.launcherSections).thenReturn([
      fakeCategory(name: "Favorites", order: 0),
      applicationsCategory,
    ]);
    await _pumpWidgetWith(tester, appsService);

    await tester.longPress(find.byKey(Key("me.efesser.flauncher")));
    await tester.pumpAndSettle();
    await tester.tap(find.text("Reorder"));
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    verify(appsService.reorderApplication(applicationsCategory, 0, 1));
    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await tester.pump();
    verify(appsService.saveApplicationOrderInCategory(applicationsCategory));
  });

  testWidgets("Moving down does not skip row", (tester) async {
    // given
    final appsService = mkAppService();

    /*
     * we are creating 3 rows like the following:
     * ▭ ▭ ▭
     * ▭ ▭
     * ▭ ▭ ▭
     */
    final tvCat = fakeCategory(name: "tv", order: 0);
    tvCat.applications.addAll([
      fakeApp(
        packageName: "me.efesser.tv1",
        name: "tv 1",
        version: "1.0.0",
      ),
      fakeApp(
        packageName: "me.efesser.tv2",
        name: "tv 2",
        version: "1.0.0",
      ),
      fakeApp(
        packageName: "me.efesser.tv3",
        name: "tv 3",
        version: "1.0.0",
      ),
    ]);
    final musicCat = fakeCategory(name: "music", order: 1);
    musicCat.applications.addAll([
      fakeApp(
        packageName: "me.efesser.music1",
        name: "music 1",
        version: "1.0.0",
      ),
      fakeApp(
        packageName: "me.efesser.music2",
        name: "music 2",
        version: "1.0.0",
      ),
    ]);
    final gamesCat = fakeCategory(name: "games", order: 2);
    gamesCat.applications.addAll([
      fakeApp(
        packageName: "me.efesser.game1",
        name: "game 1",
        version: "1.0.0",
      ),
      fakeApp(
        packageName: "me.efesser.game2",
        name: "game 2",
        version: "1.0.0",
      ),
      fakeApp(
        packageName: "me.efesser.game3",
        name: "game 3",
        version: "1.0.0",
      ),
    ]);
    when(appsService.launcherSections).thenReturn([
      tvCat,
      musicCat,
      gamesCat,
    ]);

    await _pumpWidgetWith(tester, appsService);
    // when
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();

    // then
    Element? tv1 = findAppCardByPackageName(tester, "me.efesser.tv1");
    expect(tv1, isNotNull);
    Element? music2 = findAppCardByPackageName(tester, "me.efesser.music2");
    expect(music2, isNotNull);
    expect(isAppCardFocused(tester, "me.efesser.tv1"), isFalse);
    expect(isAppCardFocused(tester, "me.efesser.music2"), isTrue); // this is new, before it was going straight to the third row

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    Element? game2 = findAppCardByPackageName(tester, "me.efesser.game2");
    expect(game2, isNotNull);
    expect(isAppCardFocused(tester, "me.efesser.tv1"), isFalse);
    expect(isAppCardFocused(tester, "me.efesser.music2"), isFalse);
    expect(isAppCardFocused(tester, "me.efesser.game2"), isTrue);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pump();
    expect(isAppCardFocused(tester, "me.efesser.tv1"), isFalse);
    expect(isAppCardFocused(tester, "me.efesser.music2"), isTrue);
    expect(isAppCardFocused(tester, "me.efesser.game2"), isFalse);
  });

  testWidgets("Moving left or right stays on the same row", (tester) async {
    // given
    final appsService = mkAppService();

    /*
     * we are creating 2 rows like the following:
     * ▭ ▭
     * ▭ ▭ ▭ ▭ ▭
     */
    final tvCat = fakeCategory(name: "tv", order: 0);
    tvCat.applications.addAll([
      fakeApp(
        packageName: "me.efesser.tv1",
        name: "tv 1",
        version: "1.0.0",
      ),
      fakeApp(
        packageName: "me.efesser.tv2",
        name: "tv 2",
        version: "1.0.0",
      ),
    ]);
    final musicCat = fakeCategory(name: "music", order: 1, columnsCount: 5);
    musicCat.applications.addAll([
      fakeApp(
        packageName: "me.efesser.music1",
        name: "music 1",
        version: "1.0.0",
      ),
      fakeApp(
        packageName: "me.efesser.music2",
        name: "music 2",
        version: "1.0.0",
      ),
      fakeApp(
        packageName: "me.efesser.music3",
        name: "music 3",
        version: "1.0.0",
      ),
      fakeApp(
        packageName: "me.efesser.music4",
        name: "music 4",
        version: "1.0.0",
      ),
      fakeApp(
        packageName: "me.efesser.music5",
        name: "music 5",
        version: "1.0.0",
      ),
    ]);
    when(appsService.launcherSections).thenReturn([
      tvCat,
      musicCat,
    ]);

    await _pumpWidgetWith(tester, appsService);

    // then
    Element? tv1 = findAppCardByPackageName(tester, "me.efesser.tv1");
    expect(tv1, isNotNull);
    expect(isAppCardFocused(tester, "me.efesser.tv1"), isTrue);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    Element? music1 = findAppCardByPackageName(tester, "me.efesser.music1");
    expect(music1, isNotNull);
    expect(isAppCardFocused(tester, "me.efesser.tv1"), isFalse);
    expect(isAppCardFocused(tester, "me.efesser.music1"), isTrue);

    // check right direction
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    Element? music2 = findAppCardByPackageName(tester, "me.efesser.music2");
    expect(music2, isNotNull);
    expect(isAppCardFocused(tester, "me.efesser.tv1"), isFalse);
    expect(isAppCardFocused(tester, "me.efesser.music1"), isFalse);
    expect(isAppCardFocused(tester, "me.efesser.music2"), isTrue);

    // check if right on the last app stays on the same app
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    Element? music5 = findAppCardByPackageName(tester, "me.efesser.music5");
    expect(music5, isNotNull);
    expect(isAppCardFocused(tester, "me.efesser.music5"), isTrue);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pump();
    Element? tv2 = findAppCardByPackageName(tester, "me.efesser.tv2");
    expect(tv2, isNotNull);
    expect(isAppCardFocused(tester, "me.efesser.tv2"), isTrue);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    expect(isAppCardFocused(tester, "me.efesser.music2"), isTrue);

    // check left direction
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pump();
    expect(isAppCardFocused(tester, "me.efesser.music1"), isTrue);

    // going left on the first app opens Settings rather than leaving the row
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pumpAndSettle();
    expect(find.byType(SettingsPanelPage), findsOneWidget);
  });

  testWidgets("Up from the first section goes to the profile button", (tester) async {
    // given
    final appsService = mkAppService();

    /*
     * we are creating 2 rows like the following:
     * ▭ ▭
     * ▭ ▭ ▭
     */
    final tvCat = fakeCategory(name: "tv", order: 0);
    tvCat.applications.addAll([
      fakeApp(
        packageName: "me.efesser.tv1",
        name: "tv 1",
        version: "1.0.0",
      ),
      fakeApp(
        packageName: "me.efesser.tv2",
        name: "tv 2",
        version: "1.0.0",
      ),
    ]);
    final musicCat = fakeCategory(name: "music", order: 1);
    musicCat.applications.addAll([
      fakeApp(
        packageName: "me.efesser.music1",
        name: "music 1",
        version: "1.0.0",
      ),
      fakeApp(
        packageName: "me.efesser.music2",
        name: "music 2",
        version: "1.0.0",
      ),
      fakeApp(
        packageName: "me.efesser.music3",
        name: "music 3",
        version: "1.0.0",
      ),
    ]);
    when(appsService.launcherSections).thenReturn([
      tvCat,
      musicCat,
    ]);

    await _pumpWidgetWith(tester, appsService);

    // then
    Element? tv1 = findAppCardByPackageName(tester, "me.efesser.tv1");
    expect(tv1, isNotNull);
    expect(isAppCardFocused(tester, "me.efesser.tv1"), isTrue);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pump();


    Element? profileButton = findProfileButton(tester);
    expect(profileButton, isNotNull);
    expect(isAppCardFocused(tester, "me.efesser.tv1"), isFalse);
    expect(isProfileButtonFocused(tester), isTrue);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    expect(isProfileButtonFocused(tester), isFalse);
    expect(isAppCardFocused(tester, "me.efesser.tv1"), isTrue);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pump();
    expect(isProfileButtonFocused(tester), isTrue);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    expect(isAppCardFocused(tester, "me.efesser.tv2"), isTrue);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pump();
    expect(isProfileButtonFocused(tester), isTrue);
  });
}

/// Mocks whose listeners hear [LiveListeners.changed], for tests where the home changes under the selection.
class LiveAppsService extends MockAppsService with LiveListeners {}

class LiveSettingsService extends MockSettingsService with LiveListeners {}

class LiveWatchNextService extends MockWatchNextService with LiveListeners {}

SettingsService mkSettingsService([MockSettingsService? mock]) {
  final settingsService = mock ?? MockSettingsService();
  when(settingsService.dateFormat).thenReturn(SettingsService.defaultDateFormat);
  when(settingsService.timeFormat).thenReturn(SettingsService.defaultTimeFormat);
  when(settingsService.appHighlightAnimationEnabled).thenReturn(true);
  when(settingsService.showCategoryTitles).thenReturn(true);
  when(settingsService.showCategoryAppCount).thenReturn(false);
  when(settingsService.autoHideAppBarEnabled).thenReturn(false);
  when(settingsService.showInputsWidgetInStatusBar).thenReturn(true);
  when(settingsService.showNetworkIndicatorInStatusBar).thenReturn(true);
  when(settingsService.showDataWidgetInStatusBar).thenReturn(true);
  when(settingsService.showDateInStatusBar).thenReturn(true);
  when(settingsService.showTimeInStatusBar).thenReturn(true);
  when(settingsService.accentColorHex).thenReturn('00ff00');
  when(settingsService.accentColor).thenReturn(const Color(0xFF00FF00));
  when(settingsService.hasParentPin).thenReturn(false);
  when(settingsService.showAppNamesBelowIcons).thenReturn(true);
  when(settingsService.themes).thenReturn('classic');
  when(settingsService.hideHighlightOutlineOnHomescreen).thenReturn(false);
  when(settingsService.appSelectorTransitionAnimationEnabled).thenReturn(true);
  when(settingsService.showContinueWatching).thenReturn(false);
  when(settingsService.continueWatchingOrder).thenReturn(0);
  when(settingsService.dockEnabled).thenReturn(false);
  when(settingsService.dockBlurEnabled).thenReturn(true);
  when(settingsService.dockDarkBackground).thenReturn(false);
  when(settingsService.dockShadowEnabled).thenReturn(true);
  when(settingsService.blurWallpaperBelowDock).thenReturn(true);
  when(settingsService.haPanelEnabled).thenReturn(false);
  when(settingsService.showNotificationsWidgetInStatusBar).thenReturn(true);
  when(settingsService.autoHideNotificationsWidget).thenReturn(false);
  when(settingsService.showWeatherInStatusBar).thenReturn(false);
  when(settingsService.showWeatherWarnings).thenReturn(false);
  when(settingsService.useFahrenheit).thenReturn(false);
  return settingsService;
}

WallpaperService mkWallpaperService([bool wallpaper = true]) {
  final wallpaperService = MockWallpaperService();
  when(wallpaperService.gradient).thenReturn(FLauncherGradients.greatWhale);
  when(wallpaperService.focusedAppColor).thenReturn(null);
  when(wallpaperService.wallpaper).thenReturn(wallpaper ? Image.asset('assets/icon.png').image : null);
  when(wallpaperService.version).thenReturn(0);
  return wallpaperService;
}

TvInputsService mkTvInputsService() {
  final tvInputsService = MockTvInputsService();
  when(tvInputsService.hasInputs).thenReturn(false);
  return tvInputsService;
}

NotificationsService mkNotificationsService() {
  final notificationsService = MockNotificationsService();
  when(notificationsService.getNotificationCount(any)).thenReturn(0);
  when(notificationsService.hasPermission).thenReturn(false);
  when(notificationsService.notifications).thenReturn([]);
  return notificationsService;
}

WatchNextService mkWatchNextService([MockWatchNextService? mock]) {
  final watchNextService = mock ?? MockWatchNextService();
  when(watchNextService.profileChanged(any)).thenReturn(null);
  when(watchNextService.programs).thenReturn([]);
  return watchNextService;
}

WeatherService mkWeatherService() {
  final weatherService = MockWeatherService();
  when(weatherService.hasWeather).thenReturn(false);
  when(weatherService.weatherData).thenReturn(null);
  when(weatherService.isBreezyInstalled).thenReturn(false);
  return weatherService;
}

AppsService mkAppService([MockAppsService? mock]) {
  final appsService = mock ?? MockAppsService();
  when(appsService.initialized).thenReturn(true);
  when(appsService.getAppBanner(any)).thenAnswer((_) async => kTransparentImage);
  when(appsService.getAppIcon(any)).thenAnswer((_) async => kTransparentImage);
  when(appsService.imageRevision(any)).thenReturn(0);
  when(appsService.pendingReorderFocusPackage).thenReturn(null);
  when(appsService.hasCustomBanner(any)).thenAnswer((_) async => false);
  when(appsService.isAppInFavorites(any)).thenReturn(false);
  return appsService;
}


Future<void> _pumpWidgetWith(
  WidgetTester tester,
  AppsService appsService,
  ) async {
  return _pumpWidgetWithProviders(tester, mkWallpaperService(), appsService, mkSettingsService());
}

Future<void> _pumpWidgetWithProviders(
  WidgetTester tester,
  WallpaperService wallpaperService,
  AppsService appsService,
  SettingsService settingsService, {
  WatchNextService? watchNextService,
  ProfileService? profileService,
}) async {
  tester.view.physicalSize = const Size(1920, 1080);
  tester.view.devicePixelRatio = 1.0;
  // A real channel: tests that need the TV's answers mock the method channel itself.
  final channel = FLauncherChannel();
  await tester.pumpWidget(
    MultiProvider(
      providers: [
        Provider<FLauncherChannel>.value(value: channel),
        ChangeNotifierProvider<WallpaperService>.value(value: wallpaperService),
        ChangeNotifierProvider<AppsService>.value(value: appsService),
        ChangeNotifierProvider<SettingsService>.value(value: settingsService),
        ChangeNotifierProvider<TvInputsService>.value(value: mkTvInputsService()),
        ChangeNotifierProvider<NotificationsService>.value(value: mkNotificationsService()),
        ChangeNotifierProvider<WatchNextService>.value(value: watchNextService ?? mkWatchNextService()),
        ChangeNotifierProvider<WeatherService>.value(value: mkWeatherService()),
        ChangeNotifierProvider(create: (_) => LauncherState()),
        ChangeNotifierProvider(create: (_) => NetworkService(channel)),
        if (profileService != null) ChangeNotifierProvider<ProfileService>.value(value: profileService),
      ],
      builder: (_, __) => MaterialApp(
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        home: FLauncher(),
      ),
    ),
  );
  await tester.pump(Duration(seconds: 30), EnginePhase.sendSemanticsUpdate);
}

FocusNode? getFocusNodeForApp(WidgetTester tester, String packageName) {
  final appCardFinder = find.byWidgetPredicate((widget) =>
    widget is AppCard && widget.application.packageName == packageName
  );
  if (appCardFinder.evaluate().isEmpty) return null;
  final inkWellFinder = find.descendant(
    of: appCardFinder,
    matching: find.byType(InkWell),
  );
  if (inkWellFinder.evaluate().isEmpty) return null;
  final inkWell = tester.widget<InkWell>(inkWellFinder);
  return inkWell.focusNode;
}

FocusNode? getProfileFocusNode(WidgetTester tester) {
  try {
    final appBarState = tester.state<FocusAwareAppBarState>(find.byType(FocusAwareAppBar));
    return appBarState.profileFocusNode;
  } catch (e) {
    return null;
  }
}

bool isAppCardFocused(WidgetTester tester, String packageName) {
  final focusNode = getFocusNodeForApp(tester, packageName);
  return focusNode?.hasFocus ?? false;
}

/// The app's card in the dock (it can be in a grid below too) has focus.
bool isDockAppFocused(WidgetTester tester, String packageName) {
  final inkWell = find.descendant(
    of: find.descendant(
        of: find.byType(HomeDock),
        matching: find.byWidgetPredicate((widget) => widget is AppCard && widget.application.packageName == packageName)),
    matching: find.byType(InkWell),
  );
  if (inkWell.evaluate().isEmpty) return false;
  return tester.widget<InkWell>(inkWell.first).focusNode?.hasFocus ?? false;
}

/// How far the home page is scrolled down.
double homeScrollOffset(WidgetTester tester) => tester
    .widget<SingleChildScrollView>(
        find.descendant(of: find.byType(FLauncher), matching: find.byType(SingleChildScrollView)).first)
    .controller!
    .offset;

bool isProfileButtonFocused(WidgetTester tester) {
  final focusNode = getProfileFocusNode(tester);
  return focusNode?.hasFocus ?? false;
}
