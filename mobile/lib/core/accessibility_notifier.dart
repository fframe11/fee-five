import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'api_client.dart';
import 'web_storage.dart';
import 'services/haptic_service.dart';

class AccessibilityState {
  final String accessibilityMode; // 'visual', 'wheelchair', 'speech_hearing'
  final bool voiceEnabled;
  final bool hapticEnabled;
  final bool highContrast;
  final bool colorBlind;
  final double fontScale;
  final String language;
  final String userName;
  final String userEmail;

  // New Voice & Haptic Specific Settings for Blind/TAM AI Mode
  final double speechRate; // 0.8 - 1.5 (default 1.0)
  final String alertDetailLevel; // 'brief' (default), 'detailed'
  final bool autoCameraOnHighRisk; // default true
  final int earlyAlertDistanceMeters; // 15, 25 (default), 35
  final String hapticIntensity; // 'off', 'light', 'medium', 'strong' (default)
  final bool vibrationOnlyMode; // default false (silent navigation mode)

  const AccessibilityState({
    required this.accessibilityMode,
    this.voiceEnabled = true,
    this.hapticEnabled = true,
    this.highContrast = false,
    this.colorBlind = false,
    this.fontScale = 1.0,
    this.language = 'th',
    this.userName = 'ผู้ใช้งาน',
    this.userEmail = '',
    this.speechRate = 1.0,
    this.alertDetailLevel = 'brief',
    this.autoCameraOnHighRisk = true,
    this.earlyAlertDistanceMeters = 25,
    this.hapticIntensity = 'strong',
    this.vibrationOnlyMode = false,
  });

  AccessibilityState copyWith({
    String? accessibilityMode,
    bool? voiceEnabled,
    bool? hapticEnabled,
    bool? highContrast,
    bool? colorBlind,
    double? fontScale,
    String? language,
    String? userName,
    String? userEmail,
    double? speechRate,
    String? alertDetailLevel,
    bool? autoCameraOnHighRisk,
    int? earlyAlertDistanceMeters,
    String? hapticIntensity,
    bool? vibrationOnlyMode,
  }) {
    return AccessibilityState(
      accessibilityMode: accessibilityMode ?? this.accessibilityMode,
      voiceEnabled: voiceEnabled ?? this.voiceEnabled,
      hapticEnabled: hapticEnabled ?? this.hapticEnabled,
      highContrast: highContrast ?? this.highContrast,
      colorBlind: colorBlind ?? this.colorBlind,
      fontScale: fontScale ?? this.fontScale,
      language: language ?? this.language,
      userName: userName ?? this.userName,
      userEmail: userEmail ?? this.userEmail,
      speechRate: speechRate ?? this.speechRate,
      alertDetailLevel: alertDetailLevel ?? this.alertDetailLevel,
      autoCameraOnHighRisk: autoCameraOnHighRisk ?? this.autoCameraOnHighRisk,
      earlyAlertDistanceMeters: earlyAlertDistanceMeters ?? this.earlyAlertDistanceMeters,
      hapticIntensity: hapticIntensity ?? this.hapticIntensity,
      vibrationOnlyMode: vibrationOnlyMode ?? this.vibrationOnlyMode,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'accessibility_mode': accessibilityMode,
      'voice_enabled': voiceEnabled,
      'haptic_enabled': hapticEnabled,
      'high_contrast': highContrast,
      'color_blind': colorBlind,
      'font_scale': fontScale,
      'language': language,
      'speech_rate': speechRate,
      'alert_detail_level': alertDetailLevel,
      'auto_camera_on_high_risk': autoCameraOnHighRisk,
      'early_alert_distance_meters': earlyAlertDistanceMeters,
      'haptic_intensity': hapticIntensity,
      'vibration_only_mode': vibrationOnlyMode,
    };
  }
}

class AccessibilityNotifier extends StateNotifier<AccessibilityState> {
  final ApiClient _apiClient;
  Timer? _debounceTimer;

  AccessibilityNotifier({ApiClient? apiClient})
      : _apiClient = apiClient ?? ApiClient(),
        super(const AccessibilityState(accessibilityMode: 'visual')) {
    _loadFromLocal();
  }

