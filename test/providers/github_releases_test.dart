import 'dart:convert';
import 'dart:io';

import 'package:flauncher/providers/github_releases.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> asset(String name) => {"name": name, "browser_download_url": "https://example/$name", "size": 1};

void main() {
  group("compareVersions", () {
    test("orders date-style versions and ignores a leading v", () {
      expect(compareVersions("v2026.10.05", "2026.10.03+8112"), greaterThan(0));
      expect(compareVersions("2026.10.03", "2026.10.03+8112"), lessThan(0));
      expect(compareVersions("2026.10.03+8112", "v2026.10.03+8112"), 0);
      expect(compareVersions("2026.9.30", "2026.10.1"), lessThan(0));
    });
  });

  group("pickApkAsset", () {
    final splitRelease = [
      asset("ltvlauncher-2026.10.05-arm64-v8a.apk"),
      asset("ltvlauncher-2026.10.05-armeabi-v7a.apk"),
      asset("checksums.txt"),
    ];

    test("picks the APK built for the device's ABI", () {
      expect(pickApkAsset(splitRelease, ["armeabi-v7a", "armeabi"])!["name"], "ltvlauncher-2026.10.05-armeabi-v7a.apk");
      expect(pickApkAsset(splitRelease, ["arm64-v8a", "armeabi-v7a"])!["name"], "ltvlauncher-2026.10.05-arm64-v8a.apk");
    });

    test("falls back to a universal APK, never to another ABI", () {
      expect(pickApkAsset([asset("ltvlauncher-2026.10.05.apk"), ...splitRelease], ["x86"])!["name"],
          "ltvlauncher-2026.10.05.apk");
      expect(pickApkAsset(splitRelease, ["x86"]), isNull);
    });

    test("understands this repo's release workflow names", () {
      final workflowRelease = [
        asset("Hearth-universal-release.apk"),
        asset("Hearth-armeabi-v7a-release.apk"),
        asset("Hearth-arm64-v8a-release.apk"),
      ];
      expect(pickApkAsset(workflowRelease, ["armeabi-v7a", "armeabi"])!["name"], "Hearth-armeabi-v7a-release.apk");
      expect(pickApkAsset(workflowRelease, ["arm64-v8a"])!["name"], "Hearth-arm64-v8a-release.apk");
      expect(pickApkAsset(workflowRelease, ["x86_64"])!["name"], "Hearth-universal-release.apk");
    });
  });

  group("GitHubReleases", () {
    late HttpServer server;
    late Uri api;
    final requests = <HttpRequest>[];

    setUp(() async {
      requests.clear();
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      api = Uri.parse("http://${server.address.host}:${server.port}");
      server.listen((request) {
        requests.add(request);
        final response = request.response;
        if (request.uri.path == "/repos/owner/app/releases") {
          response.write(jsonEncode([
            {"tag_name": "v3", "draft": true, "assets": [asset("app.apk")]},
            {"tag_name": "v2", "prerelease": true, "assets": [asset("app.apk")]},
            {"tag_name": "v1.5", "assets": [asset("app-x86.apk")]},
            {"tag_name": "v1", "body": "Notes", "assets": [{"name": "app.apk", "browser_download_url": "$api/app.apk", "size": 4}]},
          ]));
        } else if (request.uri.path == "/app.apk") {
          response
            ..contentLength = 4
            ..add([1, 2, 3, 4]);
        } else {
          response.statusCode = 404;
        }
        response.close();
      });
    });

    tearDown(() => server.close(force: true));

    test("finds the newest published release with an APK for this device", () async {
      final release = await GitHubReleases("owner/app", userAgent: "Hearth-Test", api: api).latestWithApk(["arm64-v8a"]);

      expect(release!.tagName, "v1");
      expect(release.version, "1");
      expect(release.body, "Notes");
      expect(release.apkSize, 4);
      expect(requests.single.uri.queryParameters["per_page"], "20");
      expect(requests.single.headers.value(HttpHeaders.userAgentHeader), "Hearth-Test");
    });

    test("downloads into the file with progress, and fails on an HTTP error", () async {
      final releases = GitHubReleases("owner/app", userAgent: "Hearth-Test", api: api);
      final dir = await Directory.systemTemp.createTemp("github_releases_test");
      addTearDown(() => dir.delete(recursive: true));
      final file = File("${dir.path}/app.apk");
      final progress = <double>[];

      await releases.download("$api/app.apk", file, onProgress: progress.add);

      expect(await file.readAsBytes(), [1, 2, 3, 4]);
      expect(progress.last, 1.0);
      await expectLater(releases.download("$api/missing.apk", file), throwsException);
    });
  });
}
