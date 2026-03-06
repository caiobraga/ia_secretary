import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_google_stt/flutter_google_stt_method_channel.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  MethodChannelFlutterGoogleStt platform = MethodChannelFlutterGoogleStt();
  const MethodChannel channel = MethodChannel('flutter_google_stt');

  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (MethodCall methodCall) async {
          switch (methodCall.method) {
            case 'initialize':
              return true;
            case 'startListening':
              return true;
            case 'stopListening':
              return true;
            case 'isListening':
              return false;
            case 'hasMicrophonePermission':
              return true;
            case 'requestMicrophonePermission':
              return true;
            default:
              throw PlatformException(code: 'UNIMPLEMENTED');
          }
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('initialize', () async {
    expect(await platform.initialize(accessToken: 'test-token'), true);
  });

  test('microphone permission check', () async {
    expect(await platform.hasMicrophonePermission(), true);
  });

  test('start and stop listening', () async {
    expect(await platform.startListening(), true);
    expect(await platform.stopListening(), true);
  });
}
