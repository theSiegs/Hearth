import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';

/// How the TV keeps the Parent PIN: not the PIN, a salted slow hash of it, as `v2$<iterations>$<salt>$<hash>` (hex).
/// A PIN of four digits can't be made unguessable; the salt and the cost only keep the stored value from being read
/// back in an instant, and the lockout after wrong guesses does the rest. The old form (an unsalted SHA-256 with a
/// fixed prefix, 64 hex digits) still verifies, and is replaced the next time it does.
class ParentPinHash {
  const ParentPinHash._();

  static const int iterations = 10000;
  static const int _saltBytes = 16;
  static const int _hashBytes = 32;
  static const String _prefix = "v2";

  /// What a stored value may look like: the old 64 hex digits or the new form.
  static final RegExp pattern = RegExp(r'^([0-9a-f]{64}|v2\$[0-9]{1,7}\$[0-9a-f]{32}\$[0-9a-f]{64})$');

  /// A new stored value for [pin], with a random salt (or the [salt] given, for tests).
  static String hash(String pin, {List<int>? salt, int cost = iterations}) {
    final s = salt ?? _randomSalt();
    final derived = pbkdf2(utf8.encode(pin), s, cost, _hashBytes);
    return "$_prefix\$$cost\$${_hex(s)}\$${_hex(derived)}";
  }

  /// Whether [pin] is the PIN [stored] was made from; false for anything that isn't a stored value.
  static bool verify(String pin, String? stored) {
    if (stored == null || !pattern.hasMatch(stored)) return false;
    if (isLegacy(stored)) return _same(_legacy(pin), stored);
    final parts = stored.split(r"$");
    final cost = int.parse(parts[1]);
    if (cost < 1 || cost > 200000) return false;
    final derived = pbkdf2(utf8.encode(pin), _unhex(parts[2]), cost, _hashBytes);
    return _same(_hex(derived), parts[3]);
  }

  /// A stored value in the old form, to be replaced after the next good verify.
  static bool isLegacy(String? stored) => stored != null && RegExp(r'^[0-9a-f]{64}$').hasMatch(stored);

  static String _legacy(String pin) => sha256.convert(utf8.encode("ltv-parent-pin:$pin")).toString();

  static Uint8List _randomSalt() {
    final random = Random.secure();
    return Uint8List.fromList(List<int>.generate(_saltBytes, (_) => random.nextInt(256)));
  }

  /// PBKDF2-HMAC-SHA256 (RFC 8018).
  @visibleForTesting
  static Uint8List pbkdf2(List<int> password, List<int> salt, int cost, int length) {
    final hmac = Hmac(sha256, password);
    final out = BytesBuilder();
    for (var block = 1; out.length < length; block++) {
      var u = hmac.convert([...salt, (block >> 24) & 255, (block >> 16) & 255, (block >> 8) & 255, block & 255]).bytes;
      final t = List<int>.from(u);
      for (var i = 1; i < cost; i++) {
        u = hmac.convert(u).bytes;
        for (var j = 0; j < t.length; j++) {
          t[j] ^= u[j];
        }
      }
      out.add(t);
    }
    return Uint8List.fromList(out.toBytes().sublist(0, length));
  }

  static bool _same(String a, String b) {
    if (a.length != b.length) return false;
    var diff = 0;
    for (var i = 0; i < a.length; i++) {
      diff |= a.codeUnitAt(i) ^ b.codeUnitAt(i);
    }
    return diff == 0;
  }

  static String _hex(List<int> bytes) => bytes.map((b) => b.toRadixString(16).padLeft(2, "0")).join();

  static Uint8List _unhex(String hex) =>
      Uint8List.fromList([for (var i = 0; i < hex.length; i += 2) int.parse(hex.substring(i, i + 2), radix: 16)]);
}
