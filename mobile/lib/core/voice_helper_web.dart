import 'dart:js' as js;

void startListeningCommand(void Function(String text, bool isFinal) onUpdate) {
  try {
    js.context['onVoiceCommandUpdate'] = (String text, bool isFinal) {
      onUpdate(text, isFinal);
    };

    js.context.callMethod('eval', [
      "if (!window.globalVoiceRecognition) {"
      "  var SpeechRecognition = window.SpeechRecognition || window.webkitSpeechRecognition;"
      "  if (SpeechRecognition) {"
      "    window.globalVoiceRecognition = new SpeechRecognition();"
      "    window.globalVoiceRecognition.lang = 'th-TH';"
      "    window.globalVoiceRecognition.interimResults = true;"
      "    window.globalVoiceRecognition.continuous = false;"
      "    window.globalVoiceRecognition.maxAlternatives = 1;"
      "    window.globalVoiceRecognition.onresult = function(event) {"
      "      var resultText = '';"
      "      var isFinal = false;"
      "      for (var i = event.resultIndex; i < event.results.length; ++i) {"
      "        resultText += event.results[i][0].transcript;"
      "        if (event.results[i].isFinal) isFinal = true;"
      "      }"
      "      if (window.onVoiceCommandUpdate) window.onVoiceCommandUpdate(resultText, isFinal);"
      "    };"
      "    window.globalVoiceRecognition.onerror = function(event) {"
      "      if (window.onVoiceCommandUpdate) window.onVoiceCommandUpdate('ERROR: ' + event.error, true);"
      "    };"
      "  }"
      "}"
      
      "window.startGlobalVoiceCommand = function() {"
      "  if (window.globalVoiceRecognition) {"
      "    try { window.globalVoiceRecognition.abort(); } catch(e) {}"
      "    setTimeout(function() {"
      "      try {"
      "        window.globalVoiceRecognition.start();"
      "      } catch(e) {"
      "        console.warn('Global voice start failed:', e);"
      "      }"
      "    }, 50);"
      "  } else {"
      "    if (window.onVoiceCommandUpdate) window.onVoiceCommandUpdate('ERROR: unsupported', true);"
      "  }"
      "};"
      
      "window.stopGlobalVoiceCommand = function() {"
      "  if (window.globalVoiceRecognition) {"
      "    try { window.globalVoiceRecognition.stop(); } catch(e) {}"
      "    try { window.globalVoiceRecognition.abort(); } catch(e) {}"
      "  }"
      "};"
    ]);

    js.context.callMethod('startGlobalVoiceCommand');
  } catch (e) {
    onUpdate('ERROR: $e', true);
  }
}

void stopListeningCommand() {
  try {
    js.context.callMethod('stopGlobalVoiceCommand');
  } catch (e) {
    // ignore
  }
}
