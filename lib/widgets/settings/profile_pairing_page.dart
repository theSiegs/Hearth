import 'package:flauncher/flauncher_channel.dart';
import 'package:flauncher/widgets/rounded_switch_list_tile.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'focusable_settings_tile.dart';
import 'setup_checklist_page.dart';
import 'settings_page.dart';

/// One Google TV profile's pairing in one streaming app.
class PairingChoice {
  /// The key the choice is saved under (the Google TV profile, renames aside).
  final String hearthProfile;

  /// The profile's name, to show.
  final String displayName;
  final bool kids;

  /// "auto" (match by name), "profile" (a chosen app profile) or "picker" (always show the app's picker).
  final String mode;
  final String? chosenProfile;
  final String? autoMatch;

  PairingChoice.fromMap(Map<dynamic, dynamic> map)
      : hearthProfile = map["hearthProfile"] as String,
        displayName = map["displayName"] as String? ?? map["hearthProfile"] as String,
        kids = map["kids"] == true,
        mode = map["mode"] as String? ?? "auto",
        chosenProfile = map["chosenProfile"] as String?,
        autoMatch = map["autoMatch"] as String?;

  /// What Hearth will do, in words: "Alex Morgan (matched by name)", "Show the picker", ...
  String get summary => switch (mode) {
        "profile" => chosenProfile ?? "Show the picker",
        "picker" => "Always show the picker",
        _ => autoMatch != null ? "$autoMatch (matched by name)" : "No match yet: shows the picker",
      };
}

/// Profile Pairing (under Profiles): which profile each streaming app opens for each Google TV profile.
class ProfilePairingPage extends StatefulWidget {
  static const String routeName = "profile_pairing";

  const ProfilePairingPage({super.key});

  @override
  State<ProfilePairingPage> createState() => _ProfilePairingPageState();
}

