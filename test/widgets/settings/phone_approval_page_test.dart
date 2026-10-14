import 'package:flauncher/flauncher_channel.dart';
import 'package:flauncher/l10n/app_localizations.dart';
import 'package:flauncher/widgets/settings/phone_approval_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

class _Channel extends FLauncherChannel {
  bool haConfigured = false;

  @override
  Future<Map<dynamic, dynamic>> getPhoneApproval() async => {"haConfigured": haConfigured, "on": false};
}

void main() {
  Future<void> pump(WidgetTester tester, _Channel channel) async {
    await tester.pumpWidget(Provider<FLauncherChannel>.value(
      value: channel,
      child: const MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(body: PhoneApprovalTile()),
      ),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets("without Home Assistant the row is greyed out and says what it needs", (tester) async {
    await pump(tester, _Channel());
    expect(find.text("Needs Home Assistant"), findsOneWidget);
    await tester.tap(find.text("Approve switches from my phone"));
    await tester.pumpAndSettle();
    expect(find.textContaining("Set up Home Assistant in Settings first"), findsOneWidget);
  });

  testWidgets("with Home Assistant it says whether it's on", (tester) async {
    await pump(tester, _Channel()..haConfigured = true);
    expect(find.text("Off"), findsOneWidget);
  });

  test("a companion app's notify service reads as the phone's name", () {
    expect(phoneName("mobile_app_alex_phone"), "Alex Phone");
  });
}
