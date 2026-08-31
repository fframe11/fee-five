/// Fee Five — GPS Monitor Service
/// Runs a continuous low-power GPS watch. When the user is within BARRIER_RADIUS_M
/// of a known barrier, it fires an agent event. Does NOT poll constantly —
/// uses Geolocator's location stream + dynamic barrier list.

import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

import '../models/agent_models.dart';
import '../api_client.dart';
import 'agent_client.dart';

/// Distance in metres to trigger a GPS barrier event
const double _barrierRadius = 80.0;

/// Minimum seconds between consecutive agent calls for the same barrier
const int _cooldownSeconds = 60;

class GpsMonitorService {
  final AgentClient _agent;
  final ApiClient _apiClient = ApiClient();

  // Stream subscription for Geolocator position updates
  StreamSubscription<Position>? _positionSub;

  // Active navigation context
  int? _userId;
  UserAccessibilityMode? _userMode;
  String? _routeId;
  String? _destination;

  // Dynamic live barriers fetched from backend
  List<dynamic> _liveBarriers = [];
  DateTime? _lastBarrierFetchTime;

  // Cooldown tracker per barrier ID
  final Map<int, DateTime> _alertedBarriers = {};

  // Callbacks
  void Function(AgentDecision decision)? onAgentDecision;
  void Function(Position position)? onPositionUpdate;

  GpsMonitorService({AgentClient? agent}) : _agent = agent ?? agentClient;

  // ---------------------------------------------------------------------------
  // Start monitoring
  // ---------------------------------------------------------------------------
  void start({
    required int userId,
    required UserAccessibilityMode userMode,
    String? routeId,
    String? destination,
    LocationAccuracy accuracy = LocationAccuracy.high,
    int distanceFilter = 5,
  }) {
    _userId = userId;
    _userMode = userMode;
    _routeId = routeId;
    _destination = destination;

    _positionSub?.cancel();
    _positionSub = Geolocator.getPositionStream(
      locationSettings: LocationSettings(
        accuracy: accuracy,
        distanceFilter: distanceFilter,
      ),
    ).listen(_onPosition, onError: (e) {
      debugPrint('[GpsMonitor] stream error: $e');
    });

    debugPrint('[GpsMonitor] started — user $userId, mode ${userMode.value}');
  }

  void stop() {
    _positionSub?.cancel();
    _positionSub = null;
    debugPrint('[GpsMonitor] stopped');
  }

  void updateRouteContext({String? routeId, String? destination}) {
    _routeId = routeId;
    _destination = destination;
  }

  // ---------------------------------------------------------------------------
  // Internal: handle each new GPS position
  // ---------------------------------------------------------------------------
  void _onPosition(Position pos) async {
    onPositionUpdate?.call(pos);
    if (_userId == null || _userMode == null) return;

    // Refresh live barriers from backend every 30 seconds
    final now = DateTime.now();
    if (_lastBarrierFetchTime == null || now.difference(_lastBarrierFetchTime!).inSeconds > 30) {
      _lastBarrierFetchTime = now;
      try {
        final fetched = await _apiClient.getActiveBarriers(lat: pos.latitude, lng: pos.longitude);
        if (fetched.isNotEmpty) {
          _liveBarriers = fetched;
        }
      } catch (e) {
        debugPrint('[GpsMonitor] Failed to fetch live barriers: $e');
      }
    }

    // Check dynamic live barriers around user's real GPS position
    for (final barrier in _liveBarriers) {
      final bLat = (barrier['lat'] as num?)?.toDouble() ?? 0.0;
      final bLng = (barrier['lng'] as num?)?.toDouble() ?? 0.0;
      if (bLat == 0.0 || bLng == 0.0) continue;

      final dist = _haversine(pos.latitude, pos.longitude, bLat, bLng);
      if (dist <= _barrierRadius) {
        _maybeAlert(pos, barrier, dist);
      }
    }
  }

  void _maybeAlert(Position pos, Map<String, dynamic> barrier, double distM) {
    final barrierId = barrier['id'] is int ? barrier['id'] as int : (barrier['id']?.hashCode ?? 0);
    final lastAlert = _alertedBarriers[barrierId];

    if (lastAlert != null &&
        DateTime.now().difference(lastAlert).inSeconds < _cooldownSeconds) {
      return; // still in cooldown
    }

    _alertedBarriers[barrierId] = DateTime.now();
    debugPrint('[GpsMonitor] barrier #$barrierId at ${distM.toStringAsFixed(0)}m — sending agent event');

    _agent
        .notifyGpsBarrier(
          userId: _userId!,
          userMode: _userMode!,
          lat: pos.latitude,
          lng: pos.longitude,
          barrierInfo: {
            ...barrier,
            'distance_m': distM.toStringAsFixed(1),
          },
          routeId: _routeId,
          destination: _destination,
        )
        .then((decision) {
          if (decision != null) onAgentDecision?.call(decision);
        })
        .catchError((e) => debugPrint('[GpsMonitor] agent error: $e'));
  }

  // ---------------------------------------------------------------------------
  // Haversine distance helper
  // ---------------------------------------------------------------------------
  static double _haversine(double lat1, double lon1, double lat2, double lon2) {
    const R = 6371000.0;
    final phi1 = lat1 * math.pi / 180;
    final phi2 = lat2 * math.pi / 180;
    final dPhi = (lat2 - lat1) * math.pi / 180;
    final dLam = (lon2 - lon1) * math.pi / 180;
    final a = math.sin(dPhi / 2) * math.sin(dPhi / 2) +
        math.cos(phi1) * math.cos(phi2) * math.sin(dLam / 2) * math.sin(dLam / 2);
    return R * 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
  }
}
