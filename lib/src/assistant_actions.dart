import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import 'debug_log.dart';
import 'reminder_rich_context.dart';
import 'voice_commands.dart';

/// Executa ações no Supabase a partir de comandos de voz (calendário, eventos, notas).
class AssistantActions {
  static String? get _userId => Supabase.instance.client.auth.currentUser?.id;

  /// Títulos dos eventos listados na última resposta (para "leia as notas dessa reunião").
  static List<String> lastListedEventTitles = [];

  /// Cria uma reunião (evento). Se [startIso] e [endIso] forem fornecidos, usa esses horários; senão agora + 1h.
  /// Retorna null em sucesso, ou mensagem de erro (conflito de horário ou exceção).
  static Future<String?> createMeeting({
    String title = 'Reunião',
    String? startIso,
    String? endIso,
  }) async {
    final uid = _userId;
    if (uid == null) return 'Ava: faça login para criar eventos.';
    String startStr;
    String endStr;
    if (startIso != null && startIso.isNotEmpty && endIso != null && endIso.isNotEmpty) {
      startStr = startIso;
      endStr = endIso;
    } else {
      final now = DateTime.now();
      startStr = now.toUtc().toIso8601String();
      endStr = now.add(const Duration(hours: 1)).toUtc().toIso8601String();
    }
    try {
      // Conflito: outro evento do usuário no mesmo horário
      final overlapping = await Supabase.instance.client
          .from('events')
          .select('id, title')
          .eq('user_id', uid)
          .eq('status', 'scheduled')
          .lt('start_time', endStr)
          .gt('end_time', startStr);

      final overlaps = overlapping as List;
      if (overlaps.isNotEmpty) {
        final other = overlaps.first as Map<String, dynamic>;
        final otherTitle = other['title'] as String? ?? 'outro evento';
        return 'Ava: já existe um evento nesse horário — $otherTitle. Não foi possível marcar.';
      }

      await Supabase.instance.client.from('events').insert({
        'user_id': uid,
        'title': title,
        'start_time': startStr,
        'end_time': endStr,
        'status': 'scheduled',
      });
      debugLog('Assistant', 'createMeeting ok');
      return null;
    } catch (e) {
      debugLog('Assistant', 'createMeeting: $e');
      return 'Ava não conseguiu criar o evento.';
    }
  }

  /// Adiciona uma nota a uma reunião/evento já listada (usa lastListedEventTitles).
  static Future<String> addNoteToMeeting(String content, {String? whichListed}) async {
    final uid = _userId;
    if (uid == null) return 'Ava: faça login para adicionar notas.';
    if (lastListedEventTitles.isEmpty) {
      return 'Ava: não sei a qual reunião se refere. Antes pergunte: quais reuniões tenho hoje, ou diga o nome da reunião.';
    }
    final idx = whichListed == 'second' && lastListedEventTitles.length > 1 ? 1 : 0;
    final eventTitle = lastListedEventTitles[idx];
    try {
      final list = await Supabase.instance.client
          .from('events')
          .select('id, title')
          .eq('user_id', uid)
          .eq('status', 'scheduled')
          .order('start_time', ascending: false);
      final events = list as List;
      final titleNorm = _normalizeForMatch(eventTitle);
      String? eventId;
      for (final e in events) {
        final t = _normalizeForMatch(e['title'] as String? ?? '');
        if (t.contains(titleNorm) || titleNorm.contains(t) || t == titleNorm) {
          eventId = e['id'] as String?;
          break;
        }
      }
      if (eventId == null) return 'Ava: não encontrei a reunião "$eventTitle".';
      await Supabase.instance.client.from('meeting_notes').insert({
        'event_id': eventId,
        'title': 'Nota de voz',
        'content': content,
        'created_by': uid,
      });
      debugLog('Assistant', 'addNoteToMeeting ok: $eventTitle');
      return 'Ava anotou na reunião $eventTitle.';
    } catch (e) {
      debugLog('Assistant', 'addNoteToMeeting: $e');
      return 'Ava não conseguiu adicionar a nota.';
    }
  }

  /// Cria uma nota (meeting_note). Precisa de um event_id; criamos um evento "Notas" se necessário.
  static Future<bool> takeNote({String content = 'Nota de voz'}) async {
    final uid = _userId;
    if (uid == null) return false;
    try {
      final now = DateTime.now();
      final end = now.add(const Duration(minutes: 30));
      final eventRes = await Supabase.instance.client.from('events').insert({
        'user_id': uid,
        'title': 'Notas',
        'start_time': now.toIso8601String(),
        'end_time': end.toIso8601String(),
        'status': 'scheduled',
      }).select('id').single();
      final eventId = eventRes['id'] as String;
      await Supabase.instance.client.from('meeting_notes').insert({
        'event_id': eventId,
        'title': 'Nota de voz',
        'content': content,
        'created_by': uid,
      });
      debugLog('Assistant', 'takeNote ok');
      return true;
    } catch (e) {
      debugLog('Assistant', 'takeNote: $e');
      return false;
    }
  }

