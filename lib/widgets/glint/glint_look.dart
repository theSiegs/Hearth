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
///
/// The numbers are Glint's design tokens (a copy of Glint's glint-tokens.json is in test/widgets/glint, and
/// glint_tokens_test.dart fails when these drift from it). Where the TV differs on purpose, it says so here and in
/// that test: type is Glint's phone scale times [tvScale], the home rests later, and Easy is the default motion.
class GlintLook {
  GlintLook._();

  /// The version of Glint's token file these numbers follow.
  static const int tokensVersion = 4;

  /// Glint's accent (colors.accent.default).
  static const Color ember = Color(0xFFF0955A);

  /// Glint's accent as words on glass (colors.ink.accentText): the accent itself when it reads at [accentMinContrast]
  /// against Glint's reference frosted dark surface, else the accent mixed toward white just far enough (the hue
  /// stays). Large text ([isLargeText]) needs only [accentMinContrastLarge]. Fills, edges and bars keep [ember].
  static const Color frostedDark = Color(0xFF555658);
  static const double accentMinContrast = 4.5, accentMinContrastLarge = 3.0;
  static const double largeTextPx = 20, largeBoldTextPx = 16;
  static const int largeBoldWeight = 600;

  /// Glint's "large" text, at the size it's drawn (the TV's scale included): [largeTextPx] and up, or [largeBoldTextPx]
  /// and up at [largeBoldWeight] or heavier.
  static bool isLargeText(double px, {int weight = 400}) =>
      px >= largeTextPx || (weight >= largeBoldWeight && px >= largeBoldTextPx);

  /// [ember] as text: small text by default, [large] for big words and numbers.
  static Color accentText({bool large = false}) =>
      accentInk(ember, frostedDark, large ? accentMinContrastLarge : accentMinContrast);

  /// Glint's AccentInk.text: [accent] when it has [min] contrast (WCAG) with [surface], else the least of 256 sRGB
  /// steps toward white (on a dark surface) or black (on a light one) that reaches it.
  static Color accentInk(Color accent, Color surface, double min) {
    final a = accent.withValues(alpha: 1);
    if (contrast(a, surface) >= min) return a;
    final toWhite = contrast(Colors.white, surface) >= contrast(Colors.black, surface);
    final toward = toWhite ? Colors.white : Colors.black;
    final ls = surface.computeLuminance();
    bool ok(Color c) => contrast(c, surface) >= min && (c.computeLuminance() > ls) == toWhite;
    const steps = 256;
    Color mix(int step) {
      int ch(double x, double y) => ((x * 255) + ((y * 255) - (x * 255)) * step / steps).round().clamp(0, 255);
      return Color.fromARGB(255, ch(a.r, toward.r), ch(a.g, toward.g), ch(a.b, toward.b));
    }

    if (!ok(mix(steps))) return toward;
    var lo = 0, hi = steps;
    while (lo < hi) {
      final mid = (lo + hi) ~/ 2;
      if (ok(mix(mid))) {
        hi = mid;
      } else {
        lo = mid + 1;
      }
    }
    return mix(lo);
  }

  /// WCAG contrast between two opaque colours (1 … 21).
  static double contrast(Color a, Color b) {
    final la = a.computeLuminance(), lb = b.computeLuminance();
    return ((la > lb ? la : lb) + 0.05) / ((la > lb ? lb : la) + 0.05);
  }

  /// The glass's dark tint over the blurred picture (glass.dark).
  static const Color tint = Color(0xFF0E1016);

  /// Glint's glass at a clarity (0 clear … 100 frosted), the Smoke way (Auto over a dark picture, which the TV's
  /// pictures nearly always are): strengthBase + strengthFrost × frosted + smoke.extra.
  static const double strengthBase = 0.06;
  static const double strengthFrost = 0.49;
  static const double smokeExtra = 0.12;
  static const int clarity = 40;
  static const int restClarity = 8;

  /// The tint's strength at Glint's default clarity, and at rest, when the glass goes nearly clear.
  static const double tintAlpha = strengthBase + strengthFrost * clarity / 100 + smokeExtra;
  static const double restTintAlpha = strengthBase + strengthFrost * restClarity / 100 + smokeExtra;

  /// How strongly the picture under a tile is blurred (Glint makes its frosted copy its own way: glass.frostBlur is
  /// Android only).
  static const double blurSigma = 18;

  /// The hairline round each tile (glass.hairline, on dark).
  static const double hairlineAlpha = 0.16;
  static const double hairlineWidth = 1;
  static const Color line = Color.fromRGBO(255, 255, 255, hairlineAlpha);

  /// The shine along a tile's top edge: white warmed [shineWarmMix] of the way toward [shineWarm] (glass.shine).
  static const Color shineWarm = Color(0xFFFFB27A);
  static const double shineWarmMix = 0.15;
  static final Color shine = Color.lerp(Colors.white, shineWarm, shineWarmMix)!;
  static const double shineAlpha = 0.16;
  static const double shineHeight = 2.5;

