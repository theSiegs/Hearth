import 'package:flauncher/database.dart';
import 'package:flauncher/providers/backup_service.dart';
import 'package:flauncher/providers/profile_service.dart';
import 'package:flauncher/providers/settings_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

import '../mocks.mocks.dart';

class _RecordingBackupService extends BackupService {
  final List<String> calls = [];
  final Set<String> savedProfiles;

  _RecordingBackupService(FLauncherDatabase db, SharedPreferences prefs, this.savedProfiles) : super(db, prefs);

  @override
  Future<void> saveProfileLayout(String profileName, SettingsService settingsService) async {
    calls.add("save $profileName");
    savedProfiles.add(profileName);
  }

  @override
  Future<bool> loadProfileLayout(String profileName, SettingsService settingsService) async {
    calls.add("load $profileName");
    return savedProfiles.contains(profileName);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late SharedPreferences prefs;
  late FLauncherDatabase database;
  late MockFLauncherChannel channel;
  late MockAppsService appsService;

  setUp(() async {
    SharedPreferencesStorePlatform.instance = InMemorySharedPreferencesStore.empty();
    prefs = await SharedPreferences.getInstance();
    database = FLauncherDatabase.inMemory();
    channel = MockFLauncherChannel();
    appsService = MockAppsService();
    when(appsService.refreshState()).thenAnswer((_) async {});
    when(channel.isKidsProfile()).thenAnswer((_) async => false);
  });

  tearDown(() => database.close());

  ProfileService build(_RecordingBackupService backup) =>
      ProfileService(channel, prefs, backup, SettingsService(prefs), appsService);

  test("first profile seen takes ownership of the current layout", () async {
    when(channel.getActiveProfileName()).thenAnswer((_) async => "Alex");
    final backup = _RecordingBackupService(database, prefs, {});

    final service = build(backup);
    await service.check();

    expect(service.activeProfileName, "Alex");
    expect(backup.calls, ["load Alex"]);
    expect(prefs.getString(ProfileService.layoutOwnerKey), "Alex");
    verifyNever(appsService.refreshState());
  });

  test("switching saves the outgoing layout and restores the incoming one", () async {
    await prefs.setString(ProfileService.layoutOwnerKey, "Alex");
    when(channel.getActiveProfileName()).thenAnswer((_) async => "Riley");
    when(channel.isKidsProfile()).thenAnswer((_) async => true);
    final backup = _RecordingBackupService(database, prefs, {"Riley"});

    final service = build(backup);
    await service.check();

    expect(backup.calls, ["save Alex", "load Riley"]);
    expect(service.isKidsProfile, isTrue);
    expect(prefs.getString(ProfileService.layoutOwnerKey), "Riley");
    verify(appsService.refreshState()).called(1);
  });

  test("an unknown profile leaves the layout alone", () async {
    await prefs.setString(ProfileService.layoutOwnerKey, "Alex");
    when(channel.getActiveProfileName()).thenAnswer((_) async => null);
    final backup = _RecordingBackupService(database, prefs, {});

    final service = build(backup);
    await service.check();

    expect(backup.calls, isEmpty);
    expect(prefs.getString(ProfileService.layoutOwnerKey), "Alex");
  });
}
