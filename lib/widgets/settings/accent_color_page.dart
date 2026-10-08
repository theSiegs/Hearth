/*
 * FLauncher
 * Copyright (C) 2024 LeanBitLab
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
import 'package:flauncher/l10n/app_localizations.dart';
import 'package:provider/provider.dart';

import '../../providers/settings_service.dart';
import '../focusable_tap.dart';
import 'settings_page.dart';

class AccentColorPage extends StatelessWidget {
  static const String routeName = "accent_color_panel";

  static const List<(String hex, String name)> colorPresets = [
    (ACCENT_COLOR_PURPLE, 'Purple'),
    (ACCENT_COLOR_TEAL, 'Teal'),
    (ACCENT_COLOR_BLUE, 'Blue'),
    (ACCENT_COLOR_ORANGE, 'Orange'),
    (ACCENT_COLOR_PINK, 'Pink'),
    (ACCENT_COLOR_GREEN, 'Green'),
    (ACCENT_COLOR_WHITE, 'White'),
    (ACCENT_COLOR_YELLOW, 'Yellow'),
    (ACCENT_COLOR_RED, 'Red'),
    (ACCENT_COLOR_CYAN, 'Cyan'),
    (ACCENT_COLOR_INDIGO, 'Indigo'),
    (ACCENT_COLOR_LIME, 'Lime'),
    (ACCENT_COLOR_AMBER, 'Amber'),
    (ACCENT_COLOR_ROSE, 'Rose'),
    (ACCENT_COLOR_ICE_BLUE, 'Ice Blue'),
  ];

  const AccentColorPage({super.key});

  @override
  Widget build(BuildContext context) {
    AppLocalizations localizations = AppLocalizations.of(context)!;
    return Consumer<SettingsService>(
      builder: (context, settingsService, _) {
        final currentColorHex = settingsService.accentColorHex;
        final currentColor = settingsService.accentColor;

        return SettingsPage.custom(
          title: localizations.accentColor,
          body: Column(
            children: [
              Expanded(
                child: GridView.builder(
                  padding: const EdgeInsets.all(16),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 3,
                    crossAxisSpacing: 12,
                    mainAxisSpacing: 12,
                    childAspectRatio: 1.3,
                  ),
                  itemCount: colorPresets.length,
                  itemBuilder: (context, index) {
                    final (hex, name) = colorPresets[index];
                    final isSelected = currentColorHex == hex;

                    return _ColorTile(
                      color: accentColorFromHex(hex),
                      name: name,
                      isSelected: isSelected,
                      autofocus: index == 0,
                      onTap: () => settingsService.setAccentColor(hex),
                    );
                  },
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.black26,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: currentColor.withOpacity(0.5),
                      width: 1.5,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 10,
                        height: 10,
                        decoration: BoxDecoration(
                          color: currentColor,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 8),
                      const Text(
                        'Selected Accent',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _ColorTile extends StatelessWidget {
  final Color color;
  final String name;
  final bool isSelected;
  final bool autofocus;
  final VoidCallback onTap;

  const _ColorTile({
    required this.color,
    required this.name,
    required this.isSelected,
    required this.onTap,
    this.autofocus = false,
  });

  @override
  Widget build(BuildContext context) {
    final isLightColor = color.computeLuminance() > 0.5;
    final iconColor = isLightColor ? Colors.black : Colors.white;

    return FocusableTap(
      autofocus: autofocus,
      onPressed: onTap,
      builder: (context, focused) => Container(
        decoration: BoxDecoration(
          color: color.withOpacity(0.2),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: focused ? Colors.white : (isSelected ? color : Colors.transparent),
            width: focused ? 2.5 : (isSelected ? 2 : 0),
          ),
          boxShadow: focused ? [BoxShadow(color: color.withOpacity(0.5), blurRadius: 8)] : null,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 14,
              height: 14,
              decoration: BoxDecoration(
                color: color,
                shape: BoxShape.circle,
              ),
              child: isSelected ? Icon(Icons.check, color: iconColor, size: 10) : null,
            ),
            const SizedBox(width: 8),
            Text(
              name,
              style: TextStyle(
                color: Colors.white,
                fontWeight: focused || isSelected ? FontWeight.bold : FontWeight.w500,
                fontSize: 13,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
