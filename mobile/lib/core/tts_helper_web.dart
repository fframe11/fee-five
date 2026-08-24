import 'dart:js' as js;

void speakText(String text) {
  try {
    js.context.callMethod('eval', [
      "if ('speechSynthesis' in window) {"
      "  var utterance = new SpeechSynthesisUtterance('${text.replaceAll("'", "\\'")}');"
      "  utterance.lang = 'th-TH';"
      "  utterance.pitch = 0.75;" // Lower pitch to sound like a male voice
      "  var voices = window.speechSynthesis.getVoices();"
      "  var thVoice = voices.find(function(v) { return v.lang.startsWith('th'); });"
      "  if (thVoice) utterance.voice = thVoice;"
      "  utterance.onend = function() {"
      "    if (window.onSpeechFinished) window.onSpeechFinished();"
      "  };"
      "  window.speechSynthesis.cancel();"
      "  window.speechSynthesis.speak(utterance);"
      "}"
    ]);
  } catch (e) {
    // Ignore error
  }
}

void setSpeechFinishedCallback(void Function() callback) {
  js.context['onSpeechFinished'] = () {
    callback();
  };
}
