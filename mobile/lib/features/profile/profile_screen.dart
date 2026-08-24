import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/accessibility_notifier.dart';

class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key});

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  String _selectedLanguage = 'th';

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
        backgroundColor: isHighContrast ? Colors.black : Colors.blue[900],
        foregroundColor: Colors.white,
      ),
      backgroundColor: isHighContrast ? Colors.black : Colors.grey[50],
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // User Profile Section
            Semantics(
              label: 'ส่วนข้อมูลผู้ใช้',
              child: Card(
                color: isHighContrast ? Colors.black : Colors.white,
                shape: isHighContrast ? const RoundedRectangleBorder(side: BorderSide(color: Colors.white)) : null,
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Row(
                    children: [
                      CircleAvatar(
                        radius: 36,
                        backgroundColor: isHighContrast ? Colors.white : Colors.blue[100],
                        child: Icon(
                          Icons.person,
                          size: 48,
                          color: isHighContrast ? Colors.black : Colors.blue[900],
                        ),
                      ),
                      const SizedBox(width: 16.0),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'ผู้ใช้งานตัวอย่าง',
                              style: TextStyle(
                                fontSize: 20 * acc.fontScale,
                                fontWeight: FontWeight.bold,
                                color: isHighContrast ? Colors.white : Colors.black87,
                              ),
                            ),
                            const SizedBox(height: 4.0),
                            Text(
                              'user@example.com',
                              style: TextStyle(
                                fontSize: 16 * acc.fontScale,
                                color: isHighContrast ? Colors.white70 : Colors.grey[600],
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
            const SizedBox(height: 24.0),

            // Profile preferences card
            Card(
              color: isHighContrast ? Colors.black : Colors.white,
              shape: isHighContrast ? const RoundedRectangleBorder(side: BorderSide(color: Colors.white)) : null,
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'ภาษา (Language)',
                      style: TextStyle(fontSize: 16 * acc.fontScale, fontWeight: FontWeight.bold, color: isHighContrast ? Colors.white : Colors.black87),
                    ),
                    const SizedBox(height: 8.0),
                    DropdownButtonFormField<String>(
                      value: _selectedLanguage,
                      decoration: const InputDecoration(
                        border: OutlineInputBorder(),
                        contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      ),
                      dropdownColor: isHighContrast ? Colors.black : Colors.white,
                      style: TextStyle(color: isHighContrast ? Colors.white : Colors.black, fontSize: 16 * acc.fontScale),
                      items: const [
                        DropdownMenuItem(value: 'th', child: Text('ภาษาไทย')),
                        DropdownMenuItem(value: 'en', child: Text('English')),
                      ],
                      onChanged: (val) {
                        if (val != null) {
                          setState(() {
                            _selectedLanguage = val;
                          });
                        }
                      },
                    ),
                    const SizedBox(height: 20.0),
                    Text(
                      'เลือกโหมดการช่วยเหลือ',
                      style: TextStyle(fontSize: 16 * acc.fontScale, fontWeight: FontWeight.bold, color: isHighContrast ? Colors.white : Colors.black87),
                    ),
                    const SizedBox(height: 8.0),
                    DropdownButtonFormField<String>(
                      value: acc.accessibilityMode,
                      decoration: const InputDecoration(
                        border: OutlineInputBorder(),
                        contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      ),
                      dropdownColor: isHighContrast ? Colors.black : Colors.white,
                      style: TextStyle(color: isHighContrast ? Colors.white : Colors.black, fontSize: 16 * acc.fontScale),
                      items: const [
                        DropdownMenuItem(value: 'visual', child: Text('👁 ความช่วยเหลือทางสายตา')),
                        DropdownMenuItem(value: 'wheelchair', child: Text('♿ วีลแชร์ / การเคลื่อนไหว')),
                        DropdownMenuItem(value: 'speech_hearing', child: Text('🖐 การพูดและได้ยิน')),
                      ],
                      onChanged: (val) {
                        if (val != null) notifier.setMode(val);
                      },
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16.0),

            // System settings triggers card
            Card(
              color: isHighContrast ? Colors.black : Colors.white,
              shape: isHighContrast ? const RoundedRectangleBorder(side: BorderSide(color: Colors.white)) : null,
              child: Column(
                children: [
                  SwitchListTile(
                    title: Text('เปิดระบบคำแนะนำด้วยเสียง (Voice)', style: TextStyle(fontSize: 16 * acc.fontScale, color: isHighContrast ? Colors.white : Colors.black)),
                    value: acc.voiceEnabled,
                    onChanged: notifier.toggleVoice,
                    activeColor: isHighContrast ? Colors.white : Colors.blue,
                  ),
                  SwitchListTile(
                    title: Text('เปิดการสั่นตอบสนอง (Haptic)', style: TextStyle(fontSize: 16 * acc.fontScale, color: isHighContrast ? Colors.white : Colors.black)),
                    value: acc.hapticEnabled,
                    onChanged: notifier.toggleHaptic,
                    activeColor: isHighContrast ? Colors.white : Colors.blue,
                  ),
                  SwitchListTile(
                    title: Text('โหมดสีคอนทราสต์สูง (High Contrast)', style: TextStyle(fontSize: 16 * acc.fontScale, color: isHighContrast ? Colors.white : Colors.black)),
                    value: acc.highContrast,
                    onChanged: notifier.toggleHighContrast,
                    activeColor: isHighContrast ? Colors.white : Colors.blue,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16.0),

            // Font scale slider card
            Card(
              color: isHighContrast ? Colors.black : Colors.white,
              shape: isHighContrast ? const RoundedRectangleBorder(side: BorderSide(color: Colors.white)) : null,
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'ขนาดตัวอักษร: ${acc.fontScale.toStringAsFixed(1)}x',
                      style: TextStyle(fontSize: 16 * acc.fontScale, fontWeight: FontWeight.bold, color: isHighContrast ? Colors.white : Colors.black87),
                    ),
                    Slider(
                      min: 1.0,
                      max: 2.0,
                      divisions: 5,
                      value: acc.fontScale,
                      activeColor: isHighContrast ? Colors.white : Colors.blue[800],
                      inactiveColor: Colors.grey,
                      onChanged: notifier.setFontScale,
                      semanticFormatterCallback: (double value) => 'ขนาดตัวอักษร ${value.toStringAsFixed(1)} เท่า',
                    ),
                  ],
                ),
              ),
            ),
            const Divider(height: 32.0),

            // Emergency Contacts list
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'รายชื่อผู้ติดต่อฉุกเฉิน',
                  style: TextStyle(fontSize: 18 * acc.fontScale, fontWeight: FontWeight.bold, color: isHighContrast ? Colors.white : Colors.black87),
                ),
                IconButton(
                  icon: Icon(Icons.person_add, color: isHighContrast ? Colors.white : Colors.blue[800]),
                  onPressed: _addContact,
                  tooltip: 'เพิ่มผู้ติดต่อฉุกเฉิน',
                ),
              ],
            ),
            const SizedBox(height: 8.0),
            
            if (_contacts.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 16.0),
                child: Text(
                  'ไม่มีรายชื่อผู้ติดต่อ',
                  style: TextStyle(
                    fontSize: 16 * acc.fontScale,
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
                  return Dismissible(
                    key: ValueKey(contact['phone']! + index.toString()),
                    direction: DismissDirection.endToStart,
                    onDismissed: (direction) {
                      _deleteContact(index);
                    },
                    background: Container(
                      color: Colors.red,
                      alignment: Alignment.centerRight,
                      padding: const EdgeInsets.only(right: 20.0),
                      child: const Icon(Icons.delete, color: Colors.white),
                    ),
                    child: Card(
                      color: isHighContrast ? Colors.black : Colors.white,
                      shape: isHighContrast ? const RoundedRectangleBorder(side: BorderSide(color: Colors.white)) : null,
                      margin: const EdgeInsets.only(bottom: 8.0),
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor: isHighContrast ? Colors.white : Colors.blue[50],
                          child: Icon(Icons.person, color: isHighContrast ? Colors.black : Colors.blue[800]),
                        ),
                        title: Text(contact['name']!, style: TextStyle(fontSize: 16 * acc.fontScale, color: isHighContrast ? Colors.white : Colors.black)),
                        subtitle: Text(contact['phone']!, style: TextStyle(fontSize: 14 * acc.fontScale, color: isHighContrast ? Colors.white70 : Colors.black54)),
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
                    ),
                  );
                },
              ),
              
            const SizedBox(height: 32.0),
            
            // Logout Button
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
                  style: TextStyle(fontSize: 18 * acc.fontScale, fontWeight: FontWeight.bold),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: isHighContrast ? Colors.black : Colors.red[800],
                  foregroundColor: Colors.white,
                  side: isHighContrast ? const BorderSide(color: Colors.white, width: 2) : null,
                  padding: const EdgeInsets.symmetric(vertical: 16.0),
                ),
              ),
            ),
            
            const SizedBox(height: 24.0),
            // App Version
            Center(
              child: Text(
                'เวอร์ชันแอปพลิเคชัน 1.0.0',
                style: TextStyle(
                  fontSize: 14 * acc.fontScale,
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
