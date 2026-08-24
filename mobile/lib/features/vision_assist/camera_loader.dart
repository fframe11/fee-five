import 'camera_loader_stub.dart'
    if (dart.library.html) 'camera_loader_web.dart';

void registerWebcamView() {
  registerWebcam();
}

String? captureFrame() {
  return getCapturedFrame();
}

double captureProximity() {
  return getProximityValue();
}

String captureObstacles() {
  return getDetectedObstacles();
}

void setSosGestureCallback(void Function() callback) {
  registerSosGestureCallback(callback);
}

void setSignGestureCallback(void Function(String gesture) callback) {
  registerSignGestureCallback(callback);
}

void triggerStartSpeech() {
  startLiveSpeech();
}

void triggerStopSpeech() {
  stopLiveSpeech();
}

void setSpeechCallbacks({
  required void Function(String finalTranscript, String interimTranscript) onResult,
  required void Function(String error) onError,
  required void Function() onEnd,
}) {
  registerSpeechCallbacks(onResult: onResult, onError: onError, onEnd: onEnd);
}
