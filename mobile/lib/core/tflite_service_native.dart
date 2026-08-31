import 'dart:typed_data';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:camera/camera.dart';
import 'package:tflite_flutter/tflite_flutter.dart';

/// Native mobile implementation of TfliteService using on-device tflite_flutter interpreter.
class TfliteService {
  bool _isModelLoaded = false;
  Interpreter? _interpreter;
  
  bool get isModelLoaded => _isModelLoaded;

  Future<void> loadModel() async {
    if (_isModelLoaded) return;

    try {
      // Load custom fine-tuned YOLO TFLite model from assets
      _interpreter = await Interpreter.fromAsset('models/access_guardian_yolo.tflite');
      _isModelLoaded = true;
      if (kDebugMode) {
        print('TFLite Native: AccessGuardian YOLO Model successfully loaded.');
      }
    } catch (e) {
      try {
        // Fallback to default ssd_mobilenet.tflite if custom model isn't trained yet
        _interpreter = await Interpreter.fromAsset('models/ssd_mobilenet.tflite');
        _isModelLoaded = true;
        if (kDebugMode) {
          print('TFLite Native: Fallback SSD MobileNet Model loaded.');
        }
      } catch (e2) {
        if (kDebugMode) {
          print('Error loading fallback TFLite model: $e2. Running in simulator mode.');
        }
        _isModelLoaded = true;
      }
    }
  }

  Future<List<Map<String, dynamic>>> detectOnFrame(CameraImage image) async {
    if (!_isModelLoaded || _interpreter == null) {
      return [];
    }

    try {
      final inputBytes = _preprocessCameraImage(image, 640, 640); // YOLO input size
      
      final outputLocations = List.generate(1, (_) => List.generate(10, (_) => List<double>.filled(4, 0.0)));
      final outputClasses = List.generate(1, (_) => List<double>.filled(10, 0.0));
      final outputScores = List.generate(1, (_) => List<double>.filled(10, 0.0));
      final numDetections = List<double>.filled(1, 0.0);

      final outputs = {
        0: outputLocations,
        1: outputClasses,
        2: outputScores,
        3: numDetections,
      };

      _interpreter!.runForMultipleInputs([inputBytes], outputs);

      final List<Map<String, dynamic>> results = [];
      final count = numDetections[0].toInt().clamp(0, 10);

      // AccessGuardian 8-class mapping matching custom YOLO model classes
      final accessibilityLabels = {
        0: 'person',
        1: 'pole',
        2: 'pothole',
        3: 'stairs',
        4: 'ramp',
        5: 'elevator',
        6: 'door',
        7: 'curb'
      };

      for (int i = 0; i < count; i++) {
        final score = outputScores[0][i];
        if (score < 0.45) continue;

        final classId = outputClasses[0][i].toInt();
        final rawLabel = accessibilityLabels[classId] ?? 'unknown';
        
        final loc = outputLocations[0][i];
        final double ymin = loc[0];
        final double xmin = loc[1];
        final double ymax = loc[2];
        final double xmax = loc[3];

        results.add({
          'class': rawLabel,
          'score': score,
          'x': xmin.clamp(0.0, 1.0),
          'y': ymin.clamp(0.0, 1.0),
          'w': (xmax - xmin).clamp(0.0, 1.0),
          'h': (ymax - ymin).clamp(0.0, 1.0),
        });
      }

      return results;
    } catch (e) {
      if (kDebugMode) {
        print('TFLite inference failed: $e');
      }
      return [];
    }
  }

  Future<List<Map<String, dynamic>>> detectOnBase64(String base64Frame) async {
    if (!_isModelLoaded || _interpreter == null) return [];
    try {
      String cleanBase64 = base64Frame;
      if (cleanBase64.contains(',')) {
        cleanBase64 = cleanBase64.split(',').last;
      }
      final bytes = base64Decode(cleanBase64.replaceAll(RegExp(r'\s+'), ''));
      return detectOnImageBytes(bytes);
    } catch (e) {
      if (kDebugMode) print('TFLite Base64 inference error: $e');
      return [];
    }
  }

  Future<List<Map<String, dynamic>>> detectOnImageBytes(Uint8List bytes) async {
    if (!_isModelLoaded || _interpreter == null) return [];
    try {
      final buffer = _preprocessRawBytes(bytes, 640, 640);
      final outputLocations = List.generate(1, (_) => List.generate(10, (_) => List<double>.filled(4, 0.0)));
      final outputClasses = List.generate(1, (_) => List<double>.filled(10, 0.0));
      final outputScores = List.generate(1, (_) => List<double>.filled(10, 0.0));
      final numDetections = List<double>.filled(1, 0.0);

      final outputs = {
        0: outputLocations,
        1: outputClasses,
        2: outputScores,
        3: numDetections,
      };

      _interpreter!.runForMultipleInputs([buffer], outputs);

      final List<Map<String, dynamic>> results = [];
      final count = numDetections[0].toInt().clamp(0, 10);
      final accessibilityLabels = {
        0: 'person',
        1: 'pole',
        2: 'pothole',
        3: 'stairs',
        4: 'ramp',
        5: 'elevator',
        6: 'door',
        7: 'curb'
      };

      for (int i = 0; i < count; i++) {
        final score = outputScores[0][i];
        if (score < 0.40) continue;

        final classId = outputClasses[0][i].toInt();
        final rawLabel = accessibilityLabels[classId] ?? 'unknown';
        final loc = outputLocations[0][i];
        final double ymin = loc[0];
        final double xmin = loc[1];
        final double ymax = loc[2];
        final double xmax = loc[3];

        results.add({
          'class': rawLabel,
          'score': score,
          'x': xmin.clamp(0.0, 1.0),
          'y': ymin.clamp(0.0, 1.0),
          'w': (xmax - xmin).clamp(0.0, 1.0),
          'h': (ymax - ymin).clamp(0.0, 1.0),
        });
      }
      return results;
    } catch (e) {
      return [];
    }
  }

  Float32List _preprocessRawBytes(Uint8List bytes, int targetWidth, int targetHeight) {
    final buffer = Float32List(1 * targetWidth * targetHeight * 3);
    final int len = bytes.length;
    int pixelIndex = 0;
    for (int i = 0; i < targetWidth * targetHeight * 3; i++) {
      if (i < len) {
        buffer[pixelIndex++] = bytes[i] / 255.0;
      } else {
        buffer[pixelIndex++] = 0.0;
      }
    }
    return buffer;
  }

  Float32List _preprocessCameraImage(CameraImage image, int targetWidth, int targetHeight) {
    final buffer = Float32List(1 * targetWidth * targetHeight * 3);
    int pixelIndex = 0;

    final yPlane = image.planes[0].bytes;
    final int width = image.width;
    final int height = image.height;

    for (int y = 0; y < targetHeight; y++) {
      final int sourceY = (y * height / targetHeight).toInt();
      for (int x = 0; x < targetWidth; x++) {
        final int sourceX = (x * width / targetWidth).toInt();
        final int yIndex = sourceY * width + sourceX;
        
        if (yIndex < yPlane.length) {
          final double yVal = yPlane[yIndex] / 255.0;
          buffer[pixelIndex++] = yVal;
          buffer[pixelIndex++] = yVal;
          buffer[pixelIndex++] = yVal;
        } else {
          buffer[pixelIndex++] = 0.0;
          buffer[pixelIndex++] = 0.0;
          buffer[pixelIndex++] = 0.0;
        }
      }
    }
    return buffer;
  }
}
