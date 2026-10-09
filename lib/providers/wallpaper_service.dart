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
  final ImagePicker _imagePicker;

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
  late File _wallpaperBingInfoFile;
  Timer? _dayNightTimer;
  Timer? _bingTimer;
  bool _bingRefreshInFlight = false;

  ImageProvider? _wallpaper;
  int _version = 0;
  int _updateWallpaperCallCount = 0;
  bool _bingWallpaperError = false;

  bool get bingWallpaperError => _bingWallpaperError;

  // The picture shown (null: the gradient), and the Bing photo's title and credit as Bing gave them
  File? _shownFile;
  String? _bingTitle;
  String? _bingCredit;

  /// When Bing's photo shown now started being its photo of the day (UTC), from its "fullstartdate"; null when
  /// unknown (fetched by an older Hearth).
  DateTime? _bingStart;

  /// Whether the shown Bing photo was saved with its start time (by this version or later).
  bool _bingStartRecorded = false;
  bool _initialized = false;
  String? _lastPublishedState;

  String? get bingTitle => _bingTitle;
  String? get bingCredit => _bingCredit;

  ImageProvider?  get wallpaper     => _wallpaper;
  int             get version       => _version;

  /// How light the picture behind the home is, 0 (black) to 1 (white): the wallpaper's average, or the gradient's.
  /// Row titles sit on a darker pill the lighter it is.
  double get brightness => _wallpaper != null ? (_wallpaperBrightness ?? 0.5) : gradientBrightness(gradient.gradient);
  double? _wallpaperBrightness;

  static double gradientBrightness(Gradient gradient) {
    final colors = gradient.colors;
    if (colors.isEmpty) return 0;
    return colors.map((c) => c.computeLuminance()).reduce((a, b) => a + b) / colors.length;
  }

  /// The average luminance of an image file, from a copy a few dozen pixels wide.
  static Future<double?> imageBrightness(File file) async {
    try {
      final codec = await ui.instantiateImageCodec(await file.readAsBytes(), targetWidth: 32);
      final frame = await codec.getNextFrame();
      final data = await frame.image.toByteData(format: ui.ImageByteFormat.rawRgba);
      frame.image.dispose();
      if (data == null) return null;
      return averageLuminance(data.buffer.asUint8List());
    } catch (e) {
      developer.log("Couldn't measure the wallpaper", name: "WallpaperService", error: e);
      return null;
    }
  }

  /// Mean relative luminance (0-1) of RGBA pixels.
  static double averageLuminance(Uint8List rgba) {
    double sum = 0;
    int count = 0;
    for (int i = 0; i + 3 < rgba.length; i += 4) {
      sum += 0.2126 * rgba[i] + 0.7152 * rgba[i + 1] + 0.0722 * rgba[i + 2];
      count++;
    }
    return count == 0 ? 0 : sum / count / 255;
  }

  FLauncherGradient get gradient => FLauncherGradients.all.firstWhere(
        (gradient) => gradient.uuid == _settingsService.gradientUuid,
        orElse: () => FLauncherGradients.pitchBlack,
      );

  WallpaperService(this._fLauncherChannel, this._settingsService, {ImagePicker? imagePicker}) :
    _imagePicker = imagePicker ?? ImagePicker(),
    _wallpaper = null
  {
    _settingsService.addListener(_onSettingsChanged);
    WidgetsBinding.instance.addObserver(this);
    _init();
  }

  bool _lastTimeBasedEnabled = false;
  bool _lastBingEnabled = false;
  String? _lastGradientUuid;

  void _onSettingsChanged() {
    // A new gradient changes [brightness] when there's no wallpaper picture
    final gradientUuid = _settingsService.gradientUuid;
    if (gradientUuid != _lastGradientUuid) {
      _lastGradientUuid = gradientUuid;
      if (_wallpaper == null) notifyListeners();
      _publishState();
    }
    final timeBasedEnabled = _settingsService.timeBasedWallpaperEnabled;
    final bingEnabled = _settingsService.bingWallpaperEnabled;
    final timeBasedChanged = timeBasedEnabled != _lastTimeBasedEnabled;
    final bingChanged = bingEnabled != _lastBingEnabled;

    if (timeBasedChanged || bingChanged) {
      _lastTimeBasedEnabled = timeBasedEnabled;
      _lastBingEnabled = bingEnabled;
      _updateTimerState();
      if (bingChanged && bingEnabled) {
        refreshBingWallpaper();
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
    // The hourly check doesn't run while the TV sleeps: look for a newer Bing photo on coming back
    if (state == AppLifecycleState.resumed && _initialized && _settingsService.bingWallpaperEnabled) {
      unawaited(refreshBingWallpaperIfStale());
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
    _wallpaperBingInfoFile = File("${directory.path}/wallpaper_bing_info");
    await _loadBingInfo();

    _lastTimeBasedEnabled = _settingsService.timeBasedWallpaperEnabled;
    _lastBingEnabled = _settingsService.bingWallpaperEnabled;
    _initialized = true;
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

    File? file;

    if (bingEnabled && await _wallpaperBingFile.exists()) {
      file = _wallpaperBingFile;
    } else if (timeBasedEnabled) {
      if (isDay && await _wallpaperDayFile.exists()) {
        file = _wallpaperDayFile;
      } else if (!isDay && await _wallpaperNightFile.exists()) {
        file = _wallpaperNightFile;
      } else if (await _wallpaperFile.exists()) {
        file = _wallpaperFile; // Fallback
      }
    } else {
      if (await _wallpaperFile.exists()) {
        file = _wallpaperFile;
      }
    }
    final ImageProvider? newWallpaper = file != null ? FileImage(file) : null;

    if (callId == _updateWallpaperCallCount) {
      if (_wallpaper != newWallpaper || force) {
        _wallpaper = newWallpaper;
        _shownFile = file;
        notifyListeners();
        final brightness = file != null ? await imageBrightness(file) : null;
        if (callId == _updateWallpaperCallCount && brightness != _wallpaperBrightness) {
          _wallpaperBrightness = brightness;
          notifyListeners();
        }
      }
      if (callId == _updateWallpaperCallCount) _publishState();
    }
  }

  /// What HearthTube gets of the wallpaper through Hearth's provider (ProfileProvider, HearthWallpaper.java;
  /// docs/design/wallpaper-sync.md). Android picks the picture file itself; this adds what only Flutter knows.
  Map<String, Object?> get providerState {
    final gradient = this.gradient.gradient;
    final gradientBrightness = WallpaperService.gradientBrightness(gradient);
    return {
      "file": _shownFile?.uri.pathSegments.last,
      "brightness": _shownFile != null ? _wallpaperBrightness : null,
      "gradient_uuid": _settingsService.gradientUuid,
      "gradient": jsonEncode(describeGradient(gradient, gradientBrightness)),
      "gradient_brightness": gradientBrightness,
      "bing_title": _bingTitle,
      "bing_credit": _bingCredit,
      // A new picture in the same file (a new pick, a new day's Bing photo) is news too
      "picked": _version,
    };
  }

  /// Tells the provider when [providerState] changed, which tells HearthTube.
  void _publishState() {
    if (!_initialized) return;
    final state = providerState;
    final encoded = jsonEncode(state);
    if (encoded == _lastPublishedState) return;
    _lastPublishedState = encoded;
    unawaited(_fLauncherChannel.setWallpaperState(state));
  }

  /// A gradient for another app to draw: colors as "#AARRGGBB", stops (null: evenly spaced), and for a linear one
  /// its begin and end as alignments (-1..1 across the screen, x to the right, y down) turned by `rotation` radians
  /// clockwise about the screen's center; for a radial one its center and radius (a fraction of the shorter side).
  @visibleForTesting
  static Map<String, Object?> describeGradient(Gradient gradient, double brightness) {
    Map<String, double> point(AlignmentGeometry a) {
      final alignment = a.resolve(TextDirection.ltr);
      return {"x": alignment.x, "y": alignment.y};
    }

    final transform = gradient.transform;
    final description = <String, Object?>{
      "colors": [for (final c in gradient.colors) "#${c.value.toRadixString(16).padLeft(8, '0').toUpperCase()}"],
      "stops": gradient.stops,
      "rotation": transform is GradientRotation ? transform.radians : 0.0,
      "brightness": brightness,
    };
    if (gradient is LinearGradient) {
      description.addAll({"type": "linear", "begin": point(gradient.begin), "end": point(gradient.end)});
    } else if (gradient is RadialGradient) {
      description.addAll({"type": "radial", "center": point(gradient.center), "radius": gradient.radius});
    } else {
      description["type"] = "other";
    }
    return description;
  }

  Future<void> _loadBingInfo() async {
    try {
      if (!await _wallpaperBingInfoFile.exists()) return;
      final info = jsonDecode(await _wallpaperBingInfoFile.readAsString()) as Map<String, dynamic>;
      _bingTitle = info["title"] as String?;
      _bingCredit = info["copyright"] as String?;
      _bingStart = DateTime.tryParse(info["start"] as String? ?? "");
      _bingStartRecorded = info.containsKey("start");
    } catch (e) {
      developer.log("Couldn't read the Bing photo's credit", name: "WallpaperService", error: e);
    }
  }

  /// The title and credit of Bing's photo, from its metadata (empty ones are none).
  @visibleForTesting
  static ({String? title, String? credit}) bingInfo(Map<String, dynamic> image) {
    String? text(Object? value) => value is String && value.trim().isNotEmpty ? value.trim() : null;
    return (title: text(image['title']), credit: text(image['copyright']));
  }

  /// Bing's "fullstartdate" ("202610090700", UTC) as a time; null when it isn't one.
  @visibleForTesting
  static DateTime? bingStart(Object? fullStartDate) {
    final s = fullStartDate is String ? fullStartDate.trim() : "";
    if (!RegExp(r'^\d{12}$').hasMatch(s)) return null;
    return DateTime.utc(int.parse(s.substring(0, 4)), int.parse(s.substring(4, 6)), int.parse(s.substring(6, 8)),
        int.parse(s.substring(8, 10)), int.parse(s.substring(10, 12)));
  }

  /// Whether Bing has a newer photo than the one shown: a day has passed since the shown one became Bing's photo
  /// of the day. Bing changes its photo at its own hour (07:00 UTC for en-US), not at local midnight, so a fetch
  /// just after midnight here gets the day before's photo; with no start known, once a calendar day.
  @visibleForTesting
  static bool bingIsStale({required DateTime now, required DateTime? start, required String lastFetchedDay}) {
    if (start != null) return !now.toUtc().isBefore(start.add(const Duration(days: 1)));
    final today = "${now.year.toString().padLeft(4, '0')}-${now.month.toString().padLeft(2, '0')}-"
        "${now.day.toString().padLeft(2, '0')}";
    return lastFetchedDay.trim() != today;
  }

  /// Refreshes the Bing "Photo of the Day" only when Bing has a newer one (see [bingIsStale]).
  Future<void> refreshBingWallpaperIfStale() async {
    try {
      final lastFetched = await _wallpaperBingDateFile.exists() ? await _wallpaperBingDateFile.readAsString() : "";
      // A photo saved without its start time (an older Hearth) is fetched once more to learn it
      if (!await _wallpaperBingFile.exists() ||
          !_bingStartRecorded ||
          bingIsStale(now: DateTime.now(), start: _bingStart, lastFetchedDay: lastFetched)) {
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
  Future<void> refreshBingWallpaper() async {
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
      final info = bingInfo(images.first as Map<String, dynamic>);
      _bingTitle = info.title;
      _bingCredit = info.credit;
      _bingStart = bingStart(images.first['fullstartdate']);
      _bingStartRecorded = true;
      await _wallpaperBingInfoFile.writeAsString(
          jsonEncode({"title": info.title, "copyright": info.credit, "start": _bingStart?.toIso8601String()}),
          flush: true);

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

    final pickedFile = await _imagePicker.pickImage(source: ImageSource.gallery);
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
    // A picture picked before is gone: show what's left (the gradient, or a day/night or Bing picture)
    await _updateWallpaper(force: true);
  }
}

class NoFileExplorerException implements Exception {}
