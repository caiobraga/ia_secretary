/// Comandos de voz em português reconhecidos pela Ava (assistente).
enum VoiceCommandType {
  createMeeting,
  takeNotes,
  viewCalendar,
  scheduleEvent,
  addParticipants,
  addNoteToMeeting,
  listEvents,
  cancelEvent,
  rescheduleEvent,
  listReminders,
  readMeetingNotes,
  listMeetingsThisWeek,
  listEventsWithNotes,
  listEventsWithReminders,
  listActionItems,
  listPeople,
  askWhatCanDo,
  askTime,
  askWeather,
  searchInfo,
  exitAssistant,
  unknown,
}

class VoiceCommand {
  VoiceCommand({required this.type, required this.raw, this.params});
  final VoiceCommandType type;
  final String raw;
  /// Params extraídos da fala: start_iso (DateTime início), end_iso (opcional), title (opcional).
  final Map<String, String>? params;
}

/// Normaliza texto para comparação (minúsculo, sem acentos).
/// Comandos aceitam variantes de STT (ex.: "reunio"/"reuniao"/"reunioes", "qual"/"quais").
String _normalize(String s) {
  const withAccents = 'áàâãéèêíìîóòôõúùûç';
  const withoutAccents = 'aaaaeeeiiioooouuuc';
  String t = s.toLowerCase().trim();
  for (int i = 0; i < withAccents.length; i++) {
    t = t.replaceAll(withAccents[i], withoutAccents[i]);
  }
  // Corrige erros comuns do STT (modelo pequeno) antes do parsing
  t = _fixCommonSttErrors(t);
  return t;
}

/// Corrige erros frequentes do Vosk modelo pequeno em português.
/// Ex.: "quais reuniões atenção" → "quais reuniões tenho"
String _fixCommonSttErrors(String s) {
  String result = s;
  
  // Aplica correções em ordem de prioridade (frases longas primeiro)
  for (final fix in _sttFixes) {
    if (result.contains(fix.key)) {
      result = result.replaceAll(fix.key, fix.value);
    }
  }
  
  // Correção adicional: palavras separadas por espaço incorretamente
  result = _fixSplitWords(result);
  
  return result;
}

/// Lista de correções ordenadas por tamanho (maior primeiro para evitar conflitos)
final _sttFixes = <MapEntry<String, String>>[
  // Frases completas / trechos longos
  MapEntry('quais reunioes atencao', 'quais reunioes tenho'),
  MapEntry('reunioes atencao', 'reunioes tenho'),
  MapEntry('e sa semana', 'essa semana'),
  MapEntry('essa mana', 'essa semana'),
  MapEntry('e semana', 'essa semana'),
  MapEntry('de sa semana', 'dessa semana'),
  MapEntry('ne sa semana', 'nessa semana'),
  MapEntry('secreta ria', 'secretaria'),
  MapEntry('secre taria', 'secretaria'),
  MapEntry('calenda rio', 'calendario'),
  
  // "tenho" - muito comum errar
  MapEntry('atencao', 'tenho'),
  MapEntry('atensao', 'tenho'),
  MapEntry('a tensao', 'tenho'),
  MapEntry('tem nho', 'tenho'),
  MapEntry('ten ho', 'tenho'),
  MapEntry('tenio', 'tenho'),
  MapEntry('te nho', 'tenho'),
  
  // "reunião" - muito comum errar
  MapEntry('retina', 'reuniao'),
  MapEntry('reunia o', 'reuniao'),
  MapEntry('reuni ao', 'reuniao'),
  MapEntry('re uniao', 'reuniao'),
  MapEntry('reunio', 'reuniao'),
  MapEntry('reuni ao', 'reuniao'),
  MapEntry('reu niao', 'reuniao'),
  MapEntry('reunioes', 'reunioes'),
  MapEntry('reuiniao', 'reuniao'),
  MapEntry('reuniaos', 'reunioes'),
  MapEntry('reunia', 'reuniao'),
  
  // "evento"
  MapEntry('e vento', 'evento'),
  MapEntry('evendo', 'evento'),
  MapEntry('even to', 'evento'),
  MapEntry('e ven to', 'evento'),
  
  // "amanhã"
  MapEntry('a manha', 'amanha'),
  MapEntry('a manha', 'amanha'),
  MapEntry('ama nha', 'amanha'),
  MapEntry('amana', 'amanha'),
  
  // "hoje"
  MapEntry('o je', 'hoje'),
  MapEntry('ho je', 'hoje'),
  MapEntry('oje', 'hoje'),
  
  // "semana"
  MapEntry('se mana', 'semana'),
  MapEntry('sema na', 'semana'),
  
  // "calendário"
  MapEntry('calenda', 'calendario'),
  MapEntry('calen dario', 'calendario'),
  
  // "agenda"
  MapEntry('a genda', 'agenda'),
  MapEntry('agen da', 'agenda'),
  
  // "nota/notas"
  MapEntry('no ta', 'nota'),
  MapEntry('no tas', 'notas'),
  
  // "lembrete"
  MapEntry('lem brete', 'lembrete'),
  MapEntry('lembre te', 'lembrete'),
  
  // "compromisso"
  MapEntry('compro misso', 'compromisso'),
  MapEntry('compromiso', 'compromisso'),
  
  // "quais/qual"
  MapEntry('qua is', 'quais'),
  MapEntry('qua l', 'qual'),
  MapEntry('kuais', 'quais'),
  MapEntry('kual', 'qual'),
  
  // "criar/crie/cria"
  MapEntry('cri ar', 'criar'),
  MapEntry('cri e', 'crie'),
  MapEntry('cri a', 'cria'),
  
  // "marcar/marque"
  MapEntry('mar car', 'marcar'),
  MapEntry('mar que', 'marque'),
  MapEntry('mar ca', 'marca'),
  
  // "agendar"
  MapEntry('agen dar', 'agendar'),
  MapEntry('agen de', 'agende'),
  
  // "cancelar"
  MapEntry('cance lar', 'cancelar'),
  MapEntry('cance la', 'cancela'),
  
  // "remarcar"
  MapEntry('remar car', 'remarcar'),
  MapEntry('remar ca', 'remarca'),
  
  // "mostrar/mostrei"
  MapEntry('mos trar', 'mostrar'),
  MapEntry('mos tre', 'mostre'),
  MapEntry('mos tra', 'mostra'),
  
  // "listar"
  MapEntry('lis tar', 'listar'),
  MapEntry('lis ta', 'lista'),
  
  // "ver"
  MapEntry('ve r', 'ver'),
  
  // "pesquisar"
  MapEntry('pesqui sar', 'pesquisar'),
  MapEntry('pesqui se', 'pesquise'),
  
  // "clima/tempo"
  MapEntry('cli ma', 'clima'),
  MapEntry('tem po', 'tempo'),
  
  // "horas"
  MapEntry('ho ras', 'horas'),
  MapEntry('hora s', 'horas'),
  
  // Dias da semana
  MapEntry('segun da', 'segunda'),
  MapEntry('ter ca', 'terca'),
  MapEntry('quar ta', 'quarta'),
  MapEntry('quin ta', 'quinta'),
  MapEntry('sex ta', 'sexta'),
  MapEntry('saba do', 'sabado'),
  MapEntry('domin go', 'domingo'),
  
  // "feira"
  MapEntry('fei ra', 'feira'),
  
  // Palavras comuns
  MapEntry('voce', 'voce'),
  MapEntry('vo ce', 'voce'),
  MapEntry('mi nha', 'minha'),
  MapEntry('mi nhas', 'minhas'),
  MapEntry('me us', 'meus'),
  MapEntry('me u', 'meu'),
  
  // "participante"
  MapEntry('parti cipante', 'participante'),
  MapEntry('participan te', 'participante'),
  
  // Sair/fechar
  MapEntry('sa ir', 'sair'),
  MapEntry('fe char', 'fechar'),
  MapEntry('mini mizar', 'minimizar'),
];

