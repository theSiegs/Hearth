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

import 'package:flauncher/providers/settings_service.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

/// The dark rounded card About and Check for Updates are drawn on. It scrolls when taller than the screen allows.
class HearthDialogFrame extends StatelessWidget {
  final double width;
  final EdgeInsetsGeometry padding;
  final EdgeInsets insetPadding;

  /// The tallest it gets, as a share of the screen's height.
  final double maxHeightFactor;

  final Widget child;

  const HearthDialogFrame({
    super.key,
    required this.width,
    required this.padding,
    this.insetPadding = const EdgeInsets.all(20),
    this.maxHeightFactor = 0.88,
    required this.child,
  });

  @override
  Widget build(BuildContext context) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: insetPadding,
        child: Container(
          width: width,
          constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * maxHeightFactor),
          padding: padding,
          decoration: BoxDecoration(
            color: const Color(0xFF0F0F0F),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.white.withOpacity(0.12), width: 1),
          ),
          child: SingleChildScrollView(child: child),
        ),
      );
}

/// A button in a [HearthDialogFrame], made for the remote: tinted with the accent color and outlined when focused.
///
/// [compact] is the smaller kind that's only as wide as its label, for a row of buttons.
class FocusableDialogButton extends StatefulWidget {
  final IconData icon;
  final String label;
  final VoidCallback onPressed;
  final bool autofocus;
  final bool compact;

  const FocusableDialogButton({
    super.key,
    required this.icon,
    required this.label,
    required this.onPressed,
    this.autofocus = false,
    this.compact = false,
  });

  @override
  State<FocusableDialogButton> createState() => _FocusableDialogButtonState();
}

class _FocusableDialogButtonState extends State<FocusableDialogButton> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final accentColor = context.select((SettingsService s) => s.accentColor);
    final compact = widget.compact;
    final (verticalPadding, radius, tint, gap, fontSize) = compact ? (8.0, 8.0, 0.3, 6.0, 12.0) : (10.0, 10.0, 0.2, 8.0, 13.0);
    final label = Text(
      widget.label,
      textAlign: TextAlign.center,
      style: TextStyle(
        color: Colors.white,
        fontSize: fontSize,
        fontWeight: _focused ? FontWeight.bold : FontWeight.w500,
      ),
    );

    return Actions(
      actions: <Type, Action<Intent>>{
        ActivateIntent: CallbackAction<ActivateIntent>(onInvoke: (_) => widget.onPressed()),
        ButtonActivateIntent: CallbackAction<ButtonActivateIntent>(onInvoke: (_) => widget.onPressed()),
      },
      child: Focus(
        autofocus: widget.autofocus,
        onFocusChange: (hasFocus) => setState(() => _focused = hasFocus),
        child: GestureDetector(
          onTap: widget.onPressed,
          child: Container(
            padding: EdgeInsets.symmetric(horizontal: 14, vertical: verticalPadding),
            decoration: BoxDecoration(
              color: _focused ? accentColor.withOpacity(tint) : Colors.white.withOpacity(0.06),
              borderRadius: BorderRadius.circular(radius),
              border: Border.all(
                color: _focused ? Colors.white : Colors.transparent,
                width: _focused ? 2 : 0,
              ),
            ),
            child: Row(
              mainAxisSize: compact ? MainAxisSize.min : MainAxisSize.max,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(widget.icon, size: 16, color: _focused && !compact ? Colors.white : Colors.white70),
                SizedBox(width: gap),
                // A compact button sits in a row, which gives no width to flex into
                compact ? label : Flexible(child: label),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
