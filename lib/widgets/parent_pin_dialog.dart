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

import 'dart:async';
import 'dart:math';

import 'package:flauncher/l10n/app_localizations.dart';
import 'package:flauncher/quiet_failure.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../flauncher_channel.dart';
import '../providers/profile_service.dart';
import '../providers/settings_service.dart';
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
  final l = AppLocalizations.of(context)!;
  if (!settings.hasParentPin) {
    await showMessageDialog(context,
        title: l.parentPinAskTitle,
        message: l.parentPinAskBody(l.settingsTitle, l.familyTitle, l.parentPinTitle));
    return false;
  }

  final String? pin = await showDialog<String>(
    context: context,
    builder: (_) => ParentPinDialog(
      title: l.parentPinTitle,
      subtitle: l.parentPinKidsSubtitle,
      verify: settings.verifyParentPin,
      phone: context.read<FLauncherChannel?>(),
    ),
  );
  return pin != null;
}

/// The parent PIN in any profile, for what only a parent may do anywhere (saving a streaming app's profile PIN, or
/// changing a pairing that has one).
/// In an adult's profile it isn't asked while they're at the remote: since their profile came on (or they entered
/// the PIN), the remote hasn't gone untouched for five minutes. Without a parent PIN set, says to set one first.
/// Returns true when the caller may go ahead.
Future<bool> requireParentPin(BuildContext context) async {
  final settings = context.read<SettingsService>();
  final channel = context.read<FLauncherChannel?>();
  final bool kids = context.read<ProfileService?>()?.isKidsProfile ?? false;
  final l = AppLocalizations.of(context)!;
  if (!kids && channel != null && await _parentPresent(channel)) return true;
  if (!context.mounted) return false;
  if (!settings.hasParentPin) {
    await showMessageDialog(context,
        title: l.parentPinTitle,
        message: l.profilePinNeedsParentPin(l.settingsTitle, l.familyTitle, l.parentPinTitle));
    return false;
  }
  final String? pin = await showDialog<String>(
    context: context,
    builder: (_) => ParentPinDialog(title: l.parentPinTitle, verify: settings.verifyParentPin, phone: channel),
  );
  if (pin != null && !kids && channel != null) {
    try {
      await channel.parentConfirmed();
    } catch (err) { noteFailure('parent_pin_dialog', err); }
  }
  return pin != null;
}

/// Whether an adult is at the remote (see [requireParentPin]); not when Hearth can't tell.
Future<bool> _parentPresent(FLauncherChannel channel) async {
  try {
    return await channel.isParentPresent();
  } catch (err) {
      noteFailure('parent_pin_dialog', err);
    return false;
  }
}

/// Asks for a new parent PIN twice (the second time must match) and saves it: from Settings, and from the setup
/// flow. Returns whether one was set; Back at either step leaves things as they were.
Future<bool> chooseNewParentPin(BuildContext context) async {
  final l = AppLocalizations.of(context)!;
  final settings = context.read<SettingsService>();
  final first = await showDialog<String>(
    context: context,
    builder: (_) => ParentPinDialog(title: l.parentPinNew, subtitle: l.parentPinNewSubtitle),
  );
  if (first == null || !context.mounted) return false;
  final second = await showDialog<String>(
    context: context,
    builder: (_) => ParentPinDialog(title: l.parentPinConfirm, verify: (pin) => pin == first),
  );
  if (second == null) return false;
  await settings.setParentPin(first);
  return true;
}

/// Full-screen PIN entry in Google TV's style: the shuffled row pad (see [_RowPad]), number keys type directly.
/// Pops with the entered PIN, or null on Back.
/// Repeated wrong guesses lock a PIN pad for a while: after [freeTries] misses in a row it waits [baseSeconds], and
/// each miss after that doubles the wait (up to [maxSeconds]). A right PIN clears it. Shared by every pad that checks
/// a PIN, so closing and reopening the dialog doesn't give the tries back.
class PinLockout {
  static const int freeTries = 5;
  static const int baseSeconds = 30;
  static const int maxSeconds = 300;

  static final PinLockout shared = PinLockout();

  int _misses = 0;
  DateTime? _until;

  bool lockedAt(DateTime now) => _until != null && now.isBefore(_until!);

  int secondsLeft(DateTime now) => lockedAt(now) ? _until!.difference(now).inSeconds + 1 : 0;

  void miss(DateTime now) {
    _misses++;
    if (_misses < freeTries) return;
    final seconds = (baseSeconds * (1 << (_misses - freeTries))).clamp(baseSeconds, maxSeconds);
    _until = now.add(Duration(seconds: seconds));
  }

  void clear() {
    _misses = 0;
    _until = null;
  }
}