/// Corrige palavras que foram divididas incorretamente
String _fixSplitWords(String s) {
  // Padrões de palavras comumente divididas
  final patterns = <RegExp, String>{
    RegExp(r'\bre\s*uni[aã]o\b'): 'reuniao',
    RegExp(r'\bre\s*uni[oõ]es\b'): 'reunioes',
    RegExp(r'\bse\s*cret[aá]ria\b'): 'secretaria',
    RegExp(r'\bca\s*lend[aá]rio\b'): 'calendario',
    RegExp(r'\ba\s*gen\s*da\b'): 'agenda',
    RegExp(r'\be\s*ven\s*to\b'): 'evento',
    RegExp(r'\ba\s*ma\s*nh[aã]\b'): 'amanha',
    RegExp(r'\bho\s*je\b'): 'hoje',
    RegExp(r'\bse\s*ma\s*na\b'): 'semana',
    RegExp(r'\bcom\s*pro\s*mis\s*so\b'): 'compromisso',
    RegExp(r'\blem\s*bre\s*te\b'): 'lembrete',
  };
  
  String result = s;
  for (final entry in patterns.entries) {
    result = result.replaceAll(entry.key, entry.value);
  }
  return result;
}

// --- Extração de data e hora do texto em português ---

const _months = {
  'janeiro': 1, 'fevereiro': 2, 'marco': 3, 'abril': 4, 'maio': 5, 'junho': 6,
  'julho': 7, 'agosto': 8, 'setembro': 9, 'outubro': 10, 'novembro': 11, 'dezembro': 12,
};

const _weekdays = {
  'domingo': 7, 'segunda': 1, 'terca': 2, 'quarta': 3, 'quinta': 4, 'sexta': 5, 'sabado': 6,
  'segunda-feira': 1, 'terca-feira': 2, 'quarta-feira': 3, 'quinta-feira': 4, 'sexta-feira': 5,
};

/// Horas por extenso em português (0–23) para reconhecer "quinze horas", "nove horas", etc.
const _wordHours = <String, int>{
  'meia-noite': 0, 'zero': 0,
  'uma': 1, 'duas': 2, 'tres': 3, 'quatro': 4, 'cinco': 5, 'seis': 6, 'sete': 7, 'oito': 8, 'nove': 9,
  'dez': 10, 'onze': 11, 'doze': 12, 'meio-dia': 12,
  'treze': 13, 'catorze': 14, 'quatorze': 14, 'quinze': 15, 'dezesseis': 16, 'dezessete': 17,
  'dezoito': 18, 'dezenove': 19, 'vinte': 20, 'vinte e uma': 21, 'vinte e duas': 22, 'vinte e tres': 23,
};

