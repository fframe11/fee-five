import 'dart:js' as js;

void speakText(String text) {
  try {
    js.context.callMethod('eval', [
      "if ('speechSynthesis' in window) {"
      "  var utterance = new SpeechSynthesisUtterance('${text.replaceAll("'", "\\'")}');"
      "  utterance.lang = 'th-TH';"
      "  window.speechSynthesis.cancel();"
      "  window.speechSynthesis.speak(utterance);"
      "}"
    ]);
  } catch (e) {
    // Ignore error
  }
}
