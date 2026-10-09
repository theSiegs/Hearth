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

import 'package:flauncher/l10n/app_localizations.dart';
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
  // The labels saved with Hearth's own actions are a fallback: the page names those actions from their type, in the
  // current language (see _actionLabel).
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

  static String buttonName(String? raw, String keyCode, AppLocalizations l) {
    if (raw == null || raw.isEmpty) return l.remoteButtonsButtonNumber(keyCode);
    final words = raw.replaceFirst("KEYCODE_", "").replaceFirst("PROG_", "").replaceFirst("MEDIA_", "").split("_");
    return words.map((w) => w.isEmpty ? w : w[0] + w.substring(1).toLowerCase()).join(" ");
  }

  /// What a press or a hold does, in words. Hearth's own actions are named in the current language; an app, a TV
  /// input, a Home Assistant entity or the assistant shows the label saved with it.
  String _actionLabel(AppLocalizations l, Map<String, dynamic>? action) {
    if (action == null) return l.remoteButtonsNormal;
    return switch (action["type"]) {
      "profiles" => l.profilesSwitchProfile,
      "search" when action["target"] == "voice" => l.remoteButtonsActionSearchVoice,
      "search" when action["target"] == "text" => l.remoteButtonsActionSearchKeyboard,
      "home" => l.remoteButtonsActionHome,
      "sleep" => l.remoteButtonsActionSleep,
      "lock" => l.profileLockNow,
      "settings" => l.remoteButtonsActionAndroidSettings,
      _ => action["label"] as String? ?? "?",
    };
  }

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
      builder: (context) => AlertDialog(
        title: Text(AppLocalizations.of(context)!.remoteButtonsCaptureTitle),
        content: Text(AppLocalizations.of(context)!.remoteButtonsCaptureBody),
      ),
    );
    if (captured == null) {
      cancelled = true;
      await _channel.cancelButtonCapture().catchError((_) {});
      return;
    }
    await capture;
    if (!mounted) return;

    final l = AppLocalizations.of(context)!;
    final result = captured!;
    if (result.containsKey("error")) {
      showMessageDialog(context,
          title: l.remoteButtonsNeedsFixTitle, message: l.remoteButtonsNeedsFixBody(SetupChecklistPage.breadcrumb(l)));
      return;
    }
    final String keyCode = "${result["keyCode"]}";
    if (result["name"] == "KEYCODE_BACK") return;
    if (result["remappable"] != true) {
      showMessageDialog(context, title: l.remoteButtonsCantRemapTitle, message: l.remoteButtonsCantRemapBody);
      return;
    }
    _names[keyCode] = result["name"] as String;
    await _editButton(keyCode);
  }

  Future<void> _editButton(String keyCode) async {
    final l = AppLocalizations.of(context)!;
    final Map<String, dynamic> entry = Map<String, dynamic>.from(_mappings[keyCode] as Map? ?? {});
    final String name = buttonName(_names[keyCode] ?? entry["name"] as String?, keyCode, l);

    final String? choice = await showDialog<String>(
      context: context,
      builder: (context) => SimpleDialog(
        title: Text(name),
        children: [
          _option(context, l.remoteButtonsPressOption(_actionLabel(l, entry[_press] as Map<String, dynamic>?)), _press),
          _option(context, l.remoteButtonsHoldOption(_actionLabel(l, entry[_hold] as Map<String, dynamic>?)), _hold),
          _option(context, l.remoteButtonsSearchPreset, "searchPreset"),
          _option(context, entry["homeOnly"] == true ? l.remoteButtonsHomeOnlyOn : l.remoteButtonsHomeOnlyOff,
              "homeOnly"),
          if (_mappings.containsKey(keyCode)) _option(context, l.remoteButtonsRestore, "remove"),
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
    final l = AppLocalizations.of(context)!;
    final inputs = context.read<TvInputsService>().inputs;
    final String? type = await showDialog<String>(
      context: context,
      builder: (context) => SimpleDialog(
        title: Text(l.remoteButtonsActionTitle),
        children: [
          _option(context, l.remoteButtonsActionApp, "app"),
          if (inputs.isNotEmpty) _option(context, l.remoteButtonsActionInput, "input"),
          _option(context, "Home Assistant…", "ha"),
          _option(context, l.remoteButtonsActionSwitchProfile, "profiles"),
          _option(context, l.remoteButtonsActionSearchVoice, "search_voice"),
          _option(context, l.remoteButtonsActionSearchKeyboard, "search_text"),
          _option(context, "Google Assistant (Gemini)", "assistant"),
          _option(context, l.remoteButtonsActionHome, "home"),
          _option(context, l.remoteButtonsActionSleep, "sleep"),
          _option(context, l.profileLockNow, "lock"),
          _option(context, l.remoteButtonsActionAndroidSettings, "settings"),
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
            title: Text(l.remoteButtonsPickAppTitle),
            children: [for (final app in apps) _option(context, app.name, app)],
          ),
        );
        return app == null ? null : {"type": "app", "target": app.packageName, "label": app.name};
      case "input":
        final input = await showDialog(
          context: context,
          builder: (context) => SimpleDialog(
            title: Text(l.remoteButtonsPickInputTitle),
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
      case "lock":
        return {"type": "lock", "label": "Lock my profile"};
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
    final l = AppLocalizations.of(context)!;
    if (entities.isEmpty) {
      showMessageDialog(context,
          title: l.remoteButtonsHaConnectTitle,
          message: l.remoteButtonsHaConnectBody(HaPanelPage.breadcrumb(l), l.haSetUpFromPhone));
      return null;
    }
    // Saved as the action's label, so it stays in the language it was picked in.
    String describe(Map e) {
      final name = "${e["name"]}";
      return switch (e["domain"]) {
        "scene" => l.remoteButtonsHaScene(name),
        "script" => l.remoteButtonsHaRun(name),
        "button" || "input_button" => l.remoteButtonsHaPress(name),
        _ => l.remoteButtonsHaToggle(name),
      };
    }
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

  /// A remapped button's row: its name, then what a press and a hold do (and whether only on the home screen).
  String _rowSummary(AppLocalizations l, String keyCode) {
    final entry = _mappings[keyCode] as Map;
    final button = buttonName(entry["name"] as String?, keyCode, l);
    final press = _actionLabel(l, entry[_press] as Map<String, dynamic>?);
    final hold = _actionLabel(l, entry[_hold] as Map<String, dynamic>?);
    return entry["homeOnly"] == true
        ? l.remoteButtonsRowSummaryHomeOnly(button, press, hold)
        : l.remoteButtonsRowSummary(button, press, hold);
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final keys = _mappings.keys.toList()..sort();
    return SettingsPage(
      title: l.remoteButtonsTitle,
      children: [
        FocusableSettingsTile(
          autofocus: true,
          leading: const Icon(Icons.add),
          title: Text(l.remoteButtonsRemapButton, style: Theme.of(context).textTheme.bodyMedium),
          onPressed: _addButton,
        ),
        for (final keyCode in keys)
          FocusableSettingsTile(
            leading: const Icon(Icons.settings_remote_outlined),
            title: Text(_rowSummary(l, keyCode), style: Theme.of(context).textTheme.bodyMedium),
            onPressed: () => _editButton(keyCode),
          ),
        const SizedBox(height: 16),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Text(
            l.remoteButtonsFooter(SetupChecklistPage.breadcrumb(l)),
            style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.white54),
            textAlign: TextAlign.center,
          ),
        ),
      ],
    );
  }
}
