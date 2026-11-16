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
import 'package:provider/provider.dart';

import '../../flauncher_channel.dart';
import '../../l10n/app_localizations.dart';
import '../keyboard/hearth_keyboard.dart';
import '../keyboard/keyboard_choice.dart';
import 'package:flauncher/quiet_failure.dart';

/// Where a search is typed or spoken, over the home: on-screen and voice first. The TV's own on-screen keyboard
/// (Gboard) when it is one; Hearth's own keyboard under the box when the TV's keyboard is a phone's (Google TV's remote
/// bridge, stuck after the phone went away), with "Type on your phone" only while a phone remote is there. The mic
/// next to the box listens with Google's speech recognizer. Submitting hands the text over and closes; Back closes
/// without searching.
class SearchEntry extends StatefulWidget {
  final String initialText;

  /// Start listening for speech right away (the remote's voice search) instead of showing the keyboard.
  final bool voice;
  final ValueChanged<String> onSubmit;
  final VoidCallback onCancel;

  const SearchEntry(
      {super.key, required this.onSubmit, required this.onCancel, this.initialText = "", this.voice = false});

  @override
  State<SearchEntry> createState() => _SearchEntryState();
}

class _SearchEntryState extends State<SearchEntry> {
  late final FLauncherChannel _channel = context.read<FLauncherChannel>();
  late final TextEditingController _text = TextEditingController(text: widget.initialText)
    ..selection = TextSelection(baseOffset: 0, extentOffset: widget.initialText.length);
  late final FocusNode _field = FocusNode(onKeyEvent: (node, event) {
    // OK on the box brings the keyboard back after it was put away
    if (event is KeyDownEvent &&
        (event.logicalKey == LogicalKeyboardKey.select || event.logicalKey == LogicalKeyboardKey.enter)) {
      _showKeyboard(typeOnPhone: _phoneTyping);
      return KeyEventResult.handled;
    }
    // Back comes as Android's Back, which the home hands to the search (HomeSearch.backHandler): not handled here,
    // or one press would close the box and then the home too
    return KeyEventResult.ignored;
  });
  bool _listening = false;

  /// Hearth's keyboard shows under the box (the TV's keyboard isn't an on-screen one).
  bool _hearthKeys = false;

  /// The TV's keyboard as last read: whether it's a phone's, and whether a phone remote is there.
  KeyboardStatus _status = KeyboardStatus.unknown;

