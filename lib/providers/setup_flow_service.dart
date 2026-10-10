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

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// How the setup flow runs: the whole of it (first run, or picking up where it was left), again from Settings, or
/// only the Home button screen after an update switched Home Button Fix off.
enum SetupMode { full, rerun, lostFix }

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

  SetupFlowService(this._prefs, {DateTime Function()? now}) : _now = now ?? DateTime.now;

  /// Whether a key is the flow's own state (kept out of backups and layouts).
  static bool isSetupKey(String key) => key.startsWith(keyPrefix);

  /// The flow version last finished or closed; null when the flow has never run here.
  int? get flowVersion => _prefs.getInt(_flowVersionKey);

  /// The newest card version the owner has been shown.
  int get seenVersion => _prefs.getInt(_seenVersionKey) ?? 0;

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
}
