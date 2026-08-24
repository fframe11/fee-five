import 'tts_helper_stub.dart'
    if (dart.library.html) 'tts_helper_web.dart';

void announceSpeech(String text, bool voiceEnabled) {
  if (voiceEnabled) {
    speakText(text);
  }
}

void registerSpeechFinishedCallback(void Function() callback) {
  setSpeechFinishedCallback(callback);
}
