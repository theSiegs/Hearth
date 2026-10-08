import 'package:flutter/painting.dart';
import 'dart:typed_data';
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

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flauncher/gradients.dart';
import 'package:flauncher/providers/wallpaper_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:mockito/mockito.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import '../mocks.mocks.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late final _MockPathProviderPlatform pathProviderPlatform;
  setUpAll(() {
    pathProviderPlatform = _MockPathProviderPlatform();
    when(pathProviderPlatform.getApplicationDocumentsPath()).thenAnswer((_) => Future.value("."));
    PathProviderPlatform.instance = pathProviderPlatform;
  });

  group("pickWallpaper", () {
    test("picks image", () async {
      TestWidgetsFlutterBinding.ensureInitialized();
      final pickedFile = _MockXFile();
      when(pickedFile.readAsBytes()).thenAnswer((_) => Future.value(Uint8List.fromList([0x01])));
      final imagePicker = _MockImagePicker();
      final fLauncherChannel = MockFLauncherChannel();
      final settingsService = MockSettingsService();
      when(settingsService.timeBasedWallpaperEnabled).thenReturn(false);
      when(settingsService.bingWallpaperEnabled).thenReturn(false);
      when(imagePicker.pickImage(source: ImageSource.gallery)).thenAnswer((_) => Future.value(pickedFile));
      when(fLauncherChannel.checkForGetContentAvailability()).thenAnswer((_) => Future.value(true));
      final wallpaperService = WallpaperService(fLauncherChannel, settingsService);
      await untilCalled(pathProviderPlatform.getApplicationDocumentsPath());

      await wallpaperService.pickWallpaper();

      //verify(imagePicker.pickImage(source: ImageSource.gallery));
      // MissingPluginException(No implementation found for method pickImage on channel plugins.flutter.io/image_picker)
      //
      expect(wallpaperService.wallpaper.hashCode, 1);
    }, skip: true);

    test("throws error when no file explorer installed", () async {
      final fLauncherChannel = MockFLauncherChannel();
      when(fLauncherChannel.checkForGetContentAvailability()).thenAnswer((_) => Future.value(false));
      final settingsService = MockSettingsService();
      when(settingsService.timeBasedWallpaperEnabled).thenReturn(false);
      when(settingsService.bingWallpaperEnabled).thenReturn(false);
      final wallpaperService = WallpaperService(fLauncherChannel, settingsService);
      await untilCalled(pathProviderPlatform.getApplicationDocumentsPath());

      expect(() async => await wallpaperService.pickWallpaper(), throwsA(isInstanceOf<NoFileExplorerException>()));
    });
  });


  test("setGradient", () async {
    final fLauncherChannel = MockFLauncherChannel();
    final settingsService = MockSettingsService();
      when(settingsService.timeBasedWallpaperEnabled).thenReturn(false);
      when(settingsService.bingWallpaperEnabled).thenReturn(false);
    final wallpaperService = WallpaperService(fLauncherChannel, settingsService);

    await untilCalled(pathProviderPlatform.getApplicationDocumentsPath());
    await wallpaperService.setGradient(FLauncherGradients.greatWhale);

    verify(settingsService.setGradientUuid(FLauncherGradients.greatWhale.uuid));
    expect(wallpaperService.wallpaper, null);
  });

  group("getGradient", () {
    test("without uuid from settings", () async {
      final fLauncherChannel = MockFLauncherChannel();
      final settingsService = MockSettingsService();
      when(settingsService.timeBasedWallpaperEnabled).thenReturn(false);
      when(settingsService.bingWallpaperEnabled).thenReturn(false);
      final wallpaperService = WallpaperService(fLauncherChannel, settingsService);
      when(settingsService.gradientUuid).thenReturn(null);

      await untilCalled(pathProviderPlatform.getApplicationDocumentsPath());
      final gradient = wallpaperService.gradient;

      expect(gradient.uuid, FLauncherGradients.pitchBlack.uuid);
    });

    test("with uuid from settings", () async {
      final fLauncherChannel = MockFLauncherChannel();
      final settingsService = MockSettingsService();
      when(settingsService.timeBasedWallpaperEnabled).thenReturn(false);
      when(settingsService.bingWallpaperEnabled).thenReturn(false);
      final wallpaperService = WallpaperService(fLauncherChannel, settingsService);
      when(settingsService.gradientUuid).thenReturn(FLauncherGradients.grassShampoo.uuid);
      await untilCalled(pathProviderPlatform.getApplicationDocumentsPath());

      final gradient = wallpaperService.gradient;

      expect(gradient.uuid, FLauncherGradients.grassShampoo.uuid);
    });
  });

  test("the day and night wallpapers swap at 06:00 and 18:00", () {
    expect(WallpaperService.nextDayNightSwitch(DateTime(2026, 10, 8, 2, 30)), DateTime(2026, 10, 8, 6));
    expect(WallpaperService.nextDayNightSwitch(DateTime(2026, 10, 8, 6)), DateTime(2026, 10, 8, 18));
    expect(WallpaperService.nextDayNightSwitch(DateTime(2026, 10, 8, 17, 59)), DateTime(2026, 10, 8, 18));
    expect(WallpaperService.nextDayNightSwitch(DateTime(2026, 10, 8, 18)), DateTime(2026, 10, 9, 6));
    expect(WallpaperService.nextDayNightSwitch(DateTime(2026, 10, 31, 23)), DateTime(2026, 11, 1, 6));
  });

  group("dominantBackgroundColor", () {
    Uint8List pixels(List<List<int>> colors, int each) =>
        Uint8List.fromList([for (final c in colors) for (int i = 0; i < each; i++) ...c]);

    test("favors the logo color over white padding and darkens it", () {
      final color = WallpaperService.dominantBackgroundColor(pixels([
        [255, 255, 255, 255],
        [230, 20, 20, 255],
      ], 50))!;
      final hsl = HSLColor.fromColor(color);
      expect(hsl.hue < 20 || hsl.hue > 340, isTrue, reason: "should be red, was hue ${hsl.hue}");
      expect(hsl.lightness, lessThanOrEqualTo(0.26));
    });

    test("ignores transparent pixels and handles plain gray", () {
      final color = WallpaperService.dominantBackgroundColor(pixels([
        [0, 255, 0, 0],
        [128, 128, 128, 255],
      ], 10))!;
      final hsl = HSLColor.fromColor(color);
      expect(hsl.saturation, lessThan(0.05));
      expect(hsl.lightness, inInclusiveRange(0.12, 0.26));
    });

    test("returns null for a fully transparent image", () {
      expect(WallpaperService.dominantBackgroundColor(pixels([[0, 0, 0, 0]], 10)), isNull);
    });
  });

}

