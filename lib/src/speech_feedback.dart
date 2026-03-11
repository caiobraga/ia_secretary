import 'dart:async';
import 'platform_stub.dart' if (dart.library.io) 'dart:io' show Platform;

import 'package:flutter_tts/flutter_tts.dart';

import 'debug_log.dart';

/// Feedback por voz (TTS) para respostas da Ava (ex.: "Ava marcou o evento.", "Ava criou a reunião.").
class SpeechFeedback {
  static FlutterTts? _tts;
  static bool _initialized = false;

  static Future<void> _ensureInit() async {
    if (_initialized) return;
    _tts = FlutterTts();
    await _tts!.setLanguage('pt-BR');
    // Velocidade mais natural (0.5); 0.45 soava lenta/robótica
    await _tts!.setSpeechRate(0.5);
    await _tts!.setVolume(1.0);
    await _tts!.setPitch(1.0);
    if (Platform.isAndroid) {
      try {
        final engines = await _tts!.getEngines;
        if (engines is List && engines.isNotEmpty) {
          for (final e in engines) {
            if (e is Map) {
              final name = (e['name'] as String?)?.toLowerCase() ?? '';
              if (name.contains('google')) {
                await _tts!.setEngine(e['name'] as String);
                debugLog('SpeechFeedback', 'TTS engine: ${e['name']}');
                break;
              }
            }
          }
        }
      } catch (_) {}
      try {
        final voices = await _tts!.getVoices;
        if (voices is List && voices.isNotEmpty) {
          for (final v in voices) {
            if (v is Map) {
              final locale = (v['locale'] as String?)?.toLowerCase().replaceAll('_', '-') ?? '';
              if (locale == 'pt-br') {
                final name = v['name'] as String?;
                if (name != null && name.isNotEmpty) {
                  await _tts!.setVoice({'name': name, 'locale': 'pt-BR'});
                  debugLog('SpeechFeedback', 'TTS voice: $name');
                  break;
                }
              }
            }
          }
        }
      } catch (_) {}
      await _tts!.setLanguage('pt-BR');
    }
    _initialized = true;
    debugLog('SpeechFeedback', 'TTS initialized pt-BR');
  }

  /// Fala o texto em português. Retorna quando a fala termina (para poder retomar o listening).
  /// Ignora se [text] for vazio.
  static Future<void> speak(String text) async {
    final t = text.trim();
    if (t.isEmpty) return;
    try {
      await _ensureInit();
      final completer = Completer<void>();
      _tts!.setStartHandler(() {
        debugLog('SpeechFeedback', 'TTS started');
      });
      _tts!.setCompletionHandler(() {
        if (!completer.isCompleted) completer.complete();
        debugLog('SpeechFeedback', 'TTS completed');
      });
      await _tts!.speak(t);
      debugLog('SpeechFeedback', 'speak: $t');
      await completer.future;
    } catch (e) {
      debugLog('SpeechFeedback', 'speak error: $e');
    }
  }

  /// Para a fala atual (útil se o usuário interromper).
  static Future<void> stop() async {
    try {
      if (_tts != null) await _tts!.stop();
    } catch (_) {}
  }
}