  /// Lista eventos de um dia (query_date_iso = YYYY-MM-DD) e retorna frase para falar.
  static Future<String> listEvents(String queryDateIso) async {
    final uid = _userId;
    if (uid == null) return 'Ava: faça login para ver seus eventos.';
    try {
      final parts = queryDateIso.split('-');
      if (parts.length != 3) return 'Ava: não entendi a data.';
      final dayStart = DateTime(int.parse(parts[0]), int.parse(parts[1]), int.parse(parts[2]));
      final dayEnd = dayStart.add(const Duration(days: 1));
      final startUtc = dayStart.toUtc().toIso8601String();
      final endUtc = dayEnd.toUtc().toIso8601String();

      final list = await Supabase.instance.client
          .from('events')
          .select('id, title, start_time')
          .eq('user_id', uid)
          .eq('status', 'scheduled')
          .gte('start_time', startUtc)
          .lt('start_time', endUtc)
          .order('start_time', ascending: true);

      final events = list as List;
      if (events.isEmpty) {
        lastListedEventTitles = [];
        final label = _dateLabel(queryDateIso);
        return 'Ava: sua agenda $label está livre — não há eventos marcados. Quer marcar algo?';
      }
      final phrases = <String>[];
      lastListedEventTitles = [];
      for (final e in events) {
        final title = e['title'] as String? ?? 'Evento';
        lastListedEventTitles.add(title);
        final start = e['start_time'] as String?;
        final timeStr = start != null ? _formatTimeForSpeech(start) : '';
        phrases.add(timeStr.isEmpty ? title : '$title às $timeStr');
      }
      final label = _dateLabel(queryDateIso);
      const alternatives = ' Posso cancelar, remarcar, ler notas ou lembrar dos lembretes. O que prefere?';
      if (phrases.length == 1) {
        return 'Ava: na sua agenda $label, você tem um compromisso: ${phrases.first}.$alternatives';
      }
      return 'Ava: na sua agenda $label, você tem ${phrases.length} compromissos: ${phrases.join(', ')}.$alternatives';
    } catch (e) {
      debugLog('Assistant', 'listEvents: $e');
      return 'Ava não conseguiu consultar os eventos.';
    }
  }

  /// Eventos que têm pelo menos uma nota de reunião (relação events -> meeting_notes).
  static Future<String> listEventsWithNotes() async {
    final uid = _userId;
    if (uid == null) return 'Ava: faça login para ver eventos com notas.';
    try {
      final list = await Supabase.instance.client
          .from('meeting_notes')
          .select('event_id, events!inner(id, title, start_time, user_id)')
          .eq('events.user_id', uid);
      final rows = list as List;
      final seen = <String>{};
      final phrases = <String>[];
      for (final r in rows) {
        final event = r['events'];
        if (event is! Map) continue;
        final id = event['id'] as String?;
        if (id == null || seen.contains(id)) continue;
        seen.add(id);
        final title = event['title'] as String? ?? 'Evento';
        final start = event['start_time'] as String?;
        final timeStr = start != null ? _formatTimeForSpeech(start) : '';
        phrases.add(timeStr.isEmpty ? title : '$title às $timeStr');
      }
      if (phrases.isEmpty) {
        lastListedEventTitles = [];
        return 'Ava: você não tem eventos com notas. Posso criar uma nota na próxima reunião.';
      }
      lastListedEventTitles = phrases.map((p) => p.contains(' às ') ? p.substring(0, p.indexOf(' às ')) : p).toList();
      const alternatives = ' Quer que eu leia as notas de alguma? Ou cancele ou remarque algum evento.';
      if (phrases.length == 1) return 'Ava: você tem 1 evento com notas: ${phrases.first}.$alternatives';
      return 'Ava: você tem ${phrases.length} eventos com notas: ${phrases.join(', ')}.$alternatives';
    } catch (e) {
      debugLog('Assistant', 'listEventsWithNotes: $e');
      return 'Ava não conseguiu listar eventos com notas.';
    }
  }

  /// Eventos que têm pelo menos um lembrete (relação events -> reminders).
  static Future<String> listEventsWithReminders() async {
    final uid = _userId;
    if (uid == null) return 'Ava: faça login para ver eventos com lembrete.';
    try {
      final list = await Supabase.instance.client
          .from('reminders')
          .select('event_id, events!inner(id, title, start_time, user_id)')
          .eq('events.user_id', uid);
      final rows = list as List;
      final seen = <String>{};
      final phrases = <String>[];
      for (final r in rows) {
        final event = r['events'];
        if (event is! Map) continue;
        final id = event['id'] as String?;
        if (id == null || seen.contains(id)) continue;
        seen.add(id);
        final title = event['title'] as String? ?? 'Evento';
        final start = event['start_time'] as String?;
        final timeStr = start != null ? _formatTimeForSpeech(start) : '';
        phrases.add(timeStr.isEmpty ? title : '$title às $timeStr');
      }
      if (phrases.isEmpty) {
        lastListedEventTitles = [];
        return 'Ava: nenhum evento tem lembrete. Quer que eu adicione um lembrete a algum evento?';
      }
      lastListedEventTitles = phrases.map((p) => p.contains(' às ') ? p.substring(0, p.indexOf(' às ')) : p).toList();
      const alternatives = ' Quer adiar um lembrete ou que eu leia as notas do evento?';
      if (phrases.length == 1) return 'Ava: 1 evento com lembrete: ${phrases.first}.$alternatives';
      return 'Ava: ${phrases.length} eventos com lembrete: ${phrases.join(', ')}.$alternatives';
    } catch (e) {
      debugLog('Assistant', 'listEventsWithReminders: $e');
      return 'Ava não conseguiu listar eventos com lembrete.';
    }
  }