class ParentPinDialog extends StatefulWidget {
  final String title;
  final String? subtitle;
  final bool Function(String pin)? verify;
  static const int digitCount = 4;

  /// How many digits the PIN has ([digitCount] for Hearth's own; a streaming app's may differ).
  final int length;

  /// The pad's shuffle (tests pass a seeded one); a secure random by default.
  final Random? random;

  /// Where wrong guesses are counted (tests pass their own).
  final PinLockout? lockout;

  /// Set where this asks for the Parent PIN: a parent's phone may allow it instead, and the dialog closes as if the
  /// PIN had been entered (see ParentApproval). Left null for every other pad (new PINs, streaming apps' PINs).
  final FLauncherChannel? phone;

  const ParentPinDialog(
      {super.key,
      required this.title,
      this.subtitle,
      this.verify,
      this.random,
      this.lockout,
      this.phone,
      this.length = digitCount});

  @override
  State<ParentPinDialog> createState() => _ParentPinDialogState();
}

class _ParentPinDialogState extends State<ParentPinDialog> {
  String _entered = "";
  bool _error = false;
  Timer? _tick;
  Timer? _phoneTimer;
  // Whether a parent's phone was asked, and whether it said no
  bool _phoneAsked = false;
  bool _phoneDenied = false;

  PinLockout get _lockout => widget.lockout ?? PinLockout.shared;

  bool get _locked => widget.verify != null && _lockout.lockedAt(DateTime.now());

  @override
  void initState() {
    super.initState();
    final phone = widget.phone;
    if (phone != null && widget.verify != null) _askPhone(phone);
  }

  @override
  void dispose() {
    _tick?.cancel();
    _phoneTimer?.cancel();
    if (widget.phone != null && _phoneAsked) widget.phone!.cancelParentApproval();
    super.dispose();
  }

  Future<void> _askPhone(FLauncherChannel phone) async {
    final asked = await phone.startParentApproval();
    if (!mounted) {
      if (asked > 0) phone.cancelParentApproval();
      return;
    }
    if (asked <= 0) return;
    setState(() => _phoneAsked = true);
    _phoneTimer = Timer.periodic(const Duration(seconds: 1), (timer) async {
      final state = await phone.pollParentApproval();
      if (!mounted) return timer.cancel();
      if (state == "allowed") {
        timer.cancel();
        _phoneAsked = false;
        Navigator.of(context).pop("");
      } else if (state == "denied") {
        timer.cancel();
        setState(() => _phoneDenied = true);
      } else if (state != "pending") {
        timer.cancel();
        setState(() => _phoneAsked = false);
      }
    });
  }

