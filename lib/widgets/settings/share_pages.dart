import 'dart:async';
import 'dart:convert';

import 'package:flauncher/flauncher_channel.dart';
import 'package:flauncher/l10n/app_localizations.dart';
import 'package:flauncher/providers/apps_service.dart';
import 'package:flauncher/providers/backup_service.dart';
import 'package:flauncher/providers/settings_service.dart';
import 'package:flauncher/quiet_failure.dart';
import 'package:flauncher/share/share_applier.dart';
import 'package:flauncher/share/share_bundle.dart';
import 'package:flauncher/widgets/parent_pin_dialog.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'focusable_settings_tile.dart';
import 'settings_page.dart';

/// Copying profiles between TVs: the page that offers it (Settings > Profiles), and the two ends of a copy.
class ShareProfilesPage extends StatelessWidget {
  static const String routeName = "share_profiles";

  const ShareProfilesPage({super.key});

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final textTheme = Theme.of(context).textTheme;
    return SettingsPage(
      title: l.shareTitle,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
          child: Text(l.shareIntro, style: textTheme.bodySmall),
        ),
        FocusableSettingsTile(
          autofocus: true,
          leading: const Icon(Icons.upload),
          title: Text(l.shareSendTitle, style: textTheme.bodyMedium),
          trailing: const Icon(Icons.chevron_right, color: Colors.white54),
          onPressed: () => _open(context, ShareSendPage.routeName),
        ),
        FocusableSettingsTile(
          leading: const Icon(Icons.download),
          title: Text(l.shareReceiveTitle, style: textTheme.bodyMedium),
          trailing: const Icon(Icons.chevron_right, color: Colors.white54),
          onPressed: () => _open(context, ShareReceivePage.routeName),
        ),
      ],
    );
  }

  /// A parent is at this TV (the PIN, unless one was entered a moment ago), then the page.
  static Future<void> _open(BuildContext context, String route) async {
    final allowed = await requireParentPin(context);
    if (!allowed || !context.mounted) return;
    Navigator.of(context).pushNamed(route);
  }
}

/// What a copy's screens show between their steps, shared by both ends.
class _Step extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? body;
  final List<Widget> children;

  const _Step({required this.icon, required this.title, this.body, this.children = const []});

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(children: [
            Icon(icon, color: Theme.of(context).colorScheme.primary),
            const SizedBox(width: 12),
            Expanded(child: Text(title, style: textTheme.titleMedium)),
          ]),
          if (body != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(body!, style: textTheme.bodySmall)),
          ...children,
        ],
      ),
    );
  }
}

/// The six digits both TVs show, and the parent's answer.
class _DigitsStep extends StatelessWidget {
  final String digits;
  final void Function(bool same) onAnswer;

  const _DigitsStep({required this.digits, required this.onAnswer});

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final textTheme = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Step(icon: Icons.pin_outlined, title: l.shareDigitsTitle, body: l.shareDigitsBody),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Text(
            digits.length == 6 ? "${digits.substring(0, 3)} ${digits.substring(3)}" : digits,
            textAlign: TextAlign.center,
            style: textTheme.displaySmall?.copyWith(letterSpacing: 6, fontFeatures: const [FontFeature.tabularFigures()]),
          ),
        ),
        FocusableSettingsTile(
          autofocus: true,
          leading: const Icon(Icons.check),
          title: Text(l.shareDigitsMatch, style: textTheme.bodyMedium),
          onPressed: () => onAnswer(true),
        ),
        FocusableSettingsTile(
          leading: const Icon(Icons.close),
          title: Text(l.shareDigitsDiffer, style: textTheme.bodyMedium),
          onPressed: () => onAnswer(false),
        ),
      ],
    );
  }
}

class _Busy extends StatelessWidget {
  final String title;

  const _Busy(this.title);

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.all(24),
        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 3)),
          const SizedBox(width: 16),
          Flexible(child: Text(title, style: Theme.of(context).textTheme.bodyMedium)),
        ]),
      );
}

