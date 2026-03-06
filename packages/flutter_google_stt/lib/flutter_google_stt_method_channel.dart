import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'flutter_google_stt_platform_interface.dart';
import 'flutter_google_stt.dart';

/// An implementation of [FlutterGoogleSttPlatform] that uses method channels.
class MethodChannelFlutterGoogleStt extends FlutterGoogleSttPlatform {
  /// The method channel used to interact with the native platform.
  @visibleForTesting
  final methodChannel = const MethodChannel('flutter_google_stt');

  static bool _isInitialized = false;

  MethodChannelFlutterGoogleStt() {
    _initializeMethodCallHandler();
  }

  void _initializeMethodCallHandler() {
    if (!_isInitialized) {
      try {
        methodChannel.setMethodCallHandler(_handleMethodCall);
        _isInitialized = true;
      } catch (e) {
        // In test environment or when binary messenger is not ready
        // This is acceptable for testing
        if (kDebugMode) {
          print('Method call handler initialization skipped: $e');
        }
      }
    }
  }

  Future<dynamic> _handleMethodCall(MethodCall call) async {
    switch (call.method) {
      case 'onTranscript':
        final String transcript = call.arguments['transcript'] as String;
        final bool isFinal = call.arguments['isFinal'] as bool;
        // ignore: deprecated_member_use_from_same_package
        FlutterGoogleStt.onTranscriptReceived(transcript, isFinal);
        break;
      case 'onAudioData':
        final List<int> audioData = List<int>.from(call.arguments);
        FlutterGoogleStt.onAudioDataReceived(audioData);
        break;
      case 'onError':
        final String error = call.arguments as String;
        FlutterGoogleStt.onErrorReceived(error);
        break;
      default:
        throw PlatformException(
          code: 'Unimplemented',
          details: 'Method ${call.method} is not implemented',
        );
    }
  }

  @override
  Future<bool> initialize({
    required String accessToken,
    String languageCode = 'en-US',
    int sampleRateHertz = 16000,
  }) async {
    final bool? result = await methodChannel.invokeMethod<bool>('initialize', {
      'accessToken': accessToken,
      'languageCode': languageCode,
      'sampleRateHertz': sampleRateHertz,
    });
    return result ?? false;
  }

  @override
  Future<bool> startListening() async {
    final bool? result = await methodChannel.invokeMethod<bool>(
      'startListening',
    );
    return result ?? false;
  }

  @override
  Future<bool> stopListening() async {
    final bool? result = await methodChannel.invokeMethod<bool>(
      'stopListening',
    );
    return result ?? false;
  }

  @override
  Future<bool> isListening() async {
    final bool? result = await methodChannel.invokeMethod<bool>('isListening');
    return result ?? false;
  }

  @override
  Future<bool> hasMicrophonePermission() async {
    final bool? result = await methodChannel.invokeMethod<bool>(
      'hasMicrophonePermission',
    );
    return result ?? false;
  }

  @override
  Future<bool> requestMicrophonePermission() async {
    final bool? result = await methodChannel.invokeMethod<bool>(
      'requestMicrophonePermission',
    );
    return result ?? false;
  }
}
