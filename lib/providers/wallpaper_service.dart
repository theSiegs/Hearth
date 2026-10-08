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
import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:ui' as ui;

import 'package:flauncher/flauncher_channel.dart';
import 'package:flauncher/gradients.dart';
import 'package:flauncher/providers/settings_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';

class WallpaperService extends ChangeNotifier with WidgetsBindingObserver {
  final FLauncherChannel _fLauncherChannel;
  final SettingsService _settingsService;

  // "Match selected app": background tinted from the focused app's banner
  final Map<String, Color?> _appColorCache = {};
  Color? _focusedAppColor;

  Color? get focusedAppColor => _settingsService.matchSelectedAppBackground ? _focusedAppColor : null;

  Future<void> onAppFocused(String packageName) async {
    if (!_settingsService.matchSelectedAppBackground) return;
    final Color? color = _appColorCache.containsKey(packageName)
        ? _appColorCache[packageName]
        : (_appColorCache[packageName] = await _extractAppColor(packageName));
    if (color != null && color != _focusedAppColor) {
      _focusedAppColor = color;
      notifyListeners();
    }
  }

  Future<Color?> _extractAppColor(String packageName) async {
    try {
      Uint8List bytes = await _fLauncherChannel.getApplicationBanner(packageName);
      if (bytes.isEmpty) bytes = await _fLauncherChannel.getApplicationIcon(packageName);
      if (bytes.isEmpty) return null;
      final codec = await ui.instantiateImageCodec(bytes, targetWidth: 24);
      final image = (await codec.getNextFrame()).image;
      final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      image.dispose();
      if (data == null) return null;
      return dominantBackgroundColor(data.buffer.asUint8List());
    } catch (e) {
      developer.log("Failed to extract app color", name: "WallpaperService", error: e);
      return null;
    }
  }

  /// Average of the image weighted toward its most saturated pixels (logos over white/black padding),
  /// darkened enough for white text on top.
  static Color? dominantBackgroundColor(Uint8List rgba) {
    double r = 0, g = 0, b = 0, total = 0;
    for (int i = 0; i + 3 < rgba.length; i += 4) {
      if (rgba[i + 3] < 128) continue;
      final int pr = rgba[i], pg = rgba[i + 1], pb = rgba[i + 2];
      final int maxC = [pr, pg, pb].reduce((a, c) => a > c ? a : c);
      final int minC = [pr, pg, pb].reduce((a, c) => a < c ? a : c);
      final double weight = 0.05 + (maxC - minC) / 255.0;
      r += pr * weight;
      g += pg * weight;
      b += pb * weight;
      total += weight;
    }
    if (total == 0) return null;
    final hsl = HSLColor.fromColor(Color.fromARGB(255, (r / total).round(), (g / total).round(), (b / total).round()));
    return hsl.withLightness(hsl.lightness.clamp(0.12, 0.26)).withSaturation(hsl.saturation.clamp(0.0, 0.65)).toColor();
  }

  late File _wallpaperFile;
  late File _wallpaperDayFile;
  late File _wallpaperNightFile;
  late File _wallpaperBingFile;
  late File _wallpaperBingDateFile;
  Timer? _dayNightTimer;
  Timer? _bingTimer;
  bool _bingRefreshInFlight = false;

  ImageProvider? _wallpaper;
  int _version = 0;
  int _updateWallpaperCallCount = 0;
  bool _bingWallpaperError = false;

  bool get bingWallpaperError => _bingWallpaperError;

  ImageProvider?  get wallpaper     => _wallpaper;
  int             get version       => _version;

  FLauncherGradient get gradient => FLauncherGradients.all.firstWhere(
        (gradient) => gradient.uuid == _settingsService.gradientUuid,
        orElse: () => FLauncherGradients.pitchBlack,
      );

  WallpaperService(this._fLauncherChannel, this._settingsService) :
    _wallpaper = null
  {
    _settingsService.addListener(_onSettingsChanged);
    WidgetsBinding.instance.addObserver(this);
    _init();
  }

  bool _lastTimeBasedEnabled = false;
  bool _lastBingEnabled = false;

