import 'voice_helper_stub.dart'
    if (dart.library.html) 'voice_helper_web.dart';

void listenSpeechCommand(void Function(String text, bool isFinal) onUpdate) {
  startListeningCommand(onUpdate);
}

void stopSpeechCommand() {
  stopListeningCommand();
}
