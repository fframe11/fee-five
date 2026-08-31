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

void sendUserLocationMessage({
  required double latitude,
  required double longitude,
  String label = '📍 ตำแหน่งปัจจุบันของคุณ',
}) {
  postSetUserLocation(
    latitude: latitude,
    longitude: longitude,
    label: label,
  );
}

void onMapDestinationSelected(void Function(String stopName) callback) {
  listenDestinationSelection(callback);
}

void toggleMapIframeClickable(bool clickable) {
  setMapIframeClickable(clickable);
}
