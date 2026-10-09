import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Hearth's Android side as far as Google TV profiles go, faked at the method channel: what
/// LauncherAccessibilityService / ProfileUsers would answer (the active profile's key, name, whether it's a kids
/// profile, whether its agent has reported) and the calls they make into Flutter when Google TV switches profile
/// ("profileSwitching" when the chooser closes on a pick, "profileChanged" once the profile user has settled).
///
/// Unlike FakeProfileService, this drives the real ProfileService, so a test covers the whole Dart side of a switch:
/// channel calls → ProfileService → welcome card / Settings lock → setProfileReady back to Android.
class FakeNativeProfiles {
  static const MethodChannel channel = MethodChannel('me.efesser.flauncher/method');

  final TestDefaultBinaryMessenger _messenger;

  /// The active profile, as Android reports it ("user:0" for the TV owner, "user:10" for a profile user).
  String? key;

  /// Its Google TV name, once Hearth has read it from the chooser (null until then).
  String? name;

  /// Whether Family Link supervises it (ProfileUsers.isKids).
  bool kids;

  /// Whether the profile's agent has reported its native data (MainActivity.isProfileDataReady).
  bool dataReady = true;

  /// The keys Flutter has said are ready (setProfileReady), in order.
  final List<String> readyKeys = [];

  /// Every method Flutter called, in order.
  final List<String> calls = [];

  FakeNativeProfiles(this._messenger, {this.key = "user:0", this.name, this.kids = false}) {
    _messenger.setMockMethodCallHandler(channel, _handle);
  }

  /// Installs the fake on [tester]'s messenger and removes it when the test ends.
  factory FakeNativeProfiles.install(WidgetTester tester, {String? key = "user:0", String? name, bool kids = false}) {
    final fake = FakeNativeProfiles(tester.binding.defaultBinaryMessenger, key: key, name: name, kids: kids);
    addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, null));
    return fake;
  }

  Future<Object?> _handle(MethodCall call) async {
    calls.add(call.method);
    switch (call.method) {
      case "getActiveProfileKey":
        return key;
      case "getActiveProfileName":
        return name;
      case "isKidsProfile":
        return kids;
      case "isProfileDataReady":
        return dataReady;
      case "setProfileReady":
        readyKeys.add(call.arguments as String);
        return null;
      case "getProfileAvatar":
        return {"modified": 0, "png": null};
    }
    // Permission checks and the like: "no"
    return call.method.startsWith("check") || call.method.startsWith("is") ? false : null;
  }

  /// Google TV's chooser closed on [pickedName]: Hearth shows the welcome card before the switch is confirmed.
  Future<void> pick(String pickedName) => _send("profileSwitching", pickedName);

  /// Hearth came back without Google TV's home in between: the pick was cancelled (Back out of a PIN prompt).
  Future<void> cancelPick() => _send("profileSwitchCancelled");

  /// The switch has settled on the profile user [newKey]: Android now reports it and tells Flutter.
  Future<void> switchTo(String newKey, {String? name, bool kids = false, bool dataReady = true}) {
    key = newKey;
    this.name = name;
    this.kids = kids;
    this.dataReady = dataReady;
    return _send("profileChanged");
  }

  Future<void> _send(String method, [Object? arguments]) => _messenger.handlePlatformMessage(
        channel.name,
        channel.codec.encodeMethodCall(MethodCall(method, arguments)),
        (_) {},
      );
}
