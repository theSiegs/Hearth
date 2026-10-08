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

import 'dart:math';

import 'package:flutter/material.dart';

/// How the home screen's cards look in each card style (the `themes` setting).
class CardStyle {
  /// Corner radius of the card.
  final double radius;

  /// Zoom of the focused card.
  final double focusScale;

  /// Shadow depth of the focused card.
  final double focusElevation;

  /// The focused card's shadow takes the accent colour.
  final bool glow;

  /// Width of the accent outline round the focused card; 0 for none.
  final double outlineWidth;

  /// The accent outline has a black one inside it, and pulses when the highlight animation is on.
  final bool twoTone;

  const CardStyle._({
    required this.radius,
    this.focusScale = 1.1,
    this.focusElevation = 16,
    this.glow = false,
    this.outlineWidth = 2,
    this.twoTone = false,
  });

  static const CardStyle _modern = CardStyle._(radius: 8, twoTone: true);
  static const CardStyle _premium = CardStyle._(radius: 16, focusScale: 1.15, outlineWidth: 0);
  static const CardStyle _glow = CardStyle._(radius: 12, focusScale: 1.12, glow: true, outlineWidth: 3);
  static const CardStyle _squircle = CardStyle._(radius: 24, focusScale: 1.12, twoTone: true);
  static const CardStyle _classic = CardStyle._(radius: 0, focusScale: 1.0, focusElevation: 8, outlineWidth: 4);
  static const CardStyle _minimal = CardStyle._(radius: 4, focusScale: 1.05, focusElevation: 6);
  static const CardStyle _capsule = CardStyle._(radius: 100, twoTone: true);

  /// The style for a `themes` value; anything unknown gets the modern style.
  static CardStyle of(String theme) => switch (theme) {
        'premium' => _premium,
        'glow' => _glow,
        'squircle' => _squircle,
        'classic' => _classic,
        'minimal' => _minimal,
        'capsule' => _capsule,
        _ => _modern,
      };

  BorderRadius get borderRadius => BorderRadius.circular(radius);

  /// For the black line just inside the two-tone outline.
  BorderRadius get innerBorderRadius => BorderRadius.circular(max(radius - 2, 0));

  /// The focus zoom for a card [width] wide. Cards are at least 16 px apart, so the zoom may
  /// spread at most 14 px each side, or it would overlap the next card.
  double focusScaleFor(double width) => width > 0 ? min(focusScale, 1.0 + 28.0 / width) : focusScale;

  /// The focused card's shadow colour.
  Color focusShadowColor(Color accentColor) => glow ? accentColor.withOpacity(0.85) : Colors.black;
}
