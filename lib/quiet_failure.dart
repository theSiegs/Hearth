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
import 'package:flutter/services.dart';

/// Records that something failed and the app carried on with a default: where, and the error's type, in the log.
///
/// Not the error's message (it can quote what was asked: a name, an address, a token) and not a stack trace. A
/// missing plugin is what every test sees, so it isn't news there; on a TV it means the Java side has no such
/// method, which is.
void noteFailure(String where, Object error) {
  if (error is MissingPluginException && !kReleaseMode) return;
  debugPrint('Hearth: $where failed: ${error.runtimeType}');
}
