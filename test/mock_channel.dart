import 'package:mockito/mockito.dart';

import 'mocks.mocks.dart';

/// A mock channel for a real AppsService, which always listens for app changes.
MockFLauncherChannel mockChannelForAppsService() {
  final channel = MockFLauncherChannel();
  when(channel.addAppsChangedListener(any)).thenAnswer((_) => const Stream<void>.empty().listen(null));
  return channel;
}
