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

import 'package:flauncher/widgets/settings/remote_phones_page.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group("RemotePhone", () {
    test("reads its told role", () {
      final kid = RemotePhone.fromMap(
          {"fingerprint": "aa", "name": "Glint - Pixel", "role": "kid", "profileKey": "user:10", "lastUsed": 5});
      expect(kid.role, RemotePhoneRole.kid);
      expect(kid.profileKey, "user:10");
      expect(kid.lastUsed, DateTime.fromMillisecondsSinceEpoch(5));
      expect(RemotePhone.fromMap({"fingerprint": "bb", "role": "parent"}).role, RemotePhoneRole.parent);
    });

    test("anything else, or a kid's phone without its kid, is not this one", () {
      expect(RemotePhone.fromMap({"fingerprint": "aa"}).role, RemotePhoneRole.none);
      expect(RemotePhone.fromMap({"fingerprint": "aa", "role": "owner"}).role, RemotePhoneRole.none);
      expect(RemotePhone.fromMap({"fingerprint": "aa", "role": "kid"}).role, RemotePhoneRole.none);
      expect(RemotePhone.fromMap({"fingerprint": "aa"}).name, "phone");
    });

    test("kids come with their profile", () {
      expect(RemotePhoneKid.fromMap({"profileKey": "user:10", "name": "Sam"})?.name, "Sam");
      expect(RemotePhoneKid.fromMap({"name": "Sam"}), isNull);
    });
  });
}
