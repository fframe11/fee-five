import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// ผลลัพธ์จาก Vision — ทุกผลลัพธ์มี Confidence Score
class VisionResult {
  /// ประเภทสิ่งกีดขวาง (เช่น "เสาไฟฟ้า", "หลุม", "บันได")
  final String obstacleType;

  /// ป้ายกำกับภาษาอังกฤษ
  final String labelEn;

  /// ค่าความมั่นใจ 0.0 – 1.0
  final double confidence;

  /// ระยะทางโดยประมาณ (เมตร)
  final double estimatedDistance;

  /// Bounding box (normalized 0.0–1.0)
  final double x, y, w, h;

  /// เวลาที่ตรวจจับ
  final DateTime timestamp;

  const VisionResult({
    required this.obstacleType,
    required this.labelEn,
    required this.confidence,
    required this.estimatedDistance,
    required this.x,
    required this.y,
    required this.w,
    required this.h,
    required this.timestamp,
  });

  /// ค่า confidence เป็น % (เช่น "92%")
  String get confidencePercent => '${(confidence * 100).toStringAsFixed(0)}%';
}

/// สาเหตุที่ trigger กล้อง
enum VisionTriggerReason {
  /// Risk Engine ตรวจพบความเสี่ยงสูง
  riskEscalation,

  /// ผู้ใช้สั่งเสียง (เช่น "ตรวจสอบด้านหน้า")
  voiceCommand,

  /// ผู้ใช้กดปุ่มบนหน้าจอ
  manualButton,
}

/// สถานะของ Vision System
enum VisionState {
  /// กล้องปิด ไม่ทำงาน
  idle,

  /// กำลังเปิดกล้อง
  activating,

  /// กำลังประมวลผลภาพ
  processing,

  /// ได้ผลลัพธ์แล้ว กำลังปิดกล้อง
  completed,

  /// เกิดข้อผิดพลาด
  error,
}

/// Event-Driven Camera Controller
///
/// กล้องไม่ทำงานตลอดเวลา — เปิดเฉพาะเมื่อ:
/// 1. Risk Engine ตรวจพบ highRisk หรือ critical (auto-trigger)
/// 2. ผู้ใช้สั่งเสียง "ตรวจสอบด้านหน้า" (voice-trigger)
/// 3. ผู้ใช้กดปุ่ม (manual-trigger)
///
/// แต่ละรอบ: Camera ON → On-device AI → Result → Camera OFF (< 3 วินาที)
class VisionTrigger {
  /// สถานะปัจจุบัน
  VisionState _state = VisionState.idle;
  VisionState get state => _state;

  /// Stream สำหรับฟัง state changes
  final _stateController = StreamController<VisionState>.broadcast();
  Stream<VisionState> get stateStream => _stateController.stream;

  /// Stream สำหรับฟังผลลัพธ์ Vision
  final _resultController = StreamController<List<VisionResult>>.broadcast();
  Stream<List<VisionResult>> get resultStream => _resultController.stream;

  /// ผลลัพธ์ล่าสุด
  List<VisionResult> _lastResults = [];
  List<VisionResult> get lastResults => _lastResults;

  /// Cooldown — ป้องกันการ trigger ถี่เกินไป
  DateTime? _lastTriggerTime;
  static const Duration _cooldown = Duration(seconds: 5);

  /// จำนวน trigger ทั้งหมด (สำหรับ monitoring)
  int _triggerCount = 0;
  int get triggerCount => _triggerCount;

  /// Callback สำหรับเปิดกล้องจริง (set โดย VisionAssistScreen)
  Future<List<VisionResult>> Function()? onCaptureAndInfer;

  /// Trigger กล้อง — เรียกจาก Risk Engine หรือ Voice Command
  ///
  /// Returns ผลลัพธ์ vision หรือ empty list ถ้า cooldown/error
  Future<List<VisionResult>> trigger(VisionTriggerReason reason) async {
    // Cooldown check
    if (_lastTriggerTime != null) {
      final elapsed = DateTime.now().difference(_lastTriggerTime!);
      if (elapsed < _cooldown) {
        debugPrint('[Vision] Cooldown active, ${(_cooldown - elapsed).inSeconds}s remaining');
        return [];
      }
    }

    // ถ้ากำลัง processing อยู่ ไม่ trigger ซ้ำ
    if (_state == VisionState.activating || _state == VisionState.processing) {
      debugPrint('[Vision] Already active, skipping trigger');
      return [];
    }

    debugPrint('[Vision] 🔍 Triggered: ${reason.name}');
    _triggerCount++;
    _lastTriggerTime = DateTime.now();

    // Haptic feedback เมื่อเริ่ม capture
    HapticFeedback.mediumImpact();

    _setState(VisionState.activating);

    try {
      // เปิดกล้อง + On-device AI inference
      _setState(VisionState.processing);

      List<VisionResult> results;
      if (onCaptureAndInfer != null) {
        // ใช้ callback จาก VisionAssistScreen (กล้องจริง + TFLite)
        results = await onCaptureAndInfer!();
      } else {
        // Fallback: mock result สำหรับ prototype
        results = await _mockInference();
      }

      _lastResults = results;
      _resultController.add(results);
      _setState(VisionState.completed);

      debugPrint('[Vision] ✅ Got ${results.length} detections');
      for (final r in results) {
        debugPrint('[Vision]   - ${r.obstacleType}: ${r.confidencePercent} @ ${r.estimatedDistance.toStringAsFixed(1)}m');
      }

      // Auto-reset สถานะกลับ idle หลัง 2 วินาที
      Future.delayed(const Duration(seconds: 2), () {
        if (_state == VisionState.completed) {
          _setState(VisionState.idle);
        }
      });

      return results;
    } catch (e) {
      debugPrint('[Vision] ❌ Error: $e');
      _setState(VisionState.error);

      // Auto-reset กลับ idle หลัง 3 วินาที
      Future.delayed(const Duration(seconds: 3), () {
        if (_state == VisionState.error) {
          _setState(VisionState.idle);
        }
      });

      return [];
    }
  }

  /// Fallback inference when no active camera callback is registered
  Future<List<VisionResult>> _mockInference() async {
    return [];
  }

  /// เช็คว่าควร auto-trigger จาก Risk State หรือไม่
  bool shouldAutoTrigger(String riskState) {
    return riskState == 'highRisk' || riskState == 'critical';
  }

  void _setState(VisionState newState) {
    _state = newState;
    _stateController.add(newState);
  }

  /// ยกเลิก trigger ที่กำลังทำงาน
  void cancel() {
    if (_state == VisionState.processing || _state == VisionState.activating) {
      _setState(VisionState.idle);
    }
  }

  /// ล้าง resources
  void dispose() {
    _stateController.close();
    _resultController.close();
  }
}
