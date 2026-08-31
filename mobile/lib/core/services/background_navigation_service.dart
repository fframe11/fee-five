import 'dart:async';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flutter_tts/flutter_tts.dart';

import 'map_matcher.dart';
import 'risk_engine.dart';

// ============================================================================
// ARCHITECTURE (Committee Feedback v2):
//
//   Location FGS / Core Location    ← Process keeper (NOT Notification)
//               ↓
//       Navigation Engine            ← Core orchestrator
//               ↓
//   Notification + Voice + Haptic    ← Output channels only
//
// Notification เป็นช่องทางแสดงสถานะ ไม่ใช่ตัวรักษา Process
// Camera ไม่ทำงาน Background — แยกเป็น Optional Event-Driven Layer
// ============================================================================

/// Top-level callback for background execution isolate
@pragma('vm:entry-point')
void startCallback() {
  FlutterForegroundTask.setTaskHandler(NavigationTaskHandler());
}

// ============================================================================
// Navigation Task Handler — runs inside background isolate
// ============================================================================

/// Background isolate handler — receives GPS + runs Navigation Engine
class NavigationTaskHandler extends TaskHandler {
  StreamSubscription<Position>? _positionSubscription;
  FlutterTts? _tts;

  // Navigation state
  String _destinationName = 'จุดหมายปลายทาง';
  double? _destLat;
  double? _destLng;
  double _totalDistanceMeters = 0.0;
  RiskState _currentRiskState = RiskState.safe;
  int _consecutiveRiskCount = 0;
  RiskState _pendingRiskState = RiskState.safe;
  DateTime? _lastRiskChangeTime;
  DateTime? _lastAlertTime;

  // Map Matching
  final MapMatcher _mapMatcher = MapMatcher();

  // Recovery session ID
  String _sessionId = '';

  // Sensor config per risk state
  static const Map<RiskState, double> _distanceFilters = {
    RiskState.safe: 10.0,
    RiskState.warning: 5.0,
    RiskState.highRisk: 2.0,
    RiskState.critical: 1.0,
  };

  // Dynamic barriers along user's active route
  final List<Map<String, dynamic>> _routeBarriers = [];

  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {
    debugPrint('[NavEngine] ===== Service Started at: $timestamp =====');

    // Initialize TTS
    _tts = FlutterTts();
    await _tts?.setLanguage('th-TH');
    await _tts?.setSpeechRate(0.5);
    await _tts?.setVolume(1.0);

    // Retrieve destination info saved from main isolate
    final savedDest = await FlutterForegroundTask.getData<String>(key: 'dest_name');
    if (savedDest != null && savedDest.isNotEmpty) {
      _destinationName = savedDest;
    }
    _destLat = await FlutterForegroundTask.getData<double>(key: 'dest_lat');
    _destLng = await FlutterForegroundTask.getData<double>(key: 'dest_lng');
    final savedDist = await FlutterForegroundTask.getData<double>(key: 'total_dist');
    if (savedDist != null && savedDist > 0) {
      _totalDistanceMeters = savedDist;
    }

    // Generate session ID for recovery
    _sessionId = 'nav_${timestamp.millisecondsSinceEpoch}';
    FlutterForegroundTask.saveData(key: 'nav_session_id', value: _sessionId);

    // ─── START GPS STREAM (This is the Process Keeper) ───
    _startLocationStream(LocationAccuracy.high, _distanceFilters[RiskState.safe]!);

    // Announce start
    await _tts?.speak('เริ่มต้นการนำทางสู่ $_destinationName ระบบจะแจ้งเตือนระยะทางและสิ่งกีดขวาง');
  }

