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
import 'package:flauncher/quiet_failure.dart';
import 'package:flutter/material.dart';

import 'keyboard_choice.dart';

/// Hearth's own on-screen keyboard, for when the TV's keyboard isn't one (Google TV's phone keyboard, stuck after the
/// phone went away): keys the remote moves over, the mic, and the phone only while one is there. It types straight
/// into [controller].
class HearthKeyboard extends StatefulWidget {
  final TextEditingController controller;

  /// Digits only (a PIN, a number).
  final bool numeric;

  /// The last key's label (Search, Done, Next) and what it does.
  final String actionLabel;
  final VoidCallback onAction;

  /// The mic key; none when null (a hidden field, digits).
  final VoidCallback? onVoice;

  /// "Type on your phone"; only given while a phone remote is there.
  final VoidCallback? onPhone;

  /// Android's keyboard chooser; none when null.
  final VoidCallback? onTvKeyboards;

  /// Focus starts on the keys.
  final bool autofocus;

  const HearthKeyboard({
    super.key,
    required this.controller,
    required this.actionLabel,
    required this.onAction,
    this.numeric = false,
    this.onVoice,
    this.onPhone,
    this.onTvKeyboards,
    this.autofocus = true,
  });

  static const List<String> letterRows = ["1234567890", "qwertyuiop", "asdfghjkl'", "zxcvbnm,.-"];
  static const List<String> symbolRows = ["1234567890", "@#\$%&*()/:", "_+=!?;\"~<>", "[]{}|\\^`.,"];
  static const List<String> digitRows = ["123", "456", "789"];

  @override
  State<HearthKeyboard> createState() => _HearthKeyboardState();
}

class _HearthKeyboardState extends State<HearthKeyboard> {
  bool _symbols = false;
  bool _shift = false;

  void _insert(String text) {
    final value = widget.controller.value;
    final at = value.selection.isValid ? value.selection : TextSelection.collapsed(offset: value.text.length);
    final typed = _shift ? text.toUpperCase() : text;
    widget.controller.value = TextEditingValue(
      text: value.text.replaceRange(at.start, at.end, typed),
      selection: TextSelection.collapsed(offset: at.start + typed.length),
    );
    if (_shift) setState(() => _shift = false);
  }

  void _delete() {
    final value = widget.controller.value;
    final at = value.selection.isValid ? value.selection : TextSelection.collapsed(offset: value.text.length);
    if (!at.isCollapsed) {
      widget.controller.value = TextEditingValue(
          text: value.text.replaceRange(at.start, at.end, ""), selection: TextSelection.collapsed(offset: at.start));
    } else if (at.start > 0) {
      widget.controller.value = TextEditingValue(
          text: value.text.replaceRange(at.start - 1, at.start, ""),
          selection: TextSelection.collapsed(offset: at.start - 1));
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final rows = widget.numeric
        ? HearthKeyboard.digitRows
        : (_symbols ? HearthKeyboard.symbolRows : HearthKeyboard.letterRows);
    Widget char(String c, {bool autofocus = false}) => _Key(
          label: !_symbols && _shift ? c.toUpperCase() : c,
          autofocus: autofocus,
          onPressed: () => _insert(c),
        );

    // Focus starts on the first letter (q), or on 1 for digits
    final startRow = widget.numeric ? 0 : 1;
    final keyRows = [
      for (final (i, row) in rows.indexed)
        Row(children: [
          for (final (j, c) in row.split("").indexed)
            char(c, autofocus: widget.autofocus && i == startRow && j == 0)
        ])
    ];
    final List<Widget> bottom = widget.numeric
        ? [
            _Key(icon: Icons.backspace_outlined, semantics: l.keyboardDelete, onPressed: _delete),
            char("0"),
            _Key(label: widget.actionLabel, accent: true, onPressed: widget.onAction),
          ]
        : [
            if (!_symbols)
              _Key(
                icon: _shift ? Icons.keyboard_capslock : Icons.keyboard_arrow_up,
                semantics: l.keyboardShift,
                selected: _shift,
                onPressed: () => setState(() => _shift = !_shift),
              ),
            // Keyed: it keeps focus as the shift key comes and goes
            _Key(
              key: const ValueKey("symbols"),
              label: _symbols ? l.keyboardLetters : l.keyboardSymbols,
              onPressed: () => setState(() {
                _symbols = !_symbols;
                _shift = false;
              }),
            ),
            _Key(key: const ValueKey("space"), label: l.keyboardSpace, flex: 3, onPressed: () => _insert(" ")),
            _Key(
              key: const ValueKey("delete"),
              icon: Icons.backspace_outlined,
              semantics: l.keyboardDelete,
              onPressed: _delete,
            ),
            if (widget.onVoice != null)
              _Key(key: const ValueKey("mic"), icon: Icons.mic, semantics: l.keyboardMic, onPressed: widget.onVoice!),
            if (widget.onTvKeyboards != null)
              _Key(
                key: const ValueKey("tvKeyboards"),
                icon: Icons.keyboard_alt_outlined,
                semantics: l.keyboardTvKeyboards,
                onPressed: widget.onTvKeyboards!,
              ),
            _Key(
              key: const ValueKey("action"),
              label: widget.actionLabel,
              accent: true,
              flex: 2,
              onPressed: widget.onAction,
            ),
          ];

    return FocusTraversalGroup(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ...keyRows,
          Row(children: bottom),
          if (widget.onPhone != null)
            Row(children: [_Key(icon: Icons.smartphone, label: l.keyboardPhone, onPressed: widget.onPhone!)]),
        ],
      ),
    );
  }
}

