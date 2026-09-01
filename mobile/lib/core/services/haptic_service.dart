import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// ระดับความรุนแรงของการสั่นสะเทือน (Haptic Feedback Intensity Levels)
enum HapticLevel {
  none,       // Level 0: ไม่สั่น
  light,      // Level 1: สั่นสั้นเบา 1 ครั้ง
  medium,     // Level 2: สั่นเบา 2 ครั้ง
  strong,     // Level 3: สั่นแรง 3 ครั้ง
  continuous, // Level 4: สั่นต่อเนื่องเป็นจังหวะเตือนอันตราย/หลงทาง
}

/// บริการควบคุมระบบสั่นสะเทือนรวมศูนย์สำหรับ TAM AI (Centralized Haptic Service)
class HapticService {
  static final HapticService _instance = HapticService._internal();
  factory HapticService() => _instance;
  HapticService._internal();

  DateTime _lastHapticTime = DateTime.now().subtract(const Duration(seconds: 5));
  static const Duration _defaultCooldown = Duration(milliseconds: 1600);

  // การตั้งค่าความแรงจากผู้ใช้: 'off', 'light', 'medium', 'strong'
  String _userIntensity = 'strong';
  bool _vibrationOnlyMode = false;
  bool _enabled = true;

  void configure({
    String? userIntensity,
    bool? vibrationOnlyMode,
    bool? enabled,
  }) {
    if (userIntensity != null) _userIntensity = userIntensity;
    if (vibrationOnlyMode != null) _vibrationOnlyMode = vibrationOnlyMode;
    if (enabled != null) _enabled = enabled;
  }

  String get userIntensity => _userIntensity;
  bool get vibrationOnlyMode => _vibrationOnlyMode;
  bool get enabled => _enabled;

  /// ตรวจสอบว่าอยู่ในช่วง Cooldown หรือไม่
  bool _isCoolingDown({bool bypass = false}) {
    if (bypass) return false;
    final now = DateTime.now();
    if (now.difference(_lastHapticTime) < _defaultCooldown) {
      return true;
    }
    _lastHapticTime = now;
    return false;
  }

  /// ปรับลดระดับความแรงตาม User Settings
  HapticLevel _scaleLevel(HapticLevel requestedLevel) {
    if (!_enabled || _userIntensity == 'off' || requestedLevel == HapticLevel.none) {
      return HapticLevel.none;
    }
    if (_userIntensity == 'light') {
      return HapticLevel.light;
    }
    if (_userIntensity == 'medium') {
      if (requestedLevel == HapticLevel.strong || requestedLevel == HapticLevel.continuous) {
        return HapticLevel.medium;
      }
      return requestedLevel;
    }
    return requestedLevel; // 'strong' allows full levels
  }

  /// สั่งสั่นตามระดับความแรง (Trigger by Level)
  Future<void> trigger(HapticLevel level, {bool bypassCooldown = false}) async {
    final effectiveLevel = _scaleLevel(level);
    if (effectiveLevel == HapticLevel.none) return;

    if (_isCoolingDown(bypass: bypassCooldown || level == HapticLevel.strong || level == HapticLevel.continuous)) {
      return;
    }

    try {
      switch (effectiveLevel) {
        case HapticLevel.none:
          break;

        case HapticLevel.light:
          // สั่นสั้นเบา 1 ครั้ง
          await HapticFeedback.selectionClick();
          await HapticFeedback.lightImpact();
          break;

        case HapticLevel.medium:
          // สั่นเบา 2 ครั้ง (แต่เพิ่มความชัด)
          await HapticFeedback.vibrate();
          await Future.delayed(const Duration(milliseconds: 200));
          await HapticFeedback.vibrate();
          break;

        case HapticLevel.strong:
          // สั่นแรง 3 ครั้ง (ใช้ vibrate รัวๆ ให้รู้สึกถึงข้อมือ)
          await HapticFeedback.vibrate();
          await Future.delayed(const Duration(milliseconds: 250));
          await HapticFeedback.vibrate();
          await Future.delayed(const Duration(milliseconds: 250));
          await HapticFeedback.vibrate();
          break;

        case HapticLevel.continuous:
          // สั่นต่อเนื่องเตือนหลงทาง / อันตรายวิกฤต (5 จังหวะ)
          for (int i = 0; i < 5; i++) {
            await HapticFeedback.vibrate();
            await Future.delayed(const Duration(milliseconds: 150));
          }
          break;
      }
    } catch (e) {
      if (kDebugMode) debugPrint('[HapticService] Error triggering haptic: $e');
    }
  }