  /// Start or restart GPS stream with given accuracy and distance filter
  void _startLocationStream(LocationAccuracy accuracy, double distanceFilter) {
    _positionSubscription?.cancel();

    final settings = LocationSettings(
      accuracy: accuracy,
      distanceFilter: distanceFilter.toInt(),
    );

    _positionSubscription = Geolocator.getPositionStream(
      locationSettings: settings,
    ).listen(
      (Position position) {
        _onLocationUpdate(position);
      },
      onError: (error) {
        debugPrint('[NavEngine] ❌ Location error: $error');
        FlutterForegroundTask.updateService(
          notificationTitle: '⚠️ TAM - ข้อผิดพลาด GPS',
          notificationText: 'ไม่สามารถรับสัญญาณ GPS กรุณาตรวจสอบการตั้งค่า',
        );
      },
    );

    debugPrint('[NavEngine] GPS stream started: accuracy=$accuracy, distanceFilter=${distanceFilter}m');
  }

  /// ─── NAVIGATION ENGINE CORE ───
  /// เรียกทุกครั้งที่ได้ GPS update ใหม่
  void _onLocationUpdate(Position pos) async {
    final gpsAccuracy = pos.accuracy;

    // Refresh destination info if not yet loaded
    if (_destLat == null || _destLng == null) {
      _destLat = await FlutterForegroundTask.getData<double>(key: 'dest_lat');
      _destLng = await FlutterForegroundTask.getData<double>(key: 'dest_lng');
      final savedDest = await FlutterForegroundTask.getData<String>(key: 'dest_name');
      if (savedDest != null && savedDest.isNotEmpty) _destinationName = savedDest;
    }

    // 1. Calculate Real-time dynamic distance to destination (meters)
    double remaining = 0.0;
    double progress = 0.0;

    if (_destLat != null && _destLng != null && _destLat != 0.0) {
      remaining = _haversineDistance(pos.latitude, pos.longitude, _destLat!, _destLng!);
      if (_totalDistanceMeters <= 0.0) {
        _totalDistanceMeters = remaining;
      }
      progress = (1.0 - (remaining / _totalDistanceMeters)).clamp(0.0, 1.0);
    } else {
      final matched = _mapMatcher.match(pos.latitude, pos.longitude);
      progress = matched?.progressAlongRoute ?? 0.0;
      remaining = matched?.remainingDistanceMeters ?? 0.0;
    }

    final isOffRoute = _mapMatcher.match(pos.latitude, pos.longitude)?.isOffRoute ?? false;

    // 2. Calculate distance to nearest obstacle
    double minDistance = double.infinity;
    Map<String, dynamic>? closestBarrier;

    for (var barrier in _routeBarriers) {
      final d = _haversineDistance(
        pos.latitude, pos.longitude,
        barrier['lat'] as double, barrier['lng'] as double,
      );
      if (d < minDistance) {
        minDistance = d;
        closestBarrier = barrier;
      }
    }

    // 3. Dynamic Safety Margin calculation
    final safetyDist = DynamicSafetyMargin.calculate(gpsAccuracy: gpsAccuracy);

    // 4. Risk State evaluation (with hysteresis)
    final newRiskState = _evaluateRisk(minDistance, safetyDist);
    final riskChanged = newRiskState != _currentRiskState;

    if (riskChanged) {
      final oldState = _currentRiskState;
      _currentRiskState = newRiskState;
      debugPrint('[NavEngine] Risk: ${oldState.name} → ${newRiskState.name} '
          '(dist=${minDistance.toStringAsFixed(1)}m, margin=${safetyDist.toStringAsFixed(1)}m)');

      // Adapt GPS sensitivity based on risk state
      final newFilter = _distanceFilters[newRiskState]!;
      _startLocationStream(
        newRiskState == RiskState.critical ? LocationAccuracy.bestForNavigation : LocationAccuracy.high,
        newFilter,
      );
    }

    // 5. Output — Notification + Voice + Haptic
    _processOutput(
      position: pos,
      gpsAccuracy: gpsAccuracy,
      minDistance: minDistance,
      closestBarrier: closestBarrier,
      safetyDist: safetyDist,
      progress: progress,
      remaining: remaining,
      isOffRoute: isOffRoute,
      riskChanged: riskChanged,
    );

    // 6. Auto-save state for Recovery Manager
    // (Runs in isolate; actual SharedPreferences save happens via main isolate communication)
    FlutterForegroundTask.saveData(
      key: 'nav_last_lat',
      value: pos.latitude,
    );
    FlutterForegroundTask.saveData(
      key: 'nav_last_lng',
      value: pos.longitude,
    );
    FlutterForegroundTask.saveData(
      key: 'nav_risk_state',
      value: _currentRiskState.name,
    );
    FlutterForegroundTask.saveData(
      key: 'nav_progress',
      value: progress,
    );
  }

