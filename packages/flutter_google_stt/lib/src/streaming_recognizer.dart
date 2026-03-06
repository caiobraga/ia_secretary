import 'dart:async';
import 'dart:typed_data';
import 'package:grpc/grpc.dart';
import 'speech_grpc.dart';

/// gRPC streaming recognizer using Google Cloud Speech-to-Text streaming API
class StreamingRecognizer {
  StreamController<Map<String, dynamic>>? _transcriptController;
  bool _isStreaming = false;
  String? _accessToken;
  String? _languageCode;
  int? _sampleRateHertz;

  ClientChannel? _channel;
  ResponseStream<StreamingRecognizeResponse>? _responseStream;
  StreamController<StreamingRecognizeRequest>? _requestController;

  Timer? _audioActivityTimer;

  /// Stream of transcription results
  Stream<Map<String, dynamic>> get transcriptStream =>
      _transcriptController?.stream ?? const Stream.empty();

  /// Whether the recognizer is currently streaming
  bool get isStreaming => _isStreaming;

  /// Start streaming recognition using Google Cloud Speech-to-Text gRPC API
  Future<void> startStreaming({
    required String accessToken,
    required String languageCode,
    required int sampleRateHertz,
  }) async {
    if (_isStreaming) {
      return;
    }

    try {
      _transcriptController =
          StreamController<Map<String, dynamic>>.broadcast();

      // Store configuration for gRPC calls
      _accessToken = accessToken;
      _languageCode = languageCode;
      _sampleRateHertz = sampleRateHertz;

      // Create gRPC channel to Google Cloud Speech-to-Text
      _channel = ClientChannel(
        'speech.googleapis.com',
        port: 443,
        options: ChannelOptions(
          credentials: ChannelCredentials.secure(),
          codecRegistry: CodecRegistry(
            codecs: const [GzipCodec(), IdentityCodec()],
          ),
        ),
      );

      // Set up streaming call
      await _setupStreamingCall();

      _isStreaming = true;
    } catch (e) {
      _emitError('Failed to start streaming: $e');
      await stopStreaming();
    }
  }

  /// Set up the gRPC streaming call
  Future<void> _setupStreamingCall() async {
    // Create request stream controller
    _requestController = StreamController<StreamingRecognizeRequest>();

    try {
      final stub = SpeechClient(_channel!);
      final options = CallOptions(
        metadata: {'authorization': 'Bearer $_accessToken'},
      );
      _responseStream = stub.streamingRecognize(
        _requestController!.stream,
        options: options,
      );

      // Send initial streaming config
      await _sendInitialConfig();

      // Start listening for responses
      _listenForResponses();
    } catch (e) {
      throw Exception('Failed to setup gRPC streaming: $e');
    }
  }

  /// Send initial configuration message
  Future<void> _sendInitialConfig() async {
    // Create recognition config
    final recognitionConfig = RecognitionConfig(
      encoding: AudioEncoding.LINEAR16,
      sampleRateHertz: _sampleRateHertz!,
      languageCode: _languageCode!,
      enableAutomaticPunctuation: true,
      model: 'latest_long',
    );

    // Create streaming config
    final streamingConfig = StreamingRecognitionConfig(
      config: recognitionConfig,
      interimResults: true,
    );

    // Create initial request with streaming config
    final initialRequest = StreamingRecognizeRequest(
      streamingConfig: streamingConfig,
    );

    _requestController?.add(initialRequest);
  }

  /// Listen for gRPC responses
  void _listenForResponses() {
    _responseStream?.listen(
      (response) {
        _handleStreamingResponse(response);
      },
      onError: (error) {
        _emitError('gRPC stream error: $error');
        _isStreaming = false;
        _requestController?.close();
        _requestController = null;
      },
      onDone: () {
        _isStreaming = false;
        _requestController?.close();
        _requestController = null;
      },
    );
  }

  /// Handle streaming response from gRPC
  void _handleStreamingResponse(StreamingRecognizeResponse response) {
    try {
      // Check for errors
      if (response.hasError()) {
        _emitError('Speech recognition error: ${response.error}');
        return;
      }

      // Process all results (API can return multiple per response, e.g. after pause)
      final results = response.results;
      for (final result in results) {
        final alternatives = result.alternatives;
        if (alternatives.isEmpty) continue;

        final alternative = alternatives.first;
        final transcript = alternative.transcript;
        final confidence = alternative.confidence;
        final isFinal = result.isFinal;

        if (transcript.isNotEmpty) {
          _emitTranscript(transcript, isFinal, confidence);
        }
      }
    } catch (e) {
      _emitError('Error processing response: $e');
    }
  }

  /// Stop streaming recognition
  Future<void> stopStreaming() async {
    if (!_isStreaming) {
      return;
    }

    _isStreaming = false;

    try {
      // Cancel audio activity timer
      _audioActivityTimer?.cancel();
      _audioActivityTimer = null;

      await _requestController?.close();
      _requestController = null;

      await _channel?.shutdown();
      _channel = null;

      _responseStream = null;
    } catch (e) {
      // Ignore cleanup errors
    }
  }

  /// Send audio data for processing via gRPC
  void sendAudioData(Uint8List audioData) {
    if (!_isStreaming || _requestController == null) {
      return;
    }

    try {
      // Create audio request
      final audioRequest = StreamingRecognizeRequest(audioContent: audioData);

      _requestController!.add(audioRequest);
    } catch (e) {
      _emitError('Error sending audio data: $e');
    }
  }

  /// Emit transcript to stream
  void _emitTranscript(String transcript, bool isFinal, double confidence) {
    _transcriptController?.add({
      'transcript': transcript,
      'isFinal': isFinal,
      'confidence': confidence,
    });
  }

  /// Emit error to stream
  void _emitError(String error) {
    _transcriptController?.add({'error': error, 'isFinal': true});
  }

  /// Dispose of resources
  Future<void> dispose() async {
    await stopStreaming();
    await _transcriptController?.close();
    _transcriptController = null;
  }
}
