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

part of 'setup_flow_page.dart';

/// What a card says about itself on its own screen.
class _CardInfo {
  final IconData icon;
  final String title;
  final String benefit;
  final List<String> included;
  final List<String> needs;
  final String? note;

  const _CardInfo(this.icon, this.title, this.benefit, this.included, this.needs, {this.note});
}

/// The flow's optional cards (docs/design/first-run-setup.md, F2 Watching, F5 TV & power, F6 Updates): each is one
/// screen saying what it gives and what it needs, with Not now / Turn on, and its steps come only after Turn on.
/// TV & power is a choice in itself.
extension _CardScreens on _SetupFlowPageState {
  _CardInfo _cardInfo(AppLocalizations l, SetupCard card) => switch (card) {
        SetupCard.watching => _CardInfo(
            Icons.play_circle_outline,
            l.setupCardWatching,
            l.setupFlowWatchingBenefit,
            [l.setupFlowWatchingIncluded1, l.setupFlowWatchingIncluded2],
            [l.setupFlowNeedsQuestion, l.setupFlowNeedsOneSwitch, l.setupFlowNeedsAboutAMinute],
            note: l.setupFlowSearchWorks,
          ),
        SetupCard.tv => _CardInfo(Icons.bedtime_outlined, l.tvPowerTitle, l.setupFlowTvBody, const [], const []),
        SetupCard.updates => _CardInfo(
            Icons.system_update_outlined,
            l.updatesTitle,
            l.setupFlowUpdatesBenefit,
            [l.setupFlowUpdatesIncluded1, l.setupFlowUpdatesIncluded2],
            [l.setupFlowNeedsOneSwitch, l.setupFlowNeedsAboutAMinute],
          ),
      };

  /// Whether all a card turns on is on already.
  bool _cardOn(SetupCard card) => _snap?.cardOn(card, showContinueWatching: _showContinueWatching) ?? false;

  SetupStripGroup _cardStrip(AppLocalizations l, SetupCard card) {
    final screens = _SetupFlowPageState._cardScreens[card]!;
    final here = screens.contains(_screen);
    final choice = _flow.cardChoice(card);
    final SetupDot dot;
    if (here) {
      dot = SetupDot.here;
    } else if (choice == SetupChoice.on || _cardOn(card)) {
      dot = SetupDot.done;
    } else if (choice == SetupChoice.notNow) {
      dot = SetupDot.skipped;
    } else {
      dot = SetupDot.todo;
    }
    // In a card's steps: how far along ("1/2")
    final step = screens.indexOf(_screen);
    return SetupStripGroup(_cardInfo(l, card).title, [dot],
        progress: step > 0 && screens.length > 1 ? "$step/${screens.length - 1}" : null);
  }