  void _lock() {
    _tick?.cancel();
    _tick = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) return timer.cancel();
      setState(() {});
      if (!_locked) timer.cancel();
    });
  }

  void _onDigit(String digit) {
    if (_locked || _entered.length >= widget.length) return;
    setState(() {
      _entered += digit;
      _error = false;
    });
    if (_entered.length < widget.length) return;

    if (widget.verify == null || widget.verify!(_entered)) {
      if (widget.verify != null) _lockout.clear();
      Navigator.of(context).pop(_entered);
      return;
    }
    _lockout.miss(DateTime.now());
    if (_locked) _lock();
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
    final l = AppLocalizations.of(context)!;
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
                    if (_phoneAsked || _phoneDenied) ...[
                      const SizedBox(height: 16),
                      Text(_phoneDenied ? l.parentPinPhoneDenied : l.parentPinPhoneAsked,
                          style: const TextStyle(color: _textDim, fontSize: 15)),
                    ],
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                      _locked
                          ? l.parentPinLocked(_lockout.secondsLeft(DateTime.now()))
                          : _error
                              ? l.parentPinWrong
                              : l.parentPinEnter,
                      style: TextStyle(
                          color: _error || _locked ? const Color(0xFFF2B8B5) : _textDim,
                          fontSize: 12,
                          letterSpacing: 2)),
                  const SizedBox(height: 16),
                  Row(
                    children: List.generate(widget.length, (i) {
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
                  _RowPad(onDigit: _onDigit, onBackspace: _onBackspace, random: widget.random),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The PIN pad: four pill rows of three digits, shuffled every time it opens (two of the twelve places are empty).
/// Up and Down pick a row; Left, OK and Right enter its first, middle or last digit. The highlight covers the whole
/// row, so someone watching the screen learns only that the digit was one of three, and a different three each time.
class _RowPad extends StatefulWidget {
  final void Function(String) onDigit;
  final VoidCallback onBackspace;
  final Random? random;

  const _RowPad({required this.onDigit, required this.onBackspace, this.random});

  static const int rows = 4;
  static const int perRow = 3;

  @override
  State<_RowPad> createState() => _RowPadState();
}

class _RowPadState extends State<_RowPad> {
  /// rows x perRow places, each a digit or "" (empty)
  late final List<List<String>> _layout = _shuffled(widget.random ?? Random.secure());
  late final List<FocusNode> _rowNodes = List.generate(_RowPad.rows, (_) => FocusNode());
  final FocusNode _backspaceNode = FocusNode();

  static List<List<String>> _shuffled(Random random) {
    final places = [for (int d = 0; d <= 9; d++) "$d", "", ""]..shuffle(random);
    return [for (int r = 0; r < _RowPad.rows; r++) places.sublist(r * _RowPad.perRow, (r + 1) * _RowPad.perRow)];
  }

  @override
  void dispose() {
    for (final node in _rowNodes) {
      node.dispose();
    }
    _backspaceNode.dispose();
    super.dispose();
  }

  void _enter(int row, int place) {
    final digit = _layout[row][place];
    if (digit.isNotEmpty) widget.onDigit(digit);
  }

  /// Keys on a row: Left/OK/Right enter a digit, Up/Down move between rows (and down to ⌫); it never lets the
  /// selection leave the pad.
  KeyEventResult _onRowKey(int row, KeyEvent event) {
    if (event is KeyUpEvent) return KeyEventResult.handled;
    final key = event.logicalKey;
    if (event is KeyRepeatEvent && key != LogicalKeyboardKey.arrowUp && key != LogicalKeyboardKey.arrowDown) {
      return KeyEventResult.handled; // a held OK or arrow doesn't enter the same digit again and again
    }
    if (key == LogicalKeyboardKey.arrowLeft) {
      _enter(row, 0);
    } else if (key == LogicalKeyboardKey.select || key == LogicalKeyboardKey.enter || key == LogicalKeyboardKey.gameButtonA) {
      _enter(row, 1);
    } else if (key == LogicalKeyboardKey.arrowRight) {
      _enter(row, 2);
    } else if (key == LogicalKeyboardKey.arrowUp) {
      if (row > 0) _rowNodes[row - 1].requestFocus();
    } else if (key == LogicalKeyboardKey.arrowDown) {
      (row < _RowPad.rows - 1 ? _rowNodes[row + 1] : _backspaceNode).requestFocus();
    } else {
      return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
  }

  KeyEventResult _onBackspaceKey(KeyEvent event) {
    if (event is! KeyDownEvent) return event is KeyRepeatEvent ? KeyEventResult.handled : KeyEventResult.ignored;
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.select || key == LogicalKeyboardKey.enter || key == LogicalKeyboardKey.gameButtonA) {
      widget.onBackspace();
    } else if (key == LogicalKeyboardKey.arrowUp) {
      _rowNodes.last.requestFocus();
    } else if (key != LogicalKeyboardKey.arrowDown && key != LogicalKeyboardKey.arrowLeft && key != LogicalKeyboardKey.arrowRight) {
      return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        for (int row = 0; row < _RowPad.rows; row++)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Focus(
              focusNode: _rowNodes[row],
              autofocus: row == 0,
              onKeyEvent: (_, event) => _onRowKey(row, event),
              child: Builder(builder: (context) {
                final focused = Focus.of(context).hasFocus;
                return AnimatedContainer(
                  duration: const Duration(milliseconds: 120),
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: focused ? _keyFocused : _key,
                    borderRadius: BorderRadius.circular(32),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // The arrows say which button enters which digit; they don't change with the digit pressed
                      Icon(Icons.chevron_left, size: 22, color: focused ? Colors.black54 : Colors.transparent),
                      for (int place = 0; place < _RowPad.perRow; place++)
                        GestureDetector(
                          onTap: () => _enter(row, place),
                          child: SizedBox(
                            width: 48,
                            height: 44,
                            child: Center(
                              child: Text(_layout[row][place],
                                  style: TextStyle(color: focused ? Colors.black87 : Colors.white, fontSize: 24)),
                            ),
                          ),
                        ),
                      Icon(Icons.chevron_right, size: 22, color: focused ? Colors.black54 : Colors.transparent),
                    ],
                  ),
                );
              }),
            ),
          ),
        const SizedBox(height: 8),
        Focus(
          focusNode: _backspaceNode,
          onKeyEvent: (_, event) => _onBackspaceKey(event),
          child: Builder(builder: (context) {
            final focused = Focus.of(context).hasFocus;
            return GestureDetector(
              onTap: widget.onBackspace,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 120),
                width: 72,
                height: 44,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: focused ? _keyFocused : _key,
                  borderRadius: BorderRadius.circular(22),
                ),
                child: Icon(Icons.backspace_outlined, color: focused ? Colors.black87 : Colors.white, size: 20),
              ),
            );
          }),
        ),
      ],
    );
  }
}
