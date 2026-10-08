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

import 'package:flauncher/l10n/app_localizations.dart';
import 'package:flauncher/providers/settings_service.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'accent_color_page.dart';
import 'dock_labels_page.dart';
import 'focusable_settings_tile.dart';
import 'animations_sound_page.dart';
import 'card_style_page.dart';
import 'settings_page.dart';

/// How the home screen looks and feels: card style, accent color, the dock and labels, animations and sound.
class LookSettingsPage extends StatelessWidget {
  static const String routeName = "look_settings";

  /// CardStylePage's choices, by their saved value.
  static const Map<String, String> cardStyles = {
    "modern": "Default",
    "premium": "Premium",
    "glow": "Glow",
    "squircle": "Squircle",
    "classic": "Classic",
    "minimal": "Minimal",
    "capsule": "Capsule",
  };

  const LookSettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context)!;
    final textTheme = Theme.of(context).textTheme;
    final cardStyle = context.select<SettingsService, String>((s) => s.themes);
    return SettingsPage(
      title: "Look",
      children: [
        FocusableSettingsTile(
          autofocus: true,
          leading: const Icon(Icons.crop_square),
          title: Text(CardStylePage.title, style: textTheme.bodyMedium),
          trailing: Text(cardStyles[cardStyle] ?? "", style: textTheme.bodySmall),
          onPressed: () => Navigator.of(context).pushNamed(CardStylePage.routeName),
        ),
        FocusableSettingsTile(
          leading: const Icon(Icons.palette_outlined),
          title: Text(localizations.accentColor, style: textTheme.bodyMedium),
          onPressed: () => Navigator.of(context).pushNamed(AccentColorPage.routeName),
        ),
        FocusableSettingsTile(
          leading: const Icon(Icons.call_to_action_outlined),
          title: Text(DockLabelsPage.title, style: textTheme.bodyMedium),
          onPressed: () => Navigator.of(context).pushNamed(DockLabelsPage.routeName),
        ),
        FocusableSettingsTile(
          leading: const Icon(Icons.animation),
          title: Text(AnimationsSoundPage.title, style: textTheme.bodyMedium),
          onPressed: () => Navigator.of(context).pushNamed(AnimationsSoundPage.routeName),
        ),
      ],
    );
  }
}
