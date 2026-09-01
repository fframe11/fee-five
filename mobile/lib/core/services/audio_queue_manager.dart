import 'dart:async';
import 'package:flutter/foundation.dart';
import '../../core/tts_helper.dart';
import '../../core/services/haptic_service.dart';

enum AudioPriority {
  status,           // Lowest (e.g. GPS Uncertain)
  turnInstruction,  // General navigation
  riskWarning,      // Upcoming hazard warning
  obstacleAlert,    // YOLO11 detection
  emergency         // Highest priority (immediate stop)
}

class AudioMessage {
  final String text;
  final AudioPriority priority;
  final bool withHaptic;
  
  AudioMessage({
    required this.text,
    required this.priority,
    this.withHaptic = false,
  });
}

class AudioQueueManager {
  static final AudioQueueManager _instance = AudioQueueManager._internal();
  factory AudioQueueManager() => _instance;
  AudioQueueManager._internal();

  final List<AudioMessage> _queue = [];
  bool _isPlaying = false;
  AudioMessage? _currentMessage;

  void speak(String text, AudioPriority priority, {bool withHaptic = false}) {
    final message = AudioMessage(text: text, priority: priority, withHaptic: withHaptic);
    
    if (_isPlaying && _currentMessage != null) {
      if (message.priority.index > _currentMessage!.priority.index) {
        // TTSHelper.stop();
        _isPlaying = false;
        _playMessage(message);
        return;
      }
    }

    _queue.add(message);
    _queue.sort((a, b) => b.priority.index.compareTo(a.priority.index));
    _processQueue();
  }

  void _playMessage(AudioMessage message) {
    _queue.insert(0, message);
    _processQueue();
  }

  Future<void> _processQueue() async {
    if (_isPlaying || _queue.isEmpty) return;

    _isPlaying = true;
    _currentMessage = _queue.removeAt(0);

    if (_currentMessage!.withHaptic) {
      if (_currentMessage!.priority == AudioPriority.emergency || _currentMessage!.priority == AudioPriority.obstacleAlert) {
        HapticService().enterRisk(); 
      }
    }

    announceSpeech(_currentMessage!.text, true);
    
    await Future.delayed(Duration(milliseconds: 500 + (_currentMessage!.text.length * 50)));

    _isPlaying = false;
    _currentMessage = null;
    _processQueue();
  }
  
  void stop() {
    _queue.clear();
    // TTSHelper.stop();
    _isPlaying = false;
    _currentMessage = null;
  }
}
