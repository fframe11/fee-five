import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../core/accessibility_notifier.dart';
import '../../core/voice_helper.dart';
import '../../core/tts_helper.dart';

import '../navigation/navigation_screen.dart';
import '../vision_assist/vision_assist_screen.dart';
import '../gesture_sos/gesture_sos_screen.dart';
import '../profile/profile_screen.dart';

class TabItem {
  final int id; // 0: Home, 1: Camera, 2: Navigation, 3: SOS, 4: Profile
  final IconData icon;
  final String label;
  final Widget screen;

  TabItem({
    required this.id,
    required this.icon,
    required this.label,
    required this.screen,
  });
}

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  int _currentIndex = 0;
  bool _isLiveVoiceActive = false;
  String _liveRecognizedText = "";
  bool _isLiveSpeaking = false;

  @override
  void initState() {
    super.initState();
    registerSpeechFinishedCallback(() {
      if (!mounted) return;
      setState(() {
        _isLiveSpeaking = false;
        _liveRecognizedText = "";
      });
      if (_isLiveVoiceActive) {
        Future.delayed(const Duration(milliseconds: 400), () {
          if (_isLiveVoiceActive && mounted) {
            _startLiveVoiceRecognition();
          }
        });
      }
    });
  }

  void _startLiveVoiceRecognition() {
    if (!mounted || _isLiveSpeaking) return;

    setState(() {
      _liveRecognizedText = "กำลังรับฟัง...";
    });

    listenSpeechCommand((text, isFinal) {
      if (!mounted || !_isLiveVoiceActive || _isLiveSpeaking) return;

      final cleanText = text.trim();
      if (cleanText.isEmpty) return;

      setState(() {
        if (cleanText.startsWith("ERROR:")) {
          _liveRecognizedText = "กรุณาเปิดสิทธิ์ไมโครโฟนบนเบราว์เซอร์ของคุณ";
          _isLiveVoiceActive = false;
        } else {
          _liveRecognizedText = cleanText;
        }
      });

      if (cleanText.startsWith("ERROR:")) return;

      // Instant Matcher on Interim Outputs
      final command = cleanText.toLowerCase();
      int? targetIndex;
      String speakMsg = "";
      bool isCancelCommand = false;

      if (command.contains("ยกเลิก") || command.contains("หยุด") || command.contains("ปิด")) {
        isCancelCommand = true;
        speakMsg = "ยกเลิกและปิดระบบรับคำสั่งเสียงเรียบร้อยครับ";
      } else if (command.contains("รถเมล์") || command.contains("bts") || command.contains("บีทีเอส") || command.contains("mrt") || command.contains("เอ็มอาร์ที") || command.contains("รถไฟฟ้า") || command.contains("ขนส่งสาธารณะ") || command.contains("รถประจำทาง")) {
        targetIndex = 2;
        speakMsg = "เปิดระบบนำทางด้วยขนส่งสาธารณะ ระบบจะเลือกค้นหาป้ายและสถานีที่ใกล้ที่สุดให้ครับ";
      } else if (command.contains("แท็กซี่") || command.contains("แกร็บ") || command.contains("grab") || command.contains("taxi")) {
        targetIndex = 2;
        speakMsg = "เปิดระบบเรียกรถแท็กซี่และแกร็บสำหรับผู้พิการครับ";
      } else if (command.contains("กล้อง") || command.contains("สแกน") || command.contains("ตรวจจับ") || command.contains("สิ่งกีดขวาง")) {
        targetIndex = 1;
        speakMsg = "เปิดหน้ากล้อง AI ตรวจจับสิ่งกีดขวางแล้วครับ";
      } else if (command.contains("นำทาง") || command.contains("แผนที่") || command.contains("ไป") || command.contains("เส้นทาง")) {
        targetIndex = 2;
        speakMsg = "เปิดหน้านำทางด้วยเสียงแล้วครับ ต้องการเดินทางไปที่ไหนดีครับ?";
      } else if (command.contains("ช่วยเหลือ") || command.contains("เอสโอเอส") || command.contains("ฉุกเฉิน") || command.contains("sos") || command.contains("แจ้งเหตุ")) {
        targetIndex = 3;
        speakMsg = "เปิดหน้าขอความช่วยเหลือฉุกเฉินแล้วครับ";
      } else if (command.contains("โปรไฟล์") || command.contains("ตั้งค่า") || command.contains("ข้อมูล")) {
        targetIndex = 4;
        speakMsg = "เปิดหน้าโปรไฟล์และการตั้งค่าครับ";
      } else if (command.contains("หน้าแรก") || command.contains("แรก") || command.contains("หลัก")) {
        targetIndex = 0;
        speakMsg = "กลับสู่หน้าแรกแล้วครับ";
      }

      if (targetIndex != null || isCancelCommand) {
        setState(() {
          _isLiveSpeaking = true; // Silence mic input while speaking
          if (isCancelCommand) {
            _isLiveVoiceActive = false;
            _liveRecognizedText = "ปิดระบบเสียงแล้ว";
          } else {
            _currentIndex = targetIndex!;
            _liveRecognizedText = "คำสั่ง: $cleanText";
          }
        });

        final acc = ref.read(accessibilityProvider);
        announceSpeech(speakMsg, acc.voiceEnabled);
      } else if (isFinal) {
        // Speech ended without any matched keyword - request retry
        setState(() {
          _isLiveSpeaking = true;
          _liveRecognizedText = "ไม่เข้าใจ: $cleanText";
        });
        final acc = ref.read(accessibilityProvider);
        announceSpeech("ไม่เข้าใจคำสั่งเสียงที่พูดว่า $cleanText กรุณาลองพูดใหม่อีกครั้งครับ", acc.voiceEnabled);
      }
    });
  }

  void _toggleLiveVoiceMode() {
    final acc = ref.read(accessibilityProvider);
    _triggerHaptic(acc);
    setState(() {
      _isLiveVoiceActive = !_isLiveVoiceActive;
      if (_isLiveVoiceActive) {
        _isLiveSpeaking = false;
        _liveRecognizedText = "กำลังรับฟัง...";
        _startLiveVoiceRecognition();
        announceSpeech("เปิดระบบรับคำสั่งเสียงแบบไลฟ์ พูดสั่งการได้เลยครับ", acc.voiceEnabled);
      } else {
        _liveRecognizedText = "";
        stopSpeechCommand(); // Turn off SpeechRecognition safely
        announceSpeech("ปิดระบบรับคำสั่งเสียงแล้วครับ", acc.voiceEnabled);
      }
    });
  }

  void _triggerHaptic(AccessibilityState state) {
    if (state.hapticEnabled) {
      HapticFeedback.lightImpact();
    }
  }

  void _onTabTapped(int index, AccessibilityState acc) {
    _triggerHaptic(acc);
    setState(() {
      _currentIndex = index;
    });
  }

  @override
  Widget build(BuildContext context) {
    final acc = ref.watch(accessibilityProvider);
    final isHighContrast = acc.highContrast;
    final themeColor = isHighContrast ? Colors.black : Theme.of(context).colorScheme.primary;

    // Fixed 5 active tabs specifically designed for blind users
    final List<TabItem> activeTabs = [
      TabItem(
        id: 0,
        icon: Icons.home,
        label: 'หน้าแรก',
        screen: _HomeTabContent(
          onNavigateTab: (targetId) {
            setState(() {
              _currentIndex = targetId.clamp(0, 4);
            });
          },
        ),
      ),
      TabItem(
        id: 1,
        icon: Icons.camera_alt_rounded,
        label: 'กล้อง AI',
        screen: const VisionAssistScreen(),
      ),
      TabItem(
        id: 2,
        icon: Icons.navigation_rounded,
        label: 'นำทางเสียง',
        screen: const NavigationScreen(),
      ),
      TabItem(
        id: 3,
        icon: Icons.emergency_rounded,
        label: 'ฉุกเฉิน SOS',
        screen: const GestureSosScreen(),
      ),
      TabItem(
        id: 4,
        icon: Icons.person_rounded,
        label: 'โปรไฟล์',
        screen: const ProfileScreen(),
      ),
    ];

    if (_currentIndex >= activeTabs.length) {
      _currentIndex = 0;
    }

    return Scaffold(
      body: Stack(
        children: [
          activeTabs[_currentIndex].screen,
          
          // Live Voice Assistant Status Bar Overlay (Pulsing side-by-side card)
          if (_isLiveVoiceActive)
            Positioned(
              left: 16,
              right: 84,
              bottom: kBottomNavigationBarHeight + 16,
              child: Card(
                color: isHighContrast ? Colors.black : Theme.of(context).colorScheme.primary,
                elevation: 8,
                shape: RoundedRectangleBorder(
                  side: isHighContrast ? const BorderSide(color: Colors.white, width: 2) : BorderSide.none,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  child: Row(
                    children: [
                      Icon(
                        _isLiveSpeaking ? Icons.volume_up : Icons.mic,
                        color: _isLiveSpeaking ? Colors.orangeAccent : Colors.cyanAccent,
                        size: 24,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _liveRecognizedText,
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 14 * acc.fontScale,
                            fontWeight: FontWeight.bold,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

          // Persistent Floating Mic Button Overlay (accessible across all screens)
          Positioned(
            right: 16,
            bottom: kBottomNavigationBarHeight + 16,
            child: Semantics(
              button: true,
              label: _isLiveVoiceActive ? 'ปิดระบบสั่งการด้วยเสียง' : 'เปิดระบบสั่งการด้วยเสียงแบบไลฟ์',
              hint: 'แตะสองครั้งเพื่อสลับโหมดเปิดปิดระบบช่วยคำสั่งเสียงและเสียงอ่านประกาศภาษาไทย',
              child: FloatingActionButton(
                heroTag: 'global_voice_command_fab',
                onPressed: _toggleLiveVoiceMode,
                backgroundColor: _isLiveVoiceActive 
                    ? Colors.red 
                    : (isHighContrast ? Colors.white : Theme.of(context).colorScheme.primary),
                foregroundColor: _isLiveVoiceActive 
                    ? Colors.white 
                    : (isHighContrast ? Colors.black : Colors.white),
                child: Icon(
                  _isLiveVoiceActive ? Icons.mic_off : Icons.mic, 
                  size: 28,
                ),
              ),
            ),
          ),
        ],
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        backgroundColor: isHighContrast ? Colors.black : Colors.white,
        selectedItemColor: isHighContrast ? Colors.white : Theme.of(context).colorScheme.primary,
        unselectedItemColor: Colors.grey,
        type: BottomNavigationBarType.fixed,
        onTap: (index) => _onTabTapped(index, acc),
        items: activeTabs.map((tab) => BottomNavigationBarItem(
          icon: Icon(tab.icon),
          label: tab.label,
        )).toList(),
      ),
    );
  }
}

class _HomeTabContent extends ConsumerStatefulWidget {
  final Function(int) onNavigateTab;

  const _HomeTabContent({required this.onNavigateTab});

  @override
  ConsumerState<_HomeTabContent> createState() => _HomeTabContentState();
}

class _HomeTabContentState extends ConsumerState<_HomeTabContent> {
  bool _isLoading = true;
  Timer? _alertTimer;
  int _currentAlertIndex = 0;
  bool _isSosPressed = false;
  double _sosCountdown = 3.0;
  Timer? _sosTimer;

  final List<Map<String, String>> _alerts = [
    {
      'title': 'แจ้งเตือนลิฟต์เสีย',
      'detail': 'สถานีรถไฟฟ้า BTS สยาม ลิฟต์ทางออก 3 ปิดปรับปรุง'
    },
    {
      'title': 'สิ่งกีดขวางบนทางเท้า',
      'detail': 'พบการก่อสร้างกีดขวางทางเท้าบริเวณถนนสุขุมวิท ซอย 21'
    },
    {
      'title': 'สัญญาณไฟจราจรขัดข้อง',
      'detail': 'แยกอโศกมนตรี สัญญาณไฟจราจรคนข้ามมีปัญหา โปรดระมัดระวัง'
    },
  ];

  @override
  void initState() {
    super.initState();
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    });

    _alertTimer = Timer.periodic(const Duration(seconds: 5), (timer) {
      if (mounted) {
        setState(() {
          _currentAlertIndex = (_currentAlertIndex + 1) % _alerts.length;
        });
      }
    });
  }

  @override
  void dispose() {
    stopSpeechCommand(); // Turn off SpeechRecognition cleanly when leaving home screen
    _alertTimer?.cancel();
    _sosTimer?.cancel();
    super.dispose();
  }

  String _getGreeting() {
    final hour = DateTime.now().hour;
    if (hour < 12) {
      return 'สวัสดีตอนเช้า';
    } else if (hour < 17) {
      return 'สวัสดีตอนบ่าย';
    } else {
      return 'สวัสดีตอนเย็น';
    }
  }

  void _triggerHaptic(AccessibilityState state) {
    if (state.hapticEnabled) {
      HapticFeedback.lightImpact();
    }
  }

  void _startSosCountdown(AccessibilityState acc) {
    if (acc.hapticEnabled) HapticFeedback.heavyImpact();
    setState(() {
      _isSosPressed = true;
      _sosCountdown = 3.0;
    });

    _sosTimer = Timer.periodic(const Duration(milliseconds: 100), (timer) {
      setState(() {
        _sosCountdown -= 0.1;
        if (_sosCountdown <= 0) {
          timer.cancel();
          _isSosPressed = false;
          _sosCountdown = 3.0;
          widget.onNavigateTab(3); // Navigate to SOS Tab
        }
      });
    });
  }

  void _cancelSosCountdown() {
    _sosTimer?.cancel();
    setState(() {
      _isSosPressed = false;
      _sosCountdown = 3.0;
    });
  }


  @override
  Widget build(BuildContext context) {
    final acc = ref.watch(accessibilityProvider);
    final isHighContrast = acc.highContrast;
    final themeColor = isHighContrast ? Colors.black : Theme.of(context).colorScheme.primary;

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.asset(
                'assets/icon_in_app.png',
                width: 32,
                height: 32,
                errorBuilder: (_, __, ___) => const Icon(Icons.accessibility_new_rounded, size: 28),
              ),
            ),
            const SizedBox(width: 10),
            Text(
              'หน้าแรก (TAM)',
              style: TextStyle(
                fontSize: 20 * acc.fontScale,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        backgroundColor: themeColor,
        foregroundColor: Colors.white,
      ),
      backgroundColor: isHighContrast ? Colors.black : Colors.grey[100],
      body: SafeArea(
        child: AnimatedOpacity(
          opacity: _isLoading ? 0.3 : 1.0,
          duration: const Duration(milliseconds: 500),
          child: SingleChildScrollView(
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Greeting Header with In-App Icon
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Semantics(
                        label: 'คำทักทาย',
                        child: Text(
                          _getGreeting(),
                          style: TextStyle(
                            fontSize: 24 * acc.fontScale,
                            fontWeight: FontWeight.bold,
                            color: isHighContrast ? Colors.white : Colors.black87,
                          ),
                        ),
                      ),
                    ),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Image.asset(
                        'assets/icon_in_app.png',
                        width: 44,
                        height: 44,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => const Icon(Icons.accessibility_new_rounded, size: 36),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16.0),

                // Dynamic Alert Banner
                Semantics(
                  label: 'การแจ้งเตือนปัจจุบัน: ${_alerts[_currentAlertIndex]['title']}',
                  child: Container(
                    padding: const EdgeInsets.all(16.0),
                    decoration: BoxDecoration(
                      color: isHighContrast ? Colors.black : Colors.orange[50],
                      border: Border.all(
                        color: isHighContrast ? Colors.white : Colors.orange,
                        width: 2,
                      ),
                      borderRadius: BorderRadius.circular(12.0),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.warning_amber_rounded, color: Colors.orange, size: 28),
                            const SizedBox(width: 8.0),
                            Expanded(
                              child: Text(
                                _alerts[_currentAlertIndex]['title']!,
                                style: TextStyle(
                                  fontSize: 18 * acc.fontScale,
                                  fontWeight: FontWeight.bold,
                                  color: isHighContrast ? Colors.white : Colors.orange[900],
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8.0),
                        Text(
                          _alerts[_currentAlertIndex]['detail']!,
                          style: TextStyle(
                            fontSize: 16 * acc.fontScale,
                            color: isHighContrast ? Colors.white70 : Colors.black87,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 20.0),

                // Dynamic Content based on Accessibility Mode
                _buildDynamicBody(context, acc, ref),
                const SizedBox(height: 8.0),

                // SOS Warning trigger shortcut
                Semantics(
                  label: 'ปุ่มกดค้างเพื่อส่งสัญญาณฉุกเฉิน (SOS)',
                  button: true,
                  child: GestureDetector(
                    onTapDown: (_) => _startSosCountdown(acc),
                    onTapUp: (_) => _cancelSosCountdown(),
                    onTapCancel: () => _cancelSosCountdown(),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 100),
                      padding: const EdgeInsets.symmetric(vertical: 18.0),
                      decoration: BoxDecoration(
                        color: _isSosPressed ? Colors.red[900] : Colors.red[700],
                        borderRadius: BorderRadius.circular(16.0),
                        border: isHighContrast ? Border.all(color: Colors.white, width: 2) : null,
                        boxShadow: isHighContrast ? [] : [
                          BoxShadow(
                            color: Colors.red.withOpacity(0.3),
                            blurRadius: 10,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Column(
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(Icons.emergency_rounded, color: Colors.white, size: 24),
                              const SizedBox(width: 8),
                              Text(
                                'กดค้างเพื่อส่งสัญญาณฉุกเฉิน (SOS)',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: 17 * acc.fontScale,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                ),
                              ),
                            ],
                          ),
                          if (_isSosPressed)
                            Padding(
                              padding: const EdgeInsets.only(top: 8.0),
                              child: Text(
                                'กำลังส่งใน ${_sosCountdown.toStringAsFixed(1)} วินาที',
                                style: TextStyle(
                                  fontSize: 16 * acc.fontScale,
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 32.0),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDirectoryItem({
    required IconData icon,
    required String title,
    required String description,
    required Color color,
    required VoidCallback onTap,
    required AccessibilityState acc,
    required bool isHighContrast,
  }) {
    return Semantics(
      button: true,
      label: "$title. $description",
      child: Card(
        margin: const EdgeInsets.only(bottom: 16.0),
        color: isHighContrast ? Colors.black : Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16.0),
          side: BorderSide(
            color: isHighContrast ? Colors.white : color,
            width: isHighContrast ? 2.5 : 1.5,
          ),
        ),
        elevation: isHighContrast ? 0 : 2,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16.0),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 18.0),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 28,
                  backgroundColor: isHighContrast ? Colors.white12 : color.withOpacity(0.1),
                  child: Icon(
                    icon,
                    size: 32,
                    color: isHighContrast ? Colors.white : color,
                  ),
                ),
                const SizedBox(width: 18.0),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          fontSize: 18 * acc.fontScale,
                          fontWeight: FontWeight.bold,
                          color: isHighContrast ? Colors.white : Colors.black87,
                        ),
                      ),
                      const SizedBox(height: 6.0),
                      Text(
                        description,
                        style: TextStyle(
                          fontSize: 13 * acc.fontScale,
                          color: isHighContrast ? Colors.white70 : Colors.grey[600],
                          height: 1.3,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  Icons.arrow_forward_ios_rounded,
                  color: isHighContrast ? Colors.white54 : Colors.grey[400],
                  size: 20,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDynamicBody(BuildContext context, AccessibilityState acc, WidgetRef ref) {
    final isHighContrast = acc.highContrast;
    final primary = Theme.of(context).colorScheme.primary;
    final secondary = Theme.of(context).colorScheme.secondary;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildDirectoryItem(
          icon: Icons.camera_alt_rounded,
          title: 'กล้อง AI ตรวจจับสิ่งกีดขวาง',
          description: 'สแกนตรวจจับเสา พื้นต่างระดับ และสิ่งกีดขวาง พร้อมเสียงเตือนและระบบสั่นแบบเรียลไทม์',
          color: primary,
          onTap: () {
            _triggerHaptic(acc);
            widget.onNavigateTab(1); // Tab 1: Vision Camera
          },
          acc: acc,
          isHighContrast: isHighContrast,
        ),
        _buildDirectoryItem(
          icon: Icons.navigation_rounded,
          title: 'ระบบนำทางด้วยเสียง (Voice Nav)',
          description: 'ค้นหาเส้นทาง นำทางแบบ Turn-by-Turn เลี่ยงสิ่งกีดขวางตามแนวทางเดินเบรลล์',
          color: secondary,
          onTap: () {
            _triggerHaptic(acc);
            widget.onNavigateTab(2); // Tab 2: Navigation
          },
          acc: acc,
          isHighContrast: isHighContrast,
        ),
      ],
    );
  }
}

