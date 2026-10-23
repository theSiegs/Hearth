import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flauncher/providers/parent_pin_hash.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test("a PIN verifies against the value made from it, and a wrong one doesn't", () {
    final stored = ParentPinHash.hash("2468");
    expect(ParentPinHash.verify("2468", stored), isTrue);
    expect(ParentPinHash.verify("2469", stored), isFalse);
    expect(ParentPinHash.verify("", stored), isFalse);
    expect(ParentPinHash.isLegacy(stored), isFalse);
  });

  test("two values for the same PIN differ (a random salt), and both verify", () {
    final a = ParentPinHash.hash("2468");
    final b = ParentPinHash.hash("2468");
    expect(a, isNot(b));
    expect(ParentPinHash.verify("2468", a), isTrue);
    expect(ParentPinHash.verify("2468", b), isTrue);
  });

  test("the stored value looks like v2, the cost, a salt and a hash, and says nothing of the PIN", () {
    final stored = ParentPinHash.hash("2468");
    expect(ParentPinHash.pattern.hasMatch(stored), isTrue);
    expect(stored.startsWith("v2\$${ParentPinHash.iterations}\$"), isTrue);
    expect(stored.contains("2468"), isFalse);
  });

  test("PBKDF2-HMAC-SHA256 matches published test vectors", () {
    String hex(List<int> b) => b.map((x) => x.toRadixString(16).padLeft(2, "0")).join();
    expect(hex(ParentPinHash.pbkdf2(utf8.encode("password"), utf8.encode("salt"), 1, 32)),
        "120fb6cffcf8b32c43e7225256c4f837a86548c92ccc35480805987cb70be17b");
    expect(hex(ParentPinHash.pbkdf2(utf8.encode("password"), utf8.encode("salt"), 2, 32)),
        "ae4d0c95af6b46d32d0adff928f06dd02a303f8ef3c251dfd6e2d85a95474c43");
  });

  test("a value in the old form still verifies and is recognised as old", () {
    final legacy = sha256.convert(utf8.encode("ltv-parent-pin:1357")).toString();
    expect(ParentPinHash.isLegacy(legacy), isTrue);
    expect(ParentPinHash.verify("1357", legacy), isTrue);
    expect(ParentPinHash.verify("1358", legacy), isFalse);
  });

  test("anything that isn't a stored value never verifies", () {
    expect(ParentPinHash.verify("1234", null), isFalse);
    expect(ParentPinHash.verify("1234", ""), isFalse);
    expect(ParentPinHash.verify("1234", "1234"), isFalse);
    expect(ParentPinHash.verify("1234", "v2\$0\$00\$00"), isFalse);
    expect(ParentPinHash.verify("1234", "v2\$0\$${"0" * 32}\$${"0" * 64}"), isFalse);
  });
}
