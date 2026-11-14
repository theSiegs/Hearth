import 'package:flauncher/providers/update_deferral.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  final monday = DateTime(2026, 11, 16, 3);

  group("mayInstallUpdateNow", () {
    test("installs at once when no kids profile is running", () {
      expect(mayInstallUpdateNow(kidsUserRunning: false, now: monday), isTrue);
      expect(mayInstallUpdateNow(kidsUserRunning: false, now: monday, waitingSince: monday), isTrue);
    });

    test("waits while a kids profile is running", () {
      expect(mayInstallUpdateNow(kidsUserRunning: true, now: monday), isFalse);
      final sixDays = monday.subtract(const Duration(days: 6, hours: 23));
      expect(mayInstallUpdateNow(kidsUserRunning: true, now: monday, waitingSince: sixDays), isFalse);
    });

    test("installs anyway once it has waited a week", () {
      final week = monday.subtract(updateDeferralCap);
      expect(mayInstallUpdateNow(kidsUserRunning: true, now: monday, waitingSince: week), isTrue);
    });

    test("a clock set back doesn't count as waiting", () {
      final future = monday.add(const Duration(days: 30));
      expect(mayInstallUpdateNow(kidsUserRunning: true, now: monday, waitingSince: future), isFalse);
    });
  });

  group("UpdateDeferral", () {
    late SharedPreferences prefs;
    late DateTime now;
    late bool kids;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      prefs = await SharedPreferences.getInstance();
      now = monday;
      kids = true;
    });

    UpdateDeferral deferral() => UpdateDeferral(prefs, () async => kids, now: () => now);

    test("remembers since when an update waits, from the first time, across restarts", () async {
      expect(await deferral().mayInstall("com.example.app", "2"), isFalse);
      expect(deferral().waitingSince("com.example.app"), monday);

      now = monday.add(const Duration(days: 3));
      expect(await deferral().mayInstall("com.example.app", "2"), isFalse);
      expect(deferral().waitingSince("com.example.app"), monday);

      now = monday.add(updateDeferralCap);
      expect(await deferral().mayInstall("com.example.app", "3"), isTrue);
    });

    test("installs as soon as no kids profile is running, and forgets the wait once up to date", () async {
      expect(await deferral().mayInstall("com.example.app", "2"), isFalse);
      kids = false;
      now = monday.add(const Duration(hours: 2));
      expect(await deferral().mayInstall("com.example.app", "2"), isTrue);

      await deferral().done("com.example.app");
      expect(deferral().waitingSince("com.example.app"), isNull);
    });

    test("each app waits on its own", () async {
      await deferral().mayInstall("com.example.one", "2");
      expect(deferral().waitingSince("com.example.two"), isNull);
    });
  });
}
