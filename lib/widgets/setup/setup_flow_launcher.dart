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

import 'package:flauncher/flauncher_channel.dart';
import 'package:flauncher/providers/profile_service.dart';
import 'package:flauncher/providers/settings_service.dart';
import 'package:flauncher/providers/setup_flow_service.dart';
import 'package:flauncher/widgets/settings/settings_panel.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'setup_flow_page.dart';
import 'setup_snapshot.dart';

/// Opens the setup flow over the home when it should show by itself ([SetupFlowService.launch]): the first time
/// Hearth starts on a TV, a step left for Android's settings a moment ago, or the Home button switched off by an
/// update (the old "Home Button Fix is off" dialog). Checked once the first profile check is done (a kids' profile
/// never sees it), on every switch to another profile, whenever Hearth comes back to the front, and when a switch
/// the flow sent the owner for brings Hearth back.
class SetupFlowLauncher extends StatefulWidget {
  final Widget child;
  final FLauncherChannel? channel;

  /// Lets the home load and focus its first tile before the flow takes focus.
  final Duration startDelay;

  const SetupFlowLauncher(
      {super.key, required this.child, this.channel, this.startDelay = const Duration(seconds: 2)});

  /// Opens the flow, and Settings after it when the owner asked for them on its last screen ([fromSettings]: they're
  /// still open underneath).
  static Future<void> openFlow(BuildContext context,
      {SetupMode mode = SetupMode.full, String? startAt, bool resumed = false, bool fromSettings = false}) async {
    final result = await SetupFlowPage.open(context, mode: mode, startAt: startAt, resumed: resumed);
    if (result == SetupFlowResult.openSettings && !fromSettings && context.mounted) {
      await showDialog(context: context, barrierColor: Colors.transparent, builder: (_) => const SettingsPanel());
    }
  }

  @override
  State<SetupFlowLauncher> createState() => _SetupFlowLauncherState();
}

class _SetupFlowLauncherState extends State<SetupFlowLauncher> with WidgetsBindingObserver {
  late final FLauncherChannel _channel = widget.channel ?? context.read<FLauncherChannel>();
  ProfileService? _profiles;
  bool _started = false;
  bool _checking = false;

  /// The lost Home button takes over at most once while Hearth runs.
  bool _lostShown = false;

  /// Whether a check has run since the first profile check, and the profile it was for (null when Hearth can't
  /// tell yet): a switch to another one (from a kid's to a parent's) checks again.
  bool _checkedSettled = false;
  String? _checkedProfile;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    FLauncherChannel.listenForSetupResume((_) => _resumeFlow());
    _profiles = context.read<ProfileService?>();
    _profiles?.addListener(_onProfile);
    Future.delayed(widget.startDelay, () {
      _started = true;
      _check();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _profiles?.removeListener(_onProfile);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _check();
  }

  void _onProfile() {
    final profiles = _profiles!;
    if (profiles.settledOnce && (!_checkedSettled || profiles.activeProfileKey != _checkedProfile)) {
      _check();
    } else if (_lookDue(profiles)) {
      // The "Hi Alex" card is down: the new profile's look can be offered now
      _check();
    }
  }

  Future<void> _check() async {
    final flow = context.read<SetupFlowService?>();
    if (!_started || _checking || !mounted || flow == null || flow.showing) return;
    final profiles = _profiles;
    // Which profile this is decides everything: wait for the first check (_onProfile calls again)
    if (profiles != null && !profiles.settledOnce) return;
    _checking = true;
    try {
      _checkedSettled = true;
      _checkedProfile = profiles?.activeProfileKey;
      final status = await _channel.getHomeButtonFixStatus();
      if (!mounted || flow.showing) return;
      final launch = flow.launch(
        kids: profiles?.isKidsProfile ?? false,
        homeButtonOn: status["enabled"] == true,
        homeButtonSeenBefore: status["seenBefore"] == true,
        hasParentPin: context.read<SettingsService?>()?.hasParentPin ?? false,
      );
      switch (launch) {
        case SetupLaunchFirstRun():
          _open(SetupMode.full);
        case SetupLaunchResume(:final resume):
          _open(resume.mode, startAt: resume.screen, resumed: true);
        case SetupLaunchLostFix():
          if (!_lostShown) {
            _lostShown = true;
            _open(SetupMode.lostFix);
          }
        case SetupLaunchExistingInstall():
          final cardsOn = await SetupSnapshot.loadCardsOn(_channel,
              showContinueWatching: context.read<SettingsService?>()?.showContinueWatching ?? false,
              hasParentPin: context.read<SettingsService?>()?.hasParentPin ?? false,
              kidsProtected: flow.kidsProtected);
          await flow.markExistingInstall(cardsOn);
        case SetupLaunchNothing():
          if (profiles != null && _lookDue(profiles) && flow.flowVersion != null) {
            profiles.lookOffered();
            _open(SetupMode.look);
          }
      }
    } catch (e) {
      // No Android side (tests), or it couldn't say: nothing to open
      debugPrint("Setup flow: $e");
    } finally {
      _checking = false;
    }
  }

  /// A grown-up's first visit to their profile, after the welcome card: one card offers a look for their home.
  bool _lookDue(ProfileService profiles) =>
      profiles.firstVisitKey != null &&
      profiles.firstVisitKey == profiles.activeProfileKey &&
      profiles.transition == null &&
      profiles.incomingName == null &&
      !profiles.isKidsProfile;

  /// A switch the flow sent the owner for came on and brought Hearth back: the flow shows again if it had closed (a
  /// restart in between); an open flow checks the switch by itself.
  void _resumeFlow() {
    final flow = context.read<SetupFlowService?>();
    final resume = flow?.resume;
    if (!mounted || flow == null || flow.showing || resume == null) return;
    _open(resume.mode, startAt: resume.screen, resumed: true);
  }

  void _open(SetupMode mode, {String? startAt, bool resumed = false}) {
    if (!mounted) return;
    SetupFlowLauncher.openFlow(context, mode: mode, startAt: startAt, resumed: resumed);
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
