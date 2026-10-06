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

  Map<String, dynamic> _mappings = {};
  final Map<String, String> _names = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final decoded = json.decode(await FLauncherChannel().getButtonMappings()) as Map<String, dynamic>;
      if (mounted) setState(() => _mappings = decoded);
    } catch (_) {}
  }

  Future<void> _save() async {
    await FLauncherChannel().setButtonMappings(json.encode(_mappings));
    if (mounted) setState(() {});
  }

  static String buttonName(String? raw, String keyCode) {
    if (raw == null || raw.isEmpty) return "Button $keyCode";
    final words = raw.replaceFirst("KEYCODE_", "").replaceFirst("PROG_", "").replaceFirst("MEDIA_", "").split("_");
    return words.map((w) => w.isEmpty ? w : w[0] + w.substring(1).toLowerCase()).join(" ");
  }

  String _actionLabel(Map<String, dynamic>? action) => action == null ? "Normal" : (action["label"] as String? ?? "?");

  Future<void> _addButton() async {
    final channel = FLauncherChannel();
    Map<dynamic, dynamic>? captured;
    bool cancelled = false;

    final capture = channel.captureButton().then((value) {
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
      await channel.cancelButtonCapture().catchError((_) {});
      return;
    }
    await capture;
    if (!mounted) return;

    final result = captured!;
    if (result.containsKey("error")) {
      _showMessage("Turn on Home Button Fix first", "Remapping needs Settings > Accessibility > Home Button Fix.");
      return;
    }
    final String keyCode = "${result["keyCode"]}";
    if (result["name"] == "KEYCODE_BACK") return;
    if (result["remappable"] != true) {
      _showMessage("Can't remap that button", "The arrows, OK, Back, Home and power keep their normal job.");
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
          if (_mappings.containsKey(keyCode)) _option(context, "Restore normal button", "remove"),
        ],
      ),
    );
    if (choice == null || !mounted) return;

    if (choice == "remove") {
      _mappings.remove(keyCode);
    } else {
      final Map<String, dynamic>? action = await _pickAction();
      if (action == null) return;
      entry[choice] = action;
      entry["name"] = _names[keyCode] ?? entry["name"];
      _mappings[keyCode] = entry;
    }
    await _save();
  }

  Future<Map<String, dynamic>?> _pickAction() async {
    final inputs = context.read<TvInputsService?>()?.inputs ?? const [];
    final String? type = await showDialog<String>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text("Action"),
        children: [
          _option(context, "Open an app…", "app"),
          if (inputs.isNotEmpty) _option(context, "Switch to a TV input…", "input"),
          _option(context, "Home Assistant…", "ha"),
          _option(context, "Switch profile (Google TV)", "profiles"),
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
      entities = json.decode(await FLauncherChannel().getHaEntities()) as List<dynamic>;
    } catch (_) {}
    if (!mounted) return null;
    if (entities.isEmpty) {
      _showMessage("Connect Home Assistant first",
          "Set up the Home Assistant panel (Settings > Home Assistant > Set up from your phone), then try again.");
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

  void _showMessage(String title, String message) {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [TextButton(autofocus: true, onPressed: () => Navigator.of(context).pop(), child: const Text("OK"))],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final keys = _mappings.keys.toList()..sort();
    return Column(
      children: [
        Text("Remote buttons", style: Theme.of(context).textTheme.titleLarge),
        const Divider(),
        Expanded(
          child: SingleChildScrollView(
            child: Column(
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
                      "Hold: ${_actionLabel((_mappings[keyCode] as Map)[_hold] as Map<String, dynamic>?)}",
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    onPressed: () => _editButton(keyCode),
                  ),
                const SizedBox(height: 16),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Text(
                    "Needs Home Button Fix (Settings > Accessibility). A button with only a Hold action does that "
                    "action on a press too. Remaps pause while a kids screen time screen is showing.",
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.white54),
                    textAlign: TextAlign.center,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
