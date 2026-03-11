import 'platform_stub.dart' if (dart.library.io) 'dart:io' show Platform;

import 'package:flutter/services.dart';

const MethodChannel _channel = MethodChannel('ia_secretary');

/// Traz o app para o primeiro plano (ex.: após comando de voz "Ava" ou "secretária").
Future<bool> bringAppToFront() async {
  if (!Platform.isAndroid) return false;
  try {
    final r = await _channel.invokeMethod<bool>('bringToFront');
    return r ?? false;
  } catch (e) {
    return false;
  }
}

/// Muta o beep do sistema ao iniciar/parar o reconhecimento de voz (só Android).
Future<void> muteRecognitionBeep() async {
  if (!Platform.isAndroid) return;
  try {
    await _channel.invokeMethod('muteRecognitionBeep');
  } catch (_) {}
}

/// Restaura o som após o beep do reconhecimento (só Android).
Future<void> unmuteRecognitionBeep() async {
  if (!Platform.isAndroid) return;
  try {
    await _channel.invokeMethod('unmuteRecognitionBeep');
  } catch (_) {}
}

/// Envia o app para o plano de fundo (Android). Não encerra o app.
Future<void> moveAppToBack() async {
  if (!Platform.isAndroid) return;
  try {
    await _channel.invokeMethod('moveToBack');
  } catch (_) {}
}

/// Ativa ou desativa a bolha flutuante do sistema (overlay sobre outros apps). Só Android.
Future<void> setFloatingBubbleEnabled(bool enabled) async {
  if (!Platform.isAndroid) return;
  try {
    await _channel.invokeMethod('setFloatingBubbleEnabled', enabled);
  } catch (_) {}
}
