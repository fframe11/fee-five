void registerWebcam() {
  // Stub implementation for VM/Mobile
}

String? getCapturedFrame() {
  return null;
}

double getProximityValue() {
  return 0.0;
}

String getDetectedObstacles() {
  return "[]";
}

void registerSosGestureCallback(void Function() callback) {
  // Stub
}

void registerSignGestureCallback(void Function(String gesture) callback) {
  // Stub
}

void startLiveSpeech() {
  // Stub
}

void stopLiveSpeech() {
  // Stub
}

void registerSpeechCallbacks({
  required void Function(String finalTranscript, String interimTranscript) onResult,
  required void Function(String error) onError,
  required void Function() onEnd,
}) {
  // Stub
}