/// Extrai hora e minuto do texto (ex: "às 15h", "14 horas", "quinze horas", "nove horas e meia").
({int hour, int minute})? _parseTime(String normalized) {
  int? hour;
  int minute = 0;

  // Padrões numéricos: "as 14h", "14h30", "14 horas", "às 9:30"
  final withH = RegExp(r'(?:as\s+)?(\d{1,2})\s*(?:h|:)\s*(\d{1,2})?');
  final withHoras = RegExp(r'\b(\d{1,2})\s+horas?(?:\s+e\s+meia)?');
  var match = withH.firstMatch(normalized);
  if (match != null) {
    hour = int.tryParse(match.group(1)!);
    if (match.group(2) != null && match.group(2)!.isNotEmpty) {
      minute = int.tryParse(match.group(2)!) ?? 0;
    } else if (normalized.contains('e meia')) {
      minute = 30;
    }
  } else {
    match = withHoras.firstMatch(normalized);
    if (match != null) {
      hour = int.tryParse(match.group(1)!);
      if (normalized.contains('e meia')) minute = 30;
    }
  }

  // Horas por extenso: "quinze horas", "nove horas e meia", "às dez horas"
  if (hour == null) {
    for (final entry in _wordHours.entries) {
      final pattern = RegExp(
        r'(?:as\s+)?' + RegExp.escape(entry.key) + r'\s+horas?(?:\s+e\s+meia)?',
        caseSensitive: false,
      );
      if (pattern.hasMatch(normalized)) {
        hour = entry.value;
        if (normalized.contains('e meia')) minute = 30;
        break;
      }
    }
  }

  if (hour != null && hour >= 0 && hour <= 23 && minute >= 0 && minute <= 59) {
    return (hour: hour, minute: minute);
  }
  return null;
}

/// Extrai a data do texto (hoje, amanhã, dia N, dia N de mês, próxima segunda, etc.).
DateTime? _parseDate(String normalized) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);

  if (normalized.contains('hoje')) return today;
  if (normalized.contains('amanha')) return today.add(const Duration(days: 1));
  if (normalized.contains('depois de amanha')) return today.add(const Duration(days: 2));

  // "dia 15", "dia 20"
  final dayNum = RegExp(r'dia\s+(\d{1,2})(?:\s+de\s+(\w+))?');
  final dayMatch = dayNum.firstMatch(normalized);
  if (dayMatch != null) {
    final d = int.tryParse(dayMatch.group(1)!);
    if (d == null || d < 1 || d > 31) return null;
    if (dayMatch.group(2) != null) {
      final monthName = _normalize(dayMatch.group(2)!.replaceAll('-', ''));
      final month = _months[monthName];
      if (month != null) {
        final y = now.year;
        try {
          return DateTime(y, month, d);
        } catch (_) {
          return null;
        }
      }
    }
    try {
      return DateTime(now.year, now.month, d);
    } catch (_) {
      return DateTime(now.year, now.month + 1, d);
    }
  }

  // "15/03", "20/12"
  final slash = RegExp(r'\b(\d{1,2})/(\d{1,2})(?:/(\d{2,4}))?');
  final slashM = slash.firstMatch(normalized);
  if (slashM != null) {
    final d = int.tryParse(slashM.group(1)!);
    final m = int.tryParse(slashM.group(2)!);
    final y = slashM.group(3) != null ? int.tryParse(slashM.group(3)!) : now.year;
    if (d != null && m != null && m >= 1 && m <= 12 && d >= 1 && d <= 31) {
      final year = y != null && y > 100 ? y : (y != null && y < 100 ? 2000 + y : now.year);
      try {
        return DateTime(year, m, d);
      } catch (_) {}
    }
  }

  // "próxima segunda", "proxima segunda-feira"
  for (final entry in _weekdays.entries) {
    if (normalized.contains('proxim') && normalized.contains(entry.key)) {
      final w = entry.value;
      int diff = w - now.weekday;
      if (diff <= 0) diff += 7;
      return today.add(Duration(days: diff));
    }
  }

  // "reuniões de segunda feira", "eventos de segunda", "agenda de terça" (próxima ocorrência do dia da semana)
  final nFeira = normalized.replaceAll(' feira', '-feira');
  for (final entry in _weekdays.entries) {
    if (nFeira.contains(entry.key)) {
      final w = entry.value;
      int diff = w - now.weekday;
      if (diff < 0) diff += 7;
      return today.add(Duration(days: diff));
    }
  }

  return null;
}

/// Extrai título do evento/reunião (texto entre aspas ou após "chamada X" / "sobre X").
String? _parseTitle(String raw, String normalized) {
  final quoted = RegExp("[\"']([^\"']+)[\"']");
  final q = quoted.firstMatch(raw);
  if (q != null) return q.group(1)!.trim();
  // "reunião sobre orçamento" -> "orçamento"; "evento dentista" -> "dentista"
  final dateTimePattern = RegExp(r'(?:as\s+\d|dia\s+\d|\d{1,2}h|\d{1,2}\s+horas)');
  for (final prefix in ['sobre ', 'reuniao sobre ', 'evento ', 'reuniao ', 'encontro ']) {
    if (normalized.contains(prefix)) {
      final start = normalized.indexOf(prefix) + prefix.length;
      String rest = normalized.substring(start);
      final match = dateTimePattern.firstMatch(rest);
      if (match != null) rest = rest.substring(0, match.start).trim();
      rest = rest.split(RegExp(r'\s+')).take(5).join(' ');
      if (rest.length > 1) return rest.trim();
    }
  }
  return null;
}

