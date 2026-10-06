import 'package:flauncher/widgets/settings/setup_checklist_page.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';

import '../../mocks.mocks.dart';

void main() {
  late MockFLauncherChannel channel;

  setUp(() {
    channel = MockFLauncherChannel();
    when(channel.isDefaultLauncher()).thenAnswer((_) async => true);
    when(channel.getHomeButtonFixStatus()).thenAnswer((_) async => {"enabled": false, "restricted": true});
    when(channel.checkNotificationListenerPermission()).thenAnswer((_) async => true);
    when(channel.checkInstallPermission()).thenAnswer((_) async => false);
    when(channel.getProfilePairingStatus()).thenAnswer((_) async => {"enabled": true, "voiceDefault": false});
  });

  test("reports each step from the TV's state", () async {
    final steps = await loadSetupSteps(channel, "com.example.hearth");
    final done = {for (final step in steps) step.title: step.done};
    expect(done, {
      "Hearth as the home app": true,
      "Home Button Fix": false,
      "Notification access": true,
      "Installing updates": false,
      "Profile Pairing": true,
      "Hearth voice": false,
    });
    expect(steps.where((s) => s.optional).map((s) => s.title), ["Profile Pairing", "Hearth voice"]);
  });

  test("accessibility steps name the exact service and the adb fix when restricted", () async {
    final steps = await loadSetupSteps(channel, "com.example.hearth");
    final homeFix = steps.singleWhere((s) => s.title == "Home Button Fix");
    expect(homeFix.instructions, contains('"Hearth Home Button Fix"'));
    expect(homeFix.warning, contains("adb shell appops set com.example.hearth ACCESS_RESTRICTED_SETTINGS allow"));
  });

  test("a failing check counts as not done instead of breaking the list", () async {
    when(channel.checkInstallPermission()).thenThrow(Exception("no channel"));
    final steps = await loadSetupSteps(channel, "com.example.hearth");
    expect(steps.singleWhere((s) => s.title == "Installing updates").done, isFalse);
  });
}
