import 'package:flutter_test/flutter_test.dart';
import 'package:accessibility_assistant/core/services/haptic_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('HapticService Unit Tests', () {
    late HapticService hapticService;

    setUp(() {
      hapticService = HapticService();
      hapticService.configure(
        userIntensity: 'strong',
        vibrationOnlyMode: false,
        enabled: true,
      );
    });

    test('Default configuration is strong and enabled', () {
      expect(hapticService.userIntensity, 'strong');
      expect(hapticService.enabled, isTrue);
      expect(hapticService.vibrationOnlyMode, isFalse);
    });

    test('Configure user intensity modifies state correctly', () {
      hapticService.configure(userIntensity: 'light');
      expect(hapticService.userIntensity, 'light');

      hapticService.configure(userIntensity: 'off', enabled: false);
      expect(hapticService.userIntensity, 'off');
      expect(hapticService.enabled, isFalse);
    });

    test('Situational methods execute without throwing errors', () async {
      await expectLater(hapticService.turnGuidance(), completes);
      await expectLater(hapticService.enterRisk(), completes);
      await expectLater(hapticService.enterHighRisk(), completes);
      await expectLater(hapticService.obstacleDetected(), completes);
      await expectLater(hapticService.offRoute(), completes);
      await expectLater(hapticService.destinationReached(), completes);
      await expectLater(hapticService.startNavigation(), completes);
      await expectLater(hapticService.cameraToggle(opening: true), completes);
      await expectLater(hapticService.triggerSos(), completes);
    });
  });
}