  /// Evaluate risk with hysteresis (2 consecutive same state before changing)
  RiskState _evaluateRisk(double distance, double safetyMargin) {
    RiskState evaluated;

    if (distance < safetyMargin * 0.5) {
      evaluated = RiskState.critical;
    } else if (distance < safetyMargin) {
      evaluated = RiskState.highRisk;
    } else if (distance < safetyMargin * 2.0) {
      evaluated = RiskState.warning;
    } else {
      evaluated = RiskState.safe;
    }

    // Hysteresis: need 2 consecutive evaluations at same level
    if (evaluated == _pendingRiskState) {
      _consecutiveRiskCount++;
    } else {
      _pendingRiskState = evaluated;
      _consecutiveRiskCount = 1;
    }

    // Cooldown: minimum 1 second between state changes
    final now = DateTime.now();
    final cooldownOk = _lastRiskChangeTime == null ||
        now.difference(_lastRiskChangeTime!).inMilliseconds >= 1000;

    if (_consecutiveRiskCount >= 2 && cooldownOk && evaluated != _currentRiskState) {
      _lastRiskChangeTime = now;
      return evaluated;
    }

    return _currentRiskState; // Keep current state
  }

  /// Process output — update notification, speak warning, trigger haptic
  void _processOutput({
    required Position position,
    required double gpsAccuracy,
    required double minDistance,
    required Map<String, dynamic>? closestBarrier,
    required double safetyDist,
    required double progress,
    required double remaining,
    required bool isOffRoute,
    required bool riskChanged,
  }) {
    final now = DateTime.now();
    final canSpeak = _lastAlertTime == null || now.difference(_lastAlertTime!).inSeconds > 5;

    // Build notification text with GPS confidence
    final accuracyStr = '±${gpsAccuracy.toStringAsFixed(0)}m';
    final progressStr = '${(progress * 100).toStringAsFixed(0)}%';
    final remainingStr = remaining > 1000
        ? '${(remaining / 1000).toStringAsFixed(1)} กม.'
        : '${remaining.toStringAsFixed(0)} ม.';

    // Off-route warning
    if (isOffRoute && canSpeak) {
      _lastAlertTime = now;
      _tts?.speak('คุณอาจออกนอกเส้นทาง กรุณากลับสู่เส้นทางเดิม');
      FlutterForegroundTask.updateService(
        notificationTitle: '⚠️ TAM - ออกนอกเส้นทาง',
        notificationText: 'กรุณากลับสู่เส้นทาง | GPS $accuracyStr',
      );
      return;
    }

    switch (_currentRiskState) {
      case RiskState.critical:
        if (closestBarrier != null && canSpeak) {
          _lastAlertTime = now;
          _tts?.speak(
            '⚠️ อันตราย! ${closestBarrier['instruction']} ระยะ ${minDistance.toStringAsFixed(0)} เมตร',
          );
        }
        FlutterForegroundTask.updateService(
          notificationTitle: '🚨 TAM - อันตราย! สิ่งกีดขวางใกล้มาก',
          notificationText: closestBarrier != null
              ? '${closestBarrier['name']} ห่าง ${minDistance.toStringAsFixed(0)}m | GPS $accuracyStr'
              : 'ระวังสิ่งกีดขวาง | GPS $accuracyStr',
        );
        break;

      case RiskState.highRisk:
        if (closestBarrier != null && canSpeak) {
          _lastAlertTime = now;
          _tts?.speak(
            'ระวัง ${closestBarrier['name']} ข้างหน้า ห่าง ${minDistance.toStringAsFixed(0)} เมตร ${closestBarrier['instruction']}',
          );
        }
        FlutterForegroundTask.updateService(
          notificationTitle: '⚠️ TAM - ระวังสิ่งกีดขวางข้างหน้า',
          notificationText: closestBarrier != null
              ? '${closestBarrier['name']} ห่าง ${minDistance.toStringAsFixed(0)}m | เหลือ $remainingStr | GPS $accuracyStr'
              : 'เข้าใกล้พื้นที่เสี่ยง | GPS $accuracyStr',
        );
        break;

      case RiskState.warning:
        if (closestBarrier != null && riskChanged && canSpeak) {
          _lastAlertTime = now;
          _tts?.speak(
            'แจ้งเตือน: มี${closestBarrier['name']} ข้างหน้าในระยะ ${minDistance.toStringAsFixed(0)} เมตร',
          );
        }
        FlutterForegroundTask.updateService(
          notificationTitle: '📍 TAM - กำลังนำทาง ($progressStr)',
          notificationText: 'เหลือ $remainingStr | ระวัง: ${closestBarrier?['name'] ?? 'สิ่งกีดขวาง'} | GPS $accuracyStr',
        );
        break;

      case RiskState.safe:
        FlutterForegroundTask.updateService(
          notificationTitle: '📍 TAM - กำลังนำทางสู่ $_destinationName ($progressStr)',
          notificationText: 'เหลือ $remainingStr | เส้นทางปกติ ✅ | GPS $accuracyStr',
        );
        break;
    }
  }

