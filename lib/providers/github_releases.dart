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

const _abiPattern = r"(arm64-v8a|armeabi-v7a|armeabi|x86_64|x86)";

/// Compares dotted versions numerically ("2026.10.05" > "2026.10.03+8112"); a leading "v" and any
/// non-digits in a part are ignored, and missing parts count as 0.
int compareVersions(String left, String right) {
  List<int> parts(String version) {
    var v = version.trim();
    if (v.startsWith("v") || v.startsWith("V")) v = v.substring(1);
    return v.split(RegExp(r"[.+]")).map((p) => int.tryParse(p.replaceAll(RegExp(r"[^0-9]"), "")) ?? 0).toList();
  }

  final l = parts(left), r = parts(right);
  for (var i = 0; i < (l.length > r.length ? l.length : r.length); i++) {
    final a = i < l.length ? l[i] : 0, b = i < r.length ? r[i] : 0;
    if (a != b) return a.compareTo(b);
  }
  return 0;
}

/// The ABI token may sit anywhere between separators: "LTvLauncher-armeabi-v7a-release.apk", "app-arm64-v8a.apk".
/// Picks the release APK for this device: one built for its ABIs (in preference order), else a universal APK.
/// Never returns an APK built for another ABI — it would fail to install (e.g. arm64 on a 32-bit stick).
/// With [accept], only APKs whose file name it accepts are considered.
Map<String, dynamic>? pickApkAsset(List<dynamic> assets, List<String> deviceAbis,
    {bool Function(String name)? accept}) {
  final apks = assets
      .whereType<Map<String, dynamic>>()
      .where((a) => (a['name'] as String? ?? "").toLowerCase().endsWith(".apk") && a['browser_download_url'] is String)
      .where((a) => accept == null || accept(a['name'] as String))
      .toList();
  String? abiOf(Map<String, dynamic> asset) =>
      RegExp(r"(?:^|[-_.])" "$_abiPattern" r"(?=[-_.])", caseSensitive: false).firstMatch(asset['name'] as String)?.group(1)?.toLowerCase();

  for (final abi in deviceAbis) {
    for (final apk in apks) {
      if (abiOf(apk) == abi.toLowerCase()) return apk;
    }
  }
  for (final apk in apks) {
    if (abiOf(apk) == null) return apk;
  }
  return null;
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
