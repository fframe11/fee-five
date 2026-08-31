import 'dart:async';
import 'package:flutter/foundation.dart';

/// ระดับความเสี่ยง (Risk State)
enum RiskState {
  safe,
  warning,
  highRisk,
  critical,
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
        return const SensorConfig(distanceFilter: 10.0, sensorRateHz: 1, description: 'Low power');
      case RiskState.warning:
        return const SensorConfig(distanceFilter: 5.0, sensorRateHz: 5, description: 'Medium');
      case RiskState.highRisk:
        return const SensorConfig(distanceFilter: 2.0, sensorRateHz: 10, description: 'High');
      case RiskState.critical:
        return const SensorConfig(distanceFilter: 1.0, sensorRateHz: 25, description: 'Maximum');
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
  factory AlertConfig.forState(RiskState state) {
    switch (state) {
      case RiskState.safe:
        return const AlertConfig(tts: false, haptic: false, notification: false);
      case RiskState.warning:
        return const AlertConfig(tts: true, haptic: false, notification: false);
      case RiskState.highRisk:
        return const AlertConfig(tts: true, haptic: true, notification: false);
      case RiskState.critical:
        return const AlertConfig(tts: true, haptic: true, notification: true);
    }
  }
}

/// ข้อมูลระดับความเสี่ยง (Risk Level)
class RiskLevel {
  final RiskState state;
  final double safetyMarginMeters;
  final SensorConfig sensorConfig;
  final AlertConfig alertConfig;

  const RiskLevel({
    required this.state,
    required this.safetyMarginMeters,
    required this.sensorConfig,
    required this.alertConfig,
  });
}

/// คำนวณระยะขอบเขตความปลอดภัย (Dynamic Safety Margin)
class DynamicSafetyMargin {
  /// คำนวณระยะปลอดภัย
  ///
  /// Safety Distance = gpsUncertainty + latencyDistance + reactionDistance + safetyBuffer
  static double calculate({
    required double gpsAccuracy,
    double walkingSpeed = 1.2,
    double processingLatency = 0.5,
    double reactionTime = 2.0,
  }) {
    final double gpsUncertainty = gpsAccuracy;
    final double latencyDistance = walkingSpeed * processingLatency;
    final double reactionDistance = walkingSpeed * reactionTime;
    const double safetyBuffer = 3.0; // ค่าคงที่ระยะปลอดภัยขั้นต่ำ

    return gpsUncertainty + latencyDistance + reactionDistance + safetyBuffer;
  }
}

/// เครื่องยนต์ประเมินความเสี่ยง (Risk Engine)
class RiskEngine {
  RiskState _currentState = RiskState.safe;
  RiskState _pendingState = RiskState.safe;
  int _pendingCount = 0;
  DateTime _lastStateChange = DateTime.now().subtract(const Duration(seconds: 1));

  final StreamController<RiskLevel> _riskController = StreamController<RiskLevel>.broadcast();

  /// สตรีมแจ้งเตือนเมื่อมีการเปลี่ยนแปลงระดับความเสี่ยง
  Stream<RiskLevel> get riskStream => _riskController.stream;

  /// สถานะความเสี่ยงปัจจุบัน
  RiskState get currentState => _currentState;

  /// ประเมินความเสี่ยงปัจจุบัน
  void evaluate({
    required double distanceMeters,
    required double gpsAccuracy,
    double walkingSpeed = 1.2,
  }) {
    final double safetyMargin = DynamicSafetyMargin.calculate(
      gpsAccuracy: gpsAccuracy,
      walkingSpeed: walkingSpeed,
    );

    RiskState evaluatedState;
    if (distanceMeters < safetyMargin * 0.5) {
      evaluatedState = RiskState.critical;
    } else if (distanceMeters < safetyMargin) {
      evaluatedState = RiskState.highRisk;
    } else if (distanceMeters < safetyMargin * 2.0) {
      evaluatedState = RiskState.warning;
    } else {
      evaluatedState = RiskState.safe;
    }

    // Hysteresis: ป้องกันการสลับสถานะไปมา (Flickering) โดยต้องได้ค่าเดิม 2 ครั้งติดกัน
    if (evaluatedState == _pendingState) {
      _pendingCount++;
    } else {
      _pendingState = evaluatedState;
      _pendingCount = 1;
    }

    if (_pendingCount >= 2 && evaluatedState != _currentState) {
      final now = DateTime.now();
      // Cooldown: หน่วงเวลา 1 วินาทีก่อนจะเปลี่ยนสถานะได้อีกครั้ง
      if (now.difference(_lastStateChange).inMilliseconds >= 1000) {
        _currentState = evaluatedState;
        _lastStateChange = now;
        _pendingCount = 0; // รีเซ็ตตัวนับ
        
        if (kDebugMode) {
          debugPrint('[ความเสี่ยง] เปลี่ยนสถานะเป็น: ${_currentState.name} (Safety Margin: $safetyMargin m)');
        }

        _riskController.add(
          RiskLevel(
            state: _currentState,
            safetyMarginMeters: safetyMargin,
            sensorConfig: SensorConfig.forState(_currentState),
            alertConfig: AlertConfig.forState(_currentState),
          ),
        );
      }
    }
  }
  
  /// ยกเลิกและเคลียร์รีซอร์ส (Dispose)
  void dispose() {
    _riskController.close();
  }
}