  /// Haversine distance (meters)
  double _haversineDistance(double lat1, double lon1, double lat2, double lon2) {
    const p = 0.017453292519943295;
    final a = 0.5 -
        cos((lat2 - lat1) * p) / 2 +
        cos(lat1 * p) * cos(lat2 * p) * (1 - cos((lon2 - lon1) * p)) / 2;
    return 12742000 * asin(sqrt(a));
  }

  @override
  void onRepeatEvent(DateTime timestamp) {
    // Heartbeat — ใช้สำหรับ periodic state save
  }

  @override
  Future<void> onDestroy(DateTime timestamp, bool isTimeout) async {
    debugPrint('[NavEngine] ===== Service Terminated at: $timestamp (timeout: $isTimeout) =====');
    await _positionSubscription?.cancel();
    _tts?.stop();
  }

  @override
  void onNotificationButtonPressed(String id) {
    if (id == 'stop_navigation') {
      debugPrint('[NavEngine] User pressed STOP from notification');
      FlutterForegroundTask.stopService();
    }
  }

  @override
  void onNotificationPressed() {
    // กลับเข้าแอป
    FlutterForegroundTask.launchApp('/');
  }

  @override
  void onNotificationDismissed() {
    // Persistent notification ไม่สามารถ dismiss ได้ (FGS spec)
  }
}

// ============================================================================
// Service Orchestrator — called from Flutter UI
// ============================================================================

/// Background Navigation Service — orchestrates FGS lifecycle
///
/// Architecture:
/// - Android: Location Foreground Service เป็น Process keeper
/// - iOS: Core Location background mode
/// - Notification = ช่องทางแสดงสถานะ (ไม่ใช่ตัวรักษา Process)
class BackgroundNavigationService {
  static bool _isInitialized = false;

