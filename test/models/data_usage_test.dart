import 'package:flauncher/models/data_usage.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('formatDataBytes', () {
    test('writes amounts as Android does, in powers of 1000', () {
      expect(formatDataBytes(0), '0 B');
      expect(formatDataBytes(-5), '0 B');
      expect(formatDataBytes(999), '999 B');
      expect(formatDataBytes(1000), '1 KB');
      expect(formatDataBytes(850000), '850 KB');
      expect(formatDataBytes(1234567890), '1.2 GB');
      expect(formatDataBytes(125000000000), '125 GB');
      expect(formatDataBytes(3 * 1000 * 1000 * 1000 * 1000 * 1000), '3000 TB');
    });

    test("uses the language's decimal mark", () {
      expect(formatDataBytes(1234567890, 'de'), '1,2 GB');
    });
  });

  group('DataUsageBreakdown', () {
    final breakdown = DataUsageBreakdown.fromMap({
      'total': 10000,
      'apps': [
        {'packageName': 'com.example.music', 'label': 'Music', 'kind': 'app', 'bytes': 1000},
        {'packageName': 'com.example.tv', 'label': 'TV', 'kind': 'app', 'bytes': 6000},
        {'packageName': null, 'label': null, 'kind': 'system', 'bytes': 500},
        {'packageName': null, 'label': null, 'kind': 'other', 'bytes': 700},
        {'packageName': null, 'kind': 'app', 'bytes': 300},
      ],
    });

    test('reads the platform answer, largest first', () {
      expect(breakdown.total, 10000);
      expect(breakdown.apps.map((a) => a.bytes), [6000, 1000, 700, 500, 300]);
      expect(breakdown.apps.first.label, 'TV');
      expect(breakdown.apps.first.kind, DataUsageKind.app);
      // An app without its package is counted with the rest
      expect(breakdown.apps.last.kind, DataUsageKind.other);
    });

    test('tiles are the largest apps and Android, never the rest', () {
      expect(
          breakdown.top(6).map((a) => a.packageName ?? a.kind.name), ['com.example.tv', 'com.example.music', 'system']);
      expect(breakdown.top(1).single.packageName, 'com.example.tv');
    });

    test('everything else is the whole less the tiles', () {
      expect(breakdown.whole, 10000);
      expect(breakdown.othersBytes(6), 10000 - 6000 - 1000 - 500);
      expect(breakdown.othersBytes(1), 4000);
    });

    test('the whole is never less than the apps add up to', () {
      final apps = DataUsageBreakdown.fromMap({
        'total': 100,
        'apps': [
          {'packageName': 'com.example.tv', 'label': 'TV', 'kind': 'app', 'bytes': 150},
        ],
      });
      expect(apps.whole, 150);
      expect(apps.othersBytes(6), 0);
    });

    test('an empty answer is nothing used', () {
      final empty = DataUsageBreakdown.fromMap({});
      expect(empty.total, 0);
      expect(empty.apps, isEmpty);
      expect(empty.othersBytes(6), 0);
    });
  });
}