/// What went wrong, in words for the parent. The code is the Java side's ([ShareService]).
String shareErrorText(AppLocalizations l, String? code) {
  switch (code) {
    case "network":
    case "not_local":
      return l.shareErrorNetwork;
    case "mismatch":
      return l.shareErrorMismatch;
    case "peer_stopped":
      return l.shareErrorStopped;
    case "timeout":
      return l.shareErrorTimeout;
    case "newer":
      return l.shareErrorNewer;
    default:
      return l.shareErrorGeneric;
  }
}

/// The poll both ends share: the copy's status every so often, until the page goes.
mixin _ShareStatusPolling<T extends StatefulWidget> on State<T> {
  Timer? _poll;
  Map<dynamic, dynamic> status = const {"state": "idle"};

  FLauncherChannel? _channel;

  /// Read once while the page is up, so [dispose] can still end the copy.
  FLauncherChannel get channel => _channel ??= context.read<FLauncherChannel>();

  /// Called with each new status; returns nothing, the page moves on from it.
  void onStatus(Map<dynamic, dynamic> next);

  void startPolling() {
    _poll?.cancel();
    _poll = Timer.periodic(const Duration(milliseconds: 700), (_) async {
      try {
        final next = await channel.getShareStatus();
        if (!mounted) return;
        status = next;
        onStatus(next);
      } catch (err) {
        noteFailure('share_pages', err);
      }
    });
  }

  void stopPolling() {
    _poll?.cancel();
    _poll = null;
  }

  @override
  void dispose() {
    stopPolling();
    // The copy and the announcement end with the page: nothing is kept
    unawaited(_channel?.stopShare().catchError((_) {}));
    super.dispose();
  }
}

// ---------------------------------------------------------------------------------------------------------------
// The TV that has the profiles

enum _SendPhase { pick, waiting, digits, working, done, failed }

class ShareSendPage extends StatefulWidget {
  static const String routeName = "share_send";

  const ShareSendPage({super.key});

  @override
  State<ShareSendPage> createState() => _ShareSendPageState();
}

