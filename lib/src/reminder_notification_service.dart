import 'dart:async';

import 'package:flutter/foundation.dart' show TargetPlatform, defaultTargetPlatform;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:timezone/timezone.dart' as tz;

import 'assistant_actions.dart';
import 'debug_log.dart';
import 'reminder_rich_context.dart';
import 'speech_feedback.dart';

const String _reminderChannelId = 'ia_secretary_reminders';
const String _reminderChannelName = 'Lembretes';

/// Verifica lembretes **no horário** (remind_at já passou), fala com contexto do evento e
/// agenda notificações locais futuras com [zonedSchedule] para disparar no instante certo.
///
/// Além do [Timer.periodic] ([checkInterval]), usa **Supabase Realtime** em `reminders`,
/// `events` e `event_participants` para ressincronizar quando o Postgres mudar (pool 6543 é no
/// servidor; o app usa WebSocket + anon key).
class ReminderNotificationService {
  ReminderNotificationService({this.checkInterval = const Duration(minutes: 1)});

  final Duration checkInterval;
  Timer? _timer;
  Timer? _realtimeDebounce;
  RealtimeChannel? _realtimeChannel;
  final Set<String> _notifiedReminderIds = {};
  /// IDs de notificações OS agendadas na última sincronização (para cancelar antes de reagendar).
  final List<int> _osScheduledNotificationIds = [];
  int _pollTicks = 0;

  /// Inicializa o plugin de notificações. Chamar no startup (ex.: main).
  static Future<void> initNotifications(FlutterLocalNotificationsPlugin plugin) async {
    try {
      if (defaultTargetPlatform == TargetPlatform.android) {
        const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
        await plugin.initialize(const InitializationSettings(android: androidInit));
        final android = plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
        if (android != null) {
          await android.createNotificationChannel(const AndroidNotificationChannel(
            _reminderChannelId,
            _reminderChannelName,
            description: 'Lembretes da secretária',
            importance: Importance.high,
          ));
        }
      } else if (defaultTargetPlatform == TargetPlatform.iOS || defaultTargetPlatform == TargetPlatform.macOS) {
        await plugin.initialize(
          const InitializationSettings(
            iOS: DarwinInitializationSettings(),
            macOS: DarwinInitializationSettings(),
          ),
        );
      } else {
        return;
      }
      _plugin = plugin;
      debugLog('ReminderNotification', 'init ok');
    } catch (e) {
      debugLog('ReminderNotification', 'init: $e');
    }
  }

  /// Android 12+: pedir permissão de alarme exato (melhor aderência ao [remind_at]).
  static Future<void> requestAndroidExactAlarmsPermission() async {
    if (defaultTargetPlatform != TargetPlatform.android) return;
    final p = _plugin;
    if (p == null) return;
    try {
      final android = p.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
      await android?.requestExactAlarmsPermission();
    } catch (e) {
      debugLog('ReminderNotification', 'exact alarm permission: $e');
    }
  }

  static FlutterLocalNotificationsPlugin? _plugin;

  static int _notificationIdForReminder(String reminderUuid) =>
      300000 + (reminderUuid.hashCode.abs() % 700000);

  /// Frase para TTS quando o horário do lembrete chegou (evento, data, local, participantes).
  /// Passe [preloaded] quando já tiver carregado com [AssistantActions.loadReminderRichContext].
  static String buildProactiveReminderSpeech(Map<String, dynamic> r, {ReminderRichContext? preloaded}) {
    final ctx = preloaded ?? ReminderRichContext.fromReminderRow(r);
    if (ctx != null) {
      final rel = _relativeTimingCue(ctx);
      var phrase = ctx.speechPhrase();
      if (rel != null && rel.isNotEmpty) {
        phrase = phrase.replaceFirst('Ava: ', 'Ava: $rel ');
      }
      return phrase;
    }

    final desc = r['description'] as String?;
    final ev = r['events'];
    var eventTitle = 'seu compromisso';
    String? startIso;
    if (ev is Map) {
      final t = ev['title'] as String?;
      if (t != null && t.trim().isNotEmpty) eventTitle = t.trim();
      startIso = ev['start_time'] as String?;
    }
    final detail = desc?.trim().isNotEmpty == true ? desc!.trim() : '';

    String? eventCue;
    if (startIso != null) {
      try {
        final start = DateTime.parse(startIso).toLocal();
        final now = DateTime.now();
        final until = start.difference(now);
        if (!until.isNegative && until.inMinutes < 24 * 60) {
          if (until.inMinutes < 1) {
            eventCue = 'O evento $eventTitle começa agora.';
          } else if (until.inMinutes < 60) {
            final m = until.inMinutes;
            final minStr = m == 1 ? '1 minuto' : '$m minutos';
            eventCue = 'Faltam $minStr para $eventTitle.';
          } else {
            final h = start.hour;
            final min = start.minute.toString().padLeft(2, '0');
            eventCue = '$eventTitle está marcado para hoje às ${h}h$min.';
          }
        } else if (until.isNegative && until.inMinutes.abs() < 45) {
          eventCue = '$eventTitle já começou ou está começando.';
        }
      } catch (_) {}
    }

    if (eventCue != null && eventCue.isNotEmpty) {
      if (detail.isNotEmpty && detail != eventTitle) {
        return 'Ava: $eventCue Detalhe do lembrete: $detail.';
      }
      return 'Ava: $eventCue';
    }
    if (detail.isNotEmpty) return 'Ava: Chegou o horário do lembrete: $detail.';
    return 'Ava: Chegou o horário de um lembrete sobre $eventTitle.';
  }

