import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/painting.dart';
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
  late final Directory documents;
  setUpAll(() {
    documents = Directory.systemTemp.createTempSync("hearth_wallpaper_test");
    pathProviderPlatform = _MockPathProviderPlatform();
    when(pathProviderPlatform.getApplicationDocumentsPath()).thenAnswer((_) => Future.value(documents.path));
    PathProviderPlatform.instance = pathProviderPlatform;
  });
  tearDownAll(() => documents.deleteSync(recursive: true));

  group("pickWallpaper", () {
    test("picks image", () async {
      final pickedFile = _MockXFile();
      when(pickedFile.openRead()).thenAnswer((_) => Stream.value(Uint8List.fromList([0x01])));
      final imagePicker = _MockImagePicker();
      final fLauncherChannel = MockFLauncherChannel();
      final settingsService = MockSettingsService();
      when(settingsService.timeBasedWallpaperEnabled).thenReturn(false);
      when(settingsService.bingWallpaperEnabled).thenReturn(false);
      when(settingsService.gradientUuid).thenReturn(null);
      when(imagePicker.pickImage(source: ImageSource.gallery)).thenAnswer((_) => Future.value(pickedFile));
      when(fLauncherChannel.checkForGetContentAvailability()).thenAnswer((_) => Future.value(true));
      final wallpaperService = WallpaperService(fLauncherChannel, settingsService, imagePicker: imagePicker);
      await untilCalled(pathProviderPlatform.getApplicationDocumentsPath());

      await wallpaperService.pickWallpaper();

      verify(imagePicker.pickImage(source: ImageSource.gallery));
      expect(File("${documents.path}/wallpaper").readAsBytesSync(), [0x01]);
      expect(wallpaperService.wallpaper, isA<FileImage>());
      // HearthTube hears of the new picture through Hearth's provider
      final sent = verify(fLauncherChannel.setWallpaperState(captureAny)).captured.last as Map<String, Object?>;
      expect(sent["file"], "wallpaper");
      expect(sent["bing_credit"], isNull);
    });

    test("throws error when no file explorer installed", () async {
      final fLauncherChannel = MockFLauncherChannel();
      when(fLauncherChannel.checkForGetContentAvailability()).thenAnswer((_) => Future.value(false));
      final settingsService = MockSettingsService();
      when(settingsService.timeBasedWallpaperEnabled).thenReturn(false);
      when(settingsService.bingWallpaperEnabled).thenReturn(false);
      when(settingsService.gradientUuid).thenReturn(null);
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
      when(settingsService.gradientUuid).thenReturn(null);
    final wallpaperService = WallpaperService(fLauncherChannel, settingsService);

    await untilCalled(pathProviderPlatform.getApplicationDocumentsPath());
    // Let the first look at the wallpaper (reading the file to measure it) finish: Windows can't delete an open file
    await Future.delayed(const Duration(milliseconds: 200));
    await wallpaperService.setGradient(FLauncherGradients.greatWhale);

    verify(settingsService.setGradientUuid(FLauncherGradients.greatWhale.uuid));
    expect(wallpaperService.wallpaper, null);
    final sent = verify(fLauncherChannel.setWallpaperState(captureAny)).captured.last as Map<String, Object?>;
    expect(sent["file"], isNull);
    expect(sent["gradient"], isA<String>());
  });

  group("what HearthTube gets", () {
    test("a linear gradient: colors, begin and end, rotation, brightness", () {
      final described = WallpaperService.describeGradient(FLauncherGradients.greatWhale.gradient, 0.4);
      expect(described["type"], "linear");
      expect(described["colors"], ["#FF6991C7", "#FFA3BDED"]);
      expect(described["stops"], isNull);
      expect(described["begin"], {"x": -1.0, "y": 0.0});
      expect(described["end"], {"x": 1.0, "y": 0.0});
      expect(described["rotation"], 5.6);
      expect(described["brightness"], 0.4);
      // It goes over the provider as JSON
      expect(() => jsonEncode(described), returnsNormally);
    });

    test("stops, and a radial gradient", () {
      expect(WallpaperService.describeGradient(FLauncherGradients.grassShampoo.gradient, 0)["stops"], [0, 0.47, 1]);
      final radial = WallpaperService.describeGradient(FLauncherGradients.oldHat.gradient, 0.8);
      expect(radial["type"], "radial");
      expect(radial["center"], {"x": 0.0, "y": 0.0});
      expect(radial["radius"], 0.5);
      expect(radial["rotation"], 0.0);
    });

    test("the Bing photo's title and credit", () {
      final info = WallpaperService.bingInfo({
        "title": "A quiet lake",
        "copyright": "A quiet lake at dawn (© Example Photographer/Example Agency)",
      });
      expect(info.title, "A quiet lake");
      expect(info.credit, "A quiet lake at dawn (© Example Photographer/Example Agency)");
      final none = WallpaperService.bingInfo({"title": " ", "copyright": null});
      expect(none.title, isNull);
      expect(none.credit, isNull);
    });
  });

  test("brightness follows the gradient, and a picture's average", () {
    expect(WallpaperService.gradientBrightness(FLauncherGradients.pitchBlack.gradient), lessThan(0.05));
    expect(WallpaperService.gradientBrightness(FLauncherGradients.greatWhale.gradient), greaterThan(0.25));
    // Two pixels: white and black
    expect(WallpaperService.averageLuminance(Uint8List.fromList([255, 255, 255, 255, 0, 0, 0, 255])), closeTo(0.5, 0.01));
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
  Stream<Uint8List> openRead([int? start, int? end]) =>
      super.noSuchMethod(Invocation.method(#openRead, [start, end]), returnValue: const Stream<Uint8List>.empty());
}

class _MockPathProviderPlatform extends Mock with MockPlatformInterfaceMixin implements PathProviderPlatform {
  @override
  Future<String?> getApplicationDocumentsPath() =>
      super.noSuchMethod(Invocation.method(#getApplicationDocumentsPath, []), returnValue: Future<String?>.value());

}
