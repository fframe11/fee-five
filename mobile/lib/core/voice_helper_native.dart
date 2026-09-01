import 'package:flutter/foundation.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:permission_handler/permission_handler.dart';

final stt.SpeechToText _speech = stt.SpeechToText();
bool _isSpeechInitialized = false;

Future<void> startListeningCommand(void Function(String text, bool isFinal) onUpdate) async {
  try {
    final micStatus = await Permission.microphone.request();
    if (micStatus.isDenied || micStatus.isPermanentlyDenied) {
      onUpdate('ERROR: ไม่ได้รับอนุญาตให้ใช้ไมโครโฟน', true);
      return;
    }

    if (!_isSpeechInitialized) {
      _isSpeechInitialized = await _speech.initialize(
        onError: (err) => debugPrint('[STT Native] Error: ${err.errorMsg}'),
        onStatus: (status) => debugPrint('[STT Native] Status: $status'),
      );
    }

    if (_isSpeechInitialized) {
      _speech.listen(
        onResult: (result) {
          onUpdate(result.recognizedWords, result.finalResult);
        },
        localeId: 'th_TH',
        listenMode: stt.ListenMode.confirmation,
      );
    } else {
      onUpdate('ERROR: ไม่สามารถเริ่มต้นระบบเสียง', true);
    }
  } catch (e) {
    debugPrint('[STT Native] Exception: $e');
    onUpdate('ERROR: $e', true);
  }
}

void stopListeningCommand() {
  try {
    if (_speech.isListening) {
      _speech.stop();
    }
  } catch (_) {}
}
