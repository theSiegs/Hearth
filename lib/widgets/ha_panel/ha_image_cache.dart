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

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:path_provider/path_provider.dart';

/// Images the panel shows again and again (app icons in the screen time cards), kept on disk by their address: read
/// from there for [maxAge], fetched again after that, and the old copy used when the fetch fails (offline, Home
/// Assistant away). Flutter's own image cache keeps them in memory on top of this.
class HaImageCache {
  static const Duration maxAge = Duration(days: 30);

  /// Where the files go; the app's cache folder unless a test sets it.
  static Future<Directory> Function() directory = () async {
    final base = await getApplicationCacheDirectory();
    return Directory("${base.path}${Platform.pathSeparator}ha_images");
  };

  /// Fetches an image's bytes; a test may replace it.
  static Future<Uint8List> Function(Uri uri, Map<String, String> headers) fetch = _httpFetch;

  /// Today, for the age check; a test may replace it.
  static DateTime Function() now = DateTime.now;

  static String fileName(String url) => sha1.convert(utf8.encode(url)).toString();

  /// The image at [url]: from disk while fresh, else fetched (and kept); a stale copy when the fetch fails.
  static Future<Uint8List> bytes(String url, {Map<String, String> headers = const {}}) async {
    final dir = await directory();
    final file = File("${dir.path}${Platform.pathSeparator}${fileName(url)}");
    final exists = await file.exists();
    if (exists && now().difference(await file.lastModified()) < maxAge) return file.readAsBytes();
    try {
      final data = await fetch(Uri.parse(url), headers);
      if (data.isEmpty) throw const HttpException("empty image");
      await dir.create(recursive: true);
      await file.writeAsBytes(data, flush: true);
      return data;
    } catch (e) {
      if (exists) return file.readAsBytes();
      rethrow;
    }
  }

  static Future<Uint8List> _httpFetch(Uri uri, Map<String, String> headers) async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 10);
    try {
      final request = await client.getUrl(uri);
      headers.forEach(request.headers.set);
      final response = await request.close().timeout(const Duration(seconds: 15));
      if (response.statusCode != HttpStatus.ok) throw HttpException("HTTP ${response.statusCode}", uri: uri);
      return await consolidateHttpClientResponseBytes(response);
    } finally {
      client.close();
    }
  }
}

/// An [ImageProvider] for [HaImageCache]: an image kept on disk by its address.
@immutable
class HaCachedImage extends ImageProvider<HaCachedImage> {
  final String url;
  final Map<String, String> headers;

  const HaCachedImage(this.url, {this.headers = const {}});

  @override
  Future<HaCachedImage> obtainKey(ImageConfiguration configuration) => SynchronousFuture(this);

  @override
  ImageStreamCompleter loadImage(HaCachedImage key, ImageDecoderCallback decode) {
    return MultiFrameImageStreamCompleter(
      codec: _load(key, decode),
      scale: 1.0,
      debugLabel: key.url,
    );
  }

  static Future<ui.Codec> _load(HaCachedImage key, ImageDecoderCallback decode) async {
    final data = await HaImageCache.bytes(key.url, headers: key.headers);
    return decode(await ui.ImmutableBuffer.fromUint8List(data));
  }

  @override
  bool operator ==(Object other) => other is HaCachedImage && other.url == url;

  @override
  int get hashCode => url.hashCode;
}
