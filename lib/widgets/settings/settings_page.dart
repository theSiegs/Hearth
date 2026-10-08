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

/// A page of the Settings panel: its title centered over a divider, and its content below.
class SettingsPage extends StatelessWidget {
  final String title;

  /// A line under the title, such as how much of a checklist is done.
  final Widget? subtitle;

  final EdgeInsetsGeometry? padding;
  final CrossAxisAlignment crossAxisAlignment;
  final List<Widget>? children;
  final Widget? body;

  /// [children] in a scroll view. They're all built at once, so any of them can take focus when the page opens.
  const SettingsPage({
    super.key,
    required this.title,
    this.subtitle,
    this.padding,
    this.crossAxisAlignment = CrossAxisAlignment.stretch,
    required List<Widget> this.children,
  }) : body = null;

  /// For a page that lays out its own [body]: a grid, a long list built as it scrolls, a spinner while loading.
  const SettingsPage.custom({super.key, required this.title, this.subtitle, required Widget this.body})
      : children = null,
        padding = null,
        crossAxisAlignment = CrossAxisAlignment.stretch;

  @override
  Widget build(BuildContext context) => Column(
        children: [
          Text(title, style: Theme.of(context).textTheme.titleLarge),
          if (subtitle != null) subtitle!,
          const Divider(),
          Expanded(
            child: body ??
                SingleChildScrollView(
                  padding: padding,
                  child: Column(crossAxisAlignment: crossAxisAlignment, children: children!),
                ),
          ),
        ],
      );
}
