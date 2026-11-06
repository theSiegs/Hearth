import 'dart:convert';
import 'dart:io';

import 'package:flauncher/widgets/glint/glint_look.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// The Glint home's look against Glint's design tokens. glint-tokens.json beside this test is a copy of the file Glint
/// owns (glint-look/tokens/glint-tokens.json in the Glint repo, where Glint's Kotlin is the source of truth). To take a
/// Glint change: copy the new file over this one, run this test, and fix GlintLook until it passes.
///
/// The TV differs from the phone on purpose in three places, checked here as such rather than skipped:
/// - type: every size is Glint's times [GlintLook.tvScale] (a TV is read from across the room);
/// - rest: the home rests after 45 s, not Glint's 20 s (a TV is left alone longer);
/// - motion: Easy is the default, not Glint's Lively (a TV home is mostly for opening an app), and one tile turns at a
///   time at every level.
///
/// Not drawn on the TV, so not checked: the tile surfaces other than Smoke (Outline, Fog and the rest), Auto glass's
/// light thresholds, and the flat buttons' kinds (Urgent, Lit, Stop).
void main() {
  final tokens = jsonDecode(File("test/widgets/glint/glint-tokens.json").readAsStringSync()) as Map<String, dynamic>;
  dynamic at(String path) => path.split(".").fold<dynamic>(tokens, (node, key) => (node as Map<String, dynamic>)[key]);
  Color color(String path) => Color(int.parse((at(path) as String).substring(1), radix: 16));
  double number(String path) => (at(path) as num).toDouble();
  Duration ms(String path) => Duration(milliseconds: (at(path) as num).toInt());

  test("follows the token file's version", () {
    expect(at("version"), GlintLook.tokensVersion,
        reason: "Glint's tokens changed: check what moved, update GlintLook, then tokensVersion");
  });

  test("colours and ink", () {
    expect(GlintLook.ember, color("colors.accent.default"));
    expect(GlintLook.content, color("colors.ink.onDark.content"));
    expect(GlintLook.secondaryAlpha, number("colors.ink.onDark.secondaryAlpha"));
    expect(GlintLook.secondary.a, closeTo(number("colors.ink.onDark.secondaryAlpha"), 0.002));
  });

  test("the accent as words on glass", () {
    const a = "colors.ink.accentText";
    expect(GlintLook.frostedDark, color("$a.frostedDark"));
    expect(GlintLook.accentMinContrast, number("$a.minContrast"));
    expect(GlintLook.accentMinContrastLarge, number("$a.minContrastLarge"));
    expect(GlintLook.largeTextPx, number("$a.largePx"));
    expect(GlintLook.largeBoldTextPx, number("$a.largeBoldPx"));
    expect(GlintLook.largeBoldWeight, at("$a.boldWeight"));
    // Ember reads at about 3.2:1 on frosted dark: big words keep it, small ones are lifted toward white just enough
    expect(GlintLook.accentText(large: true), GlintLook.ember);
    final small = GlintLook.accentText();
    expect(GlintLook.contrast(small, GlintLook.frostedDark), greaterThanOrEqualTo(4.5));
    expect(small, isNot(GlintLook.ember));
    expect(HSLColor.fromColor(small).hue, closeTo(HSLColor.fromColor(GlintLook.ember).hue, 1.5));
    expect(GlintLook.isLargeText(20), isTrue);
    expect(GlintLook.isLargeText(16, weight: 600), isTrue);
    expect(GlintLook.isLargeText(16 * GlintLook.tvScale), isFalse);
  });

  test("glass, hairline and shine", () {
    expect(GlintLook.tint, color("glass.dark"));
    expect(GlintLook.strengthBase, number("glass.strengthBase"));
    expect(GlintLook.strengthFrost, number("glass.strengthFrost"));
    expect(GlintLook.smokeExtra, number("glass.smoke.extra"));
    expect(GlintLook.clarity, at("glass.clarity.default"));
    expect(GlintLook.restClarity, at("glass.rest.clarity"));
    expect(GlintLook.restFade, ms("glass.rest.easeMs"));
    expect(GlintLook.restAfter, isNot(ms("glass.rest.afterMs")), reason: "the TV rests later on purpose");
    expect(GlintLook.restAfter, const Duration(seconds: 45));

    expect(GlintLook.hairlineAlpha, number("glass.hairline.onDark"));
    expect(GlintLook.hairlineWidth, number("glass.hairline.widthDp"));
    expect(GlintLook.line.a, closeTo(number("glass.hairline.onDark"), 0.002));
    expect(GlintLook.shineWarm, color("glass.shine.warm"));
    expect(GlintLook.shineWarmMix, number("glass.shine.warmMix"));
    expect(GlintLook.shineAlpha, number("glass.shine.onDark"));
    expect(GlintLook.shineHeight, number("glass.shine.heightDp"));
    expect(GlintLook.colourEdge, number("glass.tileTint.colorStripWidthDp"));
  });

  test("shape and spacing", () {
    expect(GlintLook.corner, number("shape.tileCorner.defaultDp"));
    expect(GlintLook.gap, number("spacing.tileGapDp"));
  });

  test("type: Glint's scale times the TV's", () {
    void style(TextStyle actual, String name, {bool selawik = false}) {
      final s = at("type.styles.$name") as Map<String, dynamic>;
      expect(s["family"], selawik ? "selawik" : "system", reason: name);
      expect(actual.fontFamily, selawik ? GlintLook.wpFont : isNull, reason: name);
      expect(actual.fontSize, closeTo((s["sizeSp"] as num) * GlintLook.tvScale, 0.001), reason: name);
      if (s["weight"] != null) expect(actual.fontWeight!.value, s["weight"], reason: name);
      if (s["letterSpacingSp"] != null) {
        expect(actual.letterSpacing, closeTo((s["letterSpacingSp"] as num) * GlintLook.tvScale, 0.001), reason: name);
      }
      if (s["lineHeightSp"] != null) {
        expect(actual.height, closeTo((s["lineHeightSp"] as num) / (s["sizeSp"] as num), 0.001), reason: name);
      }
    }

    style(GlintLook.label, "label");
    style(GlintLook.primary, "primary");
    style(GlintLook.secondaryText, "secondary");
    style(GlintLook.wpTitle, "wpTitle", selawik: true);
    style(GlintLook.wpItem, "wpItem", selawik: true);
    expect(GlintLook.display(40).fontWeight!.value, at("type.displayWeight"));
    expect(GlintLook.display(40).fontFamily, isNull);
    expect(GlintLook.minTextSize, closeTo(number("type.minSizeSp") * GlintLook.tvScale, 0.001));
  });

  test("motion: the levels' paces, the flip, Easy as the TV's default", () {
    expect([for (final m in GlintMotion.values) m.name], [
      for (final l in at("motion.levels") as List) (l as String).toLowerCase(),
    ]);
    expect(at("motion.default"), "Lively");
    expect(GlintMotion.fallback, GlintMotion.easy, reason: "the TV's default on purpose");
    for (final m in GlintMotion.values) {
      final row = at("motion.pace.${m.name[0].toUpperCase()}${m.name.substring(1)}") as Map<String, dynamic>;
      expect(m.pace.moves, row["moves"], reason: m.name);
      final gap = row["drawGapMs"] as List?;
      expect(m.pace.drawGap, gap == null ? isNull : (Duration(milliseconds: gap[0]), Duration(milliseconds: gap[1])),
          reason: m.name);
      expect(m.pace.spacing, Duration(milliseconds: row["spacingMs"]), reason: m.name);
    }
    expect(GlintLook.flip, ms("motion.flip.flipMs"));
    Cubic cubic(String path) {
      final p = [for (final v in at(path) as List) (v as num).toDouble()];
      return Cubic(p[0], p[1], p[2], p[3]);
    }

    void sameCurve(Cubic actual, Cubic expected) =>
        expect([actual.a, actual.b, actual.c, actual.d], [expected.a, expected.b, expected.c, expected.d]);
    // GlintFlip runs its halves on these
    sameCurve(Curves.easeIn, cubic("motion.flip.easeIn"));
    sameCurve(Curves.easeOut, cubic("motion.flip.easeOut"));
    sameCurve(GlintLook.cometEase, cubic("motion.newContentCue.glow.cometEase"));
  });

  test("the new-content cue, Glow", () {
    const g = "motion.newContentCue.glow";
    expect(at("motion.newContentCue.default"), "Glow");
    expect(GlintLook.cueFade, ms("$g.fadeMs"));
    expect(GlintLook.cueLit, ms("$g.litMs"));
    expect(GlintLook.comet, ms("$g.cometMs"));
    expect(GlintLook.cometSoft, ms("$g.cometSoftMs"));
    expect(GlintLook.cueCalmStrength, number("$g.calmStrength"));
    expect(GlintLook.cometLength, number("$g.cometLength"));
    expect(GlintLook.cueEdgeWidth, number("$g.edgeDp"));
    expect(GlintLook.cueEdgeAlpha, number("$g.edgeAlpha"));
    expect(GlintLook.cueTopLine, color("$g.topLine"));
    expect(GlintLook.cueGlowWidth, number("$g.glowDp"));
    expect(GlintLook.cueGlowAlpha, number("$g.glowAlpha"));
    expect(GlintLook.cometWidth, number("$g.cometDp"));
    expect(GlintLook.cometHaloTimes, number("$g.haloTimes"));
    expect(GlintLook.cometHaloAlpha, number("$g.haloAlpha"));
    expect(GlintLook.cometHead, color("$g.cometHead"));
  });
}