/// Extrai só a data (para consulta "tenho eventos amanhã?") — retorna query_date_iso YYYY-MM-DD.
Map<String, String>? _extractQueryDateParams(String normalized) {
  final date = _parseDate(normalized);
  if (date == null) return null;
  final y = date.year;
  final m = date.month.toString().padLeft(2, '0');
  final d = date.day.toString().padLeft(2, '0');
  return {'query_date_iso': '$y-$m-$d'};
}

/// Extrai título da reunião para ler notas (ex: "notas da reunião orçamento" -> orçamento).
String? _extractMeetingTitleForNotes(String normalized) {
  const prefixes = [
    'notas da reuniao ', 'nota da reuniao ', 'anotado na reuniao ', 'resumo da reuniao ',
    'ler notas da reuniao ', 'ata da reuniao ', 'o que foi anotado na reuniao ',
  ];
  for (final prefix in prefixes) {
    if (normalized.contains(prefix)) {
      int start = normalized.indexOf(prefix) + prefix.length;
      String rest = normalized.substring(start).trim();
      if (rest.length > 1) return rest.split(RegExp(r'\s+')).take(6).join(' ').trim();
    }
  }
  return null;
}

/// Extrai título do evento para cancelar/remarcar (ex: "cancela o evento dentista" -> dentista).
String? _extractEventTitleForAction(String normalized, {required bool forReschedule}) {
  // "cancela o evento X" / "cancela a reunião X" / "remarca o evento X para ..."
  final cancelPrefixes = ['cancela o evento ', 'cancela a reuniao ', 'cancela evento ', 'cancela reuniao ', 'cancelar evento ', 'cancelar reuniao '];
  final reschedulePrefixes = ['remarca o evento ', 'remarcar evento ', 'remarca a reuniao ', 'remarcar reuniao ', 'remarca o evento ', 'remarca reuniao '];
  final prefixes = forReschedule ? reschedulePrefixes : cancelPrefixes;
  for (final prefix in prefixes) {
    if (normalized.contains(prefix)) {
      int start = normalized.indexOf(prefix) + prefix.length;
      String rest = normalized.substring(start);
      if (forReschedule && rest.contains(' para ')) {
        rest = rest.substring(0, rest.indexOf(' para ')).trim();
      }
      rest = rest.replaceFirst(RegExp(r'\b(?:as\s+\d|dia\s+\d|\d{1,2}h|\d{1,2}\s+horas)'), ' ').trim();
      if (rest.length > 1) return rest.split(RegExp(r'\s+')).take(6).join(' ').trim();
    }
  }
  return null;
}

/// Preenche params com start_iso (e opcionalmente end_iso e title) extraídos do texto.
Map<String, String>? _extractDateTimeParams(String raw) {
  final n = _normalize(raw);
  final date = _parseDate(n);
  final time = _parseTime(n);
  final title = _parseTitle(raw, n);

  DateTime start;
  if (date != null && time != null) {
    start = DateTime(date.year, date.month, date.day, time.hour, time.minute);
  } else if (date != null) {
    start = DateTime(date.year, date.month, date.day, 9, 0);
  } else if (time != null) {
    final t = DateTime.now();
    start = DateTime(t.year, t.month, t.day, time.hour, time.minute);
    if (start.isBefore(DateTime.now())) start = start.add(const Duration(days: 1));
  } else {
    return null;
  }
  final end = start.add(const Duration(hours: 1));
  final params = <String, String>{
    'start_iso': start.toUtc().toIso8601String(),
    'end_iso': end.toUtc().toIso8601String(),
  };
  if (title != null && title.isNotEmpty) params['title'] = title;
  return params;
}

/// Detecta se o texto contém a palavra de ativação (em qualquer resultado, parcial ou final).
/// Aceita "Ava" e "secretária"/"secretaria" para trazer a assistente ao primeiro plano.
bool isWakeWord(String text) {
  if (text.trim().isEmpty) return false;
  final n = _normalize(text);
  return n.contains('ava') || n.contains('secretaria');
}

