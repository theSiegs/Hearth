/*
 * LTvLauncher
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
import 'package:provider/provider.dart';

import '../providers/profile_service.dart';
import '../providers/settings_service.dart';
import 'focusable_tap.dart';
import 'settings/message_dialog.dart';

// Google TV's dark PIN keypad
const _background = Color(0xFF111111);
const _key = Color(0xFF2D2E31);
const _keyFocused = Color(0xFFE8EAED);
const _textDim = Color(0xFF9AA0A6);

/// In a Google TV kids profile, launcher settings and app menus need the parent PIN.
/// Returns true when the caller may go ahead.
Future<bool> requireParent(BuildContext context) async {
  final bool kids = context.read<ProfileService?>()?.isKidsProfile ?? false;
  if (!kids) return true;

  final settings = context.read<SettingsService>();
  if (!settings.hasParentPin) {
    await showMessageDialog(context,
        title: "Ask a parent",
        message: "Launcher settings are locked in kids profiles. A parent can set a PIN in Settings → Profiles → "
            "Parent PIN from their own profile.");
    return false;
  }

  final String? pin = await showDialog<String>(
    context: context,
    builder: (_) => ParentPinDialog(
      title: "Parent PIN",
      subtitle: "Kids profile: enter the parent PIN to change the launcher",
      verify: settings.verifyParentPin,
    ),
  );
  return pin != null;
}

/// Full-screen PIN entry in Google TV's style: D-pad keypad, number keys type directly.
/// Pops with the entered PIN, or null on Back.
class ParentPinDialog extends StatefulWidget {
  final String title;
  final String? subtitle;
  final bool Function(String pin)? verify;
  static const int digitCount = 4;

  const ParentPinDialog({super.key, required this.title, this.subtitle, this.verify});

  @override
  State<ParentPinDialog> createState() => _ParentPinDialogState();
}

class _ParentPinDialogState extends State<ParentPinDialog> {
  String _entered = "";
  bool _error = false;

  void _onDigit(String digit) {
    if (_entered.length >= ParentPinDialog.digitCount) return;
    setState(() {
      _entered += digit;
      _error = false;
    });
    if (_entered.length < ParentPinDialog.digitCount) return;

    if (widget.verify == null || widget.verify!(_entered)) {
      Navigator.of(context).pop(_entered);
      return;
    }
    setState(() => _error = true);
    Future.delayed(const Duration(milliseconds: 400), () {
      if (mounted) setState(() => _entered = "");
    });
  }

  void _onBackspace() {
    if (_entered.isEmpty) return;
    setState(() => _entered = _entered.substring(0, _entered.length - 1));
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final String label = event.logicalKey.keyLabel;
    if (label.length == 1 && RegExp(r'[0-9]').hasMatch(label)) {
      _onDigit(label);
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.backspace || event.logicalKey == LogicalKeyboardKey.delete) {
      _onBackspace();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    return Dialog.fullscreen(
      backgroundColor: _background,
      child: Focus(
        onKeyEvent: _onKey,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 64, vertical: 40),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(widget.title, style: const TextStyle(color: Colors.white, fontSize: 32)),
                    if (widget.subtitle != null) ...[
                      const SizedBox(height: 16),
                      Text(widget.subtitle!, style: const TextStyle(color: _textDim, fontSize: 15)),
                    ],
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(_error ? "WRONG PIN" : "ENTER PIN",
                      style: TextStyle(
                          color: _error ? const Color(0xFFF2B8B5) : _textDim, fontSize: 12, letterSpacing: 2)),
                  const SizedBox(height: 16),
                  Row(
                    children: List.generate(ParentPinDialog.digitCount, (i) {
                      final bool current = i == _entered.length;
                      return Container(
                        width: 48,
                        margin: const EdgeInsets.only(right: 16),
                        child: Column(
                          children: [
                            SizedBox(
                              height: 28,
                              child: i < _entered.length
                                  ? const Center(child: Icon(Icons.circle, color: Colors.white, size: 10))
                                  : null,
                            ),
                            Container(height: 3, color: current ? Colors.white : const Color(0xFF3C4043)),
                          ],
                        ),
                      );
                    }),
                  ),
                  const SizedBox(height: 20),
                  _Keypad(onDigit: _onDigit, onBackspace: _onBackspace),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Keypad extends StatefulWidget {
  final void Function(String) onDigit;
  final VoidCallback onBackspace;

  const _Keypad({required this.onDigit, required this.onBackspace});

  static const _layout = [
    ["1", "2", "3"],
    ["4", "5", "6"],
    ["7", "8", "9"],
    ["", "0", "⌫"],
  ];

  @override
  State<_Keypad> createState() => _KeypadState();
}

/// Moves the selection itself, key by key: it stops at the keypad's edges and skips the empty corner, so it can
/// never leave the keypad (with nothing else on the screen to land on, the selection would vanish).
class _KeypadState extends State<_Keypad> {
  late final List<List<FocusNode?>> _nodes = [
    for (final row in _Keypad._layout) [for (final label in row) label.isEmpty ? null : FocusNode()],
  ];

  @override
  void dispose() {
    for (final row in _nodes) {
      for (final node in row) {
        node?.dispose();
      }
    }
    super.dispose();
  }

  KeyEventResult _move(KeyEvent event) {
    if (event is KeyUpEvent) return KeyEventResult.ignored;
    final (dr, dc) = switch (event.logicalKey) {
      LogicalKeyboardKey.arrowUp => (-1, 0),
      LogicalKeyboardKey.arrowDown => (1, 0),
      LogicalKeyboardKey.arrowLeft => (0, -1),
      LogicalKeyboardKey.arrowRight => (0, 1),
      _ => (0, 0),
    };
    if (dr == 0 && dc == 0) return KeyEventResult.ignored;
    for (int r = 0; r < _nodes.length; r++) {
      for (int c = 0; c < _nodes[r].length; c++) {
        if (_nodes[r][c]?.hasFocus != true) continue;
        // Step in the direction until a key, or stay put at the edge.
        int nr = r + dr, nc = c + dc;
        // Up or down onto the empty corner: the nearest key in that row (Down from 7 is 0).
        if (dr != 0 && nr >= 0 && nr < _nodes.length && _nodes[nr][nc] == null) {
          for (final offset in [1, -1, 2, -2]) {
            final alt = nc + offset;
            if (alt >= 0 && alt < _nodes[nr].length && _nodes[nr][alt] != null) {
              _nodes[nr][alt]!.requestFocus();
              return KeyEventResult.handled;
            }
          }
        }
        while (nr >= 0 && nr < _nodes.length && nc >= 0 && nc < _nodes[nr].length) {
          final next = _nodes[nr][nc];
          if (next != null) {
            next.requestFocus();
            break;
          }
          nr += dr;
          nc += dc;
        }
        return KeyEventResult.handled;
      }
    }
    _nodes[0][0]?.requestFocus();
    return KeyEventResult.handled;
  }

  Widget _button(String label, FocusNode? focusNode, {required bool autofocus}) {
    if (label.isEmpty) {
      return const SizedBox(width: 56, height: 56);
    }
    return _KeypadButton(
      label: label,
      focusNode: focusNode,
      autofocus: autofocus,
      onPressed: () => label == "⌫" ? widget.onBackspace() : widget.onDigit(label),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      canRequestFocus: false,
      skipTraversal: true,
      onKeyEvent: (_, event) => _move(event),
      child: Column(
        children: [
          for (int row = 0; row < _Keypad._layout.length; row++)
            Row(
              children: [
                for (int col = 0; col < _Keypad._layout[row].length; col++)
                  Padding(
                    padding: const EdgeInsets.all(7),
                    child: _button(_Keypad._layout[row][col], _nodes[row][col], autofocus: row == 0 && col == 0),
                  ),
              ],
            ),
        ],
      ),
    );
  }
}

class _KeypadButton extends StatelessWidget {
  final String label;
  final VoidCallback onPressed;
  final bool autofocus;
  final FocusNode? focusNode;

  const _KeypadButton({required this.label, required this.onPressed, this.autofocus = false, this.focusNode});

  @override
  Widget build(BuildContext context) {
    return FocusableTap(
      focusNode: focusNode,
      autofocus: autofocus,
      onPressed: onPressed,
      builder: (context, focused) => AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        width: 56,
        height: 56,
        alignment: Alignment.center,
        decoration: BoxDecoration(shape: BoxShape.circle, color: focused ? _keyFocused : _key),
        child: Text(label, style: TextStyle(color: focused ? Colors.black87 : Colors.white, fontSize: 22)),
      ),
    );
  }
}
