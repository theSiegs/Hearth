import 'package:flauncher/models/ha_lock_state.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final now = DateTime(2026, 10, 26, 18, 30);
  int ms(DateTime t) => t.millisecondsSinceEpoch;

  test("reads the pause, the lock, the next lock, the request and the groups out of time", () {
    final state = HaLockState.fromMap({
      "paired": true,
      "kids": true,
      "pause": {"reason": "Dinner", "until": ms(DateTime(2026, 10, 26, 19))},
      "lock": {"kind": "school_time", "until": null},
      "nextLock": {"kind": "bedtime", "at": ms(DateTime(2026, 10, 26, 20, 30))},
      "request": {"id": "r1", "status": "approved", "minutes": 30, "askedMinutes": 15, "group": "all"},
      "timeUp": [
        {"id": "games", "name": "Games"},
        {"id": null, "name": "TV"},
        {"name": ""},
      ],
    });
    expect(state.paused, isTrue);
    expect(state.pauseReason, "Dinner");
    expect(state.pauseUntil, DateTime(2026, 10, 26, 19));
    expect(state.lockKind, HaLockKind.schoolTime);
    expect(state.lockUntil, isNull);
    expect(state.nextLockKind, HaLockKind.bedtime);
    expect(state.request!.status, HaRequestStatus.approved);
    expect(state.request!.minutes, 30);
    expect(state.request!.askedMinutes, 15);
    expect(state.timeUp.map((g) => g.name), ["Games", "TV"]);
  });

  test("nothing from Home Assistant is no state, and no asking", () {
    expect(HaLockState.fromMap(null).canAsk, isFalse);
    expect(HaLockState.fromMap({}).paired, isFalse);
    expect(HaLockState.fromMap({"lock": {"kind": "homework"}}).lockKind, HaLockKind.other);
  });

  test("a kid asks only on a paired TV, with time up and nothing else holding them", () {
    const timeUp = [HaTimeUpGroup("games", "Games")];
    expect(const HaLockState(paired: true, kids: true, timeUp: timeUp).canAsk, isTrue);
    expect(const HaLockState(paired: false, kids: true, timeUp: timeUp).canAsk, isFalse);
    expect(const HaLockState(paired: true, kids: false, timeUp: timeUp).canAsk, isFalse);
    expect(const HaLockState(paired: true, kids: true).canAsk, isFalse);
    expect(const HaLockState(paired: true, kids: true, paused: true, timeUp: timeUp).canAsk, isFalse);
    expect(const HaLockState(paired: true, kids: true, lockKind: HaLockKind.bedtime, timeUp: timeUp).canAsk, isFalse);
  });

  test("asks for more of the held group, else All screen time, else the first", () {
    const state = HaLockState(timeUp: [HaTimeUpGroup("games", "Games"), HaTimeUpGroup("all", "All screen time")]);
    expect(state.askGroupFor("Games"), "games");
    expect(state.askGroupFor(null), "all");
    expect(const HaLockState(timeUp: [HaTimeUpGroup("games", "Games")]).askGroupFor("Other"), "games");
    expect(const HaLockState(timeUp: [HaTimeUpGroup(null, "Games")]).askGroupFor("Games"), "all");
  });

  test("not now starts a ten-minute wait from the answer", () {
    HaLockState denied(DateTime answered) => HaLockState(
        request: HaRequest(status: HaRequestStatus.denied, answered: answered));
    expect(denied(now.subtract(const Duration(minutes: 3))).cooldownLeftAt(now), const Duration(minutes: 7));
    expect(denied(now.subtract(const Duration(minutes: 10))).cooldownLeftAt(now), isNull);
    expect(HaLockState(request: HaRequest(status: HaRequestStatus.expired, answered: now)).cooldownLeftAt(now), isNull);
  });

  test("a pending request past its expiry is no longer waiting", () {
    final request = HaRequest(status: HaRequestStatus.pending, expires: now.add(const Duration(minutes: 1)));
    expect(request.isWaitingAt(now), isTrue);
    expect(request.isExpiredAt(now), isFalse);
    expect(request.isWaitingAt(now.add(const Duration(minutes: 1))), isFalse);
    expect(request.isExpiredAt(now.add(const Duration(minutes: 1))), isTrue);
  });

  test("minutes round up", () {
    expect(minutesRoundedUp(const Duration(minutes: 6, seconds: 1)), 7);
    expect(minutesRoundedUp(const Duration(minutes: 7)), 7);
    expect(minutesRoundedUp(Duration.zero), 1);
  });
  test("minutes left for an app: the fewest of the groups it counts in", () {
    final state = HaLockState.fromMap({
      "paired": true,
      "kids": true,
      "groups": [
        {"id": "games", "name": "Games", "minutesLeft": 20, "apps": ["com.example.game"], "except": []},
        {"id": "all", "name": "All screen time", "minutesLeft": 45, "apps": [], "except": ["com.example.music"]},
        {"id": "bad", "name": "No minutes"},
      ],
    });
    expect(state.groups.length, 2);
    expect(state.minutesLeftFor("com.example.game"), 20);
    expect(state.minutesLeftFor("com.example.tv"), 45);
    expect(state.minutesLeftFor("com.example.music"), isNull);
    expect(HaLockState.none.minutesLeftFor("com.example.tv"), isNull);
  });
}
