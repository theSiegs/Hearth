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
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'home_looks.dart';
import 'settings_service.dart';

/// How the setup flow runs: the whole of it (first run, or picking up where it was left), again from Settings, or
/// only the Home button screen after an update switched Home Button Fix off.
/// [look]: only "Pick a look for your home", for a grown-up's first visit to a profile after the flow has run.
enum SetupMode { full, rerun, lostFix, look }

/// The flow's optional cards, in the order they show (docs/design/first-run-setup.md). [introducedIn] is the flow
/// version that added each, so a later update can offer only what's new.
enum SetupCard {
  family(1),
  watching(1),
  home(1),
  tv(1),
  updates(1);

  final int introducedIn;

  const SetupCard(this.introducedIn);
}

/// What the owner chose on a step or card. Grants (switches in Android) are never stored: they're read live.
enum SetupChoice { on, notNow }

/// Where the flow was left: its screen, the mode it ran in, and when. [closed] when the owner chose Finish later,
/// which leaves continuing to the home-screen chip.
class SetupResume {
  final String screen;
  final SetupMode mode;
  final DateTime at;
  final bool closed;

  const SetupResume(this.screen, this.mode, this.at, {this.closed = false});
}

/// What the home opens as it starts or comes back to the front.
sealed class SetupLaunch {
  const SetupLaunch();
}

class SetupLaunchNothing extends SetupLaunch {
  const SetupLaunchNothing();
}

/// The whole flow, from Welcome: a TV Hearth was never set up on.
class SetupLaunchFirstRun extends SetupLaunch {
  const SetupLaunchFirstRun();
}

/// Hearth was in use before the flow existed: nobody redoes a setup that's done
/// ([SetupFlowService.markExistingInstall]).
class SetupLaunchExistingInstall extends SetupLaunch {
  const SetupLaunchExistingInstall();
}

/// The flow at the screen it was left on, within [SetupFlowService.resumeWindow].
class SetupLaunchResume extends SetupLaunch {
  final SetupResume resume;

  const SetupLaunchResume(this.resume);
}

/// An update switched Home Button Fix off: the one case that takes over the screen after the first run.
class SetupLaunchLostFix extends SetupLaunch {
  const SetupLaunchLostFix();
}

/// Hearth's first-run setup flow: what the owner chose, where the flow was left, and which version of it they've been
/// through. All device-wide (`device_setup_` keys): every profile shares it, and neither a profile's layout nor a
/// backup carries it, since a backup from another TV mustn't claim choices this one hasn't made.
class SetupFlowService extends ChangeNotifier {
  /// The flow as built now: a later version adds cards an earlier one didn't have.
  static const int currentVersion = 1;

  static const String keyPrefix = "device_setup_";
  static const String _flowVersionKey = "device_setup_flow_version";
  static const String _seenVersionKey = "device_setup_seen_version";
  static const String _resumeKey = "device_setup_resume";
  static const String _decisionsKey = "device_setup_decisions";
  static const String _chipHiddenKey = "device_setup_chip_hidden";

  /// The look chosen in the flow (a [HomeLook]'s name): the starting look for new grown-up profiles.
  static const String lookKey = "device_setup_look";

  /// How many kids' profiles Android listed when Hearth was last put on them from the flow: a new one asks again.
  static const String _kidsProtectedKey = "device_setup_kids_profiles";

  /// Choices that aren't a card's.
  static const String homeButtonDecision = "homeButton";
  static const String homeAppDecision = "homeApp";

  /// The owner chose Not now on the "The update turned the Home button off" screen: it doesn't take over again until
  /// Home Button Fix has been on and is lost once more.
  static const String lostFixDecision = "homeButtonLost";

  /// How long a step that sent the owner to Android's settings reopens the flow by itself when Hearth starts again.
  static const Duration resumeWindow = Duration(minutes: 30);

  final SharedPreferences _prefs;
  final DateTime Function() _now;

  /// Whether Hearth ran on this TV before this start: it kept a profile's layout. Read before this start's first
  /// profile check saves one.
  final bool _ranBefore;

  SetupFlowService(this._prefs, {DateTime Function()? now})
      : _now = now ?? DateTime.now,
        _ranBefore = _prefs.containsKey(SettingsService.layoutOwnerKey);

  /// The flow is on screen (opened by the home, its chip or Settings): nothing else opens it a second time.
  bool showing = false;

  /// Whether a key is the flow's own state (kept out of backups and layouts).
  static bool isSetupKey(String key) => key.startsWith(keyPrefix);

  /// The flow version last finished or closed; null when the flow has never run here.
  int? get flowVersion => _prefs.getInt(_flowVersionKey);

  /// The newest card version the owner has been shown.
  int get seenVersion => _prefs.getInt(_seenVersionKey) ?? 0;

  int get kidsProtected => _prefs.getInt(_kidsProtectedKey) ?? 0;

  Future<void> setKidsProtected(int count) => _prefs.setInt(_kidsProtectedKey, count);

  HomeLook? get look => HomeLook.byName(_prefs.getString(lookKey));

  Future<void> setLook(HomeLook look) => _prefs.setString(lookKey, look.name);

  bool get chipHidden => _prefs.getBool(_chipHiddenKey) ?? false;

  Future<void> hideChip() async {
    await _prefs.setBool(_chipHiddenKey, true);
    notifyListeners();
  }

