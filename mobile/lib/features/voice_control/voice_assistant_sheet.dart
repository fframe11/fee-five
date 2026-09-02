import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/accessibility_notifier.dart';
import '../../core/api_client.dart';
import '../../core/tts_helper.dart';
import '../../core/voice_helper.dart';
import '../../core/services/haptic_service.dart';

class VoiceAssistantSheet extends ConsumerStatefulWidget {
  final Function(String destination)? onStartNavigation;
  final VoidCallback? onOpenCamera;
  final VoidCallback? onTriggerSos;
  final Function(bool enable)? onToggleVoice;

  const VoiceAssistantSheet({
    super.key,
    this.onStartNavigation,
    this.onOpenCamera,
    this.onTriggerSos,
    this.onToggleVoice,
  });

  static Future<void> show(
    BuildContext context, {
    Function(String destination)? onStartNavigation,
    VoidCallback? onOpenCamera,
    VoidCallback? onTriggerSos,
    Function(bool enable)? onToggleVoice,
  }) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => VoiceAssistantSheet(
        onStartNavigation: onStartNavigation,
        onOpenCamera: onOpenCamera,
        onTriggerSos: onTriggerSos,
        onToggleVoice: onToggleVoice,
      ),
    );
  }

  @override
  ConsumerState<VoiceAssistantSheet> createState() => _VoiceAssistantSheetState();
}

class _VoiceAssistantSheetState extends ConsumerState<VoiceAssistantSheet> with SingleTickerProviderStateMixin {
  late AnimationController _animController;
  late Animation<double> _pulseAnim;

