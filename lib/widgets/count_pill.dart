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

import 'focusable_tap.dart';

/// A HearthTube-style filter pill with a count: white when selected, see-through otherwise; focusing it selects it.
/// Search's grid and Continue Watching's "See all" use it.
class CountPill extends StatelessWidget {
  final String label;
  final int count;
  final bool selected;
  final bool autofocus;
  final VoidCallback onSelected;

  const CountPill(
      {super.key,
      required this.label,
      required this.count,
      required this.selected,
      required this.onSelected,
      this.autofocus = false});

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    final fg = selected ? Colors.black : Colors.white;
    return FocusableTap(
      autofocus: autofocus,
      onPressed: onSelected,
      onFocusChange: (focused) {
        if (focused) onSelected();
      },
      builder: (context, focused) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 9),
        decoration: BoxDecoration(
          color: selected ? Colors.white : Colors.white.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: focused ? accent : Colors.white.withValues(alpha: 0.15), width: focused ? 3 : 1),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Text(label, style: TextStyle(color: fg, fontSize: 17, fontWeight: FontWeight.w500)),
          const SizedBox(width: 8),
          Text("$count", style: TextStyle(color: fg.withValues(alpha: 0.6), fontSize: 14)),
        ]),
      ),
    );
  }
}