/// Reconhece comandos como "crie uma reunião", "tome notas", "marque evento amanhã às 15h", etc.
VoiceCommand parseCommand(String text) {
  if (text.trim().isEmpty) return VoiceCommand(type: VoiceCommandType.unknown, raw: text);
  final n = _normalize(text);

  // Criar reunião: "crie/cria/criar reunião", "nova reunião", "fazer reunião", "abrir reunião"
  if ((n.contains('cria') || n.contains('crie') || n.contains('criar') || n.contains('nova reuniao') || n.contains('fazer reuniao') || n.contains('abrir reuniao')) && (n.contains('reunio') || n.contains('reuni'))) {
    final params = _extractDateTimeParams(text);
    return VoiceCommand(type: VoiceCommandType.createMeeting, raw: text, params: params);
  }
  // Tomar notas: "tome/tomar nota(s)", "anote/anotar", "registre/registrar", "gravar nota"
  if (n.contains('tome notas') || n.contains('tomar notas') || n.contains('anote') || n.contains('anotar') || n.contains('toma nota') || n.contains('tomar nota') ||
      n.contains('registre') || n.contains('registrar') || n.contains('gravar nota') || n.contains('grava nota') || n.contains('faca uma anotacao') || n.contains('fazer anotacao')) {
    return VoiceCommand(type: VoiceCommandType.takeNotes, raw: text);
  }
  // "adicione uma nota nessa reunião bom dia", "adiciona nota na reunião X" (usa última lista se "nessa/dessa/na última")
  final addNoteMatch = _extractAddNoteToMeeting(n, text);
  if (addNoteMatch != null) {
    return VoiceCommand(type: VoiceCommandType.addNoteToMeeting, raw: text, params: addNoteMatch);
  }
  // Ver calendário: "visualizar/ver/mostrar/abrir calendário ou agenda"
  if ((n.contains('visualiz') || n.contains('ver ') || n.contains('mostre') || n.contains('mostrar') || n.contains('abrir') || n.contains('mostra ')) && (n.contains('calend') || n.contains('agenda'))) {
    return VoiceCommand(type: VoiceCommandType.viewCalendar, raw: text);
  }
  // "ver reunião segunda feira", "quais reuniões tenho amanhã?" — com data: tratar ANTES do "ver reuniões = hoje"
  final hasEventListIntent = n.contains('ver reunio') || n.contains('ver reuniao') || n.contains('mostra reuniao') || n.contains('mostrar reuniao') || n.contains('mostra evento') || n.contains('mostrar evento') ||
      n.contains('tenho evento') || n.contains('tenho reuniao') || n.contains('tenho reunioes') || n.contains('tenho compromisso') || n.contains('tenho compromissos') ||
      n.contains('quais evento') || n.contains('qual evento') || n.contains('quais reuniao') || n.contains('qual reuniao') ||
      n.contains('quais reunioes') || n.contains('quais sao as minhas reunioes') || n.contains('qual sao minhas reunioes') || n.contains('quais sao meus evento') ||
      n.contains('minhas reunioes de') || n.contains('minha reuniao de') || n.contains('meus evento de') || n.contains('meus compromisso de') ||
      n.contains('reunioes de ') || n.contains('reuniao de ') || n.contains('eventos de ') || n.contains('evento de ') ||
      n.contains('compromissos de ') || n.contains('compromisso de ') || n.contains('agenda de ') ||
      n.contains('o que tenho') || n.contains('que tenho') || n.contains('tenho alguma') || n.contains('compromisso') || n.contains('agenda') ||
      n.contains('listar evento') || n.contains('mostrar evento') || n.contains('lista evento') || n.contains('lista reuniao') || n.contains('listar reuniao');
  final hasDateRef = n.contains('amanha') || n.contains('hoje') || n.contains('dia ') ||
      n.contains('segunda') || n.contains('terca') || n.contains('quarta') || n.contains('quinta') || n.contains('sexta') || n.contains('sabado') || n.contains('domingo') ||
      n.contains('feira');
  if (hasEventListIntent && hasDateRef) {
    final params = _extractQueryDateParams(n);
    return VoiceCommand(type: VoiceCommandType.listEvents, raw: text, params: params ?? {'query_date_iso': _defaultToday()});
  }
  // "ver reuniões", "minhas reuniões", "meus eventos" sem data = hoje
  if (n.contains('ver reunio') || n.contains('minhas reunio') || n.contains('meus evento') || n.contains('meu evento') ||
      n.contains('reunioes marcadas') || n.contains('reunio marcada') || n.contains('eventos marcados') ||
      n.contains('quais reunioes tenho') || n.contains('qual reuniao tenho') || n.contains('quais eventos tenho') || n.contains('reunioes que tenho') ||
      n.contains('minha agenda') || n.contains('minha agenda hoje') || n.contains('o que tenho hoje') ||
      (n.contains('reunio') && (n.contains('listar') || n.contains('mostrar') || n.contains('ver '))) ||
      (n.contains('evento') && (n.contains('listar') || n.contains('mostrar') || n.contains('ver ')))) {
    return VoiceCommand(type: VoiceCommandType.listEvents, raw: text, params: {'query_date_iso': _defaultToday()});
  }
  // "marca/marque uma reunião", "agendar reunião" (STT: marca, marque, marcar + reuniao)
  if ((n.contains('marque') || n.contains('marca') || n.contains('marcar') || n.contains('agendar reuniao') || n.contains('agende reuniao')) && (n.contains('reunio') || n.contains('reuni'))) {
    final params = _extractDateTimeParams(text);
    return VoiceCommand(type: VoiceCommandType.createMeeting, raw: text, params: params);
  }
  // Marcar evento: "marque/marca/marcar um evento", "agendar evento", "criar evento"
  if (n.contains('marque um evento') || n.contains('marcar evento') || n.contains('marque evento') ||
      n.contains('marca um evento') || n.contains('marca evento') || n.contains('agende') || n.contains('agendar') ||
      n.contains('agenda evento') || n.contains('criar evento') || n.contains('cria evento') || n.contains('novo evento') ||
      n.contains('agendar um evento') || n.contains('marcar um compromisso')) {
    final params = _extractDateTimeParams(text);
    return VoiceCommand(type: VoiceCommandType.scheduleEvent, raw: text, params: params);
  }
  if (n.contains('adicione participante') || n.contains('adicionar participante') || n.contains('inclua participante') ||
      n.contains('adiciona participante') || n.contains('incluir participante') || n.contains('coloca participante')) {
    return VoiceCommand(type: VoiceCommandType.addParticipants, raw: text);
  }
  // "eventos/reuniões que têm notas", "com ata", "com anotações"
  if ((n.contains('evento') || n.contains('reunio')) && (n.contains('tem nota') || n.contains('com ata') || n.contains('tem ata') || n.contains('anotac') || n.contains('com anotac'))) {
    return VoiceCommand(type: VoiceCommandType.listEventsWithNotes, raw: text);
  }
  // "eventos/reuniões com lembrete"
  if ((n.contains('evento') || n.contains('reuniao') || n.contains('reunio')) && (n.contains('lembrete') || n.contains('com lembrete') || n.contains('tem lembrete'))) {
    return VoiceCommand(type: VoiceCommandType.listEventsWithReminders, raw: text);
  }
  // "itens de ação", "tarefas pendentes", "pendências", "o que está aberto"
  if (n.contains('item de acao') || n.contains('itens de acao') || n.contains('tarefa pendente') || n.contains('tarefas pendente') ||
      n.contains('action item') || n.contains('pendencia') || n.contains('pendencias') || n.contains('o que esta aberto') || n.contains('aberto para fazer') ||
      n.contains('tarefas pendentes') || n.contains('lista de tarefa') || n.contains('minhas tarefa')) {
    return VoiceCommand(type: VoiceCommandType.listActionItems, raw: text);
  }
  // "meus contatos", "lista de pessoas", "contatos"
  if (n.contains('contato') || n.contains('contatos') || n.contains('lista de pessoa') || n.contains('pessoas cadastrada') ||
      n.contains('quem esta cadastrado') || (n.contains('minha') && n.contains('pessoa')) || n.contains('meus contatos') ||
      n.contains('ver contato') || n.contains('mostrar contato') || n.contains('listar contato')) {
    return VoiceCommand(type: VoiceCommandType.listPeople, raw: text);
  }
  // "o que posso fazer?", "quais opções?", "me ajude", "menu"
  if (n.contains('o que posso fazer') || n.contains('quais opcoes') || n.contains('me ajude') || n.contains('o que voce faz') ||
      n.contains('o que voce pode') || n.contains('comandos disponiveis') || n.contains('menu') || n.contains('opcoes') ||
      n.contains('o que voce sabe fazer') || n.contains('como te uso') || n.contains('me ajuda')) {
    return VoiceCommand(type: VoiceCommandType.askWhatCanDo, raw: text);
  }
  // "cancela a primeira", "cancela essa reunião" (STT: cancela/cancelar/cancelo + primeira/segunda)
  if ((n.contains('cancela') || n.contains('cancelar') || n.contains('cancelo')) &&
      (n.contains('a primeira') || n.contains('a segunda') || n.contains('essa reuniao') || n.contains('essa reunia') || n.contains('nessa reuniao') || n.contains('o primeiro') || n.contains('o segundo'))) {
    final which = n.contains('segunda') || n.contains('segundo') ? 'second' : 'first';
    return VoiceCommand(type: VoiceCommandType.cancelEvent, raw: text, params: {'event_title': '', 'which_listed': which});
  }
  // "remarca a primeira para amanhã às 15h" (STT: remarca/remarcar/remarque)
  if ((n.contains('remarca') || n.contains('remarcar') || n.contains('remarque')) && (n.contains('a primeira') || n.contains('a segunda') || n.contains('o primeiro') || n.contains('o segundo')) && n.contains(' para ')) {
    final which = n.contains('segunda') || n.contains('segundo') ? 'second' : 'first';
    final dateTimeParams = _extractDateTimeParams(text);
    if (dateTimeParams != null) {
      final params = <String, String>{'event_title': '', 'which_listed': which, 'start_iso': dateTimeParams['start_iso']!, 'end_iso': dateTimeParams['end_iso']!};
      return VoiceCommand(type: VoiceCommandType.rescheduleEvent, raw: text, params: params);
    }
  }
  // "cancela o evento X", "cancela a reunião Y" (STT: cancela/cancelar + evento/reuniao)
  if ((n.contains('cancela') || n.contains('cancelar') || n.contains('cancelo')) && (n.contains('evento') || n.contains('reuniao') || n.contains('reunio') || n.contains('compromisso'))) {
    final title = _extractEventTitleForAction(n, forReschedule: false);
    final params = title != null && title.isNotEmpty ? {'event_title': title} : null;
    return VoiceCommand(type: VoiceCommandType.cancelEvent, raw: text, params: params);
  }
  // "remarca o evento X para amanhã às 15h"
  if ((n.contains('remarca') || n.contains('remarcar') || n.contains('remarque')) && (n.contains('evento') || n.contains('reuniao') || n.contains('reunio')) && n.contains(' para ')) {
    final title = _extractEventTitleForAction(n, forReschedule: true);
    final dateTimeParams = _extractDateTimeParams(text);
    final params = <String, String>{};
    if (title != null && title.isNotEmpty) params['event_title'] = title;
    if (dateTimeParams != null) {
      params['start_iso'] = dateTimeParams['start_iso']!;
      params['end_iso'] = dateTimeParams['end_iso']!;
    }
    return VoiceCommand(type: VoiceCommandType.rescheduleEvent, raw: text, params: params.isNotEmpty ? params : null);
  }
  // "reuniões/eventos dessa semana", "o que tenho essa semana", "quais reuniões tenho essa semana"
  final hasWeekQuery = n.contains('essa semana') || n.contains('nessa semana') || n.contains('da semana') || n.contains('semana');
  final hasListIntent = n.contains('quais') || n.contains('qual') || n.contains('o que') || n.contains('tenho') || n.contains('minha') || n.contains('meu') || n.contains('ver') || n.contains('mostrar');
  final hasMeetingRef = n.contains('reunio') || n.contains('reunia') || n.contains('evento') || n.contains('compromisso') || n.contains('agenda');
  if (hasWeekQuery && (hasListIntent || hasMeetingRef)) {
    return VoiceCommand(type: VoiceCommandType.listMeetingsThisWeek, raw: text);
  }
  // "lembretes", "quais lembretes", "meus lembretes", "lista de lembrete"
  if (n.contains('lembrete') || n.contains('lembretes') || n.contains('meus lembretes') || n.contains('quais lembretes') || n.contains('tem lembrete') ||
      n.contains('lista de lembrete') || n.contains('ver lembrete') || n.contains('mostrar lembrete')) {
    return VoiceCommand(type: VoiceCommandType.listReminders, raw: text);
  }
  // "leia as notas da reunião [horário]" — por número ("15h") ou por extenso ("quinze horas"); data opcional (hoje se não disser)
  final hasReadNotesIntent = n.contains('leia as notas') || n.contains('ler notas') || n.contains('leia nota') || n.contains('ler nota') ||
      n.contains('le nota') || n.contains('le as notas') || n.contains('notas da reuniao') || n.contains('nota da reuniao') ||
      n.contains('ouvir nota') || n.contains('mostrar nota') || n.contains('resumo da reuniao') || n.contains('ata da reuniao');
  if (hasReadNotesIntent && n.contains('reuniao')) {
    final time = _parseTime(n);
    if (time != null) {
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final date = _parseDate(n) ?? today;
      final start = DateTime(date.year, date.month, date.day, time.hour, time.minute);
      final startIso = start.toUtc().toIso8601String();
      return VoiceCommand(type: VoiceCommandType.readMeetingNotes, raw: text, params: {'meeting_title': '', 'start_iso': startIso});
    }
  }
  // "leia/ler/le notas dessa reunião" — STT às vezes ouve "essa" em vez de "dessa", aceitamos os dois
  if ((n.contains('leia as notas') || n.contains('ler notas') || n.contains('leia nota') || n.contains('ler nota') || n.contains('le nota') || n.contains('le as notas') ||
      n.contains('notas da') || n.contains('nota da') || n.contains('ouvir nota') || n.contains('mostrar nota') || n.contains('lê nota') || n.contains('lee nota') ||
      n.contains('li as notas') || n.contains('lia as notas')) &&
      (n.contains('dessa reuniao') || n.contains('dessa reunia') || n.contains('nessa reuniao') || n.contains('nessa reunia') ||
      n.contains('essa reuniao') || n.contains('essa reunia') || n.contains('dessa') || n.contains('nessa') || n.contains('essa') ||
      n.contains('da ultima') || n.contains('da primeira') || n.contains('da segunda'))) {
    final which = n.contains('segunda') ? 'second' : (n.contains('primeira') ? 'first' : 'first');
    return VoiceCommand(type: VoiceCommandType.readMeetingNotes, raw: text, params: {'meeting_title': '', 'which_listed': which});
  }
  // "notas da reunião X", "resumo da reunião", "ata da reunião", "o que foi anotado"
  if (n.contains('notas da reuniao') || n.contains('nota da reuniao') || n.contains('anotado na reuniao') ||
      n.contains('ler notas') || n.contains('resumo da reuniao') || n.contains('o que foi anotado') || n.contains('ata da reuniao') ||
      n.contains('ata da reunia') || n.contains('resumo da reunia') || n.contains('conteudo da reuniao')) {
    final meetingTitle = _extractMeetingTitleForNotes(n);
    return VoiceCommand(type: VoiceCommandType.readMeetingNotes, raw: text, params: meetingTitle != null ? {'meeting_title': meetingTitle} : null);
  }
  // "que horas são?", "que hora é?", "me diga as horas", "qual o horário"
  if (n.contains('que horas') || n.contains('que hora') || n.contains('me diga as horas') || n.contains('horario') || n.contains('qual horario') || n.contains('que horario') ||
      n.contains('diga as horas') || n.contains('me fala as horas') || n.contains('horas sao') || n.contains('hora e') || n.contains('qual a hora')) {
    return VoiceCommand(type: VoiceCommandType.askTime, raw: text);
  }
  // "clima", "tempo", "temperatura", "previsão", "está chovendo"
  if (n.contains('clima') || n.contains('tempo') || n.contains('temperatura') || n.contains('previsao') || n.contains('esta chovendo') || n.contains('vai chover') ||
      n.contains('como esta o tempo') || n.contains('previsao do tempo') || n.contains('faz frio') || n.contains('faz calor')) {
    return VoiceCommand(type: VoiceCommandType.askWeather, raw: text);
  }
  // "pesquise/busque/procure X", "informações sobre", "o que é X"
  if (n.contains('pesquis') || n.contains('busqu') || n.contains('buscar') || n.contains('procur') || n.contains('noticia') || n.contains('noticias') ||
      n.contains('informacoes sobre') || n.contains('informacao sobre') || n.contains('o que e ') || n.contains('quem e ') || n.contains('o que eh ')) {
    final query = _extractSearchQuery(n);
    return VoiceCommand(type: VoiceCommandType.searchInfo, raw: text, params: query != null ? {'query': query} : null);
  }
  // "sair", "fechar", "minimizar", "voltar", "encerrar"
  if (n == 'sair' || n.contains('sair') || n.contains('fechar') || n.contains('minimizar') || n.contains('ir pro fundo') || n.contains('ir para o fundo') ||
      n.contains('voltar') || n.contains('encerrar') || n.contains('fechar assistente') || n.contains('tchau') || n.contains('ate logo')) {
    return VoiceCommand(type: VoiceCommandType.exitAssistant, raw: text);
  }

  return VoiceCommand(type: VoiceCommandType.unknown, raw: text);
}

