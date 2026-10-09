import 'dart:typed_data';

import 'package:flauncher/providers/profile_service.dart';
import 'package:flauncher/widgets/app_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Element? findAppCardByPackageName(WidgetTester tester, String packageName) {
  for (var val in tester.elementList(find.byType(AppCard))) {
    if ((val.widget as AppCard).application.packageName == packageName) {
      return val;
    }
  }
  return null;
}

/// The top bar's profile button, where Up from the first section lands.
Element? findProfileButton(WidgetTester tester) {
  try {
    return tester.element(find.byIcon(Icons.person));
  } catch (e) {
    return null;
  }
}

/// ProfileService's profile-switch state, with real notifications (a mock's listeners never hear anything).
class FakeProfileService extends ChangeNotifier implements ProfileService {
  String? _activeKey;
  String? _activeName;
  String? _incoming;
  ProfileTransition? _transition;
  String? _layoutReadyKey;

  /// The switches the welcome card has ended.
  final List<ProfileTransition> ended = [];

  FakeProfileService({String? activeKey, String? activeName})
      : _activeKey = activeKey,
        _activeName = activeName,
        _layoutReadyKey = activeKey;

  /// Google TV's chooser closed on [name]; null when the pick came to nothing.
  void pick(String? name) {
    _incoming = name;
    notifyListeners();
  }

  /// The switch to [key] is confirmed; its layout is still loading.
  ProfileTransition switchTo(String key, String name) {
    final transition = ProfileTransition(key, DateTime.now(), name);
    _transition = transition;
    _incoming = null;
    _activeKey = key;
    _activeName = name;
    _layoutReadyKey = null;
    notifyListeners();
    return transition;
  }

  /// The active profile's layout is in.
  void layoutReady() {
    _layoutReadyKey = _activeKey;
    notifyListeners();
  }

  @override
  String? get activeProfileKey => _activeKey;

  @override
  String? get activeProfileName => _activeName;

  @override
  Uint8List? get activeProfileAvatar => null;

  @override
  bool get settledOnce => true;

  @override
  ProfileTransition? get transition => _transition;

  @override
  String? get incomingName => _incoming;

  @override
  Uint8List? get incomingAvatar => null;

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

/// Real listeners for a generated mock of a ChangeNotifier service (the mock's own addListener does nothing), so a
/// test can change what it returns and have the home rebuild: mix it into the mock and call [changed].
mixin LiveListeners {
  final List<VoidCallback> _listeners = [];

  void addListener(VoidCallback? listener) {
    if (listener != null) _listeners.add(listener);
  }

  void removeListener(VoidCallback? listener) => _listeners.remove(listener);

  void changed() {
    for (final listener in List.of(_listeners)) {
      listener();
    }
  }
}
