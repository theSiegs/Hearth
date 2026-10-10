import 'package:flauncher/hearth_ids.dart';
import 'package:flauncher/flauncher_channel.dart';
import 'package:flauncher/l10n/app_localizations.dart';
import 'package:flauncher/providers/settings_service.dart';
import 'package:flauncher/widgets/rounded_switch_list_tile.dart';
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';

import 'adb_command_dialog.dart';
import 'focusable_settings_tile.dart';
import 'settings_page.dart';

/// The things the TV owner turns on in Android's Settings for Hearth. The setup flow and this checklist both work
/// from [loadSetupSteps], so they agree on what's done.
enum SetupStepId { homeButton, homeApp, notifications, install, profilePairing, voice }

/// One thing the TV owner turns on in Android's Settings for Hearth. Android doesn't let an app jump to (or
/// highlight) the exact switch on Google TV, so each step explains what to pick on the screen it opens.
class SetupStep {
  final SetupStepId id;
  final String title;
  final String why;
  final String instructions;
  final IconData icon;
  final bool optional;
  final bool done;
  final String? warning;

  /// Android blocks the switch (restricted settings), so it can't be turned on from the TV alone.
  final bool blocked;

  /// Android lists it as on, but the service isn't running.
  final bool stuck;

  /// Opens the Settings screen for it; false when Android couldn't open it.
  final Future<bool> Function() open;

  /// What to run from a computer instead, when the screen won't open.
  final String? adbFallback;

  const SetupStep({
    required this.id,
    required this.title,
    required this.why,
    required this.instructions,
    required this.icon,
    required this.done,
    required this.open,
    this.optional = false,
    this.warning,
    this.blocked = false,
    this.stuck = false,
    this.adbFallback,
  });
}

/// Builds the checklist from the TV's current state, worded in [l]'s language. The services' names stay as Android
/// shows them (they come from Hearth's manifest).
Future<List<SetupStep>> loadSetupSteps(FLauncherChannel channel, String packageName, AppLocalizations l) async {
  Future<T> safe<T>(Future<T> Function() read, T fallback) async {
    try {
      return await read();
    } catch (_) {
      return fallback;
    }
  }

  final isDefault = await safe(channel.isDefaultLauncher, false);
  final homeFix = await safe(channel.getHomeButtonFixStatus, <dynamic, dynamic>{});
  final notifications = await safe(channel.checkNotificationListenerPermission, false);
  final install = await safe(channel.checkInstallPermission, false);
  final pairing = await safe(channel.getProfilePairingStatus, <dynamic, dynamic>{});

  final bool blocked = homeFix["restricted"] == true;
  final restricted = blocked
      ? l.setupRestrictedWarning("adb shell appops set $packageName ACCESS_RESTRICTED_SETTINGS allow")
      : null;

  return [
    SetupStep(
      id: SetupStepId.homeApp,
      title: l.setupDefaultLauncherTitle,
      why: l.setupDefaultLauncherWhy,
      instructions: l.setupDefaultLauncherInstructions,
      icon: Icons.home_outlined,
      done: isDefault,
      open: () async {
        await channel.openDefaultLauncherSettings();
        return true;
      },
    ),
    SetupStep(
      id: SetupStepId.homeButton,
      title: l.setupHomeFixTitle,
      why: l.setupHomeFixWhy,
      instructions: l.setupAccessibilityInstructions("Hearth Home Button Fix"),
      icon: Icons.settings_remote_outlined,
      done: homeFix["enabled"] == true,
      warning: restricted,
      blocked: blocked,
      stuck: homeFix["listedButStopped"] == true,
      open: channel.requestAccessibilityPermission,
      adbFallback: "adb shell settings put secure enabled_accessibility_services "
          "${hearthComponent(packageName, "LauncherAccessibilityService")}",
    ),
    SetupStep(
      id: SetupStepId.notifications,
      title: l.setupNotificationsTitle,
      why: l.setupNotificationsWhy,
      instructions: l.setupNotificationsInstructions("Hearth Notification Service"),
      icon: Icons.notifications_active_outlined,
      done: notifications,
      open: () async {
        await channel.requestNotificationListenerPermission();
        return true;
      },
    ),
    SetupStep(
      id: SetupStepId.install,
      title: l.setupInstallTitle,
      why: l.setupInstallWhy,
      instructions: l.setupInstallInstructions,
      icon: Icons.system_update_outlined,
      done: install,
      open: () async {
        await channel.requestInstallPermission();
        return true;
      },
    ),
    SetupStep(
      id: SetupStepId.profilePairing,
      title: l.profilePairingTitle,
      why: l.setupPairingWhy,
      instructions: l.setupAccessibilityInstructions("Hearth Profile Pairing"),
      icon: Icons.switch_account,
      optional: true,
      done: pairing["enabled"] == true,
      warning: restricted,
      blocked: blocked,
      open: channel.requestAccessibilityPermission,
    ),
    SetupStep(
      id: SetupStepId.voice,
      title: l.setupVoiceTitle,
      why: l.setupVoiceWhy,
      instructions: l.setupVoiceInstructions("Hearth voice"),
      icon: Icons.record_voice_over,
      optional: true,
      done: pairing["voiceDefault"] == true,
      open: () async {
        await channel.openTextToSpeechSettings();
        return true;
      },
    ),
  ];
}

