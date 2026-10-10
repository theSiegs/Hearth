/*
 * FLauncher
 * Copyright (C) 2021  Étienne Fesser
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

import 'dart:async';

import 'package:flauncher/widgets/app_card_keys.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class FocusKeyboardListener extends StatefulWidget {
  final WidgetBuilder builder;
  final KeyEventResult Function(LogicalKeyboardKey)? onPressed;
  final KeyEventResult Function(LogicalKeyboardKey)? onLongPress;

  /// A long press's action that opens another app's screen: run once the key is let go, not while it's held. A
  /// key released over another app's screen presses whatever has focus there (Android's buttons act on release).
  final void Function(LogicalKeyboardKey)? onLongPressReleased;

  const FocusKeyboardListener({
    super.key,
    required this.builder,
    this.onPressed,
    this.onLongPress,
    this.onLongPressReleased,
  });

  @override
  State<FocusKeyboardListener> createState() => _FocusKeyboardListenerState();
}

class _FocusKeyboardListenerState extends State<FocusKeyboardListener> {
  Timer? _longPressTimer;
  bool _longPressFired = false;
  int? _keyDownAt;
  final Set<LogicalKeyboardKey> _handledKeys = {};

  @override
  void dispose() {
    _longPressTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Focus(
        canRequestFocus: false,
        onKeyEvent: (_, keyEvent) => _handleKey(keyEvent),
        child: Builder(builder: widget.builder),
      );

  KeyEventResult _handleKey(KeyEvent keyEvent) {
    final key = keyEvent.logicalKey;
    if (keyEvent is KeyRepeatEvent && AppCardKeys.isArrowKey(key)) {
      return widget.onPressed?.call(key) ?? KeyEventResult.ignored;
    }

    return switch (keyEvent) {
      KeyDownEvent() || KeyRepeatEvent() => _keyDownEvent(key),
      KeyUpEvent() => _keyUpEvent(key),
      _ => KeyEventResult.handled,
    };
  }

  KeyEventResult _keyDownEvent(LogicalKeyboardKey key) {
    // Menu or info key opens options immediately without waiting
    if (AppCardKeys.menuKeys.contains(key)) {
      _longPressTimer?.cancel();
      // A long press already: its release runs onLongPressReleased
      _longPressFired = widget.onLongPressReleased != null;
      _keyDownAt = null;
      return widget.onLongPress?.call(key) ?? KeyEventResult.ignored;
    }

    if (!AppCardKeys.longPressableKeys.contains(key)) {
      final result = widget.onPressed?.call(key) ?? KeyEventResult.ignored;
      if (result == KeyEventResult.handled) {
        _handledKeys.add(key);
      }
      return result;
    }

    // Still held after the long press fired: the repeats belong to it, not to a new press
    if (_longPressFired) return KeyEventResult.handled;
    if (_keyDownAt == null) {
      _keyDownAt = DateTime.now().millisecondsSinceEpoch;
      _longPressFired = false;
      _longPressTimer?.cancel();
      _longPressTimer = Timer(const Duration(milliseconds: 500), () {
        if (!mounted) return;
        if (_keyDownAt != null) {
          _longPressFired = true;
          _keyDownAt = null;
          widget.onLongPress?.call(key);
        }
      });
      return KeyEventResult.handled;
    } else if (_longPress() && !_longPressFired) {
      _longPressTimer?.cancel();
      _longPressFired = true;
      _keyDownAt = null;
      return widget.onLongPress?.call(key) ?? KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
  }

  KeyEventResult _keyUpEvent(LogicalKeyboardKey key) {
    _longPressTimer?.cancel();
    if (_handledKeys.remove(key)) {
      return KeyEventResult.handled;
    }
    if (_longPressFired) {
      _longPressFired = false;
      widget.onLongPressReleased?.call(key);
      return KeyEventResult.handled;
    }
    if (_keyDownAt != null) {
      _keyDownAt = null;
      return widget.onPressed?.call(key) ?? KeyEventResult.ignored;
    }
    return KeyEventResult.ignored;
  }

  bool _longPress() => _keyDownAt != null && DateTime.now().millisecondsSinceEpoch - _keyDownAt! >= 500;
}