  /// An app's colour shows only as a strip down the tile's left edge, never as a fill (glass.tileTint, Faint).
  static const double colourEdge = 4;

  static const double corner = 12;
  static const double gap = 8;

  /// White text, and the quieter secondary lines (colors.ink.onDark).
  static const Color content = Colors.white;
  static const double secondaryAlpha = 0.72;
  static const Color secondary = Color.fromRGBO(255, 255, 255, secondaryAlpha);

  /// A shadow that keeps text readable on the clear glass of a resting tile, or over a picture.
  static const List<Shadow> textShadow = [Shadow(color: Color(0x73000000), blurRadius: 6)];

  /// The Windows Phone pieces: the app list's title, letters and names.
  static const String wpFont = "Selawik";

  /// Glint's type is sized for a phone in the hand; on a TV across the room every size is this much bigger.
  static const double tvScale = 1.15;

  /// Glint's type scale (type.styles), before [tvScale].
  static const double labelSize = 12, labelTracking = 1.2;
  static const double primarySize = 15;
  static const double secondarySize = 13;
  static const double wpTitleSize = 44, wpTitleLine = 48;
  static const double wpItemSize = 22, wpItemLine = 26;

  /// The smallest text the home draws (Glint's floor, type.minSizeSp, at TV size): a face that needs smaller type gets
  /// more room instead.
  static const double minTextSize = 12 * tvScale;

  /// A face's primary line, its secondary lines and the small tracked caps over it.
  static const TextStyle primary = TextStyle(
    color: content,
    fontSize: primarySize * tvScale,
    fontWeight: FontWeight.w500,
    height: 1.15,
    shadows: textShadow,
  );
  static const TextStyle secondaryText = TextStyle(
    color: secondary,
    fontSize: secondarySize * tvScale,
    fontWeight: FontWeight.w400,
    height: 1.2,
    shadows: textShadow,
  );
  static const TextStyle label = TextStyle(
    color: secondary,
    fontSize: labelSize * tvScale,
    fontWeight: FontWeight.w600,
    letterSpacing: labelTracking * tvScale,
    shadows: textShadow,
  );

  /// The big light numerals and words on tiles: the clock, the temperature, "2 h 10 min" (type.displayWeight). The
  /// system sans; Selawik is only for the Windows Phone pages. Sizes stay with each face.
  static const FontWeight displayWeight = FontWeight.w300;
  static TextStyle display(double size) => TextStyle(
    color: content,
    fontSize: size,
    fontWeight: displayWeight,
    height: 1.0,
    shadows: textShadow,
  );

  /// A Windows Phone page's title: big, light, lower case ("apps"); and a row's name in its list.
  static const TextStyle wpTitle = TextStyle(
    color: content,
    fontFamily: wpFont,
    fontSize: wpTitleSize * tvScale,
    height: wpTitleLine / wpTitleSize,
    fontWeight: FontWeight.w300,
  );
  static const TextStyle wpItem = TextStyle(
    color: content,
    fontFamily: wpFont,
    fontSize: wpItemSize * tvScale,
    height: wpItemLine / wpItemSize,
    fontWeight: FontWeight.w300,
  );

  /// How long a face takes to flip over its top edge (motion.flip; its halves run on Curves.easeIn and easeOut, which
  /// are Glint's beziers).
  static const Duration flip = Duration(milliseconds: 650);

  /// Glint's new-content cue, Glow (motion.newContentCue.glow): the edge lights for [cueLit], fading in and out over
  /// [cueFade], and one comet runs round once ([cometSoft] at Calm, played at [cueCalmStrength]); at Still the edge
  /// lights with no fades and no comet.
  static const Duration cueFade = Duration(milliseconds: 500);
  static const Duration cueLit = Duration(milliseconds: 1300);
  static const Duration comet = Duration(milliseconds: 1300);
  static const Duration cometSoft = Duration(milliseconds: 1700);
  static const double cueCalmStrength = 0.6;
  static const double cometLength = 0.26;
  static const Cubic cometEase = Cubic(0.1, 0.9, 0.2, 1);
  static const double cueEdgeWidth = 2;
  static const double cueEdgeAlpha = 0.95;
  static const Color cueTopLine = Color(0xFFFFEEDC);
  static const double cueGlowWidth = 22;
  static const double cueGlowAlpha = 0.35;
  static const double cometWidth = 3;
  static const double cometHaloTimes = 4;
  static const double cometHaloAlpha = 0.55;
  static const Color cometHead = Color(0xFFFFE3CC);

  /// Idle this long, the home rests: the glass goes clear and the picture shows through. Glint rests after 20 s; a TV
  /// is looked at from across the room and left alone longer, so it waits 45 s.
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
