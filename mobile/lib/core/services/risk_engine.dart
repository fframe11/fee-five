import 'dart:async';
import 'package:flutter/foundation.dart';
import 'haptic_service.dart';

/// ระดับความเสี่ยง (Risk State)
enum RiskState {
  safe,
  warning,
  highRisk,
  critical,
}

/// คุณภาพสัญญาณพิกัด GPS / A-GPS / Wi-Fi / Cell Site
enum GpsFixQuality {
  highPrecision,   // สัญญาณดาวเทียมตรง (GNSS Lock) ความคลาดเคลื่อนต่ำ (<= 5 ม.)
  mediumPrecision, // สัญญาณผสม Wi-Fi / A-GPS ความคลาดเคลื่อนปานกลาง (5 - 12 ม.)
  lowPrecision,    // สัญญาณจากเสามือถือ (Cell Site) หรือถูกตึกบัง คลาดเคลื่อนสูง (> 12 ม.)
}

/// สถานะการเคลื่อนที่ของผู้พิการทางสายตา (จาก IMU / ความเร็ว)
enum MovementStatus {
  stationary,  // ยืนหยุดนิ่ง (ไม่ควรส่งเสียงเตือนพร่ำเพรื่อ)
  walking,     // เดินปกติ (~0.8 - 1.4 m/s)
  fastWalking, // เดินเร็ว หรือขึ้นพาหนะ (> 1.4 m/s)
}

/// ระดับความรุนแรงของจุดเสี่ยง (Hazard Severity)

/// ระดับความรุนแรงของจุดเสี่ยง (Hazard Severity)
enum HazardSeverity {
  low,      // ป้ายเตือนทั่วไป, ทางลาดเอียงเล็กน้อย
  medium,   // เสาไฟฟ้า, ทางเท้าแคบ, ป้ายจราจรขวาง
  high,     // ทางเท้าชำรุดทรุดตัว, ทางม้าลายข้ามถนนใหญ่
  critical, // หลุมท่อเปิดฝา, เขตก่อสร้างไม่มีราวกั้น, มอเตอร์ไซค์บนทางเท้า
}

/// สถานะการควบคุมกล้อง AI (Camera Trigger State)
enum CameraTriggerState {
  sleep,          // โซนปลอดภัย: ปิดกล้อง 100% ประหยัดแบตเตอรี่และลดความร้อน
  prewarm,        // โซนเตรียมพร้อม (Approach): ปลุกเซนเซอร์/กล้องล่วงหน้าในพื้นหลัง
  activeScanning, // โซนเสี่ยง (Risk Zone): เปิดกล้องเต็มกำลัง รัน YOLO11 สแกนอุปสรรคจริง
}

/// การตั้งค่าเซ็นเซอร์ตามระดับความเสี่ยง (Sensor Configuration)
class SensorConfig {
  final double distanceFilter;
  final int sensorRateHz;
  final String description;

  const SensorConfig({
    required this.distanceFilter,
    required this.sensorRateHz,
    required this.description,
  });

  /// ดึงการตั้งค่าตามสถานะปัจจุบัน
  factory SensorConfig.forState(RiskState state) {
    switch (state) {
      case RiskState.safe:
        return const SensorConfig(distanceFilter: 10.0, sensorRateHz: 1, description: 'Low power (GPS 1Hz)');
      case RiskState.warning:
        return const SensorConfig(distanceFilter: 5.0, sensorRateHz: 5, description: 'Medium (Pre-warm)');
      case RiskState.highRisk:
        return const SensorConfig(distanceFilter: 2.0, sensorRateHz: 10, description: 'High (YOLO Active)');
      case RiskState.critical:
        return const SensorConfig(distanceFilter: 1.0, sensorRateHz: 20, description: 'Maximum (Real-time Vision)');
    }
  }
}

/// การตั้งค่าการแจ้งเตือน (Alert Configuration)
class AlertConfig {
  final bool tts;
  final bool haptic;
  final bool notification;

  const AlertConfig({
    required this.tts,
    required this.haptic,
    required this.notification,
  });

  /// ดึงการตั้งค่าการแจ้งเตือนตามสถานะ
  factory AlertConfig.forState(RiskState state, {bool isStationary = false}) {
    switch (state) {
      case RiskState.safe:
        return const AlertConfig(tts: false, haptic: false, notification: false);
      case RiskState.warning:
        return AlertConfig(tts: !isStationary, haptic: true, notification: false);
      case RiskState.highRisk:
        return const AlertConfig(tts: true, haptic: true, notification: false);
      case RiskState.critical:
        return const AlertConfig(tts: true, haptic: true, notification: true);
    }
  }
}

