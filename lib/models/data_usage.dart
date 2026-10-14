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

import 'package:intl/intl.dart';
import 'package:flauncher/quiet_failure.dart';

/// Whose data an [AppDataUsage] is.
enum DataUsageKind {
  /// An app's (its package and name are known).
  app,

  /// Android's own: system services, downloads of updates and the like.
  system,

  /// Removed apps, tethering, another profile's apps.
  other,
}

/// One app's data (sent and received) over a period.
class AppDataUsage {
  final String? packageName;
  final String? label;
  final DataUsageKind kind;
  final int bytes;

  const AppDataUsage({this.packageName, this.label, required this.kind, required this.bytes});

  factory AppDataUsage.fromMap(Map<dynamic, dynamic> map) {
    final kind = switch (map["kind"]) {
      "app" => DataUsageKind.app,
      "system" => DataUsageKind.system,
      _ => DataUsageKind.other,
    };
    final packageName = map["packageName"] as String?;
    return AppDataUsage(
      packageName: packageName,
      label: map["label"] as String? ?? packageName,
      // An app without its package can't be shown as one
      kind: kind == DataUsageKind.app && packageName == null ? DataUsageKind.other : kind,
      bytes: (map["bytes"] as num?)?.toInt() ?? 0,
    );
  }
}

/// The TV's data over a period: all of it, and app by app (largest first).
class DataUsageBreakdown {
  final int total;
  final List<AppDataUsage> apps;

  const DataUsageBreakdown({required this.total, required this.apps});

  factory DataUsageBreakdown.fromMap(Map<dynamic, dynamic> map) {
    final apps = [
      for (final entry in (map["apps"] as List<dynamic>? ?? const []))
        if (entry is Map) AppDataUsage.fromMap(entry),
    ]..sort((a, b) => b.bytes.compareTo(a.bytes));
    return DataUsageBreakdown(total: (map["total"] as num?)?.toInt() ?? 0, apps: apps);
  }

  /// The [count] largest apps and Android's own, for tiles; what they leave of the total is [othersBytes].
  List<AppDataUsage> top(int count) =>
      apps.where((a) => a.kind != DataUsageKind.other && a.bytes > 0).take(count).toList();

  /// The [whole] less the [count] largest ([top]): smaller apps, removed apps, other profiles, what no app is named
  /// for.
  int othersBytes(int count) {
    final shown = top(count).fold<int>(0, (sum, a) => sum + a.bytes);
    return whole > shown ? whole - shown : 0;
  }

  /// The larger of the device total and what the apps add up to (Android counts them apart, so they can differ a
  /// little): the whole the tiles are shares of.
  int get whole {
    final apps = this.apps.fold<int>(0, (sum, a) => sum + a.bytes);
    return total > apps ? total : apps;
  }
}

/// An amount of data as Android's own data usage screen writes it (powers of 1000): "0 B", "850 KB", "1.2 GB",
/// "125 GB", with the language's decimal mark.
String formatDataBytes(int bytes, [String? locale]) {
  if (bytes <= 0) return "0 B";
  const units = ["B", "KB", "MB", "GB", "TB"];
  var value = bytes.toDouble();
  var unit = 0;
  while (value >= 1000 && unit < units.length - 1) {
    value /= 1000;
    unit++;
  }
  NumberFormat format;
  try {
    format = NumberFormat(value < 100 && unit > 0 ? "0.#" : "0", locale);
  } catch (err) {
      noteFailure('data_usage', err);
    format = NumberFormat(value < 100 && unit > 0 ? "0.#" : "0", "en_US");
  }
  return "${format.format(value)} ${units[unit]}";
}
