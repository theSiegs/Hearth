import 'dart:convert';
import 'dart:io';

import 'package:flauncher/database.dart';
import 'package:flauncher/flauncher_channel.dart';
import 'package:flauncher/l10n/app_localizations.dart';
import 'package:flauncher/providers/apps_service.dart';
import 'package:flauncher/providers/backup_service.dart';
import 'package:flauncher/providers/settings_service.dart';
import 'package:flauncher/share/share_bundle.dart';
import 'package:flauncher/widgets/parent_pin_dialog.dart';
import 'package:flauncher/widgets/settings/share_pages.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// This TV and the other one, as the screens of a copy see them through the channel.
class _ShareChannel extends FLauncherChannel {
  List<Map<dynamic, dynamic>> profiles = [
    {"key": "user:0:alex", "name": "Alex", "kids": false},
    {"key": "user:11", "name": "Sam", "kids": true},
  ];
  final Map<String, List<Map<dynamic, dynamic>>> pairings = {
    "user:0:alex": [
      {"pkg": "com.netflix.ninja", "mode": "profile", "appProfile": "Alex"},
    ],
  };
  Map<dynamic, dynamic> status = {"state": "waiting"};
  List<Map<dynamic, dynamic>> found = [];
  String? bundleOut;
  String? bundleIn;
  String? connectedHost;
  int? connectedPort;
  bool? answered;
  String? reportSent;
  int stops = 0;
  final List<(String, List<Map<String, dynamic>>)> applied = [];

  /// Nobody is at the remote as far as Hearth can tell (a parent has to enter the PIN).
  @override
  Future<bool> isParentPresent() async => false;

  @override
  Future<String> getShareDeviceName() async => "Den";

  @override
  Future<List<Map<dynamic, dynamic>>> getShareProfiles() async => profiles;

  @override
  Future<List<Map<dynamic, dynamic>>> getSharePairings(String profileKey) async => pairings[profileKey] ?? [];

  @override
  Future<Map<dynamic, dynamic>> applySharePairings(String profileKey, List<Map<String, dynamic>> choices) async {
    applied.add((profileKey, choices));
    return {"applied": choices.length, "kept": 0, "skipped": 0};
  }

  @override
  Future<Map<dynamic, dynamic>?> startShareSending(String bundleJson) async {
    bundleOut = bundleJson;
    return {"host": "192.0.2.20", "port": 8770, "name": "Den"};
  }

  @override
  Future<void> startShareReceiving(String host, int port) async {
    connectedHost = host;
    connectedPort = port;
  }

  @override
  Future<Map<dynamic, dynamic>> getShareStatus() async => status;

  @override
  Future<void> confirmShare(bool same) async => answered = same;

  @override
  Future<String?> takeShareBundle() async => bundleIn;

  @override
  Future<void> sendShareReport(String report) async => reportSent = report;

  @override
  Future<void> stopShare() async => stops++;

  @override
  Future<void> startShareFinding() async {}

  @override
  Future<List<Map<dynamic, dynamic>>> getShareFound() async => found;
}

/// Backups and layouts without files or a database (their I/O doesn't run inside a widget test's clock; the
/// real ones are tested with the applier).
class _Backup extends BackupService {
  final SettingsService settings;
  final List<(String, bool)> applied = [];

  _Backup(super.database, super.prefs, this.settings);

  @override
  Future<Map<String, dynamic>?> readProfileLayout(String profileKey) async => null;

  @override
  Future<Map<String, dynamic>> buildBackupData(SettingsService settingsService, [bool profileOnly = false]) async =>
      {"version": 1, "settings": {"accent_color": "#123456"}, "apps": [], "categories": [], "appsCategories": [], "spacers": []};

  @override
  Future<List<InstalledApp>> installedApps() async => const [];

  @override
  Future<File> backupBeforeCopy(SettingsService settingsService, {DateTime? now}) async =>
      File("ltv_backup_before_copy_test.json");

  @override
  Future<void> applySharedLayout(String profileKey, Map<String, dynamic> backup, SettingsService settingsService,
      {required bool live}) async {
    applied.add((profileKey, live));
    await settingsService.importSettingsMap(Map<String, dynamic>.from(backup["settings"] as Map));
  }
}

class _Apps extends Fake implements AppsService {
  int refreshes = 0;

  @override
  Future<void> refreshState() async => refreshes++;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _ShareChannel channel;
  late _Apps apps;
  late FLauncherDatabase database;
  late SharedPreferences prefs;
  late SettingsService settings;
  late _Backup backup;

  setUp(() async {
    // The fake AppsService is a Listenable that nothing listens to
    Provider.debugCheckInvalidValueType = null;
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    channel = _ShareChannel();
    apps = _Apps();
    database = FLauncherDatabase.inMemory();
    settings = SettingsService(prefs);
    backup = _Backup(database, prefs, settings);
  });

  tearDown(() => database.close());

