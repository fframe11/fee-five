import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';

/// สถานะการจัดการแบตเตอรี่ของแอป
enum BatteryOptimizationStatus {
  unrestricted,
  normal,
  restricted,
  unknown,
}

/// สถานะอุณหภูมิของอุปกรณ์
enum ThermalState {
  normal,
  warm,
  hot,
  critical,
}

/// Singleton class สำหรับจัดการและตรวจสอบสถานะแบตเตอรี่และอุณหภูมิ
class BatteryManager {
  static final BatteryManager _instance = BatteryManager._internal();

  factory BatteryManager() {
    return _instance;
  }

  BatteryManager._internal();

  ThermalState _currentThermalState = ThermalState.normal;
  Timer? _thermalTimer;
  final StreamController<ThermalState> _thermalStreamController =
      StreamController<ThermalState>.broadcast();

  /// Stream สำหรับติดตามสถานะอุณหภูมิ
  Stream<ThermalState> get thermalStateStream =>
      _thermalStreamController.stream;

  /// ตรวจสอบการจัดการแบตเตอรี่ของ OS 
  /// (หมายเหตุ: unrestricted ไม่ได้รับประกันว่าแอปจะไม่ถูกระบบปิดการทำงานโดยสมบูรณ์)
  Future<BatteryOptimizationStatus> checkBatteryOptimization() async {
    try {
      final bool isIgnoring =
          await FlutterForegroundTask.isIgnoringBatteryOptimizations;
      if (isIgnoring) {
        debugPrint('[แบตเตอรี่] สถานะ: ไม่ถูกจำกัด (Unrestricted)');
        return BatteryOptimizationStatus.unrestricted;
      } else {
        debugPrint('[แบตเตอรี่] สถานะ: ปกติหรือถูกจำกัด (Normal/Restricted)');
        return BatteryOptimizationStatus.normal;
      }
    } catch (e) {
      debugPrint('[แบตเตอรี่] เกิดข้อผิดพลาดในการตรวจสอบ: $e');
      return BatteryOptimizationStatus.unknown;
    }
  }

  /// ขอให้ผู้ใช้ปิดการประหยัดแบตเตอรี่สำหรับแอปนี้
  Future<bool> requestDisableBatteryOptimization() async {
    try {
      debugPrint('[แบตเตอรี่] กำลังขอปิดการประหยัดแบตเตอรี่...');
      return await FlutterForegroundTask.requestIgnoreBatteryOptimization();
    } catch (e) {
      debugPrint('[แบตเตอรี่] เกิดข้อผิดพลาดในการขอปิด: $e');
      return false;
    }
  }

  /// ควรแสดงคำเตือนหรือไม่
  bool shouldShowWarning(BatteryOptimizationStatus status) {
    return status == BatteryOptimizationStatus.restricted ||
        status == BatteryOptimizationStatus.normal;
  }

  /// ข้อความเตือนภาษาไทย
  String getWarningMessage(BatteryOptimizationStatus status) {
    switch (status) {
      case BatteryOptimizationStatus.restricted:
        return 'การนำทางพื้นหลังอาจถูกจำกัด กรุณาอนุญาตในตั้งค่า > แบตเตอรี่ > ไม่จำกัด';
      case BatteryOptimizationStatus.normal:
        return 'แนะนำให้ปิดการประหยัดแบตเตอรี่เพื่อให้การนำทางทำงานต่อเนื่อง';
      default:
        return '';
    }
  }

  /// เริ่มติดตามสถานะอุณหภูมิของอุปกรณ์ (placeholder)
  void monitorThermal() {
    debugPrint('[แบตเตอรี่] เริ่มติดตามอุณหภูมิของอุปกรณ์...');
    _thermalTimer?.cancel();
    _thermalTimer = Timer.periodic(const Duration(minutes: 5), (timer) {
      // Placeholder: ในสถานการณ์จริงสามารถใช้ plugin เพื่อดึงข้อมูลอุณหภูมิจริงได้
      _updateThermalState(ThermalState.normal);
    });
  }

  void _updateThermalState(ThermalState newState) {
    if (_currentThermalState != newState) {
      _currentThermalState = newState;
      _thermalStreamController.add(newState);
      debugPrint('[แบตเตอรี่] อุณหภูมิเปลี่ยนแปลง: ${newState.name}');
    }
  }

  /// ดึงสถานะอุณหภูมิปัจจุบัน
  ThermalState getThermalState() {
    return _currentThermalState;
  }

  /// ควรลดประสิทธิภาพการทำงานเพื่อลดความร้อนหรือไม่
  bool shouldReducePerformance() {
    return _currentThermalState == ThermalState.hot ||
        _currentThermalState == ThermalState.critical;
  }

  /// ปิดการทำงานของ Stream และ Timer
  void dispose() {
    _thermalTimer?.cancel();
    _thermalStreamController.close();
  }
}
