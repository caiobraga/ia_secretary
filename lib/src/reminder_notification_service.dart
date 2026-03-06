import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'assistant_actions.dart';
import 'debug_log.dart';
import 'speech_feedback.dart';

const String _reminderChannelId = 'ia_secretary_reminders';
const String _reminderChannelName = 'Lembretes';

/// Verifica lembretes vencendo, fala e dispara notificação local.
class ReminderNotificationService {
  ReminderNotificationService({this.checkInterval = const Duration(minutes: 1)});

  final Duration checkInterval;
  Timer? _timer;
  final Set<String> _notifiedReminderIds = {};

  /// Inicializa o plugin de notificações. Chamar no startup (ex.: main).
  static Future<void> initNotifications(FlutterLocalNotificationsPlugin plugin) async {
    if (!defaultTargetPlatform.toString().contains('Android')) return;
    try {
      const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
      await plugin.initialize(InitializationSettings(android: androidInit));
      final android = plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
      if (android != null) {
        await android.createNotificationChannel(const AndroidNotificationChannel(
          _reminderChannelId,
          _reminderChannelName,
          description: 'Lembretes da secretária',
          importance: Importance.high,
        ));
      }
      _plugin = plugin;
      debugLog('ReminderNotification', 'init ok');
    } catch (e) {
      debugLog('ReminderNotification', 'init: $e');
    }
  }

  static FlutterLocalNotificationsPlugin? _plugin;

  /// Inicia a verificação periódica. Chamar quando o usuário estiver logado.
  void start() {
    stop();
    _timer = Timer.periodic(checkInterval, (_) => _checkAndNotify());
    debugLog('ReminderNotification', 'started (interval: $checkInterval)');
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
  }

  Future<void> _checkAndNotify() async {
    try {
      final reminders = await AssistantActions.getUpcomingRemindersForNotification(withinMinutes: 5);
      final now = DateTime.now();
      for (final r in reminders) {
        final id = r['id'] as String?;
        if (id == null) continue;
        if (_notifiedReminderIds.contains(id)) continue;
        final remindAt = r['remind_at'] as String?;
        if (remindAt != null) {
          try {
            final at = DateTime.parse(remindAt);
            if (at.isAfter(now.add(const Duration(minutes: 4)))) continue;
          } catch (_) {}
        }
        _notifiedReminderIds.add(id);
        final desc = r['description'] as String?;
        final event = r['events'];
        final title = event is Map ? (event['title'] as String?) : null;
        final body = desc?.trim().isNotEmpty == true ? desc! : (title ?? 'Lembrete');
        final phrase = 'Ava: lembrete. $body';
        if (body.trim().isNotEmpty) {
          SpeechFeedback.speak(phrase);
          await _showReminderNotification(title: 'Lembrete', body: body, id: id.hashCode.abs() % 100000);
        }
      }
      if (_notifiedReminderIds.length > 50) _notifiedReminderIds.clear();
    } catch (e) {
      debugLog('ReminderNotification', 'check: $e');
    }
  }

  static Future<void> _showReminderNotification({required String title, required String body, required int id}) async {
    final plugin = _plugin;
    if (plugin == null) return;
    try {
      const details = AndroidNotificationDetails(
        _reminderChannelId,
        _reminderChannelName,
        channelDescription: 'Lembretes da secretária',
        importance: Importance.high,
      );
      await plugin.show(id, title, body, const NotificationDetails(android: details));
    } catch (e) {
      debugLog('ReminderNotification', 'show: $e');
    }
  }
}
