import 'package:flutter_test/flutter_test.dart';
import 'package:notechondria_shared/notechondria_shared.dart';

void main() {
  group('compareSemver', () {
    test('orders dotted-numeric versions', () {
      expect(compareSemver('0.1.151', '0.1.152') < 0, isTrue);
      expect(compareSemver('0.1.152', '0.1.151') > 0, isTrue);
      expect(compareSemver('0.1.151', '0.1.151'), 0);
      expect(compareSemver('0.2.0', '0.1.999') > 0, isTrue);
      // shorter == implicit zeros
      expect(compareSemver('0.1', '0.1.0'), 0);
      expect(compareSemver('0.1.1', '0.1') > 0, isTrue);
    });

    test('non-numeric / empty versions are incomparable (0)', () {
      expect(compareSemver('unknown', '0.1.151'), 0);
      expect(compareSemver('git-abc', '0.1.151'), 0);
      expect(compareSemver('', '0.1.151'), 0);
      expect(compareSemver('0.1.151', ''), 0);
    });

    test('ignores pre-release / build suffixes', () {
      expect(compareSemver('0.1.151-rc1', '0.1.151'), 0);
      expect(compareSemver('0.1.151+5', '0.1.152') < 0, isTrue);
    });
  });

  group('computeVersionStatus', () {
    AppVersionStatus s(String fe, String be, [String? floor]) =>
        computeVersionStatus(
          frontendVersion: fe,
          backendVersion: be,
          minFrontendVersion: floor,
        );

    test('equal -> upToDate', () {
      expect(s('0.1.151', '0.1.151'), AppVersionStatus.upToDate);
    });

    test('backend newer -> updateAvailable', () {
      expect(s('0.1.151', '0.1.152'), AppVersionStatus.updateAvailable);
    });

    test('backend older -> deploying', () {
      expect(s('0.1.152', '0.1.151'), AppVersionStatus.deploying);
    });

    test('below floor -> unsupported (wins over version compare)', () {
      expect(s('0.1.139', '0.1.139', '0.1.140'),
          AppVersionStatus.unsupported);
    });

    test('at/above floor -> normal compare', () {
      expect(s('0.1.140', '0.1.140', '0.1.140'), AppVersionStatus.upToDate);
      expect(s('0.1.141', '0.1.142', '0.1.140'),
          AppVersionStatus.updateAvailable);
    });

    test('empty floor is ignored', () {
      expect(s('0.1.151', '0.1.151', ''), AppVersionStatus.upToDate);
      expect(s('0.1.151', '0.1.151', null), AppVersionStatus.upToDate);
    });

    test('incomparable versions -> upToDate (no noisy banner)', () {
      expect(s('0.1.151', 'unknown'), AppVersionStatus.upToDate);
    });
  });
}
