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

  /// The main button, when it isn't "Turn on".
  final String? turnOn;

  const _CardInfo(this.icon, this.title, this.benefit, this.included, this.needs, {this.note, this.turnOn});
}

/// The flow's optional cards (docs/design/first-run-setup.md, F2 Watching, F5 TV & power, F6 Updates): each is one
/// screen saying what it gives and what it needs, with Not now / Turn on, and its steps come only after Turn on.
/// TV & power is a choice in itself.
extension _CardScreens on _SetupFlowPageState {
  _CardInfo _cardInfo(AppLocalizations l, SetupCard card) => switch (card) {
        SetupCard.family => _CardInfo(
            Icons.family_restroom,
            l.setupCardFamily,
            l.setupFlowFamilyBenefit,
            [
              l.setupFlowFamilyIncluded1,
              l.setupFlowFamilyIncluded2,
              if ((_snap?.kidsProfiles ?? 0) > 0) l.setupFlowFamilyIncluded3,
            ],
            [l.setupFlowNeedsPin, l.setupFlowNeedsOneSwitch, l.setupFlowNeedsTwoMinutes],
          ),
        SetupCard.watching => _CardInfo(
            Icons.play_circle_outline,
            l.setupCardWatching,
            l.setupFlowWatchingBenefit,
            [l.setupFlowWatchingIncluded1, l.setupFlowWatchingIncluded2],
            [l.setupFlowNeedsQuestion, l.setupFlowNeedsOneSwitch, l.setupFlowNeedsAboutAMinute],
            note: l.setupFlowSearchWorks,
          ),
        SetupCard.home =>
          _CardInfo(Icons.palette_outlined, l.setupCardHome, l.setupFlowLookTitle, const [], const []),
        SetupCard.smartHome => _CardInfo(
            Icons.cottage_outlined,
            l.setupCardSmartHome,
            l.setupFlowHaBenefit,
            [l.setupFlowHaIncluded1, l.setupFlowHaIncluded2, l.setupFlowHaIncluded3],
            [l.setupFlowNeedsPhone, l.setupFlowNeedsFewMinutes],
            turnOn: l.setupFlowHaUse,
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
  bool _cardOn(SetupCard card) =>
      _snap?.cardOn(card,
          showContinueWatching: _showContinueWatching,
          hasParentPin: _hasParentPin,
          kidsProtected: _flow.kidsProtected) ??
      false;

  SetupStripGroup _cardStrip(AppLocalizations l, SetupCard card) {
    final screens = _SetupFlowPageState._cardScreens[card]!;
    final here = screens.contains(_SetupFlowPageState._mainScreen(_screen));
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
    final step = screens.indexOf(_SetupFlowPageState._mainScreen(_screen));
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
                label: info.turnOn ?? l.setupFlowTurnOn,
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

  // --- Your family ---

  Widget _parentPin(AppLocalizations l) {
    if (_state == SetupStepState.done) return _doneBody(l, l.setupFlowPinDone);
    return SetupScreenBody(
      icon: Icons.pin_outlined,
      title: l.setupFlowPinTitle,
      body: l.setupFlowPinBody,
      buttons: [
        SetupButton(label: l.setupFlowSkip, onPressed: _next),
        SetupButton(label: l.setupFlowPinChoose, focusNode: _primary, autofocus: true, onPressed: _chooseParentPin),
      ],
    );
  }

  /// The row pad twice (Settings' own PIN dialogs), then on.
  Future<void> _chooseParentPin() async {
    final set = await chooseNewParentPin(context);
    if (!mounted) return;
    if (set) {
      _showDone(SetupScreen.familyPin, const Duration(seconds: 2));
    } else {
      _focusPrimary();
    }
  }

  /// Profile Pairing: the same Accessibility screen as the Home button, another switch on it.
  Widget _pairing(AppLocalizations l) {
    const name = "Hearth Profile Pairing";
    final skip = SetupButton(label: l.setupFlowSkip, onPressed: _next);
    final picture = SetupStepsPicture(
      heading: l.setupFlowOnNextScreen,
      steps: [l.setupFlowStepServices, l.setupFlowStepSelect(name), l.setupFlowStepEnable],
    );
    final selfFix = (_snap?.adbEnabled ?? false)
        ? SetupButton(
            label: l.setupFlowLetHearthFix,
            onPressed: () =>
                _runFixes(const ["profile_pairing"], (snap) => snap.isDone(SetupStepId.profilePairing)),
          )
        : null;
    return switch (_state) {
      SetupStepState.done => SetupScreenBody(
          icon: Icons.check_circle,
          iconColor: Colors.green,
          title: l.setupFlowPairingDone,
          body: l.setupFlowPairingDoneBody,
          buttons: [
            SetupButton(
              label: l.setupFlowCheckPairings,
              icon: Icons.switch_account,
              onPressed: () => _openSettingsPage(ProfilePairingPage.routeName),
            ),
            SetupButton(label: l.setupFlowNext, focusNode: _primary, autofocus: true, onPressed: _next),
          ],
        ),
      SetupStepState.notYet => SetupScreenBody(
          icon: Icons.info_outline,
          title: l.setupFlowNotOnYetTitle,
          body: l.setupFlowNotOnYetBody,
          content: [picture],
          buttons: [
            skip,
            if (selfFix != null) selfFix,
            SetupButton(
              label: l.tryAgain,
              focusNode: _primary,
              autofocus: true,
              onPressed: () => _openStep(SetupStepId.profilePairing),
            ),
          ],
        ),
      _ => SetupScreenBody(
          icon: Icons.switch_account,
          title: l.setupFlowPairingTitle,
          body: l.setupFlowPairingBody(name),
          content: [
            picture,
            Text(l.setupFlowComesBack, style: const TextStyle(color: Colors.white54, fontSize: 13)),
          ],
          buttons: [
            skip,
            SetupButton(
              label: l.setupFlowOpenAccessibility,
              focusNode: _primary,
              autofocus: true,
              onPressed: () => _openStep(SetupStepId.profilePairing),
            ),
          ],
        ),
    };
  }

  /// Hearth voice: Netflix reads its profile screen aloud, and Profile Pairing listens through Hearth's own voice.
  Widget _voice(AppLocalizations l) => _bounceStepBody(
        l,
        SetupStepId.voice,
        icon: Icons.record_voice_over,
        title: l.setupFlowVoiceTitle,
        body: l.setupFlowVoiceBody("Hearth voice"),
        done: l.setupFlowVoiceDone,
      );

  /// Keep Hearth on the kids' profiles, where Google TV removes apps it didn't install at each profile start. Needs
  /// the TV's debugging switch, then the one-time "Allow debugging?".
  Widget _kids(AppLocalizations l) {
    final snap = _snap!;
    final skip = SetupButton(label: l.setupFlowSkip, onPressed: _next);
    if (_state == SetupStepState.done) {
      final rows = _kidsRows ?? const [];
      return SetupScreenBody(
        icon: Icons.check_circle,
        iconColor: Colors.green,
        title: l.setupFlowKidsDone,
        content: [
          for (final apps in FamilyAppsPage.byProfile(rows).values)
            Builder(builder: (context) {
              final (:label, :status, :color) = FamilyAppsPage.describeProfile(l, apps);
              return Row(children: [
                Icon((apps.first["supervised"] as bool?) == true ? Icons.child_care : Icons.person_outline,
                    size: 18, color: Colors.white70),
                const SizedBox(width: 8),
                Expanded(child: Text(label, style: const TextStyle(color: Colors.white, fontSize: 14))),
                Text(status, style: TextStyle(color: color ?? Colors.white54, fontSize: 13)),
              ]);
            }),
          Text(l.setupFlowKidsKeepDebugging, style: const TextStyle(color: Colors.white54, fontSize: 13)),
        ],
        buttons: [SetupButton(label: l.setupFlowNext, focusNode: _primary, autofocus: true, onPressed: _next)],
      );
    }
    if (!snap.adbEnabled) {
      return SetupScreenBody(
        icon: Icons.developer_mode,
        title: l.setupFlowDebugTitle,
        body: l.setupFlowDebugBody,
        buttons: [
          skip,
          SetupButton(label: l.setupFlowDebugOpen, focusNode: _primary, autofocus: true, onPressed: _openAbout),
        ],
      );
    }
    return SetupScreenBody(
      icon: Icons.child_care,
      title: l.setupFlowKidsTitle,
      body: l.setupFlowKidsBody,
      content: [Text(l.setupFlowKidsApprove, style: const TextStyle(color: Colors.white, fontSize: 14))],
      buttons: [
        skip,
        SetupButton(label: l.setupFlowKidsAdd, focusNode: _primary, autofocus: true, onPressed: _addToKids),
      ],
    );
  }

  /// Android's About screen, to turn on Developer options and debugging; checked again when Hearth is back.
  Future<void> _openAbout() async {
    _update(() => _state = SetupStepState.waiting);
    try {
      await _channel.openDeviceInfoSettings();
    } catch (_) {}
  }

  /// Says what adding does (Settings' own words), then adds Hearth and HearthTube to the kids' profiles over
  /// Hearth's own adb, and shows where they are.
  Future<void> _addToKids() async {
    final l = AppLocalizations.of(context)!;
    final includeAdults = context.read<SettingsService?>()?.pushToAdultProfiles ?? true;
    final go = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l.familyAppsAddTitle),
        content: SizedBox(
          width: 520,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final line in [
                  l.familyAppsAddKids,
                  if (includeAdults) l.familyAppsAddAdults,
                  l.familyAppsAddOnlyOwnApps,
                  l.familyAppsAddFamilyLink,
                  l.familyAppsAddApproval,
                ]) ...[
                  Text(line),
                  const SizedBox(height: 10),
                ],
              ],
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: Text(l.cancel)),
          TextButton(autofocus: true, onPressed: () => Navigator.of(context).pop(true), child: Text(l.familyAppsAdd)),
        ],
      ),
    );
    if (go != true || !mounted) {
      _focusPrimary();
      return;
    }
    _update(() => _fixing = true);
    List<Map<dynamic, dynamic>>? rows;
    try {
      await _channel.addHearthToProfiles(includeAdults: includeAdults);
      rows = await _channel.getHearthProfilesState();
    } catch (_) {
      rows = null;
    }
    if (!mounted) return;
    _update(() => _fixing = false);
    if (rows == null) {
      // Most likely "Allow debugging?" wasn't approved
      await showMessageDialog(context,
          title: l.familyAppsFailedTitle, message: "${l.familyAppsFailedBody}\n\n${l.familyAppsFailedRetry}");
      _focusPrimary();
      return;
    }
    await _flow.setKidsProtected(_snap?.kidsProfiles ?? 0);
    _update(() {
      _kidsRows = rows;
      _state = SetupStepState.done;
    });
    _focusPrimary();
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

  // --- Your home ---

  String _lookName(AppLocalizations l, HomeLook look) => switch (look) {
        HomeLook.hearth => l.setupLookHearth,
        HomeLook.photo => l.setupLookPhoto,
        HomeLook.calmDark => l.setupLookCalmDark,
        HomeLook.bold => l.setupLookBold,
      };

  /// The look screen opened: notes the look as it is, to put back unless one is chosen.
  void _startPreview() {
    final settings = context.read<SettingsService?>();
    if (settings == null) return;
    _lookSettings = settings;
    _lookBefore = HomeLookSnapshot.of(settings);
    _previewing = null;
  }

  /// Shows [look] on the home behind the card, until another is focused or the screen is left.
  void _preview(HomeLook look) {
    final settings = _lookSettings;
    if (settings == null || _previewing == look) return;
    _previewing = look;
    unawaited(look.apply(settings));
  }

  /// Leaves the look screen without choosing: the home goes back to how it was.
  void _endPreview() {
    final settings = _lookSettings;
    final before = _lookBefore;
    if (_previewing != null && settings != null && before != null) {
      // From dispose too, when Hearth itself may be closing: nothing to put back then
      unawaited(before.restore(settings).catchError((Object _) {}));
    }
    _previewing = null;
  }

  Future<void> _useLook(HomeLook look) async {
    final settings = _lookSettings;
    _previewing = null;
    if (settings != null) {
      await look.apply(settings);
      // Chosen for good: a picture picked as the wallpaper makes way for the look's gradient
      final gradient = look.gradient;
      if (gradient != null && mounted) await context.read<WallpaperService?>()?.setGradient(gradient);
    }
    // Another grown-up's choice is their own; the owner's is where new profiles start
    if (!_lookOnly) {
      await _flow.setLook(look);
      await _flow.decide(SetupCard.home.name, SetupChoice.on);
    }
    _next();
  }

  Future<void> _keepLook() async {
    _endPreview();
    if (!_lookOnly) await _flow.decide(SetupCard.home.name, SetupChoice.on);
    _next();
  }

  /// Customize: Settings' Look page over the flow, starting from the look on show. What the owner makes there stays.
  Future<void> _customizeLook() async {
    await _openSettingsPage(LookSettingsPage.routeName);
    final settings = _lookSettings;
    if (settings != null) _lookBefore = HomeLookSnapshot.of(settings);
    _previewing = null;
    if (!_lookOnly) await _flow.decide(SetupCard.home.name, SetupChoice.on);
  }

  /// Your home: four looks, each previewed on the home behind the card as it's focused. The card is the choice.
  Widget _lookScreen(AppLocalizations l) {
    final settings = _lookSettings ?? context.read<SettingsService?>();
    final current = settings == null ? null : HomeLook.current(settings);
    // Focus starts on the look the home has now, or Hearth's own
    final first = current ?? HomeLook.hearth;
    final where = "${l.settingsTitle} > ${l.homeScreenTitle} > ${l.lookTitle}";
    final kept = settings == null ? null : (_lookBefore ?? HomeLookSnapshot.of(settings));
    return SetupScreenBody(
      icon: Icons.palette_outlined,
      title: _lookOnly ? l.setupFlowLookOtherTitle : l.setupFlowLookTitle,
      body: _lookOnly ? l.setupFlowLookOtherBody : l.setupFlowLookBody(where),
      content: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final look in HomeLook.values) ...[
              Expanded(
                child: SetupLookTile(
                  key: ValueKey("look_${look.name}"),
                  label: _lookName(l, look),
                  gradient: look.gradient?.gradient,
                  // The photo look keeps the accent the home has
                  accent: accentColorFromHex(look.accent ?? kept?.accent ?? accentColorPurple),
                  note: look == current ? l.setupFlowLookNow : null,
                  focusNode: look == first ? _primary : null,
                  autofocus: look == first,
                  onFocused: () => _preview(look),
                  onPressed: () => _useLook(look),
                ),
              ),
              if (look != HomeLook.values.last) const SizedBox(width: 16),
            ],
          ],
        ),
      ],
      buttons: [
        SetupButton(label: l.setupFlowLookKeep, onPressed: _keepLook),
        SetupButton(label: l.setupFlowLookCustomize, icon: Icons.tune, onPressed: _customizeLook),
        SetupButton(label: l.setupFlowLookUse, onPressed: () => _useLook(_previewing ?? first)),
      ],
    );
  }

  bool get _weatherSet {
    final weather = context.read<WeatherService?>();
    // Without the weather (tests) there's nothing to set up
    return weather == null || (weather.location != null && (_lookSettings?.showWeatherInStatusBar ?? true));
  }

  /// Show the weather? Typing a town is the one place the flow asks for text; the dialog searches Open-Meteo.
  Widget _weather(AppLocalizations l) {
    if (_state == SetupStepState.done) return _doneBody(l, l.setupFlowWeatherDone);
    return SetupScreenBody(
      icon: Icons.wb_sunny_outlined,
      title: l.setupFlowWeatherTitle,
      body: l.setupFlowWeatherBody,
      buttons: [
        SetupButton(label: l.setupFlowSkip, onPressed: _next),
        SetupButton(label: l.setupFlowWeatherChoose, focusNode: _primary, autofocus: true, onPressed: _chooseTown),
      ],
    );
  }

  Future<void> _chooseTown() async {
    final weather = context.read<WeatherService?>();
    final settings = context.read<SettingsService?>();
    if (weather == null) return;
    final place = await showDialog<WeatherPlace>(
        context: context, builder: (_) => WeatherLocationDialog(weatherService: weather));
    if (place == null || !mounted) {
      _focusPrimary();
      return;
    }
    await weather.setLocation(place);
    await settings?.setShowWeatherInStatusBar(true);
    _showDone(SetupScreen.lookWeather, const Duration(seconds: 2));
  }

  // --- Smart home ---

  /// Home Assistant's pop-ups: Hearth listens for its notifications integration on the home network.
  Widget _haAlertsScreen(AppLocalizations l) {
    final body = l.setupFlowHaAlertsBody(_ip ?? l.haNotificationsThisTvIp);
    if (_state == SetupStepState.done) {
      return SetupScreenBody(
        icon: Icons.check_circle,
        iconColor: Colors.green,
        title: l.setupFlowHaAlertsDone,
        body: body,
        content: [
          if (_haTestResult != null) Text(_haTestResult!, style: const TextStyle(color: Colors.amber, fontSize: 13)),
        ],
        buttons: [
          SetupButton(label: l.haNotificationsSendTest, icon: Icons.notifications_outlined, onPressed: _sendHaTest),
          SetupButton(label: l.setupFlowNext, focusNode: _primary, autofocus: true, onPressed: _next),
        ],
      );
    }
    return SetupScreenBody(
      icon: Icons.notifications_active_outlined,
      title: l.setupFlowHaAlertsTitle,
      body: body,
      buttons: [
        SetupButton(label: l.setupFlowSkip, onPressed: _next),
        SetupButton(
          label: l.setupFlowTurnOn,
          focusNode: _primary,
          autofocus: true,
          onPressed: () async {
            try {
              await _channel.setHaNotificationsEnabled(true);
            } catch (_) {}
            if (!mounted) return;
            _update(() => _state = SetupStepState.done);
            _focusPrimary();
          },
        ),
      ],
    );
  }

  /// The test pop-up shows over the flow; without Home Button Fix it can't, and that's what's said.
  Future<void> _sendHaTest() async {
    final l = AppLocalizations.of(context)!;
    bool shown = false;
    try {
      shown = await _channel.sendHaTestNotification();
    } catch (_) {}
    if (mounted) _update(() => _haTestResult = shown ? null : l.haNotificationsNeedsFix(SetupChecklistPage.breadcrumb(l)));
  }

  /// The dashboard panel: the address and a token come from the phone, never typed with the remote.
  Widget _haDashboard(AppLocalizations l) {
    if (_state == SetupStepState.done) {
      return SetupScreenBody(
        icon: Icons.check_circle,
        iconColor: Colors.green,
        title: l.setupFlowHaDashboardDone,
        body: l.haPanelRightEdge,
        buttons: [SetupButton(label: l.setupFlowNext, focusNode: _primary, autofocus: true, onPressed: _next)],
      );
    }
    return SetupScreenBody(
      icon: Icons.dashboard_outlined,
      title: l.setupFlowHaDashboardTitle,
      body: l.setupFlowHaDashboardBody,
      buttons: [
        SetupButton(label: l.setupFlowSkip, onPressed: _next),
        SetupButton(
          label: l.haSetUpFromPhone,
          icon: Icons.qr_code_2,
          focusNode: _primary,
          autofocus: true,
          onPressed: () => _haFromPhone(SetupScreen.haDashboard),
        ),
      ],
    );
  }

  /// TV status: the webhook id comes from the same phone page.
  Widget _haStatusScreen(AppLocalizations l) {
    if (_state == SetupStepState.done) return _doneBody(l, l.setupFlowHaStatusDone);
    return SetupScreenBody(
      icon: Icons.sensors,
      title: l.setupFlowHaStatusTitle,
      body: l.setupFlowHaStatusBody,
      content: [
        if (_state == SetupStepState.notYet)
          Text(l.setupFlowHaStatusNoWebhook, style: const TextStyle(color: Colors.amber, fontSize: 13)),
      ],
      buttons: [
        SetupButton(label: l.setupFlowSkip, onPressed: _next),
        SetupButton(
          label: l.haSetUpFromPhone,
          icon: Icons.qr_code_2,
          focusNode: _primary,
          autofocus: true,
          onPressed: () => _haFromPhone(SetupScreen.haStatus),
        ),
      ],
    );
  }

  /// The phone page's QR code; once the phone has sent, what it set up shows as done.
  Future<void> _haFromPhone(SetupScreen screen) async {
    final settings = context.read<SettingsService?>();
    final received = await showDialog<bool>(context: context, builder: (_) => HaPhoneSetupDialog(channel: _channel));
    if (!mounted) return;
    if (received != true) {
      _focusPrimary();
      return;
    }
    await _refresh();
    if (!mounted) return;
    final snap = _snap;
    if (screen == SetupScreen.haDashboard && (snap?.haPanel ?? false)) {
      // The panel is each profile's own: on for this one, as the owner just set it up
      await settings?.setHaPanelEnabled(true);
      _showDone(screen, null);
    } else if (screen == SetupScreen.haStatus && (snap?.haStatus ?? false)) {
      _showDone(screen, const Duration(seconds: 2));
    } else {
      _update(() => _state = SetupStepState.notYet);
      _focusPrimary();
    }
  }

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
