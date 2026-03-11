// Android/iOS/Desktop: full implementation with Vosk, TFLite, speech_to_text (uses dart:io and dart:ffi).
// Whisper removido: libwhisper.so causava crash em vários dispositivos.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:speech_to_text/speech_to_text.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:tflite_audio/tflite_audio.dart';
import 'package:vosk_flutter_service/vosk_flutter.dart' as vosk;

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

/// Listens to the user continuously (Vosk, TFLite or speech_to_text). Not for web.
class SecretaryVoiceService {
  SecretaryVoiceService({
    SecretarySupabaseClient? apiClient,
    this.localeId = 'pt_BR',
    String? voskModelUrl,
    this.voskModelAsset,
    this.preferSystemSpeechToText = false,
    this.preferWhisperStt = false,
    this.useTfliteAudio = false,
    this.tfliteModelAsset = 'assets/tflite_audio_model.tflite',
    this.tfliteLabelAsset = 'assets/tflite_audio_labels.txt',
    this.tfliteInputType = 'rawAudio',
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
  final void Function(bool isLoading, String? message)? onLoadingModel;
  final String _voskModelUrl;
  final String? voskModelAsset;
  final bool preferSystemSpeechToText;
  final bool preferWhisperStt;
  final bool useTfliteAudio;
  final String tfliteModelAsset;
  final String tfliteLabelAsset;
  final String tfliteInputType;

  final SpeechToText _stt = SpeechToText();
  bool _isListening = false;
  bool _isStopped = false;
  String _engine = 'stt';
  bool _useVosk = false;
  bool _useTflite = false;
  vosk.Recognizer? _voskRecognizer;
  vosk.SpeechService? _voskSpeechService;
  final List<StreamSubscription<String>> _voskSubscriptions = [];
  StreamSubscription<Map<dynamic, dynamic>>? _tfliteSubscription;
  Future<bool>? _initFuture;

  static const Map<String, String> _tfliteLabelToPhrase = {
    'ava': 'ava',
    'secretaria': 'secretaria',
    'reunioes': 'quais reuniões tenho',
    'reuniao': 'quais reuniões tenho',
    'calendario': 'ver calendário',
    'agenda': 'ver calendário',
    'sair': 'sair',
    'fechar': 'sair',
    'notas': 'tomar notas',
    'criar reuniao': 'criar reunião',
    'marque evento': 'marque um evento',
    'clima': 'clima',
    'horas': 'que horas são',
    'menu': 'menu',
    'minimizar': 'minimizar',
  };
  static String _tfliteLabelToCommand(String label) {
    return _tfliteLabelToPhrase[label.toLowerCase().trim()] ?? label.toLowerCase().trim();
  }
  static const int _voskSampleRate = 16000;
  static const String _defaultVoskModelUrl =
      'https://alphacephei.com/vosk/models/vosk-model-small-pt-0.3.zip';
  static const String voskSmallPtAsset = 'assets/models/vosk-model-small-pt-0.3.zip';
  static String get voskSmallPtUrl => _defaultVoskModelUrl;

  String _phraseBuffer = '';
  Timer? _commitTimer;
  static const Duration _commitDelayPartial = Duration(milliseconds: 4500);
  DateTime? _wakeWordCooldownUntil;
  static const Duration _wakeWordCooldown = Duration(seconds: 5);

  bool get isListening => _isListening;
  String get engine => _engine;

  Future<bool> init() async {
    if (_initFuture != null) return _initFuture!;
    if (_engine == 'vosk' && _voskRecognizer != null) return true;
    if (_engine == 'tflite') return true;

    _initFuture = () async {
      if (Platform.isAndroid && useTfliteAudio) {
        try {
          debugLog('Voice', 'Trying TFLite Audio...');
          onLoadingModel?.call(true, 'Carregando modelo TFLite Audio...');
          await TfliteAudio.loadModel(
            model: tfliteModelAsset,
            label: tfliteLabelAsset,
            inputType: tfliteInputType,
            isAsset: true,
          );
          _useTflite = true;
          _useVosk = false;
          _engine = 'tflite';
          debugPrint('[Voice] Motor: TFLite Audio (classificação)');
          onLoadingModel?.call(false, null);
          return true;
        } catch (e) {
          debugLog('Voice', 'TFLite Audio init failed: $e');
          onLoadingModel?.call(false, null);
        }
      }

      if (Platform.isAndroid && !preferSystemSpeechToText) {
        try {
          debugLog('Voice', 'Trying Vosk...');
          final loader = vosk.ModelLoader();
          final modelName = _voskModelUrl.split('/').last.split('?').first.replaceAll('.zip', '');
          final alreadyOnDisk = await loader.isModelAlreadyLoaded(modelName);
          Timer? delayedOverlay;
          String modelPath;
          if (voskModelAsset != null && voskModelAsset!.trim().isNotEmpty) {
            try {
              final assetMsg = alreadyOnDisk
                  ? 'Carregando modelo de voz (salvo no aparelho)...'
                  : 'Carregando modelo de voz (pré-instalado)...';
              if (onLoadingModel != null) {
                delayedOverlay = Timer(const Duration(milliseconds: 450), () {
                  onLoadingModel?.call(true, assetMsg);
                });
              }
              modelPath = await loader.loadFromAssets(voskModelAsset!.trim(), forceReload: false);
            } catch (e) {
              delayedOverlay?.cancel();
              final msg = alreadyOnDisk
                  ? 'Carregando modelo de voz (salvo no aparelho)...'
                  : 'Baixando modelo de voz em português (só na primeira vez)...';
              if (onLoadingModel != null) {
                delayedOverlay = Timer(const Duration(milliseconds: 450), () => onLoadingModel?.call(true, msg));
              }
              modelPath = await loader.loadFromNetwork(_voskModelUrl, forceReload: false);
            }
          } else {
            final msg = alreadyOnDisk
                ? 'Carregando modelo de voz (salvo no aparelho)...'
                : 'Baixando modelo de voz em português (só na primeira vez)...';
            if (onLoadingModel != null) {
              delayedOverlay = Timer(const Duration(milliseconds: 450), () => onLoadingModel?.call(true, msg));
            }
            modelPath = await loader.loadFromNetwork(_voskModelUrl, forceReload: false);
          }
          final plugin = vosk.VoskFlutterPlugin.instance();
          final model = await plugin.createModel(modelPath);
          _voskRecognizer = await plugin.createRecognizer(model: model, sampleRate: _voskSampleRate);
          await _voskRecognizer!.setMaxAlternatives(5);
          await _voskRecognizer!.setWords(words: false);
          await _voskRecognizer!.setPartialWords(partialWords: false);
          _useVosk = true;
          _useTflite = false;
          _engine = 'vosk';
          delayedOverlay?.cancel();
          onLoadingModel?.call(false, null);
          return true;
        } catch (e) {
          debugLog('Voice', 'Vosk init failed: $e');
          onLoadingModel?.call(false, null);
        }
      }

      _engine = 'stt';
      _useVosk = false;
      _useTflite = false;
      debugPrint(
        preferSystemSpeechToText
            ? '[Voice] Motor: reconhecimento do sistema (fala natural)'
            : '[Voice] Motor: reconhecimento do sistema (speech_to_text)',
      );
      return _stt.initialize(
        onStatus: (status) => _onStatus(status),
        onError: (error) => _onError(error),
      );
    }();
    return _initFuture!;
  }

  static String _pickBestCandidate(List<({String text, double? confidence})> candidates) {
    final list = candidates.map((c) => (text: c.text.trim(), confidence: c.confidence)).where((c) => c.text.isNotEmpty).toList();
    if (list.isEmpty) return '';
    for (final c in list) {
      if (isWakeWord(c.text)) return c.text;
    }
    final cmdCandidates = <({String text, String corrected, double? confidence})>[];
    for (final c in list) {
      final corrected = correctSttText(c.text);
      final cmd = parseCommand(corrected);
      if (cmd.type != VoiceCommandType.unknown) {
        cmdCandidates.add((text: c.text, corrected: corrected, confidence: c.confidence));
      }
    }
    if (cmdCandidates.isNotEmpty) {
      cmdCandidates.sort((a, b) => (b.confidence ?? -1).compareTo(a.confidence ?? -1));
      return cmdCandidates.first.corrected;
    }
    list.sort((a, b) => (b.confidence ?? -1).compareTo(a.confidence ?? -1));
    return correctSttText(list.first.text);
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
    if (_useTflite) {
      _startTfliteListening();
    } else if (_useVosk && _voskRecognizer != null) {
      _startVoskListening();
    } else {
      _listen();
    }
  }

  void _startTfliteListening() {
    if (!_isListening || _isStopped) return;
    try {
      final stream = TfliteAudio.startAudioRecognition(
        sampleRate: tfliteInputType == 'rawAudio' ? 44100 : 16000,
        bufferSize: tfliteInputType == 'rawAudio' ? 22016 : 2000,
        detectionThreshold: 0.5,
        averageWindowDuration: 1200,
        suppressionTime: 1500,
      );
      _tfliteSubscription?.cancel();
      _tfliteSubscription = stream.listen((event) {
        if (!_isListening || _isStopped) return;
        final result = event['recognitionResult'];
        if (result == null || result.toString().trim().isEmpty) return;
        final label = result.toString().trim();
        if (label.toLowerCase() == 'background' || label.toLowerCase().contains('noise')) return;
        _handleTranscript(_tfliteLabelToCommand(label), true);
      }, onError: (e) => debugLog('Voice', 'TFLite stream error: $e'), onDone: () {
        if (_isListening && !_isStopped) Future.delayed(const Duration(milliseconds: 500), _startTfliteListening);
      });
    } catch (e) {
      debugLog('Voice', 'TFLite start error: $e');
    }
  }

  Future<void> _startVoskListening() async {
    if (!_isListening || _isStopped || _voskRecognizer == null) return;
    try {
      final plugin = vosk.VoskFlutterPlugin.instance();
      _voskSpeechService = await plugin.initSpeechService(_voskRecognizer!);
      _voskSubscriptions.add(_voskSpeechService!.onPartial().listen((text) {
        final t = _parseVoskTranscript(text);
        if (t.isNotEmpty) _handleTranscript(t, false);
      }));
      _voskSubscriptions.add(_voskSpeechService!.onResult().listen((text) {
        final t = _parseVoskTranscript(text);
        if (t.isNotEmpty) _handleTranscript(t, true);
      }));
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
    _phraseBuffer = t;
    if (isFinal) {
      _commitTimer?.cancel();
      _commitTimer = null;
      _commitPhraseWith(t);
    } else {
      onTranscript?.call(t, false);
      _commitTimer?.cancel();
      _commitTimer = Timer(_commitDelayPartial, () => _commitPhraseWith(_phraseBuffer));
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
        lower.contains('permission_denied') || lower.contains('unauthenticated') ||
        lower.contains('quota project') || lower.contains('speech.googleapis.com');
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
    _commitTimer = null;
    _wakeWordCooldownUntil = null;
    if (_phraseBuffer.trim().isNotEmpty) {
      _api.sendTranscript(_phraseBuffer.trim(), isFinal: true);
      onTranscript?.call(_phraseBuffer.trim(), true);
      _phraseBuffer = '';
    }
    if (_useTflite) {
      await _tfliteSubscription?.cancel();
      _tfliteSubscription = null;
      TfliteAudio.stopAudioRecognition();
    } else if (_useVosk) {
      for (final sub in _voskSubscriptions) await sub.cancel();
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
    if (_useTflite) {
      _startTfliteListening();
    } else if (_useVosk && _voskRecognizer != null) {
      _startVoskListening();
    } else {
      _listen();
    }
  }

  Future<void> restartListening() async {
    if (_isStopped) return;
    if (_useTflite) {
      await _tfliteSubscription?.cancel();
      _tfliteSubscription = null;
      TfliteAudio.stopAudioRecognition();
      _isListening = true;
      _startTfliteListening();
    } else if (_useVosk) {
      for (final sub in _voskSubscriptions) await sub.cancel();
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

