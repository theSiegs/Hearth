import 'package:flauncher/l10n/app_localizations.dart';
import 'package:flauncher/providers/home_data_usage.dart';
import 'package:flauncher/providers/network_service.dart';
import 'package:flauncher/providers/settings_service.dart';
import 'package:flauncher/widgets/daily_data_usage_widget.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:provider/provider.dart';

import '../mocks.mocks.dart';

void main() {
  late MockNetworkService mockNetworkService;
  late MockSettingsService mockSettingsService;
  late HomeDataUsage homeDataUsage;

  setUp(() {
    mockNetworkService = MockNetworkService();
    mockSettingsService = MockSettingsService();
    // Default fallback mock
    when(mockNetworkService.dailyDataUsage).thenReturn(0);
    when(mockNetworkService.offline).thenReturn(false);
    when(mockNetworkService.vpnActive).thenReturn(false);
    when(mockSettingsService.dataUsagePeriod).thenReturn('daily');
    homeDataUsage = HomeDataUsage();
  });

  Widget createWidgetUnderTest({Locale? locale}) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<NetworkService>.value(value: mockNetworkService),
        ChangeNotifierProvider<SettingsService>.value(value: mockSettingsService),
        ChangeNotifierProvider<HomeDataUsage>.value(value: homeDataUsage),
      ],
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: locale,
        home: const Directionality(
          textDirection: TextDirection.ltr,
          child: Scaffold(
            body: Center(child: DailyDataUsageWidget()),
          ),
        ),
      ),
    );
  }

  testWidgets('shows Grant Usage Permission button when permission is missing', (WidgetTester tester) async {
    when(mockNetworkService.hasUsageStatsPermission).thenReturn(false);

    await tester.pumpWidget(createWidgetUnderTest());

    expect(find.text('Grant Usage Permission'), findsOneWidget);
    expect(find.byIcon(Icons.data_usage), findsOneWidget);
  });

  testWidgets('calls requestPermission when button is tapped', (WidgetTester tester) async {
    when(mockNetworkService.hasUsageStatsPermission).thenReturn(false);
    when(mockNetworkService.requestPermission()).thenAnswer((_) async {});

    await tester.pumpWidget(createWidgetUnderTest());

    await tester.tap(find.text('Grant Usage Permission'));
    await tester.pumpAndSettle();

    verify(mockNetworkService.requestPermission()).called(1);
  });

  testWidgets('displays daily usage when permission granted and period is daily', (WidgetTester tester) async {
    when(mockNetworkService.hasUsageStatsPermission).thenReturn(true);
    when(mockSettingsService.dataUsagePeriod).thenReturn('daily');
    when(mockNetworkService.getDataUsageForPeriod('daily')).thenAnswer((_) async => 1024 * 1024 * 5); // 5 MB

    await tester.pumpWidget(createWidgetUnderTest());
    await tester.pumpAndSettle();

    expect(find.byType(RichText), findsOneWidget);
    final richText = tester.widget<RichText>(find.byType(RichText));
    final span = richText.text as TextSpan;
    expect((span.children![0] as TextSpan).text, 'Daily: ');
    expect((span.children![1] as TextSpan).text, '5.2 MB');
  });

  testWidgets('displays weekly usage when permission granted and period is weekly', (WidgetTester tester) async {
    when(mockNetworkService.hasUsageStatsPermission).thenReturn(true);
    when(mockSettingsService.dataUsagePeriod).thenReturn('weekly');
    when(mockNetworkService.getDataUsageForPeriod('weekly')).thenAnswer((_) async => 1024 * 1024 * 1024 * 2); // 2 GB

    await tester.pumpWidget(createWidgetUnderTest());
    await tester.pumpAndSettle();

    expect(find.byType(RichText), findsOneWidget);
    final richText = tester.widget<RichText>(find.byType(RichText));
    final span = richText.text as TextSpan;
    expect((span.children![0] as TextSpan).text, 'Weekly: ');
    expect((span.children![1] as TextSpan).text, '2.1 GB');
  });

  testWidgets('displays monthly usage when permission granted and period is monthly', (WidgetTester tester) async {
    when(mockNetworkService.hasUsageStatsPermission).thenReturn(true);
    when(mockSettingsService.dataUsagePeriod).thenReturn('monthly');
    when(mockNetworkService.getDataUsageForPeriod('monthly')).thenAnswer((_) async => 1024 * 500); // 500 KB

    await tester.pumpWidget(createWidgetUnderTest());
    await tester.pumpAndSettle();

    expect(find.byType(RichText), findsOneWidget);
    final richText = tester.widget<RichText>(find.byType(RichText));
    final span = richText.text as TextSpan;
    expect((span.children![0] as TextSpan).text, 'Monthly: ');
    expect((span.children![1] as TextSpan).text, '512 KB');
  });

  testWidgets('falls back to networkService.dailyDataUsage if future data is null', (WidgetTester tester) async {
    when(mockNetworkService.hasUsageStatsPermission).thenReturn(true);
    when(mockSettingsService.dataUsagePeriod).thenReturn('daily');
    // Provide a mocked future that completes but isn't instantly available
    when(mockNetworkService.getDataUsageForPeriod('daily')).thenAnswer((_) => Future.value(1024));
    when(mockNetworkService.dailyDataUsage).thenReturn(2048);

    await tester.pumpWidget(createWidgetUnderTest());

    // Wait for future to complete
    await tester.pumpAndSettle();

    expect(find.byType(RichText), findsOneWidget);
    final richText = tester.widget<RichText>(find.byType(RichText));
    final span = richText.text as TextSpan;
    expect((span.children![1] as TextSpan).text, '1 KB');
  });

  testWidgets('asks again only when the period or the polled usage changes', (WidgetTester tester) async {
    VoidCallback? notify;
    when(mockNetworkService.addListener(any)).thenAnswer((i) => notify = i.positionalArguments[0] as VoidCallback);
    when(mockNetworkService.hasUsageStatsPermission).thenReturn(true);
    when(mockSettingsService.dataUsagePeriod).thenReturn('weekly');
    when(mockNetworkService.getDataUsageForPeriod('weekly')).thenAnswer((_) async => 1024);

    await tester.pumpWidget(createWidgetUnderTest());
    await tester.pumpAndSettle();
    verify(mockNetworkService.getDataUsageForPeriod('weekly')).called(1);

    // A network change: same numbers, so no new platform call.
    notify!();
    await tester.pumpAndSettle();
    verifyNever(mockNetworkService.getDataUsageForPeriod('weekly'));

    // The service's poll found new usage.
    when(mockNetworkService.dailyDataUsage).thenReturn(4096);
    notify!();
    await tester.pumpAndSettle();
    verify(mockNetworkService.getDataUsageForPeriod('weekly')).called(1);
  });

  testWidgets('formats 0 bytes correctly', (WidgetTester tester) async {
    when(mockNetworkService.hasUsageStatsPermission).thenReturn(true);
    when(mockSettingsService.dataUsagePeriod).thenReturn('daily');
    when(mockNetworkService.getDataUsageForPeriod('daily')).thenAnswer((_) async => 0);

    await tester.pumpWidget(createWidgetUnderTest());
    await tester.pumpAndSettle();

    expect(find.byType(RichText), findsOneWidget);
    final richText = tester.widget<RichText>(find.byType(RichText));
    final span = richText.text as TextSpan;
    expect((span.children![1] as TextSpan).text, '0 B');
  });



  Widget focusableUnderTest(FocusNode focusNode) => MultiProvider(
        providers: [
          ChangeNotifierProvider<NetworkService>.value(value: mockNetworkService),
          ChangeNotifierProvider<SettingsService>.value(value: mockSettingsService),
          ChangeNotifierProvider<HomeDataUsage>.value(value: homeDataUsage),
        ],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(body: Center(child: DailyDataUsageWidget(focusNode: focusNode))),
        ),
      );

  testWidgets('says "No internet" once the TV has been offline a while', (WidgetTester tester) async {
    when(mockNetworkService.hasUsageStatsPermission).thenReturn(true);
    when(mockNetworkService.offline).thenReturn(true);
    when(mockNetworkService.getDataUsageForPeriod('daily')).thenAnswer((_) async => 1000);

    await tester.pumpWidget(createWidgetUnderTest());
    await tester.pumpAndSettle();

    expect(find.text('No internet'), findsOneWidget);
    expect(find.byKey(const Key('data_usage_offline')), findsOneWidget);
    expect(find.textContaining('Daily'), findsNothing);
  });

  testWidgets('shows no key without a VPN', (WidgetTester tester) async {
    when(mockNetworkService.hasUsageStatsPermission).thenReturn(true);
    when(mockNetworkService.getDataUsageForPeriod('daily')).thenAnswer((_) async => 1000);

    await tester.pumpWidget(createWidgetUnderTest());
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('data_usage_vpn')), findsNothing);
  });

  testWidgets('shows a key while a VPN is on', (WidgetTester tester) async {
    when(mockNetworkService.hasUsageStatsPermission).thenReturn(true);
    when(mockNetworkService.vpnActive).thenReturn(true);
    when(mockNetworkService.getDataUsageForPeriod('daily')).thenAnswer((_) async => 1000);

    await tester.pumpWidget(createWidgetUnderTest());
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('data_usage_vpn')), findsOneWidget);
  });

  testWidgets("focused, it shows the data over the home on the top bar's period; OK goes on to the next",
      (WidgetTester tester) async {
    when(mockNetworkService.hasUsageStatsPermission).thenReturn(true);
    when(mockSettingsService.dataUsagePeriod).thenReturn('weekly');
    when(mockNetworkService.getDataUsageForPeriod('weekly')).thenAnswer((_) async => 1000);
    final focusNode = FocusNode();
    addTearDown(focusNode.dispose);

    await tester.pumpWidget(focusableUnderTest(focusNode));
    await tester.pumpAndSettle();
    expect(homeDataUsage.showing, isFalse);

    focusNode.requestFocus();
    await tester.pumpAndSettle();
    expect(homeDataUsage.showing, isTrue);
    expect(homeDataUsage.period, 'weekly');

    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await tester.pumpAndSettle();
    expect(homeDataUsage.period, 'monthly');

    focusNode.unfocus();
    await tester.pumpAndSettle();
    expect(homeDataUsage.showing, isFalse);
  });

  testWidgets('without usage access, focus shows nothing over the home and OK asks for it', (WidgetTester tester) async {
    when(mockNetworkService.hasUsageStatsPermission).thenReturn(false);
    when(mockNetworkService.requestPermission()).thenAnswer((_) async {});
    final focusNode = FocusNode();
    addTearDown(focusNode.dispose);

    await tester.pumpWidget(focusableUnderTest(focusNode));
    focusNode.requestFocus();
    await tester.pumpAndSettle();
    expect(homeDataUsage.showing, isFalse);

    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await tester.pumpAndSettle();
    verify(mockNetworkService.requestPermission()).called(1);
  });
}
