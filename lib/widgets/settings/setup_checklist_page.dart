import 'package:flauncher/flauncher_channel.dart';
import 'package:flauncher/l10n/app_localizations.dart';
import 'package:flauncher/providers/settings_service.dart';
import 'package:flauncher/widgets/rounded_switch_list_tile.dart';
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';

import 'adb_command_dialog.dart';
import 'family_apps_page.dart';
import 'focusable_settings_tile.dart';
import 'settings_page.dart';

/// One thing the TV owner turns on in Android's Settings for Hearth. Android doesn't let an app jump to (or
/// highlight) the exact switch on Google TV, so each step explains what to pick on the screen it opens.
class SetupStep {
  final String title;
  final String why;
  final String instructions;
  final IconData icon;
  final bool optional;
  final bool done;
  final String? warning;

  /// Opens the Settings screen for it; false when Android couldn't open it.
  final Future<bool> Function() open;

  /// What to run from a computer instead, when the screen won't open.
  final String? adbFallback;

  const SetupStep({
    required this.title,
    required this.why,
    required this.instructions,
    required this.icon,
    required this.done,
    required this.open,
    this.optional = false,
    this.warning,
    this.adbFallback,
  });
}

/// Builds the checklist from the TV's current state.
Future<List<SetupStep>> loadSetupSteps(FLauncherChannel channel, String packageName) async {
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

  const accessibilitySteps = "scroll down to Services, select \"%s\", then turn on Enable and confirm. "
      "Press Back until you're home again.";
  final restricted = homeFix["restricted"] == true
      ? "If Android says the setting is restricted, run this once from a computer:\n"
          "adb shell appops set $packageName ACCESS_RESTRICTED_SETTINGS allow"
      : null;

  return [
    SetupStep(
      title: "Hearth as the home app",
      why: "Keeps kids profiles from blocking Hearth.",
      instructions: "On the next screen, choose Hearth.",
      icon: Icons.home_outlined,
      done: isDefault,
      open: () async {
        await channel.openDefaultLauncherSettings();
        return true;
      },
    ),
    SetupStep(
      title: "Home Button Fix",
      why: "The Home button opens Hearth instead of Google TV.",
      instructions: "On the next screen, ${accessibilitySteps.replaceFirst("%s", "Hearth Home Button Fix")}",
      icon: Icons.settings_remote_outlined,
      done: homeFix["enabled"] == true,
      warning: restricted,
      open: channel.requestAccessibilityPermission,
      adbFallback: "adb shell settings put secure enabled_accessibility_services "
          "$packageName/$packageName.LauncherAccessibilityService",
    ),
    SetupStep(
      title: "Notification access",
      why: "Shows notifications and what's playing.",
      instructions: "On the next screen, select \"Hearth Notification Service\" and allow it.",
      icon: Icons.notifications_active_outlined,
      done: notifications,
      open: () async {
        await channel.requestNotificationListenerPermission();
        return true;
      },
    ),
    SetupStep(
      title: "Installing updates",
      why: "Lets Hearth update itself and install companion apps.",
      instructions: "On the next screen, turn on Hearth.",
      icon: Icons.system_update_outlined,
      done: install,
      open: () async {
        await channel.requestInstallPermission();
        return true;
      },
    ),
    SetupStep(
      title: "Profile Pairing",
      why: "Picks your profile in Netflix, Disney+, Apple TV, HBO Max and Paramount+.",
      instructions: "On the next screen, ${accessibilitySteps.replaceFirst("%s", "Hearth Profile Pairing")}",
      icon: Icons.switch_account,
      optional: true,
      done: pairing["enabled"] == true,
      warning: restricted,
      open: channel.requestAccessibilityPermission,
    ),
    SetupStep(
      title: "Hearth voice",
      why: "Lets Profile Pairing hear Netflix's profile screen. Other apps keep Google's voice.",
      instructions:
          "On the next screen, under Preferred engine, choose \"Hearth voice\", then OK on the warning (Hearth only listens to the streaming apps). Press Back to return.",
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
    String packageName = "com.leanbitlab.ltvL";
    try {
      packageName = (await PackageInfo.fromPlatform()).packageName;
    } catch (_) {}
    final steps = await loadSetupSteps(_channel, packageName);
    if (mounted) setState(() => _steps = steps);
  }

  Future<void> _showCard(SetupStep step) async {
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
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text("Not now")),
          TextButton(
            autofocus: true,
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text("Open Settings"),
          ),
        ],
      ),
    );
    if (go != true) return;
    if (!await step.open() && step.adbFallback != null && mounted) {
      await showAdbCommandDialog(
        context,
        title: step.title,
        message: "This TV wouldn't open that Settings screen. Run this once from a computer instead:",
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
    final textTheme = Theme.of(context).textTheme;
    final steps = _steps;
    final required = steps?.where((s) => !s.optional).toList() ?? [];
    return SettingsPage.custom(
      title: AppLocalizations.of(context)!.setupPermissionsTitle,
      subtitle: steps == null
          ? null
          : Text(
              "${required.where((s) => s.done).length} of ${required.length} done",
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
                          child: Text("Optional", style: textTheme.labelMedium?.copyWith(color: Colors.white54)),
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
                  FocusableSettingsTile(
                    leading: const Icon(Icons.people_alt_outlined),
                    title: Text(AppLocalizations.of(context)!.familyAppsTitle, style: textTheme.bodyMedium),
                    trailing: const Icon(Icons.chevron_right, color: Colors.white54),
                    onPressed: () => Navigator.of(context).pushNamed(FamilyAppsPage.routeName),
                  ),
                ],
              ),
            ),
    );
  }
}
