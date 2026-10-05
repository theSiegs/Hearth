import 'dart:async';
import 'dart:ffi';
import 'dart:io';
import 'package:sqlite3/open.dart';

Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  if (Platform.isLinux) {
    open.overrideFor(OperatingSystem.linux, () => DynamicLibrary.open('libsqlite3.so.0'));
  } else if (Platform.isWindows) {
    final bundled = File('tool/windows/sqlite3.dll');
    if (bundled.existsSync()) {
      open.overrideFor(OperatingSystem.windows, () => DynamicLibrary.open(bundled.absolute.path));
    }
  }
  await testMain();
}
