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

/// For permissions the TV won't grant from its own screens: why, and the adb command to run from a computer.
///
/// [actionLabel] adds a button before OK that closes the dialog and runs [onAction].
Future<void> showAdbCommandDialog(
  BuildContext context, {
  required String title,
  required String message,
  required String command,
  String? actionLabel,
  VoidCallback? onAction,
}) {
  return showDialog<void>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(title),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(message),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.black26,
              borderRadius: BorderRadius.circular(4),
            ),
            child: SelectableText(command, style: const TextStyle(fontFamily: 'monospace', fontSize: 12)),
          ),
        ],
      ),
      actions: [
        if (actionLabel != null)
          TextButton(
            onPressed: () {
              Navigator.of(dialogContext).pop();
              onAction?.call();
            },
            child: Text(actionLabel),
          ),
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(),
          child: const Text('OK'),
        ),
      ],
    ),
  );
}
