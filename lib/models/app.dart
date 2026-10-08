/*
 * FLauncher
 * Copyright (C) 2024 Oscar Rojas
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

class App
{
  final String name;

  final String packageName;

  final String version;

  bool hidden;

  bool sideloaded;

  /// Blocked in the current Google TV profile (kids profile without approval, or its screen time is up). Not persisted.
  bool suspended = false;

  /// A parent approved it for the current Google TV kids profile (always true for grown-ups). Unlike [suspended],
  /// it stays true while screen time is up. Not persisted.
  bool approved = true;

  Map<int, int> categoryOrders;

  String? action;

  DateTime? lastLaunchedAt; // For "Last Used" category sorting

  App({
    required this.packageName,
    required this.name,
    required this.version,
    required this.hidden,
    this.action
  }):
    categoryOrders = {},
    sideloaded = false;

  App.fromSystem(Map<dynamic, dynamic> data):
    packageName = data['packageName'] as String? ?? '',
    name = data['name'] as String? ?? '',
    version = data['version'] as String? ?? '',
    hidden = false,
    sideloaded = data['sideloaded'] as bool? ?? false,
    suspended = data['suspended'] as bool? ?? false,
    approved = data['approved'] as bool? ?? true,
    categoryOrders = <int, int>{} {
    if (data.containsKey('action')) {
      action = data['action'] as String?;
    }
  }
}