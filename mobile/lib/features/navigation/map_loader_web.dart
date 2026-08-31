import 'dart:html' as html;
import 'dart:ui_web' as ui_web;
import 'dart:js' as js;

void registerView() {
  ui_web.platformViewRegistry.registerViewFactory(
    'map-iframe',
    (int viewId) {
      final isHc = html.window.localStorage['high_contrast'] == 'true';
      final isDark = html.window.localStorage['theme'] == 'dark' || isHc;
      
      final hcParam = isHc ? 'hc=true' : 'hc=false';
      final themeParam = isDark ? 'theme=dark' : 'theme=light';
      
      return html.IFrameElement()
        ..src = 'map.html?$hcParam&$themeParam'
        ..style.border = 'none'
        ..style.width = '100%'
        ..style.height = '100%'
        ..style.pointerEvents = 'auto'; // Allows dragging, panning, zooming, and clicking markers
    },
  );
}

void postDrawRoute({
  required String startNode,
  required String endNode,
  required bool wheelchairMode,
  required bool avoidBrokenElevator,
}) {
  js.context.callMethod('eval', [
    "var iframes = document.getElementsByTagName('iframe');"
    "for (var i = 0; i < iframes.length; i++) {"
    "  if (iframes[i].src.indexOf('map.html') !== -1) {"
    "    iframes[i].contentWindow.postMessage({"
    "      type: 'DRAW_ROUTE',"
    "      startNode: '$startNode',"
    "      endNode: '$endNode',"
    "      wheelchairMode: $wheelchairMode,"
    "      avoidBrokenElevator: $avoidBrokenElevator"
    "    }, '*');"
    "  }"
    "}"
  ]);
}

void postSetUserLocation({
  required double latitude,
  required double longitude,
  String label = '📍 ตำแหน่งปัจจุบันของคุณ',
}) {
  js.context.callMethod('eval', [
    "var iframes = document.getElementsByTagName('iframe');"
    "for (var i = 0; i < iframes.length; i++) {"
    "  if (iframes[i].src.indexOf('map.html') !== -1) {"
    "    iframes[i].contentWindow.postMessage({"
    "      type: 'SET_USER_LOCATION',"
    "      latitude: $latitude,"
    "      longitude: $longitude,"
    "      label: '$label'"
    "    }, '*');"
    "  }"
    "}"
  ]);
}

void listenDestinationSelection(void Function(String stopName) callback) {
  html.window.onMessage.listen((event) {
    try {
      final data = event.data;
      if (data is Map && data['type'] == 'SELECT_DESTINATION') {
        final stopName = data['stop_name'] as String?;
        if (stopName != null) {
          callback(stopName);
        }
      }
    } catch (_) {}
  });
}

void setMapIframeClickable(bool clickable) {
  try {
    js.context.callMethod('eval', [
      "var iframes = document.getElementsByTagName('iframe');"
      "for (var i = 0; i < iframes.length; i++) {"
      "  if (iframes[i].src.indexOf('map.html') !== -1) {"
      "    iframes[i].style.pointerEvents = '${clickable ? 'auto' : 'none'}';"
      "  }"
      "}"
    ]);
  } catch (e) {
    // Ignore error
  }
}