  /// Initialize foreground service configuration
  static Future<void> init() async {
    if (_isInitialized || kIsWeb) return;

    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: 'tam_navigation_channel',
        channelName: 'TAM Background Navigation',
        channelDescription: 'แจ้งเตือนสถานะการนำทางและสิ่งกีดขวางแบบเรียลไทม์',
        channelImportance: NotificationChannelImportance.HIGH,
        priority: NotificationPriority.HIGH,
        enableVibration: true,
        playSound: true,
      ),
      iosNotificationOptions: const IOSNotificationOptions(
        showNotification: true,
        playSound: true,
      ),
      foregroundTaskOptions: ForegroundTaskOptions(
        eventAction: ForegroundTaskEventAction.repeat(5000),
        autoRunOnBoot: false,
        allowWakeLock: true,
        allowWifiLock: false,
      ),
    );

    _isInitialized = true;
    debugPrint('[NavService] Initialized');
  }

  /// Request all necessary system permissions
  ///
  /// Permission flow:
  /// 1. Notification (Android 13+)
  /// 2. Location (While In Use → Always)
  /// 3. Battery Optimization Exemption (optional but recommended)
  static Future<bool> requestPermissions() async {
    if (kIsWeb) return true;

    // 1. Notification Permission (Android 13+)
    final notifPermission = await FlutterForegroundTask.checkNotificationPermission();
    if (notifPermission != NotificationPermission.granted) {
      await FlutterForegroundTask.requestNotificationPermission();
    }

    // 2. Location Permission
    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        debugPrint('[NavService] ❌ Location permission denied');
        return false;
      }
    }

    if (permission == LocationPermission.deniedForever) {
      debugPrint('[NavService] ❌ Location permission permanently denied');
      return false;
    }

    // 3. Battery Optimization Exemption (optional — not a guarantee)
    if (!await FlutterForegroundTask.isIgnoringBatteryOptimizations) {
      await FlutterForegroundTask.requestIgnoreBatteryOptimization();
    }

    return true;
  }

  /// Start background navigation
  ///
  /// ขั้นตอน:
  /// 1. Request permissions
  /// 2. Start Foreground Service (= Location FGS เป็น Process keeper)
  /// 3. Persistent Notification แสดงสถานะ
  /// 4. Navigation Engine เริ่มทำงานใน isolate
  static Future<bool> startNavigation({
    required String destination,
    double? destLat,
    double? destLng,
    double? totalDistanceMeters,
  }) async {
    if (kIsWeb) return true;

    await init();
    final hasPermissions = await requestPermissions();
    if (!hasPermissions) return false;

    // Save destination metadata so the background isolate has access to real coordinates!
    await FlutterForegroundTask.saveData(key: 'dest_name', value: destination);
    if (destLat != null) {
      await FlutterForegroundTask.saveData(key: 'dest_lat', value: destLat);
    }
    if (destLng != null) {
      await FlutterForegroundTask.saveData(key: 'dest_lng', value: destLng);
    }
    if (totalDistanceMeters != null && totalDistanceMeters > 0) {
      await FlutterForegroundTask.saveData(key: 'total_dist', value: totalDistanceMeters);
    }

    if (await FlutterForegroundTask.isRunningService) {
      debugPrint('[NavService] Already running - updated target');
      return true;
    }

    final result = await FlutterForegroundTask.startService(
      serviceTypes: [ForegroundServiceTypes.location],
      notificationTitle: '📍 TAM - เริ่มต้นการนำทาง',
      notificationText: 'กำลังค้นหาพิกัดและติดตามเส้นทางสู่ $destination...',
      notificationButtons: const [
        NotificationButton(id: 'stop_navigation', text: 'หยุดการนำทาง'),
      ],
      callback: startCallback,
    );

    final success = result is ServiceRequestSuccess;
    debugPrint('[NavService] Start ${success ? "✅" : "❌"}');
    return success;
  }

  /// Stop background navigation
  static Future<bool> stopNavigation() async {
    if (kIsWeb) return true;

    if (await FlutterForegroundTask.isRunningService) {
      final result = await FlutterForegroundTask.stopService();
      final success = result is ServiceRequestSuccess;
      debugPrint('[NavService] Stop ${success ? "✅" : "❌"}');
      return success;
    }
    return true;
  }

  /// Check if background navigation is running
  static Future<bool> isRunning() async {
    if (kIsWeb) return false;
    return await FlutterForegroundTask.isRunningService;
  }
}
