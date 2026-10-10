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

import 'dart:async';

import 'package:flauncher/flauncher_channel.dart';
import 'package:flauncher/l10n/app_localizations.dart';
import 'package:flauncher/providers/settings_service.dart';
import 'package:flauncher/providers/setup_flow_service.dart';
import 'package:flauncher/widgets/settings/adb_command_dialog.dart';
import 'package:flauncher/widgets/settings/app_language_page.dart';
import 'package:flauncher/widgets/settings/backup_restore_page.dart';
import 'package:flauncher/widgets/settings/message_dialog.dart';
import 'package:flauncher/widgets/settings/settings_panel.dart';
import 'package:flauncher/widgets/settings/setup_checklist_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'setup_frame.dart';
import 'setup_snapshot.dart';

/// The flow's screens. Their names are what the resume point stores.
enum SetupScreen { welcome, homeButton, homeButtonBlocked, homeApp, finish }

/// What a screen that sends the owner to Android's settings shows: its explanation, a wait for the owner to come
/// back, or how it went.
enum SetupStepState { intro, waiting, done, notYet, stuck, confirmSkip }

/// How the flow was closed: [openSettings] when the owner asked for Settings on the last screen.
enum SetupFlowResult { closed, openSettings }

/// Hearth's first-run setup (docs/design/first-run-setup.md): one full-screen flow over the home that walks through
/// what Hearth needs from Android, one decision per screen, and comes back to where it was after each trip to
/// Android's settings. The order: Welcome, the Home button (Home Button Fix), the home app, then Finish.
class SetupFlowPage extends StatefulWidget {
  static const String routeName = "setup_flow";

  final SetupMode mode;

  /// The screen to start on, by name (a resume point).
  final String? startAt;

  /// Back from a trip to Android's settings for [startAt]'s step: it reports how that went right away ("It's not on
  /// yet") rather than explaining the step again.
  final bool resumed;

  const SetupFlowPage({super.key, this.mode = SetupMode.full, this.startAt, this.resumed = false});

  /// Opens the flow over whatever is showing, Settings' side panel included.
  static Future<SetupFlowResult?> open(BuildContext context,
          {SetupMode mode = SetupMode.full, String? startAt, bool resumed = false}) =>
      Navigator.of(context, rootNavigator: true).push<SetupFlowResult>(PageRouteBuilder(
        opaque: false,
        settings: const RouteSettings(name: routeName),
        pageBuilder: (_, __, ___) => SetupFlowPage(mode: mode, startAt: startAt, resumed: resumed),
        transitionsBuilder: (_, animation, __, child) => FadeTransition(opacity: animation, child: child),
      ));

  @override
  State<SetupFlowPage> createState() => _SetupFlowPageState();
}

class _SetupFlowPageState extends State<SetupFlowPage> with WidgetsBindingObserver {
  /// The main screens in order. The blocked-switch screen is a side trip from the Home button's.
  static const List<SetupScreen> _order = [
    SetupScreen.welcome,
    SetupScreen.homeButton,
    SetupScreen.homeApp,
    SetupScreen.finish,
  ];

  /// How often the blocked-switch screen checks whether the switch was turned on from a computer.
  static const Duration _pollEvery = Duration(seconds: 2);

  late final FLauncherChannel _channel = context.read<FLauncherChannel>();
  late final SetupFlowService _flow = context.read<SetupFlowService>();

  SetupSnapshot? _snap;
  SetupScreen _screen = SetupScreen.welcome;
  SetupStepState _state = SetupStepState.intro;
  final List<SetupScreen> _history = [];

  /// Skipping the Home button asks "Skip the Home button?" once.
  bool _skipAsked = false;

  /// One of Hearth's own fixes is running (waiting on "Allow debugging?").
  bool _fixing = false;

  /// The TV's address, for `adb connect` on the blocked-switch screen.
  String? _ip;

  /// The button each screen starts on.
  final FocusNode _primary = FocusNode(debugLabel: "setup_primary");
  Timer? _poll;
  Timer? _autoNext;