  static String? _relativeTimingCue(ReminderRichContext ctx) {
    final start = ctx.startLocal;
    if (start == null) return null;
    try {
      final eventTitle = ctx.eventTitle;
      final now = DateTime.now();
      final until = start.difference(now);
      if (!until.isNegative && until.inMinutes < 24 * 60) {
        if (until.inMinutes < 1) {
          return 'O evento $eventTitle começa agora.';
        }
        if (until.inMinutes < 60) {
          final m = until.inMinutes;
          final minStr = m == 1 ? '1 minuto' : '$m minutos';
          return 'Faltam $minStr para $eventTitle.';
        }
        final h = start.hour;
        final min = start.minute.toString().padLeft(2, '0');
        return '$eventTitle está marcado para hoje às ${h}h$min.';
      }
      if (until.isNegative && until.inMinutes.abs() < 45) {
        return '$eventTitle já começou ou está começando.';
      }
    } catch (_) {}
    return null;
  }

  /// Inicia a verificação periódica e sincroniza alarmes locais futuros.
  void start() {
    stop();
    _timer = Timer.periodic(checkInterval, (_) {
      _pollTicks++;
      unawaited(_checkAndNotify());
      if (_pollTicks % 5 == 0) unawaited(resyncOsScheduledReminders());
    });
    unawaited(_checkAndNotify());
    unawaited(resyncOsScheduledReminders());
    _subscribeRealtime();
    debugLog('ReminderNotification', 'started (interval: $checkInterval)');
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
    _unsubscribeRealtime();
  }

  static const _realtimeDebounceDelay = Duration(milliseconds: 500);

  void _scheduleRealtimeResync() {
    _realtimeDebounce?.cancel();
    _realtimeDebounce = Timer(_realtimeDebounceDelay, () {
      _realtimeDebounce = null;
      unawaited(resyncOsScheduledReminders());
      unawaited(_checkAndNotify());
    });
  }