  /// Load saved preferences from SharedPreferences on startup
  Future<void> _loadFromLocal() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final loadedState = AccessibilityState(
        accessibilityMode: 'visual',
        voiceEnabled: prefs.getBool('voice_enabled') ?? true,
        hapticEnabled: prefs.getBool('haptic_enabled') ?? true,
        highContrast: prefs.getBool('high_contrast') ?? false,
        colorBlind: prefs.getBool('color_blind') ?? false,
        fontScale: prefs.getDouble('font_scale') ?? 1.0,
        language: prefs.getString('language') ?? 'th',
        userName: prefs.getString('user_name') ?? 'ผู้ใช้งาน',
        userEmail: prefs.getString('user_email') ?? '',
        speechRate: prefs.getDouble('speech_rate') ?? 1.0,
        alertDetailLevel: prefs.getString('alert_detail_level') ?? 'brief',
        autoCameraOnHighRisk: prefs.getBool('auto_camera_on_high_risk') ?? true,
        earlyAlertDistanceMeters: prefs.getInt('early_alert_distance_meters') ?? 25,
        hapticIntensity: prefs.getString('haptic_intensity') ?? 'strong',
        vibrationOnlyMode: prefs.getBool('vibration_only_mode') ?? false,
      );
      state = loadedState;

      // Configure HapticService with loaded settings
      HapticService().configure(
        userIntensity: loadedState.hapticIntensity,
        vibrationOnlyMode: loadedState.vibrationOnlyMode,
        enabled: loadedState.hapticEnabled,
      );
    } catch (e) {
      if (kDebugMode) print('Failed to load local prefs: $e');
    }
  }

  /// Persist current state to SharedPreferences
  Future<void> _saveToLocal() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('acc_mode', 'visual');
      await prefs.setBool('voice_enabled', state.voiceEnabled);
      await prefs.setBool('haptic_enabled', state.hapticEnabled);
      await prefs.setBool('high_contrast', state.highContrast);
      await prefs.setBool('color_blind', state.colorBlind);
      await prefs.setDouble('font_scale', state.fontScale);
      await prefs.setString('language', state.language);
      await prefs.setString('user_name', state.userName);
      await prefs.setString('user_email', state.userEmail);
      await prefs.setDouble('speech_rate', state.speechRate);
      await prefs.setString('alert_detail_level', state.alertDetailLevel);
      await prefs.setBool('auto_camera_on_high_risk', state.autoCameraOnHighRisk);
      await prefs.setInt('early_alert_distance_meters', state.earlyAlertDistanceMeters);
      await prefs.setString('haptic_intensity', state.hapticIntensity);
      await prefs.setBool('vibration_only_mode', state.vibrationOnlyMode);

      // Keep HapticService in sync
      HapticService().configure(
        userIntensity: state.hapticIntensity,
        vibrationOnlyMode: state.vibrationOnlyMode,
        enabled: state.hapticEnabled,
      );
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
    state = state.copyWith(
      accessibilityMode: 'visual',
      voiceEnabled: true,
    );
    _syncToBackend();
  }

  void toggleVoice(bool enabled) {
    state = state.copyWith(voiceEnabled: enabled);
    _syncToBackend();
  }

  void toggleHaptic(bool enabled) {
    state = state.copyWith(hapticEnabled: enabled);
    HapticService().configure(enabled: enabled);
    _syncToBackend();
  }

  void setSpeechRate(double rate) {
    state = state.copyWith(speechRate: rate.clamp(0.8, 1.5));
    _syncToBackend();
  }

  void setAlertDetailLevel(String level) {
    state = state.copyWith(alertDetailLevel: level);
    _syncToBackend();
  }

  void toggleAutoCamera(bool enabled) {
    state = state.copyWith(autoCameraOnHighRisk: enabled);
    _syncToBackend();
  }

  void setEarlyAlertDistance(int distanceMeters) {
    state = state.copyWith(earlyAlertDistanceMeters: distanceMeters);
    _syncToBackend();
  }

  void setHapticIntensity(String intensity) {
    state = state.copyWith(hapticIntensity: intensity);
    HapticService().configure(userIntensity: intensity);
    _syncToBackend();
  }

  void toggleVibrationOnlyMode(bool enabled) {
    state = state.copyWith(vibrationOnlyMode: enabled);
    HapticService().configure(vibrationOnlyMode: enabled);
    _syncToBackend();
  }

  void toggleHighContrast(bool enabled) {
    state = state.copyWith(highContrast: enabled);
    updateWebPreference('high_contrast', enabled.toString());
    updateWebPreference('theme', enabled ? 'dark' : 'light');
    _syncToBackend();
  }

  void toggleColorBlind(bool enabled) {
    state = state.copyWith(colorBlind: enabled);
    updateWebPreference('color_blind', enabled.toString());
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
    state = const AccessibilityState(accessibilityMode: 'visual');
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
