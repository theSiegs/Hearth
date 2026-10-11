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
import 'package:flutter/services.dart';

/// A one-line text field for the remote. Moving onto it only selects it: OK starts editing (the keyboard comes up),
/// so passing through a page never changes a value by accident. While editing, Up and Down leave it for the row above
/// or below (a plain field keeps them, so the remote could never get past it), Left and Right move the cursor, and
/// OK brings the keyboard back after it was put away; leaving the field or submitting ends the editing.
class RemoteTextField extends StatefulWidget {
  final TextEditingController controller;
  final InputDecoration decoration;
  final bool obscureText;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final ValueChanged<String>? onSubmitted;

  const RemoteTextField({
    super.key,
    required this.controller,
    required this.decoration,
    this.obscureText = false,
    this.keyboardType,
    this.textInputAction,
    this.onSubmitted,
  });

  @override
  State<RemoteTextField> createState() => _RemoteTextFieldState();
}

class _RemoteTextFieldState extends State<RemoteTextField> {
  /// OK was pressed on it: the value can change (until the field is left or submitted).
  bool _editing = false;

  late final FocusNode _focus = FocusNode(onKeyEvent: (node, event) {
    if (event is KeyUpEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;
    final bool sideways = key == LogicalKeyboardKey.arrowLeft || key == LogicalKeyboardKey.arrowRight;
    if (key == LogicalKeyboardKey.arrowUp || key == LogicalKeyboardKey.arrowDown || (sideways && !_editing)) {
      if (event is KeyDownEvent) {
        node.focusInDirection(switch (key) {
          LogicalKeyboardKey.arrowUp => TraversalDirection.up,
          LogicalKeyboardKey.arrowDown => TraversalDirection.down,
          LogicalKeyboardKey.arrowLeft => TraversalDirection.left,
          _ => TraversalDirection.right,
        });
      }
      return KeyEventResult.handled;
    }
    if (event is KeyDownEvent && (key == LogicalKeyboardKey.select || key == LogicalKeyboardKey.enter)) {
      if (!_editing) {
        setState(() => _editing = true);
        // Editable from the next frame: the field asks for the keyboard itself then
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && _focus.hasFocus) SystemChannels.textInput.invokeMethod("TextInput.show");
        });
      } else {
        SystemChannels.textInput.invokeMethod("TextInput.show");
      }
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  });

  @override
  void initState() {
    super.initState();
    _focus.addListener(_onFocusChange);
  }

  void _onFocusChange() {
    if (!_focus.hasFocus && _editing) setState(() => _editing = false);
  }

  @override
  void dispose() {
    _focus.removeListener(_onFocusChange);
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => TextField(
        controller: widget.controller,
        focusNode: _focus,
        readOnly: !_editing,
        showCursor: _editing,
        obscureText: widget.obscureText,
        keyboardType: widget.keyboardType,
        textInputAction: widget.textInputAction,
        onSubmitted: (value) {
          setState(() => _editing = false);
          widget.onSubmitted?.call(value);
        },
        decoration: widget.decoration,
      );
}
