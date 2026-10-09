import 'package:flauncher/flauncher_channel.dart';
import 'package:flauncher/l10n/app_localizations.dart';
import 'package:flauncher/widgets/hearth_move.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeChannel extends FLauncherChannel {
  final Map<String, Object?> status;
  int marked = 0;
  String? opened;

  _FakeChannel(this.status);

  @override
  Future<Map<dynamic, dynamic>> getMoveStatus() async => status;

  @override
  Future<void> markMoveNoticeShown() async => marked++;

  @override
  Future<bool> openNewHearth(String packageName) async {
    opened = packageName;
    return true;
  }
}

Future<void> _pump(WidgetTester tester, _FakeChannel channel) async {
  await tester.pumpWidget(MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: HearthMoveCheck(channel: channel, startDelay: Duration.zero, child: const Text('home')),
  ));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('after the move, says what came over and which PINs to enter again, once', (tester) async {
    final channel = _FakeChannel({
      'bridge': false,
      'state': 'imported',
      'noticeShown': false,
      'fromVersion': '2026.10.10',
      'pinsToReenter': 2,
      'legacyInstalled': true,
    });
    await _pump(tester, channel);
    expect(find.text('Hearth has moved'), findsOneWidget);
    expect(find.textContaining('(2026.10.10)'), findsOneWidget);
    expect(find.textContaining('Profile Pairing (2)'), findsOneWidget);
    expect(find.text('Remove the old Hearth'), findsOneWidget);
    expect(channel.marked, 1);
  });

  testWidgets('nothing once the notice was shown, or without a move', (tester) async {
    await _pump(tester, _FakeChannel({'bridge': false, 'state': 'imported', 'noticeShown': true}));
    expect(find.text('Hearth has moved'), findsNothing);
    await _pump(tester, _FakeChannel({'bridge': false, 'state': 'none', 'noticeShown': true}));
    expect(find.byType(AlertDialog), findsNothing);
  });

  testWidgets('says when the old Hearth is too old to hand its settings over', (tester) async {
    await _pump(tester, _FakeChannel(
        {'bridge': false, 'state': 'unavailable', 'noticeShown': false, 'legacyVersion': '2026.10.05'}));
    expect(find.text("The old Hearth can't hand over its settings"), findsOneWidget);
    expect(find.textContaining('(2026.10.05)'), findsOneWidget);
  });

  testWidgets('the bridge build opens the new Hearth once it is installed', (tester) async {
    final channel = _FakeChannel({
      'bridge': true,
      'newInstalled': true,
      'newVersion': '2026.10.11',
      'newPackage': 'com.thesiegs.hearth',
    });
    await _pump(tester, channel);
    expect(find.text('Hearth is moving'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(channel.opened, 'com.thesiegs.hearth');
  });
}
