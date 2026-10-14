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
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flauncher/providers/ha_entities.dart';
import 'package:flauncher/widgets/ha_panel/ha_image_cache.dart';
import 'package:flauncher/quiet_failure.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// Map tiles around home, all fetched at once and then only read from disk.
///
/// Which tiles are asked for depends only on where home is, never on where anyone is, so the tile server never learns
/// a person's whereabouts: a person inside the area is drawn on tiles already on disk, and one outside it gets no map.
class HaMapTiles {
  /// The zone whose position the area is centred on; the panel follows it whenever a dashboard has someone to locate.
  static const String homeZone = "zone.home";

  /// Whether a tile for [entity] is about where someone (or something) is.
  static bool locates(HaEntity entity) => entity.domain == "person" || entity.domain == "device_tracker";

  static const int zoom = 14;

  /// Tiles each side of home's tile: a 9 x 9 square, about 17 km across at this latitude band.
  static const int radius = 4;
  static const double tileSize = 256;

  static String url(int x, int y) => "https://tile.openstreetmap.org/$zoom/$x/$y.png";

  /// The tile server asks every client to name itself.
  static const Map<String, String> headers = {"User-Agent": "Hearth/1 (Android TV launcher; Home Assistant panel)"};

  /// A point's position in pixels on the whole world map at [zoom] (Web Mercator).
  static Offset worldPixel(double latitude, double longitude) {
    final scale = tileSize * (1 << zoom);
    final lat = latitude.clamp(-85.05112878, 85.05112878) * math.pi / 180;
    final x = (longitude + 180) / 360 * scale;
    final y = (1 - math.log(math.tan(lat) + 1 / math.cos(lat)) / math.pi) / 2 * scale;
    return Offset(x, y);
  }

  /// The tile [pixel] falls in.
  static (int, int) tileOf(Offset pixel) => ((pixel.dx / tileSize).floor(), (pixel.dy / tileSize).floor());

  /// The pixel area the tiles around [home] cover.
  static Rect area(Offset home) {
    final (x, y) = tileOf(home);
    return Rect.fromLTRB(
        (x - radius) * tileSize, (y - radius) * tileSize, (x + radius + 1) * tileSize, (y + radius + 1) * tileSize);
  }

  /// Every tile around [home], in a fixed order.
  static List<(int, int)> around(Offset home) {
    final (x, y) = tileOf(home);
    return [
      for (var dy = -radius; dy <= radius; dy++)
        for (var dx = -radius; dx <= radius; dx++) (x + dx, y + dy)
    ];
  }

  /// Metres one pixel spans at [latitude].
  static double metresPerPixel(double latitude) =>
      156543.03392 * math.cos(latitude * math.pi / 180) / (1 << zoom);

  static final Map<(int, int), Future<bool>> _fetched = {};

  /// Fetches every tile around [home] (kept on disk by [HaImageCache]); true once all are there. Asked again it
  /// reuses the first attempt, unless that one failed.
  static Future<bool> ready(Offset home) {
    final key = tileOf(home);
    final previous = _fetched[key];
    if (previous != null) return previous;
    final attempt = _fetchAll(home);
    _fetched[key] = attempt;
    attempt.then((ok) {
      if (!ok) _fetched.remove(key);
    });
    return attempt;
  }

  static Future<bool> _fetchAll(Offset home) async {
    try {
      final tiles = around(home);
      // A few at a time, so the tile server isn't hit with all of them together
      for (var i = 0; i < tiles.length; i += 4) {
        await Future.wait([
          for (final (x, y) in tiles.skip(i).take(4)) HaImageCache.bytes(url(x, y), headers: headers),
        ]);
      }
      return true;
    } catch (err) {
        noteFailure('ha_person_map', err);
      return false;
    }
  }

  /// Forgets which areas were fetched; for tests.
  @visibleForTesting
  static void reset() => _fetched.clear();
}

/// An image read only from [HaImageCache]'s folder: it never goes to the network.
@immutable
class HaDiskImage extends ImageProvider<HaDiskImage> {
  final String url;

  const HaDiskImage(this.url);

  @override
  Future<HaDiskImage> obtainKey(ImageConfiguration configuration) => SynchronousFuture(this);

  @override
  ImageStreamCompleter loadImage(HaDiskImage key, ImageDecoderCallback decode) =>
      MultiFrameImageStreamCompleter(codec: _load(key, decode), scale: 1.0, debugLabel: key.url);

  static Future<ui.Codec> _load(HaDiskImage key, ImageDecoderCallback decode) async {
    final dir = await HaImageCache.directory();
    final file = File("${dir.path}${Platform.pathSeparator}${HaImageCache.fileName(key.url)}");
    return decode(await ui.ImmutableBuffer.fromUint8List(await file.readAsBytes()));
  }

