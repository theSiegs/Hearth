import 'package:flauncher/providers/home_looks.dart';
import 'package:flauncher/providers/settings_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

void main() {
  late SharedPreferences prefs;

  setUp(() async {
    SharedPreferencesStorePlatform.instance = InMemorySharedPreferencesStore.empty();
    prefs = await SharedPreferences.getInstance();
    await prefs.clear();
  });

  test("every look but the photo of the day has one of Hearth's gradients", () {
    for (final look in HomeLook.values) {
      expect(look.gradient == null, look.bing, reason: look.name);
    }
  });

  test("a look put in place is the one the home has, and only that one", () async {
    final settings = SettingsService(prefs);
    for (final look in HomeLook.values) {
      await look.apply(settings);
      expect(HomeLook.current(settings), look);
    }
  });

  test("the photo of the day keeps the accent", () async {
    final settings = SettingsService(prefs);
    await settings.setAccentColor(accentColorTeal);
    await HomeLook.photo.apply(settings);
    expect(settings.accentColorHex, accentColorTeal);
    expect(settings.bingWallpaperEnabled, isTrue);
  });

  test("a snapshot puts back what a preview changed", () async {
    final settings = SettingsService(prefs);
    await settings.setThemes("capsule");
    await settings.setTimeBasedWallpaperEnabled(true);
    final before = HomeLookSnapshot.of(settings);

    await HomeLook.photo.apply(settings);
    expect(HomeLookSnapshot.of(settings).sameAs(before), isFalse);
    await before.restore(settings);
    expect(HomeLookSnapshot.of(settings).sameAs(before), isTrue);
    expect(settings.themes, "capsule");
    expect(settings.timeBasedWallpaperEnabled, isTrue);
    expect(settings.bingWallpaperEnabled, isFalse);
  });
}
