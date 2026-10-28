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

/// A hint on a settings page: an info icon and a line of text in a faint box.
class SettingsHint extends StatelessWidget {
  final String text;
  final EdgeInsetsGeometry padding;

  const SettingsHint(this.text, {super.key, this.padding = const EdgeInsets.symmetric(vertical: 8.0)});

  @override
  Widget build(BuildContext context) => Padding(
        padding: padding,
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.05),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: [
              const Icon(Icons.info_outline, size: 20, color: Colors.white70),
              const SizedBox(width: 12),
              Expanded(
                child: Text(text, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.white70)),
              ),
            ],
          ),
        ),
      );
}
