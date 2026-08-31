import 'dart:convert';
import 'package:camera/camera.dart';
import '../features/vision_assist/camera_loader.dart';

/// Web-compatible implementation of TfliteService.
/// Bridges on-device browser COCO-SSD and MediaPipe vision engines.
class TfliteService {
  bool get isModelLoaded => true;

  Future<void> loadModel() async {
    // Web loads COCO-SSD / MediaPipe automatically in browser
  }

  Future<List<Map<String, dynamic>>> detectOnFrame(CameraImage image) async {
    return _fetchWebDetections();
  }

  Future<List<Map<String, dynamic>>> detectOnBase64(String base64Frame) async {
    return _fetchWebDetections();
  }

  List<Map<String, dynamic>> _fetchWebDetections() {
    try {
      final jsonStr = captureObstacles();
      if (jsonStr.isNotEmpty && jsonStr != '[]') {
        final List<dynamic> decoded = jsonDecode(jsonStr);
        return decoded.map((e) => Map<String, dynamic>.from(e)).toList();
      }
    } catch (_) {}
    return [];
  }
}
