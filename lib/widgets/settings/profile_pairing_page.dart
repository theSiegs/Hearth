import 'package:flauncher/l10n/app_localizations.dart';
import 'package:flauncher/flauncher_channel.dart';
import 'package:flauncher/providers/profile_service.dart';
import 'package:flauncher/providers/settings_service.dart';
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

/// Rejections in a row after which Hearth waits for a new PIN (ProfilePairingService.PIN_GIVE_UP_REJECTIONS).
const int profilePinGiveUpRejections = 2;

/// A saved streaming-app profile PIN's state in words ([FLauncherChannel.getProfilePinStatus]): none, saved, not
/// accepted last time, not accepted twice (not tried until saved again), or paused.
String profilePinStatus(AppLocalizations l, Map<dynamic, dynamic>? pin) {
  final status = pin?["status"] as String? ?? "none";
  if (status != "none" && pin?["paused"] == true) return l.profilePinPaused;
  return switch (status) {
    "none" => l.profilePinNone,
    "rejected" when (pin?["rejections"] as int? ?? 0) >= profilePinGiveUpRejections => l.profilePinGaveUp,
    "rejected" => l.profilePinRejected,
    _ => l.profilePinSaved,
  };
}

/// What typing streaming PINs involves, once per TV before the first PIN is saved; true when the parent goes on.
Future<bool> confirmPinConsent(BuildContext context, String appLabel) async {
  final settings = context.read<SettingsService>();
  if (settings.pinConsentGiven) return true;
  final l = AppLocalizations.of(context)!;
  final ok = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(l.pinConsentTitle),
      content: SingleChildScrollView(child: Text(l.pinConsentBody(appLabel))),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(false), child: Text(l.cancel)),
        TextButton(autofocus: true, onPressed: () => Navigator.of(context).pop(true), child: Text(l.pinConsentAgree)),
      ],
    ),
  );
  if (ok != true) return false;
  await settings.setPinConsentGiven();
  return true;
}

/// An app profile's PIN: the parent PIN first, then the PIN on the row pad, twice; for a saved one, Change or Remove
/// first. [beforeSave] runs just before a new PIN is saved (Streaming app PINs pairs the profiles for good then, so
/// nothing changes when the parent backs out). Returns whether anything changed.
Future<bool> editProfilePin(
  BuildContext context, {
  required String packageName,
  required String appLabel,
  required String appProfile,
  required bool saved,
  Future<void> Function()? beforeSave,
}) async {
  final l = AppLocalizations.of(context)!;
  final channel = context.read<FLauncherChannel>();
  if (!await requireParentPin(context)) return false;
  if (!context.mounted) return false;
  if (saved) {
    final remove = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l.profilePinEnterTitle(appProfile, appLabel)),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(true), child: Text(l.parentPinRemove)),
          TextButton(
              autofocus: true, onPressed: () => Navigator.of(context).pop(false), child: Text(l.parentPinChange)),
        ],
      ),
    );
    if (remove == null || !context.mounted) return false;
    if (remove) {
      await channel.removeProfilePin(packageName, appProfile);
      return true;
    }
  }
  if (!await confirmPinConsent(context, appLabel)) return false;
  if (!context.mounted) return false;
  final first = await showDialog<String>(
    context: context,
    builder: (_) => ParentPinDialog(
      title: l.profilePinEnterTitle(appProfile, appLabel),
      subtitle: l.profilePinEnterSubtitle(appLabel),
      length: ProfilePairingAppPage.pinLength,
    ),
  );
  if (first == null || !context.mounted) return false;
  final second = await showDialog<String>(
    context: context,
    builder: (_) => ParentPinDialog(
      title: l.parentPinConfirm,
      verify: (pin) => pin == first,
      length: ProfilePairingAppPage.pinLength,
    ),
  );
  if (second == null || !context.mounted) return false;
  await beforeSave?.call();
  final ok = await channel.saveProfilePin(packageName, appProfile, first);
  if (!ok && context.mounted) await showMessageDialog(context, title: l.profilePinRow, message: l.profilePinSaveFailed);
  return true;
}

