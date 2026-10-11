import 'dart:async';
import 'dart:typed_data';

import 'package:flauncher/l10n/app_localizations.dart';
import 'package:flauncher/models/data_usage.dart';
import 'package:flauncher/providers/apps_service.dart';
import 'package:flauncher/providers/home_data_usage.dart';
import 'package:flauncher/providers/network_service.dart';
import 'package:flauncher/widgets/data_usage_row.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:provider/provider.dart';

import '../mocks.mocks.dart';

void main() {
  late MockNetworkService network;
  late MockAppsService apps;
  late HomeDataUsage home;

  const breakdown = DataUsageBreakdown(total: 10 * 1000 * 1000 * 1000, apps: [
    AppDataUsage(
        packageName: "com.example.tv", label: "Example TV", kind: DataUsageKind.app, bytes: 6 * 1000 * 1000 * 1000),
    AppDataUsage(packageName: "com.example.music", label: "Music", kind: DataUsageKind.app, bytes: 1500 * 1000 * 1000),
    AppDataUsage(kind: DataUsageKind.system, bytes: 400 * 1000 * 1000),
    AppDataUsage(kind: DataUsageKind.other, bytes: 900 * 1000 * 1000),
  ]);

  setUp(() {
    network = MockNetworkService();
    apps = MockAppsService();
    home = HomeDataUsage();
    when(network.networkType).thenReturn(NetworkType.wifi);
    when(network.offline).thenReturn(false);
    when(network.vpnActive).thenReturn(false);
    when(network.getDataUsageByApp(any)).thenAnswer((_) async => breakdown);
    when(apps.getAppIcon(any)).thenAnswer((_) async => Uint8List(0));
  });

  Widget underTest() => MultiProvider(
        providers: [
          ChangeNotifierProvider<NetworkService>.value(value: network),
          ChangeNotifierProvider<AppsService>.value(value: apps),
          ChangeNotifierProvider<HomeDataUsage>.value(value: home),
        ],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const Scaffold(body: DataUsageRow()),
        ),
      );

  testWidgets("shows the largest apps' data, Android's and everything else, for the period", (tester) async {
    home.setShowing(true, period: "daily");
    await tester.pumpWidget(underTest());
    await tester.pumpAndSettle();

    expect(find.text("DATA USAGE"), findsOneWidget);
    expect(find.text("10 GB on this TV · Today"), findsOneWidget);
    expect(find.text("Wi-Fi · OK: this week"), findsOneWidget);
    expect(find.text("Example TV"), findsOneWidget);
    expect(find.text("6 GB"), findsOneWidget);
    expect(find.text("Music"), findsOneWidget);
    expect(find.text("1.5 GB"), findsOneWidget);
    expect(find.text("Android system"), findsOneWidget);
    // 10 GB less the tiles' 7.9 GB
    expect(find.text("Everything else"), findsOneWidget);
    expect(find.text("2.1 GB"), findsOneWidget);
    verify(network.getDataUsageByApp("daily")).called(1);
  });

  testWidgets("asks again for a new period and each time it comes up, not on every rebuild", (tester) async {
    home.setShowing(true, period: "daily");
    await tester.pumpWidget(underTest());
    await tester.pumpAndSettle();
    verify(network.getDataUsageByApp("daily")).called(1);

    home.nextPeriod();
    await tester.pumpAndSettle();
    verify(network.getDataUsageByApp("weekly")).called(1);
    expect(find.text("10 GB on this TV · This week"), findsOneWidget);
    expect(find.text("Wi-Fi · OK: this month"), findsOneWidget);

    await tester.pumpWidget(underTest());
    await tester.pumpAndSettle();
    verifyNever(network.getDataUsageByApp(any));

    home.setShowing(false);
    await tester.pumpAndSettle();
    home.setShowing(true, period: "monthly");
    await tester.pumpAndSettle();
    verify(network.getDataUsageByApp("monthly")).called(1);
  });

  testWidgets("doesn't show an earlier period's numbers under a new period's name", (tester) async {
    final weekly = Completer<DataUsageBreakdown?>();
    when(network.getDataUsageByApp("weekly")).thenAnswer((_) => weekly.future);
    home.setShowing(true, period: "daily");
    await tester.pumpWidget(underTest());
    await tester.pumpAndSettle();
    expect(find.text("Example TV"), findsOneWidget);

    home.nextPeriod();
    await tester.pump();
    expect(find.text("This week"), findsOneWidget);
    expect(find.text("Example TV"), findsNothing);

    weekly.complete(breakdown);
    await tester.pumpAndSettle();
    expect(find.text("Example TV"), findsOneWidget);
  });

  testWidgets("says when nothing was used yet", (tester) async {
    when(network.getDataUsageByApp(any)).thenAnswer((_) async => const DataUsageBreakdown(total: 0, apps: []));
    home.setShowing(true);
    await tester.pumpWidget(underTest());
    await tester.pumpAndSettle();

    expect(find.text("No data used yet"), findsOneWidget);
    expect(find.text("0 B on this TV · Today"), findsOneWidget);
  });

  testWidgets("the connection line says no internet, VPN and that Ethernet isn't counted", (tester) async {
    final l = await AppLocalizations.delegate.load(const Locale("en"));
    when(network.offline).thenReturn(true);
    when(network.vpnActive).thenReturn(true);
    expect(dataUsageConnectionText(l, network), "Wi-Fi · No internet · VPN on");

    when(network.offline).thenReturn(false);
    when(network.vpnActive).thenReturn(false);
    when(network.networkType).thenReturn(NetworkType.wired);
    expect(dataUsageConnectionText(l, network), "Ethernet · Android doesn't count data over Ethernet");

    when(network.networkType).thenReturn(NetworkType.unknown);
    when(network.offline).thenReturn(true);
    expect(dataUsageConnectionText(l, network), "Not connected");

    when(network.networkType).thenReturn(NetworkType.vpn);
    when(network.offline).thenReturn(false);
    when(network.vpnActive).thenReturn(true);
    expect(dataUsageConnectionText(l, network), "VPN on");
  });
}
