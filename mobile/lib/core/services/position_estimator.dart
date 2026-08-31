import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'package:pedometer/pedometer.dart';

/// แหล่งที่มาของตำแหน่ง (Position Source)
enum PositionSource {
  gps,
  deadReckoning,
  fused,
}

/// ข้อมูลตำแหน่งที่ผ่านการประมาณค่าและ Sensor Fusion แล้ว
class EstimatedPosition {
  final double latitude;
  final double longitude;
  final double accuracy;
  final double confidence;
  final double heading;
  final double speed;
  final PositionSource source;
  final DateTime timestamp;

  EstimatedPosition({
    required this.latitude,
    required this.longitude,
    required this.accuracy,
    required this.confidence,
    required this.heading,
    required this.speed,
    required this.source,
    required this.timestamp,
  });
}

/// Engine สำหรับ Sensor Fusion ช่วยนำทางผู้พิการทางสายตา
class PositionEstimator {
  StreamSubscription<Position>? _gpsSubscription;
  StreamSubscription<AccelerometerEvent>? _accelSubscription;
  StreamSubscription<GyroscopeEvent>? _gyroSubscription;
  StreamSubscription<StepCount>? _stepSubscription;

  final _positionController = StreamController<EstimatedPosition>.broadcast();
  
  /// Stream ของตำแหน่งที่ประมาณค่าแล้ว
  Stream<EstimatedPosition> get positionStream => _positionController.stream;

  double _distanceFilter = 0.0;
  
  // State for dead reckoning
  Position? _lastGpsPosition;
  DateTime? _lastGpsTime;
  int? _lastStepCount;
  
  double _currentHeading = 0.0;
  
  // Smoothing state
  double? _smoothedLat;
  double? _smoothedLng;

  // Constants
  static const double _earthRadius = 6371000.0; // meters
  static const double _strideLength = 0.65; // meters per step (walking)
  static const double _alpha = 0.3; // Exponential smoothing factor

  /// ตั้งค่าความไวของ GPS
  void setDistanceFilter(double meters) {
    _distanceFilter = meters;
    // หากทำงานอยู่แล้ว ให้ restart เพื่อใช้ค่า distance filter ใหม่
    if (_gpsSubscription != null) {
      stop();
      start();
    }
  }

  /// เริ่มต้นการทำงานของ Sensor Fusion
  void start() {
    debugPrint('[ตำแหน่ง] Starting PositionEstimator...');
    
    if (kIsWeb) {
      // บน Web ไม่มี sensors ให้ใช้ GPS อย่างเดียว
      _gpsSubscription = Geolocator.getPositionStream(
        locationSettings: LocationSettings(
          distanceFilter: _distanceFilter.toInt(),
        ),
      ).listen((Position position) {
        _positionController.add(EstimatedPosition(
          latitude: position.latitude,
          longitude: position.longitude,
          accuracy: position.accuracy,
          confidence: 0.8, // Default confidence for web
          heading: position.heading,
          speed: position.speed,
          source: PositionSource.gps,
          timestamp: position.timestamp,
        ));
      });
      return;
    }

    // เริ่มทำงานบนอุปกรณ์พกพา
    _startGps();
    _startSensors();
  }

  void _startGps() {
    _gpsSubscription = Geolocator.getPositionStream(
      locationSettings: LocationSettings(
        distanceFilter: _distanceFilter.toInt(),
      ),
    ).listen((Position position) {
      debugPrint('[ตำแหน่ง] GPS Update received: ${position.latitude}, ${position.longitude}');
      
      _lastGpsPosition = position;
      _lastGpsTime = DateTime.now();
      
      // Update heading from GPS if valid
      if (position.speed > 0.5 && position.heading >= 0) {
        _currentHeading = position.heading;
      }

      // Apply exponential smoothing
      if (_smoothedLat == null || _smoothedLng == null) {
        _smoothedLat = position.latitude;
        _smoothedLng = position.longitude;
      } else {
        _smoothedLat = _alpha * position.latitude + (1 - _alpha) * _smoothedLat!;
        _smoothedLng = _alpha * position.longitude + (1 - _alpha) * _smoothedLng!;
      }

      _emitPosition(PositionSource.gps);
    });
  }

