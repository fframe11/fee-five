import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:accessibility_assistant/core/accessibility_notifier.dart';
import 'package:accessibility_assistant/features/home/home_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('TAM AI AccessibilityState & HomeScreen Tests', () {
    test('AccessibilityState stores and copies Voice & Haptic options correctly', () {
      const state = AccessibilityState(accessibilityMode: 'visual');
      expect(state.speechRate, 1.0);
      expect(state.alertDetailLevel, 'brief');
      expect(state.autoCameraOnHighRisk, isTrue);
      expect(state.earlyAlertDistanceMeters, 25);
      expect(state.hapticIntensity, 'strong');
      expect(state.vibrationOnlyMode, isFalse);

      final updated = state.copyWith(
        speechRate: 1.2,
        alertDetailLevel: 'detailed',
        autoCameraOnHighRisk: false,
        earlyAlertDistanceMeters: 35,
        hapticIntensity: 'medium',
        vibrationOnlyMode: true,
      );

      expect(updated.speechRate, 1.2);
      expect(updated.alertDetailLevel, 'detailed');
      expect(updated.autoCameraOnHighRisk, isFalse);
      expect(updated.earlyAlertDistanceMeters, 35);
      expect(updated.hapticIntensity, 'medium');
      expect(updated.vibrationOnlyMode, isTrue);
    });

    testWidgets('HomeScreen renders 3 Bottom Navigation tabs and Action-First buttons', (WidgetTester tester) async {
      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: HomeScreen(),
          ),
        ),
      );

      await tester.pump(const Duration(milliseconds: 700));

      // 1. Verify 3 Bottom Navigation Tabs
      expect(find.text('หน้าแรก'), findsWidgets);
      expect(find.text('นำทางเสียง'), findsWidgets);
      expect(find.text('โปรไฟล์'), findsWidgets);

      // 2. Verify 3 Action-First Giant Buttons
      expect(find.text('🚀 เริ่มนำทางด้วยเสียง'), findsOneWidget);
      expect(find.text('📷 เปิดกล้องตรวจสิ่งกีดขวาง'), findsOneWidget);
      expect(find.text('🆘 ขอความช่วยเหลือ (SOS)'), findsOneWidget);
    });
  });
}
