import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:speech_to_text/speech_to_text.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:vosk_flutter_service/vosk_flutter.dart';

import 'debug_log.dart';
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

/// Listens to the user continuously and sends transcripts to Supabase (Alexa-style).
/// When "secretária" is detected, [onWakeWordDetected] is called.
/// Optional [onTranscript] is called for every result (e.g. for assistant screen commands).
/// Optional [onLoadingModel] is called when loading the model (Vosk).
class SecretaryVoiceService {
  SecretaryVoiceService({
    SecretarySupabaseClient? apiClient,
    this.localeId = 'pt_BR',
    String? voskModelUrl,
    @Deprecated('Whisper removido. Usando apenas Vosk.') bool useWhisper = false,
    @Deprecated('Whisper removido.') String whisperModel = 'base',
    this.onWakeWordDetected,
    this.onTranscript,
    this.onLoadingModel,
  }) : _api = apiClient ?? SecretarySupabaseClient(),
       _voskModelUrl = (voskModelUrl == null || voskModelUrl.trim().isEmpty)
           ? _defaultVoskModelUrl
           : voskModelUrl.trim();

  final SecretarySupabaseClient _api;
  final String localeId;
  final VoidCallback? onWakeWordDetected;
  final void Function(String text, bool isFinal)? onTranscript;
  /// (isLoading, message). Chamado ao carregar o modelo.
  final void Function(bool isLoading, String? message)? onLoadingModel;
  final String _voskModelUrl;

  final SpeechToText _stt = SpeechToText();
  bool _isListening = false;
  bool _isStopped = false;

  /// Motor de reconhecimento: 'vosk' ou 'stt'.
  String _engine = 'stt';
  bool _useVosk = false;
  Recognizer? _voskRecognizer;
  SpeechService? _voskSpeechService;
  final List<StreamSubscription<String>> _voskSubscriptions = [];
  Future<bool>? _initFuture;
  static const int _voskSampleRate = 16000;
  static const String _defaultVoskModelUrl =
      'https://alphacephei.com/vosk/models/vosk-model-small-pt-0.3.zip';
  static const String _largeVoskModelUrl =
      'https://alphacephei.com/vosk/models/vosk-model-pt-fb-v0.1.1-20220516_2113.zip';

  String _phraseBuffer = '';
  Timer? _commitTimer;
  static const Duration _commitDelay = Duration(milliseconds: 2000);

  DateTime? _wakeWordCooldownUntil;
  static const Duration _wakeWordCooldown = Duration(seconds: 5);

  bool get isListening => _isListening;
  String get engine => _engine;

  Future<bool> init() async {
    if (_initFuture != null) return _initFuture!;
    if (_engine == 'vosk' && _voskRecognizer != null) return true;

    _initFuture = () async {
      // Android: usa Vosk (local, sem beep, com correção de erros robusta)
      if (Platform.isAndroid) {
        try {
          debugLog('Voice', 'Trying Vosk...');
          final loader = ModelLoader();
          final modelName = _voskModelUrl.split('/').last.split('?').first.replaceAll('.zip', '');
          final alreadyOnDisk = await loader.isModelAlreadyLoaded(modelName);
          final msg = alreadyOnDisk
              ? 'Carregando modelo de voz (salvo no aparelho)...'
              : 'Baixando modelo de voz em português (só na primeira vez)...';

          Timer? delayedOverlay;
          if (onLoadingModel != null) {
            delayedOverlay = Timer(const Duration(milliseconds: 450), () {
              onLoadingModel?.call(true, msg);
              debugLog('Voice', msg);
            });
          }

          final modelPath = await loader.loadFromNetwork(_voskModelUrl, forceReload: false);
          final vosk = VoskFlutterPlugin.instance();
          final model = await vosk.createModel(modelPath);
          _voskRecognizer = await vosk.createRecognizer(
            model: model,
            sampleRate: _voskSampleRate,
          );
          await _voskRecognizer!.setMaxAlternatives(3);
          await _voskRecognizer!.setWords(words: false);
          await _voskRecognizer!.setPartialWords(partialWords: false);
          _useVosk = true;
          _engine = 'vosk';
          debugPrint('[Voice] Motor: Vosk (reconhecimento local, sem beep)');
          delayedOverlay?.cancel();
          onLoadingModel?.call(false, null);
          return true;
        } catch (e) {
          debugLog('Voice', 'Vosk init failed: $e');
          onLoadingModel?.call(false, null);
        }
      }

      // 3) Fallback final: speech_to_text
      _engine = 'stt';
      debugPrint('[Voice] Motor: reconhecimento do sistema (speech_to_text)');
      _useVosk = false;
      return _stt.initialize(
        onStatus: (status) => _onStatus(status),
        onError: (error) => _onError(error),
      );
    }();

    return _initFuture!;
  }

