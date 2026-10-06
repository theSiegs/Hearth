import 'package:flauncher/flauncher_channel.dart';
import 'package:flauncher/widgets/home_button_fix_check.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeChannel extends FLauncherChannel {
  Map<String, bool> status;
  int opened = 0;
  int forgotten = 0;

  _FakeChannel(this.status);

  @override
  Future<Map<dynamic, dynamic>> getHomeButtonFixStatus() async => status;

  @override
  Future<bool> requestAccessibilityPermission() async {
    opened++;
    return true;
  }

  @override
  Future<void> forgetHomeButtonFix() async => forgotten++;
}

Future<void> _pump(WidgetTester tester, _FakeChannel channel) async {
  await tester.pumpWidget(MaterialApp(
    home: HomeButtonFixCheck(channel: channel, startDelay: Duration.zero, child: const Text('home')),
  ));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('no warning while the service is on', (tester) async {
    await _pump(tester, _FakeChannel({'enabled': true, 'seenBefore': true, 'restricted': false}));
    expect(find.text('Home Button Fix is off'), findsNothing);
  });

  testWidgets('no warning when the service was never turned on', (tester) async {
    await _pump(tester, _FakeChannel({'enabled': false, 'seenBefore': false, 'restricted': false}));
    expect(find.text('Home Button Fix is off'), findsNothing);
  });

  testWidgets('warns when the service was on and is now off, and opens settings', (tester) async {
    final channel = _FakeChannel({'enabled': false, 'seenBefore': true, 'restricted': false});
    await _pump(tester, channel);
    expect(find.text('Home Button Fix is off'), findsOneWidget);
    expect(find.textContaining('ACCESS_RESTRICTED_SETTINGS'), findsNothing);

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(find.text('Home Button Fix is off'), findsNothing);
    expect(channel.opened, 1);
  });

  testWidgets('explains a service Android lists as on but that is not running', (tester) async {
    await _pump(tester, _FakeChannel({'enabled': false, 'listedButStopped': true, 'seenBefore': true, 'restricted': false}));
    expect(find.textContaining('still lists it as on'), findsOneWidget);
  });

  testWidgets('shows the adb command when Android restricts the app', (tester) async {
    await _pump(tester, _FakeChannel({'enabled': false, 'seenBefore': true, 'restricted': true}));
    expect(find.textContaining('ACCESS_RESTRICTED_SETTINGS allow'), findsOneWidget);
  });

  testWidgets("Don't remind me forgets the service, and the warning shows once per run", (tester) async {
    final channel = _FakeChannel({'enabled': false, 'seenBefore': true, 'restricted': false});
    await _pump(tester, channel);
    await tester.tap(find.text("Don't remind me"));
    await tester.pumpAndSettle();
    expect(channel.forgotten, 1);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(find.text('Home Button Fix is off'), findsNothing);
  });
}
