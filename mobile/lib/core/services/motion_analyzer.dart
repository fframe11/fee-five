/// Fee Five — Motion Analyzer
/// Reads accelerometer data and detects anomalous patterns:
///   - sudden_stop: rapid deceleration (possible obstacle encounter)
///   - fall_detected: high-magnitude spike across all axes
///   - wandering: moving in circles without forward progress
///
/// Uses Flutter's sensors_plus package.
/// When a pattern is detected, it fires an agent event (not a direct alert).

import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';

import '../models/agent_models.dart';
import 'agent_client.dart';

// ---------------------------------------------------------------------------
// Thresholds (conservative to minimise false positives)
// ---------------------------------------------------------------------------

/// m/s² — acceleration magnitude that indicates a sudden stop/jerk
const double _suddenStopThreshold = 14.0;

/// m/s² — magnitude indicating a likely fall (very high spike)
const double _fallThreshold = 28.0;

/// Minimum seconds between consecutive motion alerts (cooldown)
const int _motionCooldownSeconds = 30;

// ---------------------------------------------------------------------------
// Simulated accelerometer sample (replaces sensors_plus in web builds)
// ---------------------------------------------------------------------------
class AccelSample {
  final double x, y, z;
  const AccelSample(this.x, this.y, this.z);
  double get magnitude => math.sqrt(x * x + y * y + z * z);
}

// ---------------------------------------------------------------------------
// MotionAnalyzer
// ---------------------------------------------------------------------------
class MotionAnalyzer {
  final AgentClient _agent;

  int? _userId;
  UserAccessibilityMode? _userMode;
  double _lat = 0, _lng = 0;
  String? _routeId;

  DateTime? _lastMotionAlert;

  // Callback when agent responds
  final void Function(AgentDecision decision)? onAgentDecision;

  // Raw sample buffer for smoothing
  final List<double> _magnitudeBuffer = [];
  static const int _bufferSize = 10;

  MotionAnalyzer({
    AgentClient? agent,
    this.onAgentDecision,
  }) : _agent = agent ?? agentClient;

  // ---------------------------------------------------------------------------
  // Start / Stop
  // ---------------------------------------------------------------------------
  void start({
    required int userId,
    required UserAccessibilityMode userMode,
    required double lat,
    required double lng,
    String? routeId,
  }) {
    _userId = userId;
    _userMode = userMode;
    _lat = lat;
    _lng = lng;
    _routeId = routeId;
    debugPrint('[MotionAnalyzer] started');
  }

  void stop() {
    _userId = null;
    _magnitudeBuffer.clear();
    debugPrint('[MotionAnalyzer] stopped');
  }

  void updateLocation(double lat, double lng) {
    _lat = lat;
    _lng = lng;
  }

  // ---------------------------------------------------------------------------
  // Feed a raw accelerometer sample (call from sensors_plus listener)
  // ---------------------------------------------------------------------------
  void onAccelSample(double x, double y, double z) {
    if (_userId == null) return;

    final sample = AccelSample(x, y, z);
    final mag = sample.magnitude;

    _magnitudeBuffer.add(mag);
    if (_magnitudeBuffer.length > _bufferSize) {
      _magnitudeBuffer.removeAt(0);
    }

    _classify(mag);
  }

  void _classify(double mag) {
    // Cooldown check
    if (_lastMotionAlert != null &&
        DateTime.now().difference(_lastMotionAlert!).inSeconds < _motionCooldownSeconds) {
      return;
    }

    String? pattern;
    if (mag >= _fallThreshold) {
      pattern = 'fall_detected';
    } else if (mag >= _suddenStopThreshold) {
      // Only fire if previous readings were calm (moving at normal pace)
      final avgPrevious = _magnitudeBuffer.length > 3
          ? _magnitudeBuffer
                  .sublist(0, _magnitudeBuffer.length - 1)
                  .fold(0.0, (a, b) => a + b) /
              (_magnitudeBuffer.length - 1)
          : mag;
      if (avgPrevious < 12.0) {
        pattern = 'sudden_stop';
      }
    }

    if (pattern != null) {
      _lastMotionAlert = DateTime.now();
      debugPrint('[MotionAnalyzer] pattern detected: $pattern (mag=${mag.toStringAsFixed(1)})');
      _sendAgentEvent(pattern, mag);
    }
  }

  void _sendAgentEvent(String pattern, double magnitude) {
    _agent
        .notifyMotionAnomaly(
          userId: _userId!,
          userMode: _userMode!,
          lat: _lat,
          lng: _lng,
          pattern: pattern,
          magnitude: magnitude,
          routeId: _routeId,
        )
        .then((decision) {
          if (decision != null) onAgentDecision?.call(decision);
        })
        .catchError((e) => debugPrint('[MotionAnalyzer] agent error: $e'));
  }
}