  /// "Type on your phone" was chosen: the box has the TV's keyboard, which goes to the phone.
  bool _phoneTyping = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => widget.voice ? _listen() : _showKeyboard());
  }

  @override
  void dispose() {
    _text.dispose();
    _field.dispose();
    super.dispose();
  }

  /// The keyboard for the box: the TV's when it's on screen (put back first when Hearth may and no phone is there),
  /// else Hearth's own. [typeOnPhone]: the TV's keyboard on purpose, to type on the phone.
  Future<void> _showKeyboard({bool typeOnPhone = false}) async {
    if (!mounted) return;
    if (typeOnPhone) {
      _systemKeyboard();
      return;
    }
    final choice = await chooseKeyboard(_channel);
    if (!mounted) return;
    // OK on the box with Hearth's keys already under it: back down to them
    if (_hearthKeys && choice.way == KeyboardWay.hearth) {
      setState(() => _status = choice.status);
      _field.focusInDirection(TraversalDirection.down);
      return;
    }
    setState(() {
      _status = choice.status;
      _phoneTyping = false;
      _hearthKeys = choice.way == KeyboardWay.hearth;
    });
    switch (choice.way) {
      case KeyboardWay.hearth:
        SystemChannels.textInput.invokeMethod("TextInput.hide");
      case KeyboardWay.systemAfterSwitch:
        // The box may hold the old keyboard's connection: let go, give Android a moment, then ask again
        _field.unfocus();
        await Future<void>.delayed(KeyboardChoice.switchSettle);
        _systemKeyboard();
      case KeyboardWay.system:
        _systemKeyboard();
    }
  }

  void _systemKeyboard() {
    if (!mounted) return;
    _field.requestFocus();
    SystemChannels.textInput.invokeMethod("TextInput.show");
  }

  /// "Type on your phone": the box takes the TV's keyboard, which sends the typing to the phone. Hearth's keys stay
  /// under it; Down goes back to them.
  void _typeOnPhone() {
    setState(() => _phoneTyping = true);
    WidgetsBinding.instance.addPostFrameCallback((_) => _systemKeyboard());
  }

  Future<void> _listen() async {
    if (_listening) return;
    setState(() => _listening = true);
    String? said;
    try {
      said = await _channel.voiceSearch();
    } catch (err) { noteFailure('search_entry', err); }
    if (!mounted) return;
    setState(() => _listening = false);
    if (said != null && said.trim().isNotEmpty) {
      widget.onSubmit(said.trim());
    } else if (!_hearthKeys) {
      _showKeyboard();
    }
  }

  void _submit(String text) {
    if (text.trim().length < 2) return;
    SystemChannels.textInput.invokeMethod("TextInput.hide");
    widget.onSubmit(text.trim());
  }

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    final textTheme = Theme.of(context).textTheme;
    final localizations = AppLocalizations.of(context)!;
    final help = _hearthKeys && _status.phone
        ? "${localizations.searchEntryHelp} ${localizations.searchEntryPhoneHelp}"
        : localizations.searchEntryHelp;
    final helpStyle = textTheme.bodyMedium?.copyWith(
        color: Colors.white70, shadows: [const Shadow(color: Colors.black87, offset: Offset(1, 1), blurRadius: 6)]);
    // Its own scope: while it's open the arrows stay between the box, the mic and Hearth's keys, never the home
    return FocusScope(
      child: Align(
      alignment: Alignment.topCenter,
      child: Padding(
        padding: const EdgeInsets.only(top: 96),
        child: SizedBox(
          width: 860,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Expanded(
                  child: Material(
                    color: Colors.transparent,
                    child: TextField(
                      controller: _text,
                      focusNode: _field,
                      // With Hearth's keys the box only shows the text (the keys type into it), unless the phone types
                      readOnly: _hearthKeys && !_phoneTyping,
                      showCursor: true,
                      textInputAction: TextInputAction.search,
                      onSubmitted: _submit,
                      style: textTheme.headlineSmall,
                      decoration: InputDecoration(
                        hintText: _listening ? localizations.searchListening : localizations.searchHint,
                        prefixIcon: const Icon(Icons.search),
                        filled: true,
                        fillColor: const Color(0xEE1E2026),
                        enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(30),
                            borderSide: const BorderSide(color: Colors.transparent, width: 2)),
                        focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(30), borderSide: BorderSide(color: accent, width: 2)),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                // Voice first, next to the box: Google's speech recognizer, whatever the keyboard
                Material(
                  color: const Color(0xEE1E2026),
                  shape: const CircleBorder(),
                  child: IconButton(
                    key: const ValueKey("searchMic"),
                    tooltip: localizations.searchMic,
                    iconSize: 30,
                    padding: const EdgeInsets.all(12),
                    focusColor: accent.withValues(alpha: 0.6),
                    icon: Icon(_listening ? Icons.mic : Icons.mic_none),
                    onPressed: _listen,
                  ),
                ),
              ]),
              const SizedBox(height: 10),
              Padding(
                padding: const EdgeInsets.only(left: 74),
                child: Text(help, style: helpStyle),
              ),
              if (_hearthKeys) ...[
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(color: const Color(0xF2202228), borderRadius: BorderRadius.circular(20)),
                  child: HearthKeyboard(
                    controller: _text,
                    autofocus: !_phoneTyping,
                    actionLabel: localizations.keyboardSearch,
                    onAction: () => _submit(_text.text),
                    onVoice: _listen,
                    onPhone: _status.phone ? _typeOnPhone : null,
                    onTvKeyboards: () => _channel.showKeyboardPicker(),
                  ),
                ),
                if (_status.kind == "phone") ...[
                  const SizedBox(height: 8),
                  Padding(
                    padding: const EdgeInsets.only(left: 12),
                    child: Text(localizations.keyboardPhoneStuck, style: helpStyle?.copyWith(color: Colors.white54)),
                  ),
                ],
              ],
            ],
          ),
        ),
      ),
    ),
    );
  }
}
