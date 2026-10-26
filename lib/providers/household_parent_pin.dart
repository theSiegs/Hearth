import 'package:flauncher/flauncher_channel.dart';
import 'package:flauncher/providers/parent_pin_hash.dart';
import 'package:flauncher/providers/settings_service.dart';
import 'package:flauncher/quiet_failure.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// What one round of [HouseholdParentPin] does.
enum ParentPinStep {
  /// Nothing to do: this TV's and the household's agree.
  none,

  /// The household's Parent PIN becomes this TV's.
  take,

  /// The household removed its Parent PIN: this TV's goes too.
  remove,

  /// This TV's (or its removal) goes to the household: it was changed here, past the PIN.
  give,

  /// This TV had its own Parent PIN before it joined, and the household's differs: it's kept until an adult enters
  /// the household's here (Settings > Family > Parent PIN), so joining can't replace it unseen.
  ask,
}

/// The household's Parent PIN (docs/household-sync.md, "Parent PIN"): one for every TV, kept as the salted hash, never
/// the PIN, the newest change winning. A TV that joins without a Parent PIN takes the household's. A TV with its own,
/// different one is asked for the household's before it takes it. A change made here (which needs the PIN here) goes
/// out. What this TV last took or gave is remembered, which is how a change here is told from one in the household.
class HouseholdParentPin {
  /// device_: the TV's own, never in a backup. The hash this TV last took from or gave to the household.
  static const String knownKey = "device_household_parent_pin_known";

  final FLauncherChannel _channel;
  final SharedPreferences _prefs;
  final SettingsService _settings;

  HouseholdParentPin(this._channel, this._prefs, this._settings);

  /// The rule, pure: [household] is the household's hash (null when it has none), [householdRemoved] when it had one
  /// and removed it; [local] this TV's; [known] what this TV last took or gave ("" for none; null: nothing yet since
  /// it joined).
  static ParentPinStep decide(
      {required String? household, required bool householdRemoved, required String? local, required String? known}) {
    if (known == null) {
      if (local == null) return household != null ? ParentPinStep.take : ParentPinStep.none;
      if (household == null) return ParentPinStep.give;
      return household == local ? ParentPinStep.none : ParentPinStep.ask;
    }
    // Changed here since: it goes out
    if ((local ?? "") != known) return ParentPinStep.give;
    if (household != null) return household == local ? ParentPinStep.none : ParentPinStep.take;
    if (householdRemoved) return local == null ? ParentPinStep.none : ParentPinStep.remove;
    // The household has none (a household older than this kind): this TV's is the first
    return local == null ? ParentPinStep.none : ParentPinStep.give;
  }

  /// One round: outside a household, forgets what it knew (a household joined later starts fresh).
  Future<void> tick() async {
    try {
      final state = await _channel.getHouseholdParentPin();
      if (state == null) {
        await _prefs.remove(knownKey);
        await _settings.setHouseholdParentPinOffered(null);
        return;
      }
      final hash = state["state"] == "live" ? state["hash"] as String? : null;
      final household = hash != null && ParentPinHash.pattern.hasMatch(hash) ? hash : null;
      final local = _settings.parentPinHash;
      final step = decide(
          household: household,
          householdRemoved: state["state"] == "removed",
          local: local,
          known: _prefs.getString(knownKey));
      switch (step) {
        case ParentPinStep.none:
          await _setKnown(local);
          await _settings.setHouseholdParentPinOffered(null);
        case ParentPinStep.take:
          await _settings.setParentPinHash(household!);
          await _setKnown(household);
          await _settings.setHouseholdParentPinOffered(null);
        case ParentPinStep.remove:
          await _settings.setParentPin(null);
          await _setKnown(null);
        case ParentPinStep.give:
          if (await _channel.publishHouseholdParentPin(local)) await _setKnown(local);
        case ParentPinStep.ask:
          await _settings.setHouseholdParentPinOffered(household);
      }
    } catch (err) {
      noteFailure('household_parent_pin', err);
    }
  }

  /// Null is remembered as "" (known to be none), so a removal here isn't taken for "never synced".
  Future<void> _setKnown(String? hash) => _prefs.setString(knownKey, hash ?? "");
}
