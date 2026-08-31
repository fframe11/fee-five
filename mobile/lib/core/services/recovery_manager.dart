import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// คลาสที่ใช้สำหรับจัดการข้อมูลเซสชันการนำทาง
/// จัดเก็บข้อมูลเพื่อสามารถกู้คืนสถานะการนำทางได้หากแอปปิดตัวลง
class NavigationSession {
  final String sessionId;
  final String destinationName;
  final double destinationLat;
  final double destinationLng;
  final List<Map<String, double>> routePolyline;
  final double lastLocationLat;
  final double lastLocationLng;
  final DateTime lastTimestamp;
  final String riskState;
  final double progressAlongRoute;
  final bool isActive;

  NavigationSession({
    required this.sessionId,
    required this.destinationName,
    required this.destinationLat,
    required this.destinationLng,
    required this.routePolyline,
    required this.lastLocationLat,
    required this.lastLocationLng,
    required this.lastTimestamp,
    required this.riskState,
    required this.progressAlongRoute,
    required this.isActive,
  });

  /// แปลงเป็น JSON สำหรับการจัดเก็บ
  Map<String, dynamic> toJson() {
    return {
      'sessionId': sessionId,
      'destinationName': destinationName,
      'destinationLat': destinationLat,
      'destinationLng': destinationLng,
      'routePolyline': routePolyline,
      'lastLocationLat': lastLocationLat,
      'lastLocationLng': lastLocationLng,
      'lastTimestamp': lastTimestamp.toIso8601String(),
      'riskState': riskState,
      'progressAlongRoute': progressAlongRoute,
      'isActive': isActive,
    };
  }

  /// สร้างออบเจ็กต์จาก JSON ที่จัดเก็บ
  factory NavigationSession.fromJson(Map<String, dynamic> json) {
    var routePolylineDynamic = json['routePolyline'] as List<dynamic>? ?? [];
    List<Map<String, double>> polyline = routePolylineDynamic.map((item) {
      Map<String, dynamic> mapItem = item as Map<String, dynamic>;
      return {
        'lat': (mapItem['lat'] as num).toDouble(),
        'lng': (mapItem['lng'] as num).toDouble(),
      };
    }).toList();

    return NavigationSession(
      sessionId: json['sessionId'] as String? ?? '',
      destinationName: json['destinationName'] as String? ?? '',
      destinationLat: (json['destinationLat'] as num?)?.toDouble() ?? 0.0,
      destinationLng: (json['destinationLng'] as num?)?.toDouble() ?? 0.0,
      routePolyline: polyline,
      lastLocationLat: (json['lastLocationLat'] as num?)?.toDouble() ?? 0.0,
      lastLocationLng: (json['lastLocationLng'] as num?)?.toDouble() ?? 0.0,
      lastTimestamp: json['lastTimestamp'] != null 
          ? DateTime.parse(json['lastTimestamp'] as String) 
          : DateTime.now(),
      riskState: json['riskState'] as String? ?? 'safe',
      progressAlongRoute: (json['progressAlongRoute'] as num?)?.toDouble() ?? 0.0,
      isActive: json['isActive'] as bool? ?? false,
    );
  }
}

/// ระบบกู้คืนสถานะ (Recovery Manager)
/// จัดการการบันทึกและกู้คืนสถานะการนำทางโดยอัตโนมัติ
class RecoveryManager {
  static final RecoveryManager _instance = RecoveryManager._internal();
  static const String _sessionKey = 'nav_session';
  Timer? _autoSaveTimer;

  factory RecoveryManager() {
    return _instance;
  }

  RecoveryManager._internal();

  /// บันทึกสถานะการนำทางปัจจุบันลงใน SharedPreferences
  Future<void> saveState(NavigationSession session) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonString = jsonEncode(session.toJson());
      await prefs.setString(_sessionKey, jsonString);
      debugPrint('[กู้คืน] บันทึกสถานะการนำทางสำเร็จ sessionId: ${session.sessionId}');
    } catch (e) {
      debugPrint('[กู้คืน] เกิดข้อผิดพลาดในการบันทึกสถานะ: $e');
    }
  }

  /// กู้คืนสถานะการนำทางจาก SharedPreferences
  Future<NavigationSession?> restoreState() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonString = prefs.getString(_sessionKey);
      
      if (jsonString == null) {
        debugPrint('[กู้คืน] ไม่พบสถานะการนำทางที่บันทึกไว้');
        return null;
      }

      final Map<String, dynamic> jsonMap = jsonDecode(jsonString);
      final session = NavigationSession.fromJson(jsonMap);

      final now = DateTime.now();
      final difference = now.difference(session.lastTimestamp);
      
      // ตรวจสอบว่า session หมดอายุหรือไม่ (เกิน 30 นาที)
      if (difference.inMinutes >= 30) {
        debugPrint('[กู้คืน] สถานะการนำทางหมดอายุแล้ว (เกิน 30 นาที)');
        await clearState();
        return null;
      }

      debugPrint('[กู้คืน] กู้คืนสถานะการนำทางสำเร็จ sessionId: ${session.sessionId}');
      return session;
    } catch (e) {
      debugPrint('[กู้คืน] เกิดข้อผิดพลาดในการกู้คืนสถานะ: $e');
      return null;
    }
  }

  /// ลบสถานะการนำทางที่บันทึกไว้
  Future<void> clearState() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_sessionKey);
      _autoSaveTimer?.cancel();
      debugPrint('[กู้คืน] ล้างสถานะการนำทางเรียบร้อยแล้ว');
    } catch (e) {
      debugPrint('[กู้คืน] เกิดข้อผิดพลาดในการล้างสถานะ: $e');
    }
  }

  /// ตรวจสอบว่ามีเซสชันการนำทางที่ยังใช้งานได้อยู่หรือไม่
  Future<bool> hasActiveSession() async {
    final session = await restoreState();
    if (session == null) return false;
    return session.isActive;
  }

  /// เริ่มการบันทึกสถานะโดยอัตโนมัติ (ทุก 10 วินาที)
  void autoSave(NavigationSession session) {
    _autoSaveTimer?.cancel();
    _autoSaveTimer = Timer.periodic(const Duration(seconds: 10), (timer) {
      saveState(session);
    });
    
    // บันทึกทันทีเมื่อเรียกใช้
    saveState(session);
  }

  /// ยกเลิกการบันทึกอัตโนมัติ
  void stopAutoSave() {
    _autoSaveTimer?.cancel();
    _autoSaveTimer = null;
    debugPrint('[กู้คืน] ยกเลิกระบบบันทึกอัตโนมัติ');
  }
}