  /// Stream de mudanças no Postgres (substitui depender só do polling para dados novos).
  void _subscribeRealtime() {
    _unsubscribeRealtime();
    final client = Supabase.instance.client;
    final uid = client.auth.currentUser?.id;
    if (uid == null) {
      debugLog('ReminderNotification', 'realtime: skip (no user)');
      return;
    }
    try {
      final ch = client.channel('ia_secretary_reminder_sync_$uid');
      ch
          .onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: 'reminders',
            callback: (_) => _scheduleRealtimeResync(),
          )
          .onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: 'events',
            filter: PostgresChangeFilter(
              type: PostgresChangeFilterType.eq,
              column: 'user_id',
              value: uid,
            ),
            callback: (_) => _scheduleRealtimeResync(),
          )
          .onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: 'event_participants',
            callback: (_) => _scheduleRealtimeResync(),
          )
          .subscribe();
      _realtimeChannel = ch;
      debugLog('ReminderNotification', 'realtime subscribed');
    } catch (e) {
      debugLog('ReminderNotification', 'realtime subscribe: $e');
    }
  }

  void _unsubscribeRealtime() {
    _realtimeDebounce?.cancel();
    _realtimeDebounce = null;
    final ch = _realtimeChannel;
    _realtimeChannel = null;
    if (ch == null) return;
    try {
      Supabase.instance.client.removeChannel(ch);
      debugLog('ReminderNotification', 'realtime unsubscribed');
    } catch (e) {
      debugLog('ReminderNotification', 'realtime unsubscribe: $e');
    }
  }

  /// Cancela agendamentos OS antigos e recria a partir do Supabase (login, mudança de dados).
  Future<void> resyncOsScheduledReminders() async {
    final plugin = _plugin;
    if (plugin == null) return;
    for (final id in _osScheduledNotificationIds) {
      try {
        await plugin.cancel(id);
      } catch (_) {}
    }
    _osScheduledNotificationIds.clear();

    final rows = await AssistantActions.getRemindersForFutureOsSchedule();
    for (final r in rows) {
      final rid = r['id'] as String?;
      final remindAt = r['remind_at'] as String?;
      if (rid == null || remindAt == null) continue;

      final when = DateTime.tryParse(remindAt);
      if (when == null) continue;
      final local = when.toLocal();
      if (!local.isAfter(DateTime.now())) continue;

      final scheduled = tz.TZDateTime.from(local, tz.local);
      final nid = _notificationIdForReminder(rid);
      final ctx = await AssistantActions.loadReminderRichContext(r);
      final ev = r['events'];
      final eventTitle = ctx?.eventTitle ?? (ev is Map ? (ev['title'] as String?)?.trim() : null);
      final desc = r['description'] as String?;
      final title = ctx?.notificationTitle() ?? 'Lembrete';
      final body = ctx?.compactSummary() ??
          (desc?.trim().isNotEmpty == true
              ? desc!.trim()
              : (eventTitle != null && eventTitle.isNotEmpty ? eventTitle : 'Hora do lembrete'));
      final bigText = ctx?.expandedBigText() ?? body;

      final details = _platformScheduleDetails(androidBigText: bigText, androidSummary: body);
      try {
        await plugin.zonedSchedule(
          nid,
          title,
          body,
          scheduled,
          details,
          androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
          uiLocalNotificationDateInterpretation: UILocalNotificationDateInterpretation.absoluteTime,
        );
        _osScheduledNotificationIds.add(nid);
      } catch (e) {
        debugLog('ReminderNotification', 'exact schedule: $e');
        try {
          await plugin.zonedSchedule(
            nid,
            title,
            body,
            scheduled,
            details,
            androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
            uiLocalNotificationDateInterpretation: UILocalNotificationDateInterpretation.absoluteTime,
          );
          _osScheduledNotificationIds.add(nid);
        } catch (e2) {
          debugLog('ReminderNotification', 'inexact schedule: $e2');
        }
      }
    }
    debugLog('ReminderNotification', 'OS scheduled count=${_osScheduledNotificationIds.length}');
  }

  static NotificationDetails _platformScheduleDetails({
    String? androidBigText,
    String? androidSummary,
  }) {
    if (defaultTargetPlatform == TargetPlatform.android) {
      final big = androidBigText?.trim();
      final summary = androidSummary?.trim();
      return NotificationDetails(
        android: AndroidNotificationDetails(
          _reminderChannelId,
          _reminderChannelName,
          channelDescription: 'Lembretes da secretária',
          importance: Importance.high,
          priority: Priority.high,
          styleInformation: big != null && big.isNotEmpty
              ? BigTextStyleInformation(
                  big,
                  summaryText: summary != null && summary.isNotEmpty ? summary : null,
                )
              : null,
        ),
      );
    }
    if (defaultTargetPlatform == TargetPlatform.iOS || defaultTargetPlatform == TargetPlatform.macOS) {
      return const NotificationDetails(
        iOS: DarwinNotificationDetails(presentAlert: true, presentSound: true),
        macOS: DarwinNotificationDetails(presentAlert: true, presentSound: true),
      );
    }
    return const NotificationDetails();
  }

  Future<void> _checkAndNotify() async {
    try {
      final reminders = await AssistantActions.getUpcomingRemindersForNotification();
      for (final r in reminders) {
        final id = r['id'] as String?;
        if (id == null) continue;
        if (_notifiedReminderIds.contains(id)) continue;
        final ctx = await AssistantActions.loadReminderRichContext(r);
        final phrase = buildProactiveReminderSpeech(r, preloaded: ctx);
        final desc = r['description'] as String?;
        final ev = r['events'];
        final eventTitle = ctx?.eventTitle ?? (ev is Map ? (ev['title'] as String?) : null);
        final summaryBody = ctx?.compactSummary() ??
            (desc?.trim().isNotEmpty == true ? desc! : (eventTitle ?? 'Lembrete'));
        final bigText = ctx?.expandedBigText() ?? summaryBody;
        final notifTitle = ctx?.notificationTitle() ?? 'Lembrete';
        if (phrase.trim().isNotEmpty) {
          SpeechFeedback.speak(phrase);
        }
        await _showReminderNotification(
          title: notifTitle,
          summaryBody: summaryBody,
          bigText: bigText,
          id: _notificationIdForReminder(id),
        );
        final marked = await AssistantActions.markReminderRelembrado(id);
        if (marked) {
          _notifiedReminderIds.add(id);
        } else {
          debugLog('ReminderNotification', 'relembrado não gravado; tentará de novo: $id');
        }
      }
      if (_notifiedReminderIds.length > 80) _notifiedReminderIds.clear();
    } catch (e) {
      debugLog('ReminderNotification', 'check: $e');
    }
  }

  static Future<void> _showReminderNotification({
    required String title,
    required String summaryBody,
    required String bigText,
    required int id,
  }) async {
    final plugin = _plugin;
    if (plugin == null) return;
    try {
      if (defaultTargetPlatform == TargetPlatform.android) {
        final android = AndroidNotificationDetails(
          _reminderChannelId,
          _reminderChannelName,
          channelDescription: 'Lembretes da secretária',
          importance: Importance.high,
          priority: Priority.high,
          styleInformation: BigTextStyleInformation(
            bigText,
            summaryText: summaryBody,
          ),
        );
        await plugin.show(id, title, summaryBody, NotificationDetails(android: android));
      } else if (defaultTargetPlatform == TargetPlatform.iOS || defaultTargetPlatform == TargetPlatform.macOS) {
        const ios = DarwinNotificationDetails(presentAlert: true, presentSound: true);
        await plugin.show(id, title, bigText, const NotificationDetails(iOS: ios, macOS: ios));
      }
    } catch (e) {
      debugLog('ReminderNotification', 'show: $e');
    }
  }
}
