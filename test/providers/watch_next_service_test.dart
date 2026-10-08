import 'dart:async';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:flauncher/providers/watch_next_service.dart';
import 'package:flauncher/models/watch_next_program.dart';
import 'package:flauncher/providers/settings_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../mocks.mocks.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // A day after the test programs' engagement times (Sep 2020), so none counts as old
  DateTime clock() => DateTime.fromMillisecondsSinceEpoch(1600000000000 + const Duration(days: 1).inMilliseconds);
  late MockFLauncherChannel mockChannel;
  late SharedPreferences prefs;
  late StreamController<dynamic> watchNextStreamController;
  late WatchNextService watchNextService;

  setUp(() async {
    // Ownership tracking has started (no stored owners), and the active profile last used every test app
    SharedPreferences.setMockInitialValues({'watch_next_owners_v2': '{}'});
    prefs = await SharedPreferences.getInstance();
    mockChannel = MockFLauncherChannel();
    watchNextStreamController = StreamController<dynamic>.broadcast();
    // Default stubs
    when(mockChannel.getActiveProfileKey()).thenAnswer((_) async => 'user:0');
    when(mockChannel.getAppLastProfiles()).thenAnswer((_) async => {
          for (final pkg in [
            'com.google.android.youtube.tv',
            'com.netflix.mediaclient',
            'com.lagradost.cloudstream3',
            'in.startv.hotstar',
            'com.example.tv',
          ])
            pkg: 'user:0',
        });
    when(mockChannel.getWatchNextPrograms()).thenAnswer((_) async => []);
    when(mockChannel.checkWatchNextPermission()).thenAnswer((_) async => true);
    when(mockChannel.addWatchNextChangedListener(any)).thenAnswer((invocation) {
      final void Function(dynamic) listener = invocation.positionalArguments[0];
      return watchNextStreamController.stream.listen(listener);
    });
  });

  tearDown(() {
    watchNextStreamController.close();
  });

  group('WatchNextService Initialization', () {
    test('initializes with empty programs list', () async {
      watchNextService = WatchNextService(mockChannel, prefs, clock: clock);
      while (!watchNextService.initialized) {
        await Future.delayed(Duration.zero);
      }

      expect(watchNextService.programs, isEmpty);
      verify(mockChannel.getWatchNextPrograms()).called(1);
    });

    test('refreshes watch next programs when event stream emits change', () async {
      watchNextService = WatchNextService(mockChannel, prefs, clock: clock);
      while (!watchNextService.initialized) {
        await Future.delayed(Duration.zero);
      }

      expect(watchNextService.programs, isEmpty);
      verify(mockChannel.getWatchNextPrograms()).called(1);

      final fakePrograms = [
        {
          'id': 10,
          'packageName': 'com.google.android.youtube.tv',
          'title': 'YouTube Video',
          'description': 'Channel Name',
          'watchNextType': 1,
          'lastEngagementTime': 1600000000,
          'playbackPosition': 100,
          'duration': 500,
          'intentUri': 'intent://youtube',
          'posterArtUri': ''
        }
      ];
      when(mockChannel.getWatchNextPrograms()).thenAnswer((_) async => fakePrograms);

      watchNextStreamController.add(true);
      await pumpEventQueue();

      expect(watchNextService.programs.length, 1);
      expect(watchNextService.programs[0].title, 'YouTube Video');
      verify(mockChannel.getWatchNextPrograms()).called(1);
    });

    test('fetches watch next programs on init', () async {
      final fakePrograms = [
        {
          'id': 1,
          'packageName': 'com.netflix.mediaclient',
          'title': 'Stranger Things',
          'description': 'S1:E1 Chapter One',
          'watchNextType': 1,
          'lastEngagementTime': 1600000000,
          'playbackPosition': 500,
          'duration': 3000,
          'intentUri': 'intent://netflix_uri',
          'posterArtUri': 'content://netflix/poster/1'
        }
      ];

      when(mockChannel.getWatchNextPrograms()).thenAnswer((_) async => fakePrograms);

      watchNextService = WatchNextService(mockChannel, prefs, clock: clock);
      while (!watchNextService.initialized) {
        await Future.delayed(Duration.zero);
      }

      expect(watchNextService.programs.length, 1);
      expect(watchNextService.programs[0].title, 'Stranger Things');

      verify(mockChannel.getWatchNextPrograms()).called(1);
    });

    test('sorts watch next programs with most recently watched first', () async {
      final fakePrograms = [
        {
          'id': 1,
          'packageName': 'com.lagradost.cloudstream3',
          'title': 'Older Stream',
          'description': 'Episode 1',
          'watchNextType': 1,
          'lastEngagementTime': 1600000000000,
          'playbackPosition': 500,
          'duration': 3000,
          'intentUri': 'intent://older',
          'posterArtUri': ''
        },
        {
          'id': 2,
          'packageName': 'in.startv.hotstar',
          'title': 'Recent Movie',
          'description': 'Watched Just Now',
          'watchNextType': 1,
          'lastEngagementTime': 1700000000000,
          'playbackPosition': 200,
          'duration': 7200,
          'intentUri': 'intent://recent',
          'posterArtUri': ''
        }
      ];

      when(mockChannel.getWatchNextPrograms()).thenAnswer((_) async => fakePrograms);

      watchNextService = WatchNextService(mockChannel, prefs, clock: clock);
      while (!watchNextService.initialized) {
        await Future.delayed(Duration.zero);
      }

      expect(watchNextService.programs.length, 2);
      expect(watchNextService.programs[0].title, 'Recent Movie');
      expect(watchNextService.programs[1].title, 'Older Stream');
    });
    test('handles missing permission by setting hasPermission to false and clearing programs', () async {
      when(mockChannel.checkWatchNextPermission()).thenAnswer((_) async => false);

      watchNextService = WatchNextService(mockChannel, prefs, clock: clock);
      while (!watchNextService.initialized) {
        await Future.delayed(Duration.zero);
      }

      expect(watchNextService.hasPermission, isFalse);
      expect(watchNextService.programs, isEmpty);
      verify(mockChannel.checkWatchNextPermission()).called(1);
      verifyNever(mockChannel.getWatchNextPrograms());
    });

    test('handles channel getWatchNextPrograms error gracefully without throwing', () async {
      when(mockChannel.getWatchNextPrograms()).thenThrow(Exception('Channel failure'));

      watchNextService = WatchNextService(mockChannel, prefs, clock: clock);
      while (!watchNextService.initialized) {
        await Future.delayed(Duration.zero);
      }

      expect(watchNextService.programs, isEmpty);
      verify(mockChannel.getWatchNextPrograms()).called(1);
    });
  });

  group('WatchNextService Permissions', () {
    test('checkPermission queries channel directly', () async {
      when(mockChannel.checkWatchNextPermission()).thenAnswer((_) async => false);
      watchNextService = WatchNextService(mockChannel, prefs, clock: clock);
      while (!watchNextService.initialized) {
        await Future.delayed(Duration.zero);
      }

      final result = await watchNextService.checkPermission();
      expect(result, isFalse);
    });

    test('requestPermission requests channel permission and refreshes on grant', () async {
      when(mockChannel.requestWatchNextPermission()).thenAnswer((_) async => true);
      watchNextService = WatchNextService(mockChannel, prefs, clock: clock);
      while (!watchNextService.initialized) {
        await Future.delayed(Duration.zero);
      }

      final granted = await watchNextService.requestPermission();
      expect(granted, isTrue);
      verify(mockChannel.requestWatchNextPermission()).called(1);
    });

    test('requestPermission returns false when denied', () async {
      when(mockChannel.requestWatchNextPermission()).thenAnswer((_) async => false);
      watchNextService = WatchNextService(mockChannel, prefs, clock: clock);
      while (!watchNextService.initialized) {
        await Future.delayed(Duration.zero);
      }

      final granted = await watchNextService.requestPermission();
      expect(granted, isFalse);
      verify(mockChannel.requestWatchNextPermission()).called(1);
    });
  });

  group('WatchNextService launch', () {
    test('launches program via channel intentUri', () async {
      watchNextService = WatchNextService(mockChannel, prefs, clock: clock);
      while (!watchNextService.initialized) {
        await Future.delayed(Duration.zero);
      }

      final program = WatchNextProgram(
        id: 1,
        packageName: 'com.netflix.mediaclient',
        title: 'Stranger Things',
        description: 'S1:E1',
        watchNextType: 1,
        lastEngagementTime: 1600000000,
        playbackPosition: 500,
        duration: 3000,
        intentUri: 'intent://netflix_uri',
        posterArtUri: 'content://netflix/poster/1',
      );

      when(mockChannel.launchWatchNextProgram(any)).thenAnswer((_) async => true);

      final success = await watchNextService.launch(program);

      expect(success, isTrue);
      verify(mockChannel.launchWatchNextProgram('intent://netflix_uri')).called(1);
    });

    test('fallback launches app packageName when intentUri empty', () async {
      watchNextService = WatchNextService(mockChannel, prefs, clock: clock);
      while (!watchNextService.initialized) {
        await Future.delayed(Duration.zero);
      }

      final program = WatchNextProgram(
        id: 1,
        packageName: 'com.netflix.mediaclient',
        title: 'Stranger Things',
        description: 'S1:E1',
        watchNextType: 1,
        lastEngagementTime: 1600000000,
        playbackPosition: 500,
        duration: 3000,
        intentUri: '',
        posterArtUri: '',
      );

      when(mockChannel.launchApp(any)).thenAnswer((_) async {});

      final success = await watchNextService.launch(program);

      expect(success, isTrue);
      verify(mockChannel.launchApp('com.netflix.mediaclient')).called(1);
    });

    test('fallback launches app packageName when intentUri returns false', () async {
      watchNextService = WatchNextService(mockChannel, prefs, clock: clock);
      while (!watchNextService.initialized) {
        await Future.delayed(Duration.zero);
      }

      final program = WatchNextProgram(
        id: 1,
        packageName: 'com.netflix.mediaclient',
        title: 'Stranger Things',
        description: 'S1:E1',
        watchNextType: 1,
        lastEngagementTime: 1600000000,
        playbackPosition: 500,
        duration: 3000,
        intentUri: 'intent://invalid_intent',
        posterArtUri: '',
      );

      when(mockChannel.launchWatchNextProgram(any)).thenAnswer((_) async => false);
      when(mockChannel.launchApp(any)).thenAnswer((_) async {});

      final success = await watchNextService.launch(program);

      expect(success, isTrue);
      verify(mockChannel.launchWatchNextProgram('intent://invalid_intent')).called(1);
      verify(mockChannel.launchApp('com.netflix.mediaclient')).called(1);
    });
  });

  group('WatchNextService deleteProgram', () {
    test('calls mockChannel.deleteWatchNextProgram and removes from programs list', () async {
      final fakePrograms = [
        {
          'id': 42,
          'packageName': 'com.netflix.mediaclient',
          'title': 'Stranger Things',
          'description': 'S1:E1 Chapter One',
          'watchNextType': 1,
          'lastEngagementTime': 1600000000,
          'playbackPosition': 500,
          'duration': 3000,
          'intentUri': 'intent://netflix_uri',
          'posterArtUri': ''
        }
      ];
      when(mockChannel.getWatchNextPrograms()).thenAnswer((_) async => fakePrograms);
      when(mockChannel.deleteWatchNextProgram(42)).thenAnswer((_) async => true);

      watchNextService = WatchNextService(mockChannel, prefs, clock: clock);
      while (!watchNextService.initialized) {
        await Future.delayed(Duration.zero);
      }

      expect(watchNextService.programs.length, 1);
      final program = watchNextService.programs.first;

      final result = await watchNextService.deleteProgram(program);

      expect(result, isTrue);
      expect(watchNextService.programs, isEmpty);
      verify(mockChannel.deleteWatchNextProgram(42)).called(1);
    });
  });

  group('WatchNextService posters', () {
    Map<String, Object> program(int id, String poster) => {
          'id': id,
          'packageName': 'com.example.tv',
          'title': 'Show $id',
          'description': '',
          'watchNextType': 1,
          'lastEngagementTime': 1600000000 - id,
          'playbackPosition': 0,
          'duration': 0,
          'intentUri': '',
          'posterArtUri': poster,
        };

    Future<WatchNextService> ready() async {
      final service = WatchNextService(mockChannel, prefs, clock: clock);
      while (!service.initialized) {
        await Future.delayed(Duration.zero);
      }
      await pumpEventQueue();
      return service;
    }

    test('fills in posters after the row appears and reuses them on the next refresh', () async {
      final art = Uint8List.fromList([1, 2, 3]);
      when(mockChannel.getWatchNextPrograms())
          .thenAnswer((_) async => [program(1, 'https://img.example/1.jpg'), program(2, '')]);
      when(mockChannel.getWatchNextPoster('https://img.example/1.jpg')).thenAnswer((_) async => art);

      final service = await ready();

      expect(service.programs[0].posterBytes, art);
      expect(service.programs[1].posterBytes, isNull);
      verifyNever(mockChannel.getWatchNextPoster(''));

      watchNextStreamController.add(true);
      await pumpEventQueue();

      expect(service.programs[0].posterBytes, art);
      verify(mockChannel.getWatchNextPoster('https://img.example/1.jpg')).called(1);
    });

    test('a poster that fails to load leaves the card without art', () async {
      when(mockChannel.getWatchNextPrograms())
          .thenAnswer((_) async => [program(1, 'https://img.example/broken.jpg')]);
      when(mockChannel.getWatchNextPoster(any)).thenAnswer((_) async => null);

      final service = await ready();

      expect(service.programs.single.posterBytes, isNull);
    });
  });

  group('WatchNextService ownership', () {
    Map<String, Object> entry(int id, String pkg, {int time = 1600000000000}) => {
          'id': id,
          'packageName': pkg,
          'title': 'Show $id',
          'description': '',
          'watchNextType': 1,
          'lastEngagementTime': time,
          'playbackPosition': 0,
          'duration': 0,
          'intentUri': '',
          'posterArtUri': '',
        };
    List<String> titles(WatchNextService service) => service.programs.map((p) => p.title).toList();

    Future<WatchNextService> ready() async {
      final service = WatchNextService(mockChannel, prefs, clock: clock);
      while (!service.initialized) {
        await Future.delayed(Duration.zero);
      }
      return service;
    }

    test('each profile sees the entries from apps it last used here', () async {
      when(mockChannel.getWatchNextPrograms())
          .thenAnswer((_) async => [entry(1, 'com.netflix.mediaclient'), entry(2, 'com.disney.disneyplus')]);
      when(mockChannel.getAppLastProfiles())
          .thenAnswer((_) async => {'com.netflix.mediaclient': 'user:0', 'com.disney.disneyplus': 'user:10'});

      final service = await ready();
      expect(titles(service), ['Show 1']);

      when(mockChannel.getActiveProfileKey()).thenAnswer((_) async => 'user:10');
      await service.refresh();
      expect(titles(service), ['Show 2']);
    });

    test('entries already there when tracking starts belong to no one until watched again', () async {
      SharedPreferences.setMockInitialValues({});
      prefs = await SharedPreferences.getInstance();
      when(mockChannel.getWatchNextPrograms()).thenAnswer((_) async => [entry(1, 'com.netflix.mediaclient')]);

      final service = await ready();
      expect(service.programs, isEmpty);

      when(mockChannel.getWatchNextPrograms())
          .thenAnswer((_) async => [entry(1, 'com.netflix.mediaclient', time: 1600000060000)]);
      await service.refresh();
      expect(titles(service), ['Show 1']);
    });

    test("an entry from the active profile's own agent is always shown", () async {
      when(mockChannel.getWatchNextPrograms())
          .thenAnswer((_) async => [entry(1, 'com.disney.disneyplus')..['profileOwned'] = true]);
      when(mockChannel.getAppLastProfiles()).thenAnswer((_) async => {'com.disney.disneyplus': 'user:10'});

      final service = await ready();
      expect(titles(service), ['Show 1']);
    });
  });

  group('WatchNextService hidden apps', () {
    test('setPackageHidden and unhideAll save the choice and re-read the list', () async {
      final settings = SettingsService(prefs);
      final service = WatchNextService(mockChannel, prefs, clock: clock);
      while (!service.initialized) {
        await Future.delayed(Duration.zero);
      }
      clearInteractions(mockChannel);

      await service.setPackageHidden(settings, 'com.netflix.mediaclient', true);
      expect(settings.hiddenWatchNextPackages, ['com.netflix.mediaclient']);

      await service.setPackageHidden(settings, 'com.netflix.mediaclient', false);
      expect(settings.hiddenWatchNextPackages, isEmpty);

      await service.setPackageHidden(settings, 'com.example.tv', true);
      await service.unhideAll(settings);
      expect(settings.hiddenWatchNextPackages, isEmpty);
      verify(mockChannel.getWatchNextPrograms()).called(4);
    });
  });

  group('Continue Watching row selection', () {
    final now = DateTime.utc(2026, 10, 7, 12);
    WatchNextProgram program(int id, String pkg, {required Duration ago, int type = 0, int position = 100, int duration = 1000}) =>
        WatchNextProgram(
          id: id,
          packageName: pkg,
          title: 'Title $id',
          description: '',
          watchNextType: type,
          lastEngagementTime: now.subtract(ago).millisecondsSinceEpoch,
          playbackPosition: position,
          duration: duration,
          intentUri: '',
          posterArtUri: '',
        );
    List<int> ids(Iterable<WatchNextProgram> programs) => programs.map((p) => p.id).toList();

    test('keeps at most three entries from one app, newest first', () {
      final programs = [
        for (var i = 1; i <= 5; i++) program(i, 'disney', ago: Duration(hours: i)),
        program(6, 'netflix', ago: const Duration(hours: 6)),
      ];
      expect(ids(WatchNextService.selectForRow(programs, now)), [1, 2, 3, 6]);
    });

    test('drops entries left part-way more than 60 days ago', () {
      final programs = [
        program(1, 'apple', ago: const Duration(days: 59)),
        program(2, 'apple', ago: const Duration(days: 61)),
      ];
      expect(ids(WatchNextService.selectForRow(programs, now)), [1]);
    });

    test('drops not-started entries (next episode, new, watchlist) after 30 days', () {
      final programs = [
        program(1, 'apple', ago: const Duration(days: 29), type: 1, position: 0),
        program(2, 'apple', ago: const Duration(days: 31), type: 1, position: 0),
        program(3, 'apple', ago: const Duration(days: 31), type: 3, position: 0),
        program(4, 'apple', ago: const Duration(days: 31)),
      ];
      expect(ids(WatchNextService.selectForRow(programs, now)), [1, 4]);
    });

    test('drops finished entries', () {
      final programs = [
        program(1, 'max', ago: const Duration(hours: 1), position: 960, duration: 1000),
        program(2, 'max', ago: const Duration(hours: 2), position: 500, duration: 1000),
        program(3, 'max', ago: const Duration(hours: 3), position: 960, duration: 0),
      ];
      expect(ids(WatchNextService.selectForRow(programs, now)), [2, 3]);
    });

    test('reads engagement times in seconds too', () {
      final seconds = WatchNextProgram(
        id: 1,
        packageName: 'netflix',
        title: '',
        description: '',
        watchNextType: 0,
        lastEngagementTime: now.subtract(const Duration(days: 61)).millisecondsSinceEpoch ~/ 1000,
        playbackPosition: 1,
        duration: 10,
        intentUri: '',
        posterArtUri: '',
      );
      expect(WatchNextService.selectForRow([seconds], now), isEmpty);
    });

    test('an old entry from one app frees its place for another of the same app', () {
      final programs = [
        program(1, 'disney', ago: const Duration(days: 1)),
        program(2, 'disney', ago: const Duration(days: 1), position: 999),
        program(3, 'disney', ago: const Duration(days: 2)),
        program(4, 'disney', ago: const Duration(days: 3)),
        program(5, 'disney', ago: const Duration(days: 4)),
      ];
      expect(ids(WatchNextService.selectForRow(programs, now)), [1, 3, 4]);
    });
  });
}