/// ข้อมูลระดับความเสี่ยง (Risk Level) พร้อมข้อมูลการควบคุมกล้องและ GPS
class RiskLevel {
  final RiskState state;
  final double safetyMarginMeters;
  final GpsFixQuality gpsQuality;
  final CameraTriggerState cameraTrigger;
  final MovementStatus movementStatus;
  final SensorConfig sensorConfig;
  final AlertConfig alertConfig;

  const RiskLevel({
    required this.state,
    required this.safetyMarginMeters,
    required this.gpsQuality,
    required this.cameraTrigger,
    required this.movementStatus,
    required this.sensorConfig,
    required this.alertConfig,
  });
}

/// คำนวณระยะขอบเขตความปลอดภัยแบบ Dynamic (GPS Uncertainty & Factor Adaptive)
class DynamicSafetyMargin {
  /// จำแนกคุณภาพสัญญาณ GPS ตามความคลาดเคลื่อน (Accuracy in meters)
  static GpsFixQuality evaluateGpsQuality(double gpsAccuracy) {
    if (gpsAccuracy <= 5.0) {
      return GpsFixQuality.highPrecision;
    } else if (gpsAccuracy <= 12.0) {
      return GpsFixQuality.mediumPrecision;
    } else {
      return GpsFixQuality.lowPrecision;
    }
  }

  /// จำแนกสถานะการเคลื่อนที่จากความเร็วเดิน (m/s)
  static MovementStatus evaluateMovement(double walkingSpeed) {
    if (walkingSpeed < 0.3) {
      return MovementStatus.stationary;
    } else if (walkingSpeed <= 1.4) {
      return MovementStatus.walking;
    } else {
      return MovementStatus.fastWalking;
    }
  }

  /// คำนวณระยะปลอดภัยแบบปรับตามความแม่นยำ GPS แฟกเตอร์สัญญาณ และโหมดที่ผู้ใช้เลือก (5m / 10m / 15m)
  static double calculate({
    required double gpsAccuracy,
    double walkingSpeed = 1.2,
    HazardSeverity severity = HazardSeverity.medium,
    MovementStatus? movementStatus,
    double processingLatency = 0.35,
    double reactionTime = 1.5,
  }) {
    final movement = movementStatus ?? evaluateMovement(walkingSpeed);
    final quality = evaluateGpsQuality(gpsAccuracy);

    // 1. ระยะเป้าหมายพื้นฐานแบบอัตโนมัติ 100% ตามคุณภาพสัญญาณ (Zero-Configuration)
    // - เมื่อดาวเทียมแม่นยำสูง คลาดเคลื่อนต่ำ: คุมระยะปลอดภัยใกล้ตัวที่ 5.0 เมตร
    // - เมื่อดาวเทียมคลาดเคลื่อนปานกลาง: คุมระยะปลอดภัยมาตรฐานที่ 8.0 เมตร
    // - เมื่อสัญญาณแย่/เสามือถือ คลาดเคลื่อนสูง: คุมระยะปลอดภัยล่วงหน้าที่ 14.0 เมตร
    double baseTarget;
    switch (quality) {
      case GpsFixQuality.highPrecision:
        baseTarget = 5.0;
        break;
      case GpsFixQuality.mediumPrecision:
        baseTarget = 8.0;
        break;
      case GpsFixQuality.lowPrecision:
        baseTarget = 14.0;
        break;
    }

    // 2. ชดเชยตามความแม่นยำ GPS (Uncertainty Factor):
    // - สัญญาณดีเยี่ยม คลาดเคลื่อนต่ำ (GNSS Lock <= 5m): ชดเชยต่ำ บีบระยะให้ใกล้ 5-8 ม.
    // - สัญญาณแย่ คลาดเคลื่อนสูง (Cell Site > 12m): ชดเชยสูง ขยายระยะปลอดภัยล่วงหน้า 18-30+ ม.
    double gpsPenalty;
    switch (quality) {
      case GpsFixQuality.highPrecision:
        gpsPenalty = gpsAccuracy * 0.35;
        break;
      case GpsFixQuality.mediumPrecision:
        gpsPenalty = gpsAccuracy * 0.65;
        break;
      case GpsFixQuality.lowPrecision:
        gpsPenalty = gpsAccuracy * 1.25;
        break;
    }

    // 3. ระยะการเคลื่อนที่ระหว่างประมวลผล (Dynamic Latency + Reaction)
    final effectiveSpeed = movement == MovementStatus.stationary ? 0.0 : walkingSpeed;
    final double dynamicReaction = effectiveSpeed * (processingLatency + reactionTime);

    // 4. Severity Offset
    double severityOffset = 0.0;
    if (severity == HazardSeverity.critical) {
      severityOffset = 3.0;
    } else if (severity == HazardSeverity.high) {
      severityOffset = 1.5;
    }

    final double calculatedMargin = baseTarget + gpsPenalty + dynamicReaction + severityOffset;
    const double minMargin = 5.0;
    return calculatedMargin.clamp(minMargin, 35.0);
  }
}