  void _onSettingsChanged() {
    final timeBasedEnabled = _settingsService.timeBasedWallpaperEnabled;
    final bingEnabled = _settingsService.bingWallpaperEnabled;
    final timeBasedChanged = timeBasedEnabled != _lastTimeBasedEnabled;
    final bingChanged = bingEnabled != _lastBingEnabled;

    if (timeBasedChanged || bingChanged) {
      _lastTimeBasedEnabled = timeBasedEnabled;
      _lastBingEnabled = bingEnabled;
      _updateTimerState();
      if (bingChanged && bingEnabled) {
        refreshBingWallpaper(force: true);
      } else {
        _updateWallpaper();
      }
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // The switch timer runs late when the TV has slept, so check again on coming back
    if (state == AppLifecycleState.resumed && _dayNightTimer != null) {
      _updateWallpaper();
      _scheduleDayNightSwitch();
    }
  }

  @override
  void dispose() {
    _settingsService.removeListener(_onSettingsChanged);
    WidgetsBinding.instance.removeObserver(this);
    _dayNightTimer?.cancel();
    _bingTimer?.cancel();
    super.dispose();
  }

  Future<void> _init() async {
    final directory = await getApplicationDocumentsDirectory();
    _wallpaperFile = File("${directory.path}/wallpaper");
    _wallpaperDayFile = File("${directory.path}/wallpaper_day");
    _wallpaperNightFile = File("${directory.path}/wallpaper_night");
    _wallpaperBingFile = File("${directory.path}/wallpaper_bing");
    _wallpaperBingDateFile = File("${directory.path}/wallpaper_bing_date");

    _lastTimeBasedEnabled = _settingsService.timeBasedWallpaperEnabled;
    _lastBingEnabled = _settingsService.bingWallpaperEnabled;
    await _updateWallpaper();
    _updateTimerState();

    if (_lastBingEnabled) {
      unawaited(refreshBingWallpaperIfStale());
    }
  }

  void _updateTimerState() {
    if (_settingsService.timeBasedWallpaperEnabled) {
      _scheduleDayNightSwitch();
    } else {
      _dayNightTimer?.cancel();
      _dayNightTimer = null;
    }

    final bingEnabled = _settingsService.bingWallpaperEnabled;
    if (bingEnabled && (_bingTimer == null || !_bingTimer!.isActive)) {
      _bingTimer = Timer.periodic(const Duration(hours: 1), (_) => refreshBingWallpaperIfStale());
    } else if (!bingEnabled && _bingTimer != null) {
      _bingTimer?.cancel();
      _bingTimer = null;
    }
  }

  /// The next 06:00 or 18:00 after [now], where the day and night wallpapers swap.
  @visibleForTesting
  static DateTime nextDayNightSwitch(DateTime now) {
    final morning = DateTime(now.year, now.month, now.day, 6);
    final evening = DateTime(now.year, now.month, now.day, 18);
    if (now.isBefore(morning)) return morning;
    if (now.isBefore(evening)) return evening;
    return DateTime(now.year, now.month, now.day + 1, 6);
  }

  void _scheduleDayNightSwitch() {
    _dayNightTimer?.cancel();
    final now = DateTime.now();
    _dayNightTimer = Timer(nextDayNightSwitch(now).difference(now), () {
      _updateWallpaper();
      _scheduleDayNightSwitch();
    });
  }

  Future<void> _updateWallpaper({bool force = false}) async {
    final callId = ++_updateWallpaperCallCount;
    final now = DateTime.now();
    final isDay = now.hour >= 6 && now.hour < 18;
    final bingEnabled = _settingsService.bingWallpaperEnabled;
    final timeBasedEnabled = _settingsService.timeBasedWallpaperEnabled;

    ImageProvider? newWallpaper;

    if (bingEnabled && await _wallpaperBingFile.exists()) {
      newWallpaper = FileImage(_wallpaperBingFile);
    } else if (timeBasedEnabled) {
      if (isDay && await _wallpaperDayFile.exists()) {
        newWallpaper = FileImage(_wallpaperDayFile);
      } else if (!isDay && await _wallpaperNightFile.exists()) {
        newWallpaper = FileImage(_wallpaperNightFile);
      } else if (await _wallpaperFile.exists()) {
        newWallpaper = FileImage(_wallpaperFile); // Fallback
      }
    } else {
      if (await _wallpaperFile.exists()) {
        newWallpaper = FileImage(_wallpaperFile);
      }
    }

    if (callId == _updateWallpaperCallCount) {
      if (_wallpaper != newWallpaper || force) {
        _wallpaper = newWallpaper;
        notifyListeners();
      }
    }
  }

  /// Refreshes the Bing "Photo of the Day" only if it hasn't been fetched yet today.
  Future<void> refreshBingWallpaperIfStale() async {
    try {
      final today = _dateStamp(DateTime.now());
      final lastFetched = await _wallpaperBingDateFile.exists() ? await _wallpaperBingDateFile.readAsString() : "";
      if (lastFetched.trim() != today || !await _wallpaperBingFile.exists()) {
        await refreshBingWallpaper();
      }
    } catch (e) {
      developer.log("Failed to check Bing wallpaper staleness", name: "WallpaperService", error: e);
    }
  }

  String _dateStamp(DateTime d) =>
      "${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}";

  /// Downloads Bing's current "Photo of the Day" and sets it as the wallpaper.
  /// Talks only to bing.com; nothing else, no analytics.
  Future<void> refreshBingWallpaper({bool force = false}) async {
    if (_bingRefreshInFlight) return;
    _bingRefreshInFlight = true;
    final httpClient = HttpClient();
    try {
      final metaRequest = await httpClient
          .getUrl(Uri.parse("https://www.bing.com/HPImageArchive.aspx?format=js&idx=0&n=1&mkt=en-US"));
      final metaResponse = await metaRequest.close();
      if (metaResponse.statusCode != 200) {
        throw Exception("Bing metadata request failed with ${metaResponse.statusCode}");
      }
      final metaBody = await metaResponse.transform(utf8.decoder).join();
      final Map<String, dynamic> json = jsonDecode(metaBody) as Map<String, dynamic>;
      final images = json['images'] as List<dynamic>?;
      if (images == null || images.isEmpty) {
        throw Exception("Bing metadata had no images");
      }
      final String urlBase = images.first['urlbase'] as String? ?? "";
      if (urlBase.isEmpty) {
        throw Exception("Bing metadata missing urlbase");
      }
      final imageUrl = "https://www.bing.com${urlBase}_1920x1080.jpg";

      final imageRequest = await httpClient.getUrl(Uri.parse(imageUrl));
      final imageResponse = await imageRequest.close();
      if (imageResponse.statusCode != 200) {
        throw Exception("Bing image download failed with ${imageResponse.statusCode}");
      }

      final bytes = await consolidateHttpClientResponseBytes(imageResponse);
      await _wallpaperBingFile.writeAsBytes(bytes, flush: true);
      await _wallpaperBingDateFile.writeAsString(_dateStamp(DateTime.now()), flush: true);

      await FileImage(_wallpaperBingFile).evict();
      _bingWallpaperError = false;
      _version++;
      await _updateWallpaper(force: true);
    } catch (e, stack) {
      developer.log("Failed to refresh Bing wallpaper", name: "WallpaperService", error: e, stackTrace: stack);
      _bingWallpaperError = true;
      notifyListeners();
    } finally {
      httpClient.close();
      _bingRefreshInFlight = false;
    }
  }

  Future<void> pickWallpaper() async {
    await _pickAndSave(_wallpaperFile);
  }

  Future<void> pickWallpaperDay() async {
    await _pickAndSave(_wallpaperDayFile);
  }

  Future<void> pickWallpaperNight() async {
    await _pickAndSave(_wallpaperNightFile);
  }

  Future<void> _pickAndSave(File targetFile) async {
    if (!await _fLauncherChannel.checkForGetContentAvailability()) {
      throw NoFileExplorerException();
    }

    final imagePicker = ImagePicker();
    final pickedFile = await imagePicker.pickImage(source: ImageSource.gallery);
    if (pickedFile != null) {
      // Use stream for memory efficiency
      final readStream = pickedFile.openRead();
      final writeStream = targetFile.openWrite();
      await readStream.cast<List<int>>().pipe(writeStream);

      // Evict from cache to ensure UI updates
      await FileImage(targetFile).evict();

      _version++;
      await _updateWallpaper(force: true);
    }
  }

  Future<void> setGradient(FLauncherGradient fLauncherGradient) async {
    if (await _wallpaperFile.exists()) {
      await _wallpaperFile.delete();
    }

    await _settingsService.setGradientUuid(fLauncherGradient.uuid);
    notifyListeners();
  }
}

class NoFileExplorerException implements Exception {}
