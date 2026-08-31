/// Fee Five — Smart Accessibility Agent HTTP Client
/// Communicates with the backend /api/v1/agent/* endpoints.
/// Handles retries, timeout, and graceful fallback so the app never crashes
/// if the agent is unavailable.

import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../api_client.dart';
import '../models/agent_models.dart';

class AgentClient {
  final ApiClient _api;
  static const Duration _timeout = Duration(seconds: 12);

  AgentClient({ApiClient? api}) : _api = api ?? ApiClient();

  // ---------------------------------------------------------------------------
  // Send any accessibility event to the Smart Agent
  // ---------------------------------------------------------------------------
  Future<AgentDecision?> sendEvent(AgentEventPayload payload) async {
    try {
      final url = Uri.parse('${_api.baseUrl}/api/v1/agent/event');
      final response = await http
          .post(url, headers: _headers(), body: jsonEncode(payload.toJson()))
          .timeout(_timeout);

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        return AgentDecision.fromJson(data);
      } else {
        debugPrint('[AgentClient] event error ${response.statusCode}: ${response.body}');
        return null;
      }
    } catch (e) {
      debugPrint('[AgentClient] sendEvent failed: $e');
      return null;
    }
  }

  // ---------------------------------------------------------------------------
  // Convenience: GPS Barrier event
  // ---------------------------------------------------------------------------
  Future<AgentDecision?> notifyGpsBarrier({
    required int userId,
    required UserAccessibilityMode userMode,
    required double lat,
    required double lng,
    required Map<String, dynamic> barrierInfo,
    String? routeId,
    String? destination,
  }) {
    return sendEvent(AgentEventPayload(
      eventType: AgentEventType.gpsBarrier,
      userId: userId,
      userMode: userMode,
      lat: lat,
      lng: lng,
      barrierInfo: barrierInfo,
      routeId: routeId,
      destination: destination,
    ));
  }

  // ---------------------------------------------------------------------------
  // Convenience: Voice command event
  // ---------------------------------------------------------------------------
  Future<AgentDecision?> sendVoiceCommand({
    required int userId,
    required UserAccessibilityMode userMode,
    required double lat,
    required double lng,
    required String voiceText,
    String? routeId,
    String? destination,
  }) {
    return sendEvent(AgentEventPayload(
      eventType: AgentEventType.voiceCommand,
      userId: userId,
      userMode: userMode,
      lat: lat,
      lng: lng,
      voiceText: voiceText,
      routeId: routeId,
      destination: destination,
    ));
  }

  // ---------------------------------------------------------------------------
  // Convenience: Camera scan event (on-demand — only when user opened camera)
  // ---------------------------------------------------------------------------
  Future<AgentDecision?> sendCameraScan({
    required int userId,
    required UserAccessibilityMode userMode,
    required double lat,
    required double lng,
    String? cameraFrameB64,   // null = user opened camera but no frame yet
    String? routeId,
    String? destination,
  }) {
    return sendEvent(AgentEventPayload(
      eventType: AgentEventType.cameraScan,
      userId: userId,
      userMode: userMode,
      lat: lat,
      lng: lng,
      cameraFrameB64: cameraFrameB64,
      routeId: routeId,
      destination: destination,
    ));
  }

  // ---------------------------------------------------------------------------
  // Convenience: Motion anomaly event
  // ---------------------------------------------------------------------------
  Future<AgentDecision?> notifyMotionAnomaly({
    required int userId,
    required UserAccessibilityMode userMode,
    required double lat,
    required double lng,
    required String pattern,    // sudden_stop | fall_detected | wandering
    double magnitude = 0.0,
    String? routeId,
  }) {
    return sendEvent(AgentEventPayload(
      eventType: AgentEventType.motionAnomaly,
      userId: userId,
      userMode: userMode,
      lat: lat,
      lng: lng,
      motionData: {'pattern': pattern, 'magnitude': magnitude},
      routeId: routeId,
    ));
  }

  // ---------------------------------------------------------------------------
  // Get agent session status
  // ---------------------------------------------------------------------------
  Future<Map<String, dynamic>?> getSessionStatus(int userId) async {
    try {
      final url = Uri.parse('${_api.baseUrl}/api/v1/agent/status/$userId');
      final response = await http.get(url, headers: _headers()).timeout(_timeout);
      if (response.statusCode == 200) {
        return jsonDecode(response.body) as Map<String, dynamic>;
      }
    } catch (e) {
      debugPrint('[AgentClient] getSessionStatus failed: $e');
    }
    return null;
  }

  // ---------------------------------------------------------------------------
  // Clear session (call when navigation ends)
  // ---------------------------------------------------------------------------
  Future<void> clearSession(int userId) async {
    try {
      final url = Uri.parse('${_api.baseUrl}/api/v1/agent/session/$userId');
      await http.delete(url, headers: _headers()).timeout(_timeout);
    } catch (e) {
      debugPrint('[AgentClient] clearSession failed: $e');
    }
  }

  Map<String, String> _headers() => {'Content-Type': 'application/json'};
}

// ---------------------------------------------------------------------------
// Singleton for easy access across the app
// ---------------------------------------------------------------------------
final agentClient = AgentClient();
