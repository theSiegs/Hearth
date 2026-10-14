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

import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';

/// A full-size background drawn once into an image and shown as that image, instead of being painted again on every
/// frame: a full-screen gradient shader costs a TV stick noticeably more than a picture. [paint] draws it; [paintKey]
/// says when it must be drawn again (with the size). Until the image is ready it's painted live, so nothing flashes.
class PaintedOnce extends StatefulWidget {
  final Object paintKey;
  final void Function(Canvas canvas, Size size) paint;

  const PaintedOnce({super.key, required this.paintKey, required this.paint});

  /// A gradient filling the box.
  factory PaintedOnce.gradient(Gradient gradient, {Key? key}) => PaintedOnce(
        key: key,
        paintKey: gradient,
        paint: (canvas, size) => canvas.drawRect(Offset.zero & size, Paint()..shader = gradient.createShader(Offset.zero & size)),
      );

  @override
  State<PaintedOnce> createState() => _PaintedOnceState();
}

class _PaintedOnceState extends State<PaintedOnce> {
  ui.Image? _image;
  (Object, Size)? _drawnFor;
  (Object, Size)? _drawing;

  @override
  void dispose() {
    _image?.dispose();
    super.dispose();
  }

  Future<void> _draw((Object, Size) target) async {
    _drawing = target;
    final (_, size) = target;
    final recorder = ui.PictureRecorder();
    widget.paint(Canvas(recorder), size);
    final picture = recorder.endRecording();
    final image = await picture.toImage(size.width.ceil(), size.height.ceil());
    picture.dispose();
    if (!mounted || _drawing != target) {
      image.dispose();
      return;
    }
    setState(() {
      _image?.dispose();
      _image = image;
      _drawnFor = target;
      _drawing = null;
    });
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, constraints) {
        final size = constraints.biggest;
        final target = (widget.paintKey, size);
        final image = _image;
        if (image != null && _drawnFor == target) {
          return RawImage(image: image, width: size.width, height: size.height, fit: BoxFit.fill);
        }
        if (_drawing != target && size.isFinite && !size.isEmpty) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted && _drawing != target && _drawnFor != target) _draw(target);
          });
        }
        return CustomPaint(size: size, painter: _LivePainter(widget.paint, widget.paintKey));
      });
}

class _LivePainter extends CustomPainter {
  final void Function(Canvas canvas, Size size) draw;
  final Object paintKey;

  _LivePainter(this.draw, this.paintKey);

  @override
  void paint(Canvas canvas, Size size) => draw(canvas, size);

  @override
  bool shouldRepaint(_LivePainter oldDelegate) => oldDelegate.paintKey != paintKey;
}
