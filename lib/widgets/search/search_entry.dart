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

/// Where a search is typed or spoken, over the home: Google's own on-screen keyboard (also what a phone's Google
/// TV app or a paired keyboard types into) and the mic for Google's speech recognizer. Submitting hands the text
/// over and closes; Back closes without searching.
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
      _showKeyboard();
      return KeyEventResult.handled;
    }
    // Back comes as Android's Back, which the home hands to the search (HomeSearch.backHandler): not handled here,
    // or one press would close the box and then the home too
    return KeyEventResult.ignored;
  });
  bool _listening = false;

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

  void _showKeyboard() {
    if (!mounted) return;
    _field.requestFocus();
    SystemChannels.textInput.invokeMethod("TextInput.show");
  }

  Future<void> _listen() async {
    if (_listening) return;
    setState(() => _listening = true);
    String? said;
    try {
      said = await _channel.voiceSearch();
    } catch (_) {}
    if (!mounted) return;
    setState(() => _listening = false);
    if (said != null && said.trim().isNotEmpty) {
      widget.onSubmit(said.trim());
    } else {
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
    // Its own scope: while it's open the arrows stay between the mic and the box, never the home underneath
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
              // No mic button of its own: the keyboard has one, and the remote's voice search starts listening
              Row(children: [
                Expanded(
                  child: Material(
                    color: Colors.transparent,
                    child: TextField(
                      controller: _text,
                      focusNode: _field,
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
              ]),
              const SizedBox(height: 10),
              Padding(
                padding: const EdgeInsets.only(left: 74),
                child: Text(
                  localizations.searchEntryHelp,
                  style: textTheme.bodyMedium?.copyWith(
                      color: Colors.white70,
                      shadows: [const Shadow(color: Colors.black87, offset: Offset(1, 1), blurRadius: 6)]),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
    );
  }
}
