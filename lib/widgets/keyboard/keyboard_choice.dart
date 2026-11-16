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
import 'package:flauncher/quiet_failure.dart';

/// The TV's keyboard as the Android side reads it (Keyboards.java).
class KeyboardStatus {
  /// "onscreen", "phone" (Google TV's remote bridge: typing goes to a phone), "voice", "none", or "unknown" when it
  /// couldn't be read.
  final String kind;

  /// A phone remote is there now, as far as Hearth can tell (a paired phone with Hearth's remote open).
  final bool phone;

  /// Hearth may change the TV's keyboard (the keyboard setup fix granted WRITE_SECURE_SETTINGS).
  final bool canSwitch;

  /// The on-screen keyboard Hearth would put back, or null when the TV has none turned on.
  final String? onScreenId;

  const KeyboardStatus({required this.kind, this.phone = false, this.canSwitch = false, this.onScreenId});

  /// Nothing known: Hearth asks the TV's keyboard as it always did.
  static const unknown = KeyboardStatus(kind: "unknown");

  factory KeyboardStatus.fromMap(Map<dynamic, dynamic> map) => KeyboardStatus(
        kind: map["kind"] as String? ?? "unknown",
        phone: map["phone"] == true,
        canSwitch: map["canSwitch"] == true,
        onScreenId: map["onScreen"] as String?,
      );

  /// The TV's keyboard shows on the screen (or Hearth can't tell, and trusts it as before).
  bool get systemOnScreen => kind == "onscreen" || kind == "unknown";
}

/// How a Hearth text field gets its keyboard.
enum KeyboardWay {
  /// The TV's keyboard (on screen): ask for it as usual.
  system,

  /// Hearth just put the TV's on-screen keyboard back (it was a phone's, with no phone there): ask for it once
  /// Android has switched.
  systemAfterSwitch,

  /// Hearth's own on-screen keyboard with the mic: the TV's keyboard would go to a phone (or nowhere).
  hearth,
}

/// What a field does for [status], before anything is switched: [KeyboardWay.systemAfterSwitch] means "switch first".
KeyboardWay keyboardWayFor(KeyboardStatus status) {
  if (status.systemOnScreen) return KeyboardWay.system;
  if (status.canSwitch && !status.phone && status.onScreenId != null) return KeyboardWay.systemAfterSwitch;
  return KeyboardWay.hearth;
}

/// The keyboard a Hearth text field should use now, switching the TV's keyboard back to an on-screen one where
/// Hearth may and no phone is there. Never a phone's keyboard by default: when the TV's keyboard is a phone's, the
/// field gets Hearth's own, which offers the phone only while one is there ([KeyboardChoice.status]).
Future<KeyboardChoice> chooseKeyboard(FLauncherChannel? channel) async {
  if (channel == null) return const KeyboardChoice(KeyboardWay.system, KeyboardStatus.unknown);
  KeyboardStatus status;
  try {
    status = KeyboardStatus.fromMap(await channel.getKeyboardStatus());
  } catch (err) {
    noteFailure('keyboard_choice', err);
    return const KeyboardChoice(KeyboardWay.system, KeyboardStatus.unknown);
  }
  final way = keyboardWayFor(status);
  if (way != KeyboardWay.systemAfterSwitch) return KeyboardChoice(way, status);
  bool switched = false;
  try {
    switched = await channel.useOnScreenKeyboard();
  } catch (err) {
    noteFailure('keyboard_choice', err);
  }
  return KeyboardChoice(switched ? KeyboardWay.systemAfterSwitch : KeyboardWay.hearth, status);
}

class KeyboardChoice {
  final KeyboardWay way;
  final KeyboardStatus status;

  const KeyboardChoice(this.way, this.status);

  /// Android needs a moment to bind the keyboard Hearth just switched to before a field asks it to show.
  static const switchSettle = Duration(milliseconds: 300);
}