  // ══════════════════════════════════════════════════════════════════════
  // สถานการณ์จำเพาะตามข้อกำหนด (Situational Haptic Triggers)
  // ══════════════════════════════════════════════════════════════════════

  /// 1. คำแนะนำเลี้ยว / ตรงไป (Turn / Straight Guidance)
  Future<void> turnGuidance({String direction = 'straight'}) async {
    final d = direction.toLowerCase().trim();
    if (d.contains('left')) {
      await turnLeft();
    } else if (d.contains('right')) {
      await turnRight();
    } else if (d.contains('u-turn') || d.contains('uturn')) {
      await turnUturn();
    } else {
      await trigger(HapticLevel.light);
    }
  }

  /// สั่นเตือนเลี้ยวซ้าย ➔ สั่นเตือน 1 ครั้งชัดเจน (Single Strong Pulse)
  Future<void> turnLeft() async {
    try {
      await HapticFeedback.vibrate();
    } catch (_) {}
  }

  /// สั่นเตือนเลี้ยวขวา ➔ สั่นเตือน 2 ครั้งหนักแน่น (Double Strong Pulse)
  Future<void> turnRight() async {
    try {
      await HapticFeedback.vibrate();
      await Future.delayed(const Duration(milliseconds: 180));
      await HapticFeedback.vibrate();
    } catch (_) {}
  }

  /// สั่นเตือนกลับตัว (U-Turn) ➔ สั่นเตือน 3 ครั้ง
  Future<void> turnUturn() async {
    try {
      for (int i = 0; i < 3; i++) {
        await HapticFeedback.vibrate();
        await Future.delayed(const Duration(milliseconds: 160));
      }
    } catch (_) {}
  }

  /// 2. เข้าสู่สถานะ Risk (Warning 15-25m) ➔ Medium
  Future<void> enterRisk() => trigger(HapticLevel.medium);

  /// 3. เข้าสู่สถานะ High Risk (< 15m) ➔ Strong (Bypass Cooldown)
  Future<void> enterHighRisk() => trigger(HapticLevel.strong, bypassCooldown: true);

  /// 4. พบสิ่งกีดขวางจาก AI Vision ➔ Strong Triple Vibrate
  Future<void> obstacleDetected() async {
    try {
      for (int i = 0; i < 5; i++) {
        await HapticFeedback.vibrate();
        await Future.delayed(const Duration(milliseconds: 120));
      }
    } catch (_) {}
  }

  /// 5. หลงทาง / ออกนอกเส้นทาง ➔ Continuous Alert (Bypass Cooldown)
  Future<void> offRoute() => trigger(HapticLevel.continuous, bypassCooldown: true);

  /// 6. ถึงจุดหมายปลายทาง ➔ สั่นยาว 2 จังหวะชัดเจน
  Future<void> destinationReached() async {
    try {
      await HapticFeedback.vibrate();
      await Future.delayed(const Duration(milliseconds: 250));
      await HapticFeedback.vibrate();
    } catch (_) {}
  }

  /// 7. เริ่มต้นการนำทาง ➔ Light
  Future<void> startNavigation() => trigger(HapticLevel.light);

  /// 8. เปิด/ปิดกล้องสแกน ➔ Light / Medium
  Future<void> cameraToggle({bool opening = true}) =>
      trigger(opening ? HapticLevel.medium : HapticLevel.light);

  /// 9. เรียกสัญญาณฉุกเฉิน SOS ➔ Strong ซ้ำ
  Future<void> triggerSos() async {
    await trigger(HapticLevel.strong, bypassCooldown: true);
  }
}
