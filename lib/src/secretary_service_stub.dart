// Web-only implementation: no Vosk/Whisper/TFLite (dart:ffi not available on web).
// Uses speech_to_text only.
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:speech_to_text/speech_to_text.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'debug_log.dart';
import 'remote_listen_ui_state.dart';
import 'voice_commands.dart';

/// Sends transcribed speech to Supabase `voice_transcripts` table.
class SecretarySupabaseClient {
  static const String _tableName = 'voice_transcripts';

  Future<void> sendTranscript(String text, {bool isFinal = true}) async {
    if (text.trim().isEmpty) return;
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null) {
      debugLog('Supabase', 'no user signed in, skipping transcript');
      return;
    }
    final body = {
      'user_id': userId,
      'text': text,
      'is_final': isFinal,
    };
    try {
      await Supabase.instance.client.from(_tableName).insert(body);
      debugLog('Supabase', 'insert voice_transcripts ok: is_final=$isFinal');
    } catch (e) {
      debugLog('Supabase', 'sendTranscript error: $e');
    }
  }
}

/// Web: only speech_to_text (no Vosk/Whisper/TFLite).
class SecretaryVoiceService {
  SecretaryVoiceService({
    SecretarySupabaseClient? apiClient,
    this.localeId = 'pt_BR',
    String? voskModelUrl,
    this.voskModelAsset,
    this.preferSystemSpeechToText = false,
    this.preferGoogleCloudStt = false,
    this.googleCloudAccessToken,
    this.googleCloudSpeechLanguage = 'pt-BR',
    this.preferRemoteStt = false,
    this.remoteSttDeferUntilWakeWord = false,
    this.remoteSttUrl,
    this.remoteSttToken,
    this.remoteSttLanguage = 'pt',
    this.remoteSttPrompt,
    this.remoteSttVadFilter = true,
    this.remoteSttChunkSeconds = 2.0,
    this.remoteSttTimeoutSeconds = 180,
    this.useTfliteAudio = false,
    this.tfliteModelAsset = 'assets/tflite_audio_model.tflite',
    this.tfliteLabelAsset = 'assets/tflite_audio_labels.txt',
    this.tfliteInputType = 'rawAudio',
    this.onWakeWordDetected,
    this.onTranscript,
    this.onLoadingModel,
    this.onRemoteListenUi,
    this.remoteSttMaxSegmentSeconds = 15,
    this.remoteSttSilenceEndMs = 700,
    this.remoteSttMinSegmentMs = 400,
    this.remoteSttMaxLeadSilenceMs = 12000,
  }) : _api = apiClient ?? SecretarySupabaseClient();

  final SecretarySupabaseClient _api;
  final String localeId;
  final VoidCallback? onWakeWordDetected;
  final void Function(String text, bool isFinal)? onTranscript;
  final void Function(bool isLoading, String? message)? onLoadingModel;
  final void Function(RemoteListenUiState state)? onRemoteListenUi;
  final String? voskModelAsset;
  final bool preferSystemSpeechToText;
  final bool preferGoogleCloudStt;
  final String? googleCloudAccessToken;
  final String googleCloudSpeechLanguage;
  final bool preferRemoteStt;
  final bool remoteSttDeferUntilWakeWord;
  final String? remoteSttUrl;
  final String? remoteSttToken;
  final String remoteSttLanguage;
  final String? remoteSttPrompt;
  final bool remoteSttVadFilter;
  final double remoteSttMaxSegmentSeconds;
  final int remoteSttSilenceEndMs;
  final int remoteSttMinSegmentMs;
  final int remoteSttMaxLeadSilenceMs;
  @Deprecated('Use remoteSttMaxSegmentSeconds')
  final double remoteSttChunkSeconds;
  final int remoteSttTimeoutSeconds;
  final bool useTfliteAudio;
  final String tfliteModelAsset;
  final String tfliteLabelAsset;
  final String tfliteInputType;

  final SpeechToText _stt = SpeechToText();
  bool _isListening = false;
  bool _isStopped = false;
  String _engine = 'stt';
  Future<bool>? _initFuture;

  static const Duration _commitDelayPartialStt = Duration(milliseconds: 4000);
  DateTime? _wakeWordCooldownUntil;
  static const Duration _wakeWordCooldown = Duration(seconds: 5);
  String _phraseBuffer = '';
  Timer? _commitTimer;

  bool get isListening => _isListening;
  String get engine => _engine;

  static const String voskSmallPtAsset = 'assets/models/vosk-model-small-pt-0.3.zip';
  static String get voskSmallPtUrl =>
      'https://alphacephei.com/vosk/models/vosk-model-small-pt-0.3.zip';