class _ShareSendPageState extends State<ShareSendPage> with _ShareStatusPolling<ShareSendPage> {
  _SendPhase _phase = _SendPhase.pick;
  List<LocalProfile>? _profiles;
  final Set<String> _picked = {};
  String _tvName = "";
  String _address = "";
  String? _digits;
  String? _error;
  Map<String, dynamic>? _report;
  bool _starting = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final list = await channel.getShareProfiles();
      if (mounted) setState(() => _profiles = [for (final p in list) LocalProfile.fromChannel(p)]);
    } catch (err) {
      noteFailure('share_pages', err);
      if (mounted) setState(() => _profiles = const []);
    }
  }

  Future<void> _start() async {
    if (_starting || _picked.isEmpty) return;
    setState(() => _starting = true);
    try {
      final settings = context.read<SettingsService>();
      final backup = context.read<BackupService>();
      final chosen = [for (final p in _profiles!) if (_picked.contains(p.key)) p];
      final profiles = <ShareProfile>[];
      final layouts = <String, Map<String, dynamic>>{};
      final pairings = <String, List<SharedPairing>>{};
      for (var i = 0; i < chosen.length; i++) {
        final local = chosen[i];
        final id = "p${i + 1}";
        profiles.add(ShareProfile(id: id, name: local.name, kids: local.kids));
        // The live profile's layout is in the database; any other profile's was saved when it was switched away from
        final layout = settings.layoutOwner == local.key
            ? await backup.buildBackupData(settings, true)
            : await backup.readProfileLayout(local.key);
        if (layout != null) layouts[id] = layout;
        final choices = await channel.getSharePairings(local.key);
        pairings[id] = [
          for (final c in choices)
            if (c["mode"] == "picker" || (c["appProfile"] as String?)?.isNotEmpty == true)
              SharedPairing(
                packageName: c["pkg"] as String,
                picker: c["mode"] == "picker",
                appProfile: (c["appProfile"] as String?) ?? "",
              ),
        ];
      }
      final tv = await channel.getShareDeviceName();
      final bundle = ShareBundle.build(
        hearth: "",
        tv: tv,
        profiles: profiles,
        layouts: layouts,
        pairings: pairings,
        settingKeys: settings.settingKeys,
      ).encode();
      final started = await channel.startShareSending(bundle);
      if (!mounted) return;
      if (started == null) {
        setState(() {
          _phase = _SendPhase.failed;
          _error = "network";
          _starting = false;
        });
        return;
      }
      setState(() {
        _tvName = (started["name"] as String?) ?? tv;
        final host = started["host"] as String?;
        _address = host == null ? "" : "$host:${started["port"]}";
        _phase = _SendPhase.waiting;
        _starting = false;
      });
      startPolling();
    } catch (err) {
      noteFailure('share_pages', err);
      if (mounted) {
        setState(() {
          _phase = _SendPhase.failed;
          _error = "generic";
          _starting = false;
        });
      }
    }
  }

  @override
  void onStatus(Map<dynamic, dynamic> next) {
    final state = next["state"] as String?;
    setState(() {
      switch (state) {
        case "waiting":
          _phase = _SendPhase.waiting;
        case "digits":
          _phase = _SendPhase.digits;
          _digits = next["digits"] as String?;
        case "working":
          _phase = _SendPhase.working;
        case "done":
          stopPolling();
          _phase = _SendPhase.done;
          try {
            _report = jsonDecode((next["report"] as String?) ?? "{}") as Map<String, dynamic>;
          } catch (_) {
            _report = const {};
          }
        case "failed":
          stopPolling();
          _phase = _SendPhase.failed;
          _error = next["error"] as String?;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final textTheme = Theme.of(context).textTheme;
    final Widget content;
    switch (_phase) {
      case _SendPhase.pick:
        final profiles = _profiles;
        content = profiles == null
            ? _Busy(l.loading)
            : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                _Step(icon: Icons.people_outline, title: l.shareSendPick),
                if (profiles.isEmpty)
                  Padding(padding: const EdgeInsets.all(16), child: Text(l.shareNoProfiles, style: textTheme.bodySmall)),
                for (var i = 0; i < profiles.length; i++)
                  FocusableSettingsTile(
                    autofocus: i == 0,
                    leading: Icon(profiles[i].kids ? Icons.child_care : Icons.person_outline),
                    title: Text(profiles[i].name, style: textTheme.bodyMedium),
                    trailing: Icon(_picked.contains(profiles[i].key) ? Icons.check_box : Icons.check_box_outline_blank),
                    onPressed: () => setState(() {
                      if (!_picked.remove(profiles[i].key)) _picked.add(profiles[i].key);
                    }),
                  ),
                if (profiles.isNotEmpty)
                  FocusableSettingsTile(
                    leading: const Icon(Icons.arrow_forward),
                    title: Text(l.shareContinue,
                        style: textTheme.bodyMedium?.copyWith(color: _picked.isEmpty ? Colors.white38 : null)),
                    onPressed: _picked.isEmpty ? null : _start,
                  ),
              ]);
      case _SendPhase.waiting:
        content = Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          _Step(icon: Icons.tv, title: _tvName, body: l.shareSendWaiting(_tvName), children: [
            if (_address.isNotEmpty)
              Padding(padding: const EdgeInsets.only(top: 12), child: Text(l.shareSendAddress(_address), style: textTheme.bodySmall)),
          ]),
          _Busy(l.loading),
        ]);
      case _SendPhase.digits:
        content = _DigitsStep(digits: _digits ?? "", onAnswer: (same) => channel.confirmShare(same));
      case _SendPhase.working:
        content = _Busy(l.shareWorking);
      case _SendPhase.done:
        final count = (_report?["copied"] as num?)?.toInt() ?? 0;
        final missing = (_report?["missingApps"] as num?)?.toInt() ?? 0;
        content = Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          _Step(icon: Icons.check_circle_outline, title: l.shareDoneTitle, body: l.shareSentBody(count), children: [
            if (missing > 0)
              Padding(padding: const EdgeInsets.only(top: 8), child: Text(l.shareMissingApps(missing), style: textTheme.bodySmall)),
          ]),
          FocusableSettingsTile(
            autofocus: true,
            leading: const Icon(Icons.done),
            title: Text(l.done, style: textTheme.bodyMedium),
            onPressed: () => Navigator.of(context).pop(),
          ),
        ]);
      case _SendPhase.failed:
        content = _FailedStep(error: _error, onClose: () => Navigator.of(context).pop());
    }
    return SettingsPage.custom(title: l.shareSendTitle, body: SingleChildScrollView(child: content));
  }
}

