import 'package:flauncher/models/kids_profiles.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  KidsProfilesState state(List<Map<String, dynamic>> kids, {bool tube = false}) =>
      KidsProfilesState.fromMap({"kids": kids, "hearthTubeOnOwner": tube});

  test("HearthTube counts only when the owner has it", () {
    final kid = {"userId": 10, "hearth": true, "hearthTube": false};
    expect(state([kid]).statusOf(state([kid]).kids.single), KidProfileStatus.ready);
    final withTube = state([kid], tube: true);
    expect(withTube.statusOf(withTube.kids.single), KidProfileStatus.hearthTubeMissing);
  });

  test("a copy Google TV can remove needs a fix; one not read yet doesn't", () {
    final unread = state([
      {"userId": 10, "hearth": true, "hearthKept": null}
    ]);
    expect(unread.allReady, isTrue);
    final unkept = state([
      {"userId": 10, "hearth": true, "hearthKept": false}
    ]);
    expect(unkept.statusOf(unkept.kids.single), KidProfileStatus.notKept);
    expect(unkept.needingFix, 1);
  });

  test("no Hearth at all, and no kids' profiles", () {
    final missing = state([
      {"userId": 10, "profileKey": "user:10", "hearth": false}
    ]);
    expect(missing.statusOf(missing.kids.single), KidProfileStatus.hearthMissing);
    expect(missing.kids.single.profileKey, "user:10");
    expect(state([]).allReady, isFalse);
    expect(state([]).needingFix, 0);
  });
}
