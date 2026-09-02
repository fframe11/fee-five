import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/accessibility_notifier.dart';
import '../../core/tts_helper.dart';
import '../../core/services/haptic_service.dart';

import '../navigation/navigation_screen.dart';
import '../profile/profile_screen.dart';
import '../voice_control/voice_assistant_sheet.dart';

class TabItem {
  final int id; // 0: Home, 1: Voice Navigation, 2: Profile
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

  void _onTabTapped(int index, AccessibilityState acc) {
    HapticService().turnGuidance();
    setState(() {
      _currentIndex = index;
    });
  }

  void _openVoiceAssistant() {
    VoiceAssistantSheet.show(
      context,
      onStartNavigation: (destination) {
        setState(() {
          _currentIndex = 1;
        });
      },
      onOpenCamera: () {
        Navigator.of(context).pushNamed('/vision');
      },
      onTriggerSos: () {
        Navigator.of(context).pushNamed('/sos');
      },
      onToggleVoice: (enable) {
        ref.read(accessibilityProvider.notifier).toggleVoice(enable);
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final acc = ref.watch(accessibilityProvider);
    final isHighContrast = acc.highContrast;

    // ═══ TAM AI 3 Core Tabs (Home, Voice Navigation, Profile) ═══
    final List<TabItem> activeTabs = [
      TabItem(
        id: 0,
        icon: Icons.home_rounded,
        label: 'หน้าแรก',
        screen: _HomeTabContent(
          onNavigateTab: (targetId) {
            setState(() {
              _currentIndex = targetId.clamp(0, 2);
            });
          },
        ),
      ),
      TabItem(
        id: 1,
        icon: Icons.record_voice_over_rounded,
        label: 'นำทางเสียง',
        screen: const NavigationScreen(),
      ),
      TabItem(
        id: 2,
        icon: Icons.person_rounded,
        label: 'โปรไฟล์',
        screen: const ProfileScreen(),
      ),
    ];

    if (_currentIndex >= activeTabs.length) {
      _currentIndex = 0;
    }

    return Scaffold(
      body: activeTabs[_currentIndex].screen,
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
      floatingActionButton: Semantics(
        button: true,
        label: 'สั่งการด้วยเสียง AI นิ้วดิจิทัล แตะเพื่อพูดสั่งงาน',
        child: FloatingActionButton.extended(
          backgroundColor: isHighContrast ? Colors.yellowAccent : const Color(0xFF2563EB),
          foregroundColor: isHighContrast ? Colors.black : Colors.white,
          elevation: 8,
          onPressed: _openVoiceAssistant,
          icon: const Icon(Icons.mic_rounded, size: 28),
          label: Text(
            '🎙️ สั่งด้วยเสียง',
            style: TextStyle(
              fontSize: 15 * acc.fontScale,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        backgroundColor: isHighContrast ? Colors.black : Colors.white,
        selectedItemColor: isHighContrast ? Colors.yellowAccent : Theme.of(context).colorScheme.primary,
        unselectedItemColor: isHighContrast ? Colors.white60 : Colors.grey,
        selectedLabelStyle: TextStyle(fontSize: 14 * acc.fontScale, fontWeight: FontWeight.bold),
        unselectedLabelStyle: TextStyle(fontSize: 12 * acc.fontScale),
        type: BottomNavigationBarType.fixed,
        onTap: (index) => _onTabTapped(index, acc),
        items: activeTabs.map((tab) => BottomNavigationBarItem(
          icon: Icon(tab.icon, size: 28),
          label: tab.label,
        )).toList(),
      ),
    );
  }
}

/// ═══ Ultra-Minimal Action-First Home Tab Content (Only 3 Giant Main Buttons) ═══
class _HomeTabContent extends ConsumerStatefulWidget {
  final Function(int) onNavigateTab;

  const _HomeTabContent({required this.onNavigateTab});

  @override
  ConsumerState<_HomeTabContent> createState() => _HomeTabContentState();
}

class _HomeTabContentState extends ConsumerState<_HomeTabContent> {
  bool _isLoading = true;
  bool _isSosPressed = false;
  double _sosCountdown = 3.0;
  Timer? _sosTimer;

  @override
  void initState() {
    super.initState();
    Future.delayed(const Duration(milliseconds: 300), () {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    });
  }

  @override
  void dispose() {
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

  void _startSosCountdown(AccessibilityState acc) {
    HapticService().triggerSos();
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
          Navigator.of(context).pushNamed('/sos');
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
              'TAM AI (หน้าแรก)',
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
      backgroundColor: isHighContrast ? Colors.black : const Color(0xFFF1F5F9),
      body: SafeArea(
        child: AnimatedOpacity(
          opacity: _isLoading ? 0.3 : 1.0,
          duration: const Duration(milliseconds: 300),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18.0, vertical: 16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Clean Greeting Header
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Semantics(
                      header: true,
                      label: 'คำทักทาย: ${_getGreeting()}',
                      child: Text(
                        _getGreeting(),
                        style: TextStyle(
                          fontSize: 22 * acc.fontScale,
                          fontWeight: FontWeight.bold,
                          color: isHighContrast ? Colors.yellowAccent : const Color(0xFF0F172A),
                        ),
                      ),
                    ),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Image.asset(
                        'assets/icon_in_app.png',
                        width: 42,
                        height: 42,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => const Icon(Icons.accessibility_new_rounded, size: 32),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20.0),

                // ═══ 3 GIANT ACTION BUTTONS ONLY ═══

                // 1. Button 1 (Largest, Primary): "เริ่มนำทางด้วยเสียง"
                Expanded(
                  flex: 3,
                  child: Semantics(
                    button: true,
                    label: 'เริ่มนำทางด้วยเสียง แตะเพื่อเลือกจุดหมายและฟังเสียงบอกทาง',
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: isHighContrast ? Colors.yellowAccent : const Color(0xFF16A34A),
                        foregroundColor: isHighContrast ? Colors.black : Colors.white,
                        elevation: 6,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(24),
                          side: BorderSide(
                            color: isHighContrast ? Colors.black : Colors.white24,
                            width: 2,
                          ),
                        ),
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                      ),
                      onPressed: () {
                        HapticService().startNavigation();
                        announceSpeech('เปิดหน้านำทางด้วยเสียง', acc.voiceEnabled);
                        widget.onNavigateTab(1); // Switch to Voice Navigation Tab
                      },
                      child: Row(
                        children: [
                          CircleAvatar(
                            radius: 32,
                            backgroundColor: isHighContrast ? Colors.black12 : Colors.white24,
                            child: Icon(
                              Icons.record_voice_over_rounded,
                              size: 38,
                              color: isHighContrast ? Colors.black : Colors.white,
                            ),
                          ),
                          const SizedBox(width: 18),
                          Expanded(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '🚀 เริ่มนำทางด้วยเสียง',
                                  style: TextStyle(
                                    fontSize: 20 * acc.fontScale,
                                    fontWeight: FontWeight.bold,
                                    color: isHighContrast ? Colors.black : Colors.white,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'ค้นหาจุดหมายและฟังเสียงนำทาง',
                                  style: TextStyle(
                                    fontSize: 13 * acc.fontScale,
                                    color: isHighContrast ? Colors.black87 : Colors.white.withOpacity(0.9),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Icon(
                            Icons.arrow_forward_ios_rounded,
                            size: 22,
                            color: isHighContrast ? Colors.black54 : Colors.white70,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 16.0),

                // 2. Button 2 (Secondary): "เปิดกล้องตรวจสิ่งกีดขวาง"
                Expanded(
                  flex: 2,
                  child: Semantics(
                    button: true,
                    label: 'เปิดกล้องตรวจสิ่งกีดขวาง สแกนหาเสา หลุม ทางต่างระดับเฉพาะหน้า',
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: isHighContrast ? const Color(0xFF27272A) : const Color(0xFF0F766E),
                        foregroundColor: Colors.white,
                        elevation: 5,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(22),
                          side: BorderSide(
                            color: isHighContrast ? Colors.white : Colors.white24,
                            width: 2,
                          ),
                        ),
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                      ),
                      onPressed: () {
                        HapticService().cameraToggle(opening: true);
                        announceSpeech('เปิดกล้องตรวจจับสิ่งกีดขวาง', acc.voiceEnabled);
                        Navigator.of(context).pushNamed('/vision');
                      },
                      child: Row(
                        children: [
                          CircleAvatar(
                            radius: 28,
                            backgroundColor: Colors.white24,
                            child: const Icon(
                              Icons.camera_alt_rounded,
                              size: 32,
                              color: Colors.white,
                            ),
                          ),
                          const SizedBox(width: 18),
                          Expanded(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '📷 เปิดกล้องตรวจสิ่งกีดขวาง',
                                  style: TextStyle(
                                    fontSize: 18 * acc.fontScale,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white,
                                  ),
                                ),
                                const SizedBox(height: 3),
                                Text(
                                  'สแกนหาเสา หลุม ทางต่างระดับเฉพาะหน้า',
                                  style: TextStyle(
                                    fontSize: 12.5 * acc.fontScale,
                                    color: Colors.white70,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const Icon(
                            Icons.arrow_forward_ios_rounded,
                            size: 20,
                            color: Colors.white70,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 16.0),

                // 3. Button 3 (Emergency): "SOS ขอความช่วยเหลือ"
                Expanded(
                  flex: 2,
                  child: Semantics(
                    button: true,
                    label: 'ปุ่มกดค้างเพื่อส่งสัญญาณฉุกเฉิน SOS',
                    child: GestureDetector(
                      onTapDown: (_) => _startSosCountdown(acc),
                      onTapUp: (_) => _cancelSosCountdown(),
                      onTapCancel: () => _cancelSosCountdown(),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 14.0),
                        decoration: BoxDecoration(
                          color: _isSosPressed ? Colors.red[900] : const Color(0xFFDC2626),
                          borderRadius: BorderRadius.circular(22),
                          border: isHighContrast ? Border.all(color: Colors.white, width: 2.5) : null,
                          boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 6, offset: Offset(0, 3))],
                        ),
                        child: Row(
                          children: [
                            CircleAvatar(
                              radius: 28,
                              backgroundColor: Colors.white24,
                              child: const Icon(Icons.emergency_rounded, color: Colors.white, size: 34),
                            ),
                            const SizedBox(width: 18),
                            Expanded(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    '🆘 ขอความช่วยเหลือ (SOS)',
                                    style: TextStyle(
                                      fontSize: 18 * acc.fontScale,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.white,
                                    ),
                                  ),
                                  const SizedBox(height: 3),
                                  Text(
                                    _isSosPressed
                                        ? 'กำลังส่งใน ${_sosCountdown.toStringAsFixed(1)} วินาที'
                                        : 'แตะหรือกดค้างเพื่อแจ้งเหตุฉุกเฉินและพิกัดทันที',
                                    style: TextStyle(
                                      fontSize: 12.5 * acc.fontScale,
                                      color: Colors.white.withOpacity(0.9),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 10.0),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
