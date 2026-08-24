import 'dart:html' as html;

void saveWebPreference(String key, String value) {
  try {
    html.window.localStorage[key] = value;
  } catch (e) {
    // Ignore iframe localStorage security errors
  }
}
