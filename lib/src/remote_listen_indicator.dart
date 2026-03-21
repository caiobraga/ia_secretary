import 'package:flutter/material.dart';

import 'remote_listen_ui_state.dart';

/// Indicador visual do STT remoto: fase (gravar / transcrever) e nível de áudio.
class RemoteListenIndicator extends StatelessWidget {
  const RemoteListenIndicator({
    super.key,
    required this.state,
    this.compact = false,
  });

  final RemoteListenUiState state;
  final bool compact;

  static const Color _accent = Color(0xFF00d4ff);

  @override
  Widget build(BuildContext context) {
    final pad = compact ? const EdgeInsets.symmetric(horizontal: 12, vertical: 8) : const EdgeInsets.only(top: 4);
    final label = switch (state.phase) {
      RemoteListenPhase.recording => 'A ouvir… faça uma pausa no fim da frase',
      RemoteListenPhase.transcribing => 'A transcrever…',
      RemoteListenPhase.idle => '',
    };

    if (state.phase == RemoteListenPhase.idle && !compact) {
      return const SizedBox.shrink();
    }

    return Padding(
      padding: pad,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (label.isNotEmpty)
            Text(
              label,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white.withValues(alpha: compact ? 0.85 : 0.55),
                fontSize: compact ? 11 : 12,
                letterSpacing: compact ? 0.5 : 2,
              ),
            ),
          if (label.isNotEmpty) SizedBox(height: compact ? 6 : 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: state.phase == RemoteListenPhase.transcribing
                ? LinearProgressIndicator(
                    minHeight: compact ? 3 : 4,
                    backgroundColor: _accent.withValues(alpha: 0.15),
                    color: _accent.withValues(alpha: 0.85),
                  )
                : LinearProgressIndicator(
                    value: state.voiceLevel.clamp(0.0, 1.0),
                    minHeight: compact ? 3 : 4,
                    backgroundColor: _accent.withValues(alpha: 0.12),
                    valueColor: AlwaysStoppedAnimation<Color>(_accent.withValues(alpha: 0.75)),
                  ),
          ),
        ],
      ),
    );
  }
}

/// Chip flutuante quando a assistente está minimizada.
class RemoteListenOverlayChip extends StatelessWidget {
  const RemoteListenOverlayChip({super.key, required this.state});

  final RemoteListenUiState state;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: const Color(0xFF0d1321).withValues(alpha: 0.92),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFF00d4ff).withValues(alpha: 0.35)),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF00d4ff).withValues(alpha: 0.12),
              blurRadius: 16,
              spreadRadius: 0,
            ),
          ],
        ),
        child: RemoteListenIndicator(state: state, compact: true),
      ),
    );
  }
}