  /// Itens de ação (action_items) abertos, com evento/nota relacionada.
  static Future<String> listActionItems() async {
    final uid = _userId;
    if (uid == null) return 'Ava: faça login para ver itens de ação.';
    try {
      final list = await Supabase.instance.client
          .from('action_items')
          .select('id, description, status, due_date, meeting_notes(events(title))');
      final rows = list as List;
      final open = <Map<String, dynamic>>[];
      for (final r in rows) {
        final status = r['status'] as String?;
        if (status != null && status != 'open') continue;
        open.add(r as Map<String, dynamic>);
      }
      if (open.isEmpty) return 'Ava: não há itens de ação pendentes. Posso listar eventos com notas se quiser.';
      final phrases = <String>[];
      for (final o in open.take(15)) {
        final desc = o['description'] as String? ?? 'Item';
        final due = o['due_date'] as String?;
        final dueStr = due != null ? ' até ${_formatTimeForSpeech(due)}' : '';
        phrases.add('$desc$dueStr');
      }
      const alternatives = ' Quer marcar algum como concluído ou ouvir as notas da reunião relacionada?';
      if (phrases.length == 1) return 'Ava: você tem 1 item pendente: ${phrases.first}.$alternatives';
      return 'Ava: você tem ${phrases.length} itens pendentes: ${phrases.join(', ')}.$alternatives';
    } catch (e) {
      debugLog('Assistant', 'listActionItems: $e');
      return 'Ava não conseguiu listar itens de ação.';
    }
  }

  /// Lista pessoas/contatos do usuário (tabela people).
  static Future<String> listPeople() async {
    final uid = _userId;
    if (uid == null) return 'Ava: faça login para ver seus contatos.';
    try {
      final list = await Supabase.instance.client
          .from('people')
          .select('id, name, email, phone')
          .eq('user_id', uid)
          .order('name')
          .limit(30);
      final people = list as List;
      if (people.isEmpty) return 'Ava: você ainda não tem contatos. Posso adicionar quando você disser o nome e e-mail.';
      final phrases = <String>[];
      for (final p in people) {
        final name = p['name'] as String? ?? 'Sem nome';
        final email = p['email'] as String?;
        phrases.add(email != null && email.isNotEmpty ? '$name ($email)' : name);
      }
      const alternatives = ' Posso adicionar participantes a um evento ou mostrar detalhes de alguém. O que deseja?';
      if (phrases.length == 1) return 'Ava: você tem 1 contato: ${phrases.first}.$alternatives';
      return 'Ava: você tem ${phrases.length} contatos: ${phrases.join(', ')}.$alternatives';
    } catch (e) {
      debugLog('Assistant', 'listPeople: $e');
      return 'Ava não conseguiu listar contatos.';
    }
  }

  /// Resposta conversacional: o que a Ava pode fazer (opções disponíveis).
  static Future<String> getWhatCanDoSpeech() async {
    return 'Ava: você pode me pedir para listar eventos por dia ou semana, cancelar ou remarcar um evento, '
        'ver lembretes e eventos com notas, ou os lembretes de um evento específico. Posso ler as notas de uma reunião, listar itens de ação e contatos. '
        'Também marco reuniões, anoto o que você disser, digo as horas e o clima. '
        'Diga por exemplo: quais reuniões tive essa semana, ou: notas da reunião orçamento. O que deseja?';
  }

  /// Lista reuniões/eventos dessa semana (segunda a domingo) e pergunta se quer ouvir as notas.
  static Future<String> listMeetingsThisWeek() async {
    final uid = _userId;
    if (uid == null) return 'Ava: faça login para ver suas reuniões.';
    try {
      final now = DateTime.now();
      // Segunda = 1, domingo = 7
      final startOfWeek = DateTime(now.year, now.month, now.day).subtract(Duration(days: now.weekday - 1));
      final endOfWeek = startOfWeek.add(const Duration(days: 6, hours: 23, minutes: 59, seconds: 59));
      final startUtc = startOfWeek.toUtc().toIso8601String();
      final endUtc = endOfWeek.toUtc().toIso8601String();

      final list = await Supabase.instance.client
          .from('events')
          .select('id, title, start_time')
          .eq('user_id', uid)
          .eq('status', 'scheduled')
          .gte('start_time', startUtc)
          .lte('start_time', endUtc)
          .order('start_time', ascending: true);

      final events = list as List;
      if (events.isEmpty) {
        lastListedEventTitles = [];
        return 'Ava: esta semana está livre — sem reuniões marcadas. Quer agendar alguma?';
      }
      final phrases = <String>[];
      lastListedEventTitles = [];
      for (final e in events) {
        final title = e['title'] as String? ?? 'Reunião';
        lastListedEventTitles.add(title);
        final start = e['start_time'] as String?;
        final timeStr = start != null ? _formatTimeForSpeech(start) : '';
        phrases.add(timeStr.isEmpty ? title : '$title às $timeStr');
      }
      if (phrases.length == 1) {
        return 'Ava: nesta semana você tem uma reunião marcada: ${phrases.first}. Quer que eu leia as notas ou os lembretes?';
      }
      return 'Ava: nesta semana você tem ${phrases.length} reuniões: ${phrases.join(', ')}. Quer notas ou lembretes de alguma?';
    } catch (e) {
      debugLog('Assistant', 'listMeetingsThisWeek: $e');
      return 'Ava não conseguiu listar as reuniões da semana.';
    }
  }

