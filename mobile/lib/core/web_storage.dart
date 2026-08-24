import 'web_storage_stub.dart'
    if (dart.library.html) 'web_storage_web.dart';

void updateWebPreference(String key, String value) {
  saveWebPreference(key, value);
}
