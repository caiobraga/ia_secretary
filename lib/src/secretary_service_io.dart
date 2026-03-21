// Android/iOS/Desktop: full implementation with Vosk, TFLite, speech_to_text (uses dart:io and dart:ffi).
// Whisper removido: libwhisper.so causava crash em vários dispositivos.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:flutter_google_stt/flutter_google_stt.dart';
import 'package:record/record.dart';
import 'package:speech_to_text/speech_to_text.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:tflite_audio/tflite_audio.dart';
import 'package:vosk_flutter_service/vosk_flutter.dart' as vosk;

import 'debug_log.dart';
import 'remote_listen_ui_state.dart';
import 'voice_commands.dart';

class _RemoteSegmentEnd {
  const _RemoteSegmentEnd({
    required this.stopped,
    required this.heardSpeech,
    required this.skipUpload,
  });

  final bool stopped;
  final bool heardSpeech;

  /// Sem fala útil ou silêncio inicial longo: não enviar ao servidor.
  final bool skipUpload;
}

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
    this.preferGoogleCloudStt = false,
    this.googleCloudAccessToken,
    this.googleCloudSpeechLanguage = 'pt-BR',
    this.preferRemoteStt = false,
    /// Com [preferRemoteStt] e URL: até a ativação usa Vosk; depois [remoteSttUrl].
    this.remoteSttDeferUntilWakeWord = false,
    this.remoteSttUrl,
    this.remoteSttToken,
    this.remoteSttLanguage = 'pt',
    this.remoteSttPrompt,
    this.remoteSttVadFilter = true,
    this.remoteSttChunkSeconds = 1.5,
    this.remoteSttTimeoutSeconds = 180,
    this.useTfliteAudio = false,
    this.tfliteModelAsset = 'assets/tflite_audio_model.tflite',
    this.tfliteLabelAsset = 'assets/tflite_audio_labels.txt',
    this.tfliteInputType = 'rawAudio',
    this.onWakeWordDetected,
    this.onTranscript,
    this.onLoadingModel,
    this.onRemoteListenUi,
    /// Teto de duração do segmento enviado ao STT remoto (segundos). Fim antecipado após silêncio.
    this.remoteSttMaxSegmentSeconds = 15,
    /// Ms de silêncio após fala para considerar a frase terminada.
    this.remoteSttSilenceEndMs = 700,
    /// Duração mínima de gravação antes de aceitar fim por silêncio (evita cortar sílabas).
    this.remoteSttMinSegmentMs = 400,
    /// Se ainda não houve fala, aborta o segmento após estes ms (evita WAV longo só com silêncio).
    this.remoteSttMaxLeadSilenceMs = 12000,
  }) : _api = apiClient ?? SecretarySupabaseClient(),
       _voskModelUrl = (voskModelUrl == null || voskModelUrl.trim().isEmpty)
           ? _defaultVoskModelUrl
           : voskModelUrl.trim();

  final SecretarySupabaseClient _api;
  final String localeId;
  final VoidCallback? onWakeWordDetected;
  final void Function(String text, bool isFinal)? onTranscript;
  final void Function(bool isLoading, String? message)? onLoadingModel;
  final void Function(RemoteListenUiState state)? onRemoteListenUi;
  final String _voskModelUrl;
  final String? voskModelAsset;
  final bool preferSystemSpeechToText;
  /// Google Cloud Speech via microfone direto (sem beep do Android SpeechRecognizer).
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
  /// Legado: antes era o tamanho fixo do chunk. O fim do segmento é por silêncio; use [remoteSttMaxSegmentSeconds].
  final double remoteSttMaxSegmentSeconds;
  final int remoteSttSilenceEndMs;
  final int remoteSttMinSegmentMs;
  final int remoteSttMaxLeadSilenceMs;
  /// Mantido por compatibilidade com código antigo / env; não usado no loop remoto.
  @Deprecated('Use remoteSttMaxSegmentSeconds')
  final double remoteSttChunkSeconds;
  /// Tempo máximo por requisição (upload + inferência + resposta). CPU lenta / 1ª carga do modelo precisa de mais.
  final int remoteSttTimeoutSeconds;
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
  bool _useRemote = false;
  bool _useGoogleCloud = false;
  /// Após init com Vosk e [remoteSttDeferUntilWakeWord], fica true até a 1ª ativação por wake word.
  bool _pendingRemoteAfterWake = false;
  vosk.Recognizer? _voskRecognizer;
  vosk.SpeechService? _voskSpeechService;
  final List<StreamSubscription<String>> _voskSubscriptions = [];
  StreamSubscription<Map<dynamic, dynamic>>? _tfliteSubscription;
  AudioRecorder? _remoteRecorder;
  Completer<void>? _remoteStopCompleter;
  /// Incrementado em [stopListening]/restart para encerrar o loop mesmo durante `_transcribeRemote`.
  int _remoteSession = 0;
  Future<void>? _remoteLoopFuture;
  RemoteListenPhase? _lastRemoteUiPhase;
  int _lastRemoteUiLevelBucket = -1;
  DateTime _lastRemoteUiNotify = DateTime.fromMillisecondsSinceEpoch(0);
  static const RecordConfig _remoteRecordConfig = RecordConfig(
    encoder: AudioEncoder.wav,
    sampleRate: 16000,
    numChannels: 1,
  );
  /// Whisper `initial_prompt` em chunks curtos tende a **repetir** texto longo (ruído/silêncio).
  static const int _maxRemoteSttPromptChars = 96;
  Future<bool>? _initFuture;

  /// Prompt curto só para viés léxico; prompts longos são ignorados (evita "eco" do texto no STT).
  String? _effectiveRemoteSttPromptForRequest() {
    final raw = remoteSttPrompt?.trim();
    if (raw == null || raw.isEmpty) return null;
    if (raw.length > _maxRemoteSttPromptChars) {
      debugLog(
        'Voice',
        'REMOTE_STT_PROMPT ignorado (${raw.length} chars > $_maxRemoteSttPromptChars): '
        'Whisper repete prompts longos em áudio curto. Use só termos curtos (ex.: nomes, jargão).',
      );
      return null;
    }
    return raw;
  }

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
  /// Vosk manda parciais frequentes: commit mais cedo após estabilizar.
  static const Duration _commitDelayPartialVosk = Duration(milliseconds: 2400);
  /// speech_to_text do sistema costuma precisar de mais contexto antes de “fechar” a frase.
  static const Duration _commitDelayPartialStt = Duration(milliseconds: 4000);
  DateTime? _wakeWordCooldownUntil;
  static const Duration _wakeWordCooldown = Duration(seconds: 5);

  bool get isListening => _isListening;
  String get engine => _engine;

  Future<bool> init() async {
    if (_initFuture != null) return _initFuture!;
    if (_engine == 'vosk' && _voskRecognizer != null) return true;
    if (_engine == 'tflite') return true;
    if (_engine == 'remote') return true;
    if (_engine == 'google_cloud') return true;

    _initFuture = () async {
      final remoteUrl = remoteSttUrl?.trim();
      final deferRemote = preferRemoteStt &&
          remoteUrl != null &&
          remoteUrl.isNotEmpty &&
          remoteSttDeferUntilWakeWord;

      if (deferRemote) {
        debugLog(
          'Voice',
          'STT remoto adiado até "secretária" ou Ava; depois ${remoteUrl.split('?').first}',
        );
      }

      if (preferRemoteStt && remoteUrl != null && remoteUrl.isNotEmpty && !deferRemote) {
        _pendingRemoteAfterWake = false;
        debugLog('Voice', 'Trying remote STT API...');
        _remoteRecorder = AudioRecorder();
        _useRemote = true;
        _useGoogleCloud = false;
        _useTflite = false;
        _useVosk = false;
        _engine = 'remote';
        debugPrint('[Voice] Motor: STT remoto (silêncio + API)');
        return true;
      }

      final gcToken = googleCloudAccessToken?.trim();
      if (preferGoogleCloudStt &&
          gcToken != null &&
          gcToken.isNotEmpty &&
          (Platform.isAndroid || Platform.isIOS)) {
        try {
          debugLog('Voice', 'Trying Google Cloud STT (sem beep do sistema)...');
          onLoadingModel?.call(true, 'Conectando ao Google Speech...');
          final ok = await FlutterGoogleStt.initialize(
            accessToken: gcToken,
            languageCode: googleCloudSpeechLanguage,
            sampleRateHertz: 16000,
          );
          if (ok) {
            _useGoogleCloud = true;
            _useRemote = false;
            _useTflite = false;
            _useVosk = false;
            _engine = 'google_cloud';
            onLoadingModel?.call(false, null);
            debugPrint('[Voice] Motor: Google Cloud Speech (API, sem beep)');
            return true;
          }
        } catch (e) {
          debugLog('Voice', 'Google Cloud STT init failed: $e');
          onLoadingModel?.call(false, null);
        }
      }

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

      // Fase local (incl. REMOTE_STT_AFTER_WAKE_WORD) usa Vosk quando possível; só cai em speech_to_text se Vosk falhar.
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
          await _voskRecognizer!.setMaxAlternatives(8);
          await _voskRecognizer!.setWords(words: false);
          await _voskRecognizer!.setPartialWords(partialWords: false);
          _useVosk = true;
          _useGoogleCloud = false;
          _useTflite = false;
          _engine = 'vosk';
          delayedOverlay?.cancel();
          onLoadingModel?.call(false, null);
          if (deferRemote) _pendingRemoteAfterWake = true;
          return true;
        } catch (e) {
          debugLog('Voice', 'Vosk init failed: $e');
          onLoadingModel?.call(false, null);
        }
      }

      _engine = 'stt';
      _useVosk = false;
      _useTflite = false;
      _useRemote = false;
      _useGoogleCloud = false;
      debugPrint(
        preferSystemSpeechToText
            ? '[Voice] Motor: reconhecimento do sistema (fala natural)'
            : '[Voice] Motor: reconhecimento do sistema (speech_to_text)',
      );
      return _stt.initialize(
        onStatus: (status) => _onStatus(status),
        onError: (error) => _onError(error),
      ).then((ok) {
        if (ok && deferRemote) _pendingRemoteAfterWake = true;
        return ok;
      });
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
    } else if (_useRemote) {
      _startRemoteListening();
    } else if (_useGoogleCloud) {
      unawaited(_startGoogleCloudListening());
    } else if (_useVosk && _voskRecognizer != null) {
      _startVoskListening();
    } else {
      _listen();
    }
  }

  Future<void> _startGoogleCloudListening() async {
    if (!_isListening || _isStopped) return;
    try {
      await FlutterGoogleStt.startListening((String transcript, bool isFinal) {
        if (!_isListening || _isStopped) return;
        _handleTranscript(transcript, isFinal);
      });
    } catch (e) {
      debugLog('Voice', 'Google Cloud STT start error: $e');
    }
  }

  void _startRemoteListening() {
    if (!_isListening || _isStopped) return;
    if (_remoteLoopFuture != null) {
      debugLog('Voice', 'Remote STT: loop já ativo (evita gravador duplicado)');
      return;
    }
    final fut = _remoteLoopBody();
    _remoteLoopFuture = fut;
    fut.whenComplete(() {
      if (identical(_remoteLoopFuture, fut)) _remoteLoopFuture = null;
    });
  }

  Future<void> _resumeLocalListeningAfterFailedRemoteActivation() async {
    _useRemote = false;
    if (!_isListening || _isStopped) return;
    if (_voskRecognizer != null) {
      _engine = 'vosk';
      _useVosk = true;
      await _startVoskListening();
    } else {
      _engine = 'stt';
      _listen();
    }
  }

  /// Troca Vosk/speech_to_text pelo STT remoto após [isWakeWord] (secretária / Ava).
  Future<void> _activateRemoteSttAfterWake() async {
    if (_useRemote || !_isListening || _isStopped) return;
    if (!_pendingRemoteAfterWake) return;
    _pendingRemoteAfterWake = false;
    try {
      debugLog('Voice', 'Ativando STT remoto após palavra de ativação...');
      if (_useVosk) {
        for (final sub in _voskSubscriptions) {
          await sub.cancel();
        }
        _voskSubscriptions.clear();
        await _voskSpeechService?.stop();
        await _voskSpeechService?.dispose();
        _voskSpeechService = null;
        _useVosk = false;
      } else {
        await _stt.stop();
      }
      final url = remoteSttUrl?.trim();
      if (url == null || url.isEmpty) {
        debugLog('Voice', 'REMOTE_STT_URL vazio; mantendo escuta local.');
        _pendingRemoteAfterWake = true;
        await _resumeLocalListeningAfterFailedRemoteActivation();
        return;
      }
      _remoteRecorder ??= AudioRecorder();
      _useRemote = true;
      _engine = 'remote';
      debugPrint('[Voice] Motor: STT remoto (silêncio + API)');
      _startRemoteListening();
    } catch (e) {
      debugLog('Voice', 'Falha ao ativar STT remoto: $e');
      _pendingRemoteAfterWake = true;
      await _resumeLocalListeningAfterFailedRemoteActivation();
    }
  }

  void _emitRemoteListenUi(RemoteListenUiState state, {bool force = false}) {
    final c = onRemoteListenUi;
    if (c == null) return;
    final now = DateTime.now();
    if (!force) {
      if (state.phase == _lastRemoteUiPhase && state.phase == RemoteListenPhase.recording) {
        final b = (state.voiceLevel * 12).floor().clamp(0, 12);
        if (b == _lastRemoteUiLevelBucket && now.difference(_lastRemoteUiNotify).inMilliseconds < 100) {
          return;
        }
        _lastRemoteUiLevelBucket = b;
      } else {
        _lastRemoteUiLevelBucket = -1;
      }
    } else {
      _lastRemoteUiLevelBucket = -1;
    }
    _lastRemoteUiPhase = state.phase;
    _lastRemoteUiNotify = now;
    c(state);
  }

  void _emitRemoteListenIdle() {
    _emitRemoteListenUi(const RemoteListenUiState(phase: RemoteListenPhase.idle), force: true);
  }

  static double _amplitudeDbfsToLevel(double db) {
    const low = -52.0;
    const high = -14.0;
    return ((db - low) / (high - low)).clamp(0.0, 1.0);
  }

  static bool _isLikelySpeechDbfs(double db) => db > -38.0;

  Future<_RemoteSegmentEnd> _waitRemoteSegmentEnd(
    AudioRecorder recorder,
    int loopSession,
  ) async {
    final maxMs = (remoteSttMaxSegmentSeconds * 1000).round().clamp(2500, 180000);
    final silenceMs = remoteSttSilenceEndMs.clamp(200, 4000);
    final minMs = remoteSttMinSegmentMs.clamp(200, 8000);
    final leadMs = remoteSttMaxLeadSilenceMs.clamp(2000, 120000);
    final start = DateTime.now();
    final deadline = start.add(Duration(milliseconds: maxMs));

    var heardSpeech = false;
    DateTime? quietSince;

    _emitRemoteListenUi(
      const RemoteListenUiState(phase: RemoteListenPhase.recording, voiceLevel: 0),
      force: true,
    );

    while (DateTime.now().isBefore(deadline)) {
      if (_remoteSession != loopSession || !_isListening || _isStopped) {
        return _RemoteSegmentEnd(stopped: true, heardSpeech: heardSpeech, skipUpload: true);
      }

      await Future.any<void>([
        Future<void>.delayed(const Duration(milliseconds: 90)),
        _remoteStopCompleter!.future,
      ]);

      if (_remoteSession != loopSession || !_isListening || _isStopped) {
        return _RemoteSegmentEnd(stopped: true, heardSpeech: heardSpeech, skipUpload: true);
      }

      if (!heardSpeech && DateTime.now().difference(start).inMilliseconds >= leadMs) {
        return const _RemoteSegmentEnd(stopped: false, heardSpeech: false, skipUpload: true);
      }

      Amplitude a;
      try {
        a = await recorder.getAmplitude();
      } catch (_) {
        continue;
      }

      final level = _amplitudeDbfsToLevel(a.current);
      final loud = _isLikelySpeechDbfs(a.current);
      _emitRemoteListenUi(RemoteListenUiState(phase: RemoteListenPhase.recording, voiceLevel: level));

      if (loud) {
        heardSpeech = true;
        quietSince = null;
      } else if (heardSpeech) {
        final quietStart = quietSince ??= DateTime.now();
        final q = DateTime.now().difference(quietStart).inMilliseconds;
        final elapsed = DateTime.now().difference(start).inMilliseconds;
        if (q >= silenceMs && elapsed >= minMs) {
          return const _RemoteSegmentEnd(stopped: false, heardSpeech: true, skipUpload: false);
        }
      }
    }

    return _RemoteSegmentEnd(stopped: false, heardSpeech: heardSpeech, skipUpload: !heardSpeech);
  }

  Future<void> _remoteLoopBody() async {
    final loopSession = _remoteSession;
    try {
      while (_isListening && !_isStopped && _remoteSession == loopSession) {
        final endpoint = remoteSttUrl?.trim();
        if (endpoint == null || endpoint.isEmpty) break;

        _remoteStopCompleter = Completer<void>();
        final dir = await getTemporaryDirectory();
        final path = '${dir.path}/remote_stt_${DateTime.now().millisecondsSinceEpoch}.wav';
        try {
          var recorder = _remoteRecorder;
          if (recorder == null) {
            debugLog('Voice', 'Remote STT: gravador nulo; encerrando loop');
            break;
          }
          if (await recorder.hasPermission() == false) {
            debugLog('Voice', 'Remote STT: sem permissao de microfone');
            break;
          }
          try {
            await recorder.start(_remoteRecordConfig, path: path);
          } catch (e) {
            debugLog('Voice', 'Remote STT: falha ao iniciar gravação ($e); recriando gravador');
            try {
              await recorder.dispose();
            } catch (_) {}
            _remoteRecorder = AudioRecorder();
            recorder = _remoteRecorder!;
            await Future<void>.delayed(const Duration(milliseconds: 120));
            if (!_isListening || _isStopped || _remoteSession != loopSession) break;
            await recorder.start(_remoteRecordConfig, path: path);
          }

          final end = await _waitRemoteSegmentEnd(recorder, loopSession);
          if (!_isListening || _isStopped || _remoteSession != loopSession) {
            try {
              await recorder.stop();
            } catch (_) {}
            try {
              await File(path).delete();
            } catch (_) {}
            break;
          }
          if (end.stopped) {
            try {
              await recorder.stop();
            } catch (_) {}
            try {
              await File(path).delete();
            } catch (_) {}
            break;
          }

          await recorder.stop();

          if (_remoteSession != loopSession) {
            try {
              await File(path).delete();
            } catch (_) {}
            break;
          }

          if (end.skipUpload) {
            try {
              await File(path).delete();
            } catch (_) {}
            _emitRemoteListenIdle();
            continue;
          }

          _emitRemoteListenUi(
            const RemoteListenUiState(phase: RemoteListenPhase.transcribing),
            force: true,
          );
          final text = await _transcribeRemote(path);
          try {
            await File(path).delete();
          } catch (_) {}

          if (_remoteSession != loopSession || !_isListening || _isStopped) break;
          if (text.isNotEmpty) _handleTranscript(text, true);
          _emitRemoteListenIdle();
        } catch (e) {
          debugLog('Voice', 'Remote STT chunk error: $e');
          try {
            await File(path).delete();
          } catch (_) {}
          if (_isListening && !_isStopped && _remoteSession == loopSession) {
            await Future<void>.delayed(const Duration(milliseconds: 200));
          }
        }
        _remoteStopCompleter = null;
      }
    } finally {
      _emitRemoteListenIdle();
    }
  }

  Future<String> _transcribeRemote(String wavPath) async {
    final endpoint = remoteSttUrl?.trim();
    if (endpoint == null || endpoint.isEmpty) return '';
    final timeoutSec = remoteSttTimeoutSeconds.clamp(45, 600);
    try {
      return await () async {
        final request = http.MultipartRequest('POST', Uri.parse(endpoint));
        request.files.add(await http.MultipartFile.fromPath('file', wavPath));
        request.fields['language'] = remoteSttLanguage;
        request.fields['vad_filter'] = remoteSttVadFilter ? 'true' : 'false';
        final prompt = _effectiveRemoteSttPromptForRequest();
        if (prompt != null) {
          request.fields['prompt'] = prompt;
        }
        final token = remoteSttToken?.trim();
        if (token != null && token.isNotEmpty) {
          request.headers['Authorization'] = 'Bearer $token';
        }
        final streamed = await request.send();
        final body = await streamed.stream.bytesToString();
        if (streamed.statusCode < 200 || streamed.statusCode >= 300) {
          debugLog('Voice', 'Remote STT HTTP ${streamed.statusCode}: $body');
          return '';
        }
        final data = jsonDecode(body);
        if (data is Map<String, dynamic>) {
          return (data['text'] ?? '').toString().trim();
        }
        return '';
      }().timeout(
        Duration(seconds: timeoutSec),
        onTimeout: () {
          debugLog('Voice', 'Remote STT timeout após ${timeoutSec}s (aumente REMOTE_STT_TIMEOUT_SECONDS se o servidor for lento)');
          return '';
        },
      );
    } catch (e) {
      debugLog('Voice', 'Remote STT request error: $e → $endpoint');
      return '';
    }
  }

  void _signalRemoteStop() {
    _remoteStopCompleter?.complete();
  }

  void _startTfliteListening() {
    if (!_isListening || _isStopped) return;
    try {
      final stream = TfliteAudio.startAudioRecognition(
        sampleRate: tfliteInputType == 'rawAudio' ? 44100 : 16000,
        bufferSize: tfliteInputType == 'rawAudio' ? 22016 : 2000,
        detectionThreshold: 0.42,
        averageWindowDuration: 1000,
        suppressionTime: 1200,
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

  /// [speech_to_text] no Android usa `SpeechRecognizer`; o beep de início é do SO e não tem API no plugin
  /// (ver `docs/SPEECH_TO_TEXT_AND_BEEP.md`).
  void _listen() async {
    if (!_isListening || _isStopped) return;
    _stt.listen(
      onResult: (result) => _handleTranscript(result.recognizedWords.trim(), result.finalResult),
      listenFor: const Duration(seconds: 120),
      // 20s fazia o sistema demorar muito para considerar a frase “final”; 4s melhora resposta local.
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
        if (_pendingRemoteAfterWake && !_useRemote) {
          unawaited(_activateRemoteSttAfterWake());
        }
        onWakeWordDetected?.call();
        _wakeWordCooldownUntil = DateTime.now().add(_wakeWordCooldown);
      }
    }
    final partialDelay = _useVosk ? _commitDelayPartialVosk : _commitDelayPartialStt;
    if (isFinal) {
      _commitTimer?.cancel();
      _commitTimer = null;
      _phraseBuffer = t;
      _commitPhraseWith(t);
    } else {
      final changed = t != _phraseBuffer;
      _phraseBuffer = t;
      onTranscript?.call(t, false);
      // Só reinicia o timer se o texto parcial mudou: evita que ruído/Vosk oscilando impeça o commit.
      if (changed) {
        _commitTimer?.cancel();
        _commitTimer = Timer(partialDelay, () => _commitPhraseWith(_phraseBuffer));
      } else if (_commitTimer == null) {
        _commitTimer = Timer(partialDelay, () => _commitPhraseWith(_phraseBuffer));
      }
    }
  }

  void _commitPhraseWith(String text) {
    _commitTimer?.cancel();
    _commitTimer = null;
    final phrase = text.trim();
    _phraseBuffer = '';
    if (phrase.isEmpty || !_isListening || _isStopped) return;
    if (phrase.length < 8 && !_looksLikeShortCommand(phrase)) return;
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
    _signalRemoteStop();
    if (_phraseBuffer.trim().isNotEmpty) {
      _api.sendTranscript(_phraseBuffer.trim(), isFinal: true);
      onTranscript?.call(_phraseBuffer.trim(), true);
      _phraseBuffer = '';
    }
    if (_useTflite) {
      await _tfliteSubscription?.cancel();
      _tfliteSubscription = null;
      TfliteAudio.stopAudioRecognition();
    } else if (_useRemote) {
      _remoteSession++;
      try {
        await _remoteRecorder?.stop();
      } catch (_) {}
      final loopDone = _remoteLoopFuture;
      if (loopDone != null) {
        try {
          await loopDone.timeout(const Duration(seconds: 45));
        } catch (e) {
          debugLog('Voice', 'Remote STT: timeout/aguardar loop ao parar: $e');
          // Libera [resumeListening] se a transcrição HTTP ainda estiver pendente.
          if (identical(_remoteLoopFuture, loopDone)) _remoteLoopFuture = null;
        }
      }
      _remoteRecorder?.dispose();
      _remoteRecorder = null;
    } else if (_useGoogleCloud) {
      try {
        await FlutterGoogleStt.stopListening();
      } catch (e) {
        debugLog('Voice', 'Google Cloud STT stop: $e');
      }
    } else if (_useVosk) {
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
    if (_useTflite) {
      _startTfliteListening();
    } else if (_useRemote) {
      _remoteRecorder ??= AudioRecorder();
      _startRemoteListening();
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
    } else if (_useRemote) {
      _remoteSession++;
      _signalRemoteStop();
      try {
        await _remoteRecorder?.stop();
      } catch (_) {}
      final loopDone = _remoteLoopFuture;
      if (loopDone != null) {
        try {
          await loopDone.timeout(const Duration(seconds: 45));
        } catch (e) {
          debugLog('Voice', 'Remote STT restart: aguardar loop: $e');
          if (identical(_remoteLoopFuture, loopDone)) _remoteLoopFuture = null;
        }
      }
      _remoteRecorder ??= AudioRecorder();
      _isListening = true;
      _startRemoteListening();
    } else if (_useGoogleCloud) {
      try {
        await FlutterGoogleStt.stopListening();
      } catch (_) {}
      _isListening = true;
      await _startGoogleCloudListening();
    } else if (_useVosk) {
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

