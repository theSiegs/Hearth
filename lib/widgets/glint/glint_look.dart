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
    fontSize: 12,
    fontWeight: FontWeight.w600,
    letterSpacing: 1.2,
    shadows: textShadow,
  );

  /// The smallest text the home draws (Glint's floor): a face that needs smaller type gets more room instead.
  static const double minTextSize = 12;

  /// The big light numerals and words on tiles: the clock, the temperature, "2 h 10 min". The system sans, light;
  /// Selawik is only for the Windows Phone pages.
  static TextStyle display(double size) => TextStyle(
    color: content,
    fontSize: size,
    fontWeight: FontWeight.w300,
    height: 1.0,
    shadows: textShadow,
  );

  /// A Windows Phone page's title: big, light, lower case ("apps").
  static const TextStyle wpTitle = TextStyle(
    color: content,
    fontFamily: wpFont,
    fontSize: 44,
    height: 48 / 44,
    fontWeight: FontWeight.w300,
  );

  /// How long a face takes to flip over its top edge.
  static const Duration flip = Duration(milliseconds: 650);

  /// The lit edge on a tile with something new, and the one comet round it when it lights.
  static const double cueWidth = 2;
  static const Duration cometLap = Duration(milliseconds: 1800);

  /// Idle this long, the home rests: the glass goes clear and the picture shows through.
  static const Duration restAfter = Duration(seconds: 45);
  static const Duration restFade = Duration(milliseconds: 1600);
}

/// How much the Glint home moves, most to least (Glint's Motion, one row each of [GlintPace]): Lively, Easy (Lively's
/// moves at half its rate, the TV's default), Calm (nothing turns while you look; a tile shows its next face on a fresh
/// view of the home) and Still (nothing moves at all). Saved by name.
enum GlintMotion {
  lively(GlintPace(drawGap: (Duration(seconds: 2), Duration(seconds: 5)), spacing: Duration(milliseconds: 1500))),
  easy(GlintPace(drawGap: (Duration(seconds: 4), Duration(seconds: 10)), spacing: Duration(seconds: 3))),
  calm(GlintPace()),
  still(GlintPace(moves: false));

  final GlintPace pace;
  const GlintMotion(this.pace);

  static const GlintMotion fallback = easy;

  /// From its saved name, any case; unknown or missing is [fallback].
  static GlintMotion fromName(String? name) =>
      values.where((m) => m.name == name?.trim().toLowerCase()).firstOrNull ?? fallback;
}

/// One Motion level's numbers, from Glint's MotionPace table.
class GlintPace {
  /// Anything moves at all (not Still).
  final bool moves;

  /// The ticker turns a tile every so often, a random time in this range (null: no turning while shown, Calm and
  /// Still). Each draw turns one tile, so one tile moves at a time.
  final (Duration, Duration)? drawGap;

  /// Two turns are never closer than this, so neighbours don't move together.
  final Duration spacing;

  const GlintPace({this.moves = true, this.drawGap, this.spacing = Duration.zero});

  /// Faces turn while the home is shown (Lively and Easy flip; Calm and Still change only on a fresh view).
  bool get draws => drawGap != null;
}
