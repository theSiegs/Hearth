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

import 'package:flutter/foundation.dart';

/// A profile key for the TV's log ("user:0:alex" names its account): in a release build its name part is a short
/// stand-in, the same one Hearth's Android side logs (LogNames.java), so a pasted log doesn't name the family.
String logKey(String? key) {
  if (key == null || !kReleaseMode) return "$key";
  final first = key.indexOf(":");
  final second = first < 0 ? -1 : key.indexOf(":", first + 1);
  return second < 0 ? key : key.substring(0, second + 1) + logStandIn(key.substring(second + 1));
}

/// "#3f2a": Java's String.hashCode of the trimmed, lower-cased name, its low 16 bits in hex (as LogNames.standIn).
String logStandIn(String name) {
  var hash = 0;
  for (final unit in name.trim().toLowerCase().codeUnits) {
    hash = (31 * hash + unit) & 0xffffffff;
  }
  return "#${(hash & 0xffff).toRadixString(16).padLeft(4, "0")}";
}
