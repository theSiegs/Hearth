import 'package:flauncher/log_names.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test("stand-ins match the Android side's (Java String.hashCode, low 16 bits)", () {
    // "alex".hashCode() in Java is 0x2DBA1E
    expect(logStandIn(" Alex "), "#ba1e");
  });

  test("keys keep their shape; tests run in debug mode, where names show", () {
    expect(logKey("user:0:alex"), "user:0:alex");
    expect(logKey(null), "null");
  });
}
