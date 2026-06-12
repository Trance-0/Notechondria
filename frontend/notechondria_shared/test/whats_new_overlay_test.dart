import 'package:flutter_test/flutter_test.dart';
import 'package:notechondria_shared/notechondria_shared.dart';

void main() {
  group('compareAppVersions', () {
    test('compares numerically per segment', () {
      expect(compareAppVersions('0.1.9', '0.1.10'), lessThan(0));
      expect(compareAppVersions('0.1.127', '0.1.127'), 0);
      expect(compareAppVersions('0.2.0', '0.1.127'), greaterThan(0));
    });

    test('treats missing or malformed segments as zero', () {
      expect(compareAppVersions('0.1', '0.1.0'), 0);
      expect(compareAppVersions('0.1.x', '0.1.0'), 0);
    });
  });

  group('selectMissedUpdates', () {
    const registry = [
      FeatureUpdate(version: '0.1.120', title: 'a', description: 'a'),
      FeatureUpdate(version: '0.1.125', title: 'b', description: 'b'),
      FeatureUpdate(version: '0.1.127', title: 'c', description: 'c'),
    ];

    test('returns entries newer than last seen, capped at current', () {
      final missed = selectMissedUpdates(
        registry: registry,
        lastSeenVersion: '0.1.123',
        currentVersion: '0.1.127',
      );
      expect(missed.map((u) => u.version), ['0.1.125', '0.1.127']);
    });

    test('empty last seen yields nothing (fresh install stamps silently)', () {
      final missed = selectMissedUpdates(
        registry: registry,
        lastSeenVersion: '',
        currentVersion: '0.1.127',
      );
      expect(missed, isEmpty);
    });

    test('up-to-date user gets nothing', () {
      final missed = selectMissedUpdates(
        registry: registry,
        lastSeenVersion: '0.1.127',
        currentVersion: '0.1.127',
      );
      expect(missed, isEmpty);
    });

    test('entries newer than the running build are excluded', () {
      final missed = selectMissedUpdates(
        registry: registry,
        lastSeenVersion: '0.1.119',
        currentVersion: '0.1.125',
      );
      expect(missed.map((u) => u.version), ['0.1.120', '0.1.125']);
    });
  });
}
