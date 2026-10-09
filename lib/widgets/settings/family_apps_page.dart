import 'package:flauncher/l10n/app_localizations.dart';
import 'package:flauncher/flauncher_channel.dart';
import 'package:flauncher/providers/settings_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'focusable_settings_tile.dart';
import 'settings_page.dart';

/// Settings: put Hearth (and HearthTube) on the TV's other Google TV profiles, and take them off again — all
/// parent-controlled. The parent presses Add or Remove; the first Add asks for the one-time on-screen
/// "Allow debugging?" approval. Supervised kids' profiles are kept installed (Google TV would otherwise strip them
/// at each profile start); other adult profiles get a plain install, as a convenience, when the toggle is on.
class FamilyAppsPage extends StatefulWidget {
  static const String routeName = "family_apps";

  const FamilyAppsPage({super.key});

  @override
  State<FamilyAppsPage> createState() => _FamilyAppsPageState();
}

class _FamilyAppsPageState extends State<FamilyAppsPage> with WidgetsBindingObserver {
  late final FLauncherChannel _channel = context.read<FLauncherChannel>();
  List<Map<dynamic, dynamic>>? _state;
  bool _busy = false;

  /// The profile (user id) whose row has focus: it shows what's on that profile.
  int? _selectedUser;

  /// The "What is this?" row is selected: it shows the page's explanation.
  bool _aboutShown = false;

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
    final l = AppLocalizations.of(context)!;
    final includeAdults = context.read<SettingsService>().pushToAdultProfiles;
    final go = await _confirm(
      title: l.familyAppsAddTitle,
      lines: [
        l.familyAppsAddKids,
        if (includeAdults) l.familyAppsAddAdults,
        l.familyAppsAddOnlyOwnApps,
        l.familyAppsAddFamilyLink,
        l.familyAppsAddApproval,
      ],
      action: l.familyAppsAdd,
    );
    if (go != true) return;
    await _run(() => _channel.addHearthToProfiles(includeAdults: includeAdults), adding: true);
  }

  Future<void> _remove() async {
    final l = AppLocalizations.of(context)!;
    final go = await _confirm(
      title: l.familyAppsRemoveTitle,
      lines: [l.familyAppsRemoveBody, l.familyAppsRemoveFirst],
      action: l.remove,
    );
    if (go != true) return;
    await _run(() => _channel.removeHearthFromProfiles(), adding: false);
  }

  /// Uninstall Hearth the safe way: clean up the other profiles first (so nothing is left behind), then open
  /// Android's uninstall screen for Hearth itself. If the cleanup can't run yet, stop and ask for the approval
  /// rather than uninstall into a half-cleaned state.
  Future<void> _uninstallHearth() async {
    final l = AppLocalizations.of(context)!;
    final go = await _confirm(
      title: l.familyAppsUninstallTitle,
      lines: [l.familyAppsUninstallBody, l.familyAppsUninstallWhyHere],
      action: l.uninstall,
    );
    if (go != true) return;
    setState(() => _busy = true);
    try {
      await _channel.removeHearthFromProfiles();
    } on PlatformException {
      if (mounted) {
        setState(() => _busy = false);
        await _showLog(l.familyAppsApprovalFirstTitle, [l.familyAppsApprovalFirstBody, l.familyAppsApprovalFirstRetry]);
      }
      return;
    }
    if (mounted) setState(() => _busy = false);
    await _channel.uninstallHearth();
  }

  Future<void> _run(Future<List<String>> Function() action, {required bool adding}) async {
    final l = AppLocalizations.of(context)!;
    setState(() => _busy = true);
    try {
      final log = await action();
      await _refresh();
      if (mounted) {
        final done = adding ? l.familyAppsAdded : l.familyAppsRemoved;
        await _showLog(adding ? l.familyAppsAddDone : l.familyAppsRemoveDone,
            [log.isEmpty ? l.familyAppsNothingToSetUp : done]);
      }
    } on PlatformException {
      if (mounted) {
        await _showLog(l.familyAppsFailedTitle, [l.familyAppsFailedBody, l.familyAppsFailedRetry]);
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
          // Longer languages can run past the screen's height
          child: SingleChildScrollView(
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
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(context).pop(false), child: Text(AppLocalizations.of(context)!.notNow)),
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
        actions: [
          TextButton(
              autofocus: true,
              onPressed: () => Navigator.of(context).pop(),
              child: Text(AppLocalizations.of(context)!.ok)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final textTheme = Theme.of(context).textTheme;
    final settings = context.watch<SettingsService>();
    final adultsOn = settings.pushToAdultProfiles;
    return SettingsPage(
      title: l.familyAppsTitle,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        FocusableSettingsTile(
          autofocus: true,
          leading: const Icon(Icons.group_add_outlined),
          title: Text(l.familyAppsAddTitle, style: textTheme.bodyMedium),
          trailing: _busy
              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.chevron_right, color: Colors.white54),
          onPressed: _busy ? null : () => _add(),
        ),
        FocusableSettingsTile(
          leading: const Icon(Icons.group_remove_outlined),
          title: Text(l.familyAppsRemoveTitle, style: textTheme.bodyMedium),
          trailing: const Icon(Icons.chevron_right, color: Colors.white54),
          onPressed: _busy ? null : () => _remove(),
        ),
        FocusableSettingsTile(
          leading: const Icon(Icons.delete_outline),
          title: Text(l.familyAppsUninstallTitle, style: textTheme.bodyMedium),
          trailing: const Icon(Icons.chevron_right, color: Colors.white54),
          onPressed: _busy ? null : () => _uninstallHearth(),
        ),
        FocusableSettingsTile(
          leading: Icon(Icons.person_outline, color: adultsOn ? Colors.green : null),
          title: Text(l.familyAppsAlsoAdults, style: textTheme.bodyMedium),
          trailing: Text(adultsOn ? l.familyAppsOn : l.familyAppsOff,
              style: textTheme.bodySmall?.copyWith(color: adultsOn ? Colors.green : Colors.white54)),
          onPressed: () => settings.setPushToAdultProfiles(!adultsOn),
        ),
        // "What is this?": the page explained, shown while this row is selected (it used to sit over the buttons)
        Focus(
          canRequestFocus: false,
          skipTraversal: true,
          onFocusChange: (focused) => setState(() => _aboutShown = focused),
          child: FocusableSettingsTile(
            leading: const Icon(Icons.info_outline),
            title: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(l.familyAppsAbout, style: textTheme.bodyMedium),
                if (_aboutShown) ...[
                  const SizedBox(height: 4),
                  Text(l.familyAppsIntro, style: textTheme.bodySmall?.copyWith(color: Colors.white70)),
                ],
              ],
            ),
          ),
        ),
        const Divider(),
        _stateSection(context),
      ],
    );
  }

  Widget _stateSection(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final textTheme = Theme.of(context).textTheme;
    final rows = _state;
    if (rows == null) {
      return const Padding(padding: EdgeInsets.all(16), child: CircularProgressIndicator());
    }
    if (rows.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
        child: Text(l.familyAppsNoneYet, style: textTheme.bodySmall?.copyWith(color: Colors.white54)),
      );
    }
    final byUser = <int, List<Map<dynamic, dynamic>>>{};
    for (final r in rows) {
      byUser.putIfAbsent((r["userId"] as int?) ?? -1, () => []).add(r);
    }
    // One focusable row per profile: the remote moves down through them and the panel scrolls with it. Each shows
    // its status in a word; the selected one also says what's on it.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final entry in byUser.entries)
          Focus(
            canRequestFocus: false,
            skipTraversal: true,
            onFocusChange: (focused) => setState(() {
              if (focused) {
                _selectedUser = entry.key;
              } else if (_selectedUser == entry.key) {
                _selectedUser = null;
              }
            }),
            child: _profileRow(context, entry.value, selected: _selectedUser == entry.key),
          ),
      ],
    );
  }

  Widget _profileRow(BuildContext context, List<Map<dynamic, dynamic>> apps, {required bool selected}) {
    final l = AppLocalizations.of(context)!;
    final textTheme = Theme.of(context).textTheme;
    final supervised = (apps.first["supervised"] as bool?) ?? false;
    final (String status, Color? color) = switch (_ProfileStatus.of(apps, supervised: supervised)) {
      _ProfileStatus.installed => (l.familyAppsStatusInstalled, Colors.green),
      _ProfileStatus.partial => (l.familyAppsStatusPartial, Colors.amber),
      _ProfileStatus.atRisk => (l.familyAppsStatusAtRisk, Colors.redAccent),
      _ProfileStatus.notInstalled => (l.familyAppsStatusNotInstalled, null),
    };
    final atRisk = color == Colors.redAccent;
    return FocusableSettingsTile(
      leading: Icon(supervised ? Icons.child_care : Icons.person_outline),
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(_profileLabel(l, apps.first), style: textTheme.bodyMedium),
          if (selected) ...[
            const SizedBox(height: 2),
            Text(apps.map((r) => _appLine(l, r)).join("  ·  "),
                style: textTheme.bodySmall?.copyWith(color: Colors.white70)),
            if (atRisk)
              Text(l.familyAppsAtRiskDetail, style: textTheme.bodySmall?.copyWith(color: Colors.redAccent)),
          ],
        ],
      ),
      trailing: Text(status, style: textTheme.bodySmall?.copyWith(color: color)),
    );
  }

  /// A friendly label for a profile row: its name if Hearth knows it, with whether it's a kids or adult profile.
  String _profileLabel(AppLocalizations l, Map<dynamic, dynamic> row) {
    final supervised = (row["supervised"] as bool?) ?? false;
    final name = row["name"] as String?;
    if (name != null && name.isNotEmpty) return supervised ? l.profilesKidsName(name) : l.profilesAdultName(name);
    return supervised ? l.familyAppsUnnamedKids : l.familyAppsUnnamedAdult;
  }

  /// One of Hearth's apps on a profile: whether it's installed there, and whether Hearth keeps it installed.
  String _appLine(AppLocalizations l, Map<dynamic, dynamic> row) {
    final app = _shortName(row["packageName"] as String?);
    final installed = (row["installed"] as bool?) ?? false;
    final kept = (row["protected"] as bool?) ?? false;
    return switch ((installed, kept)) {
      (true, true) => l.familyAppsAppInstalledKept(app),
      (true, false) => l.familyAppsAppInstalled(app),
      (false, true) => l.familyAppsAppNotInstalledKept(app),
      (false, false) => l.familyAppsAppNotInstalled(app),
    };
  }

  String _shortName(String? pkg) {
    if (pkg == "com.leanbitlab.ltvL") return "Hearth";
    if (pkg == "com.thesiegs.hearthtube") return "HearthTube";
    return pkg ?? "?";
  }
}

/// One profile's state, in a word: Hearth's apps are all there (protected, on a kids profile), some are, none are, or
/// a kids profile has one Google TV will remove at its next start (installed but not protected).
enum _ProfileStatus {
  installed,
  partial,
  notInstalled,
  atRisk;

  static _ProfileStatus of(List<Map<dynamic, dynamic>> apps, {required bool supervised}) {
    bool installed(Map<dynamic, dynamic> r) => (r["installed"] as bool?) ?? false;
    bool kept(Map<dynamic, dynamic> r) => (r["protected"] as bool?) ?? false;
    if (supervised && apps.any((r) => installed(r) && !kept(r))) return atRisk;
    final count = apps.where(installed).length;
    if (count == 0) return notInstalled;
    return count == apps.length ? _ProfileStatus.installed : partial;
  }
}