  void _startSensors() {
    // Gyroscope สำหรับปรับแก้ Heading
    _gyroSubscription = gyroscopeEventStream().listen((GyroscopeEvent event) {
      // ใช้แกน Z สำหรับการหมุนรอบตัว (yaw) อย่างง่าย
      // ในแอปพลิเคชันจริงอาจต้องทำ sensor fusion ที่ซับซ้อนกว่านี้
      _currentHeading += event.z * (180.0 / math.pi) * 0.1; // 0.1 คือสมมติฐานช่วงเวลา (dt)
      if (_currentHeading < 0) _currentHeading += 360;
      if (_currentHeading >= 360) _currentHeading -= 360;
    });

    // Pedometer สำหรับนับก้าวเพื่อหาระยะทาง
    _stepSubscription = Pedometer.stepCountStream.listen((StepCount event) {
      int currentSteps = event.steps;
      if (_lastStepCount != null) {
        int stepsTaken = currentSteps - _lastStepCount!;
        if (stepsTaken > 0) {
          _applyDeadReckoning(stepsTaken);
        }
      }
      _lastStepCount = currentSteps;
    });

    // Accelerometer (เพิ่มเติมหากต้องตรวจจับการเคลื่อนไหวอื่นๆ)
    _accelSubscription = accelerometerEventStream().listen((AccelerometerEvent event) {
      // สามารถนำมาใช้คำนวณการก้าวได้หากไม่มี Pedometer หรือช่วยเสริม
    });
  }

  void _applyDeadReckoning(int steps) {
    if (_smoothedLat == null || _smoothedLng == null) return;

    double distance = steps * _strideLength;
    
    // แปลงพิกัดตามระยะทางและทิศทาง (Heading)
    double headingRad = _currentHeading * (math.pi / 180.0);
    double dx = distance * math.sin(headingRad);
    double dy = distance * math.cos(headingRad);

    double dLat = dy / _earthRadius;
    double dLng = dx / (_earthRadius * math.cos(_smoothedLat! * math.pi / 180.0));

    _smoothedLat = _smoothedLat! + (dLat * 180.0 / math.pi);
    _smoothedLng = _smoothedLng! + (dLng * 180.0 / math.pi);

    debugPrint('[ตำแหน่ง] Dead Reckoning applied: $steps steps');
    
    _emitPosition(PositionSource.deadReckoning);
  }

  double _calculateConfidence(PositionSource source) {
    if (source == PositionSource.gps) {
      // ความมั่นใจลดลงถ้า accuracy สูง (แย่)
      double accuracy = _lastGpsPosition?.accuracy ?? 100.0;
      return math.max(0.0, 1.0 - (accuracy / 50.0)).clamp(0.0, 1.0);
    } else {
      // Dead Reckoning: ความมั่นใจลดลงตามระยะเวลาที่ห่างจาก GPS ครั้งล่าสุด
      if (_lastGpsTime == null) return 0.0;
      double secondsSinceGps = DateTime.now().difference(_lastGpsTime!).inSeconds.toDouble();
      return math.max(0.0, 1.0 - (secondsSinceGps / 60.0)).clamp(0.0, 1.0);
    }
  }

  void _emitPosition(PositionSource source) {
    if (_smoothedLat == null || _smoothedLng == null) return;

    double confidence = _calculateConfidence(source);

    _positionController.add(EstimatedPosition(
      latitude: _smoothedLat!,
      longitude: _smoothedLng!,
      accuracy: _lastGpsPosition?.accuracy ?? 10.0,
      confidence: confidence,
      heading: _currentHeading,
      speed: _lastGpsPosition?.speed ?? 0.0,
      source: source,
      timestamp: DateTime.now(),
    ));
  }

  /// หยุดการทำงาน
  void stop() {
    debugPrint('[ตำแหน่ง] Stopping PositionEstimator...');
    _gpsSubscription?.cancel();
    _accelSubscription?.cancel();
    _gyroSubscription?.cancel();
    _stepSubscription?.cancel();
    
    _gpsSubscription = null;
    _accelSubscription = null;
    _gyroSubscription = null;
    _stepSubscription = null;
  }

  /// คืนค่า resource
  void dispose() {
    stop();
    _positionController.close();
  }
}
