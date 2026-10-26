import 'package:flauncher/flauncher_channel.dart';
import 'package:flauncher/providers/household_parent_pin.dart';
import 'package:flauncher/providers/parent_pin_hash.dart';
import 'package:flauncher/providers/settings_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The household's side, as the Java side reports it, and what this TV gave it.
class _FakeChannel extends FLauncherChannel {
  bool member = true;
  String state = "none";
  String? hash;
  final List<String?> given = [];

  @override
  Future<Map<dynamic, dynamic>?> getHouseholdParentPin() async =>
      member ? {"state": state, if (hash != null) "hash": hash} : null;

  @override
  Future<bool> publishHouseholdParentPin(String? hash) async {
    if (!member) return false;
    given.add(hash);
    state = hash == null ? "removed" : "live";
    this.hash = hash;
    return true;
  }
}

void main() {
  // Cheap hashes for the test (the cost is part of the stored value)
  final a = ParentPinHash.hash("2468", salt: List.filled(16, 1), cost: 2);
  final b = ParentPinHash.hash("1357", salt: List.filled(16, 2), cost: 2);

  group("the rule", () {
    ParentPinStep decide({String? household, bool removed = false, String? local, String? known}) =>
        HouseholdParentPin.decide(household: household, householdRemoved: removed, local: local, known: known);

    test("a TV without a Parent PIN takes the household's", () {
      expect(decide(household: a), ParentPinStep.take);
      expect(decide(), ParentPinStep.none);
    });

    test("a TV with its own, different one asks before taking the household's", () {
      expect(decide(household: a, local: b), ParentPinStep.ask);
      expect(decide(household: a, local: a), ParentPinStep.none);
    });

    test("the first TV with one gives it to a household that has none", () {
      expect(decide(local: a), ParentPinStep.give);
      expect(decide(local: a, known: a), ParentPinStep.give);
    });

    test("changed or removed here: it goes out", () {
      expect(decide(household: a, local: b, known: a), ParentPinStep.give);
      expect(decide(household: a, local: null, known: a), ParentPinStep.give);
    });

    test("changed or removed on another TV: this TV follows", () {
      expect(decide(household: b, local: a, known: a), ParentPinStep.take);
      expect(decide(removed: true, local: a, known: a), ParentPinStep.remove);
      expect(decide(removed: true, local: null, known: ""), ParentPinStep.none);
      // Removed, then set again elsewhere
      expect(decide(household: b, local: null, known: ""), ParentPinStep.take);
    });
  });

  group("rounds", () {
    late SharedPreferences prefs;
    late SettingsService settings;
    late _FakeChannel channel;
    late HouseholdParentPin sync;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      prefs = await SharedPreferences.getInstance();
      settings = SettingsService(prefs);
      channel = _FakeChannel();
      sync = HouseholdParentPin(channel, prefs, settings);
    });

    test("joined without a Parent PIN: the household's is this TV's after one round", () async {
      channel
        ..state = "live"
        ..hash = a;
      await sync.tick();
      expect(settings.parentPinHash, a);
      expect(settings.verifyParentPin("2468"), isTrue);
      expect(channel.given, isEmpty);
    });

    test("joined with its own: kept until the household's is entered here", () async {
      await settings.setParentPinHash(b);
      channel
        ..state = "live"
        ..hash = a;
      await sync.tick();
      expect(settings.parentPinHash, b);
      expect(settings.householdParentPinOffered, a);
      // Changing this TV's own meanwhile doesn't reach the household
      await settings.setParentPin("9999");
      await sync.tick();
      expect(channel.given, isEmpty);
      expect(settings.verifyHouseholdParentPin("1357"), isFalse);
      expect(settings.verifyHouseholdParentPin("2468"), isTrue);
      await settings.takeHouseholdParentPin();
      await sync.tick();
      expect(settings.parentPinHash, a);
      expect(settings.householdParentPinOffered, isNull);
      // From now on a change here goes out
      await settings.setParentPin("1111");
      await sync.tick();
      expect(channel.given.single, settings.parentPinHash);
    });

    test("removed here goes out; removed elsewhere is removed here", () async {
      channel
        ..state = "live"
        ..hash = a;
      await sync.tick();
      await settings.setParentPin(null);
      await sync.tick();
      expect(channel.given, [null]);
      expect(channel.state, "removed");

      channel
        ..state = "live"
        ..hash = b;
      await sync.tick();
      expect(settings.parentPinHash, b);
      channel
        ..state = "removed"
        ..hash = null;
      await sync.tick();
      expect(settings.hasParentPin, isFalse);
    });

    test("outside a household nothing changes, and what it knew is forgotten", () async {
      channel
        ..state = "live"
        ..hash = a;
      await sync.tick();
      channel.member = false;
      await sync.tick();
      expect(prefs.getString(HouseholdParentPin.knownKey), isNull);
      expect(settings.parentPinHash, a);
    });
  });
}