  static String _pickBestCandidate(List<({String text, double? confidence})> candidates) {
    final list = candidates
        .map((c) => (text: c.text.trim(), confidence: c.confidence))
        .where((c) => c.text.isNotEmpty)
        .toList();
    if (list.isEmpty) return '';

    for (final c in list) {
      if (isWakeWord(c.text)) return c.text;
    }

    final cmdCandidates = <({String text, double? confidence})>[];
    for (final c in list) {
      final cmd = parseCommand(c.text);
      if (cmd.type != VoiceCommandType.unknown) cmdCandidates.add(c);
    }
    if (cmdCandidates.isNotEmpty) {
      cmdCandidates.sort((a, b) => (b.confidence ?? -1).compareTo(a.confidence ?? -1));
      return cmdCandidates.first.text;
    }

    list.sort((a, b) => (b.confidence ?? -1).compareTo(a.confidence ?? -1));
    return list.first.text;
  }

  static String _parseVoskTranscript(String raw) {
    final s = raw.trim();
    if (s.isEmpty) return '';
    if (!s.startsWith('{')) return s;
    try {
      final map = jsonDecode(s) as Map<String, dynamic>;
      final candidates = <({String text, double? confidence})>[];
      final primary = (map['text'] ?? map['partial'] ?? '').toString().trim();
      if (primary.isNotEmpty) candidates.add((text: primary, confidence: map['confidence'] is num ? (map['confidence'] as num).toDouble() : null));

      final alternatives = map['alternatives'];
      if (alternatives is List) {
        for (final a in alternatives) {
          if (a is Map) {
            final t = (a['text'] ?? '').toString().trim();
            final conf = a['confidence'] is num ? (a['confidence'] as num).toDouble() : null;
            if (t.isNotEmpty) candidates.add((text: t, confidence: conf));
          }
        }
      }

      return _pickBestCandidate(candidates);
    } catch (_) {
      return s;
    }
  }

  static String get voskSmallPtUrl => _defaultVoskModelUrl;
  static String get voskLargePtUrl => _largeVoskModelUrl;

  void _onStatus(String status) {
    debugLog('Voice', 'status=$status');
    if (_isListening && !_isStopped && (status == 'done' || status == 'notListening')) {
      Future.delayed(const Duration(milliseconds: 800), () {
        if (_isListening && !_isStopped) _listen();
      });
    }
  }

  void _onError(dynamic error) {
    debugLog('Voice', 'error=$error');
  }

  void startListening() {
    if (_isListening || _isStopped) return;
    _isListening = true;

    if (_useVosk && _voskRecognizer != null) {
      debugPrint('[Voice] Iniciando escuta (Vosk, sem beep)');
      _startVoskListening();
    } else {
      debugPrint('[Voice] Iniciando escuta (speech_to_text)');
      _listen();
    }
  }

  Future<void> _startVoskListening() async {
    if (!_isListening || _isStopped || _voskRecognizer == null) return;
    try {
      final vosk = VoskFlutterPlugin.instance();
      _voskSpeechService = await vosk.initSpeechService(_voskRecognizer!);
      _voskSubscriptions.add(
        _voskSpeechService!.onPartial().listen((text) {
          final t = _parseVoskTranscript(text);
          if (t.isNotEmpty) _handleTranscript(t, false);
        }),
      );
      _voskSubscriptions.add(
        _voskSpeechService!.onResult().listen((text) {
          final t = _parseVoskTranscript(text);
          if (t.isNotEmpty) _handleTranscript(t, true);
        }),
      );
      await _voskSpeechService!.start();
    } catch (e) {
      debugLog('Voice', 'Vosk start error: $e');
    }
  }

  void _listen() async {
    if (!_isListening || _isStopped) return;
    _stt.listen(
      onResult: (result) => _handleTranscript(result.recognizedWords.trim(), result.finalResult),
      listenFor: const Duration(seconds: 120),
      pauseFor: const Duration(seconds: 20),
      localeId: localeId,
      listenOptions: SpeechListenOptions(
        partialResults: true,
        listenMode: ListenMode.dictation,
        cancelOnError: false,
        enableHapticFeedback: false,
      ),
    );
  }

