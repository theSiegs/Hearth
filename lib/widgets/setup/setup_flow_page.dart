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
import 'package:flauncher/providers/companion_updater.dart';
import 'package:flauncher/providers/home_looks.dart';
import 'package:flauncher/providers/open_meteo_client.dart';
import 'package:flauncher/providers/settings_service.dart';
import 'package:flauncher/providers/setup_flow_service.dart';
import 'package:flauncher/providers/wallpaper_service.dart';
import 'package:flauncher/providers/watch_next_service.dart';
import 'package:flauncher/providers/weather_service.dart';
import 'package:flauncher/widgets/settings/adb_command_dialog.dart';
import 'package:flauncher/widgets/settings/app_language_page.dart';
import 'package:flauncher/widgets/parent_pin_dialog.dart';
import 'package:flauncher/widgets/settings/backup_restore_page.dart';
import 'package:flauncher/widgets/settings/family_apps_page.dart';
import 'package:flauncher/widgets/settings/ha_phone_setup_dialog.dart';
import 'package:flauncher/widgets/settings/look_settings_page.dart';
import 'package:flauncher/widgets/settings/message_dialog.dart';
import 'package:flauncher/widgets/settings/profile_pairing_page.dart';
import 'package:flauncher/widgets/settings/settings_panel.dart';
import 'package:flauncher/widgets/settings/setup_checklist_page.dart';
import 'package:flauncher/widgets/settings/weather_location_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'setup_frame.dart';
import 'setup_snapshot.dart';

part 'setup_flow_cards.dart';

/// The flow's screens. Their names are what the resume point stores.
enum SetupScreen {
  welcome,
  homeButton,
  homeButtonBlocked,
  homeApp,
  family,
  familyPin,
  familyPairing,
  familyPairingBlocked,
  familyVoice,
  familyKids,
  watching,
  watchingContinue,
  watchingNotifications,
  look,
  lookWeather,
  smartHome,
  haAlerts,
  haDashboard,
  haStatus,
  tv,
  updates,
  updatesInstall,
  updatesHearthTube,
  finish,
}

/// What a screen that sends the owner to Android's settings shows: its explanation, a wait for the owner to come
/// back, or how it went.
enum SetupStepState { intro, waiting, done, notYet, stuck, confirmSkip }

/// How the flow was closed: [openSettings] when the owner asked for Settings on the last screen.
enum SetupFlowResult { closed, openSettings }

