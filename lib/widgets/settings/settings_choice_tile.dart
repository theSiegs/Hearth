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

import 'focusable_settings_tile.dart';

/// One option on a "pick one" page: a radio mark, its label and an optional second line.
///
/// The chosen option takes focus when the page opens, so the remote starts where the current value is.
class SettingsChoiceTile<T> extends StatelessWidget {
  final String title;
  final String? subtitle;
  final T value;
  final T groupValue;
  final ValueChanged<T> onChanged;

  /// Defaults to whether this option is the chosen one.
  final bool? autofocus;

  const SettingsChoiceTile({
    super.key,
    required this.title,
    this.subtitle,
    required this.value,
    required this.groupValue,
    required this.onChanged,
    this.autofocus,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final selected = value == groupValue;
    final label = Text(title, style: theme.textTheme.bodyMedium);
    return FocusableSettingsTile(
      autofocus: autofocus ?? selected,
      leading: Icon(
        selected ? Icons.radio_button_checked : Icons.radio_button_unchecked,
        color: selected ? theme.colorScheme.secondary : Colors.grey,
      ),
      title: subtitle == null
          ? label
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                label,
                Text(subtitle!, style: const TextStyle(fontSize: 12, color: Colors.grey)),
              ],
            ),
      onPressed: () => onChanged(value),
    );
  }
}
