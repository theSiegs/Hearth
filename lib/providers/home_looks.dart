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

import 'package:flauncher/gradients.dart';

import 'settings_service.dart';

/// The setup flow's ready-made looks for the home (docs/design/first-run-setup.md, F3): a card style, an accent, a
/// wallpaper and a dock in one choice. The one the owner picks is also the starting look for new grown-up profiles.
enum HomeLook {
  /// Hearth's own: default cards, purple, the "Faraway River" gradient, a frosted dock.
  hearth(cardStyle: "modern", accent: accentColorPurple, gradientUuid: _farawayRiver),

  /// Bing's photo of the day behind premium cards; the accent stays as it was.
  photo(cardStyle: "premium", bing: true),

  /// Minimal cards, white, pitch black (kind to OLED screens), a dark dock.
  calmDark(cardStyle: "minimal", accent: accentColorWhite, gradientUuid: _pitchBlack, darkDock: true),

  /// Glowing cards, pink, the "African Field" gradient.
  bold(cardStyle: "glow", accent: accentColorPink, gradientUuid: _africanField);

  static const String _farawayRiver = "7d34faa2-104a-49b7-bea5-ad48f4ccbd9c";
  static const String _pitchBlack = "00000000-0000-0000-0000-000000000000";
  static const String _africanField = "7e1c12aa-3769-4474-957a-e08ef98a93c2";

  final String cardStyle;

  /// Null: the accent is left as it is.
  final String? accent;

  /// Null: the photo of the day instead of a gradient.
  final String? gradientUuid;
  final bool bing;
  final bool darkDock;

  const HomeLook({
    required this.cardStyle,
    this.accent,
    this.gradientUuid,
    this.bing = false,
    this.darkDock = false,
  });

  /// The gradient behind it, for its tile: the photo of the day has none.
  FLauncherGradient? get gradient =>
      FLauncherGradients.all.where((gradient) => gradient.uuid == gradientUuid).firstOrNull;

  static HomeLook? byName(String? name) => HomeLook.values.asNameMap()[name];

  /// Puts this look in place. Only settings: a picture picked as the wallpaper stays in front of a gradient until
  /// WallpaperService.setGradient removes it (the flow does that when the look is chosen, not while previewing).
  Future<void> apply(SettingsService settings) async {
    await settings.setThemes(cardStyle);
    if (accent != null) await settings.setAccentColor(accent!);
    if (gradientUuid != null) await settings.setGradientUuid(gradientUuid!);
    await settings.setBingWallpaperEnabled(bing);
    if (bing) await settings.setTimeBasedWallpaperEnabled(false);
    await settings.setDockDarkBackground(darkDock);
    await settings.setDockBlurEnabled(true);
  }

  /// Whether the home looks like this now.
  bool matches(SettingsService settings) => matchesSnapshot(HomeLookSnapshot.of(settings));

  /// Whether a home as [snapshot] keeps it looks like this.
  bool matchesSnapshot(HomeLookSnapshot snapshot) =>
      snapshot.cardStyle == cardStyle &&
      (accent == null || snapshot.accent == accent) &&
      snapshot.bing == bing &&
      (bing || snapshot.gradientUuid == gradientUuid) &&
      snapshot.darkDock == darkDock;

  /// The look the home has now, if it's one of these.
  static HomeLook? current(SettingsService settings) => currentOf(HomeLookSnapshot.of(settings));

  /// The look a home as [snapshot] keeps it has, if it's one of these.
  static HomeLook? currentOf(HomeLookSnapshot snapshot) =>
      HomeLook.values.where((look) => look.matchesSnapshot(snapshot)).firstOrNull;
}

/// What a look changes, as it was: the flow previews each look as it's focused and puts this back on Keep current.
class HomeLookSnapshot {
  final String cardStyle;
  final String accent;
  final String gradientUuid;
  final bool bing;
  final bool timeBased;
  final bool darkDock;
  final bool dockBlur;

  HomeLookSnapshot.of(SettingsService settings)
      : cardStyle = settings.themes,
        accent = settings.accentColorHex,
        // No gradient chosen ever shows pitch black, and the setting can't be unset
        gradientUuid = settings.gradientUuid ?? HomeLook._pitchBlack,
        bing = settings.bingWallpaperEnabled,
        timeBased = settings.timeBasedWallpaperEnabled,
        darkDock = settings.dockDarkBackground,
        dockBlur = settings.dockBlurEnabled;

  HomeLookSnapshot.fromJson(Map<String, dynamic> json)
      : cardStyle = json["cardStyle"] as String,
        accent = json["accent"] as String,
        gradientUuid = json["gradientUuid"] as String,
        bing = json["bing"] as bool,
        timeBased = json["timeBased"] as bool,
        darkDock = json["darkDock"] as bool,
        dockBlur = json["dockBlur"] as bool;

  Map<String, dynamic> toJson() => {
        "cardStyle": cardStyle,
        "accent": accent,
        "gradientUuid": gradientUuid,
        "bing": bing,
        "timeBased": timeBased,
        "darkDock": darkDock,
        "dockBlur": dockBlur,
      };

  bool sameAs(HomeLookSnapshot other) =>
      cardStyle == other.cardStyle &&
      accent == other.accent &&
      gradientUuid == other.gradientUuid &&
      bing == other.bing &&
      timeBased == other.timeBased &&
      darkDock == other.darkDock &&
      dockBlur == other.dockBlur;

  Future<void> restore(SettingsService settings) async {
    await settings.setThemes(cardStyle);
    await settings.setAccentColor(accent);
    await settings.setGradientUuid(gradientUuid);
    await settings.setBingWallpaperEnabled(bing);
    await settings.setTimeBasedWallpaperEnabled(timeBased);
    await settings.setDockDarkBackground(darkDock);
    await settings.setDockBlurEnabled(dockBlur);
  }
}