/// An app's account-wide content PIN (Paramount+'s, asked for when a title starts): the parent PIN first, then the
/// PIN on the row pad, twice; for a saved one, Change or Remove first. Saved once for the whole TV, it's typed only in
/// an adult's profile that has its own Google TV PIN lock. Returns whether anything changed.
Future<bool> editContentPin(
  BuildContext context, {
  required String packageName,
  required String appLabel,
  required bool saved,
}) async {
  final l = AppLocalizations.of(context)!;
  final channel = context.read<FLauncherChannel>();
  if (!await requireParentPin(context)) return false;
  if (!context.mounted) return false;
  final title = l.contentPinRow(appLabel);
  if (saved) {
    final remove = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(true), child: Text(l.parentPinRemove)),
          TextButton(
              autofocus: true, onPressed: () => Navigator.of(context).pop(false), child: Text(l.parentPinChange)),
        ],
      ),
    );
    if (remove == null || !context.mounted) return false;
    if (remove) {
      await channel.removeContentPin(packageName);
      return true;
    }
  }
  if (!await confirmPinConsent(context, appLabel)) return false;
  if (!context.mounted) return false;
  final first = await showDialog<String>(
    context: context,
    builder: (_) => ParentPinDialog(
      title: title,
      subtitle: l.contentPinEnterSubtitle(appLabel),
      length: ProfilePairingAppPage.pinLength,
    ),
  );
  if (first == null || !context.mounted) return false;
  final second = await showDialog<String>(
    context: context,
    builder: (_) => ParentPinDialog(
      title: l.parentPinConfirm,
      verify: (pin) => pin == first,
      length: ProfilePairingAppPage.pinLength,
    ),
  );
  if (second == null || !context.mounted) return false;
  final ok = await channel.saveContentPin(packageName, first);
  if (!ok && context.mounted) await showMessageDialog(context, title: title, message: l.profilePinSaveFailed);
  return true;
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
                      autofocus: true,
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

  /// The PIN length every supported app uses so far.
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

  /// A Google TV profile paired with an app profile by an explicit choice (Streaming app PINs pairs a name match for
  /// good when its PIN is set), a kids' one too.
  static bool _paired(PairingChoice choice) => choice.mode == "profile" && choice.chosenProfile != null;

  /// Only the profile on now sees and sets its PIN here: each profile controls only its own.
  bool _hasPin(PairingChoice choice) =>
      _paired(choice) && choice.hearthProfile == context.read<ProfileService?>()?.activeProfileKey;

  String _pinStatus(AppLocalizations l, String appProfile) {
    String text = profilePinStatus(l, _pins[appProfile]);
    if (!_pinsSupported) text = "$text · ${l.profilePinUnsupported(widget.app["label"] as String)}";
    return text;
  }

  Future<void> _editPin(String appProfile) async {
    await editProfilePin(
      context,
      packageName: _packageName,
      appLabel: widget.app["label"] as String,
      appProfile: appProfile,
      saved: (_pins[appProfile]?["status"] as String? ?? "none") != "none",
    );
    if (mounted) _load();
  }

  Future<void> _change(PairingChoice choice) async {
    final l = AppLocalizations.of(context)!;
    // A pairing with a saved PIN changes only with the parent PIN: the PIN goes with it (see below)
    final old = choice.chosenProfile;
    if (_paired(choice)) {
      final pin = await _channel.getProfilePinStatus(_packageName, old!, profileKey: choice.hearthProfile);
      if ((pin["status"] as String? ?? "none") != "none") {
        if (!mounted || !await requireParentPin(context) || !mounted) return;
      }
    }
    final label = widget.app["label"] as String;
    // Each option: (mode, app profile, text).
    final options = <(String, String?, String)>[
      ("auto", null, choice.autoMatch != null ? l.pairingMatchByName(choice.autoMatch!) : l.pairingMatchByNameNone),
      for (final profile in _seenProfiles) ("profile", profile, profile),
      ("picker", null, l.pairingAlwaysShowPicker),
    ];
    bool isCurrent((String, String?, String) option) =>
        option.$1 == choice.mode && (option.$1 != "profile" || option.$2 == choice.chosenProfile);

    if (!mounted) return;
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
    // The PIN this Google TV profile saved for the app profile it leaves goes (each profile's PINs are its own)
    if (_paired(choice) && !(picked.$1 == "profile" && picked.$2 == old)) {
      await _channel.removeProfilePin(_packageName, old!, profileKey: choice.hearthProfile);
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
