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

/// Hearth's app ids (see docs/design/app-id-change.md).
const String kHearthAppId = "com.thesiegs.hearth";

/// The id Hearth had up to v2026.10.x (inherited from the LTvLauncher fork); a bridge build still has it.
const String kLegacyHearthAppId = "com.leanbitlab.ltvL";

/// The Java package of Hearth's services and receivers, in every build (release, debug, bridge).
const String kHearthJavaPackage = "com.thesiegs.hearth";

/// A Hearth component's full name for `adb`/Settings: "com.thesiegs.hearth.debug/com.thesiegs.hearth.X".
String hearthComponent(String packageName, String className) => "$packageName/$kHearthJavaPackage.$className";

/// The id without the debug build's suffix.
String withoutDebugSuffix(String packageName) =>
    packageName.endsWith(".debug") ? packageName.substring(0, packageName.length - ".debug".length) : packageName;

/// This is the bridge build: the old app id, which moves the TV to the new one.
bool isBridgePackage(String packageName) => withoutDebugSuffix(packageName) == kLegacyHearthAppId;

/// Hearth under either id, release or debug.
bool isHearthPackage(String? packageName) {
  if (packageName == null) return false;
  final id = withoutDebugSuffix(packageName);
  return id == kHearthAppId || id == kLegacyHearthAppId;
}
