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

/// The Java package of Hearth's services and receivers, in every build (release, debug).
const String kHearthJavaPackage = "com.thesiegs.hearth";

/// A Hearth component's full name for `adb`/Settings: "com.thesiegs.hearth.debug/com.thesiegs.hearth.X".
String hearthComponent(String packageName, String className) => "$packageName/$kHearthJavaPackage.$className";

/// The id without the debug build's suffix.
String withoutDebugSuffix(String packageName) =>
    packageName.endsWith(".debug") ? packageName.substring(0, packageName.length - ".debug".length) : packageName;

/// The app a Hearth update must install: Hearth itself. Release APKs only (a debug build updates to the release
/// app, as before).
String expectedUpdatePackage(String ownPackage) => withoutDebugSuffix(ownPackage);

/// Hearth, release or debug.
bool isHearthPackage(String? packageName) => packageName != null && withoutDebugSuffix(packageName) == kHearthAppId;
