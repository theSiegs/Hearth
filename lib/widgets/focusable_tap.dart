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

/// A button for the D-pad: select and a tap both run [onPressed], and [builder] draws it
/// focused or not. It is a single focus stop.
class FocusableTap extends StatefulWidget {
  final VoidCallback onPressed;
  final Widget Function(BuildContext context, bool focused) builder;
  final FocusNode? focusNode;
  final bool autofocus;
  final ValueChanged<bool>? onFocusChange;

  /// The shape of the ink splash a tap shows; without one, a tap shows none.
  final ShapeBorder? splashShape;

  const FocusableTap({
    super.key,
    required this.onPressed,
    required this.builder,
    this.focusNode,
    this.autofocus = false,
    this.onFocusChange,
    this.splashShape,
  });

  @override
  State<FocusableTap> createState() => _FocusableTapState();
}

class _FocusableTapState extends State<FocusableTap> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final Widget child = widget.builder(context, _focused);
    return Actions(
      actions: <Type, Action<Intent>>{
        ActivateIntent: CallbackAction<ActivateIntent>(onInvoke: (_) => widget.onPressed()),
        ButtonActivateIntent: CallbackAction<ButtonActivateIntent>(onInvoke: (_) => widget.onPressed()),
      },
      child: Focus(
        focusNode: widget.focusNode,
        autofocus: widget.autofocus,
        onFocusChange: (focused) {
          setState(() => _focused = focused);
          widget.onFocusChange?.call(focused);
        },
        child: widget.splashShape == null
            ? GestureDetector(onTap: widget.onPressed, child: child)
            : InkWell(
                onTap: widget.onPressed,
                // The Focus above takes focus; the InkWell would be a second stop.
                canRequestFocus: false,
                // The builder draws the focused look; only a tap's splash comes from the InkWell.
                hoverColor: Colors.transparent,
                highlightColor: Colors.transparent,
                customBorder: widget.splashShape,
                child: child,
              ),
      ),
    );
  }
}
