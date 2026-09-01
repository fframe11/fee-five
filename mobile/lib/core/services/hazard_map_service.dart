import 'dart:math' as math;
import 'osrm_routing_service.dart';
import 'package:geolocator/geolocator.dart';
import 'risk_engine.dart';

enum HazardType {
  intersection,
  crosswalk,
  stairs,
  construction,
  destination
}

class MapHazard {
  final double latitude;
  final double longitude;
  final HazardType type;
  final HazardSeverity severity;
  final String source;
  
  MapHazard({
    required this.latitude,
    required this.longitude,
    required this.type,
    required this.severity,
    required this.source,
  });
}

class HazardMapService {
  static final HazardMapService _instance = HazardMapService._internal();
  factory HazardMapService() => _instance;
  HazardMapService._internal();

  final List<MapHazard> _hazards = [];

  void loadFromRoute(OsrmRouteResult route) {
    _hazards.clear();
    for (int i = 1; i < route.steps.length; i++) {
      final step = route.steps[i];
      HazardType type = HazardType.intersection;
      HazardSeverity severity = HazardSeverity.medium;
      
      if (step.maneuverType == 'arrive') {
        type = HazardType.destination;
        severity = HazardSeverity.low;
      }
      
      _hazards.add(MapHazard(
        latitude: step.stepLat,
        longitude: step.stepLon,
        type: type,
        severity: severity,
        source: 'OSRM',
      ));
    }
  }

  void addExternalHazard(MapHazard hazard) {
    _hazards.add(hazard);
  }

  MapHazard? getNearestHazard(double lat, double lon) {
    if (_hazards.isEmpty) return null;
    
    MapHazard? nearest;
    double minDistance = double.infinity;
    
    for (var hazard in _hazards) {
      double dist = Geolocator.distanceBetween(lat, lon, hazard.latitude, hazard.longitude);
      if (dist < minDistance) {
        minDistance = dist;
        nearest = hazard;
      }
    }
    
    return nearest;
  }
}