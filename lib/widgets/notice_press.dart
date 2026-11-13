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

import 'package:flauncher/l10n/app_localizations.dart';
import 'package:flutter/material.dart';

import '../flauncher_channel.dart';
import 'parent_pin_dialog.dart';

/// One of the Hearth integration's notice buttons, pressed in the Bell or its pop-up (Household.openIntegrationPress).
class NoticePress {
  final String person;
  final String item;
  final int index;
  final String title;
  final String button;

  /// Whether an adult has phone approval on: the pad asks the adults' phones as it opens, as the Parent PIN pad
  /// does elsewhere (the integration picks the phones).
  final bool phone;

  const NoticePress(
      {required this.person,
      required this.item,
      required this.index,
      this.title = "",
      this.button = "",
      this.phone = false});

  /// From the Java side's map; null when it isn't one.
  static NoticePress? from(Map<dynamic, dynamic>? map) {
    final person = map?["person"];
    final item = map?["item"];
    final index = map?["index"];
    if (person is! String || item is! String || index is! int) return null;
    return NoticePress(
        person: person,
        item: item,
        index: index,
        title: map?["title"] as String? ?? "",
        button: map?["button"] as String? ?? "",
        phone: map?["phone"] == true);
  }
}

/// What the TV says once the pad closes, for the integration's answer ([result]); null says nothing (Back).
String? noticeMessage(AppLocalizations l, String? result) => switch (result) {
      null => null,
      "done" => l.noticeDone,
      "pending" => l.noticeSent,
      "gone" => l.noticeGone,
      "unsupported" || "not_paired" => l.noticeUsePhone,
      "too_many" => l.noticeTooMany,
      _ => l.noticeFailed,
    };

/// Whether a wrong PIN should ask the adults' phones instead: Home Assistant has no Parent PIN (so every PIN is
/// wrong there, and only a phone's answer works), the integration didn't lock the pad, and the phones weren't asked
/// yet on this pad.
bool offerPhoneAfterWrongPin(Map<dynamic, dynamic> answer, {required bool asked}) =>
    !asked && answer["noParentPin"] == true && (answer["retryAfter"] as int? ?? 0) == 0;

/// The Parent PIN pad for a notice's button: the PIN goes to the Hearth integration, which checks it (its lockout is
/// the pad's too) and runs the button as that adult. As on Hearth's other Parent PIN pads, the adults' phones are
/// asked as it opens when phone approval is on; and once after a wrong PIN when Home Assistant has no Parent PIN. At
/// most one phone request per pad. A short message says how it went.
Future<void> answerNotice(BuildContext context, FLauncherChannel channel, NoticePress press) async {
  final l = AppLocalizations.of(context)!;
  String? result;
  var asked = false;
  var sentToPhone = false;
  final note = ValueNotifier<String?>(null);

  // Asks the phones (once): the note to show, or null; closes the pad when there's nothing left to ask
  Future<String?> askPhones() async {
    if (asked) return null;
    asked = true;
    final answer = await channel.pressIntegrationNotice(press.person, press.item, press.index);
    final said = answer["result"] as String? ?? "failed";
    if (said == "pending") {
      sentToPhone = true;
      return l.noticeSentToPhone;
    }
    if (said == "gone" || said == "unsupported" || said == "not_paired") {
      result = said;
      throw const PinPadClose();
    }
    // The phones couldn't be asked: the PIN still works
    return null;
  }

  await showDialog<String>(
    context: context,
    builder: (_) => ParentPinDialog(
      title: press.button.isEmpty ? l.parentPinTitle : press.button,
      subtitle: press.title.isEmpty ? null : press.title,
      note: note,
      verify: (pin) async {
        final answer = await channel.pressIntegrationNotice(press.person, press.item, press.index, pin: pin);
        final said = answer["result"] as String? ?? "failed";
        // A wrong PIN is the pad's to count (and to wait, when the integration locked it out)
        if (said == "wrong_pin") {
          if (offerPhoneAfterWrongPin(answer, asked: asked)) note.value = await askPhones() ?? note.value;
          return false;
        }
        result = said;
        if (said == "done") return true;
        throw const PinPadClose();
      },
      askPhone: press.phone ? askPhones : null,
    ),
  );
  note.dispose();
  if (!context.mounted) return;
  // Back after the phones were asked: it waits for them
  final message = noticeMessage(l, result ?? (sentToPhone ? "pending" : null));
  if (message != null) ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(content: Text(message)));
}