/// เครื่องยนต์ประเมินความเสี่ยงและกระตุ้นกล้อง (Risk Engine & Camera Trigger)
class RiskEngine {
  RiskState _currentState = RiskState.safe;
  RiskState _pendingState = RiskState.safe;
  int _pendingCount = 0;
  DateTime _lastStateChange = DateTime.now().subtract(const Duration(seconds: 1));

  final Map<String, DateTime> _recentAlertTimestamps = {};
  static const Duration _audioCooldownDuration = Duration(seconds: 7);

  final StreamController<RiskLevel> _riskController = StreamController<RiskLevel>.broadcast();

  Stream<RiskLevel> get riskStream => _riskController.stream;
  RiskState get currentState => _currentState;

  RiskLevel evaluate({
    required double distanceMeters,
    required double gpsAccuracy,
    double walkingSpeed = 1.2,
    HazardSeverity severity = HazardSeverity.medium,
  }) {
    final movement = DynamicSafetyMargin.evaluateMovement(walkingSpeed);
    final gpsQuality = DynamicSafetyMargin.evaluateGpsQuality(gpsAccuracy);

    final double safetyMargin = DynamicSafetyMargin.calculate(
      gpsAccuracy: gpsAccuracy,
      walkingSpeed: walkingSpeed,
      severity: severity,
      movementStatus: movement,
    );

    RiskState evaluatedState;
    CameraTriggerState cameraTrigger;

    if (distanceMeters <= safetyMargin * 0.45) {
      evaluatedState = RiskState.critical;
      cameraTrigger = CameraTriggerState.activeScanning;
    } else if (distanceMeters <= safetyMargin) {
      evaluatedState = RiskState.highRisk;
      cameraTrigger = CameraTriggerState.activeScanning;
    } else if (distanceMeters <= safetyMargin * 1.8) {
      evaluatedState = RiskState.warning;
      cameraTrigger = CameraTriggerState.prewarm;
    } else {
      evaluatedState = RiskState.safe;
      cameraTrigger = CameraTriggerState.sleep;
    }

    if (evaluatedState == _pendingState) {
      _pendingCount++;
    } else {
      _pendingState = evaluatedState;
      _pendingCount = 1;
    }

    final now = DateTime.now();
    if (evaluatedState != _currentState) {
      if (now.difference(_lastStateChange).inMilliseconds >= 600) {
        _currentState = evaluatedState;
        _lastStateChange = now;
        _pendingCount = 0;

        // Trigger appropriate Haptic Feedback on Risk State Transition
        if (_currentState == RiskState.highRisk || _currentState == RiskState.critical) {
          HapticService().enterHighRisk();
        } else if (_currentState == RiskState.warning) {
          HapticService().enterRisk();
        }

        if (kDebugMode) {
          debugPrint('[TAM RiskEngine] State: $_currentState | SafetyMargin: ${safetyMargin.toStringAsFixed(1)}m | Camera: $cameraTrigger');
        }
      }
    }

    final riskLevel = RiskLevel(
      state: _currentState,
      safetyMarginMeters: safetyMargin,
      gpsQuality: gpsQuality,
      cameraTrigger: cameraTrigger,
      movementStatus: movement,
      sensorConfig: SensorConfig.forState(_currentState),
      alertConfig: AlertConfig.forState(_currentState, isStationary: movement == MovementStatus.stationary),
    );

    _riskController.add(riskLevel);
    return riskLevel;
  }

  bool shouldPlayAudioAlert(String hazardKey) {
    final now = DateTime.now();
    if (_recentAlertTimestamps.containsKey(hazardKey)) {
      final lastAlertTime = _recentAlertTimestamps[hazardKey]!;
      if (now.difference(lastAlertTime) < _audioCooldownDuration) {
        return false;
      }
    }
    _recentAlertTimestamps[hazardKey] = now;
    return true;
  }

  void clearAudioCooldown() {
    _recentAlertTimestamps.clear();
  }

  void dispose() {
    _riskController.close();
  }
}
