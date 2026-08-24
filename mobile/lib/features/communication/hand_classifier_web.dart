import 'dart:js' as js;

String? getHandShape() {
  try {
    final landmarks = js.context['currentHandLandmarks'];
    if (landmarks != null) {
      final shape = js.context.callMethod('classifyHandShape', [landmarks]);
      return shape?.toString();
    }
  } catch (_) {}
  return null;
}
