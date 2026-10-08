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

import 'package:flauncher/widgets/side_panel_dialog.dart';
import 'package:flutter/material.dart';

/// A panel along the left edge over the dimmed home screen, as Settings, Inputs and Notifications open. A tap outside
/// the panel closes it.
class SidePanelOverlay extends StatelessWidget {
  final double width;
  final Widget child;

  const SidePanelOverlay({super.key, required this.width, required this.child});

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: Colors.black.withOpacity(0.70),
        body: Stack(
          children: [
            GestureDetector(
              onTap: () => Navigator.of(context).pop(),
              child: Container(color: Colors.transparent),
            ),
            SidePanelDialog(width: width, child: child),
          ],
        ),
      );
}
