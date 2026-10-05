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
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Ask a parent"),
        content: const Text(
            "Launcher settings are locked in kids profiles. A parent can set a PIN in Settings → Parent PIN from their own profile."),
        actions: [TextButton(autofocus: true, onPressed: () => Navigator.of(context).pop(), child: const Text("OK"))],
      ),
    );
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
    final String? label = event.logicalKey.keyLabel;
    if (label != null && label.length == 1 && RegExp(r'[0-9]').hasMatch(label)) {
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

class _Keypad extends StatelessWidget {
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
  Widget build(BuildContext context) {
    return FocusTraversalGroup(
      policy: ReadingOrderTraversalPolicy(),
      child: Column(
        children: [
          for (int row = 0; row < _layout.length; row++)
            Row(
              children: [
                for (int col = 0; col < 3; col++)
                  Padding(
                    padding: const EdgeInsets.all(7),
                    child: _layout[row][col].isEmpty
                        ? const SizedBox(width: 56, height: 56)
                        : _KeypadButton(
                            label: _layout[row][col],
                            autofocus: row == 0 && col == 0,
                            onPressed: () =>
                                _layout[row][col] == "⌫" ? onBackspace() : onDigit(_layout[row][col]),
                          ),
                  ),
              ],
            ),
        ],
      ),
    );
  }
}

class _KeypadButton extends StatefulWidget {
  final String label;
  final VoidCallback onPressed;
  final bool autofocus;

  const _KeypadButton({required this.label, required this.onPressed, this.autofocus = false});

  @override
  State<_KeypadButton> createState() => _KeypadButtonState();
}

class _KeypadButtonState extends State<_KeypadButton> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    return Actions(
      actions: <Type, Action<Intent>>{
        ActivateIntent: CallbackAction<ActivateIntent>(onInvoke: (_) => widget.onPressed()),
        ButtonActivateIntent: CallbackAction<ButtonActivateIntent>(onInvoke: (_) => widget.onPressed()),
      },
      child: Focus(
        autofocus: widget.autofocus,
        onFocusChange: (focused) => setState(() => _focused = focused),
        child: GestureDetector(
          onTap: widget.onPressed,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            width: 56,
            height: 56,
            alignment: Alignment.center,
            decoration: BoxDecoration(shape: BoxShape.circle, color: _focused ? _keyFocused : _key),
            child: Text(widget.label,
                style: TextStyle(color: _focused ? Colors.black87 : Colors.white, fontSize: 22)),
          ),
        ),
      ),
    );
  }
}
