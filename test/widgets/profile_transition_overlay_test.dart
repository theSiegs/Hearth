import 'package:flauncher/l10n/app_localizations.dart';
import 'package:flauncher/providers/profile_service.dart';
import 'package:flauncher/widgets/profile_transition_overlay.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:provider/provider.dart';

import '../helpers.dart';
import '../mocks.mocks.dart';

void main() {
  late FakeProfileService profiles;
  late MockFLauncherChannel channel;

  setUp(() {
    profiles = FakeProfileService(activeKey: "user:0", activeName: "Alex");
    channel = MockFLauncherChannel();
    when(channel.setProfileReady(any)).thenAnswer((_) async {});
  });

  Future<void> pumpOverlay(WidgetTester tester) => tester.pumpWidget(
        ChangeNotifierProvider<ProfileService>.value(
          value: profiles,
          child: MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(body: ProfileTransitionOverlay(channel: channel)),
          ),
        ),
      );

  bool cardFocused() => FocusManager.instance.primaryFocus?.debugLabel == "profile_transition";

  testWidgets("shows nothing while no profile is on its way", (tester) async {
    await pumpOverlay(tester);

    expect(find.byType(LinearProgressIndicator), findsNothing);
  });

  testWidgets("a profile picked in the chooser shows its card and takes focus", (tester) async {
    await pumpOverlay(tester);

    profiles.pick("Sam");
    await tester.pump();
    await tester.pump();

    expect(find.text("Hi, Sam"), findsOneWidget);
    expect(cardFocused(), isTrue);

    profiles.pick(null);
    await tester.pump();

    expect(find.text("Hi, Sam"), findsNothing);
  });

  testWidgets("a switch ends once its layout and native data are in", (tester) async {
    when(channel.isProfileDataReady()).thenAnswer((_) async => true);
    await pumpOverlay(tester);

    final transition = profiles.switchTo("user:11", "Sam");
    await tester.pump();
    await tester.pump();

    expect(find.text("Hi, Sam"), findsOneWidget);
    expect(cardFocused(), isTrue);
    expect(tester.widget<LinearProgressIndicator>(find.byType(LinearProgressIndicator)).value, 0.75);

    profiles.layoutReady();
    await tester.pump();
    await tester.pump();

    expect(profiles.ended, [transition]);
    verify(channel.setProfileReady("user:11")).called(1);
    expect(find.text("Hi, Sam"), findsNothing);
  });

  testWidgets("a switch that doesn't finish ends after maxWait", (tester) async {
    when(channel.isProfileDataReady()).thenAnswer((_) async => false);
    await pumpOverlay(tester);

    final transition = profiles.switchTo("user:11", "Sam");
    await tester.pump();

    expect(find.text("Hi, Sam"), findsOneWidget);

    await tester.pump(ProfileTransitionOverlay.maxWait);
    await tester.pump();

    expect(profiles.ended, [transition]);
    expect(find.text("Hi, Sam"), findsNothing);
  });
}
