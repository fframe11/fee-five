import 'dart:math';
import 'package:flutter/foundation.dart';

/// จุดพิกัดบนเส้นทาง
class LatLng {
  final double latitude;
  final double longitude;

  const LatLng(this.latitude, this.longitude);

  Map<String, dynamic> toJson() => {'lat': latitude, 'lng': longitude};

  factory LatLng.fromJson(Map<String, dynamic> json) =>
      LatLng(json['lat'] as double, json['lng'] as double);

  @override
  String toString() => 'LatLng($latitude, $longitude)';
}

/// ผลลัพธ์จาก Map Matching — ตำแหน่งที่ snap ลงบนเส้นทาง
class MatchedPosition {
  /// ตำแหน่งที่ snap ลงบนเส้นทาง
  final LatLng snappedPosition;

  /// ระยะห่างจากตำแหน่ง GPS ดิบถึงจุด snap (เมตร)
  final double distanceFromRoute;

  /// ความก้าวหน้าบนเส้นทาง (0.0 = เริ่มต้น, 1.0 = ถึงปลายทาง)
  final double progressAlongRoute;

  /// Index ของ segment บนเส้นทางที่ใกล้ที่สุด
  final int nearestSegmentIndex;

  /// ระยะทางที่เหลือถึงปลายทาง (เมตร)
  final double remainingDistanceMeters;

  /// ผู้ใช้อยู่นอกเส้นทางหรือไม่ (distanceFromRoute > threshold)
  final bool isOffRoute;

  const MatchedPosition({
    required this.snappedPosition,
    required this.distanceFromRoute,
    required this.progressAlongRoute,
    required this.nearestSegmentIndex,
    required this.remainingDistanceMeters,
    required this.isOffRoute,
  });
}

/// Map Matching Engine — snap ตำแหน่ง GPS ลงบนเส้นทาง polyline
///
/// ป้องกันกรณีที่ GPS คลาดเคลื่อนแล้วระบบคิดว่าผู้ใช้ออกนอกเส้นทาง
class MapMatcher {
  /// Route polyline (ordered list of LatLng waypoints)
  List<LatLng> _routePolyline = [];

  /// Precomputed cumulative distances along route segments (meters)
  List<double> _cumulativeDistances = [];

  /// Total route length (meters)
  double _totalRouteLength = 0.0;

  /// Off-route threshold (meters) — ถ้า GPS ห่างจากเส้นทางมากกว่านี้ ถือว่า off-route
  double offRouteThreshold;

  MapMatcher({this.offRouteThreshold = 25.0});

  /// โหลดเส้นทางใหม่
  void setRoute(List<LatLng> polyline) {
    _routePolyline = List.unmodifiable(polyline);
    _precomputeDistances();
    debugPrint('[MapMatch] Route loaded: ${polyline.length} points, total ${_totalRouteLength.toStringAsFixed(1)}m');
  }

  /// Precompute cumulative distances สำหรับ progress calculation
  void _precomputeDistances() {
    _cumulativeDistances = [0.0];
    _totalRouteLength = 0.0;

    for (int i = 1; i < _routePolyline.length; i++) {
      final segDist = _haversineDistance(
        _routePolyline[i - 1].latitude, _routePolyline[i - 1].longitude,
        _routePolyline[i].latitude, _routePolyline[i].longitude,
      );
      _totalRouteLength += segDist;
      _cumulativeDistances.add(_totalRouteLength);
    }
  }