/// Setup & permissions: what to turn on in Android's Settings for Hearth, each with its status, and Start on boot.
class SetupChecklistPage extends StatefulWidget {
  static const String routeName = "setup_checklist";
  /// Where this page is, for the hints on other pages that send people here.
  static String breadcrumb(AppLocalizations l) => "${l.settingsTitle} > ${l.system} > ${l.setupPermissionsTitle}";

  const SetupChecklistPage({super.key});

  @override
  State<SetupChecklistPage> createState() => _SetupChecklistPageState();
}

class _SetupChecklistPageState extends State<SetupChecklistPage> with WidgetsBindingObserver {
  late final FLauncherChannel _channel;
  List<SetupStep>? _steps;

  @override
  void initState() {
    super.initState();
    _channel = context.read<FLauncherChannel>();
    WidgetsBinding.instance.addObserver(this);
    _refresh();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refresh();
  }

  Future<void> _refresh() async {
    String packageName = kHearthAppId;
    try {
      packageName = (await PackageInfo.fromPlatform()).packageName;
    } catch (_) {}
    if (!mounted) return;
    final steps = await loadSetupSteps(_channel, packageName, AppLocalizations.of(context)!);
    if (mounted) setState(() => _steps = steps);
  }

  Future<void> _showCard(SetupStep step) async {
    final l = AppLocalizations.of(context)!;
    final textTheme = Theme.of(context).textTheme;
    final go = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(step.title),
        content: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(step.why, style: textTheme.bodySmall?.copyWith(color: Colors.white70)),
              const SizedBox(height: 12),
              Text(step.instructions, style: textTheme.bodyMedium),
              if (step.warning != null) ...[
                const SizedBox(height: 12),
                Text(step.warning!, style: textTheme.bodySmall?.copyWith(color: Colors.orange)),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: Text(l.notNow)),
          TextButton(
            autofocus: true,
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(l.setupOpenSettings),
          ),
        ],
      ),
    );
    if (go != true) return;
    if (!await step.open() && step.adbFallback != null && mounted) {
      await showAdbCommandDialog(
        context,
        title: step.title,
        message: l.setupAdbFallback,
        command: step.adbFallback!,
      );
    }
  }

  Widget _startOnBootTile(BuildContext context) {
    final localizations = AppLocalizations.of(context)!;
    final settings = context.watch<SettingsService>();
    final on = settings.startOnBoot;
    return RoundedSwitchListTile(
      value: on,
      onChanged: (start) => settings.setStartOnBoot(start),
      title: Text(localizations.startOnBoot, style: Theme.of(context).textTheme.bodyMedium),
      secondary: Icon(Icons.power_settings_new, color: on ? Colors.green : null),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final textTheme = Theme.of(context).textTheme;
    final steps = _steps;
    final required = steps?.where((s) => !s.optional).toList() ?? [];
    return SettingsPage.custom(
      title: l.setupPermissionsTitle,
      subtitle: steps == null
          ? null
          : Text(
              l.setupProgress(required.where((s) => s.done).length, required.length),
              style: textTheme.bodySmall?.copyWith(color: Colors.white54),
            ),
      body: steps == null
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              child: Column(
                children: [
                  for (final (index, step) in steps.indexed) ...[
                    if (step.optional && (index == 0 || !steps[index - 1].optional))
                      Padding(
                        padding: const EdgeInsets.fromLTRB(24, 12, 24, 4),
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: Text(l.setupOptional, style: textTheme.labelMedium?.copyWith(color: Colors.white54)),
                        ),
                      ),
                    FocusableSettingsTile(
                      autofocus: index == 0,
                      leading: Icon(step.icon, color: step.done ? Colors.green : null),
                      title: Text(step.title, style: textTheme.bodyMedium),
                      trailing: Icon(
                        step.done ? Icons.check_circle : Icons.chevron_right,
                        color: step.done ? Colors.green : Colors.white54,
                      ),
                      onPressed: () => _showCard(step),
                    ),
                  ],
                  const Divider(),
                  _startOnBootTile(context),
                ],
              ),
            ),
    );
  }
}