  static String _dateLabel(String queryDateIso) {
    final now = DateTime.now();
    final today = '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
    if (queryDateIso == today) return 'hoje';
    final tomorrow = now.add(const Duration(days: 1));
    final tomorrowStr = '${tomorrow.year}-${tomorrow.month.toString().padLeft(2, '0')}-${tomorrow.day.toString().padLeft(2, '0')}';
    if (queryDateIso == tomorrowStr) return 'amanhã';
    final parts = queryDateIso.split('-');
    if (parts.length == 3) return 'no dia ${parts[2]}/${parts[1]}';
    return 'nesse dia';
  }

  static String _normalizeForMatch(String s) {
    const withAccents = 'áàâãéèêíìîóòôõúùûç';
    const withoutAccents = 'aaaaeeeiiioooouuuc';
    String t = s.toLowerCase().trim();
    for (int i = 0; i < withAccents.length; i++) {
      t = t.replaceAll(withAccents[i], withoutAccents[i]);
    }
    return t;
  }

  static String _formatTimeForSpeech(String iso) {
    try {
      final dt = DateTime.parse(iso).toLocal();
      final h = dt.hour;
      final m = dt.minute;
      if (m == 0) return '${h}h';
      return '${h}h${m.toString().padLeft(2, '0')}';
    } catch (_) {
      return '';
    }
  }

  /// Lembretes ligados a um evento (por título ou à primeira/segunda da última lista).
  static Future<String> readRemindersForEvent(String meetingTitle, {String? whichListed}) async {
    final uid = _userId;
    if (uid == null) return 'Ava: faça login para ver lembretes.';
    var title = meetingTitle.trim();
    if (title.isEmpty && whichListed != null && lastListedEventTitles.isNotEmpty) {
      final idx = whichListed == 'second' && lastListedEventTitles.length > 1 ? 1 : 0;
      title = lastListedEventTitles[idx];
    }
    if (title.isEmpty) {
      return 'Ava: diga de qual reunião ou evento quer os lembretes. Por exemplo: lembretes da reunião orçamento.';
    }
    try {
      final titleNorm = _normalizeForMatch(title);
      final eventsList = await Supabase.instance.client
          .from('events')
          .select('id, title')
          .eq('user_id', uid)
          .eq('status', 'scheduled')
          .order('start_time', ascending: false);
      final events = eventsList as List;
      String? eventId;
      String? matchedTitle;
      for (final e in events) {
        final t = _normalizeForMatch(e['title'] as String? ?? '');
        if (t.contains(titleNorm) || titleNorm.contains(t) || t == titleNorm) {
          eventId = e['id'] as String?;
          matchedTitle = e['title'] as String?;
          break;
        }
      }
      if (eventId == null) return 'Ava: não encontrei o evento "$title".';
      final list = await Supabase.instance.client
          .from('reminders')
          .select('id, remind_at, description, relembrado')
          .eq('event_id', eventId)
          .order('remind_at', ascending: true);
      final rows = list as List;
      if (rows.isEmpty) {
        return 'Ava: não há lembretes para o evento "$matchedTitle".';
      }
      final parts = <String>[];
      for (final r in rows) {
        final at = r['remind_at'] as String?;
        final timeStr = at != null ? _formatTimeForSpeech(at) : '';
        final desc = r['description'] as String?;
        final label = desc?.trim().isNotEmpty == true ? desc! : 'Lembrete';
        final when = at != null ? _reminderWhenPhrase(at) : '';
        final done = r['relembrado'] as bool? ?? false;
        final suffix = done ? ', já avisado' : ', pendente';
        parts.add(when.isEmpty
            ? (timeStr.isEmpty ? '$label$suffix' : '$label às $timeStr$suffix')
            : '$label, $when$suffix');
      }
      if (parts.length == 1) {
        return 'Ava: para "$matchedTitle", um lembrete: ${parts.first}.';
      }
      return 'Ava: para "$matchedTitle", ${parts.length} lembretes: ${parts.join('; ')}.';
    } catch (e) {
      debugLog('Assistant', 'readRemindersForEvent: $e');
      return 'Ava não conseguiu buscar os lembretes desse evento.';
    }
  }

