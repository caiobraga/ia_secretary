/// Monta texto de voz e de notificação a partir de um reminder + evento + participantes (Supabase).
class ReminderRichContext {
  ReminderRichContext({
    required this.eventId,
    required this.eventTitle,
    this.eventDescription,
    this.startLocal,
    this.endLocal,
    this.location,
    this.participantNames = const [],
    this.reminderDescription,
  });

  /// ID do evento no banco (para contexto; na fala usamos título + data).
  final String eventId;
  final String eventTitle;
  final String? eventDescription;
  final DateTime? startLocal;
  final DateTime? endLocal;
  final String? location;
  final List<String> participantNames;
  final String? reminderDescription;

  static Map<String, dynamic>? _asJsonMap(dynamic raw) {
    if (raw == null) return null;
    if (raw is Map<String, dynamic>) return raw;
    if (raw is Map) return Map<String, dynamic>.from(raw);
    if (raw is List && raw.isNotEmpty) {
      final first = raw.first;
      if (first is Map) return Map<String, dynamic>.from(first);
    }
    return null;
  }

  static Iterable<Map<String, dynamic>> _participantRows(dynamic raw) sync* {
    if (raw == null) return;
    if (raw is List) {
      for (final p in raw) {
        if (p is Map) yield Map<String, dynamic>.from(p);
      }
      return;
    }
    if (raw is Map) yield Map<String, dynamic>.from(raw);
  }

  static const _meses = [
    'janeiro', 'fevereiro', 'março', 'abril', 'maio', 'junho',
    'julho', 'agosto', 'setembro', 'outubro', 'novembro', 'dezembro',
  ];

  static ReminderRichContext? fromReminderRow(Map<String, dynamic> row) {
    final ev = _asJsonMap(row['events']);
    if (ev == null) return null;

    final eid = (ev['id'] as String?) ?? (row['event_id'] as String?);
    if (eid == null || eid.isEmpty) return null;

    final title = (ev['title'] as String?)?.trim();
    if (title == null || title.isEmpty) return null;

    return _fromEventMap(ev, row, eventId: eid);
  }

  /// Quando o embed veio em query separada (fallback por [event_id]).
  static ReminderRichContext? fromEventMapAndReminder(
    Map<String, dynamic> event,
    Map<String, dynamic> reminderRow,
  ) {
    final eid = (event['id'] as String?)?.trim();
    if (eid == null || eid.isEmpty) return null;
    return _fromEventMap(event, reminderRow, eventId: eid);
  }

  static ReminderRichContext? _fromEventMap(
    Map<String, dynamic> ev,
    Map<String, dynamic> row, {
    required String eventId,
  }) {
    final title = (ev['title'] as String?)?.trim();
    if (title == null || title.isEmpty) return null;

    DateTime? start;
    DateTime? end;
    try {
      final s = ev['start_time'] as String?;
      if (s != null) start = DateTime.parse(s).toLocal();
      final e = ev['end_time'] as String?;
      if (e != null) end = DateTime.parse(e).toLocal();
    } catch (_) {}

    final loc = (ev['location'] as String?)?.trim();
    final desc = (ev['description'] as String?)?.trim();
    final rem = (row['description'] as String?)?.trim();

    final names = <String>[];
    for (final p in _participantRows(ev['event_participants'])) {
      final n = (p['name'] as String?)?.trim();
      final em = (p['email'] as String?)?.trim();
      if (n != null && n.isNotEmpty) {
        names.add(n);
      } else if (em != null && em.isNotEmpty) {
        names.add(em);
      }
    }

    return ReminderRichContext(
      eventId: eventId,
      eventTitle: title,
      eventDescription: desc?.isNotEmpty == true ? desc : null,
      startLocal: start,
      endLocal: end,
      location: loc?.isNotEmpty == true ? loc : null,
      participantNames: names,
      reminderDescription: rem?.isNotEmpty == true ? rem : null,
    );
  }

  String _formatDataHora(DateTime dt) {
    final d = dt.day;
    final m = _meses[dt.month - 1];
    final y = dt.year;
    final h = dt.hour;
    final min = dt.minute.toString().padLeft(2, '0');
    if (min == '00') return 'dia $d de $m de $y, às ${h}h';
    return 'dia $d de $m de $y, às ${h}h$min';
  }

  /// Uma linha para o corpo colapsado da notificação.
  String compactSummary() {
    final buf = StringBuffer();
    if (startLocal != null) {
      buf.write('Reunião: ${_formatDataHora(startLocal!)}');
    } else {
      buf.write('Evento: $eventTitle');
    }
    if (participantNames.isNotEmpty) {
      buf.write(' · ${participantNames.take(3).join(', ')}');
      if (participantNames.length > 3) buf.write('…');
    }
    return buf.toString();
  }

  /// Texto longo para BigText / leitura na bandeja (funciona com app em background).
  String expandedBigText() {
    final lines = <String>[];
    lines.add('Evento: $eventTitle');
    lines.add('Referência do evento: $eventId');
    if (startLocal != null) {
      lines.add('Data e horário da reunião: ${_formatDataHora(startLocal!)}.');
      if (endLocal != null) {
        final eh = endLocal!.hour;
        final em = endLocal!.minute.toString().padLeft(2, '0');
        lines.add('Término previsto: às ${eh}h$em.');
      }
    }
    if (location != null) lines.add('Local: $location.');
    if (eventDescription != null) lines.add('Sobre o evento: $eventDescription.');
    if (participantNames.isNotEmpty) {
      if (participantNames.length == 1) {
        lines.add('Participante: ${participantNames.first}.');
      } else {
        lines.add('Participantes: ${_formatNamesPt(participantNames)}.');
      }
    }
    if (reminderDescription != null) {
      lines.add('Este lembrete: $reminderDescription.');
    } else {
      lines.add('Lembrete ligado a este evento.');
    }
    return lines.join('\n');
  }

  static String _formatNamesPt(List<String> names) {
    if (names.isEmpty) return '';
    if (names.length == 1) return names.first;
    if (names.length == 2) return '${names[0]} e ${names[1]}';
    return '${names.sublist(0, names.length - 1).join(', ')} e ${names.last}';
  }

  /// Frase para TTS (Ava) — data e participantes antes do texto longo do lembrete.
  String speechPhrase() {
    final parts = <String>[];
    parts.add('Lembrete ligado ao evento "$eventTitle".');
    if (startLocal != null) {
      parts.add('Data e horário da reunião: ${_formatDataHora(startLocal!)}.');
    } else {
      parts.add('Não há data de início cadastrada para esse evento no calendário.');
    }
    if (location != null) {
      parts.add('Local: $location.');
    }
    if (participantNames.isNotEmpty) {
      parts.add('Participantes: ${_formatNamesPt(participantNames)}.');
    }
    if (eventDescription != null) {
      parts.add(_clipForSpeech('Sobre o evento: $eventDescription.', 220));
    }
    if (reminderDescription != null) {
      parts.add(_clipForSpeech('Texto do lembrete: $reminderDescription.', 260));
    }
    var s = 'Ava: ${parts.join(' ')}';
    if (s.length > 900) s = '${s.substring(0, 897)}...';
    return s;
  }

  static String _clipForSpeech(String line, int maxChars) {
    if (line.length <= maxChars) return line;
    return '${line.substring(0, maxChars - 3)}...';
  }

  String notificationTitle() => 'Lembrete · $eventTitle';
}
