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
import 'dart:ui' show lerpDouble;

import 'package:flauncher/widgets/frosted_glass.dart';
import 'package:flauncher/widgets/glint/glint_look.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// How far the Glint home has gone into rest (0 awake, 1 resting): tiles read it to clear their glass.
class GlintRest extends InheritedNotifier<Animation<double>> {
  const GlintRest({super.key, required Animation<double> rest, required super.child}) : super(notifier: rest);

  static double of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<GlintRest>()?.notifier?.value ?? 0;
}

/// One tile on the Glint home: frosted glass over the picture with Glint's hairline and warm top shine, an app's colour
/// as a strip down the left edge, or a full-bleed [picture] when the face is a real picture (a poster, a photo).
///
/// It's one stop for the D-pad. Select runs [onPressed]; held, [onLongPress]. Selected, it lifts a little and wears a
/// white border, which isn't the glow Glint gives tiles it put out by itself.
class GlintTile extends StatefulWidget {
  final Widget child;
  final VoidCallback? onPressed;
  final VoidCallback? onLongPress;
  final Color? colourEdge;
  final ImageProvider? picture;
  final FocusNode? focusNode;
  final ValueChanged<bool>? onFocusChange;
  final EdgeInsets padding;

  const GlintTile({
    super.key,
    required this.child,
    this.onPressed,
    this.onLongPress,
    this.colourEdge,
    this.picture,
    this.focusNode,
    this.onFocusChange,
    this.padding = const EdgeInsets.fromLTRB(14, 12, 14, 10),
  });

  /// Held this long, select is a long press.
  static const Duration longPress = Duration(milliseconds: 600);

  static final _selectKeys = {
    LogicalKeyboardKey.select,
    LogicalKeyboardKey.enter,
    LogicalKeyboardKey.numpadEnter,
    LogicalKeyboardKey.gameButtonA,
  };

  @override
  State<GlintTile> createState() => _GlintTileState();
}

class _GlintTileState extends State<GlintTile> {
  bool _focused = false;

  void _focusChanged(bool focused) {
    setState(() => _focused = focused);
    if (focused) {
      Scrollable.ensureVisible(
        context,
        alignment: 0.5,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
      );
    }
    widget.onFocusChange?.call(focused);
  }

  @override
  Widget build(BuildContext context) {
    final rest = GlintRest.of(context);
    final radius = BorderRadius.circular(GlintLook.corner);
    return GlintPress(
      focusNode: widget.focusNode,
      onPressed: widget.onPressed,
      onLongPress: widget.onLongPress,
      onFocusChange: _focusChanged,
      child: AnimatedScale(
        scale: _focused ? 1.06 : 1.0,
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOutCubic,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          decoration: BoxDecoration(
            borderRadius: radius,
            boxShadow: _focused
                ? const [BoxShadow(color: Color(0x80000000), blurRadius: 24, offset: Offset(0, 10))]
                : const [],
          ),
          foregroundDecoration: _focused
              ? BoxDecoration(
                  borderRadius: radius,
                  border: Border.all(color: Colors.white, width: 2.5),
                )
              : null,
          child: ClipRRect(
            borderRadius: radius,
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (widget.picture == null) ...[
                  // The glass clears as the home rests; the selected tile stays frosted so it reads
                  Opacity(
                    opacity: _focused ? 1 : 1 - rest * 0.8,
                    child: const FrostedGlass(sigma: GlintLook.blurSigma, child: SizedBox.expand()),
                  ),
                  ColoredBox(
                    color: GlintLook.tint.withValues(
                      alpha: _focused
                          ? GlintLook.tintAlpha
                          : lerpDouble(GlintLook.tintAlpha, GlintLook.restTintAlpha, rest)!,
                    ),
                  ),
                ] else ...[
                  Image(image: widget.picture!, fit: BoxFit.cover, gaplessPlayback: true),
                  // Under the text along the bottom, so it reads on any picture
                  const DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        stops: [0.35, 1],
                        colors: [Color(0x00000000), Color(0xC0000000)],
                      ),
                    ),
                  ),
                ],
                if (widget.colourEdge != null)
                  Positioned(
                    left: 0,
                    top: 0,
                    bottom: 0,
                    width: GlintLook.colourEdge,
                    child: ColoredBox(color: widget.colourEdge!),
                  ),
                Padding(padding: widget.padding, child: widget.child),
                IgnorePointer(
                  child: CustomPaint(painter: _EdgePainter(radius: GlintLook.corner)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Glint's edge: a white hairline all round and a warm shine fading down from the top edge.
class _EdgePainter extends CustomPainter {
  final double radius;
  const _EdgePainter({required this.radius});

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final rrect = RRect.fromRectAndRadius(rect.deflate(0.5), Radius.circular(radius));
    canvas.drawRRect(
      rrect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = GlintLook.line,
    );
    canvas.save();
    canvas.clipRRect(RRect.fromRectAndRadius(rect, Radius.circular(radius)));
    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width, GlintLook.shineHeight),
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            GlintLook.shine.withValues(alpha: GlintLook.shineAlpha),
            GlintLook.shine.withValues(alpha: 0),
          ],
        ).createShader(Rect.fromLTWH(0, 0, size.width, GlintLook.shineHeight)),
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(_EdgePainter old) => old.radius != radius;
}

/// One stop for the D-pad that tells a press of select from a hold, as [GlintTile] does, around any [child].
class GlintPress extends StatefulWidget {
  final Widget child;
  final VoidCallback? onPressed;
  final VoidCallback? onLongPress;
  final ValueChanged<bool>? onFocusChange;
  final FocusNode? focusNode;
  final bool autofocus;

  const GlintPress({
    super.key,
    required this.child,
    this.onPressed,
    this.onLongPress,
    this.onFocusChange,
    this.focusNode,
    this.autofocus = false,
  });

  @override
  State<GlintPress> createState() => _GlintPressState();
}

class _GlintPressState extends State<GlintPress> {
  Timer? _hold;
  bool _held = false;
  bool _down = false;

  @override
  void dispose() {
    _hold?.cancel();
    super.dispose();
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (!GlintTile._selectKeys.contains(event.logicalKey)) return KeyEventResult.ignored;
    if (event is KeyDownEvent) {
      _down = true;
      _held = false;
      _hold?.cancel();
      _hold = Timer(GlintTile.longPress, () {
        if (!_down) return;
        _held = true;
        widget.onLongPress?.call();
      });
    } else if (event is KeyUpEvent) {
      _hold?.cancel();
      final wasDown = _down;
      _down = false;
      if (wasDown && !_held) widget.onPressed?.call();
    }
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) => Focus(
    focusNode: widget.focusNode,
    autofocus: widget.autofocus,
    onKeyEvent: _onKey,
    onFocusChange: (focused) {
      if (!focused) {
        _hold?.cancel();
        _down = false;
      }
      widget.onFocusChange?.call(focused);
    },
    child: GestureDetector(onTap: widget.onPressed, onLongPress: widget.onLongPress, child: widget.child),
  );
}