  void _handleTranscript(String text, bool isFinal) {
    final t = text.trim();
    if (t.isEmpty) return;
    if (_isGrpcOrErrorResponse(t)) {
      debugLog('Voice', 'ignoring gRPC/error response');
      debugPrint('[Voice] Erro da API (ignorado como fala): ${t.length > 120 ? "${t.substring(0, 120)}..." : t}');
      return;
    }
    debugLog('Voice', 'result: final=$isFinal text="$t"');
    debugPrint('[Voice] Escuta: "$t" ${isFinal ? "(final)" : "(parcial)"}');

    if (t.isNotEmpty && isWakeWord(t)) {
      final inCooldown = _wakeWordCooldownUntil != null && DateTime.now().isBefore(_wakeWordCooldownUntil!);
      if (inCooldown) {
        debugLog('Voice', 'wake word em cooldown, tratando como comando');
      } else {
        debugLog('Voice', 'wake word detected: Ava/secretária');
        onWakeWordDetected?.call();
        _wakeWordCooldownUntil = DateTime.now().add(_wakeWordCooldown);
      }
    }

    onTranscript?.call(t, false);

    _phraseBuffer = t;
    _commitTimer?.cancel();
    _commitTimer = Timer(_commitDelay, _commitPhrase);
  }

  void _commitPhrase() {
    _commitTimer?.cancel();
    _commitTimer = null;
    final phrase = _phraseBuffer.trim();
    _phraseBuffer = '';
    if (phrase.isEmpty) return;
    if (!_isListening || _isStopped) return;
    if (phrase.length < 10 && !_looksLikeShortCommand(phrase)) {
      debugLog('Voice', 'ignoring short fragment: "$phrase"');
      return;
    }
    debugLog('Voice', 'commit phrase: "$phrase"');
    debugPrint('[Voice] Frase enviada (comando): "$phrase"');
    _api.sendTranscript(phrase, isFinal: true);
    onTranscript?.call(phrase, true);
  }

  bool _isGrpcOrErrorResponse(String text) {
    final lower = text.toLowerCase();
    return lower.startsWith('error:') ||
        lower.contains('grpc ') ||
        lower.contains('permission_denied') ||
        lower.contains('unauthenticated') ||
        lower.contains('quota project') ||
        lower.contains('speech.googleapis.com');
  }

  bool _looksLikeShortCommand(String phrase) {
    final n = phrase.toLowerCase().trim();
    return n == 'sair' || n == 'fechar' || n == 'clima' || n == 'menu' || n == 'horas' ||
        n == 'voltar' || n == 'tchau' || n == 'minimizar' ||
        n == 'quais' || n == 'quais as' || n == 'quais reuniões' || n == 'que horas' ||
        n == 'lista' || n == 'listar' || n == 'mostre' || n == 'mostrar';
  }

  Future<void> stopListening() async {
    _isStopped = true;
    _isListening = false;
    _commitTimer?.cancel();
    _commitTimer = null;
    _wakeWordCooldownUntil = null;
    if (_phraseBuffer.trim().isNotEmpty) {
      _api.sendTranscript(_phraseBuffer.trim(), isFinal: true);
      onTranscript?.call(_phraseBuffer.trim(), true);
      _phraseBuffer = '';
    }

    if (_useVosk) {
      for (final sub in _voskSubscriptions) {
        await sub.cancel();
      }
      _voskSubscriptions.clear();
      await _voskSpeechService?.stop();
      await _voskSpeechService?.dispose();
      _voskSpeechService = null;
    } else {
      await _stt.stop();
    }
  }

  void resumeListening() {
    if (_isListening) return;
    _isStopped = false;
    _isListening = true;

    if (_useVosk && _voskRecognizer != null) {
      debugLog('Voice', 'resumeListening: Vosk');
      _startVoskListening();
    } else {
      debugLog('Voice', 'resumeListening: speech_to_text');
      _listen();
    }
  }

  Future<void> restartListening() async {
    if (_isStopped) return;

    if (_useVosk) {
      for (final sub in _voskSubscriptions) {
        await sub.cancel();
      }
      _voskSubscriptions.clear();
      await _voskSpeechService?.stop();
      await _voskSpeechService?.dispose();
      _voskSpeechService = null;
      _isListening = true;
      _startVoskListening();
    } else {
      await _stt.stop();
      _isListening = true;
      _listen();
    }
  }
}
