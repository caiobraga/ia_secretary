import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'flutter_google_stt_method_channel.dart';

/// Callback function for receiving transcription results
typedef TranscriptionCallback = void Function(String transcript, bool isFinal);

abstract class FlutterGoogleSttPlatform extends PlatformInterface {
  /// Constructs a FlutterGoogleSttPlatform.
  FlutterGoogleSttPlatform() : super(token: _token);

  static final Object _token = Object();

  static FlutterGoogleSttPlatform _instance = MethodChannelFlutterGoogleStt();

  /// The default instance of [FlutterGoogleSttPlatform] to use.
  ///
  /// Defaults to [MethodChannelFlutterGoogleStt].
  static FlutterGoogleSttPlatform get instance => _instance;

  /// Platform-specific implementations should set this with their own
  /// platform-specific class that extends [FlutterGoogleSttPlatform] when
  /// they register themselves.
  static set instance(FlutterGoogleSttPlatform instance) {
    PlatformInterface.verifyToken(instance, _token);
    _instance = instance;
  }

  /// Initialize the speech-to-text service with Google Cloud credentials
  Future<bool> initialize({
    required String accessToken,
    String languageCode = 'en-US',
    int sampleRateHertz = 16000,
  }) {
    throw UnimplementedError('initialize() has not been implemented.');
  }

  /// Start listening for speech input
  Future<bool> startListening() {
    throw UnimplementedError('startListening() has not been implemented.');
  }

  /// Stop listening for speech input
  Future<bool> stopListening() {
    throw UnimplementedError('stopListening() has not been implemented.');
  }

  /// Check if currently listening
  Future<bool> isListening() {
    throw UnimplementedError('isListening() has not been implemented.');
  }

  /// Check if microphone permission is granted
  Future<bool> hasMicrophonePermission() {
    throw UnimplementedError(
      'hasMicrophonePermission() has not been implemented.',
    );
  }

  /// Request microphone permission
  Future<bool> requestMicrophonePermission() {
    throw UnimplementedError(
      'requestMicrophonePermission() has not been implemented.',
    );
  }
}
