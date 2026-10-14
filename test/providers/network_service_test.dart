import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flauncher/providers/network_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';

import '../mocks.mocks.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late MockFLauncherChannel channel;
  late StreamController<Map<String, dynamic>> changes;

  setUp(() {
    channel = MockFLauncherChannel();
    changes = StreamController<Map<String, dynamic>>.broadcast();
    when(channel.getNetworkStatus()).thenAnswer((_) async => {"type": "wifi", "vpn": false, "internet": true});
    when(channel.networkStatusChanges()).thenAnswer((_) => changes.stream);
    when(channel.checkUsageStatsPermission()).thenAnswer((_) async => true);
    when(channel.getDailyDataUsage()).thenAnswer((_) async => 2048);
    when(channel.getWeeklyDataUsage()).thenAnswer((_) async => 4096);
    when(channel.getMonthlyDataUsage()).thenAnswer((_) async => 8192);
  });

  tearDown(() => changes.close());

  test("reads the connection, and follows its changes", () async {
    final service = NetworkService(channel);
    await pumpEventQueue();
    expect(service.networkType, NetworkType.wifi);
    expect(service.hasInternetAccess, isTrue);
    expect(service.vpnActive, isFalse);

    changes.add({"type": "wired", "vpn": true, "internet": true});
    await pumpEventQueue();
    expect(service.networkType, NetworkType.wired);
    expect(service.vpnActive, isTrue);

    changes.add({"type": "something new", "vpn": false, "internet": false});
    await pumpEventQueue();
    expect(service.networkType, NetworkType.none);
    service.dispose();
  });

  test("offline only after the internet has been gone a while", () {
    fakeAsync((async) {
      final service = NetworkService(channel);
      async.flushMicrotasks();
      service.applyStatus({"type": "wifi", "vpn": false, "internet": false});
      async.elapse(NetworkService.offlineGrace - const Duration(seconds: 1));
      expect(service.offline, isFalse);
      async.elapse(const Duration(seconds: 2));
      expect(service.offline, isTrue);
      // Back: at once
      service.applyStatus({"type": "wifi", "vpn": false, "internet": true});
      expect(service.offline, isFalse);
      // A blip shorter than the grace never shows
      service.applyStatus({"type": "wifi", "vpn": false, "internet": false});
      async.elapse(const Duration(seconds: 3));
      service.applyStatus({"type": "wifi", "vpn": false, "internet": true});
      async.elapse(NetworkService.offlineGrace);
      expect(service.offline, isFalse);
      service.dispose();
    });
  });

  test("reads today's usage with usage access, and each period on request", () async {
    final service = NetworkService(channel);
    await pumpEventQueue();
    expect(service.hasUsageStatsPermission, isTrue);
    expect(service.dailyDataUsage, 2048);
    expect(await service.getDataUsageForPeriod("weekly"), 4096);
    expect(await service.getDataUsageForPeriod("monthly"), 8192);
    expect(await service.getDataUsageForPeriod("daily"), 2048);
    service.dispose();
  });

  test("without usage access nothing is read", () async {
    when(channel.checkUsageStatsPermission()).thenAnswer((_) async => false);
    final service = NetworkService(channel);
    await pumpEventQueue();
    expect(service.hasUsageStatsPermission, isFalse);
    verifyNever(channel.getDailyDataUsage());
    service.dispose();
  });

  test("asks Android for usage access", () async {
    when(channel.requestUsageStatsPermission()).thenAnswer((_) async {});
    final service = NetworkService(channel);
    await service.requestPermission();
    verify(channel.requestUsageStatsPermission()).called(1);
    service.dispose();
  });
}
