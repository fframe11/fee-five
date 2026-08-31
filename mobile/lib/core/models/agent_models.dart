/// Fee Five — Agent Data Models
/// Mirrors the backend AgentEvent / AgentResponse schemas.

enum AgentEventType {
  gpsBarrier('gps_barrier'),
  voiceCommand('voice_command'),
  pushEvent('push_event'),
  cameraScan('camera_scan'),
  motionAnomaly('motion_anomaly');

  final String value;
  const AgentEventType(this.value);
}

enum AgentUrgency { low, medium, high, critical }

enum UserAccessibilityMode {
  wheelchair('wheelchair'),
  visual('visual'),
  hearing('hearing');

  final String value;
  const UserAccessibilityMode(this.value);
}

// ---------------------------------------------------------------------------
// Outgoing: Event payload sent to backend
// ---------------------------------------------------------------------------
class AgentEventPayload {
  final AgentEventType eventType;
  final int userId;
  final UserAccessibilityMode userMode;
  final double lat;
  final double lng;

  // Optional per event type
  final Map<String, dynamic>? barrierInfo;
  final String? voiceText;
  final Map<String, dynamic>? pushPayload;
  final String? cameraFrameB64;   // only when camera is open
  final Map<String, dynamic>? motionData;

  // Navigation context
  final String? routeId;
  final String? destination;

  const AgentEventPayload({
    required this.eventType,
    required this.userId,
    required this.userMode,
    required this.lat,
    required this.lng,
    this.barrierInfo,
    this.voiceText,
    this.pushPayload,
    this.cameraFrameB64,
    this.motionData,
    this.routeId,
    this.destination,
  });

  Map<String, dynamic> toJson() => {
    'event_type': eventType.value,
    'user_id': userId,
    'user_mode': userMode.value,
    'lat': lat,
    'lng': lng,
    if (barrierInfo != null) 'barrier_info': barrierInfo,
    if (voiceText != null) 'voice_text': voiceText,
    if (pushPayload != null) 'push_payload': pushPayload,
    if (cameraFrameB64 != null) 'camera_frame_b64': cameraFrameB64,
    if (motionData != null) 'motion_data': motionData,
    if (routeId != null) 'route_id': routeId,
    if (destination != null) 'destination': destination,
  };
}

// ---------------------------------------------------------------------------
// Incoming: Agent decision from backend
// ---------------------------------------------------------------------------
class AgentDecision {
  final String decision;      // tool name or 'none'
  final double confidence;
  final String thought;
  final String userMessage;   // Thai string for TTS / display
  final Map<String, dynamic> toolResult;
  final String eventType;
  final AgentUrgency urgency;
  final String userMode;
  final String timestamp;

  const AgentDecision({
    required this.decision,
    required this.confidence,
    required this.thought,
    required this.userMessage,
    required this.toolResult,
    required this.eventType,
    required this.urgency,
    required this.userMode,
    required this.timestamp,
  });

  factory AgentDecision.fromJson(Map<String, dynamic> json) {
    final urgencyStr = json['urgency'] as String? ?? 'low';
    final urgency = AgentUrgency.values.firstWhere(
      (e) => e.name == urgencyStr,
      orElse: () => AgentUrgency.low,
    );
    return AgentDecision(
      decision: json['decision'] as String? ?? 'none',
      confidence: (json['confidence'] as num?)?.toDouble() ?? 0.0,
      thought: json['thought'] as String? ?? '',
      userMessage: json['user_message'] as String? ?? '',
      toolResult: json['tool_result'] as Map<String, dynamic>? ?? {},
      eventType: json['event_type'] as String? ?? '',
      urgency: urgency,
      userMode: json['user_mode'] as String? ?? '',
      timestamp: json['timestamp'] as String? ?? '',
    );
  }

  /// Convenience: Is this decision asking the mobile to reroute?
  bool get isReroute => decision == 'reroute_navigation';

  /// Convenience: Is this an SOS trigger?
  bool get isSOS => decision == 'trigger_sos';

  /// Convenience: Should we show a camera scan suggestion?
  bool get isCameraSuggestion => decision == 'suggest_camera_scan';

  /// Convenience: Is audio output needed?
  bool get needsAudio =>
      toolResult['alert']?['modality']?['audio'] == true ||
      toolResult['instruction']?['audio'] == true;

  /// Convenience: Is haptic needed?
  bool get needsHaptic =>
      toolResult['alert']?['modality']?['haptic'] == true ||
      toolResult['instruction']?['haptic'] == true;

  /// Returns the Thai alert message for TTS / display
  String get alertMessage {
    if (userMessage.isNotEmpty) return userMessage;
    final alert = toolResult['alert'];
    if (alert != null) return alert['message'] as String? ?? '';
    final instruction = toolResult['instruction'];
    if (instruction != null) return instruction['text'] as String? ?? '';
    return '';
  }

  @override
  String toString() =>
      'AgentDecision(decision=$decision, urgency=$urgency, message=$alertMessage)';
}
