import 'dart:typed_data';

import 'package:flauncher/providers/profile_service.dart';
import 'package:flauncher/widgets/profile_transition_overlay.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:provider/provider.dart';

import '../mocks.mocks.dart';

/// Just the switch state the overlay reads, with real notifications.
class _FakeProfiles extends ChangeNotifier implements ProfileService {
  ProfileTransition? _transition;
  String? _incoming;
  String? _layoutReadyKey;
  final List<ProfileTransition> ended = [];

  void pick(String? name) {
    _incoming = name;
    notifyListeners();
  }

  void begin(ProfileTransition transition) {
    _transition = transition;
    _incoming = null;
    notifyListeners();
  }

  void layoutReady(String key) {
    _layoutReadyKey = key;
    notifyListeners();
  }

  @override
  ProfileTransition? get transition => _transition;

  @override
  String? get incomingName => _incoming;

  @override
  Uint8List? get incomingAvatar => null;

  @override
  String? get activeProfileName => _transition?.pickedName;

  @override
  Uint8List? get activeProfileAvatar => null;

  @override
  bool layoutReadyFor(String key) => _layoutReadyKey == key;

  @override
  void endTransition(ProfileTransition transition) {
    if (_transition != transition) return;
    ended.add(transition);
    _transition = null;
    notifyListeners();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late _FakeProfiles profiles;
  late MockFLauncherChannel channel;

  setUp(() {
    profiles = _FakeProfiles();
    channel = MockFLauncherChannel();
    when(channel.setProfileReady(any)).thenAnswer((_) async {});
  });

  Future<void> pumpOverlay(WidgetTester tester) => tester.pumpWidget(
        ChangeNotifierProvider<ProfileService>.value(
          value: profiles,
          child: MaterialApp(home: Scaffold(body: ProfileTransitionOverlay(channel: channel))),
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

    final transition = ProfileTransition("user:11", DateTime.now(), "Sam");
    profiles.begin(transition);
    await tester.pump();
    await tester.pump();

    expect(find.text("Hi, Sam"), findsOneWidget);
    expect(cardFocused(), isTrue);
    expect(tester.widget<LinearProgressIndicator>(find.byType(LinearProgressIndicator)).value, 0.75);

    profiles.layoutReady("user:11");
    await tester.pump();
    await tester.pump();

    expect(profiles.ended, [transition]);
    verify(channel.setProfileReady("user:11")).called(1);
    expect(find.text("Hi, Sam"), findsNothing);
  });

  testWidgets("a switch that doesn't finish ends after maxWait", (tester) async {
    when(channel.isProfileDataReady()).thenAnswer((_) async => false);
    await pumpOverlay(tester);

    final transition = ProfileTransition("user:11", DateTime.now(), "Sam");
    profiles.begin(transition);
    await tester.pump();

    expect(find.text("Hi, Sam"), findsOneWidget);

    await tester.pump(ProfileTransitionOverlay.maxWait);
    await tester.pump();

    expect(profiles.ended, [transition]);
    expect(find.text("Hi, Sam"), findsNothing);
  });
}
