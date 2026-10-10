/*
 * FLauncher
 * Copyright (C) 2026 LeanBitLab
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
import 'package:flauncher/widgets/settings/settings_choice_tile.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flauncher/widgets/settings/settings_page.dart';

class AppLanguagePage extends StatelessWidget {
  static const String routeName = "app_language_panel";

  const AppLanguagePage({super.key});

  /// Each choice: its code ("" for the TV's own language) and its name in the current language.
  static List<(String, String)> choices(AppLocalizations l) => [
        ("", l.systemDefault),
        ("en", l.english),
        ("es", l.spanish),
        ("fr", l.french),
        ("de", l.german),
        ("it", l.italian),
        ("pt", l.portuguese),
        ("ru", l.russian),
        ("uk", l.ukrainian),
        ("tr", l.turkish),
        ("ar", l.arabic),
        ("hi", l.hindi),
        ("zh", l.chinese),
        ("ja", l.japanese),
        ("ko", l.korean),
      ];

  /// The name of the language Hearth is set to, as this page lists it.
  static String nameOf(AppLocalizations l, String code) =>
      choices(l).firstWhere((choice) => choice.$1 == code, orElse: () => choices(l).first).$2;

  @override
  Widget build(BuildContext context) {
    AppLocalizations localizations = AppLocalizations.of(context)!;
    return Consumer<SettingsService>(
      builder: (context, service, _) {
        return SettingsPage(
          title: localizations.appLanguage,
          children: [
            for (final (code, label) in choices(localizations)) _choice(service, label, code),
          ],
        );
      },
    );
  }

  Widget _choice(SettingsService service, String label, String value) => SettingsChoiceTile<String>(
        title: label,
        value: value,
        groupValue: service.appLanguage,
        onChanged: service.setAppLanguage,
      );
}
