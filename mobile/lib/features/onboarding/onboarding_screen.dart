import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/accessibility_notifier.dart';
import '../../core/tts_helper.dart';

class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  final PageController _pageController = PageController();
  int _currentPage = 0;

  final List<OnboardingSlideData> _slides = [
    OnboardingSlideData(
      icon: Icons.remove_red_eye_rounded,
      title: "กล้องตรวจสิ่งกีดขวาง AI",
      description: "วิเคราะห์ภาพและส่งเสียงเตือนสิ่งกีดขวางบนพื้นแบบเรียลไทม์",
      color: const Color(0xFF0D47A1), // Colors.blue[900]
    ),
    OnboardingSlideData(
      icon: Icons.accessible_rounded,
      title: "แผนที่นำทางวีลแชร์",
      description: "ค้นหาลิฟต์ ทางลาด และเลี่ยงอุปสรรคเพื่ออำนวยความสะดวก",
      color: const Color(0xFF00695C), // Colors.teal[800]
    ),
    OnboardingSlideData(
      icon: Icons.gesture_rounded,
      title: "แจ้งเหตุฉุกเฉิน SOS ด่วน",
      description: "ส่งตำแหน่ง SOS ให้คนสนิททันทีด้วยการโบกมือผ่านกล้องหน้า",
      color: const Color(0xFF6A1B9A), // Colors.purple[800]
    ),
  ];

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _onPageChanged(int index) {
    HapticFeedback.lightImpact();
    setState(() {
      _currentPage = index;
    });
    final acc = ref.read(accessibilityProvider);
    announceSpeech("หน้า ${index + 1}: ${_slides[index].title}", acc.voiceEnabled);
  }

  Future<void> _finishOnboarding() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('onboarding_complete', true);
    } catch (e) {
      // Ignore sandbox/iframe localStorage errors gracefully
    }
    if (!mounted) return;
    final acc = ref.read(accessibilityProvider);
    announceSpeech("ยินดีด้วย! บันทึกข้อมูลเริ่มต้นสำเร็จแล้ว กำลังเข้าสู่ขั้นตอนการล็อกอินเข้าสู่ระบบ", acc.voiceEnabled);
    Navigator.pushReplacementNamed(context, '/auth');
  }

  @override
  Widget build(BuildContext context) {
    final acc = ref.watch(accessibilityProvider);
    final isHighContrast = acc.highContrast;
    final themeColor = isHighContrast ? Colors.black : _slides[_currentPage].color;
    final textColor = isHighContrast ? Colors.white : Colors.black87;
    final bgTextColor = isHighContrast ? Colors.white : Colors.white;

    return Scaffold(
      backgroundColor: isHighContrast ? Colors.black : Colors.grey[50],
      body: SafeArea(
        child: Column(
          children: [
            // Top Skip Button
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
              child: Align(
                alignment: Alignment.topRight,
                child: Semantics(
                  label: 'ข้ามคำแนะนำการใช้งาน',
                  button: true,
                  child: TextButton(
                    onPressed: _finishOnboarding,
                    style: TextButton.styleFrom(
                      foregroundColor: isHighContrast ? Colors.white : Colors.grey[600],
                    ),
                    child: Text(
                      'ข้าม',
                      style: TextStyle(fontSize: 16 * acc.fontScale, fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
              ),
            ),

            // Page Slider with Scale and Fade Transitions
            Expanded(
              child: PageView.builder(
                controller: _pageController,
                itemCount: _slides.length,
                onPageChanged: _onPageChanged,
                itemBuilder: (context, index) {
                  return AnimatedBuilder(
                    animation: _pageController,
                    builder: (context, child) {
                      double value = 1.0;
                      if (_pageController.position.haveDimensions) {
                        value = _pageController.page! - index;
                        value = (1 - (value.abs() * 0.3)).clamp(0.0, 1.0);
                      }
                      final opacity = (1 - ((_pageController.position.haveDimensions ? _pageController.page! : 0.0) - index).abs()).clamp(0.0, 1.0).toDouble();

                      return Transform.scale(
                        scale: value,
                        child: Opacity(
                          opacity: opacity,
                          child: child,
                        ),
                      );
                    },
                    child: Padding(
                      padding: const EdgeInsets.all(32.0),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Container(
                            padding: const EdgeInsets.all(24.0),
                            decoration: BoxDecoration(
                              color: isHighContrast ? Colors.grey[900] : _slides[index].color.withOpacity(0.1),
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              _slides[index].icon,
                              size: 100,
                              color: isHighContrast ? Colors.white : _slides[index].color,
                            ),
                          ),
                          const SizedBox(height: 40.0),
                          Text(
                            _slides[index].title,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 26 * acc.fontScale,
                              fontWeight: FontWeight.bold,
                              color: isHighContrast ? Colors.white : _slides[index].color,
                            ),
                          ),
                          const SizedBox(height: 16.0),
                          Text(
                            _slides[index].description,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 16 * acc.fontScale,
                              color: isHighContrast ? Colors.white70 : Colors.black87,
                              height: 1.6,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),

            // Bottom navigation row (indicators and buttons)
            Padding(
              padding: const EdgeInsets.all(24.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  // Indicators dots
                  Row(
                    children: List.generate(_slides.length, (index) {
                      final isSelected = _currentPage == index;
                      return AnimatedContainer(
                        duration: const Duration(milliseconds: 300),
                        margin: const EdgeInsets.symmetric(horizontal: 4.0),
                        height: 8.0,
                        width: isSelected ? 24.0 : 8.0,
                        decoration: BoxDecoration(
                          color: isHighContrast
                              ? (isSelected ? Colors.white : Colors.white24)
                              : (isSelected ? themeColor : Colors.grey[300]),
                          borderRadius: BorderRadius.circular(4.0),
                        ),
                      );
                    }),
                  ),

                  // Action Button
                  Semantics(
                    label: _currentPage < _slides.length - 1 ? 'ไปหน้าถัดไป' : 'เริ่มต้นใช้งานแอปพลิเคชัน',
                    button: true,
                    child: ElevatedButton(
                      onPressed: () {
                        if (_currentPage < _slides.length - 1) {
                          _pageController.nextPage(
                            duration: const Duration(milliseconds: 300),
                            curve: Curves.easeIn,
                          );
                        } else {
                          _finishOnboarding();
                        }
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: isHighContrast ? Colors.white : themeColor,
                        foregroundColor: isHighContrast ? Colors.black : bgTextColor,
                        padding: const EdgeInsets.symmetric(horizontal: 32.0, vertical: 16.0),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(30.0),
                        ),
                        elevation: isHighContrast ? 0 : 4,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            _currentPage < _slides.length - 1 ? 'ถัดไป' : 'เริ่มต้นใช้งาน',
                            style: TextStyle(fontSize: 16 * acc.fontScale, fontWeight: FontWeight.bold),
                          ),
                          if (_currentPage < _slides.length - 1) ...[
                            const SizedBox(width: 8),
                            const Icon(Icons.arrow_forward_rounded, size: 20),
                          ]
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class OnboardingSlideData {
  final IconData icon;
  final String title;
  final String description;
  final Color color;

  OnboardingSlideData({
    required this.icon,
    required this.title,
    required this.description,
    required this.color,
  });
}