  /// A card's own screen: Turn on or Not now; once decided, how it was decided, with Keep or Change.
  Widget _cardScreen(AppLocalizations l, SetupCard card) {
    final info = _cardInfo(l, card);
    final choice = _flow.cardChoice(card);
    final on = choice == SetupChoice.on || _cardOn(card);
    final decided = (choice != null || on) && !_changing;
    const heading = TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.w600);
    return SetupScreenBody(
      icon: info.icon,
      title: info.title,
      body: info.benefit,
      content: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(l.setupFlowCardIncluded, style: heading),
                const SizedBox(height: 6),
                SetupBullets(items: info.included),
              ]),
            ),
            const SizedBox(width: 24),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(l.setupFlowCardNeeds, style: heading),
                const SizedBox(height: 6),
                SetupBullets(items: info.needs),
              ]),
            ),
          ],
        ),
        if (info.note != null) Text(info.note!, style: const TextStyle(color: Colors.white54, fontSize: 13)),
        if (decided)
          Row(children: [
            Icon(on ? Icons.check_circle : Icons.radio_button_unchecked,
                size: 18, color: on ? Colors.green : Colors.white54),
            const SizedBox(width: 8),
            Text(on ? l.setupFlowFinishOn : l.setupFlowCardSkipped,
                style: TextStyle(color: on ? Colors.green : Colors.white70, fontSize: 14)),
          ]),
      ],
      buttons: decided
          ? [
              SetupButton(
                label: l.setupFlowChange,
                onPressed: () {
                  _update(() => _changing = true);
                  _focusPrimary();
                },
              ),
              SetupButton(
                label: l.setupFlowKeep,
                focusNode: _primary,
                autofocus: true,
                onPressed: () => _show(_nextAfter(_screen, leaveCard: true)),
              ),
            ]
          : [
              SetupButton(
                label: l.notNow,
                onPressed: () async {
                  await _flow.decide(card.name, SetupChoice.notNow);
                  _show(_nextAfter(_screen, leaveCard: true));
                },
              ),
              SetupButton(
                label: l.setupFlowTurnOn,
                focusNode: _primary,
                autofocus: true,
                onPressed: () async {
                  await _flow.decide(card.name, SetupChoice.on);
                  _next();
                },
              ),
            ],
    );
  }

  // --- Watching ---

  /// Continue Watching: Android's own question, right over Hearth.
  Widget _continueWatching(AppLocalizations l) {
    final skip = SetupButton(label: l.setupFlowSkip, onPressed: _next);
    final where = "${l.settingsTitle} > ${l.homeScreenTitle} > ${l.continueWatching}";
    return switch (_state) {
      SetupStepState.done => _doneBody(l, l.setupFlowContinueDone),
      SetupStepState.notYet => SetupScreenBody(
          icon: Icons.info_outline,
          title: l.setupFlowContinueDeniedTitle,
          body: l.setupFlowContinueDeniedBody(where),
          content: [
            if (!(_snap?.adbEnabled ?? false))
              SetupCommandBox(
                heading: l.setupFlowBlockedComputer,
                lines: ["adb shell pm grant ${_snap?.packageName} android.permission.READ_TV_LISTINGS"],
              ),
          ],
          buttons: [
            skip,
            if (_snap?.adbEnabled ?? false)
              SetupButton(
                label: l.setupFlowLetHearthFix,
                onPressed: () => _runFixes(const ["watch_next"], (snap) => snap.watchNextAllowed),
              ),
            SetupButton(label: l.tryAgain, focusNode: _primary, autofocus: true, onPressed: _askForWatchNext),
          ],
        ),
      _ => SetupScreenBody(
          icon: Icons.play_circle_outline,
          title: l.continueWatching,
          body: l.setupFlowContinueBody,
          buttons: [
            skip,
            SetupButton(label: l.setupFlowTurnOn, focusNode: _primary, autofocus: true, onPressed: _askForWatchNext),
          ],
        ),
    };
  }

  /// Android's question; its answer is checked as Hearth comes back to the front after it, and here.
  Future<void> _askForWatchNext() async {
    _update(() => _state = SetupStepState.waiting);
    bool granted = false;
    try {
      granted = await _channel.requestWatchNextPermission();
    } catch (_) {}
    if (!mounted) return;
    if (granted) {
      await _recheck();
    } else if (_state == SetupStepState.waiting) {
      _update(() => _state = SetupStepState.notYet);
      _focusPrimary();
    }
  }

  /// What's playing and notifications: notification access, one switch on Android's screen.
  Widget _notifications(AppLocalizations l) => _bounceStepBody(
        l,
        SetupStepId.notifications,
        icon: Icons.notifications_active_outlined,
        title: l.setupFlowNotificationsTitle,
        body: l.setupFlowNotificationsBody("Hearth Notification Service"),
        done: l.setupFlowNotificationsDone,
        fix: "notification_access",
      );

  // --- TV & power ---

  Future<void> _readIdleMinutes() async {
    try {
      final minutes = await _channel.getIdleStandbyMinutes();
      if (mounted) _update(() => _idleMinutes = minutes);
    } catch (_) {
      if (mounted) _update(() => _idleMinutes = 0);
    }
  }

  /// TV & power: the card is the choice. Sleep when idle (needs Home Button Fix to see the remote), Start on boot,
  /// and a way to Google's screensaver settings.
  Widget _tvAndPower(AppLocalizations l) {
    final settings = context.watch<SettingsService?>();
    final homeButtonOn = _snap?.isDone(SetupStepId.homeButton) ?? false;
    final current = _idleMinutes ?? 0;
    // Focus starts on the current choice, or on 2 hours when it's off
    final focused = SetupFlowCards.idleOptions.contains(current) && current != 0 ? current : 120;
    final options = Wrap(spacing: 12, runSpacing: 12, children: [
      for (final minutes in SetupFlowCards.idleOptions)
        SetupButton(
          key: ValueKey("idle_$minutes"),
          label: minutes == 0 ? l.tvPowerSleepOff : l.tvPowerHours(minutes ~/ 60),
          icon: minutes == current ? Icons.radio_button_checked : Icons.radio_button_unchecked,
          focusNode: homeButtonOn && minutes == focused ? _primary : null,
          autofocus: homeButtonOn && minutes == focused,
          onPressed: () async {
            _update(() => _idleMinutes = minutes);
            try {
              await _channel.setIdleStandbyMinutes(minutes);
            } catch (_) {}
          },
        ),
    ]);
    return SetupScreenBody(
      icon: Icons.bedtime_outlined,
      title: l.setupFlowTvTitle,
      body: l.setupFlowTvBody,
      content: [
        // Without Home Button Fix Hearth can't see the remote, so it can't tell when nobody's watching
        homeButtonOn
            ? options
            : ExcludeFocus(child: Opacity(opacity: 0.4, child: IgnorePointer(child: options))),
        if (!homeButtonOn)
          Text(l.setupFlowTvNeedsHomeButton, style: const TextStyle(color: Colors.amber, fontSize: 13)),
        const Divider(color: Colors.white12),
        if (settings != null)
          SetupSwitch(
            label: l.setupFlowStartOnBoot,
            value: settings.startOnBoot,
            focusNode: homeButtonOn ? null : _primary,
            autofocus: !homeButtonOn,
            onChanged: settings.setStartOnBoot,
          ),
        SetupButton(
          compact: true,
          icon: Icons.photo_library_outlined,
          label: l.setupFlowScreensaver,
          onPressed: () => _channel.openScreensaverSettings().catchError((_) => false),
        ),
      ],
      buttons: [
        SetupButton(
          label: l.setupFlowSkip,
          onPressed: () async {
            await _flow.decide(SetupCard.tv.name, SetupChoice.notNow);
            _next();
          },
        ),
        SetupButton(
          label: l.setupFlowNext,
          onPressed: () async {
            await _flow.decide(SetupCard.tv.name, SetupChoice.on);
            _next();
          },
        ),
      ],
    );
  }

  // --- Updates ---

  Widget _installs(AppLocalizations l) => _bounceStepBody(
        l,
        SetupStepId.install,
        icon: Icons.system_update_outlined,
        title: l.setupFlowInstallTitle,
        body: l.setupFlowInstallBody,
        done: l.setupFlowInstallDone,
      );

  /// HearthTube: installed from its latest release through Android's installer, so Hearth can keep it up to date
  /// without asking each time.
  Widget _hearthTube(AppLocalizations l) {
    final updater = context.read<CompanionUpdater?>();
    final app = companionApps.first;
    if (_state == SetupStepState.done || (_snap?.hearthTubeInstalled ?? false)) {
      return SetupScreenBody(
        icon: Icons.check_circle,
        iconColor: Colors.green,
        title: l.setupFlowTubeInstalled,
        content: [
          if (updater != null)
            FutureBuilder<bool>(
              future: updater.autoUpdateEnabled(),
              builder: (context, snapshot) => SetupSwitch(
                label: l.updatesAutoUpdate,
                description: l.updatesAutoUpdateDescription,
                value: snapshot.data ?? true,
                onChanged: (on) async {
                  await updater.setAutoUpdate(on);
                  _update(() {});
                },
              ),
            ),
        ],
        buttons: [SetupButton(label: l.setupFlowNext, focusNode: _primary, autofocus: true, onPressed: _next)],
      );
    }
    final downloading = _state == SetupStepState.waiting;
    final progress = _tubeProgress;
    return SetupScreenBody(
      icon: Icons.smart_display_outlined,
      title: l.setupFlowTubeTitle,
      body: l.setupFlowTubeBody,
      content: [
        if (downloading)
          Row(children: [
            const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
            const SizedBox(width: 12),
            Text(progress == null || progress >= 1
                ? l.updatesInstalling
                : l.updatesDownloadingPercent((progress * 100).round())),
          ]),
        if (_tubeError != null) Text(_tubeError!, style: const TextStyle(color: Colors.redAccent, fontSize: 13)),
      ],
      buttons: [
        SetupButton(label: l.notNow, onPressed: _next),
        if (updater != null && !downloading)
          SetupButton(
            label: _tubeError == null ? l.updatesInstall : l.tryAgain,
            focusNode: _primary,
            autofocus: true,
            onPressed: () => _installHearthTube(updater, app),
          ),
      ],
    );
  }

  Future<void> _installHearthTube(CompanionUpdater updater, CompanionApp app) async {
    final l = AppLocalizations.of(context)!;
    // Android asks for "Install unknown apps" first: that's this card's other step
    if (!(_snap?.isDone(SetupStepId.install) ?? false)) {
      _show(SetupScreen.updatesInstall);
      return;
    }
    _update(() {
      _state = SetupStepState.waiting;
      _tubeProgress = null;
      _tubeError = null;
    });
    try {
      final release = await updater.latestRelease(app);
      if (release == null) throw Exception(l.updatesCheckFailed);
      final apk = await updater.download(app, release, onProgress: (fraction) {
        if (mounted) _update(() => _tubeProgress = fraction);
      });
      if (mounted) _update(() => _tubeProgress = 1);
      if (!await _channel.installApk(apk.path)) throw Exception(l.updatesInstallerNotStarted);
      // A first install asks on Android's screen; nothing tells Hearth it's done, so watch for the app
      for (int i = 0; i < 60 && mounted && _screen == SetupScreen.updatesHearthTube; i++) {
        await Future<void>.delayed(const Duration(seconds: 3));
        if (await _channel.getPackageVersion(app.packageName) != null) {
          await updater.setAutoUpdate(true);
          await _refresh();
          if (mounted && _screen == SetupScreen.updatesHearthTube) _update(() => _state = SetupStepState.done);
          _focusPrimary();
          return;
        }
      }
      if (mounted && _screen == SetupScreen.updatesHearthTube) _update(() => _state = SetupStepState.intro);
    } catch (e) {
      if (!mounted) return;
      _update(() {
        _state = SetupStepState.intro;
        _tubeError = e.toString().replaceFirst("Exception: ", "");
      });
      _focusPrimary();
    }
  }

  // --- Shared ---

  Widget _doneBody(AppLocalizations l, String title) => SetupScreenBody(
        icon: Icons.check_circle,
        iconColor: Colors.green,
        title: title,
        buttons: [SetupButton(label: l.setupFlowNext, focusNode: _primary, autofocus: true, onPressed: _next)],
      );

  /// A step that opens one Android screen ([id]'s) and checks its switch when Hearth is back. [fix]: what Hearth can
  /// run itself when it's still off and debugging is on.
  Widget _bounceStepBody(AppLocalizations l, SetupStepId id,
      {required IconData icon, required String title, required String body, required String done, String? fix}) {
    final skip = SetupButton(label: l.setupFlowSkip, onPressed: _next);
    return switch (_state) {
      SetupStepState.done => _doneBody(l, done),
      SetupStepState.notYet => SetupScreenBody(
          icon: Icons.info_outline,
          title: l.setupFlowNotOnYetTitle,
          body: l.setupFlowNotOnYetBody,
          buttons: [
            skip,
            if (fix != null && (_snap?.adbEnabled ?? false))
              SetupButton(label: l.setupFlowLetHearthFix, onPressed: () => _runFixes([fix], (s) => s.isDone(id))),
            SetupButton(label: l.tryAgain, focusNode: _primary, autofocus: true, onPressed: () => _openStep(id)),
          ],
        ),
      _ => SetupScreenBody(
          icon: icon,
          title: title,
          body: body,
          buttons: [
            skip,
            SetupButton(label: l.setupOpenSettings, focusNode: _primary, autofocus: true, onPressed: () => _openStep(id)),
          ],
        ),
    };
  }
}

/// The flow's fixed choices.
abstract final class SetupFlowCards {
  /// Sleep when idle, in minutes: a few of Settings' choices (TV & power has the rest).
  static const List<int> idleOptions = [0, 60, 120, 240];
}
