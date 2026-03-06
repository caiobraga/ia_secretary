import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_google_stt/flutter_google_stt.dart';
import 'package:flutter_google_stt/flutter_google_stt_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

class MockFlutterGoogleSttPlatform
    with MockPlatformInterfaceMixin
    implements FlutterGoogleSttPlatform {
  @override
  Future<bool> initialize({
    required String accessToken,
    String languageCode = 'en-US',
    int sampleRateHertz = 16000,
  }) => Future.value(true);

  @override
  Future<bool> startListening() => Future.value(true);

  @override
  Future<bool> stopListening() => Future.value(true);

  @override
  Future<bool> isListening() => Future.value(false);

  @override
  Future<bool> hasMicrophonePermission() => Future.value(true);

  @override
  Future<bool> requestMicrophonePermission() => Future.value(true);
}

void main() {
  group('FlutterGoogleStt', () {
    late MockFlutterGoogleSttPlatform mockPlatform;

    setUp(() {
      mockPlatform = MockFlutterGoogleSttPlatform();
      FlutterGoogleSttPlatform.instance = mockPlatform;
    });

    test('initialize', () async {
      expect(
        await FlutterGoogleStt.initialize(accessToken: 'test-token'),
        true,
      );
    });

    test('microphone permission check', () async {
      expect(await FlutterGoogleStt.hasMicrophonePermission, true);
    });

    test('start and stop listening', () async {
      expect(await FlutterGoogleStt.startListening((text, isFinal) {}), true);
      expect(await FlutterGoogleStt.stopListening(), true);
    });

    test('is listening check', () async {
      expect(await FlutterGoogleStt.isListening, false);
    });
  });
}
