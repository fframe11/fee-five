import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_tts/flutter_tts.dart';

final FlutterTts _flutterTts = FlutterTts();
bool _isInitialized = false;
void Function()? _onSpeechFinished;

Future<void> _initTts() async {
  if (_isInitialized) return;
  try {
    await _flutterTts.setLanguage('th-TH');
    await _flutterTts.setSpeechRate(0.5);
    await _flutterTts.setVolume(1.0);
    await _flutterTts.setPitch(1.0);
    _flutterTts.setCompletionHandler(() {
      if (_onSpeechFinished != null) {
        _onSpeechFinished!();
      }
    });
    _isInitialized = true;
  } catch (e) {
    debugPrint('[TTS Native] Init error: $e');
  }
}

void speakText(String text) async {
  if (text.trim().isEmpty) return;
  
  final isScreenReader = ui.PlatformDispatcher.instance.accessibilityFeatures.accessibleNavigation;

  if (isScreenReader) {
    // TalkBack / VoiceOver is Active: ONLY announce through TalkBack queue (No duplicate TTS voice)
    try {
      SemanticsService.announce(text, TextDirection.ltr);
    } catch (_) {}
  } else {
    // TalkBack is OFF: Announce via Native Text-To-Speech engine
    await _initTts();
    try {
      await _flutterTts.stop();
      await _flutterTts.speak(text);
    } catch (e) {
      debugPrint('[TTS Native] Speak error: $e');
    }
  }
}

void setSpeechFinishedCallback(void Function() callback) {
  _onSpeechFinished = callback;
}
