import 'package:flauncher/l10n/app_localizations.dart';
import 'package:flauncher/flauncher_channel.dart';
import 'package:flauncher/widgets/parent_pin_dialog.dart';
import 'package:flauncher/widgets/rounded_switch_list_tile.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'focusable_settings_tile.dart';
import 'message_dialog.dart';
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
  String summary(AppLocalizations l) => switch (mode) {
        "profile" => chosenProfile ?? l.pairingShowPicker,
        "picker" => l.pairingAlwaysShowPicker,
        _ => autoMatch != null ? l.pairingMatchedByName(autoMatch!) : l.pairingNoMatchYet,
      };
}

/// Profile Pairing (under Profiles): which profile each streaming app opens for each Google TV profile.
class ProfilePairingPage extends StatefulWidget {
  static const String routeName = "profile_pairing";

  /// Opens this app's page once loaded (Profile Pairing's "Change PIN"), with the selection on its PINs.
  final String? openApp;

  const ProfilePairingPage({super.key, this.openApp});

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
    final openApp = widget.openApp;
    if (openApp != null && !_openedApp && mounted) {
      _openedApp = true;
      final app = apps.where((a) => a["packageName"] == openApp && a["installed"] == true).firstOrNull;
      if (app != null) {
        await Navigator.of(context)
            .pushNamed(ProfilePairingAppPage.routeName, arguments: {...app, ProfilePairingAppPage.focusPinsKey: true});
        _load();
      }
    }
  }

  bool _openedApp = false;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final textTheme = Theme.of(context).textTheme;
    final apps = _apps;
    return SettingsPage.custom(
      title: l.profilePairingTitle,
      body: apps == null
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              child: Column(
                children: [
                  if (!_serviceOn)
                    FocusableSettingsTile(
                      leading: const Icon(Icons.warning_amber_rounded, color: Colors.orange),
                      title: Text(l.pairingOffSetUp, style: textTheme.bodyMedium),
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
                          Text(_appStatus(l, app), style: textTheme.bodySmall?.copyWith(color: Colors.white54)),
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
                      l.pairingFooter("Alex", "Alex Morgan"),
                      style: textTheme.bodySmall?.copyWith(color: Colors.white54),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  String _appStatus(AppLocalizations l, Map<dynamic, dynamic> app) {
    if (app["installed"] != true) return l.pairingAppNotInstalled;
    if (app["enabled"] == false) return l.pairingAppOff;
    final seen = (app["seenProfiles"] as List?)?.length ?? 0;
    if (seen == 0) return l.pairingAppNotSeen;
    return l.pairingAppProfilesFound(seen);
  }
}

/// One app's pairings: a row per Google TV profile.
class ProfilePairingAppPage extends StatefulWidget {
  static const String routeName = "profile_pairing_app";

  /// In [app]: open with the selection on the first profile PIN (from Profile Pairing's "Change PIN").
  static const String focusPinsKey = "focusPins";

  /// The PIN length every supported app uses so far (see docs/design/streaming-pin-entry.md).
  static const int pinLength = 4;

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

  bool get _focusPins => widget.app[ProfilePairingAppPage.focusPinsKey] == true && (_choices ?? []).any(_hasPin);

  List<String> get _seenProfiles => ((widget.app["seenProfiles"] as List?) ?? []).cast<String>();

  @override
  void initState() {
    super.initState();
    _load();
  }

  /// Each explicitly paired app profile's saved PIN state, by app profile name.
  Map<String, Map<dynamic, dynamic>> _pins = {};
  bool _pinsSupported = false;

  Future<void> _load() async {
    final choices = (await _channel.getProfilePairingChoices(_packageName)).map(PairingChoice.fromMap).toList();
    final pins = <String, Map<dynamic, dynamic>>{};
    for (final choice in choices.where(_hasPin)) {
      pins[choice.chosenProfile!] = await _channel.getProfilePinStatus(_packageName, choice.chosenProfile!);
    }
    final supported = await _channel.profilePinEntrySupported(_packageName);
    if (mounted) {
      setState(() {
        _choices = choices;
        _pins = pins;
        _pinsSupported = supported;
      });
    }
  }

  /// Only grown-up profiles paired with an app profile by an explicit choice get a PIN (never a name match, never kids).
  static bool _hasPin(PairingChoice choice) => choice.mode == "profile" && !choice.kids && choice.chosenProfile != null;

  String _pinStatus(AppLocalizations l, String appProfile) {
    final pin = _pins[appProfile] ?? const {};
    final status = pin["status"] as String? ?? "none";
    String text = switch (status) {
      "none" => l.profilePinNone,
      "rejected" => l.profilePinRejected,
      _ => l.profilePinSaved,
    };
    if (status != "none" && pin["paused"] == true) text = l.profilePinPaused;
    if (!_pinsSupported) text = "$text · ${l.profilePinUnsupported(widget.app["label"] as String)}";
    return text;
  }

  /// The parent PIN first, then the app profile's PIN on the row pad, twice; or Change / Remove for a saved one.
  Future<void> _editPin(String appProfile) async {
    final l = AppLocalizations.of(context)!;
    if (!await requireParentPin(context)) return;
    if (!mounted) return;
    final saved = (_pins[appProfile]?["status"] as String? ?? "none") != "none";
    if (saved) {
      final remove = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(l.profilePinEnterTitle(appProfile, widget.app["label"] as String)),
          actions: [
            TextButton(onPressed: () => Navigator.of(context).pop(true), child: Text(l.parentPinRemove)),
            TextButton(
                autofocus: true, onPressed: () => Navigator.of(context).pop(false), child: Text(l.parentPinChange)),
          ],
        ),
      );
      if (remove == null) return;
      if (!mounted) return;
      if (remove) {
        await _channel.removeProfilePin(_packageName, appProfile);
        _load();
        return;
      }
    }
    final label = widget.app["label"] as String;
    final first = await showDialog<String>(
      context: context,
      builder: (_) => ParentPinDialog(
        title: l.profilePinEnterTitle(appProfile, label),
        subtitle: l.profilePinEnterSubtitle(label),
        length: ProfilePairingAppPage.pinLength,
      ),
    );
    if (first == null || !mounted) return;
    final second = await showDialog<String>(
      context: context,
      builder: (_) => ParentPinDialog(
        title: l.parentPinConfirm,
        verify: (pin) => pin == first,
        length: ProfilePairingAppPage.pinLength,
      ),
    );
    if (second == null || !mounted) return;
    final ok = await _channel.saveProfilePin(_packageName, appProfile, first);
    if (!ok && mounted) await showMessageDialog(context, title: l.profilePinRow, message: l.profilePinSaveFailed);
    _load();
  }

  Future<void> _change(PairingChoice choice) async {
    final l = AppLocalizations.of(context)!;
    final label = widget.app["label"] as String;
    // Each option: (mode, app profile, text).
    final options = <(String, String?, String)>[
      ("auto", null, choice.autoMatch != null ? l.pairingMatchByName(choice.autoMatch!) : l.pairingMatchByNameNone),
      for (final profile in _seenProfiles) ("profile", profile, profile),
      ("picker", null, l.pairingAlwaysShowPicker),
    ];
    bool isCurrent((String, String?, String) option) =>
        option.$1 == choice.mode && (option.$1 != "profile" || option.$2 == choice.chosenProfile);

    final picked = await showDialog<(String, String?, String)>(
      context: context,
      builder: (context) => SimpleDialog(
        title: Text(l.pairingProfileInApp(choice.displayName, label)),
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
    // A PIN saved for the app profile this pairing leaves goes, unless another Google TV profile still uses it
    final old = choice.chosenProfile;
    if (_hasPin(choice) && !(picked.$1 == "profile" && picked.$2 == old)) {
      final stillUsed = (_choices ?? []).any((c) => c != choice && _hasPin(c) && c.chosenProfile == old);
      if (!stillUsed) await _channel.removeProfilePin(_packageName, old!);
    }
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
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
                    autofocus: !_focusPins,
                    value: _enabled,
                    onChanged: _setEnabled,
                    title: Text(l.pairingPairIn(widget.app["label"] as String), style: textTheme.bodyMedium),
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
                            Text(choice.kids ? l.profilesKidsName(choice.displayName) : choice.displayName,
                                style: textTheme.bodyMedium),
                            Text(choice.summary(l), style: textTheme.bodySmall?.copyWith(color: Colors.white54)),
                          ],
                        ),
                        trailing: const Icon(Icons.chevron_right),
                        onPressed: () => _change(choice),
                      ),
                  if (_enabled)
                    for (final (index, choice) in choices.where(_hasPin).indexed)
                      FocusableSettingsTile(
                        autofocus: _focusPins && index == 0,
                        leading: const Icon(Icons.pin_outlined),
                        title: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text("${l.profilePinRow}: ${choice.chosenProfile}", style: textTheme.bodyMedium),
                            Text(_pinStatus(l, choice.chosenProfile!),
                                style: textTheme.bodySmall?.copyWith(color: Colors.white54)),
                          ],
                        ),
                        trailing: const Icon(Icons.chevron_right),
                        onPressed: () => _editPin(choice.chosenProfile!),
                      ),
                  const SizedBox(height: 16),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Text(
                      _seenProfiles.isEmpty
                          ? l.pairingAppNotSeenFooter
                          : l.pairingAppProfilesFooter(_seenProfiles.join(", ")),
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
