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

import 'package:flauncher/models/category.dart';
import 'package:flauncher/providers/settings_service.dart';
import 'package:flauncher/widgets/card_style.dart';
import 'package:flauncher/widgets/category_row.dart';
import 'package:flauncher/widgets/frosted_glass.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

/// Space between the dock's edge and the app cards inside it.
const double kDockInnerPadding = 10;

/// The dock's corner radius for a card style: the cards' radius plus the dock's padding, so its corners follow the
/// cards' (square cards, a square dock).
double dockRadiusForTheme(String theme) {
  final double cardRadius = CardStyle.of(theme).radius;
  return cardRadius == 0 ? 0 : cardRadius + kDockInnerPadding;
}

/// The Favorites section as a bar of glass over the wallpaper, centred on the home's first screen. Its look comes
/// from Settings → Home screen → Look: frosted or clear, dark or light, with or without a shadow.
class HomeDock extends StatelessWidget {
  final Category category;
  final bool isFirstSection;

  const HomeDock({super.key, required this.category, this.isFirstSection = false});

  @override
  Widget build(BuildContext context) {
    final look = context.select<SettingsService, _DockLook>((s) =>
        _DockLook(theme: s.themes, frosted: s.dockBlurEnabled, dark: s.dockDarkBackground, shadow: s.dockShadowEnabled));
    final shape = BorderRadius.circular(dockRadiusForTheme(look.theme));
    return Center(
      key: const Key("home_dock"),
      // The glass sits behind the row and is the only part clipped to the dock's shape: a focused card grows and
      // glows past the dock's edge, so the cards themselves aren't clipped
      child: Stack(children: [
        Positioned.fill(child: _DockGlass(look: look, shape: shape)),
        Padding(
          // The row pads each card by 8 already
          padding: const EdgeInsets.all(kDockInnerPadding - 8),
          child: CategoryRow(category: category, isFirstSection: isFirstSection, showTitle: false, shrinkWrap: true),
        ),
      ]),
    );
  }
}

/// The settings the dock is drawn with; equal looks don't rebuild it.
@immutable
class _DockLook {
  final String theme;
  final bool frosted;
  final bool dark;
  final bool shadow;

  const _DockLook({required this.theme, required this.frosted, required this.dark, required this.shadow});

  @override
  bool operator ==(Object other) =>
      other is _DockLook && other.theme == theme && other.frosted == frosted && other.dark == dark && other.shadow == shadow;

  @override
  int get hashCode => Object.hash(theme, frosted, dark, shadow);
}

class _DockGlass extends StatelessWidget {
  final _DockLook look;
  final BorderRadius shape;

  const _DockGlass({required this.look, required this.shape});

  @override
  Widget build(BuildContext context) {
    // A dark tint for light wallpapers, a faint light one otherwise, and an edge that catches the light
    final tint = look.dark ? const Color(0x59000000) : const Color(0x1AFFFFFF);
    final edge = look.dark ? const Color(0x14FFFFFF) : const Color(0x26FFFFFF);
    Widget glass = DecoratedBox(
      decoration: BoxDecoration(color: tint, borderRadius: shape, border: Border.all(color: edge, width: 1.5)),
    );
    if (look.frosted) glass = FrostedGlass(sigma: 12, child: glass);
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: shape,
        boxShadow: look.shadow ? const [BoxShadow(color: Color(0x4D000000), blurRadius: 20, spreadRadius: 2)] : null,
      ),
      child: ClipRRect(borderRadius: shape, child: glass),
    );
  }
}
