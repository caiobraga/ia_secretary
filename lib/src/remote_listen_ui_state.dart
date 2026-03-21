/// Fases do STT remoto para feedback visual.
enum RemoteListenPhase {
  /// Entre segmentos ou ocioso.
  idle,

  /// Gravando até detetar pausa na fala (ou teto de duração).
  recording,

  /// A enviar áudio e a aguardar transcrição.
  transcribing,
}

/// Estado para indicador de audição (micro + nível).
class RemoteListenUiState {
  const RemoteListenUiState({
    required this.phase,
    this.voiceLevel = 0,
  });

  final RemoteListenPhase phase;

  /// 0–1 (aprox.), derivado da amplitude do microfone.
  final double voiceLevel;
}
