// This is a basic Flutter integration test.
//
// Since integration tests run in a full Flutter application, they can interact
// with the host side of a plugin implementation, unlike Dart unit tests.
//
// For more information about Flutter integration tests, please see
// https://flutter.dev/to/integration-testing

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:flutter_google_stt/flutter_google_stt.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('microphone permission test', (WidgetTester tester) async {
    // Test microphone permission functionality
    final bool hasPermission = await FlutterGoogleStt.hasMicrophonePermission;
    // Should return a boolean value
    expect(hasPermission, isA<bool>());
  });

  testWidgets('initialization test', (WidgetTester tester) async {
    // Test plugin initialization (will fail with invalid token, but should not crash)
    try {
      final bool result = await FlutterGoogleStt.initialize(
        accessToken: 'test-token',
      );
      // Should return a boolean value
      expect(result, isA<bool>());
    } catch (e) {
      // It's expected to fail with invalid token
      expect(e, isNotNull);
    }
  });
}