class _FailedStep extends StatelessWidget {
  final String? error;
  final VoidCallback onClose;

  const _FailedStep({required this.error, required this.onClose});

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _Step(icon: Icons.error_outline, title: l.shareErrorTitle, body: shareErrorText(l, error)),
      FocusableSettingsTile(
        autofocus: true,
        leading: const Icon(Icons.close),
        title: Text(l.close, style: Theme.of(context).textTheme.bodyMedium),
        onPressed: onClose,
      ),
    ]);
  }
}

// ---------------------------------------------------------------------------------------------------------------
// The TV that wants them

enum _ReceivePhase { find, connecting, digits, working, preview, applying, done, failed }

class ShareReceivePage extends StatefulWidget {
  static const String routeName = "share_receive";

  const ShareReceivePage({super.key});

  /// "192.168.1.20:8770" (or "192.168.1.20", for the first port) as host and port; null if it isn't one.
  static (String, int)? parseAddress(String? text) {
    if (text == null) return null;
    final match = RegExp(r'^\s*([0-9]{1,3}(?:\.[0-9]{1,3}){3})(?::([0-9]{2,5}))?\s*$').firstMatch(text);
    if (match == null) return null;
    final port = match.group(2) == null ? 8770 : int.parse(match.group(2)!);
    return port < 1 || port > 65535 ? null : (match.group(1)!, port);
  }

  @override
  State<ShareReceivePage> createState() => _ShareReceivePageState();
}

class _ShareReceivePageState extends State<ShareReceivePage> with _ShareStatusPolling<ShareReceivePage> {
  _ReceivePhase _phase = _ReceivePhase.find;
  List<Map<dynamic, dynamic>> _found = const [];
  Timer? _finder;
  String? _digits;
  String? _error;
  ShareBundle? _bundle;
  List<LocalProfile> _locals = const [];
  final Map<String, LocalProfile?> _targets = {};
  bool _layouts = true;
  bool _pairings = true;
  ShareApplyReport? _report;

  @override
  void initState() {
    super.initState();
    _find();
  }

  Future<void> _find() async {
    try {
      await channel.startShareFinding();
    } catch (err) {
      noteFailure('share_pages', err);
    }
    _finder = Timer.periodic(const Duration(seconds: 1), (_) async {
      try {
        final found = await channel.getShareFound();
        if (mounted && _phase == _ReceivePhase.find) setState(() => _found = found);
      } catch (err) {
        noteFailure('share_pages', err);
      }
    });
  }

  @override
  void dispose() {
    _finder?.cancel();
    super.dispose();
  }

  Future<void> _connect(String host, int port) async {
    _finder?.cancel();
    setState(() => _phase = _ReceivePhase.connecting);
    try {
      await channel.startShareReceiving(host, port);
      startPolling();
    } catch (err) {
      noteFailure('share_pages', err);
      if (mounted) {
        setState(() {
          _phase = _ReceivePhase.failed;
          _error = "generic";
        });
      }
    }
  }

