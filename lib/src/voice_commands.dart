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

/// Contexto da conversa para validar se o comando faz sentido (ex.: "cancela a primeira" só após listar eventos).
class VoiceCommandContext {
  const VoiceCommandContext({this.lastCommandType});

  /// Último tipo de comando executado (ex.: listEvents). Usado para aceitar "cancela a primeira" só quando fez sentido.
  final VoiceCommandType? lastCommandType;

  static const _listContextTypes = [
    VoiceCommandType.listEvents,
    VoiceCommandType.listMeetingsThisWeek,
    VoiceCommandType.listEventsWithNotes,
    VoiceCommandType.listEventsWithReminders,
  ];

  bool get lastWasListingEvents =>
      lastCommandType != null && _listContextTypes.contains(lastCommandType!);
}

/// Aplica correções de erros comuns do STT (Vosk). Use no texto bruto antes de exibir ou parsear.
/// Melhora bastante o reconhecimento para português.
String correctSttText(String raw) {
  if (raw.trim().isEmpty) return raw;
  String t = raw.trim().toLowerCase();
  t = _fixCommonSttErrors(t);
  return t;
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
  t = _fixCommonSttErrors(t);
  return t;
}

/// Corrige erros frequentes do Vosk modelo pequeno em português.
/// Ex.: "quais reuniões atenção" → "quais reuniões tenho"
String _fixCommonSttErrors(String s) {
  String result = s;
  // Primeiro: separar palavras "coladas" (fala rápida)
  result = _fixMergedWords(result);
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

/// Separa palavras que o STT juntou quando a fala é rápida (ex.: "quaisreunioestenho" → "quais reunioes tenho").
String _fixMergedWords(String s) {
  if (s.isEmpty) return s;
  String result = s;
  // Ordenado do mais longo ao mais curto para evitar substituições parciais erradas
  const merged = <String, String>{
    'quaisasminhasreunioesamanha': 'quais as minhas reunioes amanha',
    'quaisasminhasreunioes': 'quais as minhas reunioes',
    'quaisreunioestenhoessasemana': 'quais reunioes tenho essa semana',
    'quaisreunioestenho': 'quais reunioes tenho',
    'quaisreunioes': 'quais reunioes',
    'reunioestenho': 'reunioes tenho',
    'minhasreunioesamanha': 'minhas reunioes amanha',
    'minhasreunioestenho': 'minhas reunioes tenho',
    'minhaagendahoje': 'minha agenda hoje',
    'minhaagendaamanha': 'minha agenda amanha',
    'minhaagenda': 'minha agenda',
    'oquetenhohoje': 'o que tenho hoje',
    'oquetenhoamanha': 'o que tenho amanha',
    'oquetenho': 'o que tenho',
    'quetenhohoje': 'que tenho hoje',
    'quetenhoamanha': 'que tenho amanha',
    'quetenho': 'que tenho',
    'tomenotas': 'tome notas',
    'tomarnotas': 'tomar notas',
    'vercalendario': 'ver calendario',
    'veragenda': 'ver agenda',
    'meuslembretes': 'meus lembretes',
    'quaislembretes': 'quais lembretes',
    'minhasreunioes': 'minhas reunioes',
    'meuscompromissos': 'meus compromissos',
    'meuseventos': 'meus eventos',
    'marqueumaevento': 'marque um evento',
    'criarlembrete': 'criar lembrete',
    'quehoras': 'que horas',
    'quehorassao': 'que horas sao',
    'listareunioes': 'lista reunioes',
    'listaeventos': 'lista eventos',
    'listalembretes': 'lista lembretes',
    'queroverreunioes': 'quero ver reunioes',
    'queroveragenda': 'quero ver agenda',
    'memosstraagenda': 'me mostra agenda',
    'abreagenda': 'abre agenda',
    'abrecalendario': 'abre calendario',
    'querohoras': 'que horas',
    'queranotar': 'quero anotar',
  };
  for (final entry in merged.entries) {
    if (result.contains(entry.key)) {
      result = result.replaceAll(entry.key, entry.value);
    }
  }
  return result;
}

/// Lista de correções ordenadas por tamanho (maior primeiro para evitar conflitos)
final _sttFixes = <MapEntry<String, String>>[
  // Frases completas / trechos longos (maior primeiro)
  MapEntry('quais reunioes atencao', 'quais reunioes tenho'),
  MapEntry('quais reunioes tenho essa mana', 'quais reunioes tenho essa semana'),
  MapEntry('quais reunioes tenho e sa semana', 'quais reunioes tenho essa semana'),
  MapEntry('reunioes atencao', 'reunioes tenho'),
  MapEntry('reunioes tenho e sa semana', 'reunioes tenho essa semana'),
  MapEntry('e sa semana', 'essa semana'),
  MapEntry('essa mana', 'essa semana'),
  MapEntry('e semana', 'essa semana'),
  MapEntry('de sa semana', 'dessa semana'),
  MapEntry('ne sa semana', 'nessa semana'),
  MapEntry('secreta ria', 'secretaria'),
  MapEntry('secre taria', 'secretaria'),
  MapEntry('calenda rio', 'calendario'),
  MapEntry('ver calenda rio', 'ver calendario'),
  MapEntry('minhas reunioes atencao', 'minhas reunioes tenho'),
  MapEntry('o que atencao hoje', 'o que tenho hoje'),
  MapEntry('que atencao hoje', 'que tenho hoje'),
  
  // "tenho" - muito comum errar
  MapEntry('atencao', 'tenho'),
  MapEntry('atensao', 'tenho'),
  MapEntry('a tensao', 'tenho'),
  MapEntry('tem nho', 'tenho'),
  MapEntry('ten ho', 'tenho'),
  MapEntry('tenio', 'tenho'),
  MapEntry('te nho', 'tenho'),
  MapEntry('teu nho', 'tenho'),
  MapEntry('tenu', 'tenho'),
  MapEntry('teu no', 'tenho'),
  
  // "reunião" - muito comum errar
  MapEntry('retina', 'reuniao'),
  MapEntry('reunia o', 'reuniao'),
  MapEntry('reuni ao', 'reuniao'),
  MapEntry('re uniao', 'reuniao'),
  MapEntry('reunio', 'reuniao'),
  MapEntry('reu niao', 'reuniao'),
  MapEntry('reuiniao', 'reuniao'),
  MapEntry('reuniaos', 'reunioes'),
  MapEntry('reunia', 'reuniao'),
  MapEntry('reunioes', 'reunioes'),
  MapEntry('re unioes', 'reunioes'),
  MapEntry('reunio es', 'reunioes'),
  MapEntry('reuniaoes', 'reunioes'),
  MapEntry('reunioas', 'reunioes'),
  MapEntry('reuniaoz', 'reunioes'),
  MapEntry('reunioz', 'reunioes'),
  MapEntry('reunioe', 'reunioes'),
  MapEntry('reunioe s', 'reunioes'),
  MapEntry('retinas', 'reunioes'),
  MapEntry('reunioes tenho', 'reunioes tenho'),
  MapEntry('minha reuniao', 'minha reuniao'),
  MapEntry('minhas reunioes', 'minhas reunioes'),
  
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
  
  // Ava / assistente
  MapEntry('a va', 'ava'),
  MapEntry('a bá', 'ava'),
  MapEntry('aba', 'ava'),
  MapEntry('haba', 'ava'),
  MapEntry('la va', 'ava'),
  
  // "essa" / "nessa" / "dessa"
  MapEntry('e ssa', 'essa'),
  MapEntry('ne ssa', 'nessa'),
  MapEntry('de ssa', 'dessa'),
  MapEntry('esa', 'essa'),
  MapEntry('nesa', 'nessa'),
  MapEntry('desa', 'dessa'),
  
  // "hoje" / "amanhã"
  MapEntry('o je', 'hoje'),
  MapEntry('ho je', 'hoje'),
  MapEntry('oje', 'hoje'),
  MapEntry('a manha', 'amanha'),
  MapEntry('ama nha', 'amanha'),
  MapEntry('amana', 'amanha'),
  MapEntry('amanha', 'amanha'),
  
  // "semana"
  MapEntry('se mana', 'semana'),
  MapEntry('sema na', 'semana'),
  MapEntry('cemana', 'semana'),
  
  // "criar" / "marque"
  MapEntry('criar reuniao', 'criar reuniao'),
  MapEntry('criar reunia', 'criar reuniao'),
  MapEntry('marque reuniao', 'marque reuniao'),
  MapEntry('marque evento', 'marque evento'),
  
  // "notas" / "nota"
  MapEntry('no tas', 'notas'),
  MapEntry('no ta', 'nota'),
  MapEntry('notas da reuniao', 'notas da reuniao'),
  MapEntry('ler notas', 'ler notas'),
  MapEntry('leia notas', 'leia notas'),

  // --- Negócios: lembretes ---
  MapEntry('lembretes', 'lembretes'),
  MapEntry('lem bretes', 'lembretes'),
  MapEntry('lembrete s', 'lembretes'),
  MapEntry('me lembre', 'me lembre'),
  MapEntry('lembre me', 'lembre me'),
  MapEntry('lembre me de', 'lembre me de'),
  MapEntry('criar lembrete', 'criar lembrete'),
  MapEntry('crie lembrete', 'crie lembrete'),
  MapEntry('agendar lembrete', 'agendar lembrete'),
  MapEntry('quais lembretes', 'quais lembretes'),
  MapEntry('meus lembretes', 'meus lembretes'),
  MapEntry('lista de lembrete', 'lista de lembretes'),

  // --- Negócios: compromissos ---
  MapEntry('compromissos', 'compromissos'),
  MapEntry('compro missos', 'compromissos'),
  MapEntry('tenho compromisso', 'tenho compromisso'),
  MapEntry('tenho compromissos', 'tenho compromissos'),
  MapEntry('meus compromissos', 'meus compromissos'),
  MapEntry('meu compromisso', 'meu compromisso'),

  // --- Negócios: reunião/reuniões (variantes extras) ---
  MapEntry('reuniao de equipe', 'reuniao de equipe'),
  MapEntry('reunioes de equipe', 'reunioes de equipe'),
  MapEntry('reuniao de equi pe', 'reuniao de equipe'),
  MapEntry('proxima reuniao', 'proxima reuniao'),
  MapEntry('proximas reunioes', 'proximas reunioes'),
  MapEntry('proxima reunia o', 'proxima reuniao'),
  MapEntry('minha proxima reuniao', 'minha proxima reuniao'),
  MapEntry('call de', 'reuniao de'),
  MapEntry('call com', 'reuniao com'),
  MapEntry('tenho call', 'tenho reuniao'),
  MapEntry('minhas call', 'minhas reunioes'),
  MapEntry('daily', 'daily'),
  MapEntry('stand up', 'stand up'),
  MapEntry('standup', 'stand up'),
  MapEntry('reuniao stand up', 'reuniao stand up'),

  // --- Agenda / o que tenho ---
  MapEntry('minha agenda', 'minha agenda'),
  MapEntry('minha agen da', 'minha agenda'),
  MapEntry('minha agenda hoje', 'minha agenda hoje'),
  MapEntry('minha agenda amanha', 'minha agenda amanha'),
  MapEntry('o que tenho hoje', 'o que tenho hoje'),
  MapEntry('o que tenho amanha', 'o que tenho amanha'),
  MapEntry('que tenho hoje', 'que tenho hoje'),
  MapEntry('que tenho amanha', 'que tenho amanha'),
  MapEntry('tenho algo hoje', 'tenho algo hoje'),
  MapEntry('tenho algo amanha', 'tenho algo amanha'),
  MapEntry('tenho alguma coisa', 'tenho alguma coisa'),
  MapEntry('tenho alguma reuniao', 'tenho alguma reuniao'),
  MapEntry('tenho algum evento', 'tenho algum evento'),
  MapEntry('tenho algum compro misso', 'tenho algum compromisso'),
  MapEntry('agenda de hoje', 'agenda de hoje'),
  MapEntry('agenda de amanha', 'agenda de amanha'),
  MapEntry('agenda da semana', 'agenda da semana'),

  // --- Ação: marcar / agendar / cancelar / remarcar ---
  MapEntry('marque uma reuniao', 'marque uma reuniao'),
  MapEntry('marque um evento', 'marque um evento'),
  MapEntry('marcar uma reuniao', 'marcar uma reuniao'),
  MapEntry('marcar um evento', 'marcar um evento'),
  MapEntry('agende uma reuniao', 'agende uma reuniao'),
  MapEntry('agende um evento', 'agende um evento'),
  MapEntry('agendar uma reuniao', 'agendar uma reuniao'),
  MapEntry('agendar um evento', 'agendar um evento'),
  MapEntry('cancela a reuniao', 'cancela a reuniao'),
  MapEntry('cancela o evento', 'cancela o evento'),
  MapEntry('cancelar a reuniao', 'cancelar a reuniao'),
  MapEntry('cancelar o evento', 'cancelar o evento'),
  MapEntry('remarca a reuniao', 'remarca a reuniao'),
  MapEntry('remarca o evento', 'remarca o evento'),
  MapEntry('remarcar a reuniao', 'remarcar a reuniao'),
  MapEntry('remarcar o evento', 'remarcar o evento'),

  // --- Anotações / ata ---
  MapEntry('anotacao', 'anotacao'),
  MapEntry('anotacoes', 'anotacoes'),
  MapEntry('a notacao', 'anotacao'),
  MapEntry('ano tacao', 'anotacao'),
  MapEntry('faca uma anotacao', 'faca uma anotacao'),
  MapEntry('fazer anotacao', 'fazer anotacao'),
  MapEntry('tome nota', 'tome nota'),
  MapEntry('tomar nota', 'tomar nota'),
  MapEntry('tome notas', 'tome notas'),
  MapEntry('tomar notas', 'tomar notas'),
  MapEntry('ata da reuniao', 'ata da reuniao'),
  MapEntry('ata da reunia', 'ata da reuniao'),
  MapEntry('resumo da reuniao', 'resumo da reuniao'),
  MapEntry('resumo da reunia', 'resumo da reuniao'),
  MapEntry('adiciona nota', 'adiciona nota'),
  MapEntry('adicione nota', 'adicione nota'),
  MapEntry('adicionar nota na reuniao', 'adicionar nota na reuniao'),

  // --- Participantes ---
  MapEntry('participantes', 'participantes'),
  MapEntry('parti cipantes', 'participantes'),
  MapEntry('adicionar participante', 'adicionar participante'),
  MapEntry('adicione participante', 'adicione participante'),

  // --- Datas/horas comuns em negócios ---
  MapEntry('depois de amanha', 'depois de amanha'),
  MapEntry('depois de ama nha', 'depois de amanha'),
  MapEntry('proxima semana', 'proxima semana'),
  MapEntry('proxima segun da', 'proxima segunda'),
  MapEntry('proxima segunda feira', 'proxima segunda feira'),
  MapEntry('proxima terca', 'proxima terca'),
  MapEntry('proxima quar ta', 'proxima quarta'),
  MapEntry('proxima quin ta', 'proxima quinta'),
  MapEntry('proxima sex ta', 'proxima sexta'),
  MapEntry('as nove horas', 'as nove horas'),
  MapEntry('as oito horas', 'as oito horas'),
  MapEntry('as dez horas', 'as dez horas'),
  MapEntry('as quinze horas', 'as quinze horas'),
  MapEntry('as 9 horas', 'as 9 horas'),
  MapEntry('as 14 horas', 'as 14 horas'),

  // --- Itens de ação / tarefas ---
  MapEntry('itens de acao', 'itens de acao'),
  MapEntry('item de acao', 'item de acao'),
  MapEntry('tarefas pendentes', 'tarefas pendentes'),
  MapEntry('tarefa pendente', 'tarefa pendente'),
  MapEntry('pendencia', 'pendencia'),
  MapEntry('pendencias', 'pendencias'),
  MapEntry('o que esta aberto', 'o que esta aberto'),
  MapEntry('lista de tarefa', 'lista de tarefas'),
  MapEntry('minhas tarefas', 'minhas tarefas'),

  // --- Fala rápida / pronúncia pouco clara (vogais ou sílabas “engolidas”) ---
  MapEntry('qais ', 'quais '),
  MapEntry('qais reunioes', 'quais reunioes'),
  MapEntry('qais evento', 'quais eventos'),
  MapEntry('calendrio', 'calendario'),
  MapEntry('calendri', 'calendario'),
  MapEntry('agnda', 'agenda'),
  MapEntry('agend', 'agenda'),
  MapEntry('lembret', 'lembrete'),
  MapEntry('lembret s', 'lembretes'),
  MapEntry('reunies', 'reunioes'),
  MapEntry('reunie', 'reuniao'),
  MapEntry('evnto', 'evento'),
  MapEntry('event', 'evento'),
  MapEntry('compromis', 'compromisso'),
  MapEntry('compromiss', 'compromisso'),
  MapEntry('hoj ', 'hoje '),
  MapEntry('hoj.', 'hoje'),
  MapEntry('seman ', 'semana '),
  MapEntry('seman.', 'semana'),
  MapEntry('amanh ', 'amanha '),
  MapEntry('participant', 'participante'),
  MapEntry('participants', 'participantes'),
  MapEntry('anotac', 'anotacao'),
  MapEntry('not ', 'nota '),
  MapEntry('nots', 'notas'),
  MapEntry('marq ', 'marque '),
  MapEntry('marq reuniao', 'marque reuniao'),
  MapEntry('proxim ', 'proxima '),
  MapEntry('proxim reuniao', 'proxima reuniao'),
  MapEntry('ess seman', 'essa semana'),
  MapEntry('e seman', 'essa semana'),

  // --- Frases que disparam ações (formas coloquiais que o STT costuma errar) ---
  MapEntry('quero ver reunioes', 'ver reunioes'),
  MapEntry('quero ver reuniao', 'ver reuniao'),
  MapEntry('quero ver agenda', 'ver agenda'),
  MapEntry('quero ver calendario', 'ver calendario'),
  MapEntry('quero ver evento', 'ver eventos'),
  MapEntry('quero ver eventos', 'ver eventos'),
  MapEntry('quero ver compromisso', 'ver compromissos'),
  MapEntry('queria ver reunioes', 'ver reunioes'),
  MapEntry('queria ver agenda', 'ver agenda'),
  MapEntry('me mostra reunioes', 'mostra reunioes'),
  MapEntry('me mostra reuniao', 'mostra reuniao'),
  MapEntry('me mostra a agenda', 'mostra agenda'),
  MapEntry('me mostra agenda', 'mostra agenda'),
  MapEntry('me mostra o calendario', 'mostra calendario'),
  MapEntry('me mostra calendario', 'mostra calendario'),
  MapEntry('me mostra eventos', 'mostra eventos'),
  MapEntry('pode mostrar reunioes', 'mostrar reunioes'),
  MapEntry('pode mostrar agenda', 'mostrar agenda'),
  MapEntry('pode mostrar calendario', 'mostrar calendario'),
  MapEntry('abre a agenda', 'abrir agenda'),
  MapEntry('abre o calendario', 'abrir calendario'),
  MapEntry('abre agenda', 'abrir agenda'),
  MapEntry('abre calendario', 'abrir calendario'),
  MapEntry('abrir a agenda', 'abrir agenda'),
  MapEntry('abrir o calendario', 'abrir calendario'),
  MapEntry('preciso ver reunioes', 'ver reunioes'),
  MapEntry('preciso ver agenda', 'ver agenda'),
  MapEntry('quero saber minhas reunioes', 'quais reunioes tenho'),
  MapEntry('quero saber o que tenho', 'o que tenho'),
  MapEntry('me fala as horas', 'que horas sao'),
  MapEntry('me diz as horas', 'que horas sao'),
  MapEntry('pode me dizer as horas', 'que horas sao'),
  MapEntry('quero anotar', 'anotar'),
  MapEntry('preciso anotar', 'anotar'),
  MapEntry('quero fazer uma anotacao', 'faca uma anotacao'),
  MapEntry('preciso de uma anotacao', 'faca uma anotacao'),
  MapEntry('quero ver lembretes', 'ver lembretes'),
  MapEntry('me mostra lembretes', 'mostra lembretes'),
  MapEntry('quero ver minha agenda', 'minha agenda'),
  MapEntry('mostra minha agenda', 'minha agenda'),
  MapEntry('ver minha agenda', 'minha agenda'),
  MapEntry('quais sao minhas reunioes', 'quais reunioes tenho'),
  MapEntry('o que eu tenho hoje', 'o que tenho hoje'),
  MapEntry('o que eu tenho amanha', 'o que tenho amanha'),
  MapEntry('reunioes que eu tenho', 'reunioes que tenho'),
  MapEntry('eventos que eu tenho', 'eventos que tenho'),
  MapEntry('agenda do dia', 'agenda hoje'),
  MapEntry('agenda de hoje', 'agenda hoje'),
  MapEntry('compromissos do dia', 'compromissos hoje'),

  // --- "quais as minhas reuniões amanhã" (fala rápida) ---
  MapEntry('quais as minhas reunioes manha', 'quais as minhas reunioes amanha'),
  MapEntry('quais as minhas reunioes aman', 'quais as minhas reunioes amanha'),
  MapEntry('quais as minhas reunioes ama nha', 'quais as minhas reunioes amanha'),
  MapEntry('quais as minhas reuniao amanha', 'quais as minhas reunioes amanha'),
  MapEntry('quais as minhas reuniao manha', 'quais as minhas reunioes amanha'),
  MapEntry('qais as minhas reunioes amanha', 'quais as minhas reunioes amanha'),
  // STT às vezes ouve "minhas reuniões amanhã" como "as mesmas"
  MapEntry('quais sao as mesmas', 'quais sao as minhas reunioes amanha'),
  MapEntry('quais as mesmas', 'quais as minhas reunioes amanha'),
];

/// Corrige palavras que foram divididas incorretamente
String _fixSplitWords(String s) {
  // Padrões de palavras comumente divididas (negócios + geral)
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
    RegExp(r'\bcom\s*pro\s*mis\s*sos\b'): 'compromissos',
    RegExp(r'\blem\s*bre\s*te\b'): 'lembrete',
    RegExp(r'\blem\s*bre\s*tes\b'): 'lembretes',
    RegExp(r'\bpar\s*ti\s*ci\s*pan\s*te\b'): 'participante',
    RegExp(r'\bpar\s*ti\s*ci\s*pan\s*tes\b'): 'participantes',
    RegExp(r'\ba\s*no\s*ta\s*c[aã]o\b'): 'anotacao',
    RegExp(r'\ba\s*no\s*ta\s*c[oõ]es\b'): 'anotacoes',
    RegExp(r'\bpen\s*d[eê]n\s*cia\b'): 'pendencia',
    RegExp(r'\bpen\s*d[eê]n\s*cias\b'): 'pendencias',
    RegExp(r'\bta\s*re\s*fa\b'): 'tarefa',
    RegExp(r'\bta\s*re\s*fas\b'): 'tarefas',
    RegExp(r'\bpro\s*xi\s*ma\b'): 'proxima',
    RegExp(r'\bpro\s*xi\s*mo\b'): 'proximo',
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
/// Se [context] for passado, comandos que dependem de lista (ex.: "cancela a primeira") só são aceitos quando [context.lastCommandType] for um comando que listou eventos.
VoiceCommand parseCommand(String text, {VoiceCommandContext? context}) {
  if (text.trim().isEmpty) return VoiceCommand(type: VoiceCommandType.unknown, raw: text);
  final n = _normalize(text);

  // Criar reunião: "crie/cria/criar reunião", "nova reunião", "marque uma call", "daily", "stand up"
  final createMeetingTrigger = (n.contains('cria') || n.contains('crie') || n.contains('criar') || n.contains('nova reuniao') || n.contains('fazer reuniao') || n.contains('abrir reuniao') || n.contains('marque uma call') || n.contains('marcar call') || n.contains('agende uma call'));
  final hasMeetingWord = n.contains('reunio') || n.contains('reuni') || n.contains('call') || n.contains('daily') || n.contains('stand up') || n.contains('standup');
  if (createMeetingTrigger && hasMeetingWord) {
    final params = _extractDateTimeParams(text);
    return VoiceCommand(type: VoiceCommandType.createMeeting, raw: text, params: params);
  }
  // Tomar notas: "tome/tomar nota(s)", "anote/anotar", "quero anotar", "registre", "gravar nota"
  if (n.contains('tome notas') || n.contains('tomar notas') || n.contains('anote') || n.contains('anotar') || n.contains('toma nota') || n.contains('tomar nota') ||
      n.contains('registre') || n.contains('registrar') || n.contains('gravar nota') || n.contains('grava nota') || n.contains('faca uma anotacao') || n.contains('fazer anotacao') ||
      n.contains('quero anotar') || n.contains('preciso anotar') || n.contains('quero fazer uma anotacao') || n.contains('preciso de uma anotacao')) {
    return VoiceCommand(type: VoiceCommandType.takeNotes, raw: text);
  }
  // "adicione uma nota nessa reunião bom dia", "adiciona nota na reunião X" (usa última lista se "nessa/dessa/na última")
  final addNoteMatch = _extractAddNoteToMeeting(n, text);
  if (addNoteMatch != null) {
    return VoiceCommand(type: VoiceCommandType.addNoteToMeeting, raw: text, params: addNoteMatch);
  }
  // Ver calendário: "visualizar/ver/mostrar/abrir calendário ou agenda", "quero ver calendário", "abre a agenda"
  if ((n.contains('visualiz') || n.contains('ver ') || n.contains('mostre') || n.contains('mostrar') || n.contains('abrir') || n.contains('mostra ') || n.contains('quero ver') || n.contains('queria ver')) && (n.contains('calend') || n.contains('agenda'))) {
    return VoiceCommand(type: VoiceCommandType.viewCalendar, raw: text);
  }
  // "ver reunião segunda feira", "quais reuniões tenho amanhã?", "quero ver agenda", "minha agenda" — com data: tratar ANTES do "ver reuniões = hoje"
  final hasEventListIntent = n.contains('ver reunio') || n.contains('ver reuniao') || n.contains('mostra reuniao') || n.contains('mostrar reuniao') || n.contains('mostra evento') || n.contains('mostrar evento') ||
      n.contains('tenho evento') || n.contains('tenho reuniao') || n.contains('tenho reunioes') || n.contains('tenho call') || n.contains('tenho calls') ||
      n.contains('tenho compromisso') || n.contains('tenho compromissos') || n.contains('tenho algo') || n.contains('tenho alguma') || n.contains('tenho algum') ||
      n.contains('quais evento') || n.contains('qual evento') || n.contains('quais reuniao') || n.contains('qual reuniao') ||
      n.contains('quais reunioes') || n.contains('quais as minhas reunioes') || n.contains('quais as minhas reuniao') ||
      n.contains('quais sao as minhas reunioes') || n.contains('qual sao minhas reunioes') || n.contains('quais sao meus evento') ||
      n.contains('minhas reunioes de') || n.contains('minha reuniao de') || n.contains('minhas call') || n.contains('minha agenda') ||
      n.contains('meus evento de') || n.contains('meus compromisso de') ||
      n.contains('reunioes de ') || n.contains('reuniao de ') || n.contains('eventos de ') || n.contains('evento de ') ||
      n.contains('compromissos de ') || n.contains('compromisso de ') || n.contains('agenda de ') ||
      n.contains('o que tenho') || n.contains('que tenho') || n.contains('reunioes que tenho') || n.contains('eventos que tenho') ||
      n.contains('compromisso') || n.contains('agenda') ||
      n.contains('listar evento') || n.contains('mostrar evento') || n.contains('lista evento') || n.contains('lista reuniao') || n.contains('listar reuniao') ||
      n.contains('quero ver reunio') || n.contains('quero ver evento') || n.contains('quero ver agenda') || n.contains('me mostra reunio') || n.contains('me mostra evento') || n.contains('me mostra agenda') ||
      n.contains('pode mostrar reunio') || n.contains('pode mostrar agenda') || n.contains('preciso ver reunio') || n.contains('preciso ver agenda') || n.contains('queria ver reunio') || n.contains('queria ver agenda');
  final hasDateRef = n.contains('amanha') || n.contains('hoje') || n.contains('dia ') ||
      n.contains('segunda') || n.contains('terca') || n.contains('quarta') || n.contains('quinta') || n.contains('sexta') || n.contains('sabado') || n.contains('domingo') ||
      n.contains('feira');
  if (hasEventListIntent && hasDateRef) {
    final params = _extractQueryDateParams(n);
    return VoiceCommand(type: VoiceCommandType.listEvents, raw: text, params: params ?? {'query_date_iso': _defaultToday()});
  }
  // "ver reuniões", "minhas reuniões", "meus eventos" sem data = hoje; "agenda hoje", "compromissos hoje"
  final hasListEventsToday = n.contains('ver reunio') || n.contains('minhas reunio') || n.contains('meus evento') || n.contains('meu evento') ||
      n.contains('reunioes marcadas') || n.contains('reunio marcada') || n.contains('eventos marcados') ||
      n.contains('quais reunioes tenho') || n.contains('qual reuniao tenho') || n.contains('quais eventos tenho') || n.contains('reunioes que tenho') ||
      n.contains('quais as minhas reunioes') || n.contains('quais as minhas reuniao') ||
      n.contains('minha agenda') || n.contains('minha agenda hoje') || n.contains('o que tenho hoje') || n.contains('agenda hoje') || n.contains('compromissos hoje') ||
      (n.contains('reunio') && (n.contains('listar') || n.contains('mostrar') || n.contains('ver ') || n.contains('quero ver'))) ||
      (n.contains('evento') && (n.contains('listar') || n.contains('mostrar') || n.contains('ver ')));
  if (hasListEventsToday) {
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
  // "cancela a primeira", "cancela essa reunião" (STT: cancela/cancelar/cancelo + primeira/segunda) — só faz sentido após listar eventos
  if ((n.contains('cancela') || n.contains('cancelar') || n.contains('cancelo')) &&
      (n.contains('a primeira') || n.contains('a segunda') || n.contains('essa reuniao') || n.contains('essa reunia') || n.contains('nessa reuniao') || n.contains('o primeiro') || n.contains('o segundo'))) {
    final which = n.contains('segunda') || n.contains('segundo') ? 'second' : 'first';
    if (context == null || context.lastWasListingEvents) {
      return VoiceCommand(type: VoiceCommandType.cancelEvent, raw: text, params: {'event_title': '', 'which_listed': which});
    }
  }
  // "remarca a primeira para amanhã às 15h" (STT: remarca/remarcar/remarque) — só faz sentido após listar eventos
  if ((n.contains('remarca') || n.contains('remarcar') || n.contains('remarque')) && (n.contains('a primeira') || n.contains('a segunda') || n.contains('o primeiro') || n.contains('o segundo')) && n.contains(' para ')) {
    final which = n.contains('segunda') || n.contains('segundo') ? 'second' : 'first';
    final dateTimeParams = _extractDateTimeParams(text);
    if (dateTimeParams != null && (context == null || context.lastWasListingEvents)) {
      final params = <String, String>{'event_title': '', 'which_listed': which, 'start_iso': dateTimeParams['start_iso']!, 'end_iso': dateTimeParams['end_iso']!};
      if (_dateNotInPast(dateTimeParams['start_iso'])) {
        return VoiceCommand(type: VoiceCommandType.rescheduleEvent, raw: text, params: params);
      }
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
    if (dateTimeParams != null && _dateNotInPast(dateTimeParams['start_iso'])) {
      final params = <String, String>{};
      if (title != null && title.isNotEmpty) params['event_title'] = title;
      params['start_iso'] = dateTimeParams['start_iso']!;
      params['end_iso'] = dateTimeParams['end_iso']!;
      return VoiceCommand(type: VoiceCommandType.rescheduleEvent, raw: text, params: params);
    }
  }
  // "reuniões/eventos dessa semana", "o que tenho essa semana", "quais reuniões tenho essa semana"
  final hasWeekQuery = n.contains('essa semana') || n.contains('nessa semana') || n.contains('da semana') || n.contains('semana');
  final hasListIntent = n.contains('quais') || n.contains('qual') || n.contains('o que') || n.contains('tenho') || n.contains('minha') || n.contains('meu') || n.contains('ver') || n.contains('mostrar');
  final hasMeetingRef = n.contains('reunio') || n.contains('reunia') || n.contains('evento') || n.contains('compromisso') || n.contains('agenda');
  if (hasWeekQuery && (hasListIntent || hasMeetingRef)) {
    return VoiceCommand(type: VoiceCommandType.listMeetingsThisWeek, raw: text);
  }
  // "lembretes", "quais lembretes", "meus lembretes", "criar lembrete", "me lembre", "lembre me"
  if (n.contains('lembrete') || n.contains('lembretes') || n.contains('meus lembretes') || n.contains('quais lembretes') || n.contains('tem lembrete') ||
      n.contains('lista de lembrete') || n.contains('ver lembrete') || n.contains('mostrar lembrete') ||
      n.contains('criar lembrete') || n.contains('crie lembrete') || n.contains('crie um lembrete') ||
      n.contains('me lembre') || n.contains('lembre me') || n.contains('lembre me de') || n.contains('agendar lembrete')) {
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
  // "leia/ler/le notas dessa reunião" — STT às vezes ouve "essa" em vez de "dessa"; só faz sentido após listar eventos
  if ((n.contains('leia as notas') || n.contains('ler notas') || n.contains('leia nota') || n.contains('ler nota') || n.contains('le nota') || n.contains('le as notas') ||
      n.contains('notas da') || n.contains('nota da') || n.contains('ouvir nota') || n.contains('mostrar nota') || n.contains('lê nota') || n.contains('lee nota') ||
      n.contains('li as notas') || n.contains('lia as notas')) &&
      (n.contains('dessa reuniao') || n.contains('dessa reunia') || n.contains('nessa reuniao') || n.contains('nessa reunia') ||
      n.contains('essa reuniao') || n.contains('essa reunia') || n.contains('dessa') || n.contains('nessa') || n.contains('essa') ||
      n.contains('da ultima') || n.contains('da primeira') || n.contains('da segunda'))) {
    final which = n.contains('segunda') ? 'second' : (n.contains('primeira') ? 'first' : 'first');
    if (context == null || context.lastWasListingEvents) {
      return VoiceCommand(type: VoiceCommandType.readMeetingNotes, raw: text, params: {'meeting_title': '', 'which_listed': which});
    }
  }
  // "notas da reunião X", "resumo da reunião", "ata da reunião", "o que foi anotado"
  if (n.contains('notas da reuniao') || n.contains('nota da reuniao') || n.contains('anotado na reuniao') ||
      n.contains('ler notas') || n.contains('resumo da reuniao') || n.contains('o que foi anotado') || n.contains('ata da reuniao') ||
      n.contains('ata da reunia') || n.contains('resumo da reunia') || n.contains('conteudo da reuniao')) {
    final meetingTitle = _extractMeetingTitleForNotes(n);
    return VoiceCommand(type: VoiceCommandType.readMeetingNotes, raw: text, params: meetingTitle != null ? {'meeting_title': meetingTitle} : null);
  }
  // "que horas são?", "que hora é?", "me diga as horas", "me fala as horas", "qual o horário"
  if (n.contains('que horas') || n.contains('que hora') || n.contains('me diga as horas') || n.contains('me diz as horas') || n.contains('me fala as horas') ||
      n.contains('horario') || n.contains('qual horario') || n.contains('que horario') ||
      n.contains('diga as horas') || n.contains('pode me dizer as horas') || n.contains('horas sao') || n.contains('hora e') || n.contains('qual a hora') || n.contains('quero saber que horas')) {
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

  // Fallback por palavras-chave: frases curtas que parecem comando mas o STT errou um pouco
  final words = n.split(RegExp(r'\s+')).where((w) => w.length > 1).toList();
  if (words.length <= 10) {
    final hasReuniao = n.contains('reunio');
    final hasEvento = n.contains('evento');
    final hasAgenda = n.contains('agenda');
    final hasCalendario = n.contains('calend');
    final hasLembrete = n.contains('lembrete');
    final hasTenho = n.contains('tenho');
    final hasQuais = n.contains('quais') || n.contains('qual');
    final hasVer = n.contains('ver') || n.contains('mostra') || n.contains('mostrar');
    final hasNota = n.contains('nota') || n.contains('anot');
    final hasHora = n.contains('hora');

    if ((hasReuniao || hasEvento || hasAgenda) && (hasTenho || hasQuais || hasVer)) {
      final params = _extractQueryDateParams(n);
      return VoiceCommand(type: VoiceCommandType.listEvents, raw: text, params: params ?? {'query_date_iso': _defaultToday()});
    }
    if ((hasCalendario || hasAgenda) && hasVer) {
      return VoiceCommand(type: VoiceCommandType.viewCalendar, raw: text);
    }
    if (hasLembrete && (hasVer || hasQuais || n.contains('meus') || n.contains('lista'))) {
      return VoiceCommand(type: VoiceCommandType.listReminders, raw: text);
    }
    if (hasNota && (n.contains('tome') || n.contains('tomar') || n.contains('anot') || n.contains('faca') || n.contains('quero') || n.contains('preciso'))) {
      return VoiceCommand(type: VoiceCommandType.takeNotes, raw: text);
    }
    if (hasHora && (n.contains('que') || n.contains('qual') || n.contains('diga') || n.contains('fala') || n.contains('diz'))) {
      return VoiceCommand(type: VoiceCommandType.askTime, raw: text);
    }
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

/// Retorna true se [iso] for null ou se a data/hora não estiver no passado (>= agora, com 1 min de margem).
bool _dateNotInPast(String? iso) {
  if (iso == null || iso.isEmpty) return true;
  try {
    final dt = DateTime.parse(iso);
    return !dt.isBefore(DateTime.now().toUtc().subtract(const Duration(minutes: 1)));
  } catch (_) {
    return true;
  }
}

/// Verifica se o comando faz sentido no contexto (ex.: não agendar no passado). Use após [parseCommand].
bool commandMakesSense(VoiceCommand cmd) {
  if (cmd.type != VoiceCommandType.createMeeting &&
      cmd.type != VoiceCommandType.scheduleEvent &&
      cmd.type != VoiceCommandType.rescheduleEvent) {
    return true;
  }
  final startIso = cmd.params?['start_iso'];
  return _dateNotInPast(startIso);
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