  /// Match ตำแหน่ง GPS ลงบนเส้นทาง
  ///
  /// Returns null ถ้ายังไม่ได้โหลด route
  MatchedPosition? match(double latitude, double longitude) {
    if (_routePolyline.length < 2) return null;

    double minDistance = double.infinity;
    int bestSegmentIndex = 0;
    LatLng bestSnappedPoint = _routePolyline.first;
    double bestProjectionRatio = 0.0;

    // หา segment ที่ใกล้ที่สุดด้วย perpendicular projection
    for (int i = 0; i < _routePolyline.length - 1; i++) {
      final a = _routePolyline[i];
      final b = _routePolyline[i + 1];

      final projection = _projectPointOnSegment(
        latitude, longitude,
        a.latitude, a.longitude,
        b.latitude, b.longitude,
      );

      final dist = _haversineDistance(
        latitude, longitude,
        projection.latitude, projection.longitude,
      );

      if (dist < minDistance) {
        minDistance = dist;
        bestSegmentIndex = i;
        bestSnappedPoint = projection;

        // คำนวณ ratio ของ projection บน segment นี้
        final segLength = _haversineDistance(
          a.latitude, a.longitude, b.latitude, b.longitude,
        );
        if (segLength > 0) {
          final projDist = _haversineDistance(
            a.latitude, a.longitude,
            projection.latitude, projection.longitude,
          );
          bestProjectionRatio = (projDist / segLength).clamp(0.0, 1.0);
        } else {
          bestProjectionRatio = 0.0;
        }
      }
    }

    // คำนวณ progress along route (0.0 - 1.0)
    final distAlongRoute = _cumulativeDistances[bestSegmentIndex] +
        bestProjectionRatio *
            (_cumulativeDistances[bestSegmentIndex + 1] -
                _cumulativeDistances[bestSegmentIndex]);
    final progress = _totalRouteLength > 0
        ? (distAlongRoute / _totalRouteLength).clamp(0.0, 1.0)
        : 0.0;

    final remaining = _totalRouteLength - distAlongRoute;
    final isOffRoute = minDistance > offRouteThreshold;

    if (isOffRoute) {
      debugPrint('[MapMatch] ⚠️ Off-route! distance=${minDistance.toStringAsFixed(1)}m (threshold=${offRouteThreshold}m)');
    }

    return MatchedPosition(
      snappedPosition: bestSnappedPoint,
      distanceFromRoute: minDistance,
      progressAlongRoute: progress,
      nearestSegmentIndex: bestSegmentIndex,
      remainingDistanceMeters: remaining.clamp(0.0, double.infinity),
      isOffRoute: isOffRoute,
    );
  }

  /// คำนวณระยะทางจากตำแหน่งปัจจุบันถึงจุดถัดไปบน route (สำหรับ turn-by-turn)
  double? distanceToNextWaypoint(double latitude, double longitude) {
    final matched = match(latitude, longitude);
    if (matched == null) return null;

    final nextIdx = (matched.nearestSegmentIndex + 1)
        .clamp(0, _routePolyline.length - 1);
    final next = _routePolyline[nextIdx];

    return _haversineDistance(latitude, longitude, next.latitude, next.longitude);
  }

  /// Project จุด P ลงบน segment AB (perpendicular projection)
  LatLng _projectPointOnSegment(
    double pLat, double pLng,
    double aLat, double aLng,
    double bLat, double bLng,
  ) {
    final dx = bLng - aLng;
    final dy = bLat - aLat;
    final lenSq = dx * dx + dy * dy;

    if (lenSq == 0) return LatLng(aLat, aLng);

    final t = ((pLng - aLng) * dx + (pLat - aLat) * dy) / lenSq;
    final clampedT = t.clamp(0.0, 1.0);

    return LatLng(
      aLat + clampedT * dy,
      aLng + clampedT * dx,
    );
  }

  /// Haversine distance (เมตร) — ประหยัด CPU
  double _haversineDistance(double lat1, double lon1, double lat2, double lon2) {
    const p = 0.017453292519943295; // pi / 180
    final a = 0.5 -
        cos((lat2 - lat1) * p) / 2 +
        cos(lat1 * p) * cos(lat2 * p) * (1 - cos((lon2 - lon1) * p)) / 2;
    return 12742000 * asin(sqrt(a)); // 2 * R * 1000 in meters
  }

  /// Check ว่ามี route loaded อยู่หรือไม่
  bool get hasRoute => _routePolyline.length >= 2;

  /// Route length (meters)
  double get totalRouteLength => _totalRouteLength;

  /// Route polyline points
  List<LatLng> get routePolyline => _routePolyline;
}