class _MockImagePicker extends Mock implements ImagePicker {
  @override
  Future<XFile?> pickImage({
    required ImageSource source,
    double? maxWidth,
    double? maxHeight,
    int? imageQuality,
    CameraDevice preferredCameraDevice = CameraDevice.rear,
    bool requestFullMetadata = true,
  }) =>
      super.noSuchMethod(
          Invocation.method(#pickImage, [], {
            #source: source,
            #maxWidth: maxWidth,
            #maxHeight: maxHeight,
            #imageQuality: imageQuality,
            #preferredCameraDevice: preferredCameraDevice,
            #requestFullMetadata: requestFullMetadata,
          }),
          returnValue: Future<XFile?>.value());
}

// ignore: must_be_immutable
class _MockXFile extends Mock implements XFile {
  @override
  Future<Uint8List> readAsBytes() => super
      .noSuchMethod(Invocation.method(#readAsBytes, []), returnValue: Future<Uint8List>.value(Uint8List.fromList([])));
}

class _MockPathProviderPlatform extends Mock with MockPlatformInterfaceMixin implements PathProviderPlatform {
  @override
  Future<String?> getApplicationDocumentsPath() =>
      super.noSuchMethod(Invocation.method(#getApplicationDocumentsPath, []), returnValue: Future<String?>.value());

}
