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

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../flauncher_channel.dart';
import '../../models/app.dart';
import '../../providers/apps_service.dart';
import '../../providers/tv_inputs_service.dart';
import 'focusable_settings_tile.dart';
import 'home_assistant_page.dart';
import 'message_dialog.dart';
import 'settings_page.dart';
import 'setup_checklist_page.dart';

/// Remap remote buttons: press a button to pick it, then choose what a press and a hold do.
/// The accessibility service (Home Button Fix) does the remapping; mappings are device-wide.
class RemoteButtonsPage extends StatefulWidget {
  static const String routeName = "remote_buttons";

  const RemoteButtonsPage({super.key});

  @override
  State<RemoteButtonsPage> createState() => _RemoteButtonsPageState();
}

class _RemoteButtonsPageState extends State<RemoteButtonsPage> {
  static const _press = "short";
  static const _hold = "long";
  static const Map<String, dynamic> _searchVoice = {"type": "search", "target": "voice", "label": "Hearth search (voice)"};
  static const Map<String, dynamic> _assistant = {"type": "assistant", "label": "Google Assistant (Gemini)"};

  late final FLauncherChannel _channel = context.read<FLauncherChannel>();
  Map<String, dynamic> _mappings = {};
  final Map<String, String> _names = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final decoded = json.decode(await _channel.getButtonMappings()) as Map<String, dynamic>;
      if (mounted) setState(() => _mappings = decoded);
    } catch (_) {}
  }

  Future<void> _save() async {
    await _channel.setButtonMappings(json.encode(_mappings));
    if (mounted) setState(() {});
  }

  static String buttonName(String? raw, String keyCode) {
    if (raw == null || raw.isEmpty) return "Button $keyCode";
    final words = raw.replaceFirst("KEYCODE_", "").replaceFirst("PROG_", "").replaceFirst("MEDIA_", "").split("_");
    return words.map((w) => w.isEmpty ? w : w[0] + w.substring(1).toLowerCase()).join(" ");
  }

  String _actionLabel(Map<String, dynamic>? action) => action == null ? "Normal" : (action["label"] as String? ?? "?");

  Future<void> _addButton() async {
    Map<dynamic, dynamic>? captured;
    bool cancelled = false;

    final capture = _channel.captureButton().then((value) {
      captured = value;
      if (mounted && !cancelled) Navigator.of(context).pop();
    }).catchError((Object e) {
      captured = {"error": e is PlatformException ? e.message : e.toString()};
      if (mounted && !cancelled) Navigator.of(context).pop();
    });

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) => const AlertDialog(
        title: Text("Press a remote button"),
        content: Text("Press the button you want to remap. Press Back to cancel."),
      ),
    );
    if (captured == null) {
      cancelled = true;
      await _channel.cancelButtonCapture().catchError((_) {});
      return;
    }
    await capture;
    if (!mounted) return;

    final result = captured!;
    if (result.containsKey("error")) {
      showMessageDialog(context,
          title: "Turn on Home Button Fix first",
          message: "Remapping needs Home Button Fix (${SetupChecklistPage.breadcrumb}).");
      return;
    }
    final String keyCode = "${result["keyCode"]}";
    if (result["name"] == "KEYCODE_BACK") return;
    if (result["remappable"] != true) {
      showMessageDialog(context,
          title: "Can't remap that button", message: "The arrows, OK, Back, Home and power keep their normal job.");
      return;
    }
    _names[keyCode] = result["name"] as String;
    await _editButton(keyCode);
  }

  Future<void> _editButton(String keyCode) async {
    final Map<String, dynamic> entry = Map<String, dynamic>.from(_mappings[keyCode] as Map? ?? {});
    final String name = buttonName(_names[keyCode] ?? entry["name"] as String?, keyCode);

    final String? choice = await showDialog<String>(
      context: context,
      builder: (context) => SimpleDialog(
        title: Text(name),
        children: [
          _option(context, "Press: ${_actionLabel(entry[_press] as Map<String, dynamic>?)}", _press),
          _option(context, "Hold: ${_actionLabel(entry[_hold] as Map<String, dynamic>?)}", _hold),
          _option(context, "Tap for Hearth search, hold for Google", "searchPreset"),
          _option(context, "Only on Hearth's home screen: ${entry["homeOnly"] == true ? "On" : "Off"}", "homeOnly"),
          if (_mappings.containsKey(keyCode)) _option(context, "Restore normal button", "remove"),
        ],
      ),
    );
    if (choice == null || !mounted) return;

    if (choice == "remove") {
      _mappings.remove(keyCode);
    } else if (choice == "searchPreset") {
      // The mic button's split: a tap finds something to watch in Hearth, a hold is Google's assistant as before
      entry[_press] = _searchVoice;
      entry[_hold] = _assistant;
      entry["name"] = _names[keyCode] ?? entry["name"];
      _mappings[keyCode] = entry;
    } else if (choice == "homeOnly") {
      // In apps the button keeps its normal job (the mic button opens Google's assistant there)
      entry["homeOnly"] = entry["homeOnly"] != true;
      entry["name"] = _names[keyCode] ?? entry["name"];
      _mappings[keyCode] = entry;
    } else {
      final Map<String, dynamic>? action = await _pickAction();
      if (action == null) return;
      entry[choice] = action;
      entry["name"] = _names[keyCode] ?? entry["name"];
      // A remapped button runs its press on release even when held, so the assistant button would lose Google's
      // assistant entirely: keep it on hold unless a hold was chosen
      final rawName = (entry["name"] as String? ?? "").toUpperCase();
      if (choice == _press &&
          action["type"] == "search" &&
          entry[_hold] == null &&
          (rawName.contains("ASSIST") || rawName.contains("SEARCH") || rawName.contains("VOICE"))) {
        entry[_hold] = _assistant;
      }
      _mappings[keyCode] = entry;
    }
    await _save();
  }

  Future<Map<String, dynamic>?> _pickAction() async {
    final inputs = context.read<TvInputsService>().inputs;
    final String? type = await showDialog<String>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text("Action"),
        children: [
          _option(context, "Open an app…", "app"),
          if (inputs.isNotEmpty) _option(context, "Switch to a TV input…", "input"),
          _option(context, "Home Assistant…", "ha"),
          _option(context, "Switch profile (Google TV)", "profiles"),
          _option(context, "Hearth search (voice)", "search_voice"),
          _option(context, "Hearth search (keyboard)", "search_text"),
          _option(context, "Google Assistant (Gemini)", "assistant"),
          _option(context, "Hearth home", "home"),
          _option(context, "Sleep", "sleep"),
          _option(context, "Android settings", "settings"),
        ],
      ),
    );
    if (type == null || !mounted) return null;

    switch (type) {
      case "app":
        final List<App> apps = context.read<AppsService>().applications.where((a) => !a.hidden).toList()
          ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
        final App? app = await showDialog<App>(
          context: context,
          builder: (context) => SimpleDialog(
            title: const Text("Open an app"),
            children: [for (final app in apps) _option(context, app.name, app)],
          ),
        );
        return app == null ? null : {"type": "app", "target": app.packageName, "label": app.name};
      case "input":
        final input = await showDialog(
          context: context,
          builder: (context) => SimpleDialog(
            title: const Text("Switch to a TV input"),
            children: [for (final input in inputs) _option(context, input.label, input)],
          ),
        );
        return input == null ? null : {"type": "input", "target": input.id, "label": input.label};
      case "ha":
        return _pickHaEntity();
      case "profiles":
        return {"type": "profiles", "label": "Switch profile"};
      case "search_voice":
        return _searchVoice;
      case "search_text":
        return {"type": "search", "target": "text", "label": "Hearth search (keyboard)"};
      case "assistant":
        return _assistant;
      case "home":
        return {"type": "home", "label": "Hearth home"};
      case "sleep":
        return {"type": "sleep", "label": "Sleep"};
      case "settings":
        return {"type": "settings", "label": "Android settings"};
    }
    return null;
  }

  /// Scenes and scripts run; lights, switches and the like toggle. Needs the Home Assistant panel's sign-in.
  Future<Map<String, dynamic>?> _pickHaEntity() async {
    List<dynamic> entities = const [];
    try {
      entities = json.decode(await _channel.getHaEntities()) as List<dynamic>;
    } catch (_) {}
    if (!mounted) return null;
    if (entities.isEmpty) {
      showMessageDialog(context,
          title: "Connect Home Assistant first",
          message: "Set up the Home Assistant panel (${HaPanelPage.breadcrumb} > Set up from your phone), then try again.");
      return null;
    }
    const verbs = {"scene": "Scene", "script": "Run", "button": "Press", "input_button": "Press"};
    String describe(Map e) => "${verbs[e["domain"]] ?? "Toggle"}: ${e["name"]}";
    final Map? picked = await showDialog<Map>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text("Home Assistant"),
        children: [for (final e in entities.cast<Map>()) _option(context, describe(e), e)],
      ),
    );
    return picked == null ? null : {"type": "ha", "target": picked["entity_id"], "label": describe(picked)};
  }

  Widget _option<T>(BuildContext context, String label, T value) => SimpleDialogOption(
        child: Text(label, style: Theme.of(context).textTheme.bodyMedium),
        onPressed: () => Navigator.of(context).pop(value),
      );

  @override
  Widget build(BuildContext context) {
    final keys = _mappings.keys.toList()..sort();
    return SettingsPage(
      title: "Remote buttons",
      children: [
        FocusableSettingsTile(
          autofocus: true,
          leading: const Icon(Icons.add),
          title: Text("Remap a button", style: Theme.of(context).textTheme.bodyMedium),
          onPressed: _addButton,
        ),
        for (final keyCode in keys)
          FocusableSettingsTile(
            leading: const Icon(Icons.settings_remote_outlined),
            title: Text(
              "${buttonName((_mappings[keyCode] as Map)["name"] as String?, keyCode)}\n"
              "Press: ${_actionLabel((_mappings[keyCode] as Map)[_press] as Map<String, dynamic>?)}  ·  "
              "Hold: ${_actionLabel((_mappings[keyCode] as Map)[_hold] as Map<String, dynamic>?)}"
              "${(_mappings[keyCode] as Map)["homeOnly"] == true ? "  ·  Home screen only" : ""}",
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            onPressed: () => _editButton(keyCode),
          ),
        const SizedBox(height: 16),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Text(
            "Needs Home Button Fix (${SetupChecklistPage.breadcrumb}). A button with only a Hold action does that "
            "action on a press too. Hearth search opens HearthTube's own search while HearthTube is in front. "
            "Remaps pause while a kids screen time screen is showing.",
            style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.white54),
            textAlign: TextAlign.center,
          ),
        ),
      ],
    );
  }
}
