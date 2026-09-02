import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/accessibility_notifier.dart';
import '../../core/api_client.dart';
import '../../core/app_colors.dart';
import '../../core/services/haptic_service.dart';

class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key});

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  final List<Map<String, String>> _contacts = [
    {'name': 'คุณแม่ (Mother)', 'phone': '0891234567'},
    {'name': 'หน่วยแพทย์ฉุกเฉิน', 'phone': '1669'},
  ];

  Future<void> _makePhoneCall(String phoneNumber) async {
    final Uri launchUri = Uri(
      scheme: 'tel',
      path: phoneNumber,
    );
    if (await canLaunchUrl(launchUri)) {
      await launchUrl(launchUri);
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('ไม่สามารถโทรออกได้ในขณะนี้')),
        );
      }
    }
  }

  void _addContact() {
    final nameController = TextEditingController();
    final phoneController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('เพิ่มผู้ติดต่อฉุกเฉิน'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameController,
                decoration: const InputDecoration(labelText: 'ชื่อผู้ติดต่อ'),
              ),
              const SizedBox(height: 8.0),
              TextField(
                controller: phoneController,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(labelText: 'เบอร์โทรศัพท์'),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('ยกเลิก'),
            ),
            ElevatedButton(
              onPressed: () {
                if (nameController.text.isNotEmpty && phoneController.text.isNotEmpty) {
                  setState(() {
                    _contacts.add({
                      'name': nameController.text,
                      'phone': phoneController.text,
                    });
                  });
                  HapticService().turnGuidance();
                  Navigator.pop(context);
                }
              },
              child: const Text('บันทึก'),
            ),
          ],
        );
      },
    );
  }

  void _deleteContact(int index) {
    setState(() {
      _contacts.removeAt(index);
    });
    HapticService().turnGuidance();
  }

  @override
  Widget build(BuildContext context) {
    final acc = ref.watch(accessibilityProvider);
    final notifier = ref.read(accessibilityProvider.notifier);
    final isHighContrast = acc.highContrast;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          'โปรไฟล์และการตั้งค่า',
          style: TextStyle(fontSize: 20 * acc.fontScale, fontWeight: FontWeight.bold),
        ),
        backgroundColor: isHighContrast ? Colors.black : Theme.of(context).colorScheme.primary,
        foregroundColor: Colors.white,
      ),
      backgroundColor: isHighContrast ? Colors.black : const Color(0xFFF1F5F9),
      body: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 1. User Profile Section
            Semantics(
              label: 'ส่วนข้อมูลผู้ใช้',
              child: Card(
                color: isHighContrast ? Colors.black : Colors.white,
                shape: isHighContrast ? const RoundedRectangleBorder(side: BorderSide(color: Colors.white, width: 2)) : null,
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Row(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(36),
                        child: Image.asset(
                          'assets/icon_in_app.png',
                          width: 68,
                          height: 68,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => CircleAvatar(
                            radius: 34,
                            backgroundColor: isHighContrast ? Colors.white : Theme.of(context).colorScheme.primary.withValues(alpha: 0.1),
                            child: Icon(
                              Icons.person,
                              size: 44,
                              color: isHighContrast ? Colors.black : Theme.of(context).colorScheme.primary,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 16.0),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              acc.userName.isNotEmpty ? acc.userName : 'ผู้ใช้งาน TAM AI',
                              style: TextStyle(
                                fontSize: 19 * acc.fontScale,
                                fontWeight: FontWeight.bold,
                                color: isHighContrast ? Colors.white : Colors.black87,
                              ),
                            ),
                            const SizedBox(height: 4.0),
                            Text(
                              acc.userEmail.isNotEmpty ? acc.userEmail : 'tam-user@example.com',
                              style: TextStyle(
                                fontSize: 13 * acc.fontScale,
                                color: isHighContrast ? Colors.white70 : Colors.grey[600],
                              ),
                            ),
                            const SizedBox(height: 6.0),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                color: isHighContrast ? Colors.yellowAccent.withValues(alpha: 0.15) : Theme.of(context).colorScheme.primary.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(8),
                                border: isHighContrast ? Border.all(color: Colors.yellowAccent) : null,
                              ),
                              child: Text(
                                '👁 โหมดผู้พิการทางสายตา (TAM AI)',
                                style: TextStyle(
                                  fontSize: 11.5 * acc.fontScale,
                                  fontWeight: FontWeight.bold,
                                  color: isHighContrast ? Colors.yellowAccent : Theme.of(context).colorScheme.primary,
                                ),
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
            const SizedBox(height: 14.0),

            // 2. ═══ Voice & Haptic Accessibility Settings (TAM AI Core Settings) ═══
            Card(
              color: isHighContrast ? Colors.black : Colors.white,
              shape: isHighContrast ? const RoundedRectangleBorder(side: BorderSide(color: Colors.white, width: 2)) : null,
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.record_voice_over_rounded, color: isHighContrast ? Colors.yellowAccent : Theme.of(context).colorScheme.primary),
                        const SizedBox(width: 8),
                        Text(
                          'การตั้งค่าระบบเสียงและการสั่น (Voice & Haptic)',
                          style: TextStyle(fontSize: 16.5 * acc.fontScale, fontWeight: FontWeight.bold, color: isHighContrast ? Colors.yellowAccent : Colors.black87),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),

                    // Voice Master Switch
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text('เปิดระบบเสียงนำทาง (Voice Guidance)', style: TextStyle(fontSize: 15 * acc.fontScale, fontWeight: FontWeight.bold, color: isHighContrast ? Colors.white : Colors.black87)),
                      subtitle: Text('พูดคำแนะนำการเลี้ยว และเตือนสิ่งกีดขวางล่วงหน้า', style: TextStyle(fontSize: 12 * acc.fontScale, color: isHighContrast ? Colors.white70 : Colors.black54)),
                      value: acc.voiceEnabled,
                      onChanged: notifier.toggleVoice,
                      activeThumbColor: isHighContrast ? Colors.yellowAccent : Theme.of(context).colorScheme.primary,
                    ),
                    const Divider(height: 16),

                    // Speech Rate Slider
                    Text(
                      'ความเร็วเสียงพูด: ${acc.speechRate.toStringAsFixed(1)}x',
                      style: TextStyle(fontSize: 14.5 * acc.fontScale, fontWeight: FontWeight.bold, color: isHighContrast ? Colors.white : Colors.black87),
                    ),
                    Slider(
                      min: 0.8,
                      max: 1.5,
                      divisions: 7,
                      value: acc.speechRate,
                      activeColor: isHighContrast ? Colors.yellowAccent : Theme.of(context).colorScheme.primary,
                      onChanged: notifier.setSpeechRate,
                    ),
                    const SizedBox(height: 8),

                    // Alert Detail Level
                    Text(
                      'ระดับความละเอียดการแจ้งเตือน:',
                      style: TextStyle(fontSize: 14 * acc.fontScale, fontWeight: FontWeight.bold, color: isHighContrast ? Colors.white : Colors.black87),
                    ),
                    const SizedBox(height: 6),
                    SizedBox(
                      width: double.infinity,
                      child: SegmentedButton<String>(
                        showSelectedIcon: false,
                        segments: const [
                          ButtonSegment(value: 'brief', label: Text('สั้นกระชับ (แนะนำ)')),
                          ButtonSegment(value: 'detailed', label: Text('ละเอียดรอบตัว')),
                        ],
                        selected: {acc.alertDetailLevel},
                        onSelectionChanged: (set) => notifier.setAlertDetailLevel(set.first),
                      ),
                    ),
                    const Divider(height: 24),

                    // Auto-open Camera on High Risk Switch
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text('เปิดกล้องตรวจจับอัตโนมัติตอน High Risk', style: TextStyle(fontSize: 15 * acc.fontScale, fontWeight: FontWeight.bold, color: isHighContrast ? Colors.white : Colors.black87)),
                      subtitle: Text('เปิดกล้อง AI สแกนเฉพาะหน้าเมื่อเข้าใกล้จุดเสี่ยงหรือสิ่งกีดขวาง', style: TextStyle(fontSize: 12 * acc.fontScale, color: isHighContrast ? Colors.white70 : Colors.black54)),
                      value: acc.autoCameraOnHighRisk,
                      onChanged: notifier.toggleAutoCamera,
                      activeThumbColor: isHighContrast ? Colors.yellowAccent : Theme.of(context).colorScheme.primary,
                    ),
                    const Divider(height: 20),

                    // Early Alert Distance
                    Text(
                      'ระยะเตือนล่วงหน้า (Early Alert Distance):',
                      style: TextStyle(fontSize: 14 * acc.fontScale, fontWeight: FontWeight.bold, color: isHighContrast ? Colors.white : Colors.black87),
                    ),
                    const SizedBox(height: 6),
                    SizedBox(
                      width: double.infinity,
                      child: SegmentedButton<int>(
                        showSelectedIcon: false,
                        segments: const [
                          ButtonSegment(value: 15, label: Text('15 เมตร')),
                          ButtonSegment(value: 25, label: Text('25 ม. (ปกติ)')),
                          ButtonSegment(value: 35, label: Text('35 เมตร')),
                        ],
                        selected: {acc.earlyAlertDistanceMeters},
                        onSelectionChanged: (set) => notifier.setEarlyAlertDistance(set.first),
                      ),
                    ),
                    const Divider(height: 24),

                    // Haptic Master Switch
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text('เปิดการสั่นตอบสนอง (Haptic Feedback)', style: TextStyle(fontSize: 15 * acc.fontScale, fontWeight: FontWeight.bold, color: isHighContrast ? Colors.white : Colors.black87)),
                      subtitle: Text('สั่นเตือนจังหวะเลี้ยว จุดเสี่ยง และขอความช่วยเหลือ', style: TextStyle(fontSize: 12 * acc.fontScale, color: isHighContrast ? Colors.white70 : Colors.black54)),
                      value: acc.hapticEnabled,
                      onChanged: notifier.toggleHaptic,
                      activeThumbColor: isHighContrast ? Colors.yellowAccent : Theme.of(context).colorScheme.primary,
                    ),
                    const SizedBox(height: 6),

                    // Haptic Intensity Level
                    Text(
                      'ระดับความแรงการสั่น:',
                      style: TextStyle(fontSize: 14 * acc.fontScale, fontWeight: FontWeight.bold, color: isHighContrast ? Colors.white : Colors.black87),
                    ),
                    const SizedBox(height: 6),
                    SizedBox(
                      width: double.infinity,
                      child: SegmentedButton<String>(
                        showSelectedIcon: false,
                        segments: const [
                          ButtonSegment(value: 'off', label: Text('ปิด')),
                          ButtonSegment(value: 'light', label: Text('เบา')),
                          ButtonSegment(value: 'medium', label: Text('กลาง')),
                          ButtonSegment(value: 'strong', label: Text('แรง')),
                        ],
                        selected: {acc.hapticIntensity},
                        onSelectionChanged: (set) => notifier.setHapticIntensity(set.first),
                      ),
                    ),
                    const Divider(height: 20),

                    // Vibration-Only Mode Switch
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text('โหมดสั่นอย่างเดียว (Vibration Only / Silent)', style: TextStyle(fontSize: 15 * acc.fontScale, fontWeight: FontWeight.bold, color: isHighContrast ? Colors.white : Colors.black87)),
                      subtitle: Text('ปิดเสียงนำทางและใช้ระบบสั่น Haptic Feedback เป็นหลัก', style: TextStyle(fontSize: 12 * acc.fontScale, color: isHighContrast ? Colors.white70 : Colors.black54)),
                      value: acc.vibrationOnlyMode,
                      onChanged: notifier.toggleVibrationOnlyMode,
                      activeThumbColor: isHighContrast ? Colors.yellowAccent : Theme.of(context).colorScheme.primary,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 14.0),

            // 3. Display & Theme Settings
            Card(
              color: isHighContrast ? Colors.black : Colors.white,
              shape: isHighContrast ? const RoundedRectangleBorder(side: BorderSide(color: Colors.white, width: 2)) : null,
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.display_settings_rounded, color: isHighContrast ? Colors.yellowAccent : Theme.of(context).colorScheme.primary),
                        const SizedBox(width: 8),
                        Text(
                          'การแสดงผลและสี (Display & Colors)',
                          style: TextStyle(fontSize: 16.5 * acc.fontScale, fontWeight: FontWeight.bold, color: isHighContrast ? Colors.yellowAccent : Colors.black87),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text('โหมดสีคอนทราสต์สูง (High Contrast)', style: TextStyle(fontSize: 15 * acc.fontScale, color: isHighContrast ? Colors.white : Colors.black87)),
                      value: acc.highContrast,
                      onChanged: notifier.toggleHighContrast,
                      activeThumbColor: isHighContrast ? Colors.yellowAccent : Theme.of(context).colorScheme.primary,
                    ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text('โหมดสีสำหรับคนตาบอดสี (Color Blind Mode)', style: TextStyle(fontSize: 15 * acc.fontScale, color: isHighContrast ? Colors.white : Colors.black87)),
                      value: acc.colorBlind,
                      onChanged: notifier.toggleColorBlind,
                      activeThumbColor: isHighContrast ? Colors.yellowAccent : Theme.of(context).colorScheme.primary,
                    ),
                    const SizedBox(height: 10),
                    Text(
                      'ขนาดตัวอักษร: ${acc.fontScale.toStringAsFixed(1)}x',
                      style: TextStyle(fontSize: 14.5 * acc.fontScale, fontWeight: FontWeight.bold, color: isHighContrast ? Colors.white : Colors.black87),
                    ),
                    Slider(
                      min: 1.0,
                      max: 2.0,
                      divisions: 5,
                      value: acc.fontScale,
                      activeColor: isHighContrast ? Colors.yellowAccent : AppColors.getPrimary(acc.colorBlind),
                      inactiveColor: Colors.grey,
                      onChanged: notifier.setFontScale,
                      semanticFormatterCallback: (double value) => 'ขนาดตัวอักษร ${value.toStringAsFixed(1)} เท่า',
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 14.0),

            // 4. Emergency Contacts list
            Card(
              color: isHighContrast ? Colors.black : Colors.white,
              shape: isHighContrast ? const RoundedRectangleBorder(side: BorderSide(color: Colors.white, width: 2)) : null,
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'รายชื่อผู้ติดต่อฉุกเฉิน',
                          style: TextStyle(fontSize: 17 * acc.fontScale, fontWeight: FontWeight.bold, color: isHighContrast ? Colors.yellowAccent : Colors.black87),
                        ),
                        IconButton(
                          icon: Icon(Icons.person_add, color: isHighContrast ? Colors.yellowAccent : AppColors.getPrimary(acc.colorBlind)),
                          onPressed: _addContact,
                          tooltip: 'เพิ่มผู้ติดต่อฉุกเฉิน',
                        ),
                      ],
                    ),
                    const SizedBox(height: 8.0),
                    if (_contacts.isEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 12.0),
                        child: Text(
                          'ไม่มีรายชื่อผู้ติดต่อ',
                          style: TextStyle(
                            fontSize: 15 * acc.fontScale,
                            color: isHighContrast ? Colors.white70 : Colors.grey[600],
                          ),
                        ),
                      )
                    else
                      ListView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: _contacts.length,
                        itemBuilder: (context, index) {
                          final contact = _contacts[index];
                          return Card(
                            color: isHighContrast ? const Color(0xFF1E293B) : const Color(0xFFF8FAFC),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                              side: BorderSide(color: isHighContrast ? Colors.white30 : const Color(0xFFE2E8F0)),
                            ),
                            margin: const EdgeInsets.only(bottom: 8.0),
                            child: ListTile(
                              leading: CircleAvatar(
                                backgroundColor: isHighContrast ? Colors.yellowAccent : AppColors.getPrimary(acc.colorBlind),
                                child: Icon(Icons.person, color: isHighContrast ? Colors.black : Colors.white),
                              ),
                              title: Text(contact['name']!, style: TextStyle(fontSize: 15 * acc.fontScale, fontWeight: FontWeight.bold, color: isHighContrast ? Colors.white : Colors.black)),
                              subtitle: Text(contact['phone']!, style: TextStyle(fontSize: 13 * acc.fontScale, color: isHighContrast ? Colors.white70 : Colors.black54)),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  IconButton(
                                    icon: const Icon(Icons.phone, color: Colors.green),
                                    onPressed: () => _makePhoneCall(contact['phone']!),
                                    tooltip: 'โทรหา ${contact['name']}',
                                  ),
                                  IconButton(
                                    icon: Icon(Icons.delete_outline, color: Colors.red[300]),
                                    onPressed: () => _deleteContact(index),
                                    tooltip: 'ลบผู้ติดต่อ',
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 14.0),

            // 5. City Accessibility Command Dashboard Link Card
            Card(
              color: isHighContrast ? Colors.black : const Color(0xFF1E1B4B),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
                side: BorderSide(color: isHighContrast ? Colors.white : const Color(0xFF6366F1), width: 1.5),
              ),
              child: ListTile(
                leading: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.indigo.withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.analytics_rounded, color: Colors.amberAccent, size: 28),
                ),
                title: Text(
                  'City Command Dashboard',
                  style: TextStyle(
                    fontSize: 16 * acc.fontScale,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                subtitle: Text(
                  'ศูนย์วิเคราะห์ Heatmap จุดเสี่ยง & บริหารเมือง',
                  style: TextStyle(fontSize: 13 * acc.fontScale, color: Colors.white70),
                ),
                trailing: const Icon(Icons.open_in_new_rounded, color: Colors.amberAccent),
                onTap: () {
                  launchUrl(
                    Uri.parse('${ApiClient.getDefaultBaseUrl()}/dashboard'),
                    mode: LaunchMode.externalApplication,
                  );
                },
              ),
            ),
            const SizedBox(height: 20.0),

            // 6. Logout Button
            Semantics(
              button: true,
              label: 'ปุ่มออกจากระบบ',
              child: ElevatedButton.icon(
                onPressed: () {
                  notifier.logout();
                  Navigator.pushNamedAndRemoveUntil(context, '/onboarding', (route) => false);
                },
                icon: const Icon(Icons.logout),
                label: Text(
                  'ออกจากระบบ',
                  style: TextStyle(fontSize: 17 * acc.fontScale, fontWeight: FontWeight.bold),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFDC2626),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  padding: const EdgeInsets.symmetric(vertical: 16.0),
                ),
              ),
            ),
            const SizedBox(height: 20.0),

            // App Version
            Center(
              child: Text(
                'TAM AI Version 1.0.0',
                style: TextStyle(
                  fontSize: 13 * acc.fontScale,
                  color: isHighContrast ? Colors.white54 : Colors.grey,
                ),
              ),
            ),
            const SizedBox(height: 16.0),
          ],
        ),
      ),
    );
  }
}