/// Extrai conteúdo e contexto para "adicione uma nota nessa reunião [texto]".
/// Retorna null se não for esse comando.
Map<String, String>? _extractAddNoteToMeeting(String normalized, String raw) {
  final addNotePrefixes = [
    'adicione uma nota ', 'adiciona uma nota ', 'adicionar uma nota ', 'adicione nota ', 'adiciona nota ',
    'inclua uma nota ', 'incluir nota ', 'inclua nota ', 'coloca nota ', 'colocar nota ',
    'poe nota ', 'por nota ', 'anota na reuniao ', 'anote na reuniao ', 'adiciona na reuniao ',
  ];
  for (final prefix in addNotePrefixes) {
    if (!normalized.contains(prefix)) continue;
    int start = normalized.indexOf(prefix) + prefix.length;
    String rest = normalized.substring(start).trim();
    // "nessa reunião bom dia" -> conteúdo = "bom dia"
    final contextMarkers = ['nessa reuniao ', 'nessa reunia ', 'dessa reuniao ', 'dessa reunia ', 'na reuniao ', 'na reunia ', 'nessa ', 'dessa ', 'na ultima ', 'na primeira ', 'na segunda '];
    String? content;
    String which = 'first';
    for (final m in contextMarkers) {
      if (rest.startsWith(m)) {
        content = rest.substring(m.length).trim();
        which = rest.contains('segunda') ? 'second' : 'first';
        break;
      }
    }
    if (content == null) continue;
    if (content.isEmpty) content = 'Nota de voz';
    return {
      'content': content.split(RegExp(r'\s+')).take(25).join(' '),
      'meeting_title': '',
      'which_listed': which,
    };
  }
  return null;
}

