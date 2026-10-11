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

import 'dart:io';
import 'dart:typed_data';

import 'package:flauncher/widgets/ha_panel/ha_image_cache.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory dir;
  late int fetches;
  late bool online;
  late DateTime today;
  const url = "https://images.example.com/app.png";

  setUp(() async {
    dir = await Directory.systemTemp.createTemp("ha_images_test");
    fetches = 0;
    online = true;
    today = DateTime(2026, 10, 11);
    HaImageCache.directory = () async => dir;
    HaImageCache.now = () => today;
    HaImageCache.fetch = (uri, headers) async {
      fetches++;
      if (!online) throw const SocketException("offline");
      return Uint8List.fromList([1, 2, 3, fetches]);
    };
  });

  tearDown(() async {
    if (await dir.exists()) await dir.delete(recursive: true);
  });

  test("Fetched once, then read from disk while it's fresh", () async {
    final first = await HaImageCache.bytes(url);
    final again = await HaImageCache.bytes(url);
    expect(fetches, 1);
    expect(again, first);
    expect(File("${dir.path}${Platform.pathSeparator}${HaImageCache.fileName(url)}").existsSync(), isTrue);
  });

  test("Fetched again after 30 days", () async {
    await HaImageCache.bytes(url);
    // The file's age counts from when it was written: move "today" past it
    today = DateTime.now().add(const Duration(days: 31));
    final fresh = await HaImageCache.bytes(url);
    expect(fetches, 2);
    expect(fresh.last, 2);
  });

  test("Offline, an old copy is used; with none, it fails", () async {
    await HaImageCache.bytes(url);
    today = DateTime.now().add(const Duration(days: 31));
    online = false;
    final stale = await HaImageCache.bytes(url);
    expect(stale.last, 1);
    await expectLater(HaImageCache.bytes("https://images.example.com/other.png"), throwsA(isA<SocketException>()));
  });
}
