import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'api_client.dart';
import 'web_storage.dart';

class AccessibilityState {
  final String accessibilityMode; // 'visual', 'wheelchair', 'speech_hearing'
  final bool voiceEnabled;
  final bool hapticEnabled;
  final bool highContrast;
  final double fontScale;
  final String language;
  final String userName;
  final String userEmail;

  const AccessibilityState({
    required this.accessibilityMode,
    this.voiceEnabled = true,
    this.hapticEnabled = true,
    this.highContrast = false,
    this.fontScale = 1.0,
    this.language = 'th',
    this.userName = 'ผู้ใช้งาน',
    this.userEmail = '',
  });

  AccessibilityState copyWith({
    String? accessibilityMode,
    bool? voiceEnabled,
    bool? hapticEnabled,
    bool? highContrast,
    double? fontScale,
    String? language,
    String? userName,
    String? userEmail,
  }) {
    return AccessibilityState(
      accessibilityMode: accessibilityMode ?? this.accessibilityMode,
      voiceEnabled: voiceEnabled ?? this.voiceEnabled,
      hapticEnabled: hapticEnabled ?? this.hapticEnabled,
      highContrast: highContrast ?? this.highContrast,
      fontScale: fontScale ?? this.fontScale,
      language: language ?? this.language,
      userName: userName ?? this.userName,
      userEmail: userEmail ?? this.userEmail,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'accessibility_mode': accessibilityMode,
      'voice_enabled': voiceEnabled,
      'haptic_enabled': hapticEnabled,
      'high_contrast': highContrast,
      'font_scale': fontScale,
      'language': language,
    };
  }
}

class AccessibilityNotifier extends StateNotifier<AccessibilityState> {
  final ApiClient _apiClient;
  Timer? _debounceTimer;

  AccessibilityNotifier({ApiClient? apiClient})
      : _apiClient = apiClient ?? ApiClient(),
        super(const AccessibilityState(accessibilityMode: 'wheelchair')) {
    _loadFromLocal();
  }

  /// Load saved preferences from SharedPreferences on startup
  Future<void> _loadFromLocal() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      state = AccessibilityState(
        accessibilityMode: prefs.getString('acc_mode') ?? 'wheelchair',
        voiceEnabled: prefs.getBool('voice_enabled') ?? true,
        hapticEnabled: prefs.getBool('haptic_enabled') ?? true,
        highContrast: prefs.getBool('high_contrast') ?? false,
        fontScale: prefs.getDouble('font_scale') ?? 1.0,
        language: prefs.getString('language') ?? 'th',
        userName: prefs.getString('user_name') ?? 'ผู้ใช้งาน',
        userEmail: prefs.getString('user_email') ?? '',
      );
    } catch (e) {
      if (kDebugMode) print('Failed to load local prefs: $e');
    }
  }

  /// Persist current state to SharedPreferences
  Future<void> _saveToLocal() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('acc_mode', state.accessibilityMode);
      await prefs.setBool('voice_enabled', state.voiceEnabled);
      await prefs.setBool('haptic_enabled', state.hapticEnabled);
      await prefs.setBool('high_contrast', state.highContrast);
      await prefs.setDouble('font_scale', state.fontScale);
      await prefs.setString('language', state.language);
      await prefs.setString('user_name', state.userName);
      await prefs.setString('user_email', state.userEmail);
    } catch (e) {
      if (kDebugMode) print('Failed to save local prefs: $e');
    }
  }

  /// Sync state modifications to FastAPI backend with debounce
  void _syncToBackend() {
    _saveToLocal();
    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 500), () async {
      try {
        await _apiClient.updatePreferences(state.toJson());
        if (kDebugMode) {
          print('Persisted accessibility settings to backend.');
        }
      } catch (e) {
        if (kDebugMode) {
          print('Backend preferences sync failed: $e');
        }
      }
    });
  }

  void setMode(String mode) {
    if (mode == 'visual') {
      state = state.copyWith(
        accessibilityMode: mode,
        voiceEnabled: true,
        highContrast: true,
        fontScale: 1.0,
      );
      updateWebPreference('high_contrast', 'true');
      updateWebPreference('theme', 'dark');
    } else if (mode == 'wheelchair') {
      state = state.copyWith(
        accessibilityMode: mode,
        voiceEnabled: false,
        highContrast: false,
        fontScale: 1.0,
      );
      updateWebPreference('high_contrast', 'false');
      updateWebPreference('theme', 'light');
    } else if (mode == 'speech_hearing') {
      state = state.copyWith(
        accessibilityMode: mode,
        voiceEnabled: false,
        highContrast: false,
        fontScale: 1.0,
      );
      updateWebPreference('high_contrast', 'false');
      updateWebPreference('theme', 'light');
    } else {
      state = state.copyWith(accessibilityMode: mode);
    }
    _syncToBackend();
  }

  void toggleVoice(bool enabled) {
    state = state.copyWith(voiceEnabled: enabled);
    _syncToBackend();
  }

  void toggleHaptic(bool enabled) {
    state = state.copyWith(hapticEnabled: enabled);
    _syncToBackend();
  }

  void toggleHighContrast(bool enabled) {
    state = state.copyWith(highContrast: enabled);
    updateWebPreference('high_contrast', enabled.toString());
    updateWebPreference('theme', enabled ? 'dark' : 'light');
    _syncToBackend();
  }

  void setFontScale(double scale) {
    state = state.copyWith(fontScale: scale);
    _syncToBackend();
  }

  void setLanguage(String lang) {
    state = state.copyWith(language: lang);
    _syncToBackend();
  }

  void setUserInfo(String name, String email) {
    state = state.copyWith(userName: name, userEmail: email);
    _saveToLocal();
  }

  void logout() {
    state = const AccessibilityState(accessibilityMode: 'wheelchair');
    _saveToLocal();
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    super.dispose();
  }
}

// Global provider for accessing and modifying accessibility state
final accessibilityProvider = StateNotifierProvider<AccessibilityNotifier, AccessibilityState>((ref) {
  return AccessibilityNotifier();
});