/// Hearth's first-run setup (docs/design/first-run-setup.md): one full-screen flow over the home that walks through
/// what Hearth needs from Android, one decision per screen, and comes back to where it was after each trip to
/// Android's settings. The order: Welcome, the essentials (the Home button, then the home app), the optional cards
/// (each a Not now / Turn on choice, its steps only after Turn on), then Finish.
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
    SetupScreen.family,
    SetupScreen.familyPin,
    SetupScreen.familyPairing,
    SetupScreen.familyVoice,
    SetupScreen.familyKids,
    SetupScreen.watching,
    SetupScreen.watchingContinue,
    SetupScreen.watchingNotifications,
    SetupScreen.look,
    SetupScreen.lookWeather,
    SetupScreen.smartHome,
    SetupScreen.haAlerts,
    SetupScreen.haDashboard,
    SetupScreen.haStatus,
    SetupScreen.tv,
    SetupScreen.updates,
    SetupScreen.updatesInstall,
    SetupScreen.updatesHearthTube,
    SetupScreen.finish,
  ];

  /// Each card's own screen, then its steps (shown only after Turn on).
  static const Map<SetupCard, List<SetupScreen>> _cardScreens = {
    SetupCard.family: [
      SetupScreen.family,
      SetupScreen.familyPin,
      SetupScreen.familyPairing,
      SetupScreen.familyVoice,
      SetupScreen.familyKids,
    ],
    SetupCard.watching: [SetupScreen.watching, SetupScreen.watchingContinue, SetupScreen.watchingNotifications],
    SetupCard.home: [SetupScreen.look, SetupScreen.lookWeather],
    SetupCard.smartHome: [SetupScreen.smartHome, SetupScreen.haAlerts, SetupScreen.haDashboard, SetupScreen.haStatus],
    SetupCard.tv: [SetupScreen.tv],
    SetupCard.updates: [SetupScreen.updates, SetupScreen.updatesInstall, SetupScreen.updatesHearthTube],
  };

  /// The steps that send the owner to one Android screen and check the switch when Hearth is back.
  static const Map<SetupScreen, SetupStepId> _bounceSteps = {
    SetupScreen.homeApp: SetupStepId.homeApp,
    SetupScreen.watchingNotifications: SetupStepId.notifications,
    SetupScreen.updatesInstall: SetupStepId.install,
    SetupScreen.familyVoice: SetupStepId.voice,
  };

  /// The screens that say Android blocked a switch, a side trip from the switch's own screen.
  static const Map<SetupScreen, SetupScreen> _blockedFrom = {
    SetupScreen.homeButtonBlocked: SetupScreen.homeButton,
    SetupScreen.familyPairingBlocked: SetupScreen.familyPairing,
  };

  /// A screen, or for a blocked-switch screen the switch's own.
  static SetupScreen _mainScreen(SetupScreen screen) => _blockedFrom[screen] ?? screen;

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

  /// A decided card shows Turn on / Not now again (after Change).
  bool _changing = false;

  /// TV & power's idle standby, in minutes (0: off), once read.
  int? _idleMinutes;

  /// The look as it was when the look screen opened, and the one previewed on the home behind it (focused, not
  /// chosen yet).
  HomeLookSnapshot? _lookBefore;
  HomeLook? _previewing;
  SettingsService? _lookSettings;

  /// What the kids' step left on each profile, once Hearth was put on them.
  List<Map<dynamic, dynamic>>? _kidsRows;

  /// How the Home Assistant test pop-up went: null when it showed (or none was sent).
  String? _haTestResult;

  /// A backup was restored from Welcome: its look came with it, so the look screen isn't shown.
  bool _restored = false;

  /// HearthTube's download, as a fraction, while it downloads; and why it couldn't be installed.
  double? _tubeProgress;
  String? _tubeError;

  /// The button each screen starts on. A new node for each screen: the old screen's button lets go of its node only
  /// after the new one has taken it, which would leave the new button without it.
  FocusNode _primary = FocusNode(debugLabel: "setup_primary");
  Timer? _poll;
  Timer? _autoNext;

  bool get _lostFix => widget.mode == SetupMode.lostFix;

  /// A grown-up's first visit to their profile: only the look screen.
  bool get _lookOnly => widget.mode == SetupMode.look;

  /// One screen by itself, with no strip, no Finish later and nothing to resume.
  bool get _single => _lostFix || _lookOnly;

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
    // Closed while a look was only being previewed: the home goes back to how it was
    _endPreview();
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
    } else if (_lookOnly) {
      _show(SetupScreen.look);
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
    if (_screen == SetupScreen.look && screen != SetupScreen.look) _endPreview();
    setState(() {
      if (_history.isEmpty || _history.last != screen) _history.add(screen);
      _screen = screen;
      _state = state ?? SetupStepState.intro;
      _changing = false;
      _tubeError = null;
      _haTestResult = null;
    });
    if (screen == SetupScreen.tv) _readIdleMinutes();
    if (screen == SetupScreen.look) _startPreview();
    if (screen == SetupScreen.haAlerts) _readIp();
    if (!_single && screen != SetupScreen.finish) unawaited(_flow.saveResume(screen.name, widget.mode));
    if (screen == SetupScreen.finish) unawaited(_flow.finish());
    if (_blockedFrom.containsKey(screen)) _startPolling();
    if (resumed && state == null) _recheck(fromResume: true);
    _focusPrimary();
  }

  void _focusPrimary() {
    if (!mounted) return;
    final old = _primary;
    setState(() => _primary = FocusNode(debugLabel: "setup_primary"));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      old.dispose();
      if (mounted && _primary.context != null) _primary.requestFocus();
    });
  }

  /// Whether a step's screen can be passed over going forward: what it asks for is on already. A card's own screen
  /// never is (it says it's on, with Keep).
  bool _alreadyDone(SetupScreen screen) {
    final snap = _snap;
    if (snap == null) return false;
    return switch (screen) {
      SetupScreen.homeButton => snap.isDone(SetupStepId.homeButton),
      SetupScreen.homeApp => snap.isDone(SetupStepId.homeApp),
      SetupScreen.watchingContinue => snap.watchNextAllowed && _showContinueWatching,
      SetupScreen.watchingNotifications => snap.isDone(SetupStepId.notifications),
      SetupScreen.updatesInstall => snap.isDone(SetupStepId.install),
      SetupScreen.updatesHearthTube => snap.hearthTubeInstalled,
      SetupScreen.familyPin => _hasParentPin,
      SetupScreen.familyPairing => snap.isDone(SetupStepId.profilePairing),
      // Only Netflix needs it, and only once Profile Pairing is on
      SetupScreen.familyVoice =>
        !snap.netflix || !snap.isDone(SetupStepId.profilePairing) || snap.isDone(SetupStepId.voice),
      SetupScreen.familyKids => snap.kidsProfiles == 0 || snap.kidsProfiles <= _flow.kidsProtected,
      SetupScreen.look => _restored,
      SetupScreen.haAlerts => snap.haAlerts,
      SetupScreen.haDashboard => snap.haPanel && (context.read<SettingsService?>()?.haPanelEnabled ?? false),
      SetupScreen.haStatus => snap.haStatus,
      SetupScreen.lookWeather => _weatherSet,
      _ => false,
    };
  }

  bool get _showContinueWatching => context.read<SettingsService?>()?.showContinueWatching ?? false;

  bool get _hasParentPin => context.read<SettingsService?>()?.hasParentPin ?? false;

  /// Whether a card is offered on this TV: the family card is Google TV's only (profiles, Profile Pairing).
  bool _cardShown(SetupCard card) => card != SetupCard.family || (_snap?.googleTv ?? false);
  /// The card a screen belongs to, if any.
  SetupCard? _cardOf(SetupScreen screen) {
    for (final entry in _cardScreens.entries) {
      if (entry.value.contains(_mainScreen(screen))) return entry.key;
    }
    return null;
  }

  /// The next screen to show after [screen]: steps that are done are passed over, and so are a card's steps unless the
  /// owner turned it on. [leaveCard]: past the rest of [screen]'s card too (Not now, Keep).
  SetupScreen _nextAfter(SetupScreen screen, {bool leaveCard = false}) {
    final from = _mainScreen(screen);
    final leaving = leaveCard ? _cardOf(from) : null;
    for (final candidate in _order.skip(_order.indexOf(from) + 1)) {
      final card = _cardOf(candidate);
      if (leaving != null && card == leaving) continue;
      if (card != null && !_cardShown(card)) continue;
      final isStep = card != null && _cardScreens[card]!.first != candidate;
      if (isStep && _flow.cardChoice(card) != SetupChoice.on) continue;
      if (!_alreadyDone(candidate)) return candidate;
    }
    return SetupScreen.finish;
  }

  void _next() {
    if (_single) {
      _close();
      return;
    }
    _show(_nextAfter(_screen));
  }

  void _back() {
    if (_fixing) return;
    if (_single || _screen == SetupScreen.welcome) {
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
    } else if (_lookOnly) {
      // Nothing to carry on with: the profile keeps the look it started with
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
      case SetupScreen.familyPairing:
      case SetupScreen.familyPairingBlocked:
        final step = snap.step(SetupStepId.profilePairing);
        if (step.done) {
          // No moving on by itself: the screen says how pairing works, and offers to check the pairings
          _showDone(SetupScreen.familyPairing, null);
        } else if (_screen == SetupScreen.familyPairing && reporting) {
          if (step.blocked) {
            _show(SetupScreen.familyPairingBlocked);
          } else {
            setState(() => _state = SetupStepState.notYet);
            _focusPrimary();
          }
        }
      case SetupScreen.familyKids:
        // Back from turning debugging on: on to adding Hearth
        if (_state == SetupStepState.waiting && snap.adbEnabled) {
          setState(() => _state = SetupStepState.intro);
          _focusPrimary();
        }
      case SetupScreen.homeApp:
      case SetupScreen.familyVoice:
      case SetupScreen.watchingNotifications:
      case SetupScreen.updatesInstall:
        if (snap.isDone(_bounceSteps[_screen]!)) {
          _showDone(_screen, const Duration(seconds: 1));
        } else if (reporting) {
          setState(() => _state = SetupStepState.notYet);
          _focusPrimary();
        }
      case SetupScreen.watchingContinue:
        // Allowed (the dialog, or Hearth's own fix): the row goes on, as the owner asked for it
        if (snap.watchNextAllowed && reporting) {
          await context.read<SettingsService?>()?.setShowContinueWatching(true);
          if (mounted) context.read<WatchNextService?>()?.refresh();
          _showDone(SetupScreen.watchingContinue, const Duration(seconds: 1));
        } else if (reporting && _state != SetupStepState.done) {
          setState(() => _state = SetupStepState.notYet);
          _focusPrimary();
        }
      default:
        break;
    }
  }

  /// A step's switch is on: says so, then moves on by itself after [pause] (null: on Next).
  void _showDone(SetupScreen screen, Duration? pause) {
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
    if (pause == null) return;
    _autoNext = Timer(pause, () {
      if (mounted && _screen == screen && _state == SetupStepState.done) _next();
    });
  }

  void _startPolling() {
    _poll?.cancel();
    _poll = Timer.periodic(_pollEvery, (_) {
      if (mounted && _blockedFrom.containsKey(_screen)) _recheck();
    });
    _readIp();
  }

  /// The TV's address, for `adb connect` and for Home Assistant's notifications integration.
  void _readIp() {
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
      onAction: fix == null ? null : () => _runFixes([fix], (snap) => snap.isDone(id)),
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

  /// Shows exactly what Hearth will run, and runs it when the parent says so. Then waits a moment for what it turned
  /// on to show as [done] (a service starts a second or two after its switch is set), and checks the screen again.
  Future<void> _runFixes(List<String> fixes, bool Function(SetupSnapshot snap) done) async {
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
        if (_snap != null && done(_snap!)) break;
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
        strip: _single || _screen == SetupScreen.welcome ? null : _strip(l),
        finishLaterLabel: l.setupFlowFinishLater,
        onFinishLater: _single || _screen == SetupScreen.welcome || _screen == SetupScreen.finish ? null : _finishLater,
        // The look screen shows the home behind it as it'll look
        preview: _screen == SetupScreen.look,
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
        SetupScreen.homeButtonBlocked => _blocked(l, SetupStepId.homeButton),
        SetupScreen.homeApp => _homeApp(l),
        SetupScreen.family => _cardScreen(l, SetupCard.family),
        SetupScreen.familyPin => _parentPin(l),
        SetupScreen.familyPairing => _pairing(l),
        SetupScreen.familyPairingBlocked => _blocked(l, SetupStepId.profilePairing),
        SetupScreen.familyVoice => _voice(l),
        SetupScreen.familyKids => _kids(l),
        SetupScreen.watching => _cardScreen(l, SetupCard.watching),
        SetupScreen.watchingContinue => _continueWatching(l),
        SetupScreen.watchingNotifications => _notifications(l),
        SetupScreen.look => _lookScreen(l),
        SetupScreen.lookWeather => _weather(l),
        SetupScreen.smartHome => _cardScreen(l, SetupCard.smartHome),
        SetupScreen.haAlerts => _haAlertsScreen(l),
        SetupScreen.haDashboard => _haDashboard(l),
        SetupScreen.haStatus => _haStatusScreen(l),
        SetupScreen.tv => _tvAndPower(l),
        SetupScreen.updates => _cardScreen(l, SetupCard.updates),
        SetupScreen.updatesInstall => _installs(l),
        SetupScreen.updatesHearthTube => _hearthTube(l),
        SetupScreen.finish => _finish(l),
      };

  /// For the card screens (in setup_flow_cards.dart): setState isn't theirs to call.
  void _update(VoidCallback change) => setState(change);

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
      for (final card in SetupCard.values)
        if (_cardShown(card)) _cardStrip(l, card),
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

  /// One of Settings' pages over the flow (the language, a backup to restore, the look); Back returns here.
  Future<void> _openSettingsPage(String route) async {
    final settings = context.read<SettingsService?>();
    final before = settings == null ? null : HomeLookSnapshot.of(settings);
    await showDialog(
        context: context, barrierColor: Colors.transparent, builder: (_) => SettingsPanel(initialRoute: route));
    // A restored backup brought its look along: the look card has nothing left to ask
    if (route == BackupRestorePage.routeName && before != null && !HomeLookSnapshot.of(settings!).sameAs(before)) {
      _restored = true;
      await _flow.decide(SetupCard.home.name, SetupChoice.on);
    }
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
    // With debugging on, Hearth can turn its switch on itself
    final selfFix = (_snap?.adbEnabled ?? false)
        ? SetupButton(
            label: l.setupFlowLetHearthFix,
            onPressed: () => _runFixes(const ["home_button_fix"], (snap) => snap.isDone(SetupStepId.homeButton)),
          )
        : null;
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
          buttons: [skip, if (selfFix != null) selfFix, tryAgain],
        ),
      SetupStepState.stuck => SetupScreenBody(
          icon: Icons.warning_amber_rounded,
          iconColor: Colors.amber,
          title: l.setupFlowStuckTitle,
          body: l.setupFlowStuckBody,
          buttons: [skip, if (selfFix != null) selfFix, open],
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

  /// Android blocked [id]'s switch (Home Button Fix, or Profile Pairing): lifting the block needs adb.
  Widget _blocked(AppLocalizations l, SetupStepId id) {
    final snap = _snap!;
    final adb = snap.adbEnabled;
    final homeButton = id == SetupStepId.homeButton;
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
            if (homeButton) await _flow.decide(SetupFlowService.homeButtonDecision, SetupChoice.notNow);
            _next();
          },
        ),
        SetupButton(
          label: l.setupFlowOpenAccessibility,
          focusNode: adb ? null : _primary,
          autofocus: !adb,
          onPressed: () => _openStep(id),
        ),
        if (adb)
          SetupButton(
            label: l.setupFlowLetHearthFix,
            focusNode: _primary,
            autofocus: true,
            onPressed: () => _runFixes(["restricted_settings", _switchFor(id)!], (snap) => snap.isDone(id)),
          ),
      ],
      below: [
        if (homeButton) Text(l.setupFlowBlockedSkipLine, style: const TextStyle(color: Colors.white54, fontSize: 13)),
      ],
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
    // A card counts as on when it's all on, or the owner turned it on (some of its steps may have been skipped)
    bool cardOn(SetupCard card) => _flow.cardChoice(card) == SetupChoice.on || _cardOn(card);
    final on = <String>[
      if (snap.isDone(SetupStepId.homeButton)) l.setupFlowHomeButtonDone,
      if (snap.isDone(SetupStepId.homeApp)) l.setupFlowHomeAppDone,
      for (final card in SetupCard.values)
        if (_cardShown(card) && cardOn(card)) _cardInfo(l, card).title,
    ];
    final later = <String>[
      if (!snap.isDone(SetupStepId.homeButton)) snap.step(SetupStepId.homeButton).title,
      if (!snap.isDone(SetupStepId.homeApp)) snap.step(SetupStepId.homeApp).title,
      for (final card in SetupCard.values)
        if (_cardShown(card) && !cardOn(card)) _cardInfo(l, card).title,
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
