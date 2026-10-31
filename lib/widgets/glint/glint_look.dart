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

import 'package:flutter/material.dart';

/// The Glint home's look, taken from Glint (the phone launcher) so the two read as one family: glass tiles over the
/// picture, one thing per face in big type, an ember accent and a warm shine along each tile's top edge.
class GlintLook {
  GlintLook._();

  /// Glint's accent.
  static const Color ember = Color(0xFFF0955A);

  /// The glass's tint over the blurred picture.
  static const Color tint = Color(0xFF0E1016);

  /// The tint's strength: Glint's at its default clarity (40), and at rest, when the glass goes nearly clear.
  static const double tintAlpha = 0.38;
  static const double restTintAlpha = 0.10;

  /// How strongly the picture under a tile is blurred.
  static const double blurSigma = 18;

  /// The hairline round each tile, and the shine along its top edge (white warmed toward amber).
  static const Color line = Color(0x29FFFFFF);
  static const Color shine = Color(0xFFFFEFE3);
  static const double shineAlpha = 0.16;
  static const double shineHeight = 2.5;

  /// An app's colour shows only as a strip down the tile's left edge, never as a fill.
  static const double colourEdge = 4;

  static const double corner = 12;
  static const double gap = 8;

  /// White text, and the quieter secondary lines.
  static const Color content = Colors.white;
  static const Color secondary = Color(0xB8FFFFFF);

  /// A shadow that keeps text readable on the clear glass of a resting tile, or over a picture.
  static const List<Shadow> textShadow = [Shadow(color: Color(0x73000000), blurRadius: 6)];

  /// The Windows Phone pieces: the clock's numerals, the app list's letters and names.
  static const String wpFont = "Selawik";

  /// A face's primary line, its secondary lines and the small tracked caps over it (Glint's scale, at TV size).
  static const TextStyle primary = TextStyle(
    color: content,
    fontSize: 17,
    fontWeight: FontWeight.w500,
    height: 1.15,
    shadows: textShadow,
  );
  static const TextStyle secondaryText = TextStyle(
    color: secondary,
    fontSize: 13,
    fontWeight: FontWeight.w400,
    height: 1.2,
    shadows: textShadow,
  );
  static const TextStyle label = TextStyle(
    color: secondary,
    fontSize: 10.5,
    fontWeight: FontWeight.w600,
    letterSpacing: 1.1,
    shadows: textShadow,
  );

  /// The big light numerals and words on tiles: the clock, the temperature, "2 h 10 min".
  static TextStyle display(double size) => TextStyle(
    color: content,
    fontFamily: wpFont,
    fontSize: size,
    fontWeight: FontWeight.w300,
    height: 1.0,
    shadows: textShadow,
  );

  /// How long a face takes to flip over its top edge, and the pause between one tile's flip and the next's (only one
  /// tile moves at a time, as Glint's Calm motion has it).
  static const Duration flip = Duration(milliseconds: 650);
  static const Duration flipSpacing = Duration(seconds: 4);

  /// Idle this long, the home rests: the glass goes clear and the picture shows through.
  static const Duration restAfter = Duration(seconds: 45);
  static const Duration restFade = Duration(milliseconds: 1600);
}
