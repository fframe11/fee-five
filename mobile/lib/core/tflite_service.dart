/// Core export file for TfliteService.
/// Dynamically exports the web-compatible implementation for browser builds,
/// and the hardware-accelerated native implementation for mobile device builds.
export 'tflite_service_web.dart'
  if (dart.library.io) 'tflite_service_native.dart';
