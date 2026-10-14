/*
 * Hearth
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

import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// The ABIs an APK's file name can be built for, longest first so "armeabi-v7a" isn't read as "armeabi".
const _knownAbis = ["armeabi-v7a", "arm64-v8a", "x86_64", "armeabi", "x86"];

/// Whether [version] is newer (> 0), older (< 0) or the same as [other], part by part as numbers: "2026.10.5" is newer
/// than "2026.10.3+8112", and "v2026.10.3+8112" is the same as "2026.10.3+8112". A missing part counts as 0.
int compareVersions(String version, String other) {
  List<int> numbers(String v) => RegExp(r"\d+").allMatches(v).map((m) => int.parse(m.group(0)!)).toList();
  final a = numbers(version);
  final b = numbers(other);
  final length = a.length > b.length ? a.length : b.length;
  for (var i = 0; i < length; i++) {
    final x = i < a.length ? a[i] : 0;
    final y = i < b.length ? b[i] : 0;
    if (x != y) return x < y ? -1 : 1;
  }
  return 0;
}

/// The ABI an APK file name says it's built for ("Hearth-armeabi-v7a-release.apk"), or null for a universal one.
/// The ABI must stand between separators (or at the start), so a word that merely contains one doesn't count.
String? apkAbi(String fileName) {
  final name = fileName.toLowerCase();
  bool separator(int at) => at < 0 || at >= name.length || "-_.".contains(name[at]);
  for (final abi in _knownAbis) {
    for (var at = name.indexOf(abi); at >= 0; at = name.indexOf(abi, at + 1)) {
      if (separator(at - 1) && at + abi.length < name.length && separator(at + abi.length)) return abi;
    }
  }
  return null;
}

/// The release's APK for this device: the first of its ABIs ([deviceAbis], most preferred first) that an APK is built
/// for, else a universal APK, and never one built for an ABI the device lacks (an arm64 APK won't install on a 32-bit
/// stick). [accept], when given, limits which file names count.
Map<String, dynamic>? pickApkAsset(List<dynamic> assets, List<String> deviceAbis,
    {bool Function(String name)? accept}) {
  final byAbi = <String?, Map<String, dynamic>>{};
  for (final asset in assets.whereType<Map<String, dynamic>>()) {
    final name = asset['name'];
    if (name is! String || !name.toLowerCase().endsWith(".apk") || asset['browser_download_url'] is! String) continue;
    if (accept != null && !accept(name)) continue;
    byAbi.putIfAbsent(apkAbi(name), () => asset);
  }
  for (final abi in deviceAbis) {
    final apk = byAbi[abi.toLowerCase()];
    if (apk != null) return apk;
  }
  return byAbi[null];
}

/// A file in the folder downloaded APKs go to, in the app's external files.
Future<File> downloadedApkFile(String name) async {
  final dir = await getExternalStorageDirectory();
  if (dir == null) throw Exception("No external storage directory available");
  final updates = Directory("${dir.path}/updates");
  await updates.create(recursive: true);
  return File("${updates.path}/$name");
}

/// A published release and its APK for this device.
class GitHubRelease {
  final Map<String, dynamic> json;
  final Map<String, dynamic> apk;

  GitHubRelease(this.json, this.apk);

  String get tagName => json['tag_name'] as String? ?? "";

  /// The tag without its leading "v".
  String get version => tagName.startsWith("v") ? tagName.substring(1) : tagName;

  String get name => json['name'] as String? ?? "";
  String get body => json['body'] as String? ?? "";
  List<Map<String, dynamic>> get assets => ((json['assets'] as List<dynamic>?) ?? []).whereType<Map<String, dynamic>>().toList();
  String get apkUrl => apk['browser_download_url'] as String;
  int get apkSize => apk['size'] as int? ?? 0;
}

/// Reads a GitHub repository's releases and downloads their files. Talks only to api.github.com and the download
/// URLs it returns.
class GitHubReleases {
  final String repo;
  final String userAgent;
  final Uri _api;

  /// [repo] is "owner/name".
  GitHubReleases(this.repo, {required this.userAgent, Uri? api}) : _api = api ?? Uri.parse("https://api.github.com");

  /// The newest release among the last [perPage] that isn't a draft or pre-release and has an APK for [abis].
  /// The full list, not /latest, so a newer release without an APK for this device doesn't hide an older one.
  /// With [accept], only APKs whose file name it accepts count (see [pickApkAsset]).
  /// With [includePrereleases], pre-releases count too; drafts never do.
  Future<GitHubRelease?> latestWithApk(List<String> abis,
      {int perPage = 20, bool Function(String name)? accept, bool includePrereleases = false}) async {
    final releases = await getJson(_api.resolve("/repos/$repo/releases?per_page=$perPage")) as List<dynamic>;
    for (final release in releases.whereType<Map<String, dynamic>>()) {
      if (release['draft'] == true) continue;
      if (release['prerelease'] == true && !includePrereleases) continue;
      final apk = pickApkAsset((release['assets'] as List<dynamic>?) ?? [], abis, accept: accept);
      if (apk != null) return GitHubRelease(release, apk);
    }
    return null;
  }

  Future<dynamic> getJson(Uri uri) async {
    final client = HttpClient();
    try {
      final request = await client.getUrl(uri);
      request.headers.set(HttpHeaders.acceptHeader, "application/vnd.github+json");
      request.headers.set(HttpHeaders.userAgentHeader, userAgent);
      final response = await request.close();
      if (response.statusCode != 200) throw Exception("GitHub API returned ${response.statusCode}");
      return jsonDecode(await response.transform(utf8.decoder).join());
    } finally {
      client.close();
    }
  }

  /// Downloads [url] into [file], reporting progress (0–1) when the size is known: [size], else the response's.
  Future<void> download(String url, File file, {int size = 0, void Function(double)? onProgress}) async {
    final client = HttpClient();
    try {
      final request = await client.getUrl(Uri.parse(url));
      request.headers.set(HttpHeaders.userAgentHeader, userAgent);
      final response = await request.close();
      if (response.statusCode != 200) throw Exception("Download failed (${response.statusCode})");
      final total = size > 0 ? size : response.contentLength;
      final sink = file.openWrite();
      var received = 0;
      try {
        await response.listen((chunk) {
          sink.add(chunk);
          received += chunk.length;
          if (total > 0) onProgress?.call(received / total);
        }).asFuture();
      } finally {
        await sink.close();
      }
    } finally {
      client.close();
    }
  }
}
