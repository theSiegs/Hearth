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
    when(channel.getActiveProfileKey()).thenAnswer((_) async => "user:0");
    final backup = _RecordingBackupService(database, prefs, {});

    final service = build(backup);
    await service.check();

    expect(service.activeProfileName, "Alex");
    expect(service.activeProfileKey, "user:0");
    expect(backup.calls, ["load user:0", "load Alex"]);
    expect(prefs.getString(ProfileService.layoutOwnerKey), "user:0");
    verifyNever(appsService.refreshState());
  });

  test("switching saves the outgoing layout and restores the incoming one", () async {
    await prefs.setString(ProfileService.layoutOwnerKey, "user:0");
    when(channel.getActiveProfileName()).thenAnswer((_) async => "Riley");
    when(channel.getActiveProfileKey()).thenAnswer((_) async => "user:10");
    when(channel.isKidsProfile()).thenAnswer((_) async => true);
    final backup = _RecordingBackupService(database, prefs, {"user:10"});

    final service = build(backup);
    await service.check();

    expect(backup.calls, ["save user:0", "load user:10"]);
    expect(service.isKidsProfile, isTrue);
    expect(prefs.getString(ProfileService.layoutOwnerKey), "user:10");
    verify(appsService.refreshState()).called(1);
  });

  test("a kids profile starts with Bing's photo once, then keeps its own choice", () async {
    await prefs.setString(ProfileService.layoutOwnerKey, "user:0");
    when(channel.getActiveProfileName()).thenAnswer((_) async => "Jordan");
    when(channel.getActiveProfileKey()).thenAnswer((_) async => "user:10");
    when(channel.isKidsProfile()).thenAnswer((_) async => true);
    when(appsService.initialized).thenReturn(false);
    final settings = SettingsService(prefs);
    final service = ProfileService(channel, prefs, _RecordingBackupService(database, prefs, {"user:10"}), settings, appsService);

    await service.check();
    expect(settings.bingWallpaperEnabled, isTrue);

    // Turned off in his Settings: it stays off when he comes back
    await settings.setBingWallpaperEnabled(false);
    await service.check();
    expect(settings.bingWallpaperEnabled, isFalse);
  });

  test("a grown-up profile's wallpaper is left alone", () async {
    when(channel.getActiveProfileName()).thenAnswer((_) async => "Alex");
    when(channel.getActiveProfileKey()).thenAnswer((_) async => "user:0");
    final settings = SettingsService(prefs);
    final service = ProfileService(channel, prefs, _RecordingBackupService(database, prefs, {}), settings, appsService);

    await service.check();
    expect(settings.bingWallpaperEnabled, isFalse);
  });

  test("a pick in the chooser shows its card at once, and the confirmed switch takes it over", () async {
    await prefs.setString(ProfileService.layoutOwnerKey, "user:0");
    when(channel.getActiveProfileName()).thenAnswer((_) async => "Alex");
    when(channel.getActiveProfileKey()).thenAnswer((_) async => "user:0");
    final service = build(_RecordingBackupService(database, prefs, {}));
    await service.check();

    await service.switchingTo("Riley");
    expect(service.incomingName, "Riley");
    expect(service.transition, isNull);

    // The profile user settles; Hearth doesn't know her name in this user yet
    when(channel.getActiveProfileName()).thenAnswer((_) async => null);
    when(channel.getActiveProfileKey()).thenAnswer((_) async => "user:12");
    await service.check();
    expect(service.incomingName, isNull);
    expect(service.transition?.key, "user:12");
    expect(service.transition?.pickedName, "Riley");
  });

  test("picking the profile that's already on shows no card", () async {
    when(channel.getActiveProfileName()).thenAnswer((_) async => "Alex");
    when(channel.getActiveProfileKey()).thenAnswer((_) async => "user:0");
    final service = build(_RecordingBackupService(database, prefs, {}));
    await service.check();

    await service.switchingTo("Alex");
    expect(service.incomingName, isNull);
  });

  test("a profile not named yet still gets its own layout", () async {
    await prefs.setString(ProfileService.layoutOwnerKey, "user:0");
    when(channel.getActiveProfileName()).thenAnswer((_) async => null);
    when(channel.getActiveProfileKey()).thenAnswer((_) async => "user:11");
    final backup = _RecordingBackupService(database, prefs, {"user:11"});

    final service = build(backup);
    await service.check();

    expect(backup.calls, ["save user:0", "load user:11"]);
    expect(prefs.getString(ProfileService.layoutOwnerKey), "user:11");
  });

  test("a layout owned by this profile's name (from before keys) stays and moves to its key", () async {
    await prefs.setString(ProfileService.layoutOwnerKey, "Alex");
    when(channel.getActiveProfileName()).thenAnswer((_) async => "Alex");
    when(channel.getActiveProfileKey()).thenAnswer((_) async => "user:0");
    final backup = _RecordingBackupService(database, prefs, {});

    final service = build(backup);
    await service.check();

    expect(backup.calls, isEmpty);
    expect(prefs.getString(ProfileService.layoutOwnerKey), "user:0");
  });

  test("switching to a profile whose layout was saved under its name restores that layout", () async {
    await prefs.setString(ProfileService.layoutOwnerKey, "user:0");
    when(channel.getActiveProfileName()).thenAnswer((_) async => "Riley");
    when(channel.getActiveProfileKey()).thenAnswer((_) async => "user:10");
    final backup = _RecordingBackupService(database, prefs, {"Riley"});

    final service = build(backup);
    await service.check();

    expect(backup.calls, ["save user:0", "load user:10", "load Riley"]);
    expect(prefs.getString(ProfileService.layoutOwnerKey), "user:10");
    verify(appsService.refreshState()).called(1);
  });

  test("an unknown profile leaves the layout alone", () async {
    await prefs.setString(ProfileService.layoutOwnerKey, "user:0");
    when(channel.getActiveProfileName()).thenAnswer((_) async => null);
    when(channel.getActiveProfileKey()).thenAnswer((_) async => null);
    final backup = _RecordingBackupService(database, prefs, {});

    final service = build(backup);
    await service.check();

    expect(backup.calls, isEmpty);
    expect(prefs.getString(ProfileService.layoutOwnerKey), "user:0");
  });

  test("starting up shows no welcome card, but counts as settled once checked", () async {
    when(channel.getActiveProfileName()).thenAnswer((_) async => "Alex");
    when(channel.getActiveProfileKey()).thenAnswer((_) async => "user:0");
    final service = build(_RecordingBackupService(database, prefs, {}));
    expect(service.settledOnce, isFalse);

    await service.check();

    expect(service.transition, isNull);
    expect(service.settledOnce, isTrue);
    expect(service.layoutReadyFor("user:0"), isTrue);
  });

  test("a switch to another profile starts a welcome card that ends when told", () async {
    when(channel.getActiveProfileName()).thenAnswer((_) async => "Alex");
    when(channel.getActiveProfileKey()).thenAnswer((_) async => "user:0");
    final service = build(_RecordingBackupService(database, prefs, {}));
    await service.check();

    when(channel.getActiveProfileName()).thenAnswer((_) async => null);
    when(channel.getActiveProfileKey()).thenAnswer((_) async => "user:11");
    await service.check();

    final transition = service.transition;
    expect(transition?.key, "user:11");
    expect(service.layoutReadyFor("user:11"), isTrue);
    service.endTransition(transition!);
    expect(service.transition, isNull);
  });

  test("checking the same profile again starts no welcome card", () async {
    when(channel.getActiveProfileName()).thenAnswer((_) async => "Alex");
    when(channel.getActiveProfileKey()).thenAnswer((_) async => "user:0");
    final service = build(_RecordingBackupService(database, prefs, {}));
    await service.check();
    await service.check();

    expect(service.transition, isNull);
  });
}
