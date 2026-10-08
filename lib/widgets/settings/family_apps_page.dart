import 'package:flauncher/flauncher_channel.dart';
import 'package:flauncher/providers/settings_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'focusable_settings_tile.dart';

/// Settings: put Hearth (and HearthTube) on the TV's other Google TV profiles, and take them off again — all
/// parent-controlled. The parent presses Add or Remove; the first Add asks for the one-time on-screen
/// "Allow debugging?" approval. Supervised kids' profiles are kept installed (Google TV would otherwise strip them
/// at each profile start); other adult profiles get a plain install, as a convenience, when the toggle is on.
class FamilyAppsPage extends StatefulWidget {
  static const String routeName = "family_apps";
  static const String title = "Hearth on other profiles";

  const FamilyAppsPage({super.key});

  @override
  State<FamilyAppsPage> createState() => _FamilyAppsPageState();
}

class _FamilyAppsPageState extends State<FamilyAppsPage> with WidgetsBindingObserver {
  final FLauncherChannel _channel = FLauncherChannel();
  List<Map<dynamic, dynamic>>? _state;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
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
    try {
      final rows = await _channel.getHearthProfilesState();
      if (mounted) setState(() => _state = rows);
    } on PlatformException {
      // Most likely the one-time "Allow debugging?" approval hasn't been given yet; show an empty state.
      if (mounted) setState(() => _state = []);
    }
  }

  Future<void> _add() async {
    final includeAdults = context.read<SettingsService>().pushToAdultProfiles;
    final go = await _confirm(
      title: "Add Hearth to other profiles",
      lines: [
        "This puts Hearth and HearthTube on your kids' profiles and keeps them there — Google TV would otherwise remove them at each profile start.",
        if (includeAdults)
          "It also installs them on the TV's other adult profiles, so another adult doesn't have to sideload Hearth.",
        "It only ever touches Hearth's own two apps, and you can undo it anytime with Remove below.",
        "Each kid gets one Family Link \"app added\" notification.",
        "The first time, the TV will ask \"Allow debugging?\" — choose Always allow.",
      ],
      action: "Add",
    );
    if (go != true) return;
    await _run(() => _channel.addHearthToProfiles(includeAdults: includeAdults), "Add");
  }

  Future<void> _remove() async {
    final go = await _confirm(
      title: "Remove Hearth from other profiles",
      lines: [
        "This removes Hearth and HearthTube from your other profiles and lifts their keep-installed protection.",
        "Run this before you ever uninstall Hearth itself — otherwise the kept copies can't be removed without a computer.",
      ],
      action: "Remove",
    );
    if (go != true) return;
    await _run(() => _channel.removeHearthFromProfiles(), "Remove");
  }

  Future<void> _run(Future<List<String>> Function() action, String label) async {
    setState(() => _busy = true);
    try {
      final log = await action();
      await _refresh();
      if (mounted) {
        await _showLog("$label done", log.isEmpty ? ["Nothing to do — no other profiles found."] : log);
      }
    } on PlatformException catch (e) {
      if (mounted) {
        await _showLog("Couldn't reach the TV", [
          "Hearth needs its one-time on-screen approval before it can manage profiles.",
          "On the TV, approve \"Allow debugging?\" (choose Always allow), then try again.",
          if (e.message != null && e.message!.isNotEmpty) "Details: ${e.message}",
        ]);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<bool?> _confirm({required String title, required List<String> lines, required String action}) {
    final textTheme = Theme.of(context).textTheme;
    return showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: SizedBox(
          width: 460,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final line in lines) ...[
                Text(line, style: textTheme.bodyMedium),
                const SizedBox(height: 10),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text("Not now")),
          TextButton(autofocus: true, onPressed: () => Navigator.of(context).pop(true), child: Text(action)),
        ],
      ),
    );
  }

  Future<void> _showLog(String title, List<String> lines) {
    final textTheme = Theme.of(context).textTheme;
    return showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: SizedBox(
          width: 460,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [for (final line in lines) Text(line, style: textTheme.bodySmall)],
            ),
          ),
        ),
        actions: [TextButton(autofocus: true, onPressed: () => Navigator.of(context).pop(), child: const Text("OK"))],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final settings = context.watch<SettingsService>();
    final adultsOn = settings.pushToAdultProfiles;
    return Column(
      children: [
        Text(FamilyAppsPage.title, style: textTheme.titleLarge),
        const Divider(),
        Expanded(
          child: SingleChildScrollView(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
                  child: Text(
                    "Put Hearth and HearthTube on your other Google TV profiles. Kids' profiles are kept installed; "
                    "other adult profiles get a plain install. You stay in control — add or remove anytime.",
                    style: textTheme.bodySmall?.copyWith(color: Colors.white70),
                  ),
                ),
                FocusableSettingsTile(
                  autofocus: true,
                  leading: const Icon(Icons.group_add_outlined),
                  title: Text("Add Hearth to other profiles", style: textTheme.bodyMedium),
                  trailing: _busy
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.chevron_right, color: Colors.white54),
                  onPressed: _busy ? null : () => _add(),
                ),
                FocusableSettingsTile(
                  leading: const Icon(Icons.group_remove_outlined),
                  title: Text("Remove Hearth from other profiles", style: textTheme.bodyMedium),
                  trailing: const Icon(Icons.chevron_right, color: Colors.white54),
                  onPressed: _busy ? null : () => _remove(),
                ),
                FocusableSettingsTile(
                  leading: Icon(Icons.person_outline, color: adultsOn ? Colors.green : null),
                  title: Text("Also set up other adult profiles", style: textTheme.bodyMedium),
                  trailing: Text(adultsOn ? "On" : "Off",
                      style: textTheme.bodySmall?.copyWith(color: adultsOn ? Colors.green : Colors.white54)),
                  onPressed: () => settings.setPushToAdultProfiles(!adultsOn),
                ),
                const Divider(),
                _stateSection(context),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _stateSection(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final rows = _state;
    if (rows == null) {
      return const Padding(padding: EdgeInsets.all(16), child: CircularProgressIndicator());
    }
    if (rows.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
        child: Text("No other profiles set up yet.", style: textTheme.bodySmall?.copyWith(color: Colors.white54)),
      );
    }
    final byUser = <int, List<Map<dynamic, dynamic>>>{};
    for (final r in rows) {
      byUser.putIfAbsent((r["userId"] as int?) ?? -1, () => []).add(r);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final entry in byUser.entries)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 6),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "${(entry.value.first["supervised"] as bool? ?? false) ? "Kid" : "Adult"} profile (user ${entry.key})",
                  style: textTheme.labelMedium?.copyWith(color: Colors.white70),
                ),
                for (final r in entry.value)
                  Text(
                    "  ${_shortName(r["packageName"] as String?)}: "
                    "${(r["installed"] as bool? ?? false) ? "installed" : "not installed"}"
                    "${(r["protected"] as bool? ?? false) ? ", kept" : ""}",
                    style: textTheme.bodySmall?.copyWith(color: Colors.white54),
                  ),
              ],
            ),
          ),
      ],
    );
  }

  String _shortName(String? pkg) {
    if (pkg == "com.leanbitlab.ltvL") return "Hearth";
    if (pkg == "com.thesiegs.hearthtube") return "HearthTube";
    return pkg ?? "?";
  }
}
