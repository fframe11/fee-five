import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/accessibility_notifier.dart';
import '../../core/api_client.dart';
import '../../core/tts_helper.dart';
import '../vision_assist/camera_loader.dart';
import 'hand_classifier.dart';

class CommunicationScreen extends ConsumerStatefulWidget {
  const CommunicationScreen({super.key});

  @override
  ConsumerState<CommunicationScreen> createState() => _CommunicationScreenState();
}

class _CommunicationScreenState extends ConsumerState<CommunicationScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  
  // 1. Sign Language variables
  String _currentGesture = "NONE";
  String _translatedText = "ไม่พบท่าทางภาษามือ";
  Timer? _signDebounceTimer;
  Timer? _gesturePollingTimer;
  
  // SOS fallback countdown variables
  bool _isSosCountdown = false;
  int _sosCountdownSeconds = 3;
  Timer? _sosTimer;
  String _sosStatusText = "";

  // 2. Speech to Text variables
  bool _isListening = false;
  String _interimTranscription = "";
  final List<String> _transcriptions = [
    "สวัสดีครับ ยินดีต้อนรับ",
    "ช่วยกรุณาชี้ทางไปลิฟต์โดยสารรถไฟฟ้า BTS ให้หน่อยได้ไหมครับ",
  ];
  final TextEditingController _mockSpeechController = TextEditingController();
  
  // 3. Text to Speech variables
  final TextEditingController _ttsInputController = TextEditingController();
  double _speechRate = 1.0;
  bool _isLiveTtsEnabled = false;
  String _lastSpokenText = "";
  Timer? _liveTtsTimer;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    
    // Bind real-time gesture callback (JS → Dart bridge)
    setSignGestureCallback((String gesture) {
      if (!mounted) return;
      if (_tabController.index == 0) {
        _handleGestureDetected(gesture);
      }
    });

    // Polling fallback: poll JS classifyHandShape every 300ms for live detection
    _gesturePollingTimer = Timer.periodic(const Duration(milliseconds: 300), (_) {
      if (!mounted || _tabController.index != 0) return;
      final shape = pollHandShape();
      if (shape != null) {
        _handleGestureDetected(shape);
      } else {
        _handleGestureDetected('NONE');
      }
    });

    // Bind real-time Speech Recognition callbacks (JS -> Dart Web Speech API)
    setSpeechCallbacks(
      onResult: (finalT, interimT) {
        if (!mounted) return;
        setState(() {
          _interimTranscription = interimT;
          if (finalT.isNotEmpty) {
            // Check if this final phrase is already in the list to prevent duplicates
            if (_transcriptions.isEmpty || _transcriptions.last != finalT) {
              _transcriptions.add(finalT);
              _interimTranscription = "";
            }
          }
        });
      },
      onError: (err) {
        if (!mounted) return;
        setState(() {
          _interimTranscription = "🚨 เกิดข้อผิดพลาด: $err";
        });
      },
      onEnd: () {
        if (!mounted) return;
        setState(() {
          _isListening = false;
        });
      },
    );

    // Bind live typing TTS listener
    _ttsInputController.addListener(_onTtsTextChanged);
  }

  void _onTtsTextChanged() {
    if (!_isLiveTtsEnabled) return;
    
    final text = _ttsInputController.text;
    if (text.isEmpty) {
      _lastSpokenText = "";
      return;
    }

    _liveTtsTimer?.cancel();
    _liveTtsTimer = Timer(const Duration(milliseconds: 800), () {
      if (!mounted || !_isLiveTtsEnabled) return;
      
      final currentText = _ttsInputController.text.trim();
      if (currentText.isEmpty || currentText == _lastSpokenText) return;
      
      String textToSpeak = currentText;
      if (currentText.startsWith(_lastSpokenText) && _lastSpokenText.isNotEmpty) {
        textToSpeak = currentText.substring(_lastSpokenText.length).trim();
      }
      
      if (textToSpeak.isNotEmpty) {
        announceSpeech(textToSpeak, true);
        _lastSpokenText = currentText;
      }
    });
  }

  @override
  void dispose() {
    triggerStopSpeech(); // Cleanly cancel speech recognition when leaving the page
    _tabController.dispose();
    _signDebounceTimer?.cancel();
    _gesturePollingTimer?.cancel();
    _sosTimer?.cancel();
    _liveTtsTimer?.cancel();
    _mockSpeechController.dispose();
    _ttsInputController.dispose();
    super.dispose();
  }

  void _handleGestureDetected(String gesture) {
    if (_isSosCountdown) return;
    
    if (gesture == _currentGesture) return;
    
    setState(() {
      _currentGesture = gesture;
    });

    String translation = "ไม่พบท่าทางภาษามือ";
    if (gesture == "PALM_OPEN") {
      translation = "สวัสดี ✋";
    } else if (gesture == "FIST") {
      translation = "ขอบคุณ ✊";
    } else if (gesture == "POINTING") {
      translation = "ขอทางหน่อย ☝️";
    } else if (gesture == "THUMB_FOLDED") {
      // Trigger traditional SOS countdown
      _triggerSosCountdown();
      return;
    }

    setState(() {
      _translatedText = translation;
    });

    if (gesture != "NONE" && gesture != "UNKNOWN") {
      // Auto-announce gesture translation
      _signDebounceTimer?.cancel();
      _signDebounceTimer = Timer(const Duration(milliseconds: 600), () {
        final acc = ref.read(accessibilityProvider);
        announceSpeech(translation.replaceAll(RegExp(r'[^\u0E00-\u0E7F]'), ''), acc.voiceEnabled);
      });
    }
  }

  void _triggerSosCountdown() {
    if (_isSosCountdown) return;
    
    final acc = ref.read(accessibilityProvider);
    HapticFeedback.vibrate();
    SemanticsService.announce("ตรวจพบสัญญาณมือฉุกเฉิน กำลังนับถอยหลัง 3 วินาทีเพื่อติดต่อฉุกเฉิน", TextDirection.ltr);
    announceSpeech("ตรวจพบสัญญาณมือฉุกเฉิน กำลังส่งสัญญาณขอความช่วยเหลือ", acc.voiceEnabled);

    setState(() {
      _isSosCountdown = true;
      _sosCountdownSeconds = 3;
      _sosStatusText = "🚨 ตรวจพบสัญญาณฉุกเฉิน! ขอความช่วยเหลือใน 3...";
    });

    _sosTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) return;
      setState(() {
        if (_sosCountdownSeconds > 1) {
          _sosCountdownSeconds--;
          _sosStatusText = "🚨 ตรวจพบสัญญาณฉุกเฉิน! ขอความช่วยเหลือใน $_sosCountdownSeconds...";
          SemanticsService.announce("นับถอยหลัง $_sosCountdownSeconds", TextDirection.ltr);
        } else {
          timer.cancel();
          _sosStatusText = "🔔 ส่งสัญญาณฉุกเฉินเรียบร้อยแล้ว!";
          _sendEmergencyAlert();
        }
      });
    });
  }

  void _sendEmergencyAlert() {
    final acc = ref.read(accessibilityProvider);
    ApiClient().triggerEmergencyAlert(
      13.7461, 100.5348,
      "สัญญาณฉุกเฉินภาษามือ (Sign Language SOS Alert)",
    ).then((res) {
      if (mounted) {
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text("🚨 ส่งสัญญาณช่วยเหลือด่วนแล้ว"),
            content: const Text("ระบบได้แจ้งพิกัดของคุณให้ผู้ดูแลระบบ เจ้าหน้าที่รักษาความปลอดภัย และผู้ติดต่อฉุกเฉินของคุณเรียบร้อยแล้ว กรุณารอ ณ จุดเดิม"),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.pop(ctx);
                  setState(() {
                    _isSosCountdown = false;
                    _currentGesture = "NONE";
                    _translatedText = "ไม่พบท่าทางภาษามือ";
                  });
                },
                child: const Text("ตกลง"),
              ),
            ],
          ),
        );
      }
    });
  }

  void _announceCurrentTranslation() {
    if (_currentGesture == "NONE" || _currentGesture == "UNKNOWN") return;
    final acc = ref.read(accessibilityProvider);
    String speechText = _translatedText.replaceAll(RegExp(r'[^\u0E00-\u0E7F]'), '');
    announceSpeech(speechText, acc.voiceEnabled);
  }

  // Speech to Text logic
  void _toggleListening() {
    setState(() {
      _isListening = !_isListening;
    });

    if (_isListening) {
      _interimTranscription = "กำลังรอรับเสียงพูด...";
      triggerStartSpeech();
    } else {
      triggerStopSpeech();
      setState(() {
        _interimTranscription = "";
      });
    }
  }

  void _sendMockSpeech() {
    if (_mockSpeechController.text.trim().isEmpty) return;
    setState(() {
      _transcriptions.add(_mockSpeechController.text.trim());
      _mockSpeechController.clear();
    });
  }

  // Text to Speech logic
  void _speakText(String text) {
    if (text.trim().isEmpty) return;
    announceSpeech(text, true); // Always speak out loud for TTS features
  }

  @override
  Widget build(BuildContext context) {
    final acc = ref.watch(accessibilityProvider);
    final isHighContrast = acc.highContrast;
    
    return Scaffold(
      appBar: AppBar(
        title: Text(
          "การสื่อสารช่วยเหลือ",
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: isHighContrast ? Colors.white : Colors.blue[900],
          ),
        ),
        backgroundColor: isHighContrast ? Colors.black : Colors.white,
        elevation: 0,
        bottom: TabBar(
          controller: _tabController,
          labelColor: isHighContrast ? Colors.yellow : Colors.blue[800],
          unselectedLabelColor: isHighContrast ? Colors.white60 : Colors.grey[600],
          indicatorColor: isHighContrast ? Colors.yellow : Colors.blue[800],
          indicatorWeight: 3,
          tabs: const [
            Tab(icon: Icon(Icons.gesture_rounded), text: "แปลภาษามือ"),
            Tab(icon: Icon(Icons.mic_rounded), text: "เสียงเป็นข้อความ"),
            Tab(icon: Icon(Icons.volume_up_rounded), text: "พิมพ์ออกเสียง"),
          ],
        ),
      ),
      body: Container(
        color: isHighContrast ? Colors.black : Colors.grey[50],
        child: TabBarView(
          controller: _tabController,
          children: [
            // Tab 1: Sign Language translation camera
            _buildSignLanguageTab(isHighContrast, acc),
            
            // Tab 2: Speech to Text translation log
            _buildSpeechToTextTab(isHighContrast, acc),
            
            // Tab 3: Text to Speech type and sound player
            _buildTextToSpeechTab(isHighContrast, acc),
          ],
        ),
      ),
    );
  }

  Widget _buildSignLanguageTab(bool isHighContrast, AccessibilityState acc) {
    return Column(
      children: [
        // Camera stream view
        Expanded(
          flex: 3,
          child: Container(
            margin: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.black,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: isHighContrast ? Colors.white : Colors.blue[800]!,
                width: 3,
              ),
            ),
            clipBehavior: Clip.antiAlias,
            child: const HtmlElementView(viewType: 'webcam-view'),
          ),
        ),
        
        // Translation info card
        Expanded(
          flex: 2,
          child: Container(
            width: double.infinity,
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: isHighContrast ? Colors.black : Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: isHighContrast ? Border.all(color: Colors.white, width: 2) : null,
              boxShadow: isHighContrast ? [] : [
                BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, 4)),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "🟢 ระบบตรวจจับแปลภาษามือสด (Live Gestures)",
                  style: TextStyle(
                    fontSize: 13 * acc.fontScale,
                    fontWeight: FontWeight.bold,
                    color: isHighContrast ? Colors.white70 : Colors.blue[800],
                  ),
                ),
                const SizedBox(height: 12),
                
                // Translated text output
                Expanded(
                  child: Center(
                    child: _isSosCountdown
                        ? Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                _sosStatusText,
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: 18 * acc.fontScale,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.red[800],
                                ),
                              ),
                              const SizedBox(height: 8),
                              ElevatedButton.icon(
                                onPressed: () {
                                  _sosTimer?.cancel();
                                  setState(() {
                                    _isSosCountdown = false;
                                    _currentGesture = "NONE";
                                    _translatedText = "ไม่พบท่าทางภาษามือ";
                                  });
                                },
                                icon: const Icon(Icons.cancel_rounded),
                                label: const Text("ยกเลิกแจ้งภัย"),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.red[800],
                                  foregroundColor: Colors.white,
                                ),
                              )
                            ],
                          )
                        : Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                _translatedText,
                                style: TextStyle(
                                  fontSize: 24 * acc.fontScale,
                                  fontWeight: FontWeight.bold,
                                  color: isHighContrast ? Colors.white : Colors.black87,
                                ),
                              ),
                              if (_currentGesture != "NONE" && _currentGesture != "UNKNOWN") ...[
                                const SizedBox(width: 12),
                                IconButton(
                                  icon: const Icon(Icons.volume_up_rounded, size: 32),
                                  color: isHighContrast ? Colors.yellow : Colors.blue[800],
                                  onPressed: _announceCurrentTranslation,
                                ),
                              ]
                            ],
                          ),
                  ),
                ),
                
                // Visual gestures legend bar
                const Divider(),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _buildLegendChip("สวัสดี ✋", isHighContrast),
                    _buildLegendChip("ขอบคุณ ✊", isHighContrast),
                    _buildLegendChip("ขอทางหน่อย ☝️", isHighContrast),
                    _buildLegendChip("SOS 🚨", isHighContrast, isAlert: true),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildLegendChip(String text, bool isHighContrast, {bool isAlert = false}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: isAlert 
            ? Colors.red[100] 
            : (isHighContrast ? Colors.white12 : Colors.blue[50]),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: isAlert 
              ? Colors.red[800]! 
              : (isHighContrast ? Colors.white30 : Colors.blue[200]!),
        ),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.bold,
          color: isAlert 
              ? Colors.red[800] 
              : (isHighContrast ? Colors.white : Colors.blue[800]),
        ),
      ),
    );
  }

  Widget _buildSpeechToTextTab(bool isHighContrast, AccessibilityState acc) {
    return Column(
      children: [
        // Transcription Chat Feed
        Expanded(
          child: Container(
            margin: const EdgeInsets.all(16),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: isHighContrast ? Colors.black : Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: isHighContrast ? Border.all(color: Colors.white, width: 2) : null,
              boxShadow: isHighContrast ? [] : [
                BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, 4)),
              ],
            ),
            child: Column(
              children: [
                Expanded(
                  child: ListView.builder(
                    itemCount: _transcriptions.length,
                    itemBuilder: (ctx, idx) {
                      final isSelf = idx % 2 == 0; // Alternating simulated layout
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Align(
                          alignment: isSelf ? Alignment.centerLeft : Alignment.centerRight,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                            decoration: BoxDecoration(
                              color: isSelf 
                                  ? (isHighContrast ? Colors.white24 : Colors.grey[200])
                                  : (isHighContrast ? Colors.yellow[800] : Colors.blue[800]),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Flexible(
                                  child: Text(
                                    _transcriptions[idx],
                                    style: TextStyle(
                                      color: isSelf 
                                          ? (isHighContrast ? Colors.white : Colors.black87)
                                          : Colors.white,
                                      fontSize: 14 * acc.fontScale,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                IconButton(
                                  padding: EdgeInsets.zero,
                                  constraints: const BoxConstraints(),
                                  icon: const Icon(Icons.volume_up_rounded, size: 18),
                                  color: isSelf 
                                      ? (isHighContrast ? Colors.white : Colors.grey[700])
                                      : Colors.white,
                                  onPressed: () => _speakText(_transcriptions[idx]),
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
                if (_isListening && _interimTranscription.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 8.0),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        decoration: BoxDecoration(
                          color: isHighContrast ? Colors.white12 : Colors.grey[100],
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: isHighContrast ? Colors.yellow : Colors.blue[600]!,
                            width: 1,
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            SizedBox(
                              width: 12,
                              height: 12,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor: AlwaysStoppedAnimation<Color>(
                                  isHighContrast ? Colors.yellow : Colors.blue[800]!,
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Flexible(
                              child: Text(
                                _interimTranscription,
                                style: TextStyle(
                                  color: isHighContrast ? Colors.yellow : Colors.blue[800],
                                  fontSize: 14 * acc.fontScale,
                                  fontStyle: FontStyle.italic,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
        
        // Mock keyboard typing log helper
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _mockSpeechController,
                  decoration: const InputDecoration(
                    hintText: "จำลองเสียงพูด (จำลองเพื่อทดสอบ)...",
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              IconButton.filled(
                icon: const Icon(Icons.send_rounded),
                onPressed: _sendMockSpeech,
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),

        // Floating record microphone control
        Container(
          margin: const EdgeInsets.only(bottom: 24),
          child: Column(
            children: [
              GestureDetector(
                onTap: _toggleListening,
                child: CircleAvatar(
                  radius: 36,
                  backgroundColor: _isListening 
                      ? Colors.red[800] 
                      : (isHighContrast ? Colors.white24 : Colors.blue[800]),
                  child: Icon(
                    _isListening ? Icons.stop_rounded : Icons.mic_rounded,
                    color: Colors.white,
                    size: 36,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                _isListening ? "กำลังรับเสียงอยู่... กดหยุดเพื่อส่งข้อความ" : "กดไมโครโฟนเพื่อพูดรับเสียง",
                style: TextStyle(
                  fontSize: 12 * acc.fontScale,
                  fontWeight: FontWeight.bold,
                  color: isHighContrast ? Colors.white70 : Colors.grey[700],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildTextToSpeechTab(bool isHighContrast, AccessibilityState acc) {
    final List<String> ttsShortcuts = [
      "สวัสดีครับ",
      "ขอบคุณครับ",
      "ขอทางผ่านให้คนพิการหน่อยครับ",
      "ช่วยเขียนลงบนกระดาษได้ไหมครับ",
      "มีทางลาดรถเข็นแถวนี้ไหมครับ",
    ];

    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            "ช่องพิมพ์เขียนข้อความเพื่อพูดออกเสียงแทนคุณ",
            style: TextStyle(
              fontSize: 13 * acc.fontScale,
              fontWeight: FontWeight.bold,
              color: isHighContrast ? Colors.white70 : Colors.grey[700],
            ),
          ),
          const SizedBox(height: 12),
          
          // Primary text input
          Expanded(
            child: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: isHighContrast ? Colors.black : Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: isHighContrast ? Colors.white : Colors.grey[300]!,
                  width: 2,
                ),
              ),
              child: TextField(
                controller: _ttsInputController,
                maxLines: null,
                style: TextStyle(
                  fontSize: 16 * acc.fontScale,
                  color: isHighContrast ? Colors.white : Colors.black87,
                ),
                decoration: const InputDecoration(
                  hintText: "พิมพ์คำหรือประโยคที่นี่เพื่อให้ระบบเปล่งเสียงพูด...",
                  border: InputBorder.none,
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          
          // Live speak-as-you-type toggle
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                "🔊 พูดออกเสียงอัตโนมัติขณะพิมพ์ (Live Auto-Speak)",
                style: TextStyle(
                  fontSize: 12 * acc.fontScale,
                  fontWeight: FontWeight.bold,
                  color: isHighContrast ? Colors.white70 : Colors.grey[700],
                ),
              ),
              Switch(
                value: _isLiveTtsEnabled,
                activeColor: isHighContrast ? Colors.yellow : Colors.blue[800],
                onChanged: (val) {
                  setState(() {
                    _isLiveTtsEnabled = val;
                    if (val) {
                      _lastSpokenText = _ttsInputController.text.trim();
                    }
                  });
                },
              ),
            ],
          ),
          const SizedBox(height: 12),
          
          // Preset chips shortcuts
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: ttsShortcuts.map((text) {
              return ActionChip(
                label: Text(text),
                backgroundColor: isHighContrast ? Colors.white12 : Colors.blue[50],
                labelStyle: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 11 * acc.fontScale,
                  color: isHighContrast ? Colors.yellow : Colors.blue[800],
                ),
                onPressed: () {
                  _ttsInputController.text = text;
                },
              );
            }).toList(),
          ),
          const SizedBox(height: 16),
          
          // Speed rate controls slider
          Row(
            children: [
              Icon(Icons.speed_rounded, color: isHighContrast ? Colors.white : Colors.grey[700]),
              const SizedBox(width: 8),
              Text(
                "ความเร็วเสียงพูด: ${_speechRate.toStringAsFixed(1)}x",
                style: TextStyle(
                  fontSize: 12 * acc.fontScale,
                  fontWeight: FontWeight.bold,
                  color: isHighContrast ? Colors.white70 : Colors.grey[700],
                ),
              ),
              Expanded(
                child: Slider(
                  value: _speechRate,
                  min: 0.5,
                  max: 2.0,
                  divisions: 6,
                  activeColor: isHighContrast ? Colors.yellow : Colors.blue[800],
                  inactiveColor: isHighContrast ? Colors.white24 : Colors.grey[300],
                  onChanged: (val) {
                    setState(() {
                      _speechRate = val;
                    });
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          
          // Trigger button
          SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton.icon(
              icon: const Icon(Icons.volume_up_rounded, size: 28),
              label: Text(
                "🔊 พูดข้อความนี้ออกเสียงด่วน",
                style: TextStyle(fontSize: 16 * acc.fontScale, fontWeight: FontWeight.bold),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: isHighContrast ? Colors.yellow : Colors.blue[800],
                foregroundColor: isHighContrast ? Colors.black : Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              onPressed: () {
                _speakText(_ttsInputController.text);
              },
            ),
          ),
        ],
      ),
    );
  }
}
