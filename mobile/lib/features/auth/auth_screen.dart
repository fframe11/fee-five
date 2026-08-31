import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/accessibility_notifier.dart';
import '../../core/api_client.dart';

class AuthScreen extends ConsumerStatefulWidget {
  const AuthScreen({super.key});

  @override
  ConsumerState<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends ConsumerState<AuthScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  
  bool _isLogin = true;
  bool _isLoading = false;
  bool _obscurePassword = true;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    
    setState(() {
      _isLoading = true;
    });

    try {
      final email = _emailController.text;
      final password = _passwordController.text;
      
      if (_isLogin) {
        await ApiClient().login(email, password);
      } else {
        await ApiClient().register(email, password);
      }
      
      if (!mounted) return;
      Navigator.pushReplacementNamed(context, '/home');
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'เกิดข้อผิดพลาด: ${e.toString()}',
            style: const TextStyle(color: Colors.white),
          ),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final acc = ref.watch(accessibilityProvider);
    final isHighContrast = acc.highContrast;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          _isLogin ? 'เข้าสู่ระบบ' : 'ลงทะเบียน',
          style: TextStyle(
            fontSize: 20 * acc.fontScale,
            fontWeight: FontWeight.bold,
          ),
        ),
        backgroundColor: isHighContrast ? Colors.black : Theme.of(context).colorScheme.primary,
        foregroundColor: Colors.white,
      ),
      backgroundColor: isHighContrast ? Colors.black : Colors.grey[50],
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Semantics(
                  label: 'โลโก้แอปพลิเคชัน TAM',
                  child: Text(
                    'TAM',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 36 * acc.fontScale,
                      fontWeight: FontWeight.bold,
                      color: isHighContrast ? Colors.white : Theme.of(context).colorScheme.primary,
                      letterSpacing: 2.0,
                    ),
                  ),
                ),
                const SizedBox(height: 6.0),
                Text(
                  'Transformation Accessibility Mass',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 15 * acc.fontScale,
                    fontWeight: FontWeight.w600,
                    color: isHighContrast ? Colors.white70 : Colors.grey[700],
                  ),
                ),

                const SizedBox(height: 32.0),
                Semantics(
                  label: 'ช่องกรอกอีเมล',
                  child: TextFormField(
                    controller: _emailController,
                    keyboardType: TextInputType.emailAddress,
                    decoration: InputDecoration(
                      labelText: 'อีเมล (Email)',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
                      labelStyle: TextStyle(
                        color: isHighContrast ? Colors.white : Colors.black,
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(
                          color: isHighContrast ? Colors.white : Colors.grey[400]!,
                          width: 1.5,
                        ),
                      ),
                    ),
                    style: TextStyle(
                      color: isHighContrast ? Colors.white : Colors.black,
                    ),
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return 'กรุณากรอกอีเมล';
                      }
                      if (!value.contains('@')) {
                        return 'รูปแบบอีเมลไม่ถูกต้อง';
                      }
                      return null;
                    },
                  ),
                ),
                const SizedBox(height: 16.0),
                Semantics(
                  label: 'ช่องกรอกรหัสผ่าน',
                  child: TextFormField(
                    controller: _passwordController,
                    obscureText: _obscurePassword,
                    decoration: InputDecoration(
                      labelText: 'รหัสผ่าน (Password)',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
                      labelStyle: TextStyle(
                        color: isHighContrast ? Colors.white : Colors.black,
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(
                          color: isHighContrast ? Colors.white : Colors.grey[400]!,
                          width: 1.5,
                        ),
                      ),
                      suffixIcon: IconButton(
                        icon: Icon(
                          _obscurePassword ? Icons.visibility_off : Icons.visibility,
                          color: isHighContrast ? Colors.white : Colors.grey,
                        ),
                        onPressed: () {
                          setState(() {
                            _obscurePassword = !_obscurePassword;
                          });
                        },
                        tooltip: 'สลับการมองเห็นรหัสผ่าน',
                      ),
                    ),
                    style: TextStyle(
                      color: isHighContrast ? Colors.white : Colors.black,
                    ),
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return 'กรุณากรอกรหัสผ่าน';
                      }
                      if (value.length < 6) {
                        return 'รหัสผ่านต้องมีอย่างน้อย 6 ตัวอักษร';
                      }
                      return null;
                    },
                  ),
                ),
                const SizedBox(height: 24.0),
                if (_isLoading)
                  const Center(child: CircularProgressIndicator())
                else
                  Semantics(
                    button: true,
                    label: _isLogin ? 'ปุ่มเข้าสู่ระบบ' : 'ปุ่มลงทะเบียน',
                    child: SizedBox(
                      height: 54,
                      child: ElevatedButton(
                        onPressed: _submit,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: isHighContrast ? Colors.white : Theme.of(context).colorScheme.primary,
                          foregroundColor: isHighContrast ? Colors.black : Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: Text(
                          _isLogin ? 'เข้าสู่ระบบ' : 'ลงทะเบียน',
                          style: TextStyle(
                            fontSize: 18 * acc.fontScale,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                  ),
                const SizedBox(height: 12.0),
                Semantics(
                  button: true,
                  label: 'สลับโหมดเข้าสู่ระบบหรือลงทะเบียน',
                  child: TextButton(
                    onPressed: () {
                      setState(() {
                        _isLogin = !_isLogin;
                        _formKey.currentState?.reset();
                        _emailController.clear();
                        _passwordController.clear();
                      });
                    },
                    style: TextButton.styleFrom(
                      foregroundColor: isHighContrast ? Colors.white : Theme.of(context).colorScheme.primary,
                    ),
                    child: Text(
                      _isLogin
                          ? 'ยังไม่มีบัญชี? สมัครใช้งานที่นี่'
                          : 'มีบัญชีอยู่แล้ว? เข้าสู่ระบบที่นี่',
                      style: TextStyle(
                        fontSize: 15 * acc.fontScale,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 8.0),
                Semantics(
                  button: true,
                  label: 'ปุ่มใช้งานในฐานะผู้มาเยือน',
                  child: SizedBox(
                    height: 54,
                    child: OutlinedButton(
                      onPressed: () {
                        Navigator.pushReplacementNamed(context, '/home');
                      },
                      style: OutlinedButton.styleFrom(
                        side: BorderSide(
                          color: isHighContrast ? Colors.white : Theme.of(context).colorScheme.primary,
                          width: 1.5,
                        ),
                        foregroundColor: isHighContrast ? Colors.white : Theme.of(context).colorScheme.primary,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: Text(
                        'ใช้งานแบบผู้มาเยือน',
                        style: TextStyle(
                          fontSize: 16 * acc.fontScale,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