  @override
  bool operator ==(Object other) => other is HaDiskImage && other.url == url;

  @override
  int get hashCode => url.hashCode;
}

/// Where [person] is, on a small map around home with home marked. Nothing when they have no position, home has
/// none, they're outside the area around home, or the tiles can't be had.
class HaPersonMap extends StatelessWidget {
  final HaEntity person;
  final HaEntity? home;
  final double height;

  const HaPersonMap({super.key, required this.person, required this.home, this.height = 170});

  static Offset? _position(HaEntity? entity) {
    final lat = entity?.number("latitude")?.toDouble();
    final lon = entity?.number("longitude")?.toDouble();
    if (lat == null || lon == null) return null;
    return HaMapTiles.worldPixel(lat, lon);
  }

  @override
  Widget build(BuildContext context) {
    final homePixel = _position(home);
    final personPixel = _position(person);
    if (homePixel == null || personPixel == null) return const SizedBox.shrink();
    final area = HaMapTiles.area(homePixel);
    if (!area.contains(personPixel)) return const SizedBox.shrink();
    return FutureBuilder<bool>(
      future: HaMapTiles.ready(homePixel),
      builder: (context, snapshot) {
        if (snapshot.data != true) return const SizedBox.shrink();
        return SizedBox(
          height: height,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: LayoutBuilder(
              builder: (context, constraints) =>
                  _map(context, constraints.maxWidth, homePixel, personPixel, area),
            ),
          ),
        );
      },
    );
  }

  Widget _map(BuildContext context, double width, Offset homePixel, Offset personPixel, Rect area) {
    // The window, centred on the person but kept inside the area that's on disk
    final left = (personPixel.dx - width / 2).clamp(area.left, math.max(area.left, area.right - width)).toDouble();
    final top = (personPixel.dy - height / 2).clamp(area.top, math.max(area.top, area.bottom - height)).toDouble();
    final window = Rect.fromLTWH(left, top, width, height);
    final accuracy = person.number("gps_accuracy")?.toDouble();
    final latitude = person.number("latitude")!.toDouble();
    final accuracyPixels = accuracy == null ? 0.0 : accuracy / HaMapTiles.metresPerPixel(latitude);
    final colour = Theme.of(context).colorScheme.primary;
    return Stack(
      clipBehavior: Clip.hardEdge,
      children: [
        for (final (x, y) in HaMapTiles.around(homePixel))
          if (Rect.fromLTWH(x * HaMapTiles.tileSize, y * HaMapTiles.tileSize, HaMapTiles.tileSize, HaMapTiles.tileSize)
              .overlaps(window))
            Positioned(
              left: x * HaMapTiles.tileSize - window.left,
              top: y * HaMapTiles.tileSize - window.top,
              width: HaMapTiles.tileSize,
              height: HaMapTiles.tileSize,
              child: Image(
                image: HaDiskImage(HaMapTiles.url(x, y)),
                fit: BoxFit.fill,
                gaplessPlayback: true,
                errorBuilder: (_, __, ___) => const ColoredBox(color: Color(0xFF2A2F38)),
              ),
            ),
        if (window.contains(homePixel))
          Positioned(
            left: homePixel.dx - window.left - 11,
            top: homePixel.dy - window.top - 11,
            child: const _HomeMarker(),
          ),
        if (accuracyPixels > 8)
          Positioned(
            left: personPixel.dx - window.left - accuracyPixels,
            top: personPixel.dy - window.top - accuracyPixels,
            child: Container(
              key: const ValueKey("ha-person-map-accuracy"),
              width: accuracyPixels * 2,
              height: accuracyPixels * 2,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: colour.withOpacity(0.15),
                border: Border.all(color: colour.withOpacity(0.5)),
              ),
            ),
          ),
        Positioned(
          left: personPixel.dx - window.left - 8,
          top: personPixel.dy - window.top - 8,
          child: Container(
            key: const ValueKey("ha-person-map-marker"),
            width: 16,
            height: 16,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: colour,
              border: Border.all(color: Colors.white, width: 2.5),
            ),
          ),
        ),
        Positioned(
          right: 4,
          bottom: 2,
          child: Text("© OpenStreetMap",
              style: Theme.of(context).textTheme.labelSmall!.copyWith(
                    fontSize: 9,
                    color: Colors.black87,
                    backgroundColor: Colors.white70,
                  )),
        ),
      ],
    );
  }
}

class _HomeMarker extends StatelessWidget {
  const _HomeMarker();

  @override
  Widget build(BuildContext context) => Container(
        width: 22,
        height: 22,
        decoration: const BoxDecoration(color: Colors.black54, shape: BoxShape.circle),
        child: const Icon(Icons.home, size: 14, color: Colors.white),
      );
}
