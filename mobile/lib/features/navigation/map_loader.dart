import 'map_loader_stub.dart'
    if (dart.library.html) 'map_loader_web.dart';

void registerMapIframe() {
  registerView();
}

void sendDrawRouteMessage({
  required String startNode,
  required String endNode,
  required bool wheelchairMode,
  required bool avoidBrokenElevator,
}) {
  postDrawRoute(
    startNode: startNode,
    endNode: endNode,
    wheelchairMode: wheelchairMode,
    avoidBrokenElevator: avoidBrokenElevator,
  );
}

void toggleMapIframeClickable(bool clickable) {
  setMapIframeClickable(clickable);
}