class _ProfilePairingPageState extends State<ProfilePairingPage> {
  late final FLauncherChannel _channel = context.read<FLauncherChannel>();
  List<Map<dynamic, dynamic>>? _apps;
  bool _serviceOn = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final apps = await _channel.getProfilePairingApps();
    final status = await _channel.getProfilePairingStatus();
    apps.sort((a, b) => (b["installed"] == true ? 1 : 0) - (a["installed"] == true ? 1 : 0));
    if (mounted) {
      setState(() {
        _apps = apps;
        _serviceOn = status["enabled"] == true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final apps = _apps;
    return SettingsPage.custom(
      title: "Profile Pairing",
      body: apps == null
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              child: Column(
                children: [
                  if (!_serviceOn)
                    FocusableSettingsTile(
                      leading: const Icon(Icons.warning_amber_rounded, color: Colors.orange),
                      title: Text("Profile Pairing is off. Set it up", style: textTheme.bodyMedium),
                      onPressed: () async {
                        await Navigator.of(context).pushNamed(SetupChecklistPage.routeName);
                        _load();
                      },
                    ),
                  for (final (index, app) in apps.indexed)
                    FocusableSettingsTile(
                      autofocus: index == 0 && _serviceOn,
                      leading: const Icon(Icons.live_tv_outlined),
                      title: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(app["label"] as String, style: textTheme.bodyMedium),
                          Text(_appStatus(app), style: textTheme.bodySmall?.copyWith(color: Colors.white54)),
                        ],
                      ),
                      trailing: app["installed"] == true ? const Icon(Icons.chevron_right) : null,
                      onPressed: app["installed"] == true
                          ? () async {
                              await Navigator.of(context).pushNamed(ProfilePairingAppPage.routeName, arguments: app);
                              _load();
                            }
                          : null,
                    ),
                  const SizedBox(height: 16),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Text(
                      "When Hearth opens one of these apps, it picks the app profile paired with the Google TV "
                      "profile. Hearth matches names by itself (\"Alex\" goes with \"Alex Morgan\"); "
                      "change any pairing here. Without a match, the app's own picker shows.",
                      style: textTheme.bodySmall?.copyWith(color: Colors.white54),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  String _appStatus(Map<dynamic, dynamic> app) {
    if (app["installed"] != true) return "Not installed";
    if (app["enabled"] == false) return "Off: the app's own picker shows";
    final seen = (app["seenProfiles"] as List?)?.length ?? 0;
    if (seen == 0) return "Open it once from Hearth so Hearth can learn its profiles";
    return "$seen profile${seen == 1 ? '' : 's'} found";
  }
}

/// One app's pairings: a row per Google TV profile.
class ProfilePairingAppPage extends StatefulWidget {
  static const String routeName = "profile_pairing_app";

  final Map<dynamic, dynamic> app;

  const ProfilePairingAppPage({super.key, required this.app});

  @override
  State<ProfilePairingAppPage> createState() => _ProfilePairingAppPageState();
}

class _ProfilePairingAppPageState extends State<ProfilePairingAppPage> {
  late final FLauncherChannel _channel = context.read<FLauncherChannel>();
  List<PairingChoice>? _choices;
  late bool _enabled = widget.app["enabled"] != false;

  Future<void> _setEnabled(bool enabled) async {
    await _channel.setProfilePairingAppEnabled(_packageName, enabled);
    if (mounted) setState(() => _enabled = enabled);
  }

  String get _packageName => widget.app["packageName"] as String;

  List<String> get _seenProfiles => ((widget.app["seenProfiles"] as List?) ?? []).cast<String>();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final choices = (await _channel.getProfilePairingChoices(_packageName)).map(PairingChoice.fromMap).toList();
    if (mounted) setState(() => _choices = choices);
  }

  Future<void> _change(PairingChoice choice) async {
    final label = widget.app["label"] as String;
    // Each option: (mode, app profile, text).
    final options = <(String, String?, String)>[
      ("auto", null, choice.autoMatch != null ? "Match by name (${choice.autoMatch})" : "Match by name (no match yet)"),
      for (final profile in _seenProfiles) ("profile", profile, profile),
      ("picker", null, "Always show the picker"),
    ];
    bool isCurrent((String, String?, String) option) =>
        option.$1 == choice.mode && (option.$1 != "profile" || option.$2 == choice.chosenProfile);

    final picked = await showDialog<(String, String?, String)>(
      context: context,
      builder: (context) => SimpleDialog(
        title: Text("${choice.displayName} in $label"),
        children: [
          for (final option in options)
            SimpleDialogOption(
              child: TextButton(
                autofocus: isCurrent(option),
                onPressed: () => Navigator.of(context).pop(option),
                child: Row(
                  children: [
                    Icon(isCurrent(option) ? Icons.radio_button_checked : Icons.radio_button_unchecked, size: 20),
                    const SizedBox(width: 12),
                    Flexible(child: Text(option.$3)),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
    if (picked == null) return;
    await _channel.setProfilePairingChoice(_packageName, choice.hearthProfile, picked.$1, picked.$2);
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final choices = _choices;
    return SettingsPage.custom(
      title: widget.app["label"] as String,
      body: choices == null
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              child: Column(
                children: [
                  RoundedSwitchListTile(
                    autofocus: true,
                    value: _enabled,
                    onChanged: _setEnabled,
                    title: Text("Pair profiles in ${widget.app["label"]}", style: textTheme.bodyMedium),
                    secondary: Icon(Icons.switch_account, color: _enabled ? Colors.green : Colors.white54),
                  ),
                  if (_enabled) const Divider(),
                  if (_enabled)
                    for (final choice in choices)
                      FocusableSettingsTile(
                        leading: Icon(choice.kids ? Icons.child_care : Icons.person_outline),
                        title: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(choice.displayName + (choice.kids ? " (kids)" : ""), style: textTheme.bodyMedium),
                            Text(choice.summary, style: textTheme.bodySmall?.copyWith(color: Colors.white54)),
                          ],
                        ),
                        trailing: const Icon(Icons.chevron_right),
                        onPressed: () => _change(choice),
                      ),
                  const SizedBox(height: 16),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Text(
                      _seenProfiles.isEmpty
                          ? "Hearth hasn't seen this app's profiles yet. Open it once from Hearth, then come back."
                          : "Profiles in this app: ${_seenProfiles.join(", ")}. Google TV profiles appear here "
                              "once Hearth has seen them.",
                      style: textTheme.bodySmall?.copyWith(color: Colors.white54),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}