  Future<void> pump(WidgetTester tester, Widget page) async {
    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MultiProvider(
      providers: [
        Provider<FLauncherChannel>.value(value: channel),
        ChangeNotifierProvider<SettingsService>.value(value: settings),
        Provider<BackupService>.value(value: backup),
        Provider<AppsService>.value(value: apps),
      ],
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(body: page),
        onGenerateRoute: (settings) => MaterialPageRoute(
          builder: (_) => Scaffold(
            body: settings.name == ShareSendPage.routeName ? const ShareSendPage() : const ShareReceivePage(),
          ),
        ),
      ),
    ));
    await tester.pump(const Duration(milliseconds: 50));
  }

  /// Time passing for the screens' polling.
  Future<void> poll(WidgetTester tester) async {
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(milliseconds: 50));
  }

  Future<void> press(WidgetTester tester, String label) async {
    await tester.tap(find.text(label).last);
    await tester.pump(const Duration(milliseconds: 50));
  }

  Future<void> leave(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 50));
  }

  testWidgets("the page offers both directions", (tester) async {
    await pump(tester, const ShareProfilesPage());
    expect(find.text("Copy profiles between TVs"), findsOneWidget);
    expect(find.text("Copy profiles to another TV"), findsOneWidget);
    expect(find.text("Copy profiles from another TV"), findsOneWidget);
    expect(find.textContaining("Streaming PINs and Home Assistant settings stay on each TV"), findsOneWidget);
  });

  group("opening it", () {
    testWidgets("goes straight in on a TV with no parent PIN, as a new TV is", (tester) async {
      await pump(tester, const ShareProfilesPage());
      await press(tester, "Copy profiles from another TV");
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text("Enter an address"), findsOneWidget);
      await leave(tester);
    });

    testWidgets("asks for the parent PIN where the TV has one", (tester) async {
      await settings.setParentPin("1357");
      await pump(tester, const ShareProfilesPage());
      await press(tester, "Copy profiles to another TV");
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byType(ParentPinDialog), findsOneWidget);
      expect(find.text("Which profiles do you want to copy?"), findsNothing);
      await leave(tester);
    });
  });

  group("sending", () {
    testWidgets("lists the profiles, and goes on only with one chosen", (tester) async {
      await pump(tester, const ShareSendPage());
      expect(find.text("Alex"), findsOneWidget);
      expect(find.text("Sam"), findsOneWidget);
      await press(tester, "Continue");
      expect(channel.bundleOut, isNull);
      await leave(tester);
    });

    testWidgets("puts the chosen profile and its pairings in a bundle, and waits for the other TV", (tester) async {
      await pump(tester, const ShareSendPage());
      await press(tester, "Alex");
      await press(tester, "Continue");

      final bundle = ShareBundle.parse(channel.bundleOut!, settingKeys: SettingsService(prefs).settingKeys);
      expect(bundle.profiles.map((p) => p.name), ["Alex"]);
      expect(bundle.profiles.single.kids, isFalse);
      expect(bundle.pairings["p1"]!.single.packageName, "com.netflix.ninja");
      expect(bundle.tv, "Den");
      // The bundle names no key of this TV
      expect(channel.bundleOut, isNot(contains("user:0:alex")));

      expect(find.textContaining("choose Den"), findsOneWidget);
      expect(find.textContaining("192.0.2.20:8770"), findsOneWidget);
      await leave(tester);
    });

    testWidgets("shows the digits, and passes the parent's answer on", (tester) async {
      await pump(tester, const ShareSendPage());
      await press(tester, "Alex");
      await press(tester, "Continue");
      channel.status = {"state": "digits", "digits": "042917"};
      await poll(tester);
      expect(find.text("Do the digits match?"), findsOneWidget);
      expect(find.text("042 917"), findsOneWidget);
      await press(tester, "They match");
      expect(channel.answered, isTrue);
      await press(tester, "They don't match");
      expect(channel.answered, isFalse);
      await leave(tester);
    });

    testWidgets("says what the other TV did when it's done", (tester) async {
      await pump(tester, const ShareSendPage());
      await press(tester, "Alex");
      await press(tester, "Continue");
      channel.status = {
        "state": "done",
        "report": jsonEncode({"copied": 1, "missingApps": 3, "pairingsApplied": 1, "pairingsKept": 0}),
      };
      await poll(tester);
      expect(find.text("Copied"), findsOneWidget);
      expect(find.text("Profiles copied to the other TV: 1."), findsOneWidget);
      expect(find.textContaining("doesn't have them: 3"), findsOneWidget);
      await leave(tester);
    });

    testWidgets("says why it failed, and ends the copy when the page goes", (tester) async {
      await pump(tester, const ShareSendPage());
      await press(tester, "Alex");
      await press(tester, "Continue");
      channel.status = {"state": "failed", "error": "mismatch"};
      await poll(tester);
      expect(find.text("The copy didn't finish"), findsOneWidget);
      expect(find.text("The digits didn't match, so nothing was copied."), findsOneWidget);
      await leave(tester);
      expect(channel.stops, greaterThan(0));
    });
  });

  group("receiving", () {
    String senderBundle() => ShareBundle.build(
          hearth: "2026.10.62",
          tv: "Den",
          profiles: const [
            ShareProfile(id: "p1", name: "Alex", kids: false),
            ShareProfile(id: "p2", name: "Riley", kids: true),
          ],
          layouts: {
            "p1": {
              "settings": {"accent_color": "#ff00aa"},
              "apps": [
                {"packageName": "com.example.gone", "name": "Gone", "hidden": false},
              ],
              "categories": [
                {"id": 1, "name": "Favorites", "sort": 0, "type": 0, "rowHeight": 110, "columnsCount": 6, "order": 0},
              ],
              "appsCategories": [
                {"categoryId": 1, "appPackageName": "com.example.gone", "order": 0},
              ],
              "spacers": [],
            },
          },
          pairings: {
            "p1": const [SharedPairing(packageName: "com.netflix.ninja", picker: false, appProfile: "Alex")],
          },
          settingKeys: SettingsService(prefs).settingKeys,
        ).encode();

    testWidgets("lists the TVs it hears, and connects to the one picked", (tester) async {
      channel.found = [
        {"name": "Den", "host": "192.0.2.20", "port": 8770},
      ];
      await pump(tester, const ShareReceivePage());
      await poll(tester);
      expect(find.text("Den"), findsOneWidget);
      await press(tester, "Den");
      expect(channel.connectedHost, "192.0.2.20");
      expect(channel.connectedPort, 8770);
      await leave(tester);
    });

    testWidgets("takes the bundle, matches profiles by name and kind, and copies on the parent's word", (tester) async {
      await prefs.setString(SettingsService.layoutOwnerKey, "user:0:alex");
      channel.found = [
        {"name": "Den", "host": "192.0.2.20", "port": 8770},
      ];
      await pump(tester, const ShareReceivePage());
      await poll(tester);
      await press(tester, "Den");

      channel.status = {"state": "digits", "digits": "123456"};
      await poll(tester);
      expect(find.text("123 456"), findsOneWidget);
      await press(tester, "They match");
      expect(channel.answered, isTrue);

      channel.bundleIn = senderBundle();
      channel.status = {"state": "received"};
      await poll(tester);
      await tester.pump(const Duration(milliseconds: 100));

      // Alex goes to Alex here; Riley has no kids profile of that name here, so isn't copied
      expect(find.text("Where does each profile go?"), findsOneWidget);
      expect(find.text("Alex"), findsWidgets);
      expect(find.text("Don't copy"), findsWidgets);

      await press(tester, "Copy");
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text("Copied"), findsOneWidget);
      expect(find.textContaining("Profiles copied: 1."), findsOneWidget);
      expect(find.textContaining("ltv_backup_before_copy_"), findsOneWidget);
      expect(channel.applied.single.$1, "user:0:alex");
      expect(channel.reportSent, isNotNull);
      expect((jsonDecode(channel.reportSent!) as Map)["copied"], 1);
      expect(apps.refreshes, 1);
      expect(backup.applied, [("user:0:alex", true)]);
      expect(settings.accentColorHex, "#ff00aa");
      await leave(tester);
    });

    Future<void> connect(WidgetTester tester) async {
      channel.found = [
        {"name": "Den", "host": "192.0.2.20", "port": 8770},
      ];
      await pump(tester, const ShareReceivePage());
      await poll(tester);
      await press(tester, "Den");
    }

    testWidgets("a bundle from a newer Hearth is refused, and said so", (tester) async {
      await connect(tester);
      channel.bundleIn = jsonEncode({"format": "hearth-share", "v": 9, "profiles": [], "sections": []});
      channel.status = {"state": "received"};
      await poll(tester);
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text("That TV has a newer Hearth. Update this one and try again."), findsOneWidget);
      await leave(tester);
    });

    testWidgets("something that isn't a bundle is refused, and nothing is changed", (tester) async {
      await connect(tester);
      channel.bundleIn = "not a bundle";
      channel.status = {"state": "received"};
      await poll(tester);
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text("The copy didn't finish. Nothing was changed on this TV."), findsOneWidget);
      expect(channel.applied, isEmpty);
      await leave(tester);
    });

    test("an address is an IPv4 address and maybe a port", () {
      expect(_parse("192.168.1.20:8771"), ("192.168.1.20", 8771));
      expect(_parse(" 192.168.1.20 "), ("192.168.1.20", 8770));
      expect(_parse("192.168.1.20:99999"), isNull);
      expect(_parse("tv.local"), isNull);
      expect(_parse("1.2.3"), isNull);
      expect(_parse(""), isNull);
      expect(_parse(null), isNull);
    });
  });
}

(String, int)? _parse(String? text) => ShareReceivePage.parseAddress(text);
