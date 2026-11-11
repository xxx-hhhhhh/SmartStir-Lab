import 'package:flutter_test/flutter_test.dart';
import 'package:smartstir_lab/core/github_update_service.dart';

void main() {
  group('Version compare', () {
    test('newer stable version', () {
      expect(SmartStirUpdateService.isNewerVersion('v1.2.1', '1.2.0'), isTrue);
      expect(SmartStirUpdateService.isNewerVersion('v2.0.0', '1.9.9'), isTrue);
      expect(SmartStirUpdateService.isNewerVersion('1.2.0', '1.2.0'), isFalse);
      expect(SmartStirUpdateService.isNewerVersion('v1.1.0', '1.2.0'), isFalse);
      expect(SmartStirUpdateService.isNewerVersion('v1.2.0-rc.1', '1.1.0'), isFalse);
      expect(SmartStirUpdateService.isNewerVersion('junk', '1.1.0'), isFalse);
    });
  });
  group('Trusted update target', () {
    test('only own GitHub release APK', () {
      expect(SmartStirUpdateService.isTrustedAssetUrl(
        'https://github.com/xxx-hhhhhh/SmartStir-Lab/releases/download/v1.2.1/app-release.apk',
        'xxx-hhhhhh', 'SmartStir-Lab'), isTrue);
      expect(SmartStirUpdateService.isTrustedAssetUrl(
        'https://example.com/app-release.apk',
        'xxx-hhhhhh', 'SmartStir-Lab'), isFalse);
      expect(SmartStirUpdateService.isTrustedAssetUrl(
        'http://github.com/xxx-hhhhhh/SmartStir-Lab/releases/download/v1.2.1/app-release.apk',
        'xxx-hhhhhh', 'SmartStir-Lab'), isFalse);
      expect(SmartStirUpdateService.isTrustedAssetUrl(
        'https://github.com/attacker/SmartStir-Lab/releases/download/v1.2.1/app-release.apk',
        'xxx-hhhhhh', 'SmartStir-Lab'), isFalse);
    });
  });
}