  bool get _lostFix => widget.mode == SetupMode.lostFix;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _flow.showing = true;
    WidgetsBinding.instance.addPostFrameCallback((_) => _start());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _poll?.cancel();
    _autoNext?.cancel();
    _primary.dispose();
    // Closed while the owner was away in Android's settings: nothing to come back to
    _waitFor(null);
    _flow.showing = false;
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Back from Android's settings (Back, or Hearth brought itself to the front): check the step again
    if (state == AppLifecycleState.resumed) _recheck();
  }

  Future<void> _start() async {
    await _refresh();
    if (!mounted) return;
    final startAt = SetupScreen.values.asNameMap()[widget.startAt];
    if (startAt != null && widget.resumed) {
      _show(startAt, resumed: true);
    } else if (startAt != null && _alreadyDone(startAt)) {
      _showDone(startAt, const Duration(seconds: 1));
    } else if (startAt != null) {
      _show(startAt);
    } else if (_lostFix) {
      _show(SetupScreen.homeButton);
    } else if (widget.mode == SetupMode.rerun) {
      _show(_nextAfter(SetupScreen.welcome));
    } else {
      _show(SetupScreen.welcome);
    }
  }

  Future<void> _refresh() async {
    final l = AppLocalizations.of(context)!;
    final snap = await SetupSnapshot.load(_channel, l);
    if (mounted) setState(() => _snap = snap);
  }

  /// Shows [screen]. [resumed]: picking up where the flow was left, so a step that's done by now says so (and moves
  /// on) rather than being skipped without a word.
  void _show(SetupScreen screen, {bool resumed = false, SetupStepState? state}) {
    _poll?.cancel();
    _autoNext?.cancel();
    setState(() {
      if (_history.isEmpty || _history.last != screen) _history.add(screen);
      _screen = screen;
      _state = state ?? SetupStepState.intro;
    });
    if (!_lostFix && screen != SetupScreen.finish) unawaited(_flow.saveResume(screen.name, widget.mode));
    if (screen == SetupScreen.finish) unawaited(_flow.finish());
    if (screen == SetupScreen.homeButtonBlocked) _startPolling();
    if (resumed && state == null) _recheck(fromResume: true);
    _focusPrimary();
  }

  void _focusPrimary() => WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _primary.context != null) _primary.requestFocus();
      });

  /// Whether a step's screen can be passed over going forward: what it asks for is on already.
  bool _alreadyDone(SetupScreen screen) => switch (screen) {
        SetupScreen.homeButton => _snap?.isDone(SetupStepId.homeButton) ?? false,
        SetupScreen.homeApp => _snap?.isDone(SetupStepId.homeApp) ?? false,
        _ => false,
      };

  SetupScreen _nextAfter(SetupScreen screen) {
    final from = screen == SetupScreen.homeButtonBlocked ? SetupScreen.homeButton : screen;
    for (final candidate in _order.skip(_order.indexOf(from) + 1)) {
      if (!_alreadyDone(candidate)) return candidate;
    }
    return SetupScreen.finish;
  }

  void _next() {
    if (_lostFix) {
      _close();
      return;
    }
    _show(_nextAfter(_screen));
  }

  void _back() {
    if (_fixing) return;
    if (_lostFix || _screen == SetupScreen.welcome) {
      _finishLater();
      return;
    }
    if (_history.length < 2) {
      _finishLater();
      return;
    }
    _history.removeLast();
    _show(_history.removeLast());
  }

  /// Finish later (or Set up later on Welcome): the chip offers to carry on.
  Future<void> _finishLater() async {
    if (_lostFix) {
      await _flow.decide(SetupFlowService.lostFixDecision, SetupChoice.notNow);
    } else {
      await _flow.close();
    }
    _close();
  }

  void _close([SetupFlowResult result = SetupFlowResult.closed]) {
    if (mounted) Navigator.of(context).pop(result);
  }

  /// After a trip to Android's settings: what the step's switch says now. A step the owner hasn't been sent away
  /// from yet keeps its explanation unless it's on already; [fromResume] counts as having been sent away.
  Future<void> _recheck({bool fromResume = false}) async {
    if (_fixing) return;
    await _refresh();
    if (!mounted) return;
    final snap = _snap!;
    final reporting =
        fromResume || (_state != SetupStepState.intro && _state != SetupStepState.confirmSkip);
    switch (_screen) {
      case SetupScreen.homeButton:
      case SetupScreen.homeButtonBlocked:
        final step = snap.step(SetupStepId.homeButton);
        if (step.done) {
          _showDone(SetupScreen.homeButton, const Duration(seconds: 2));
        } else if (_screen == SetupScreen.homeButton && reporting) {
          if (step.blocked) {
            _show(SetupScreen.homeButtonBlocked);
          } else {
            setState(() => _state = step.stuck ? SetupStepState.stuck : SetupStepState.notYet);
            _focusPrimary();
          }
        }
      case SetupScreen.homeApp:
        if (snap.isDone(SetupStepId.homeApp)) {
          _showDone(SetupScreen.homeApp, const Duration(seconds: 1));
        } else if (reporting) {
          setState(() => _state = SetupStepState.notYet);
          _focusPrimary();
        }
      default:
        break;
    }
  }

  /// A step's switch is on: says so, then moves on by itself after [pause].
  void _showDone(SetupScreen screen, Duration pause) {
    _waitFor(null);
    if (_screen != screen) {
      _show(screen, state: SetupStepState.done);
    } else if (_state != SetupStepState.done) {
      setState(() => _state = SetupStepState.done);
      _focusPrimary();
    } else {
      return;
    }
    _autoNext?.cancel();
    _autoNext = Timer(pause, () {
      if (mounted && _screen == screen && _state == SetupStepState.done) _next();
    });
  }

  void _startPolling() {
    _poll?.cancel();
    _poll = Timer.periodic(_pollEvery, (_) {
      if (mounted && _screen == SetupScreen.homeButtonBlocked) _recheck();
    });
    _channel.getLocalIpAddress().then((ip) {
      if (mounted) setState(() => _ip = ip);
    }).catchError((_) => null);
  }

  /// Opens Android's screen for a step and waits for the owner to come back. When the screen won't open, the adb
  /// command instead (and Hearth's own fix when debugging is on).
  Future<void> _openStep(SetupStepId id) async {
    final step = _snap?.step(id);
    if (step == null) return;
    setState(() => _state = SetupStepState.waiting);
    // Its service brings Hearth back when the owner turns the switch on
    await _waitFor(_switchFor(id));
    bool opened;
    try {
      opened = await step.open();
    } catch (_) {
      opened = false;
    }
    if (opened || !mounted) return;
    setState(() => _state = SetupStepState.notYet);
    final fallback = step.adbFallback;
    if (fallback == null) return;
    final l = AppLocalizations.of(context)!;
    final fix = _switchFor(id);
    await showAdbCommandDialog(
      context,
      title: step.title,
      message: l.setupAdbFallback,
      command: fallback,
      actionLabel: fix != null && (_snap?.adbEnabled ?? false) ? l.setupFlowLetHearthFix : null,
      onAction: fix == null ? null : () => _runFixes([fix], id),
    );
    _focusPrimary();
  }

  /// The name of the service a step turns on: what Hearth waits for to come back by itself, and the fix it can run
  /// itself over its own adb. Null for a step without one.
  String? _switchFor(SetupStepId id) => switch (id) {
        SetupStepId.homeButton => "home_button_fix",
        SetupStepId.profilePairing => "profile_pairing",
        SetupStepId.notifications => "notification_access",
        _ => null,
      };

  Future<void> _waitFor(String? what) async {
    try {
      await _channel.setSetupWaitingFor(what);
    } catch (_) {
      // No Android side: the step is checked when Hearth is back in front anyway
    }
  }

  /// Shows exactly what Hearth will run, and runs it when the parent says so. Then waits a moment for [step]'s
  /// service to start, as it does a second or two after its switch is set.
  Future<void> _runFixes(List<String> fixes, SetupStepId step) async {
    final l = AppLocalizations.of(context)!;
    final commands = <String>[];
    for (final fix in fixes) {
      final List<String>? fixCommands;
      try {
        fixCommands = await _channel.getSetupFixCommands(fix);
      } catch (_) {
        return;
      }
      if (fixCommands == null) {
        if (mounted) await showMessageDialog(context, title: l.setupFlowFixFailedTitle, message: l.setupFlowFixFailedBody);
        return;
      }
      commands.addAll(fixCommands);
    }
    if (!mounted) return;
    final go = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l.setupFlowLetHearthFix),
        content: SizedBox(
          width: 520,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(l.setupFlowFixConfirmBody),
                const SizedBox(height: 12),
                SetupCommandBox(lines: commands),
                const SizedBox(height: 12),
                Text(l.setupFlowFixConfirmApproval),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: Text(l.cancel)),
          TextButton(autofocus: true, onPressed: () => Navigator.of(context).pop(true), child: Text(l.setupFlowFixRun)),
        ],
      ),
    );
    if (go != true || !mounted) return;
    setState(() => _fixing = true);
    bool ran = false;
    try {
      await _channel.runSetupFixes(fixes);
      ran = true;
    } on PlatformException {
      ran = false;
    } catch (_) {
      ran = false;
    }
    if (ran) {
      for (int i = 0; i < 5 && mounted; i++) {
        await _refresh();
        if (_snap?.isDone(step) ?? false) break;
        await Future<void>.delayed(const Duration(seconds: 1));
      }
    }
    if (!mounted) return;
    setState(() => _fixing = false);
    if (!ran) {
      await showMessageDialog(context, title: l.setupFlowFixFailedTitle, message: l.setupFlowFixFailedBody);
    }
    setState(() => _state = SetupStepState.waiting);
    await _recheck();
  }

  // --- Screens ---

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _back();
      },
      child: SetupFrame(
        strip: _lostFix || _screen == SetupScreen.welcome ? null : _strip(l),
        finishLaterLabel: l.setupFlowFinishLater,
        onFinishLater: _lostFix || _screen == SetupScreen.welcome || _screen == SetupScreen.finish ? null : _finishLater,
        child: _snap == null
            ? const Padding(padding: EdgeInsets.all(48), child: Center(child: CircularProgressIndicator()))
            : _fixing
                ? _fixingBody(l)
                : KeyedSubtree(key: ValueKey("${_screen.name}_${_state.name}"), child: _body(l)),
      ),
    );
  }

  Widget _body(AppLocalizations l) => switch (_screen) {
        SetupScreen.welcome => _welcome(l),
        SetupScreen.homeButton => _homeButton(l),
        SetupScreen.homeButtonBlocked => _blocked(l),
        SetupScreen.homeApp => _homeApp(l),
        SetupScreen.finish => _finish(l),
      };

  List<SetupStripGroup> _strip(AppLocalizations l) {
    SetupDot dot(SetupStepId id, Set<SetupScreen> screens, String decision) {
      if (screens.contains(_screen)) return SetupDot.here;
      if (_snap?.isDone(id) ?? false) return SetupDot.done;
      if (_flow.choiceFor(decision) == SetupChoice.notNow) return SetupDot.skipped;
      return SetupDot.todo;
    }

    return [
      SetupStripGroup(l.setupFlowStripEssentials, [
        dot(SetupStepId.homeButton, {SetupScreen.homeButton, SetupScreen.homeButtonBlocked},
            SetupFlowService.homeButtonDecision),
        dot(SetupStepId.homeApp, {SetupScreen.homeApp}, SetupFlowService.homeAppDecision),
      ]),
    ];
  }

  Widget _fixingBody(AppLocalizations l) => SetupScreenBody(
        icon: Icons.build_circle_outlined,
        title: l.setupFlowLetHearthFix,
        body: l.setupFlowFixWaiting,
        content: const [Center(child: CircularProgressIndicator())],
        buttons: const [],
      );

  Widget _welcome(AppLocalizations l) {
    final settings = context.watch<SettingsService?>();
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Image.asset("assets/logo.png", height: 72, errorBuilder: (_, __, ___) => const SizedBox(height: 72)),
        const SizedBox(height: 16),
        Text(l.setupFlowWelcomeTitle,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.headlineMedium?.copyWith(color: Colors.white)),
        const SizedBox(height: 12),
        Text(l.setupFlowWelcomeBody,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(color: Colors.white70, height: 1.35)),
        const SizedBox(height: 28),
        Wrap(spacing: 12, alignment: WrapAlignment.center, children: [
          SetupButton(label: l.setupFlowSetUpLater, onPressed: _finishLater),
          SetupButton(
              label: l.setupFlowGetStarted, focusNode: _primary, autofocus: true, onPressed: () => _next()),
        ]),
        const SizedBox(height: 20),
        Wrap(spacing: 12, alignment: WrapAlignment.center, children: [
          if (settings != null)
            SetupButton(
              compact: true,
              icon: Icons.language,
              label: l.setupFlowLanguageLink(AppLanguagePage.nameOf(l, settings.appLanguage)),
              onPressed: () => _openSettingsPage(AppLanguagePage.routeName),
            ),
          SetupButton(
            compact: true,
            icon: Icons.settings_backup_restore,
            label: l.setupFlowRestoreLink,
            onPressed: () => _openSettingsPage(BackupRestorePage.routeName),
          ),
        ]),
        const SizedBox(height: 16),
        Text(l.setupFlowWelcomeTime, style: const TextStyle(color: Colors.white54, fontSize: 13)),
      ],
    );
  }

  /// One of Settings' pages over the flow (the language, a backup to restore); Back returns here.
  Future<void> _openSettingsPage(String route) async {
    await showDialog(
        context: context, barrierColor: Colors.transparent, builder: (_) => SettingsPanel(initialRoute: route));
    _focusPrimary();
  }

  Widget _homeButton(AppLocalizations l) {
    final step = _snap!.step(SetupStepId.homeButton);
    final skip = SetupButton(
      label: _lostFix ? l.notNow : l.setupFlowSkip,
      onPressed: () {
        if (_lostFix) {
          _finishLater();
        } else if (_skipAsked) {
          _skipHomeButton();
        } else {
          setState(() {
            _skipAsked = true;
            _state = SetupStepState.confirmSkip;
          });
          _focusPrimary();
        }
      },
    );
    final open = SetupButton(
      label: l.setupFlowOpenAccessibility,
      focusNode: _primary,
      autofocus: true,
      onPressed: () => _openStep(SetupStepId.homeButton),
    );
    final tryAgain = SetupButton(
        label: l.tryAgain, focusNode: _primary, autofocus: true, onPressed: () => _openStep(SetupStepId.homeButton));
    return switch (_state) {
      SetupStepState.done => SetupScreenBody(
          icon: Icons.check_circle,
          iconColor: Colors.green,
          title: l.setupFlowHomeButtonDone,
          buttons: [SetupButton(label: l.setupFlowNext, focusNode: _primary, autofocus: true, onPressed: _next)],
        ),
      SetupStepState.notYet => SetupScreenBody(
          icon: Icons.info_outline,
          title: l.setupFlowNotOnYetTitle,
          body: l.setupFlowNotOnYetBody,
          content: [_homeButtonPicture(l)],
          buttons: [skip, tryAgain],
        ),
      SetupStepState.stuck => SetupScreenBody(
          icon: Icons.warning_amber_rounded,
          iconColor: Colors.amber,
          title: l.setupFlowStuckTitle,
          body: l.setupFlowStuckBody,
          buttons: [skip, open],
        ),
      SetupStepState.confirmSkip => SetupScreenBody(
          icon: Icons.help_outline,
          title: l.setupFlowSkipHomeButtonTitle,
          body: l.setupFlowSkipHomeButtonBody,
          buttons: [SetupButton(label: l.setupFlowSkipAnyway, onPressed: _skipHomeButton), tryAgain],
        ),
      _ => SetupScreenBody(
          icon: Icons.settings_remote_outlined,
          title: _lostFix ? l.setupFlowLostTitle : l.setupFlowHomeButtonTitle,
          body: _lostFix ? l.setupFlowLostBody : l.setupFlowHomeButtonBody,
          content: [
            if (!_lostFix) SetupBullets(items: [l.setupFlowHomeButtonPoint1, l.setupFlowHomeButtonPoint2]),
            if (step.stuck)
              Text(l.setupFlowStuckBody, style: const TextStyle(color: Colors.amber, fontSize: 13)),
            _homeButtonPicture(l),
            Text(l.setupFlowComesBack, style: const TextStyle(color: Colors.white54, fontSize: 13)),
          ],
          buttons: [skip, open],
        ),
    };
  }

  Widget _homeButtonPicture(AppLocalizations l) => SetupStepsPicture(
        heading: l.setupFlowOnNextScreen,
        steps: [l.setupFlowStepServices, l.setupFlowStepSelect("Hearth Home Button Fix"), l.setupFlowStepEnable],
      );

  Future<void> _skipHomeButton() async {
    await _flow.decide(SetupFlowService.homeButtonDecision, SetupChoice.notNow);
    _next();
  }

  Widget _blocked(AppLocalizations l) {
    final snap = _snap!;
    final adb = snap.adbEnabled;
    final command = "adb shell appops set ${snap.packageName} ACCESS_RESTRICTED_SETTINGS allow";
    return SetupScreenBody(
      icon: Icons.block,
      iconColor: Colors.amber,
      title: l.setupFlowBlockedTitle,
      body: l.setupFlowBlockedBody,
      content: [
        if (adb) Text(l.setupFlowBlockedSelfFixBody, style: const TextStyle(color: Colors.white, fontSize: 14)),
        SetupCommandBox(
          heading: l.setupFlowBlockedComputer,
          lines: [if (_ip != null) "adb connect $_ip", command],
          note: l.setupFlowBlockedComputerThen,
        ),
      ],
      buttons: [
        SetupButton(
          label: l.setupFlowSkipForNow,
          onPressed: () async {
            await _flow.decide(SetupFlowService.homeButtonDecision, SetupChoice.notNow);
            _next();
          },
        ),
        SetupButton(
          label: l.setupFlowOpenAccessibility,
          focusNode: adb ? null : _primary,
          autofocus: !adb,
          onPressed: () => _openStep(SetupStepId.homeButton),
        ),
        if (adb)
          SetupButton(
            label: l.setupFlowLetHearthFix,
            focusNode: _primary,
            autofocus: true,
            onPressed: () => _runFixes(const ["restricted_settings", "home_button_fix"], SetupStepId.homeButton),
          ),
      ],
      below: [Text(l.setupFlowBlockedSkipLine, style: const TextStyle(color: Colors.white54, fontSize: 13))],
    );
  }

  Widget _homeApp(AppLocalizations l) {
    final skip = SetupButton(
      label: l.setupFlowSkip,
      onPressed: () async {
        await _flow.decide(SetupFlowService.homeAppDecision, SetupChoice.notNow);
        _next();
      },
    );
    return switch (_state) {
      SetupStepState.done => SetupScreenBody(
          icon: Icons.check_circle,
          iconColor: Colors.green,
          title: l.setupFlowHomeAppDone,
          buttons: [SetupButton(label: l.setupFlowNext, focusNode: _primary, autofocus: true, onPressed: _next)],
        ),
      SetupStepState.notYet => SetupScreenBody(
          icon: Icons.info_outline,
          title: l.setupFlowNotChosenTitle,
          body: l.setupFlowHomeAppBody,
          buttons: [
            skip,
            SetupButton(
                label: l.tryAgain, focusNode: _primary, autofocus: true, onPressed: () => _openStep(SetupStepId.homeApp)),
          ],
        ),
      _ => SetupScreenBody(
          icon: Icons.home_outlined,
          title: l.setupFlowHomeAppTitle,
          body: l.setupFlowHomeAppBody,
          buttons: [
            skip,
            SetupButton(
              label: l.setupFlowChooseHearth,
              focusNode: _primary,
              autofocus: true,
              onPressed: () => _openStep(SetupStepId.homeApp),
            ),
          ],
        ),
    };
  }

  Widget _finish(AppLocalizations l) {
    final snap = _snap!;
    final where = SetupChecklistPage.breadcrumb(l);
    final on = <String>[
      if (snap.isDone(SetupStepId.homeButton)) l.setupFlowHomeButtonDone,
      if (snap.isDone(SetupStepId.homeApp)) l.setupFlowHomeAppDone,
    ];
    final later = <String>[
      if (!snap.isDone(SetupStepId.homeButton)) snap.step(SetupStepId.homeButton).title,
      if (!snap.isDone(SetupStepId.homeApp)) snap.step(SetupStepId.homeApp).title,
    ];
    const heading = TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.w600);
    return SetupScreenBody(
      icon: Icons.check_circle,
      iconColor: Colors.green,
      title: l.setupFlowFinishTitle,
      body: l.setupFlowFinishBody(where),
      content: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (on.isNotEmpty)
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(l.setupFlowFinishOn, style: heading),
                  const SizedBox(height: 6),
                  SetupBullets(items: on, icon: Icons.check, iconColor: Colors.green),
                ]),
              ),
            if (later.isNotEmpty)
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(l.setupFlowFinishLaterHeading, style: heading),
                  const SizedBox(height: 6),
                  SetupBullets(items: later, icon: Icons.radio_button_unchecked),
                ]),
              ),
          ],
        ),
        Text(l.setupFlowFinishMore, style: const TextStyle(color: Colors.white54, fontSize: 13)),
      ],
      buttons: [
        SetupButton(label: l.setupOpenSettings, onPressed: () => _close(SetupFlowResult.openSettings)),
        SetupButton(label: l.setupFlowGoHome, focusNode: _primary, autofocus: true, onPressed: _close),
      ],
    );
  }
}