  SetupResume? get resume {
    final raw = _prefs.getString(_resumeKey);
    if (raw == null) return null;
    try {
      final map = jsonDecode(raw) as Map<String, dynamic>;
      final mode = SetupMode.values.asNameMap()[map["mode"]] ?? SetupMode.full;
      return SetupResume(map["screen"] as String, mode, DateTime.fromMillisecondsSinceEpoch(map["at"] as int),
          closed: map["closed"] == true);
    } catch (_) {
      return null;
    }
  }

  /// Notes the screen the flow is on, so leaving for Android's settings, a crash or a restart comes back to it.
  Future<void> saveResume(String screen, SetupMode mode) => _prefs.setString(
      _resumeKey, jsonEncode({"screen": screen, "mode": mode.name, "at": _now().millisecondsSinceEpoch}));

  Map<String, ({SetupChoice choice, DateTime at})> get decisions {
    final raw = _prefs.getString(_decisionsKey);
    if (raw == null) return const {};
    try {
      final map = jsonDecode(raw) as Map<String, dynamic>;
      return {
        for (final entry in map.entries)
          if (SetupChoice.values.asNameMap()[(entry.value as Map)["state"]] case final choice?)
            entry.key: (
              choice: choice,
              at: DateTime.fromMillisecondsSinceEpoch(((entry.value as Map)["at"] as int?) ?? 0),
            ),
      };
    } catch (_) {
      return const {};
    }
  }

  SetupChoice? choiceFor(String id) => decisions[id]?.choice;

  SetupChoice? cardChoice(SetupCard card) => choiceFor(card.name);

  Future<void> decide(String id, SetupChoice? choice) async {
    final current = {
      for (final entry in decisions.entries)
        entry.key: {"state": entry.value.choice.name, "at": entry.value.at.millisecondsSinceEpoch},
    };
    if (choice == null) {
      current.remove(id);
    } else {
      current[id] = {"state": choice.name, "at": _now().millisecondsSinceEpoch};
    }
    await _prefs.setString(_decisionsKey, jsonEncode(current));
    notifyListeners();
  }

  /// Finish later, or Set up later: the flow won't open by itself again; the chip offers to continue.
  Future<void> close() async {
    final left = resume;
    if (left != null) {
      await _prefs.setString(_resumeKey, jsonEncode({
        "screen": left.screen,
        "mode": left.mode.name,
        "at": left.at.millisecondsSinceEpoch,
        "closed": true,
      }));
    }
    await _markVersion();
  }

  /// Finish: nothing to continue.
  Future<void> finish() async {
    await _prefs.remove(_resumeKey);
    await _markVersion();
  }

  Future<void> _markVersion() async {
    await _prefs.setInt(_flowVersionKey, currentVersion);
    await _prefs.setInt(_seenVersionKey, currentVersion);
    notifyListeners();
  }

  /// What to open now. [kids]: nothing in a kids' profile (a child can't set Hearth up; it waits for an adult one).
  /// [homeButtonSeenBefore]: Home Button Fix has been on on this TV; [homeButtonOn]: it's on now. Those, a parent
  /// PIN, or a layout from before this start mean Hearth was in use before the flow existed.
  SetupLaunch launch({
    required bool kids,
    required bool homeButtonOn,
    required bool homeButtonSeenBefore,
    required bool hasParentPin,
  }) {
    if (kids) return const SetupLaunchNothing();
    // Back on: a later loss takes over again
    if (homeButtonOn && choiceFor(lostFixDecision) != null) unawaited(decide(lostFixDecision, null));
    final left = resume;
    final bool fresh = left != null && !left.closed && _now().difference(left.at) < resumeWindow;
    if (fresh) return SetupLaunchResume(left);
    if (homeButtonSeenBefore && !homeButtonOn && choiceFor(lostFixDecision) == null) {
      return const SetupLaunchLostFix();
    }
    // Run before (finished, closed, or a first run interrupted long ago): the chip carries on from here
    if (flowVersion != null || left != null) return const SetupLaunchNothing();
    if (homeButtonSeenBefore || hasParentPin || _ranBefore) return const SetupLaunchExistingInstall();
    return const SetupLaunchFirstRun();
  }

  /// An install from before the flow: counts as through it, without showing it. Each card is marked from the TV's
  /// state ([cardOn]): on when it's all on already, otherwise Not now.
  Future<void> markExistingInstall(Map<SetupCard, bool> cardOn) async {
    for (final card in SetupCard.values) {
      if (cardChoice(card) == null) {
        await decide(card.name, cardOn[card] == true ? SetupChoice.on : SetupChoice.notNow);
      }
    }
    await _markVersion();
  }

  /// Whether the Home button needs a fix: it's off, and the owner skipped it or an update switched it off.
  bool homeButtonNeedsFix({required bool homeButtonOn, required bool homeButtonSeenBefore}) =>
      !homeButtonOn && (homeButtonSeenBefore || choiceFor(homeButtonDecision) == SetupChoice.notNow);

  /// How many things the chip says are left: the essentials neither on nor skipped, and the cards nobody decided on
  /// that aren't all on anyway ([cardOn]).
  int remaining({required bool homeButtonOn, required bool homeAppOn, Map<SetupCard, bool> cardOn = const {}}) {
    int left = 0;
    if (!homeButtonOn && choiceFor(homeButtonDecision) == null) left++;
    if (!homeAppOn && choiceFor(homeAppDecision) == null) left++;
    for (final card in SetupCard.values) {
      if (cardChoice(card) == null && cardOn[card] != true) left++;
    }
    return left;
  }

  /// Whether the home may show its "Finish setting up" chip: once the flow has run (before, the flow shows itself),
  /// never in a kids' profile, and not once dismissed.
  bool chipAllowed({required bool kids}) => !kids && !chipHidden && (flowVersion != null || resume != null);
}
