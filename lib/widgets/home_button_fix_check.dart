import 'package:flauncher/flauncher_channel.dart';
import 'package:flauncher/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';

/// Warns when Home Button Fix (the accessibility service) has been on before but is off now, which is what an
/// update does: Android switches the service off, and an APK installed by the in-app updater is also marked
/// restricted, so the switch can't simply be turned back on. Checked at start and whenever Hearth comes back
/// to the front; shown at most once while Hearth runs.
class HomeButtonFixCheck extends StatefulWidget {
  final Widget child;
  final FLauncherChannel? channel;

  final Duration startDelay;

  const HomeButtonFixCheck(
      {super.key, required this.child, this.channel, this.startDelay = const Duration(seconds: 2)});

  @override
  State<HomeButtonFixCheck> createState() => _HomeButtonFixCheckState();
}

class _HomeButtonFixCheckState extends State<HomeButtonFixCheck> with WidgetsBindingObserver {
  late final FLauncherChannel _channel;
  bool _shown = false;
  bool _checking = false;
  // The debug build has its own package name. Read ahead so the dialog doesn't wait for it.
  String _packageName = 'com.leanbitlab.ltvL';

  @override
  void initState() {
    super.initState();
    _channel = widget.channel ?? context.read<FLauncherChannel>();
    WidgetsBinding.instance.addObserver(this);
    _readPackageName();
    // Let the home screen load and focus its first tile before the dialog takes focus.
    Future.delayed(widget.startDelay, _check);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _check();
  }

  Future<void> _check() async {
    if (_shown || _checking) return;
    _checking = true;
    try {
      final status = await _channel.getHomeButtonFixStatus();
      final bool lost = status["seenBefore"] == true && status["enabled"] == false;
      if (!lost || !mounted || _shown) return;
      _shown = true;
      await _showDialog(status["restricted"] == true, stuck: status["listedButStopped"] == true);
    } catch (_) {
      // No platform side (tests) or an older Android: nothing to warn about.
    } finally {
      _checking = false;
    }
  }

  Future<void> _readPackageName() async {
    try {
      _packageName = (await PackageInfo.fromPlatform()).packageName;
    } catch (e) {
      debugPrint('Home Button Fix: no package info: $e');
    }
  }

  Future<void> _showDialog(bool restricted, {bool stuck = false}) async {
    final String command = 'adb shell appops set $_packageName ACCESS_RESTRICTED_SETTINGS allow';
    final String? choice = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(AppLocalizations.of(dialogContext)!.homeButtonFixOffTitle),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              AppLocalizations.of(dialogContext)!.homeButtonFixOffBody,
              style: const TextStyle(fontSize: 13, height: 1.4),
            ),
            if (stuck) ...[
              const SizedBox(height: 12),
              Text(
                AppLocalizations.of(dialogContext)!.homeButtonFixStuck,
                style: const TextStyle(fontSize: 13, height: 1.4),
              ),
            ],
            if (restricted) ...[
              const SizedBox(height: 12),
              Text(
                AppLocalizations.of(dialogContext)!.homeButtonFixRestricted,
                style: const TextStyle(fontSize: 13, height: 1.4),
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.black45,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: Colors.white24),
                ),
                child: SelectableText(
                  command,
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 11, color: Colors.amberAccent),
                ),
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop('forget'),
            child: Text(AppLocalizations.of(dialogContext)!.homeButtonFixDontRemind),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text(AppLocalizations.of(dialogContext)!.notNow),
          ),
          TextButton(
            autofocus: true,
            onPressed: () => Navigator.of(dialogContext).pop('open'),
            child: Text(AppLocalizations.of(dialogContext)!.homeButtonFixOpenSettings),
          ),
        ],
      ),
    );
    try {
      if (choice == 'open') {
        await _channel.requestAccessibilityPermission();
      } else if (choice == 'forget') {
        await _channel.forgetHomeButtonFix();
      }
    } catch (e) {
      debugPrint('Home Button Fix: $e');
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
