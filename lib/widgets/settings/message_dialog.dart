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
import 'package:flutter/material.dart';

/// A title, a message and OK. True when it was closed with OK rather than Back.
///
/// OK starts focused, so the remote's OK button closes it right away.
Future<bool> showMessageDialog(BuildContext context, {required String title, required String message}) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(
          autofocus: true,
          onPressed: () => Navigator.of(dialogContext).pop(true),
          child: Text(AppLocalizations.of(dialogContext)!.ok),
        ),
      ],
    ),
  );
  return ok ?? false;
}

/// A title, [lines] of text one under another and the [actions] (built with the dialog's context, to close it).
Future<T?> showLinesDialog<T>(
  BuildContext context, {
  required String title,
  required List<String> lines,
  required List<Widget> Function(BuildContext dialogContext) actions,
}) {
  final textTheme = Theme.of(context).textTheme;
  return showDialog<T>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: SizedBox(
        width: 460,
        // Longer languages can run past the screen's height
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final line in lines) ...[
                Text(line, style: textTheme.bodyMedium),
                const SizedBox(height: 10),
              ],
            ],
          ),
        ),
      ),
      actions: actions(context),
    ),
  );
}