class _Key extends StatefulWidget {
  final String? label;
  final IconData? icon;
  final String? semantics;
  final int flex;
  final bool autofocus;
  final bool accent;
  final bool selected;
  final VoidCallback onPressed;

  const _Key({
    super.key,
    this.label,
    this.icon,
    this.semantics,
    this.flex = 1,
    this.autofocus = false,
    this.accent = false,
    this.selected = false,
    required this.onPressed,
  });

  @override
  State<_Key> createState() => _KeyState();
}

class _KeyState extends State<_Key> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    final Color fill = _focused
        ? Colors.white
        : widget.accent || widget.selected
            ? accent.withValues(alpha: 0.55)
            : Colors.white.withValues(alpha: 0.12);
    final Color ink = _focused ? Colors.black : Colors.white;
    final label = widget.label;
    final icon = widget.icon;
    return Expanded(
      flex: widget.flex,
      child: Padding(
        padding: const EdgeInsets.all(3),
        child: Semantics(
          button: true,
          label: widget.semantics ?? label,
          excludeSemantics: true,
          child: Material(
            color: fill,
            borderRadius: BorderRadius.circular(8),
            child: InkWell(
              autofocus: widget.autofocus,
              borderRadius: BorderRadius.circular(8),
              onFocusChange: (focused) => setState(() => _focused = focused),
              onTap: widget.onPressed,
              child: SizedBox(
                height: 44,
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (icon != null) Icon(icon, size: 22, color: ink),
                      if (icon != null && label != null) const SizedBox(width: 8),
                      if (label != null)
                        Text(label, style: TextStyle(color: ink, fontSize: 18, fontWeight: FontWeight.w500)),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// How [showHearthKeyboardSheet] was left.
enum HearthKeyboardResult {
  /// The action key (Done, Next, Search).
  action,

  /// "Type on your phone": the field asks the TV's keyboard, which goes to the phone.
  phone,
}

/// Hearth's keyboard over the page for one field ([label], what it holds now), typing into [controller]; null when
/// Back closed it (what was typed stays). [status] says whether a phone is there and why the TV's keyboard wasn't used.
Future<HearthKeyboardResult?> showHearthKeyboardSheet(
  BuildContext context, {
  required TextEditingController controller,
  required KeyboardStatus status,
  FLauncherChannel? channel,
  String? label,
  bool obscure = false,
  bool numeric = false,
  String? actionLabel,
}) {
  final l = AppLocalizations.of(context)!;
  return showDialog<HearthKeyboardResult>(
    context: context,
    barrierColor: Colors.black54,
    builder: (dialogContext) {
      Future<void> listen() async {
        try {
          final said = await channel?.voiceSearch();
          if (said != null && said.trim().isNotEmpty) {
            final text = controller.text;
            final joined = text.isEmpty || text.endsWith(" ") ? "$text${said.trim()}" : "$text ${said.trim()}";
            controller.value =
                TextEditingValue(text: joined, selection: TextSelection.collapsed(offset: joined.length));
          }
        } catch (err) {
          noteFailure('hearth_keyboard', err);
        }
      }

      final textTheme = Theme.of(dialogContext).textTheme;
      return Align(
        alignment: Alignment.bottomCenter,
        child: Padding(
          padding: const EdgeInsets.only(bottom: 24),
          child: Material(
            color: const Color(0xF2202228),
            borderRadius: BorderRadius.circular(20),
            child: SizedBox(
              width: numeric ? 420 : 900,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (label != null) Text(label, style: textTheme.labelLarge?.copyWith(color: Colors.white70)),
                    const SizedBox(height: 6),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      decoration: BoxDecoration(color: Colors.black26, borderRadius: BorderRadius.circular(10)),
                      child: ValueListenableBuilder<TextEditingValue>(
                        valueListenable: controller,
                        builder: (context, value, _) => Text(
                          obscure ? "•" * value.text.length : value.text,
                          key: const ValueKey("hearthKeyboardPreview"),
                          style: textTheme.titleLarge,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                    if (status.kind == "phone") ...[
                      const SizedBox(height: 6),
                      Text(l.keyboardPhoneStuck, style: textTheme.bodySmall?.copyWith(color: Colors.white54)),
                    ],
                    const SizedBox(height: 10),
                    HearthKeyboard(
                      controller: controller,
                      numeric: numeric,
                      actionLabel: actionLabel ?? l.done,
                      onAction: () => Navigator.of(dialogContext).pop(HearthKeyboardResult.action),
                      onVoice: channel != null && !obscure && !numeric ? listen : null,
                      onPhone: status.phone ? () => Navigator.of(dialogContext).pop(HearthKeyboardResult.phone) : null,
                      onTvKeyboards: channel != null && !numeric ? () => channel.showKeyboardPicker() : null,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    },
  );
}