  Future<bool> init() async {
    if (_initFuture != null) return _initFuture!;
    _initFuture = _stt.initialize(
      onStatus: (status) => debugLog('Voice', 'status=$status'),
      onError: (error) => debugLog('Voice', 'error=$error'),
    ).then((ok) {
      _engine = 'stt';
      debugPrint('[Voice] Motor: speech_to_text (web)');
      return ok;
    });
    return _initFuture!;
  }

  void startListening() {
    if (_isListening || _isStopped) return;
    _isListening = true;
    debugPrint('[Voice] Iniciando escuta (speech_to_text, web)');
    _listen();
  }

  void _listen() async {
    if (!_isListening || _isStopped) return;
    _stt.listen(
      onResult: (result) => _handleTranscript(result.recognizedWords.trim(), result.finalResult),
      listenFor: const Duration(seconds: 120),
      pauseFor: const Duration(seconds: 4),
      localeId: localeId,
      listenOptions: SpeechListenOptions(
        partialResults: true,
        listenMode: ListenMode.dictation,
        onDevice: true,
        cancelOnError: false,
        enableHapticFeedback: false,
      ),
    );
  }

  void _handleTranscript(String text, bool isFinal) {
    final t = correctSttText(text).trim();
    if (t.isEmpty) return;
    if (_isGrpcOrErrorResponse(t)) return;
    if (t.isNotEmpty && isWakeWord(t)) {
      final inCooldown = _wakeWordCooldownUntil != null && DateTime.now().isBefore(_wakeWordCooldownUntil!);
      if (!inCooldown) {
        onWakeWordDetected?.call();
        _wakeWordCooldownUntil = DateTime.now().add(_wakeWordCooldown);
      }
    }
    if (isFinal) {
      _commitTimer?.cancel();
      _phraseBuffer = t;
      _commitPhraseWith(t);
    } else {
      final changed = t != _phraseBuffer;
      _phraseBuffer = t;
      onTranscript?.call(t, false);
      if (changed) {
        _commitTimer?.cancel();
        _commitTimer = Timer(_commitDelayPartialStt, () => _commitPhraseWith(_phraseBuffer));
      } else if (_commitTimer == null) {
        _commitTimer = Timer(_commitDelayPartialStt, () => _commitPhraseWith(_phraseBuffer));
      }
    }
  }

  void _commitPhraseWith(String text) {
    _commitTimer?.cancel();
    _commitTimer = null;
    final phrase = text.trim();
    _phraseBuffer = '';
    if (phrase.isEmpty || !_isListening || _isStopped) return;
    if (phrase.length < 10 && !_looksLikeShortCommand(phrase)) return;
    _api.sendTranscript(phrase, isFinal: true);
    onTranscript?.call(phrase, true);
  }

  bool _isGrpcOrErrorResponse(String text) {
    final lower = text.toLowerCase();
    return lower.startsWith('error:') || lower.contains('grpc ') ||
        lower.contains('permission_denied') || lower.contains('speech.googleapis.com');
  }

  bool _looksLikeShortCommand(String phrase) {
    final n = phrase.toLowerCase().trim();
    return n == 'sair' || n == 'fechar' || n == 'clima' || n == 'menu' || n == 'horas' ||
        n == 'voltar' || n == 'tchau' || n == 'minimizar' || n == 'ava' || n == 'secretaria' ||
        n == 'quais' || n == 'quais as' || n == 'quais reunioes' || n == 'quais lembretes' ||
        n == 'que horas' || n == 'lista' || n == 'listar' || n == 'mostre' || n == 'mostrar' || n == 'ver' ||
        n == 'reunioes' || n == 'reuniao' || n == 'agenda' || n == 'notas' || n == 'calendario' ||
        n == 'lembretes' || n == 'lembrete' || n == 'compromissos' || n == 'eventos' ||
        n == 'hoje' || n == 'amanha' || n == 'essa semana' || n == 'minha agenda' ||
        n == 'o que tenho' || n == 'que tenho' || n == 'tenho hoje' || n == 'tenho amanha' ||
        n == 'criar' || n == 'marque' || n == 'agende' || n == 'cancelar' || n == 'remarcar' ||
        n == 'anotar' || n == 'tome notas' || n == 'participantes' || n == 'daily' || n == 'stand up';
  }

  Future<void> stopListening() async {
    _isStopped = true;
    _isListening = false;
    _commitTimer?.cancel();
    _wakeWordCooldownUntil = null;
    if (_phraseBuffer.trim().isNotEmpty) {
      _api.sendTranscript(_phraseBuffer.trim(), isFinal: true);
      onTranscript?.call(_phraseBuffer.trim(), true);
      _phraseBuffer = '';
    }
    await _stt.stop();
  }

  void resumeListening() {
    if (_isListening) return;
    _isStopped = false;
    _isListening = true;
    _listen();
  }

  Future<void> restartListening() async {
    if (_isStopped) return;
    await _stt.stop();
    _isListening = true;
    _listen();
  }
}
