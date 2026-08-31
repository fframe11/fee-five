import 'dart:convert';
import 'package:http/http.dart' as http;

class RouteStep {
  final String instruction;
  final String roadName;
  final double distanceMeters;
  final double durationSeconds;
  final String maneuverType; // 'turn', 'depart', 'arrive', 'continue', etc.
  final String maneuverModifier; // 'left', 'right', 'straight', 'slight left', etc.
  final double stepLat;
  final double stepLon;

  const RouteStep({
    required this.instruction,
    required this.roadName,
    required this.distanceMeters,
    required this.durationSeconds,
    required this.maneuverType,
    required this.maneuverModifier,
    required this.stepLat,
    required this.stepLon,
  });
}

class OsrmRouteResult {
  final double totalDistanceMeters;
  final double totalDurationSeconds;
  final List<RouteStep> steps;
  final List<List<double>> polylineCoordinates; // [[lon, lat], ...]

  const OsrmRouteResult({
    required this.totalDistanceMeters,
    required this.totalDurationSeconds,
    required this.steps,
    required this.polylineCoordinates,
  });
}

class OsrmRoutingService {
  /// Query real walking route from OSRM Open Source Routing Machine
  static Future<OsrmRouteResult?> getWalkingRoute({
    required double originLat,
    required double originLon,
    required double destLat,
    required double destLon,
    String profile = 'walking', // 'walking' or 'driving'
  }) async {
    try {
      final url = 'https://router.project-osrm.org/route/v1/$profile/$originLon,$originLat;$destLon,$destLat?overview=full&geometries=geojson&steps=true';
      
      final resp = await http.get(
        Uri.parse(url),
        headers: {'User-Agent': 'TAM-AccessibilityApp/1.0'},
      ).timeout(const Duration(seconds: 4));

      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body);
        final routes = data['routes'] as List<dynamic>?;
        if (routes != null && routes.isNotEmpty) {
          final route = routes[0];
          final totalDist = (route['distance'] as num?)?.toDouble() ?? 0.0;
          final totalDur = (route['duration'] as num?)?.toDouble() ?? 0.0;
          
          List<List<double>> coords = [];
          if (route['geometry'] != null && route['geometry']['coordinates'] != null) {
            final rawCoords = route['geometry']['coordinates'] as List<dynamic>;
            coords = rawCoords.map((c) => [(c[0] as num).toDouble(), (c[1] as num).toDouble()]).toList();
          }

          final List<RouteStep> parsedSteps = [];
          final legs = route['legs'] as List<dynamic>?;
          if (legs != null && legs.isNotEmpty) {
            final steps = legs[0]['steps'] as List<dynamic>?;
            if (steps != null) {
              for (var s in steps) {
                final dist = (s['distance'] as num?)?.toDouble() ?? 0.0;
                final dur = (s['duration'] as num?)?.toDouble() ?? 0.0;
                final rName = (s['name'] as String? ?? '').trim();
                final maneuver = s['maneuver'] as Map<String, dynamic>? ?? {};
                final mType = maneuver['type'] as String? ?? 'turn';
                final mMod = maneuver['modifier'] as String? ?? '';
                final mLoc = maneuver['location'] as List<dynamic>? ?? [0.0, 0.0];

                final thaiInstruction = _translateManeuverToThai(mType, mMod, rName, dist);

                parsedSteps.add(RouteStep(
                  instruction: thaiInstruction,
                  roadName: rName.isNotEmpty ? rName : 'ทางเดิน',
                  distanceMeters: dist,
                  durationSeconds: dur,
                  maneuverType: mType,
                  maneuverModifier: mMod,
                  stepLat: (mLoc.length > 1 ? mLoc[1] as num : 0.0).toDouble(),
                  stepLon: (mLoc.isNotEmpty ? mLoc[0] as num : 0.0).toDouble(),
                ));
              }
            }
          }

          return OsrmRouteResult(
            totalDistanceMeters: totalDist,
            totalDurationSeconds: totalDur,
            steps: parsedSteps,
            polylineCoordinates: coords,
          );
        }
      }
    } catch (_) {}
    return null;
  }

  static String _translateManeuverToThai(String type, String modifier, String roadName, double dist) {
    final distStr = dist > 1000 ? '${(dist / 1000).toStringAsFixed(1)} กม.' : '${dist.round()} เมตร';
    final targetRoad = roadName.isNotEmpty ? 'เข้าสู่ $roadName' : '';

    if (type == 'depart') {
      return 'เริ่มต้นเดินทาง มุ่งหน้าตรงไป $distStr';
    } else if (type == 'arrive') {
      return 'ถึงจุดหมายปลายทางของคุณแล้ว';
    }

    String direction = 'ตรงไป';
    if (modifier.contains('slight left')) {
      direction = 'เบี่ยงซ้าย';
    } else if (modifier.contains('slight right')) {
      direction = 'เบี่ยงขวา';
    } else if (modifier.contains('sharp left')) {
      direction = 'เลี้ยวซ้ายหักศอก';
    } else if (modifier.contains('sharp right')) {
      direction = 'เลี้ยวขวาหักศอก';
    } else if (modifier.contains('left')) {
      direction = 'เลี้ยวซ้าย';
    } else if (modifier.contains('right')) {
      direction = 'เลี้ยวขวา';
    } else if (modifier.contains('u-turn') || modifier.contains('uturn')) {
      direction = 'กลับรถ';
    }

    if (roadName.isNotEmpty) {
      return '$direction $targetRoad (อีก $distStr)';
    } else {
      return '$direction ตรงไป $distStr';
    }
  }
}
