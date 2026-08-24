import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/accessibility_notifier.dart';
import '../../core/tts_helper.dart';

class ProfileSelectionScreen extends ConsumerStatefulWidget {
  const ProfileSelectionScreen({super.key});

  @override
  ConsumerState<ProfileSelectionScreen> createState() => _ProfileSelectionScreenState();
}

class _ProfileSelectionScreenState extends ConsumerState<ProfileSelectionScreen> {
  String? _selectedMode;

  @override
  void initState() {
    super.initState();
    announceSpeech("กรุณาเลือกรูปแบบความต้องการพิเศษของคุณ เพื่อเริ่มต้นใช้งาน", true);
  }

  Future<void> _confirmSelection(String mode) async {
    HapticFeedback.mediumImpact();
    ref.read(accessibilityProvider.notifier).setMode(mode);

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('onboarding_complete', true);
    } catch (e) {
      // Ignore sandbox iframe restrictions gracefully
    }

    if (!mounted) return;

    String modeName = "";
    if (mode == 'visual') {
      modeName = "ผู้พิการทางสายตา";
    } else if (mode == 'wheelchair') {
      modeName = "ผู้พิการใช้วีลแชร์";
    } else {
      modeName = "ผู้พิการทางการได้ยินหรือพูด";
    }

    announceSpeech("คุณเลือกโปรไฟล์ $modeName แล้ว กำลังเข้าสู่หน้าล็อกอิน", true);
    Navigator.pushReplacementNamed(context, '/auth');
  }

  @override
  Widget build(BuildContext context) {
    final acc = ref.watch(accessibilityProvider);
    final isHighContrast = acc.highContrast;

    return Scaffold(
      backgroundColor: isHighContrast ? Colors.black : Colors.grey[50],
      appBar: AppBar(
        title: Text(
          'เลือกรูปแบบความต้องการพิเศษ',
          style: TextStyle(
            fontSize: 20 * acc.fontScale,
            fontWeight: FontWeight.bold,
            color: isHighContrast ? Colors.white : Colors.blue[900],
          ),
        ),
        backgroundColor: isHighContrast ? Colors.black : Colors.white,
        elevation: 0,
        automaticallyImplyLeading: false,
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'เลือกโปรไฟล์หลักเพื่อรับการตั้งค่าปุ่มและหน้าจอที่เหมาะสมกับการใช้งานของคุณโดยอัตโนมัติ',
                style: TextStyle(
                  fontSize: 16 * acc.fontScale,
                  color: isHighContrast ? Colors.white70 : Colors.grey[700],
                  height: 1.4,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24.0),
              
              // Mode 1: Visually Impaired
              Expanded(
                child: _buildProfileCard(
                  context: context,
                  mode: 'visual',
                  icon: Icons.remove_red_eye,
                  title: '👁 ผู้พิการทางสายตา',
                  description: 'เปิดใช้เสียงนำทาง คอนทราสต์สีสูง และขนาดปุ่มขนาดใหญ่พิเศษสำหรับการสัมผัส',
                  color: Colors.blue[900]!,
                  isHighContrast: isHighContrast,
                  acc: acc,
                ),
              ),
              const SizedBox(height: 16.0),
              
              // Mode 2: Wheelchair / Mobility
              Expanded(
                child: _buildProfileCard(
                  context: context,
                  mode: 'wheelchair',
                  icon: Icons.accessible_forward_rounded,
                  title: '♿ ผู้พิการใช้วีลแชร์ / เคลื่อนไหว',
                  description: 'แผนที่นำทางพิเศษเพื่อเลี่ยงอุปสรรค ทางลาด ลิฟต์ พร้อมปุ่มซูมขยายแผนที่ขนาดใหญ่',
                  color: Colors.teal[800]!,
                  isHighContrast: isHighContrast,
                  acc: acc,
                ),
              ),
              const SizedBox(height: 16.0),
              
              // Mode 3: Hearing / Speech
              Expanded(
                child: _buildProfileCard(
                  context: context,
                  mode: 'speech_hearing',
                  icon: Icons.sign_language_rounded,
                  title: '🖐 ผู้พิการทางการได้ยิน / พูด',
                  description: 'เครื่องมือแปลภาษามือสดผ่านกล้อง ระบบถอดเสียงพูดเป็นข้อความ และการพิมพ์สั่งคำพูดด่วน',
                  color: Colors.purple[800]!,
                  isHighContrast: isHighContrast,
                  acc: acc,
                ),
              ),
              const SizedBox(height: 20.0),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildProfileCard({
    required BuildContext context,
    required String mode,
    required IconData icon,
    required String title,
    required String description,
    required Color color,
    required bool isHighContrast,
    required AccessibilityState acc,
  }) {
    final isSelected = _selectedMode == mode;

    return Semantics(
      button: true,
      label: '$title. $description',
      child: GestureDetector(
        onTap: () {
          setState(() {
            _selectedMode = mode;
          });
          _confirmSelection(mode);
        },
        child: Container(
          decoration: BoxDecoration(
            color: isHighContrast ? Colors.black : Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isHighContrast 
                  ? Colors.white 
                  : (isSelected ? color : Colors.grey[300]!),
              width: isHighContrast ? 2.5 : (isSelected ? 3.0 : 1.5),
            ),
            boxShadow: isHighContrast ? [] : [
              BoxShadow(
                color: Colors.black.withOpacity(0.04),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          padding: const EdgeInsets.all(16.0),
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
              const SizedBox(width: 16.0),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 18 * acc.fontScale,
                        fontWeight: FontWeight.bold,
                        color: isHighContrast ? Colors.white : Colors.black87,
                      ),
                    ),
                    const SizedBox(height: 4.0),
                    Text(
                      description,
                      style: TextStyle(
                        fontSize: 12 * acc.fontScale,
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
    );
  }
}