  Future<void> _enterAddress() async {
    final l = AppLocalizations.of(context)!;
    final controller = TextEditingController();
    final text = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l.shareEnterAddress),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(l.shareAddressPrompt),
          const SizedBox(height: 12),
          TextField(
            controller: controller,
            autofocus: true,
            keyboardType: TextInputType.url,
            onSubmitted: (value) => Navigator.of(dialogContext).pop(value),
          ),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.of(dialogContext).pop(), child: Text(l.cancel)),
          TextButton(onPressed: () => Navigator.of(dialogContext).pop(controller.text), child: Text(l.shareConnect)),
        ],
      ),
    );
    final address = ShareReceivePage.parseAddress(text);
    if (address != null && mounted) _connect(address.$1, address.$2);
  }

  @override
  void onStatus(Map<dynamic, dynamic> next) {
    final state = next["state"] as String?;
    switch (state) {
      case "digits":
        setState(() {
          _phase = _ReceivePhase.digits;
          _digits = next["digits"] as String?;
        });
      case "working":
        setState(() => _phase = _ReceivePhase.working);
      case "received":
        stopPolling();
        _takeBundle();
      case "failed":
        stopPolling();
        setState(() {
          _phase = _ReceivePhase.failed;
          _error = next["error"] as String?;
        });
    }
  }

  Future<void> _takeBundle() async {
    try {
      final text = await channel.takeShareBundle();
      if (text == null) throw const ShareFormatException("nothing");
      if (!mounted) return;
      final settings = context.read<SettingsService>();
      final bundle = ShareBundle.parse(text, settingKeys: settings.settingKeys);
      final locals = [for (final p in await channel.getShareProfiles()) LocalProfile.fromChannel(p)];
      if (!mounted) return;
      setState(() {
        _bundle = bundle;
        _locals = locals;
        _targets
          ..clear()
          ..addEntries([for (final p in bundle.profiles) MapEntry(p.id, defaultTarget(p, locals))]);
        _phase = _ReceivePhase.preview;
      });
    } on ShareFormatException catch (err) {
      noteFailure('share_pages', err);
      await _failBack(err.newer ? "newer" : "generic");
    } catch (err) {
      noteFailure('share_pages', err);
      await _failBack("generic");
    }
  }

  Future<void> _failBack(String code) async {
    // The other TV is told nothing changed here: it hears the copy end
    try {
      await channel.stopShare();
    } catch (_) {}
    if (mounted) {
      setState(() {
        _phase = _ReceivePhase.failed;
        _error = code;
      });
    }
  }

  /// The next profile of this TV a copied one may go to (the same kind), then "don't copy", then the first again.
  void _cycle(ShareProfile source) {
    final options = [for (final p in _locals) if (p.kids == source.kids) p];
    final current = _targets[source.id];
    final index = current == null ? -1 : options.indexWhere((p) => p.key == current.key);
    setState(() => _targets[source.id] = index + 1 < options.length ? options[index + 1] : null);
  }

  Future<void> _copy() async {
    final bundle = _bundle!;
    setState(() => _phase = _ReceivePhase.applying);
    try {
      final applier = ShareApplier(
        context.read<BackupService>(),
        context.read<SettingsService>(),
        channel,
        () => context.read<AppsService>().refreshState(),
      );
      final report = await applier.apply(
        bundle,
        {for (final e in _targets.entries) if (e.value != null) e.key: e.value!},
        layouts: _layouts,
        pairings: _pairings,
      );
      await channel.sendShareReport(report.toReportJson());
      if (mounted) {
        setState(() {
          _report = report;
          _phase = _ReceivePhase.done;
        });
      }
    } catch (err) {
      noteFailure('share_pages', err);
      await _failBack("generic");
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final textTheme = Theme.of(context).textTheme;
    final Widget content;
    switch (_phase) {
      case _ReceivePhase.find:
        content = Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          _Step(icon: Icons.search, title: l.shareReceiveTitle, body: l.shareFinding),
          for (var i = 0; i < _found.length; i++)
            FocusableSettingsTile(
              autofocus: i == 0,
              leading: const Icon(Icons.tv),
              title: Text("${_found[i]["name"]}", style: textTheme.bodyMedium),
              trailing: Text("${_found[i]["host"]}", style: textTheme.bodySmall),
              onPressed: () => _connect(_found[i]["host"] as String, (_found[i]["port"] as num).toInt()),
            ),
          FocusableSettingsTile(
            autofocus: _found.isEmpty,
            leading: const Icon(Icons.keyboard),
            title: Text(l.shareEnterAddress, style: textTheme.bodyMedium),
            onPressed: _enterAddress,
          ),
        ]);
      case _ReceivePhase.connecting:
        content = _Busy(l.loading);
      case _ReceivePhase.digits:
        content = _DigitsStep(digits: _digits ?? "", onAnswer: (same) => channel.confirmShare(same));
      case _ReceivePhase.working:
        content = _Busy(l.shareWorking);
      case _ReceivePhase.preview:
        content = _preview(l, textTheme);
      case _ReceivePhase.applying:
        content = _Busy(l.shareWorking);
      case _ReceivePhase.done:
        final report = _report!;
        content = Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          _Step(
            icon: Icons.check_circle_outline,
            title: l.shareDoneTitle,
            body: l.shareDoneBody(report.copied, report.backupName),
            children: [
              if (report.missingApps > 0)
                Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(l.shareMissingApps(report.missingApps), style: textTheme.bodySmall)),
            ],
          ),
          FocusableSettingsTile(
            autofocus: true,
            leading: const Icon(Icons.done),
            title: Text(l.done, style: textTheme.bodyMedium),
            onPressed: () => Navigator.of(context).pop(),
          ),
        ]);
      case _ReceivePhase.failed:
        content = _FailedStep(error: _error, onClose: () => Navigator.of(context).pop());
    }
    return SettingsPage.custom(title: l.shareReceiveTitle, body: SingleChildScrollView(child: content));
  }

  Widget _preview(AppLocalizations l, TextTheme textTheme) {
    final bundle = _bundle!;
    final any = _targets.values.any((t) => t != null) && (_layouts || _pairings);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _Step(icon: Icons.account_tree_outlined, title: l.shareMapTitle),
      for (var i = 0; i < bundle.profiles.length; i++)
        FocusableSettingsTile(
          autofocus: i == 0,
          leading: Icon(bundle.profiles[i].kids ? Icons.child_care : Icons.person_outline),
          title: Text(bundle.profiles[i].name, style: textTheme.bodyMedium),
          trailing: Text(_targets[bundle.profiles[i].id]?.name ?? l.shareMapSkip, style: textTheme.bodySmall),
          onPressed: () => _cycle(bundle.profiles[i]),
        ),
      FocusableSettingsTile(
        leading: const Icon(Icons.dashboard_outlined),
        title: Text(l.shareWhatLayout, style: textTheme.bodyMedium),
        trailing: Icon(_layouts ? Icons.check_box : Icons.check_box_outline_blank),
        onPressed: () => setState(() => _layouts = !_layouts),
      ),
      FocusableSettingsTile(
        leading: const Icon(Icons.switch_account),
        title: Text(l.shareWhatPairings, style: textTheme.bodyMedium),
        trailing: Icon(_pairings ? Icons.check_box : Icons.check_box_outline_blank),
        onPressed: () => setState(() => _pairings = !_pairings),
      ),
      FocusableSettingsTile(
        leading: const Icon(Icons.file_download_done),
        title: Text(l.shareCopy, style: textTheme.bodyMedium?.copyWith(color: any ? null : Colors.white38)),
        onPressed: any ? _copy : null,
      ),
    ]);
  }
}
