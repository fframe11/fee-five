import 'package:flutter_test/flutter_test.dart';
import 'package:accessibility_assistant/core/services/risk_engine.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('RiskEngine & DynamicSafetyMargin Tests', () {
    test('evaluateGpsQuality returns accurate precision levels', () {
      expect(DynamicSafetyMargin.evaluateGpsQuality(3.0), GpsFixQuality.highPrecision);
      expect(DynamicSafetyMargin.evaluateGpsQuality(8.0), GpsFixQuality.mediumPrecision);
      expect(DynamicSafetyMargin.evaluateGpsQuality(20.0), GpsFixQuality.lowPrecision);
    });

    test('evaluateMovement returns accurate status', () {
      expect(DynamicSafetyMargin.evaluateMovement(0.1), MovementStatus.stationary);
      expect(DynamicSafetyMargin.evaluateMovement(1.1), MovementStatus.walking);
      expect(DynamicSafetyMargin.evaluateMovement(2.5), MovementStatus.fastWalking);
    });

    test('calculate safety margin produces bounded values', () {
      final margin = DynamicSafetyMargin.calculate(
        gpsAccuracy: 5.0,
        walkingSpeed: 1.2,
        severity: HazardSeverity.medium,
      );
      expect(margin, greaterThanOrEqualTo(5.0));
      expect(margin, lessThanOrEqualTo(35.0));
    });

    test('RiskEngine evaluate transitions across Safe, Warning, High Risk and Critical', () {
      final engine = RiskEngine();

      // Safe evaluation (far distance > 50m)
      final safeLevel = engine.evaluate(
        distanceMeters: 60.0,
        gpsAccuracy: 4.0,
        walkingSpeed: 1.2,
      );
      expect(safeLevel.cameraTrigger, CameraTriggerState.sleep);

      // Warning evaluation (approaching risk zone)
      final warningLevel = engine.evaluate(
        distanceMeters: 14.0,
        gpsAccuracy: 4.0,
        walkingSpeed: 1.2,
      );
      expect(warningLevel.cameraTrigger, anyOf(CameraTriggerState.prewarm, CameraTriggerState.activeScanning));

      // Close evaluation (< 4m)
      final criticalLevel = engine.evaluate(
        distanceMeters: 2.0,
        gpsAccuracy: 3.0,
        walkingSpeed: 1.2,
        severity: HazardSeverity.critical,
      );
      expect(criticalLevel.cameraTrigger, CameraTriggerState.activeScanning);

      engine.dispose();
    });
  });
}
