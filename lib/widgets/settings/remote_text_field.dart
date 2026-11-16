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

import 'package:flauncher/flauncher_channel.dart';
import 'package:flauncher/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../keyboard/hearth_keyboard.dart';
import '../keyboard/keyboard_choice.dart';

/// A one-line text field for the remote. Moving onto it only selects it: OK starts editing (the keyboard comes up),
/// so passing through a page never changes a value by accident. While editing, Up and Down leave it for the row above
/// or below (a plain field keeps them, so the remote could never get past it), Left and Right move the cursor, and
/// OK brings the keyboard back after it was put away; leaving the field or submitting ends the editing.
///
/// The keyboard is on-screen first: the TV's own when it is an on-screen one, else Hearth's own over the page (the
/// TV's keyboard is a phone's, as Google TV leaves it after a phone remote went away), which offers the phone only
/// while one is there (see [chooseKeyboard]).
class RemoteTextField extends StatefulWidget {
  final TextEditingController controller;
  final InputDecoration decoration;
  final bool obscureText;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final ValueChanged<String>? onSubmitted;
  final ValueChanged<String>? onChanged;

  /// The field's focus node, when the page needs it; otherwise the field keeps its own.
  final FocusNode? focusNode;
  final bool autofocus;

  /// Start editing as soon as the field shows (with [autofocus]), as a dialog with one box does.
  final bool startEditing;

  const RemoteTextField({
    super.key,
    required this.controller,
    required this.decoration,
    this.obscureText = false,
    this.keyboardType,
    this.textInputAction,
    this.onSubmitted,
    this.onChanged,
    this.focusNode,
    this.autofocus = false,
    this.startEditing = false,
  });

  @override
  State<RemoteTextField> createState() => _RemoteTextFieldState();
}

class _RemoteTextFieldState extends State<RemoteTextField> {
  /// OK was pressed on it: the value can change (until the field is left or submitted).
  bool _editing = false;

  /// Hearth's keyboard is over the page for this field.
  bool _hearthKeyboardOpen = false;

  FocusNode? _ownFocus;
  FocusNode get _focus => widget.focusNode ?? (_ownFocus ??= FocusNode());

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
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
      _startEditing();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  void initState() {
    super.initState();
    _focus.onKeyEvent = _onKey;
    _focus.addListener(_onFocusChange);
    if (widget.startEditing) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _focus.requestFocus();
        _startEditing();
      });
    }
  }

  void _onFocusChange() {
    if (!_focus.hasFocus && _editing) setState(() => _editing = false);
  }

  @override
  void dispose() {
    _focus.removeListener(_onFocusChange);
    if (widget.focusNode != null && widget.focusNode!.onKeyEvent == _onKey) widget.focusNode!.onKeyEvent = null;
    _ownFocus?.dispose();
    super.dispose();
  }

  /// OK on the field: the keyboard on screen first (see the class comment).
  Future<void> _startEditing() async {
    final channel = context.read<FLauncherChannel?>();
    if (channel == null) {
      _systemKeyboard();
      return;
    }
    final choice = await chooseKeyboard(channel);
    if (!mounted || _hearthKeyboardOpen) return;
    switch (choice.way) {
      case KeyboardWay.system:
        _systemKeyboard();
      case KeyboardWay.systemAfterSwitch:
        await Future<void>.delayed(KeyboardChoice.switchSettle);
        if (mounted) _systemKeyboard();
      case KeyboardWay.hearth:
        await _hearthKeyboard(channel, choice.status);
    }
  }

  void _systemKeyboard() {
    if (!_editing) {
      setState(() => _editing = true);
      // Editable from the next frame: the field asks for the keyboard itself then
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _focus.hasFocus) SystemChannels.textInput.invokeMethod("TextInput.show");
      });
    } else {
      SystemChannels.textInput.invokeMethod("TextInput.show");
    }
  }

  Future<void> _hearthKeyboard(FLauncherChannel channel, KeyboardStatus status) async {
    final l = AppLocalizations.of(context)!;
    final decoration = widget.decoration;
    final numeric = widget.keyboardType == TextInputType.number;
    _hearthKeyboardOpen = true;
    final before = widget.controller.text;
    final result = await showHearthKeyboardSheet(
      context,
      controller: widget.controller,
      status: status,
      channel: channel,
      label: decoration.labelText ?? decoration.hintText,
      obscure: widget.obscureText,
      numeric: numeric,
      actionLabel: widget.textInputAction == TextInputAction.next ? l.keyboardNext : l.done,
    );
    _hearthKeyboardOpen = false;
    if (!mounted) return;
    if (widget.controller.text != before) widget.onChanged?.call(widget.controller.text);
    switch (result) {
      case HearthKeyboardResult.action:
        widget.onSubmitted?.call(widget.controller.text);
        if (widget.textInputAction == TextInputAction.next) _focus.focusInDirection(TraversalDirection.down);
      case HearthKeyboardResult.phone:
        // The TV's keyboard, which sends the typing to the phone remote
        _focus.requestFocus();
        _systemKeyboard();
      case null:
        break;
    }
  }

  @override
  Widget build(BuildContext context) => TextField(
        controller: widget.controller,
        focusNode: _focus,
        autofocus: widget.autofocus,
        readOnly: !_editing,
        showCursor: _editing,
        obscureText: widget.obscureText,
        keyboardType: widget.keyboardType,
        textInputAction: widget.textInputAction,
        onChanged: widget.onChanged,
        onSubmitted: (value) {
          setState(() => _editing = false);
          widget.onSubmitted?.call(value);
        },
        decoration: widget.decoration,
      );
}
