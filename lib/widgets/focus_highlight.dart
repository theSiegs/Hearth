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

import 'package:flauncher/providers/settings_service.dart';
import 'package:flauncher/widgets/card_style.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

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
        return _twoTone(widget.accentColor.withValues(alpha: opacity), Colors.black.withValues(alpha: opacity));
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

/// A card's focus look, shared by the app cards and Continue Watching's: while [highlighted] it grows by [scale],
/// lifts with a glow in the accent colour and loses its dimming, and the card style's outline goes over [children].
class FocusCardFrame extends StatelessWidget {
  final bool highlighted;
  final double scale;
  final double? width;
  final double? height;

  /// The card's fill under [children]; null for the theme's.
  final Color? color;

  /// Rounds the dimming layer's corners too.
  final bool roundedDim;
  final List<Widget> children;

  const FocusCardFrame({
    super.key,
    required this.highlighted,
    required this.scale,
    this.width,
    this.height,
    this.color,
    this.roundedDim = false,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    final CardStyle style = CardStyle.of(context.select<SettingsService, String>((s) => s.themes));
    final Color accentColor = context.select<SettingsService, Color>((s) => s.accentColor);
    final bool hideHighlightOutlineOnHomescreen = context.select<SettingsService, bool>((s) => s.hideHighlightOutlineOnHomescreen);
    final bool appHighlightAnimationEnabled = context.select<SettingsService, bool>((s) => s.appHighlightAnimationEnabled);
    final bool appSelectorTransitionAnimationEnabled = context.select<SettingsService, bool>((s) => s.appSelectorTransitionAnimationEnabled);
    final Duration focusDuration = appSelectorTransitionAnimationEnabled ? const Duration(milliseconds: 200) : Duration.zero;

    return AnimatedContainer(
      duration: focusDuration,
      curve: Curves.easeOutBack,
      width: width,
      height: height,
      transform: Matrix4.diagonal3Values(scale, scale, 1.0),
      transformAlignment: Alignment.center,
      child: Material(
        borderRadius: style.borderRadius,
        clipBehavior: Clip.antiAlias,
        elevation: highlighted ? style.focusElevation : 0,
        shadowColor: highlighted ? style.focusShadowColor(accentColor) : Colors.black,
        color: color,
        child: Stack(
          fit: StackFit.expand,
          children: [
            ...children,
            IgnorePointer(
              child: AnimatedOpacity(
                duration: focusDuration,
                curve: Curves.easeInOut,
                opacity: highlighted ? 0 : 0.10,
                child: roundedDim
                    ? Container(decoration: BoxDecoration(borderRadius: style.borderRadius, color: Colors.black))
                    : Container(color: Colors.black),
              ),
            ),
            if (highlighted && !hideHighlightOutlineOnHomescreen)
              FocusHighlight(
                style: style,
                accentColor: accentColor,
                animate: appHighlightAnimationEnabled,
              ),
          ],
        ),
      ),
    );
  }
}
