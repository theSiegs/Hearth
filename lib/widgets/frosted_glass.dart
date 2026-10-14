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
import 'dart:ui' as ui;

import 'package:flauncher/providers/wallpaper_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:provider/provider.dart';

/// The shade the home paints over the wallpaper, top to bottom, so text stays readable on any picture. Frosted glass
/// bakes it into its blur, so a panel matches what's behind it.
const List<Color> kWallpaperShadeColors = [Color(0x59000000), Color(0x26000000), Color(0x73000000)];

/// Frosted glass over the home's wallpaper: [child] on a blurred view of the wallpaper behind it.
///
/// A [BackdropFilter] blurs the whole scene again on every frame, which a TV stick can't afford for a dock that's
/// always on screen. The wallpaper only changes when it's replaced, so it's blurred once per screen size and strength
/// (shared by every panel that uses the same strength), and each panel shows the piece that lies under it. While that
/// image is being made, and while the background follows the focused app's colour (which animates), a live blur stands
/// in.
class FrostedGlass extends StatelessWidget {
  final double sigma;
  final Widget child;

  const FrostedGlass({super.key, required this.sigma, required this.child});

  @override
  Widget build(BuildContext context) {
    final wallpaper = context.watch<WallpaperService>();
    final live = BackdropFilter(filter: ui.ImageFilter.blur(sigmaX: sigma, sigmaY: sigma), child: child);
    if (wallpaper.focusedAppColor != null) return live;
    final screen = MediaQuery.sizeOf(context);
    if (screen.isEmpty) return live;
    final blur = _BlurredWallpaper.of(wallpaper, screen, MediaQuery.devicePixelRatioOf(context), sigma);
    return ValueListenableBuilder<ui.Image?>(
      valueListenable: blur.image,
      builder: (_, image, __) => image == null ? live : _GlassWindow(image: image, screen: screen, child: child),
    );
  }
}

/// One blurred wallpaper image for a wallpaper, screen size and strength; made in the background, kept while that's
/// what the home shows.
class _BlurredWallpaper {
  static final Map<String, _BlurredWallpaper> _made = {};

  final ValueNotifier<ui.Image?> image = ValueNotifier(null);

  _BlurredWallpaper._();

  static _BlurredWallpaper of(WallpaperService wallpaper, Size screen, double pixelRatio, double sigma) {
    final picture = wallpaper.wallpaper == null ? "gradient:${wallpaper.gradient.uuid}" : "image:${wallpaper.version}";
    final key = "$picture|${screen.width}x${screen.height}@$pixelRatio|$sigma";
    final known = _made[key];
    if (known != null) return known;
    // Another wallpaper or size for this strength: the old image goes
    _made.removeWhere((k, old) {
      final gone = k.endsWith("|$sigma");
      if (gone) old.image.value?.dispose();
      return gone;
    });
    final made = _BlurredWallpaper._();
    _made[key] = made;
    made._make(wallpaper, screen, pixelRatio, sigma);
    return made;
  }

  Future<void> _make(WallpaperService wallpaper, Size screen, double pixelRatio, double sigma) async {
    ui.Image? photo;
    try {
      final width = (screen.width * pixelRatio).round();
      final height = (screen.height * pixelRatio).round();
      final area = Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble());
      final provider = wallpaper.wallpaper;
      if (provider != null) photo = await _decode(provider);

      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder)
        ..saveLayer(area, Paint()..imageFilter = ui.ImageFilter.blur(sigmaX: sigma * pixelRatio, sigmaY: sigma * pixelRatio));
      if (photo != null) {
        paintImage(canvas: canvas, rect: area, image: photo, fit: BoxFit.cover, filterQuality: FilterQuality.low);
      } else {
        canvas.drawRect(area, Paint()..shader = wallpaper.gradient.gradient.createShader(area));
      }
      canvas
        ..drawRect(
          area,
          Paint()
            ..shader = const LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: kWallpaperShadeColors,
            ).createShader(area),
        )
        ..restore();
      final recording = recorder.endRecording();
      final made = await recording.toImage(width, height);
      recording.dispose();
      // Replaced meanwhile (another wallpaper or size): not needed any more
      if (!_made.containsValue(this)) {
        made.dispose();
        return;
      }
      image.value = made;
    } catch (_) {
      // A wallpaper that won't decode keeps the live blur
    } finally {
      photo?.dispose();
    }
  }

  static Future<ui.Image> _decode(ImageProvider provider) {
    final done = Completer<ui.Image>();
    final stream = provider.resolve(ImageConfiguration.empty);
    late final ImageStreamListener listener;
    listener = ImageStreamListener((info, _) {
      stream.removeListener(listener);
      // A clone the caller owns: the provider's image may be shown elsewhere too
      done.complete(info.image.clone());
      info.dispose();
    }, onError: (error, stack) {
      stream.removeListener(listener);
      done.completeError(error, stack);
    });
    stream.addListener(listener);
    return done.future;
  }
}

/// [child] painted over the piece of [image] (the whole screen, blurred) that lies under it on screen, wherever it
/// has scrolled to.
class _GlassWindow extends SingleChildRenderObjectWidget {
  final ui.Image image;
  final Size screen;

  const _GlassWindow({required this.image, required this.screen, super.child});

  @override
  RenderObject createRenderObject(BuildContext context) => _RenderGlassWindow(image, screen);

  @override
  void updateRenderObject(BuildContext context, _RenderGlassWindow renderObject) {
    renderObject
      ..image = image
      ..screen = screen;
  }
}

class _RenderGlassWindow extends RenderProxyBox {
  ui.Image _image;
  Size _screen;

  _RenderGlassWindow(this._image, this._screen);

  set image(ui.Image value) {
    if (identical(value, _image)) return;
    _image = value;
    markNeedsPaint();
  }

  set screen(Size value) {
    if (value == _screen) return;
    _screen = value;
    markNeedsPaint();
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    if (!size.isEmpty) {
      final topLeft = localToGlobal(Offset.zero);
      final sx = _image.width / _screen.width;
      final sy = _image.height / _screen.height;
      final piece = Rect.fromLTWH(topLeft.dx * sx, topLeft.dy * sy, size.width * sx, size.height * sy);
      context.canvas.drawImageRect(_image, piece, offset & size, Paint()..filterQuality = FilterQuality.low);
    }
    super.paint(context, offset);
  }
}
