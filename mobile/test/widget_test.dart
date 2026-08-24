import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:accessibility_assistant/main.dart';
import 'package:accessibility_assistant/core/api_client.dart';
import 'package:accessibility_assistant/features/onboarding/onboarding_screen.dart';

void main() {
  testWidgets('App starts with SplashScreen rendering title and subtitle', (WidgetTester tester) async {
    // Build our app and trigger a frame.
    await tester.pumpWidget(
      const ProviderScope(
        child: AccessibilityAssistantApp(),
      ),
    );

    // Verify SplashScreen title and subtitle elements exist on start
    expect(find.text('Accessibility Assistant'), findsOneWidget);
    expect(find.text('ผู้ช่วยอัจฉริยะเพื่อการเข้าถึง'), findsOneWidget);

    // Advance time to trigger and finish the navigation delay
    await tester.pump(const Duration(seconds: 2));
    await tester.pump(const Duration(milliseconds: 500));
  });

  testWidgets('OnboardingScreen renders the first slide elements', (WidgetTester tester) async {
    // Build OnboardingScreen directly
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(
          home: OnboardingScreen(),
        ),
      ),
    );

    // Verify first slide title and navigation buttons
    expect(find.text('ระบบคำแนะนำทางสายตา'), findsOneWidget);
    expect(find.text('ข้าม'), findsOneWidget);
    expect(find.text('ถัดไป'), findsOneWidget);
  });

  test('ApiClient can parse default endpoint base url config', () {
    final client = ApiClient(baseUrl: 'http://localhost:8000');
    expect(client.baseUrl, 'http://localhost:8000');
  });
}
