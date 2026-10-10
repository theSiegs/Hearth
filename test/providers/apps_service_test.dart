import 'dart:io';

import 'package:flauncher/database.dart';
import 'package:flauncher/models/app.dart';
import 'package:flauncher/models/category.dart';
import 'package:flauncher/providers/apps_service.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../mock_channel.dart';
import '../mocks.mocks.dart';

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
  });

  group("removeCustomAppBanner", () {
    test("removes custom banner and deletes file if it exists", () async {
      final channel = mockChannelForAppsService();
      final database = MockFLauncherDatabase();
      final appsService = await _buildInitialisedAppsService(channel, database);

      // Create a temp file
      final tempFile =
          await File('${Directory.systemTemp.path}/test_banner.png').create();
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('custom_banner_test.app', tempFile.path);

      var notified = false;
      appsService.addListener(() {
        notified = true;
      });

      await appsService.removeCustomAppBanner('test.app');

      expect(await tempFile.exists(), isFalse);
      expect(prefs.containsKey('custom_banner_test.app'), isFalse);
      expect(notified, isTrue);
    });

    test("handles file deletion errors gracefully", () async {
      final channel = mockChannelForAppsService();
      final database = MockFLauncherDatabase();
      final appsService = await _buildInitialisedAppsService(channel, database);

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
          'custom_banner_test.app', '/invalid/path/that/does/not/exist.png');

      var notified = false;
      appsService.addListener(() {
        notified = true;
      });

      // Should not throw an exception
      await appsService.removeCustomAppBanner('test.app');

      expect(prefs.containsKey('custom_banner_test.app'), isFalse);
      expect(notified, isTrue);
    });

    test("works when custom banner path is null", () async {
      final channel = mockChannelForAppsService();
      final database = MockFLauncherDatabase();
      final appsService = await _buildInitialisedAppsService(channel, database);

      final prefs = await SharedPreferences.getInstance();

      var notified = false;
      appsService.addListener(() {
        notified = true;
      });

      // Should not throw an exception
      await appsService.removeCustomAppBanner('test.app');

      expect(prefs.containsKey('custom_banner_test.app'), isFalse);
      expect(notified, isTrue);
    });
  });

  group("setCustomAppBannerFromFile", () {
    const pathProvider = MethodChannel('plugins.flutter.io/path_provider');
    late Directory documents;
    late Directory pickerCache;

    setUp(() async {
      TestWidgetsFlutterBinding.ensureInitialized();
      documents = await Directory.systemTemp.createTemp('hearth_banner_documents');
      pickerCache = await Directory.systemTemp.createTemp('hearth_banner_picked');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(pathProvider, (_) async => documents.path);
    });

    tearDown(() async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(pathProvider, null);
      await documents.delete(recursive: true);
      await pickerCache.delete(recursive: true);
    });

    test("copies the picked image to documents under a safe name, deletes the pick and uses the copy", () async {
      final appsService = await _buildInitialisedAppsService(mockChannelForAppsService(), MockFLauncherDatabase());
      final picked = await File('${pickerCache.path}/picked.jpg').writeAsBytes([1, 2, 3]);

      var notified = false;
      appsService.addListener(() {
        notified = true;
      });

      final revision = appsService.imageRevision('com.example/tv app');
      await appsService.setCustomAppBannerFromFile('com.example/tv app', picked.path);

      final saved = File('${documents.path}/custom_banner_com.example_tv_app.png');
      expect(await saved.readAsBytes(), [1, 2, 3]);
      expect(await picked.exists(), isFalse);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('custom_banner_com.example/tv app'), saved.path);
      expect(await appsService.hasCustomBanner('com.example/tv app'), isTrue);
      expect(notified, isTrue);
      // Only this app's card reloads its image
      expect(appsService.imageRevision('com.example/tv app'), revision + 1);
      expect(appsService.imageRevision('other.app'), 0);
    });
  });

  group("AppsService Category Integration", () {
    test("loads categories with apps correctly", () async {
      final channel = mockChannelForAppsService();
      final database = MockFLauncherDatabase();

      final testApp1 = App(
          packageName: "app.1", name: "App 1", version: "1.0.0", hidden: false);
      final testApp2 = App(
          packageName: "app.2", name: "App 2", version: "1.0.0", hidden: false);
      final testApp3 = App(
          packageName: "app.3", name: "App 3", version: "1.0.0", hidden: false);
      final hiddenApp = App(
          packageName: "app.hidden",
          name: "Hidden App",
          version: "1.0.0",
          hidden: true);
      final suspendedApp = App(
          packageName: "app.suspended",
          name: "Suspended App",
          version: "1.0.0",
          hidden: false);

      final category = Category(id: 1, name: "Test Category", order: 0);

      when(channel.getApplications()).thenAnswer((_) => Future.value([
            {
              'packageName': 'app.1',
              'name': 'App 1',
              'version': '1.0.0',
              'sideloaded': false
            },
            {
              'packageName': 'app.2',
              'name': 'App 2',
              'version': '1.0.0',
              'sideloaded': false
            },
            {
              'packageName': 'app.3',
              'name': 'App 3',
              'version': '1.0.0',
              'sideloaded': false
            },
            {
              'packageName': 'app.hidden',
              'name': 'Hidden App',
              'version': '1.0.0',
              'sideloaded': false
            },
            {
              'packageName': 'app.suspended',
              'name': 'Suspended App',
              'version': '1.0.0',
              'sideloaded': false,
              'suspended': true
            },
          ]));
      when(channel.getApplicationIcon(any))
          .thenAnswer((_) => Future.value(Uint8List(0)));
      when(channel.getApplicationBanner(any))
          .thenAnswer((_) => Future.value(Uint8List(0)));

      when(database.getApplications()).thenAnswer(
          (_) => Future.value([testApp1, testApp2, testApp3, hiddenApp, suspendedApp]));
      when(database.getCategories())
          .thenAnswer((_) => Future.value([category]));
      when(database.getAppsCategories()).thenAnswer((_) => Future.value([
        AppCategory(categoryId: 1, appPackageName: "app.1", order: 1),
        AppCategory(categoryId: 1, appPackageName: "app.2", order: 0),
        AppCategory(categoryId: 1, appPackageName: "app.3", order: 2),
        AppCategory(categoryId: 1, appPackageName: "app.hidden", order: 3),
        AppCategory(categoryId: 1, appPackageName: "app.suspended", order: 4),
      ]));
      when(database.getLauncherSpacers()).thenAnswer((_) => Future.value([]));
      when(database.transaction(any)).thenAnswer(
          (realInvocation) => realInvocation.positionalArguments[0]());
      when(database.wasCreated).thenReturn(false);
      when(database.persistApps(any)).thenAnswer((_) => Future.value());
      when(database.deleteApps(any)).thenAnswer((_) => Future.value());

      final appsService = AppsService(channel, database, await SharedPreferences.getInstance());

      // Wait for initialization
      while (!appsService.initialized) {
        await Future.delayed(const Duration(milliseconds: 10));
      }

      final categories = appsService.categories;
      expect(categories.length, 1);
      expect(categories[0].name, "Test Category");

      final appsInCategory = categories[0].applications;
      // Hidden apps, and apps blocked in the current Google TV profile, are left out of categories
      expect(appsInCategory.length, 3);
      verifyNever(database.deleteApps(argThat(contains("app.suspended"))));

      // Should be ordered by the 'order' in AppCategory (0: app.2, 1: app.1, 2: app.3)
      expect(appsInCategory[0].packageName, "app.2");
      expect(appsInCategory[1].packageName, "app.1");
      expect(appsInCategory[2].packageName, "app.3");
    });

    test("an empty app list from Android is a failed read: no app (or its place in a section) is dropped", () async {
      final channel = mockChannelForAppsService();
      final database = MockFLauncherDatabase();
      final known = App(packageName: "app.1", name: "App 1", version: "1.0.0", hidden: false);

      when(channel.getApplications()).thenAnswer((_) => Future.value([]));
      when(database.getApplications()).thenAnswer((_) => Future.value([known]));
      when(database.getCategories())
          .thenAnswer((_) => Future.value([Category(id: 1, name: "Favorites", order: 0)]));
      when(database.getAppsCategories()).thenAnswer(
          (_) => Future.value([AppCategory(categoryId: 1, appPackageName: "app.1", order: 0)]));
      when(database.getLauncherSpacers()).thenAnswer((_) => Future.value([]));
      when(database.transaction(any)).thenAnswer((realInvocation) => realInvocation.positionalArguments[0]());
      when(database.wasCreated).thenReturn(false);
      when(database.persistApps(any)).thenAnswer((_) => Future.value());
      when(database.deleteApps(any)).thenAnswer((_) => Future.value());

      final appsService = AppsService(channel, database, await SharedPreferences.getInstance());
      while (!appsService.initialized) {
        await Future.delayed(const Duration(milliseconds: 10));
      }

      verifyNever(database.deleteApps(any));
    });

    test("saveApplicationOrderInCategory updates local categoryOrders map",
        () async {
      final channel = mockChannelForAppsService();
      final database = MockFLauncherDatabase();

      final testApp1 = App(
          packageName: "app.1", name: "App 1", version: "1.0.0", hidden: false);
      final testApp2 = App(
          packageName: "app.2", name: "App 2", version: "1.0.0", hidden: false);
      final category = Category(id: 1, name: "Test Category", order: 0);

      when(channel.getApplications()).thenAnswer((_) => Future.value([
            {
              'packageName': 'app.1',
              'name': 'App 1',
              'version': '1.0.0',
              'sideloaded': false
            },
            {
              'packageName': 'app.2',
              'name': 'App 2',
              'version': '1.0.0',
              'sideloaded': false
            },
          ]));
      when(channel.getApplicationIcon(any))
          .thenAnswer((_) => Future.value(Uint8List(0)));
      when(channel.getApplicationBanner(any))
          .thenAnswer((_) => Future.value(Uint8List(0)));

      when(database.getApplications())
          .thenAnswer((_) => Future.value([testApp1, testApp2]));
      when(database.getCategories())
          .thenAnswer((_) => Future.value([category]));
      when(database.getAppsCategories()).thenAnswer((_) => Future.value([
            AppCategory(categoryId: 1, appPackageName: "app.1", order: 0),
            AppCategory(categoryId: 1, appPackageName: "app.2", order: 1),
          ]));
      when(database.getLauncherSpacers()).thenAnswer((_) => Future.value([]));
      when(database.transaction(any)).thenAnswer(
          (realInvocation) => realInvocation.positionalArguments[0]());
      when(database.wasCreated).thenReturn(false);
      when(database.replaceAppsCategories(any))
          .thenAnswer((_) => Future.value());

      final appsService = AppsService(channel, database, await SharedPreferences.getInstance());

      while (!appsService.initialized) {
        await Future.delayed(const Duration(milliseconds: 10));
      }

      final categoryObj = appsService.categories.first;

      // Let's reorder them locally: move app 1 to the end
      appsService.reorderApplication(categoryObj, 0, 1);

      // Now save
      await appsService.saveApplicationOrderInCategory(categoryObj);

      // Verify that local categoryOrders reflect the new indices (app.2 order is 0, app.1 order is 1)
      expect(testApp2.categoryOrders[1], 0);
      expect(testApp1.categoryOrders[1], 1);
    });

    test("sortCategory sorts alphabetically case-insensitively", () async {
      final channel = mockChannelForAppsService();
      final database = MockFLauncherDatabase();

      final appB =
          App(packageName: "b", name: "bravo", version: "1.0", hidden: false);
      final appA =
          App(packageName: "a", name: "Alpha", version: "1.0", hidden: false);
      final appC =
          App(packageName: "c", name: "charlie", version: "1.0", hidden: false);

      final category = Category(
          id: 1,
          name: "Test Category",
          order: 0,
          sort: CategorySort.alphabetical);
      category.applications.addAll([appB, appC, appA]);

      final appsService = await _buildInitialisedAppsService(channel, database);
      appsService.sortCategory(category);

      expect(category.applications.map((a) => a.packageName).toList(),
          ["a", "b", "c"]);
    });

    test("default categories places TV Apps section before Non-TV Apps section",
        () async {
      final channel = mockChannelForAppsService();
      final database = MockFLauncherDatabase();

      when(database.insertCategory(any)).thenAnswer((inv) {
        return Future.value(1);
      });
      when(database.insertAppsCategories(any))
          .thenAnswer((_) => Future.value());

      final appsService = await _buildInitialisedAppsService(channel, database);
      await appsService.addCategory("TV Apps");
      await appsService.addCategory("Non-TV Apps");

      expect((appsService.launcherSections[0] as Category).name, "TV Apps");
      expect((appsService.launcherSections[1] as Category).name, "Non-TV Apps");
    });

    test("addCategory saves the section's type and layout, not just its name", () async {
      final channel = mockChannelForAppsService();
      final database = MockFLauncherDatabase();
      when(database.insertCategory(any)).thenAnswer((_) => Future.value(7));

      final appsService = await _buildInitialisedAppsService(channel, database);
      await appsService.addCategory("TV Apps", type: CategoryType.grid, columnsCount: 5, rowHeight: 120);

      final saved = verify(database.insertCategory(captureAny)).captured.single as CategoriesCompanion;
      expect(saved.type.value, CategoryType.grid);
      expect(saved.columnsCount.value, 5);
      expect(saved.rowHeight.value, 120);
      expect(saved.sort.value, CategorySort.manual);
    });

    test("addCategory passes a database failure on and adds nothing", () async {
      final channel = mockChannelForAppsService();
      final database = MockFLauncherDatabase();
      when(database.insertCategory(any)).thenAnswer((_) => Future.error(StateError("disk full")));

      final appsService = await _buildInitialisedAppsService(channel, database);

      await expectLater(appsService.addCategory("Movies"), throwsStateError);
      expect(appsService.launcherSections, isEmpty);
    });

    test("favoritesCategory is the category named Favorites, once there is one", () async {
      final channel = mockChannelForAppsService();
      final database = MockFLauncherDatabase();
      var nextId = 1;
      when(database.insertCategory(any)).thenAnswer((_) => Future.value(nextId++));

      final appsService = await _buildInitialisedAppsService(channel, database);
      await appsService.addCategory(AppsService.tvAppsName);
      expect(appsService.favoritesCategory, equals(null));

      await appsService.addCategory(AppsService.favoritesName);
      expect(appsService.favoritesCategory?.id, 2);
      expect((await appsService.getOrCreateFavoritesCategory()).id, 2);
    });

    test(
        "newly installed app missing AppsCategories row receives category assignment",
        () async {
      final channel = mockChannelForAppsService();
      final database = MockFLauncherDatabase();

      final orderedApp = App(
          packageName: "app.ordered",
          name: "Ordered App",
          version: "1.0.0",
          hidden: false);
      final orphanApp = App(
          packageName: "app.orphan",
          name: "Orphan App",
          version: "1.0.0",
          hidden: false);
      final tvCategory =
          Category(id: 1, name: "TV Apps", order: 0, sort: CategorySort.manual);

      when(channel.getApplications()).thenAnswer((_) => Future.value([
            {
              'packageName': 'app.ordered',
              'name': 'Ordered App',
              'version': '1.0.0',
              'sideloaded': false
            },
            {
              'packageName': 'app.orphan',
              'name': 'Orphan App',
              'version': '1.0.0',
              'sideloaded': false
            },
          ]));
      when(channel.getApplicationIcon(any))
          .thenAnswer((_) => Future.value(Uint8List(0)));
      when(channel.getApplicationBanner(any))
          .thenAnswer((_) => Future.value(Uint8List(0)));

      int getAppsCallCount = 0;
      when(database.getApplications()).thenAnswer((_) {
        getAppsCallCount++;
        if (getAppsCallCount == 1) {
          return Future.value([orderedApp]);
        }
        return Future.value([orderedApp, orphanApp]);
      });
      when(database.getCategories())
          .thenAnswer((_) => Future.value([tvCategory]));
      when(database.getAppsCategories()).thenAnswer((_) => Future.value([
            AppCategory(categoryId: 1, appPackageName: "app.ordered", order: 0),
          ]));
      when(database.getLauncherSpacers()).thenAnswer((_) => Future.value([]));
      when(database.transaction(any)).thenAnswer(
          (realInvocation) => realInvocation.positionalArguments[0]());
      when(database.persistApps(any)).thenAnswer((_) => Future.value());
      when(database.wasCreated).thenReturn(false);
      when(database.nextAppCategoryOrder(1)).thenAnswer((_) => Future.value(1));
      when(database.insertAppsCategories(any))
          .thenAnswer((_) => Future.value());

      final appsService = AppsService(channel, database, await SharedPreferences.getInstance());

      while (!appsService.initialized) {
        await Future.delayed(const Duration(milliseconds: 10));
      }

      expect(appsService.initialized, isTrue);

      final tvApps = appsService.categories.first;
      expect(tvApps.applications.map((app) => app.packageName).toList(),
          ["app.ordered", "app.orphan"]);
      expect(orderedApp.categoryOrders[1], 0);
      expect(orphanApp.categoryOrders[1], 1);

      final captured =
          verify(database.insertAppsCategories(captureAny)).captured;
      expect(captured.length, 1);
      final batch = captured.first as List<AppsCategoriesCompanion>;
      expect(batch.length, 1);
      expect(batch.first.appPackageName.value, "app.orphan");
      expect(batch.first.order.value, 1);
    });

    test(
        "existing app with zero categories (removed by user) is not re-added on initialization",
        () async {
      final channel = mockChannelForAppsService();
      final database = MockFLauncherDatabase();

      final orderedApp = App(
          packageName: "app.ordered",
          name: "Ordered App",
          version: "1.0.0",
          hidden: false);
      final removedApp = App(
          packageName: "app.removed",
          name: "Removed App",
          version: "1.0.0",
          hidden: false);
      final tvCategory =
          Category(id: 1, name: "TV Apps", order: 0, sort: CategorySort.manual);

      when(channel.getApplications()).thenAnswer((_) => Future.value([
            {
              'packageName': 'app.ordered',
              'name': 'Ordered App',
              'version': '1.0.0',
              'sideloaded': false
            },
            {
              'packageName': 'app.removed',
              'name': 'Removed App',
              'version': '1.0.0',
              'sideloaded': false
            },
          ]));
      when(channel.getApplicationIcon(any))
          .thenAnswer((_) => Future.value(Uint8List(0)));
      when(channel.getApplicationBanner(any))
          .thenAnswer((_) => Future.value(Uint8List(0)));

      // Both apps already existed in the database before persistApps
      when(database.getApplications())
          .thenAnswer((_) => Future.value([orderedApp, removedApp]));
      when(database.getCategories())
          .thenAnswer((_) => Future.value([tvCategory]));
      when(database.getAppsCategories()).thenAnswer((_) => Future.value([
            AppCategory(categoryId: 1, appPackageName: "app.ordered", order: 0),
          ]));
      when(database.getLauncherSpacers()).thenAnswer((_) => Future.value([]));
      when(database.transaction(any)).thenAnswer(
          (realInvocation) => realInvocation.positionalArguments[0]());
      when(database.persistApps(any)).thenAnswer((_) => Future.value());
      when(database.wasCreated).thenReturn(false);

      final appsService = AppsService(channel, database, await SharedPreferences.getInstance());

      while (!appsService.initialized) {
        await Future.delayed(const Duration(milliseconds: 10));
      }

      expect(appsService.initialized, isTrue);

      final tvApps = appsService.categories.first;
      expect(tvApps.applications.map((app) => app.packageName).toList(),
          ["app.ordered"]);
      expect(orderedApp.categoryOrders[1], 0);
      expect(removedApp.categoryOrders.containsKey(1), isFalse);
      verifyNever(database.insertAppsCategories(any));
    });

    test(
        "newly installed hidden app is categorized in database but not shown in category",
        () async {
      final channel = mockChannelForAppsService();
      final database = MockFLauncherDatabase();

      final visibleApp = App(
          packageName: "app.visible",
          name: "Visible App",
          version: "1.0.0",
          hidden: false);
      final hiddenOrphan = App(
          packageName: "app.hidden",
          name: "Hidden App",
          version: "1.0.0",
          hidden: true);
      final tvCategory =
          Category(id: 1, name: "TV Apps", order: 0, sort: CategorySort.manual);

      when(channel.getApplications()).thenAnswer((_) => Future.value([
            {
              'packageName': 'app.visible',
              'name': 'Visible App',
              'version': '1.0.0',
              'sideloaded': false
            },
            {
              'packageName': 'app.hidden',
              'name': 'Hidden App',
              'version': '1.0.0',
              'sideloaded': false
            },
          ]));
      when(channel.getApplicationIcon(any))
          .thenAnswer((_) => Future.value(Uint8List(0)));
      when(channel.getApplicationBanner(any))
          .thenAnswer((_) => Future.value(Uint8List(0)));

      int getAppsCallCount = 0;
      when(database.getApplications()).thenAnswer((_) {
        getAppsCallCount++;
        if (getAppsCallCount == 1) {
          return Future.value([visibleApp]);
        }
        return Future.value([visibleApp, hiddenOrphan]);
      });
      when(database.getCategories())
          .thenAnswer((_) => Future.value([tvCategory]));
      when(database.getAppsCategories()).thenAnswer((_) => Future.value([
            AppCategory(categoryId: 1, appPackageName: "app.visible", order: 0),
          ]));
      when(database.getLauncherSpacers()).thenAnswer((_) => Future.value([]));
      when(database.transaction(any)).thenAnswer(
          (realInvocation) => realInvocation.positionalArguments[0]());
      when(database.persistApps(any)).thenAnswer((_) => Future.value());
      when(database.wasCreated).thenReturn(false);
      when(database.nextAppCategoryOrder(1)).thenAnswer((_) => Future.value(1));
      when(database.insertAppsCategories(any))
          .thenAnswer((_) => Future.value());

      final appsService = AppsService(channel, database, await SharedPreferences.getInstance());
      while (!appsService.initialized) {
        await Future.delayed(const Duration(milliseconds: 10));
      }

      final tvApps = appsService.categories.first;
      expect(tvApps.applications.length, 1);
      expect(tvApps.applications.first.packageName, "app.visible");
      expect(hiddenOrphan.categoryOrders[1], 1);
      verify(database.insertAppsCategories(any)).called(1);
    });

    test("multiple newly installed apps receive deterministic non-conflicting orders",
        () async {
      final channel = mockChannelForAppsService();
      final database = MockFLauncherDatabase();

      final orphanB = App(
          packageName: "app.b", name: "Bravo", version: "1.0.0", hidden: false);
      final orphanA = App(
          packageName: "app.a", name: "Alpha", version: "1.0.0", hidden: false);
      final tvCategory =
          Category(id: 1, name: "TV Apps", order: 0, sort: CategorySort.manual);

      when(channel.getApplications()).thenAnswer((_) => Future.value([
            {
              'packageName': 'app.a',
              'name': 'Alpha',
              'version': '1.0.0',
              'sideloaded': false
            },
            {
              'packageName': 'app.b',
              'name': 'Bravo',
              'version': '1.0.0',
              'sideloaded': false
            },
          ]));
      when(channel.getApplicationIcon(any))
          .thenAnswer((_) => Future.value(Uint8List(0)));
      when(channel.getApplicationBanner(any))
          .thenAnswer((_) => Future.value(Uint8List(0)));

      int getAppsCallCount = 0;
      when(database.getApplications()).thenAnswer((_) {
        getAppsCallCount++;
        if (getAppsCallCount == 1) {
          return Future.value([]);
        }
        return Future.value([orphanA, orphanB]);
      });
      when(database.getCategories())
          .thenAnswer((_) => Future.value([tvCategory]));
      when(database.getAppsCategories()).thenAnswer((_) => Future.value([]));
      when(database.getLauncherSpacers()).thenAnswer((_) => Future.value([]));
      when(database.transaction(any)).thenAnswer(
          (realInvocation) => realInvocation.positionalArguments[0]());
      when(database.persistApps(any)).thenAnswer((_) => Future.value());
      when(database.wasCreated).thenReturn(false);
      when(database.nextAppCategoryOrder(1)).thenAnswer((_) => Future.value(0));
      when(database.insertAppsCategories(any))
          .thenAnswer((_) => Future.value());

      final appsService = AppsService(channel, database, await SharedPreferences.getInstance());
      while (!appsService.initialized) {
        await Future.delayed(const Duration(milliseconds: 10));
      }

      expect(orphanA.categoryOrders[1], 0);
      expect(orphanB.categoryOrders[1], 1);
      expect(
          appsService.categories.first.applications
              .map((app) => app.packageName)
              .toList(),
          ["app.a", "app.b"]);
    });

    test("newly installed sideloaded app is assigned to Non-TV Apps category",
        () async {
      final channel = mockChannelForAppsService();
      final database = MockFLauncherDatabase();

      final sideloadedApp = App(
          packageName: "app.sideloaded",
          name: "Sideloaded",
          version: "1.0.0",
          hidden: false);
      final tvCategory =
          Category(id: 1, name: "TV Apps", order: 0, sort: CategorySort.manual);
      final nonTvCategory = Category(
          id: 2, name: "Non-TV Apps", order: 1, sort: CategorySort.manual);

      when(channel.getApplications()).thenAnswer((_) => Future.value([
            {
              'packageName': 'app.sideloaded',
              'name': 'Sideloaded',
              'version': '1.0.0',
              'sideloaded': true
            },
          ]));
      when(channel.getApplicationIcon(any))
          .thenAnswer((_) => Future.value(Uint8List(0)));
      when(channel.getApplicationBanner(any))
          .thenAnswer((_) => Future.value(Uint8List(0)));

      int getAppsCallCount = 0;
      when(database.getApplications()).thenAnswer((_) {
        getAppsCallCount++;
        if (getAppsCallCount == 1) {
          return Future.value([]);
        }
        return Future.value([sideloadedApp]);
      });
      when(database.getCategories())
          .thenAnswer((_) => Future.value([tvCategory, nonTvCategory]));
      when(database.getAppsCategories()).thenAnswer((_) => Future.value([]));
      when(database.getLauncherSpacers()).thenAnswer((_) => Future.value([]));
      when(database.transaction(any)).thenAnswer(
          (realInvocation) => realInvocation.positionalArguments[0]());
      when(database.persistApps(any)).thenAnswer((_) => Future.value());
      when(database.wasCreated).thenReturn(false);
      when(database.nextAppCategoryOrder(2)).thenAnswer((_) => Future.value(0));
      when(database.insertAppsCategories(any))
          .thenAnswer((_) => Future.value());

      final appsService = AppsService(channel, database, await SharedPreferences.getInstance());
      while (!appsService.initialized) {
        await Future.delayed(const Duration(milliseconds: 10));
      }

      final nonTvApps =
          appsService.categories.firstWhere((c) => c.name == "Non-TV Apps");
      expect(nonTvApps.applications.map((app) => app.packageName).toList(),
          ["app.sideloaded"]);
      expect(sideloadedApp.categoryOrders[2], 0);
    });

    test("sortCategory does not throw when manual order is missing", () async {
      final channel = mockChannelForAppsService();
      final database = MockFLauncherDatabase();

      final appWithOrder = App(
          packageName: "app.ordered",
          name: "Ordered",
          version: "1.0.0",
          hidden: false);
      appWithOrder.categoryOrders[1] = 0;
      final appWithoutOrder = App(
          packageName: "app.missing",
          name: "Missing",
          version: "1.0.0",
          hidden: false);
      final category =
          Category(id: 1, name: "TV Apps", order: 0, sort: CategorySort.manual);
      category.applications.addAll([appWithoutOrder, appWithOrder]);

      final appsService = await _buildInitialisedAppsService(channel, database);
      appsService.sortCategory(category);

      expect(category.applications.first.packageName, "app.ordered");
      expect(category.applications.last.packageName, "app.missing");
    });

    test("sortCategory last-used ordering is unchanged", () async {
      final channel = mockChannelForAppsService();
      final database = MockFLauncherDatabase();

      final older = App(
          packageName: "older", name: "Older", version: "1.0.0", hidden: false);
      older.lastLaunchedAt = DateTime(2024, 1, 1);
      final newer = App(
          packageName: "newer", name: "Newer", version: "1.0.0", hidden: false);
      newer.lastLaunchedAt = DateTime(2025, 1, 1);
      final category = Category(
          id: 1, name: "Recent", order: 0, sort: CategorySort.lastUsed);
      category.applications.addAll([older, newer]);

      final appsService = await _buildInitialisedAppsService(channel, database);
      appsService.sortCategory(category);

      expect(category.applications.map((app) => app.packageName).toList(),
          ["newer", "older"]);
    });

    test(
        "existing install with Non-TV Apps above TV Apps is reordered so TV Apps is on top",
        () async {
      final channel = mockChannelForAppsService();
      final database = MockFLauncherDatabase();

      final nonTvCat = Category(id: 1, name: "Non-TV Apps", order: 0);
      final tvCat = Category(id: 2, name: "TV Apps", order: 1);

      when(channel.getApplications()).thenAnswer((_) => Future.value([]));
      when(channel.getApplicationIcon(any))
          .thenAnswer((_) => Future.value(Uint8List(0)));
      when(channel.getApplicationBanner(any))
          .thenAnswer((_) => Future.value(Uint8List(0)));
      when(database.getApplications()).thenAnswer((_) => Future.value([]));
      when(database.getAppsCategories()).thenAnswer((_) => Future.value([]));
      when(database.getCategories())
          .thenAnswer((_) => Future.value([nonTvCat, tvCat]));
      when(database.getLauncherSpacers()).thenAnswer((_) => Future.value([]));
      when(database.transaction(any)).thenAnswer(
          (realInvocation) => realInvocation.positionalArguments[0]());
      when(database.persistApps(any)).thenAnswer((_) => Future.value());
      when(database.updateCategories(any)).thenAnswer((_) => Future.value());
      when(database.updateSpacers(any)).thenAnswer((_) => Future.value());
      when(database.updateCategory(any, any))
          .thenAnswer((_) async {});
      when(database.wasCreated).thenReturn(false);

      final appsService = AppsService(channel, database, await SharedPreferences.getInstance());
      while (!appsService.initialized) {
        await Future.delayed(const Duration(milliseconds: 10));
      }

      expect((appsService.launcherSections[0] as Category).name, "TV Apps");
      expect((appsService.launcherSections[1] as Category).name, "Non-TV Apps");
    });
  });

  group("app changes from the system", () {
    late MockFLauncherChannel channel;
    late MockFLauncherDatabase database;
    late void Function(Map<String, dynamic>) onAppsChanged;
    final systemApp = {'packageName': 'app.tv', 'name': 'TV App', 'version': '1.0.0', 'sideloaded': false};

    Future<AppsService> build({bool hidden = false}) async {
      channel = mockChannelForAppsService();
      database = MockFLauncherDatabase();
      final app = App(packageName: 'app.tv', name: 'TV App', version: '1.0.0', hidden: hidden);
      when(channel.getApplications()).thenAnswer((_) async => [systemApp]);
      when(channel.getApplicationIcon(any)).thenAnswer((_) async => Uint8List(0));
      when(channel.getApplicationBanner(any)).thenAnswer((_) async => Uint8List(0));
      when(channel.addAppsChangedListener(any)).thenAnswer((invocation) {
        onAppsChanged = invocation.positionalArguments[0];
        return const Stream<void>.empty().listen(null);
      });
      when(database.getApplications()).thenAnswer((_) async => [app]);
      when(database.getCategories())
          .thenAnswer((_) async => [Category(id: 1, name: AppsService.tvAppsName, order: 0)]);
      when(database.getAppsCategories())
          .thenAnswer((_) async => [AppCategory(categoryId: 1, appPackageName: 'app.tv', order: 0)]);
      when(database.getLauncherSpacers()).thenAnswer((_) async => []);
      when(database.transaction(any)).thenAnswer((invocation) => invocation.positionalArguments[0]());
      when(database.persistApps(any)).thenAnswer((_) async {});
      when(database.wasCreated).thenReturn(false);
      final appsService = AppsService(channel, database, await SharedPreferences.getInstance());
      while (!appsService.initialized) {
        await Future.delayed(const Duration(milliseconds: 10));
      }
      return appsService;
    }

    test("an updated app takes the old one's place in its categories", () async {
      final appsService = await build();
      final before = appsService.categories.single.applications.single;

      onAppsChanged({'action': 'PACKAGE_CHANGED', 'activityInfo': {...systemApp, 'version': '2.0.0'}});
      await pumpEventQueue();

      final after = appsService.categories.single.applications.single;
      expect(after, isNot(same(before)));
      expect(after.version, '2.0.0');
      expect(after.categoryOrders, {1: 0});
      expect(appsService.getApp('app.tv'), same(after));
    });

    test("a hidden app stays out of its rows after an update", () async {
      final appsService = await build(hidden: true);
      expect(appsService.categories.single.applications, isEmpty);

      onAppsChanged({'action': 'PACKAGE_CHANGED', 'activityInfo': {...systemApp, 'version': '2.0.0'}});
      await pumpEventQueue();

      expect(appsService.categories.single.applications, isEmpty);
      expect(appsService.getApp('app.tv')!.version, '2.0.0');
      expect(appsService.getApp('app.tv')!.hidden, isTrue);
    });

    test("apps coming back on external storage keep their place too", () async {
      final appsService = await build();

      onAppsChanged({
        'action': 'PACKAGES_AVAILABLE',
        'activitiesInfo': [
          {...systemApp, 'version': '3.0.0'}
        ],
      });
      await pumpEventQueue();

      expect(appsService.categories.single.applications.map((a) => a.version), ['3.0.0']);
      expect(appsService.getApp('app.tv')!.version, '3.0.0');
    });
  });
}

Future<AppsService> _buildInitialisedAppsService(
  MockFLauncherChannel channel,
  MockFLauncherDatabase database,
) async {
  when(channel.getApplications()).thenAnswer((_) => Future.value([]));
  when(channel.getApplicationIcon(any))
      .thenAnswer((_) => Future.value(Uint8List(0)));
  when(channel.getApplicationBanner(any))
      .thenAnswer((_) => Future.value(Uint8List(0)));
  when(database.getApplications()).thenAnswer((_) => Future.value([]));
  when(database.getAppsCategories()).thenAnswer((_) => Future.value([]));
  when(database.getCategories()).thenAnswer((_) => Future.value([]));
  when(database.getLauncherSpacers()).thenAnswer((_) => Future.value([]));
  when(database.transaction(any))
      .thenAnswer((realInvocation) => realInvocation.positionalArguments[0]());
  when(database.wasCreated).thenReturn(false);
  final appsService = AppsService(channel, database, await SharedPreferences.getInstance());

  while (!appsService.initialized) {
    await Future.delayed(const Duration(milliseconds: 10));
  }

  await untilCalled(channel.addAppsChangedListener(any));
  clearInteractions(channel);
  clearInteractions(database);
  return appsService;
}
