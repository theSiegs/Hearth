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

import 'dart:ui' as ui;

import 'package:flauncher/models/app.dart';
import 'package:flauncher/models/category.dart';
import 'package:flauncher/providers/settings_service.dart';
import 'package:flauncher/widgets/category_row.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

/// Space between the dock's edge and the app cards inside it.
const double kDockInnerPadding = 10;

/// The dock's corner radius for a theme: the card radius plus the dock's padding,
/// so the dock's corners run parallel to the cards' corners.
double dockRadiusForTheme(String theme) {
  final double cardRadius = switch (theme) {
    'classic' => 0,
    'minimal' => 4,
    'glow' => 12,
    'premium' => 16,
    'squircle' => 24,
    'capsule' => 100,
    _ => 8,
  };
  return cardRadius == 0 ? 0 : cardRadius + kDockInnerPadding;
}

/// Favorites shown as a frosted bar, adapted from arclauncher's dock.
class HomeDock extends StatelessWidget {
  final Category category;
  final List<App> applications;
  final bool isFirstSection;

  const HomeDock({
    super.key,
    required this.category,
    required this.applications,
    this.isFirstSection = false,
  });

  @override
  Widget build(BuildContext context) {
    final (theme, blur, dark, shadow) = context.select<SettingsService, (String, bool, bool, bool)>(
      (s) => (s.themes, s.dockBlurEnabled, s.dockDarkBackground, s.dockShadowEnabled),
    );
    final borderRadius = BorderRadius.circular(dockRadiusForTheme(theme));

    final Widget panel = DecoratedBox(
      decoration: BoxDecoration(
        color: dark ? Colors.black.withOpacity(0.35) : Colors.white.withOpacity(0.1),
        borderRadius: borderRadius,
        border: Border.all(color: Colors.white.withOpacity(dark ? 0.08 : 0.15), width: 1.5),
      ),
    );

    // Only the panel is clipped to the dock's shape; the cards are drawn on top, unclipped,
    // so a focused card's zoom and glow can spill past the dock's edge.
    return Center(
      key: const Key("home_dock"),
      child: Stack(
        children: [
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: borderRadius,
                boxShadow:
                    shadow ? [BoxShadow(color: Colors.black.withOpacity(0.3), blurRadius: 20, spreadRadius: 2)] : null,
              ),
              child: ClipRRect(
                borderRadius: borderRadius,
                child: blur ? BackdropFilter(filter: ui.ImageFilter.blur(sigmaX: 12, sigmaY: 12), child: panel) : panel,
              ),
            ),
          ),
          Padding(
            // CategoryRow already pads its cards by 8.
            padding: const EdgeInsets.all(kDockInnerPadding - 8),
            child: CategoryRow(
              category: category,
              applications: applications,
              isFirstSection: isFirstSection,
              showTitle: false,
              shrinkWrap: true,
            ),
          ),
        ],
      ),
    );
  }
}