/// Extrai o termo de pesquisa (ex.: "pesquise inflação" -> "inflação"). [normalized] já sem acentos.
String? _extractSearchQuery(String normalized) {
  const prefixes = [
    'pesquise ', 'pesquisar ', 'busque ', 'buscar ', 'noticias sobre ', 'noticia sobre ',
    'informacoes sobre ', 'o que e ', 'quem e ',
  ];
  for (final prefix in prefixes) {
    if (normalized.contains(prefix)) {
      int start = normalized.indexOf(prefix) + prefix.length;
      String rest = normalized.substring(start).trim();
      if (rest.length > 2) return rest.split(RegExp(r'\s+')).take(6).join(' ');
    }
  }
  if (normalized.contains('noticias') || normalized.contains('noticia')) return 'notícias';
  return null;
}

String _defaultToday() {
  final now = DateTime.now();
  return '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
}

String commandTypeLabel(VoiceCommandType type) {
  switch (type) {
    case VoiceCommandType.createMeeting:
      return 'Criar reunião';
    case VoiceCommandType.takeNotes:
      return 'Tomar notas';
    case VoiceCommandType.viewCalendar:
      return 'Ver calendário';
    case VoiceCommandType.scheduleEvent:
      return 'Marcar evento';
    case VoiceCommandType.addParticipants:
      return 'Adicionar participantes';
    case VoiceCommandType.addNoteToMeeting:
      return 'Adicionar nota na reunião';
    case VoiceCommandType.listEvents:
      return 'Ver eventos';
    case VoiceCommandType.cancelEvent:
      return 'Cancelar evento';
    case VoiceCommandType.rescheduleEvent:
      return 'Remarcar evento';
    case VoiceCommandType.listReminders:
      return 'Lembretes';
    case VoiceCommandType.readMeetingNotes:
      return 'Notas da reunião';
    case VoiceCommandType.listMeetingsThisWeek:
      return 'Reuniões da semana';
    case VoiceCommandType.listEventsWithNotes:
      return 'Eventos com notas';
    case VoiceCommandType.listEventsWithReminders:
      return 'Eventos com lembrete';
    case VoiceCommandType.listActionItems:
      return 'Itens de ação';
    case VoiceCommandType.listPeople:
      return 'Contatos';
    case VoiceCommandType.askWhatCanDo:
      return 'O que posso fazer';
    case VoiceCommandType.askTime:
      return 'Que horas são';
    case VoiceCommandType.askWeather:
      return 'Clima';
    case VoiceCommandType.searchInfo:
      return 'Pesquisar';
    case VoiceCommandType.exitAssistant:
      return 'Sair';
    case VoiceCommandType.unknown:
      return '';
  }
}