  static String _reminderWhenPhrase(String remindAtIso) {
    try {
      final dt = DateTime.parse(remindAtIso).toLocal();
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final d = DateTime(dt.year, dt.month, dt.day);
      final timeStr = _formatTimeForSpeech(remindAtIso);
      if (d == today) return 'hoje às $timeStr';
      final tomorrow = today.add(const Duration(days: 1));
      if (d == tomorrow) return 'amanhã às $timeStr';
      return 'dia ${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')} às $timeStr';
    } catch (_) {
      return '';
    }
  }

  /// Lista lembretes do usuário (próximos 7 dias) para falar.
  static Future<String> listReminders() async {
    final uid = _userId;
    if (uid == null) return 'Ava: faça login para ver seus lembretes.';
    try {
      final now = DateTime.now().toUtc().toIso8601String();
      final later = DateTime.now().add(const Duration(days: 7)).toUtc().toIso8601String();
      final list = await Supabase.instance.client
          .from('reminders')
          .select('id, remind_at, description, event_id, relembrado, events!inner(title, user_id)')
          .eq('events.user_id', uid)
          .eq('relembrado', false)
          .gte('remind_at', now)
          .lte('remind_at', later)
          .order('remind_at', ascending: true)
          .limit(20);
      final reminders = list as List;
      if (reminders.isEmpty) {
        return 'Ava: você não tem lembretes pendentes nos próximos 7 dias.';
      }
      final phrases = <String>[];
      for (final r in reminders) {
        final at = r['remind_at'] as String?;
        final desc = r['description'] as String?;
        final event = r['events'];
        final evTitle = event is Map ? (event['title'] as String?) : null;
        final label = desc?.trim().isNotEmpty == true ? desc! : (evTitle ?? 'Lembrete');
        if (at != null) {
          final when = _reminderWhenPhrase(at);
          phrases.add(when.isEmpty ? label : '$label, $when');
        } else {
          phrases.add(label);
        }
      }
      const alternatives = ' Quer adiar algum ou que eu leia o evento relacionado?';
      if (phrases.length == 1) return 'Ava: você tem 1 lembrete: ${phrases.first}.$alternatives';
      return 'Ava: você tem ${phrases.length} lembretes: ${phrases.join(', ')}.$alternatives';
    } catch (e) {
      debugLog('Assistant', 'listReminders: $e');
      return 'Ava não conseguiu listar os lembretes.';
    }
  }

  /// Garante [ReminderRichContext] mesmo se o JSON de [events] vier em formato inesperado ou embed incompleto.
  static Future<ReminderRichContext?> loadReminderRichContext(Map<String, dynamic> row) async {
    final sync = ReminderRichContext.fromReminderRow(row);
    if (sync != null) return sync;
    final eid = row['event_id'] as String?;
    if (eid == null) return null;
    final uid = _userId;
    if (uid == null) return null;
    try {
      final data = await Supabase.instance.client
          .from('events')
          .select('id, title, description, start_time, end_time, location, event_participants(name, email, role)')
          .eq('id', eid)
          .eq('user_id', uid)
          .maybeSingle();
      if (data == null) return null;
      return ReminderRichContext.fromEventMapAndReminder(
        Map<String, dynamic>.from(data as Map),
        row,
      );
    } catch (e) {
      debugLog('Assistant', 'loadReminderRichContext: $e');
      return null;
    }
  }

  /// Lembretes com [remind_at] **já passou**, `relembrado = false`, e não mais antigos que [maxOverdueDays].
  /// (A janela curta de 45 min fazia sumir o lembrete se você abrisse o app mais tarde.)
  /// Lembretes ainda futuros vão para [getRemindersForFutureOsSchedule] (notificação agendada).
  static Future<List<Map<String, dynamic>>> getUpcomingRemindersForNotification({int maxOverdueDays = 30}) async {
    final uid = _userId;
    if (uid == null) return [];
    try {
      final now = DateTime.now().toUtc();
      final pastLimit = now.subtract(Duration(days: maxOverdueDays));
      final list = await Supabase.instance.client
          .from('reminders')
          .select(
            'id, remind_at, description, event_id, relembrado, events!inner(id, title, description, user_id, start_time, end_time, location, event_participants(name, email, role))',
          )
          .eq('events.user_id', uid)
          .eq('relembrado', false)
          .lte('remind_at', now.toIso8601String())
          .gte('remind_at', pastLimit.toIso8601String())
          .order('remind_at', ascending: true);
      return List<Map<String, dynamic>>.from(list as List);
    } catch (e) {
      debugLog('Assistant', 'getUpcomingReminders: $e');
      return [];
    }
  }

  /// Lembretes futuros para [zonedSchedule] no [remind_at] exato.
  static Future<List<Map<String, dynamic>>> getRemindersForFutureOsSchedule({
    int maxDays = 14,
    int limit = 48,
  }) async {
    final uid = _userId;
    if (uid == null) return [];
    try {
      final now = DateTime.now().toUtc().toIso8601String();
      final end = DateTime.now().add(Duration(days: maxDays)).toUtc().toIso8601String();
      final list = await Supabase.instance.client
          .from('reminders')
          .select(
            'id, remind_at, description, event_id, relembrado, events!inner(id, title, description, user_id, start_time, end_time, location, event_participants(name, email, role))',
          )
          .eq('events.user_id', uid)
          .eq('relembrado', false)
          .gt('remind_at', now)
          .lte('remind_at', end)
          .order('remind_at', ascending: true)
          .limit(limit);
      return List<Map<String, dynamic>>.from(list as List);
    } catch (e) {
      debugLog('Assistant', 'getRemindersForFutureOsSchedule: $e');
      return [];
    }
  }

  /// Marca lembrete como já notificado. Retorna false se RLS não permitiu (ex.: event_id null).
  static Future<bool> markReminderRelembrado(String reminderId) async {
    if (_userId == null) return false;
    try {
      final res = await Supabase.instance.client
          .from('reminders')
          .update({'relembrado': true})
          .eq('id', reminderId)
          .select('id');
      final ok = (res as List).isNotEmpty;
      if (ok) {
        debugLog('Assistant', 'relembrado ok: $reminderId');
      } else {
        debugLog('Assistant', 'relembrado: nenhuma linha atualizada (id=$reminderId)');
      }
      return ok;
    } catch (e) {
      debugLog('Assistant', 'markReminderRelembrado: $e');
      return false;
    }
  }

  /// Busca notas de reunião pelo título do evento e retorna texto para falar.
  /// Se [meetingTitle] estiver vazio e houver contexto (última lista de eventos), usa [whichListed]: 'first' ou 'second'.
  /// Se [startIso] for informado, busca o evento pelo horário de início (ex.: "reunião de segunda às 16h").
  static Future<String> readMeetingNotesByTitle(String meetingTitle, {String? whichListed, String? startIso}) async {
    final uid = _userId;
    if (uid == null) return 'Ava: faça login para ouvir as notas.';
    var title = meetingTitle.trim();
    if (title.isEmpty && (startIso == null || startIso.isEmpty)) {
      if (lastListedEventTitles.isEmpty) {
        return 'Ava: diga de qual reunião quer as notas. Antes pergunte por exemplo: quais reuniões tenho hoje, ou: notas da reunião orçamento.';
      }
      final idx = whichListed == 'second' && lastListedEventTitles.length > 1 ? 1 : 0;
      title = lastListedEventTitles[idx];
      debugLog('Assistant', 'readMeetingNotes contexto: $whichListed -> $title');
    }
    try {
      String? eventId;
      String? matchedTitle;
      if (startIso != null && startIso.isNotEmpty) {
        final startDt = DateTime.tryParse(startIso);
        if (startDt == null) return 'Ava: não consegui identificar o horário.';
        final windowStart = startDt.subtract(const Duration(minutes: 30));
        final windowEnd = startDt.add(const Duration(hours: 2));
        final startStr = windowStart.toUtc().toIso8601String();
        final endStr = windowEnd.toUtc().toIso8601String();
        final eventsList = await Supabase.instance.client
            .from('events')
            .select('id, title, start_time')
            .eq('user_id', uid)
            .gte('start_time', startStr)
            .lte('start_time', endStr)
            .order('start_time', ascending: true);
        final events = eventsList as List;
        if (events.isEmpty) return 'Ava: não encontrei reunião nesse horário.';
        final e = events.first;
        eventId = e['id'] as String?;
        matchedTitle = e['title'] as String?;
      } else {
        final titleNorm = _normalizeForMatch(title);
        final eventsList = await Supabase.instance.client
            .from('events')
            .select('id, title')
            .eq('user_id', uid)
            .order('start_time', ascending: false);
        final events = eventsList as List;
        for (final e in events) {
          final t = _normalizeForMatch(e['title'] as String? ?? '');
          if (t.contains(titleNorm) || titleNorm.contains(t) || t == titleNorm) {
            eventId = e['id'] as String?;
            matchedTitle = e['title'] as String?;
            break;
          }
        }
        if (eventId == null) return 'Ava: não encontrei reunião com "$title".';
      }
      if (eventId == null || matchedTitle == null) return 'Ava: não encontrei essa reunião.';
      final notesList = await Supabase.instance.client
          .from('meeting_notes')
          .select('id, title, content, created_at')
          .eq('event_id', eventId)
          .order('created_at', ascending: true);
      final notes = notesList as List;
      if (notes.isEmpty) return 'Ava: não há notas para a reunião $matchedTitle.';
      final buffer = StringBuffer();
      buffer.write('Ava: notas da reunião $matchedTitle. ');
      for (final n in notes) {
        final content = n['content'] as String? ?? '';
        final noteTitle = n['title'] as String?;
        if (noteTitle != null && noteTitle.trim().isNotEmpty) buffer.write('$noteTitle: ');
        if (content.length > 500) {
          buffer.write('${content.substring(0, 497)}... ');
        } else {
          buffer.write('$content ');
        }
      }
      return buffer.toString().trim();
    } catch (e) {
      debugLog('Assistant', 'readMeetingNotes: $e');
      return 'Ava não conseguiu buscar as notas.';
    }
  }

  /// Cancela evento pelo título (busca por similaridade).
  /// Se [eventTitle] vazio e [whichListed] for 'first' ou 'second', usa lastListedEventTitles.
  static Future<String> cancelEvent(String eventTitle, {String? whichListed}) async {
    final uid = _userId;
    if (uid == null) return 'Ava: faça login para gerenciar eventos.';
    var title = eventTitle.trim();
    if (title.isEmpty && whichListed != null && lastListedEventTitles.isNotEmpty) {
      final idx = whichListed == 'second' && lastListedEventTitles.length > 1 ? 1 : 0;
      title = lastListedEventTitles[idx];
    }
    if (title.isEmpty) return 'Ava: diga qual evento ou reunião deseja cancelar. Antes pergunte: quais reuniões tenho hoje.';
    try {
      final list = await Supabase.instance.client
          .from('events')
          .select('id, title')
          .eq('user_id', uid)
          .eq('status', 'scheduled')
          .order('start_time', ascending: false);

      final events = list as List;
      final titleLower = title.toLowerCase().trim();
      Map<String, dynamic>? match;
      for (final e in events) {
        final t = (e['title'] as String? ?? '').toLowerCase();
        if (t.contains(titleLower) || titleLower.contains(t) || t == titleLower) {
          match = e as Map<String, dynamic>;
          break;
        }
      }
      if (match == null) return 'Ava: não encontrei o evento "$title".';
      final id = match['id'] as String;
      final matchedTitle = match['title'] as String? ?? title;
      await Supabase.instance.client.from('events').update({'status': 'cancelled'}).eq('id', id);
      debugLog('Assistant', 'cancelEvent ok: $id');
      return 'Ava cancelou o evento "$matchedTitle".';
    } catch (e) {
      debugLog('Assistant', 'cancelEvent: $e');
      return 'Ava não conseguiu cancelar o evento.';
    }
  }

  /// Remarca evento; se já existir outro no mesmo horário, avisa e não altera.
  /// Se [eventTitle] vazio e [whichListed] for 'first' ou 'second', usa lastListedEventTitles.
  static Future<String> rescheduleEvent(String eventTitle, String newStartIso, String newEndIso, {String? whichListed}) async {
    final uid = _userId;
    if (uid == null) return 'Ava: faça login para gerenciar eventos.';
    var title = eventTitle.trim();
    if (title.isEmpty && whichListed != null && lastListedEventTitles.isNotEmpty) {
      final idx = whichListed == 'second' && lastListedEventTitles.length > 1 ? 1 : 0;
      title = lastListedEventTitles[idx];
    }
    if (title.isEmpty) return 'Ava: diga qual evento remarcar e para quando. Ex.: remarca a primeira para amanhã às 15h.';
    try {
      final list = await Supabase.instance.client
          .from('events')
          .select('id, title, start_time, end_time')
          .eq('user_id', uid)
          .eq('status', 'scheduled')
          .order('start_time', ascending: false);

      final events = list as List;
      final titleLower = title.toLowerCase().trim();
      Map<String, dynamic>? match;
      for (final e in events) {
        final t = (e['title'] as String? ?? '').toLowerCase();
        if (t.contains(titleLower) || titleLower.contains(t) || t == titleLower) {
          match = e as Map<String, dynamic>;
          break;
        }
      }
      if (match == null) return 'Ava: não encontrei o evento "$title".';

      final eventId = match['id'] as String;
      final matchedTitle = match['title'] as String? ?? title;

      // Conflito: outro evento do usuário (id diferente) no mesmo horário
      final overlapping = await Supabase.instance.client
          .from('events')
          .select('id, title')
          .eq('user_id', uid)
          .eq('status', 'scheduled')
          .neq('id', eventId)
          .lt('start_time', newEndIso)
          .gt('end_time', newStartIso);

      final overlaps = overlapping as List;
      if (overlaps.isNotEmpty) {
        final other = overlaps.first as Map<String, dynamic>;
        final otherTitle = other['title'] as String? ?? 'outro evento';
        return 'Ava: já existe um evento nesse horário — $otherTitle. Não foi possível remarcar.';
      }

      await Supabase.instance.client
          .from('events')
          .update({'start_time': newStartIso, 'end_time': newEndIso})
          .eq('id', eventId);
      debugLog('Assistant', 'rescheduleEvent ok: $eventId');
      final timeStr = _formatTimeForSpeech(newStartIso);
      return 'Ava remarcou o evento "$matchedTitle" para $timeStr.';
    } catch (e) {
      debugLog('Assistant', 'rescheduleEvent: $e');
      return 'Ava não conseguiu remarcar o evento.';
    }
  }

  /// Horário atual em frase para falar.
  static Future<String> getCurrentTimeSpeech() async {
    final now = DateTime.now();
    final h = now.hour;
    final m = now.minute;
    if (m == 0) {
      return 'Ava: são ${h == 0 ? "meia-noite" : h == 12 ? "meio-dia" : "$h horas"} em ponto.';
    }
    final minStr = m == 1 ? '1 minuto' : '$m minutos';
    if (h == 0) return 'Ava: são zero hora e $minStr.';
    if (h == 12) return 'Ava: são meio-dia e $minStr.';
    return 'Ava: são $h horas e $minStr.';
  }

  /// Clima atual (Open-Meteo, São Paulo como padrão).
  static Future<String> getWeatherSpeech() async {
    const lat = '-23.55';
    const lon = '-46.63';
    const tz = 'America/Sao_Paulo';
    final url = Uri.parse(
      'https://api.open-meteo.com/v1/forecast?latitude=$lat&longitude=$lon&current=temperature_2m,relative_humidity_2m,weather_code&timezone=$tz',
    );
    try {
      final res = await http.get(url).timeout(const Duration(seconds: 8));
      if (res.statusCode != 200) return 'Ava: não consegui obter o clima agora.';
      final data = jsonDecode(res.body) as Map<String, dynamic>?;
      final current = data?['current'] as Map<String, dynamic>?;
      if (current == null) return 'Ava: não consegui obter o clima.';
      final temp = (current['temperature_2m'] as num?)?.toDouble();
      final humidity = current['relative_humidity_2m'] as int?;
      final code = current['weather_code'] as int? ?? 0;
      final tempStr = temp != null ? '${temp.round()} graus' : '';
      final cond = _weatherCodeToPhrase(code);
      final humStr = humidity != null ? ' Umidade $humidity por cento.' : '';
      return 'Ava: $cond${tempStr.isNotEmpty ? ". $tempStr." : ""}$humStr';
    } catch (e) {
      debugLog('Assistant', 'getWeather: $e');
      return 'Ava: não consegui obter o clima.';
    }
  }

  static String _weatherCodeToPhrase(int code) {
    if (code == 0) return 'Céu limpo';
    if (code <= 3) return 'Parcialmente nublado';
    if (code <= 49) return 'Neblina';
    if (code <= 67) return 'Chovendo';
    if (code <= 77) return 'Nevando';
    if (code <= 82) return 'Chuva passageira';
    if (code <= 86) return 'Neve com trovoada';
    if (code <= 99) return 'Trovoadas';
    return 'Condição $code';
  }

  /// Pesquisa ou notícias via resumo Wikipedia (pt).
  static Future<String> getSearchOrNewsSpeech(String query) async {
    if (query.trim().isEmpty) return 'Ava: diga o que deseja pesquisar ou sobre quais notícias.';
    final title = Uri.encodeComponent(query.trim().replaceAll(' ', '_'));
    final url = Uri.parse(
      'https://pt.wikipedia.org/api/rest_v1/page/summary/$title',
    );
    try {
      final res = await http.get(url).timeout(const Duration(seconds: 10));
      if (res.statusCode != 200) return 'Ava: não encontrei nada sobre "$query".';
      final data = jsonDecode(res.body) as Map<String, dynamic>?;
      final extract = data?['extract'] as String?;
      if (extract == null || extract.isEmpty) {
        return 'Ava: não encontrei um resumo sobre "$query".';
      }
      final short = extract.length > 400 ? '${extract.substring(0, 397)}...' : extract;
      return 'Ava: $short';
    } catch (e) {
      debugLog('Assistant', 'getSearch: $e');
      return 'Ava: não consegui pesquisar agora.';
    }
  }

  /// Executa o comando e retorna mensagem de feedback.
  static Future<String> execute(VoiceCommand command) async {
    final p = command.params;
    switch (command.type) {
      case VoiceCommandType.createMeeting:
        final title = p?['title'] ?? 'Reunião';
        final err = await createMeeting(
          title: title,
          startIso: p?['start_iso'],
          endIso: p?['end_iso'],
        );
        return err ?? 'Ava criou a reunião.';
      case VoiceCommandType.takeNotes:
        final ok = await takeNote(content: command.raw);
        return ok ? 'Ava anotou.' : 'Ava não conseguiu salvar a nota.';
      case VoiceCommandType.viewCalendar: {
        final now = DateTime.now();
        final today = '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
        return await listEvents(today);
      }
      case VoiceCommandType.scheduleEvent:
        final title = p?['title'] ?? 'Evento';
        final err = await createMeeting(
          title: title,
          startIso: p?['start_iso'],
          endIso: p?['end_iso'],
        );
        return err ?? 'Ava marcou o evento.';
      case VoiceCommandType.addParticipants:
        return 'Ava: diga o evento e os e-mails para adicionar participantes.';
      case VoiceCommandType.addNoteToMeeting:
        final content = p?['content'] ?? '';
        final whichListed = p?['which_listed'];
        if (content.isEmpty) return 'Ava: diga o texto da nota. Ex.: adicione uma nota nessa reunião bom dia.';
        return await addNoteToMeeting(content, whichListed: whichListed);
      case VoiceCommandType.listEvents:
        var queryDate = p?['query_date_iso'] ?? '';
        if (queryDate.isEmpty) {
          final now = DateTime.now();
          queryDate = '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
        }
        return await listEvents(queryDate);
      case VoiceCommandType.cancelEvent:
        final title = p?['event_title'] ?? '';
        final whichListed = p?['which_listed'];
        if (title.isEmpty && whichListed == null) return 'Ava: diga qual evento ou reunião deseja cancelar. Antes pergunte: quais reuniões tenho hoje.';
        return await cancelEvent(title, whichListed: whichListed);
      case VoiceCommandType.rescheduleEvent:
        final title = p?['event_title'] ?? '';
        final whichListed = p?['which_listed'];
        final startIso = p?['start_iso'] ?? '';
        final endIso = p?['end_iso'] ?? '';
        if (startIso.isEmpty || endIso.isEmpty) {
          return 'Ava: diga para quando remarcar. Ex.: remarca a primeira para amanhã às 15h.';
        }
        if (title.isEmpty && whichListed == null) return 'Ava: diga qual evento remarcar. Ex.: remarca a primeira para amanhã às 15h.';
        return await rescheduleEvent(title, startIso, endIso, whichListed: whichListed);
      case VoiceCommandType.listReminders:
        final eventTitle = p?['event_title'] ?? '';
        final whichListed = p?['which_listed'];
        if (eventTitle.trim().isNotEmpty) {
          return await readRemindersForEvent(eventTitle.trim());
        }
        if (whichListed != null && (whichListed == 'first' || whichListed == 'second')) {
          return await readRemindersForEvent('', whichListed: whichListed);
        }
        return await listReminders();
      case VoiceCommandType.readMeetingNotes:
        final meetingTitle = p?['meeting_title'] ?? '';
        final whichListed = p?['which_listed'];
        final startIso = p?['start_iso'];
        return await readMeetingNotesByTitle(meetingTitle, whichListed: whichListed, startIso: startIso);
      case VoiceCommandType.listMeetingsThisWeek:
        return await listMeetingsThisWeek();
      case VoiceCommandType.listEventsWithNotes:
        return await listEventsWithNotes();
      case VoiceCommandType.listEventsWithReminders:
        return await listEventsWithReminders();
      case VoiceCommandType.listActionItems:
        return await listActionItems();
      case VoiceCommandType.listPeople:
        return await listPeople();
      case VoiceCommandType.askWhatCanDo:
        return await getWhatCanDoSpeech();
      case VoiceCommandType.askTime:
        return await getCurrentTimeSpeech();
      case VoiceCommandType.askWeather:
        return await getWeatherSpeech();
      case VoiceCommandType.searchInfo:
        final query = p?['query'] ?? '';
        return await getSearchOrNewsSpeech(query);
      case VoiceCommandType.exitAssistant:
        return ''; // Tratado em main.dart (minimiza e moveToBack)
      case VoiceCommandType.unknown:
        return '';
    }
  }
}
