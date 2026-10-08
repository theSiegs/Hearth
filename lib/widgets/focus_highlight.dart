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

import 'package:flauncher/widgets/card_style.dart';
import 'package:flutter/material.dart';

/// The outline round a focused card, in its card style. Show it only while the card is focused;
/// the two-tone outline pulses while [animate] is on.
class FocusHighlight extends StatefulWidget {
  final CardStyle style;
  final Color accentColor;
  final bool animate;

  const FocusHighlight({super.key, required this.style, required this.accentColor, required this.animate});

  @override
  State<FocusHighlight> createState() => _FocusHighlightState();
}

class _FocusHighlightState extends State<FocusHighlight> with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
  );

  bool get _pulses => widget.style.twoTone && widget.animate;

  @override
  void initState() {
    super.initState();
    _updatePulse();
  }

  @override
  void didUpdateWidget(FocusHighlight oldWidget) {
    super.didUpdateWidget(oldWidget);
    _updatePulse();
  }

  // Started only when it isn't running: restarting on every rebuild would flip a fading pulse back.
  void _updatePulse() {
    if (!_pulses) {
      _pulse.stop();
    } else if (!_pulse.isAnimating) {
      _pulse.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final style = widget.style;
    if (style.outlineWidth == 0) {
      return const SizedBox();
    }
    if (!style.twoTone) {
      return IgnorePointer(
        child: _outline(style.borderRadius, widget.accentColor, style.outlineWidth),
      );
    }
    if (!_pulses) {
      return _twoTone(widget.accentColor, Colors.black);
    }
    return AnimatedBuilder(
      animation: _pulse,
      builder: (context, _) {
        final opacity = 0.4 + (_pulse.value * 0.6);
        return _twoTone(widget.accentColor.withOpacity(opacity), Colors.black.withOpacity(opacity));
      },
    );
  }

  Widget _twoTone(Color outer, Color inner) => IgnorePointer(
        child: Stack(
          fit: StackFit.expand,
          children: [
            _outline(widget.style.borderRadius, outer, widget.style.outlineWidth),
            Padding(
              padding: EdgeInsets.all(widget.style.outlineWidth),
              child: _outline(widget.style.innerBorderRadius, inner, 2),
            ),
          ],
        ),
      );

  Widget _outline(BorderRadius borderRadius, Color color, double width) => Container(
        decoration: BoxDecoration(
          borderRadius: borderRadius,
          border: Border.all(color: color, width: width),
        ),
      );
}