  bool _isListening = false;
  bool _isProcessing = false;
  String _spokenText = '';
  String _aiStatusMessage = 'กำลังฟังคำสั่งของคุณ... พูดภาษาถิ่นหรือภาษาพูดได้เลยครับ';
  Timer? _silenceTimer;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    )..repeat(reverse: true);
    _pulseAnim = Tween<double>(begin: 1.0, end: 1.35).animate(
      CurvedAnimation(parent: _animController, curve: Curves.easeInOut),
    );

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _startVoiceInput();
    });
  }

  @override
  void dispose() {
    _silenceTimer?.cancel();
    _animController.dispose();
    stopSpeechCommand();
    super.dispose();
  }

  void _startVoiceInput() {
    final acc = ref.read(accessibilityProvider);
    HapticService().cameraToggle(opening: true);
    announceSpeech('กำลังฟังเสียง พูดได้เลยครับ', acc.voiceEnabled);

    setState(() {
      _isListening = true;
      _isProcessing = false;
      _spokenText = '';
      _aiStatusMessage = 'กำลังฟังคำสั่ง... พูดภาษาพูด/ภาษาถิ่นได้ตามสบายครับ';
    });

    try {
      listenSpeechCommand((text, isFinal) {
        if (!mounted) return;
        setState(() {
          _spokenText = text;
        });

        _silenceTimer?.cancel();
        if (isFinal && text.trim().isNotEmpty) {
          _processVoiceCommand(text.trim());
        } else if (text.trim().isNotEmpty) {
          _silenceTimer = Timer(const Duration(milliseconds: 1800), () {
            if (mounted && _isListening && _spokenText.trim().isNotEmpty) {
              _processVoiceCommand(_spokenText.trim());
            }
          });
        }
      });
    } catch (e) {
      setState(() {
        _isListening = false;
        _aiStatusMessage = 'ไม่สามารถเปิดระบบรับฟังเสียงได้: $e';
      });
    }
  }

  Future<void> _processVoiceCommand(String rawText) async {
    _silenceTimer?.cancel();
    stopSpeechCommand();

    setState(() {
      _isListening = false;
      _isProcessing = true;
      _aiStatusMessage = '🤖 AI กำลังทำความเข้าใจและทำหน้าที่เป็นนิ้วให้คุณ...';
    });

    HapticService().turnGuidance();

    try {
      final acc = ref.read(accessibilityProvider);
      final payload = {
        'event_type': 'voice_command',
        'voice_text': rawText,
        'user_id': 1,
        'user_mode': 'visual',
        'lat': 13.7461,
        'lng': 100.5348,
      };

      final res = await ApiClient().postAgentEvent(payload);
      final decision = res['decision']?.toString() ?? 'none';
      final actionArgs = (res['action_args'] as Map<String, dynamic>?) ?? {};
      final aiMessage = res['user_message']?.toString() ?? 'รับทราบครับ';

      setState(() {
        _isProcessing = false;
        _aiStatusMessage = aiMessage;
      });

      announceSpeech(aiMessage, acc.voiceEnabled);

      if (!mounted) return;
      await Future.delayed(const Duration(milliseconds: 600));

      if (decision == 'start_navigation') {
        Navigator.of(context).pop();
        final dest = actionArgs['destination']?.toString() ?? 'จุดหมาย';
        widget.onStartNavigation?.call(dest);
      } else if (decision == 'open_camera' || decision == 'suggest_camera_scan') {
        Navigator.of(context).pop();
        widget.onOpenCamera?.call();
      } else if (decision == 'trigger_sos') {
        Navigator.of(context).pop();
        widget.onTriggerSos?.call();
      } else if (decision == 'toggle_voice') {
        final mute = actionArgs['mute'] == true;
        widget.onToggleVoice?.call(!mute);
        await Future.delayed(const Duration(milliseconds: 1200));
        if (mounted) Navigator.of(context).pop();
      } else {
        await Future.delayed(const Duration(seconds: 2));
        if (mounted) Navigator.of(context).pop();
      }
    } catch (e) {
      setState(() {
        _isProcessing = false;
        _aiStatusMessage = 'เกิดข้อผิดพลาดในการประมวลผลคำสั่ง: $e';
      });
      announceSpeech('ขออภัยครับ ไม่สามารถประมวลผลคำสั่งได้ในขณะนี้', true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final acc = ref.watch(accessibilityProvider);
    final isHighContrast = acc.highContrast;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 32.0),
      decoration: BoxDecoration(
        color: isHighContrast ? Colors.black : const Color(0xFF0F172A),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
        border: Border.all(
          color: isHighContrast ? Colors.yellowAccent : const Color(0xFF38BDF8),
          width: 3,
        ),
        boxShadow: const [
          BoxShadow(
            color: Colors.black87,
            blurRadius: 20,
            spreadRadius: 5,
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              width: 50,
              height: 5,
              decoration: BoxDecoration(
                color: Colors.white38,
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: isHighContrast ? Colors.yellowAccent : const Color(0xFF0284C7),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.auto_awesome_rounded,
                  color: isHighContrast ? Colors.black : Colors.white,
                  size: 24,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'AI Digital Fingers (ผู้ช่วยเสียง)',
                      style: TextStyle(
                        fontSize: 18 * acc.fontScale,
                        fontWeight: FontWeight.bold,
                        color: isHighContrast ? Colors.yellowAccent : Colors.white,
                      ),
                    ),
                    Text(
                      'เข้าใจทุกภาษาถิ่นและภาษาพูด ไม่ต้องมองจอ',
                      style: TextStyle(
                        fontSize: 12 * acc.fontScale,
                        color: Colors.white70,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close_rounded, color: Colors.white, size: 28),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          ),
          const SizedBox(height: 28),
          Center(
            child: GestureDetector(
              onTap: () {
                if (_isListening) {
                  if (_spokenText.trim().isNotEmpty) {
                    _processVoiceCommand(_spokenText.trim());
                  } else {
                    stopSpeechCommand();
                    setState(() => _isListening = false);
                  }
                } else if (!_isProcessing) {
                  _startVoiceInput();
                }
              },
              child: AnimatedBuilder(
                animation: _animController,
                builder: (context, child) {
                  final scale = _isListening ? _pulseAnim.value : 1.0;
                  return Transform.scale(
                    scale: scale,
                    child: Container(
                      width: 110,
                      height: 110,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: _isProcessing
                            ? Colors.amber[700]
                            : (_isListening
                                ? (isHighContrast ? Colors.yellowAccent : const Color(0xFFE11D48))
                                : (isHighContrast ? Colors.grey[800] : const Color(0xFF0284C7))),
                        boxShadow: [
                          BoxShadow(
                            color: (_isListening ? Colors.redAccent : Colors.lightBlueAccent).withOpacity(0.4),
                            blurRadius: 18,
                            spreadRadius: 6,
                          ),
                        ],
                      ),
                      child: Icon(
                        _isProcessing
                            ? Icons.hourglass_top_rounded
                            : (_isListening ? Icons.mic_rounded : Icons.mic_none_rounded),
                        color: (_isListening && isHighContrast) ? Colors.black : Colors.white,
                        size: 52,
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
          const SizedBox(height: 24),
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: Colors.black45,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: isHighContrast ? Colors.white38 : const Color(0xFF334155),
                width: 1.5,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'สิ่งที่คุณพูด:',
                  style: TextStyle(
                    fontSize: 13 * acc.fontScale,
                    color: isHighContrast ? Colors.yellowAccent : const Color(0xFF38BDF8),
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  _spokenText.isNotEmpty ? '“$_spokenText”' : '(รอรับฟังเสียงของคุณ...)',
                  style: TextStyle(
                    fontSize: 18 * acc.fontScale,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Text(
            _aiStatusMessage,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 14 * acc.fontScale,
              color: isHighContrast ? Colors.yellowAccent : const Color(0xFFFDE047),
              height: 1.4,
            ),
          ),
          const SizedBox(height: 24),
          if (_spokenText.trim().isNotEmpty && !_isProcessing)
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: isHighContrast ? Colors.yellowAccent : const Color(0xFF10B981),
                foregroundColor: isHighContrast ? Colors.black : Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              ),
              onPressed: () => _processVoiceCommand(_spokenText.trim()),
              icon: const Icon(Icons.send_rounded, size: 24),
              label: Text(
                'ส่งคำสั่งนี้ให้ AI นิ้วดิจิทัล',
                style: TextStyle(fontSize: 16 * acc.fontScale, fontWeight: FontWeight.bold),
              ),
            ),
        ],
      ),
    );
  }
}
