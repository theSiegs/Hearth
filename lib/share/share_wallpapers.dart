import 'dart:io';
import 'dart:typed_data';

import 'package:flauncher/flauncher_channel.dart';
import 'package:flauncher/providers/wallpaper_service.dart';
import 'package:flauncher/share/share_bundle.dart';
import 'package:path_provider/path_provider.dart';

/// A profile's wallpaper pictures as a copy to another TV reads and writes them: the files WallpaperService keeps in
/// the profile's own folder. What is sent is the picture as the screen shows it (no larger than 1920x1080, a JPEG);
/// what arrives was checked as a JPEG of a wallpaper's size (ShareBundle) and only ever goes to the three fixed names.
class ShareWallpapers {
  static const Map<String, String> fileNames = {"any": "wallpaper", "day": "wallpaper_day", "night": "wallpaper_night"};

  final FLauncherChannel _channel;

  ShareWallpapers(this._channel);

  Future<String> _folder(String profileKey) async {
    final documents = await getApplicationDocumentsDirectory();
    return "${documents.path}/${WallpaperService.profileFolder(profileKey)}";
  }

  /// The pictures this profile has picked, by slot; none when it has none.
  Future<Map<String, Uint8List>> read(String profileKey) async {
    final folder = await _folder(profileKey);
    final pictures = <String, Uint8List>{};
    for (final entry in fileNames.entries) {
      final path = "$folder/${entry.value}";
      if (!await File(path).exists()) continue;
      final jpeg = await _channel.getShareWallpaper(path);
      if (jpeg != null && jpeg.isNotEmpty && jpeg.length <= ShareBundle.maxPictureBytes) pictures[entry.key] = jpeg;
    }
    return pictures;
  }

  /// Where the profile's picture for [slot] is kept (it may not be there).
  Future<File> file(String profileKey, String slot) async =>
      File("${await _folder(profileKey)}/${fileNames[slot] ?? fileNames["any"]}");

  /// Takes the profile's picture for [slot] away (household sync: it was taken away on another TV).
  Future<void> delete(String profileKey, String slot) async {
    if (!fileNames.containsKey(slot)) return;
    final picture = await file(profileKey, slot);
    if (await picture.exists()) await picture.delete();
  }

  /// Puts the pictures in the profile's folder (replacing the ones in those slots); how many were written.
  Future<int> write(String profileKey, Map<String, Uint8List> pictures) async {
    final folder = await _folder(profileKey);
    var written = 0;
    for (final entry in pictures.entries) {
      final name = fileNames[entry.key];
      if (name == null) continue;
      await Directory(folder).create(recursive: true);
      await File("$folder/$name").writeAsBytes(entry.value, flush: true);
      written++;
    }
    return written;
  }
}
