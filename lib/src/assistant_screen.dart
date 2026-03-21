import 'package:flutter/material.dart';

import 'remote_listen_indicator.dart';
import 'remote_listen_ui_state.dart';

/// Tela futurista da IA: mostra último comando de voz e resultados.
/// [isAvaSpeaking]: true quando a Ava está falando (TTS) — mostra animação de fala e para de ouvir.
class AssistantScreen extends StatelessWidget {
  const AssistantScreen({
    super.key,
    required this.lastTranscript,
    required this.commandResults,
    required this.onMinimize,
    this.isAvaSpeaking = false,
    this.onViewData,
    this.remoteListen,
  });

  final String lastTranscript;
  final List<Map<String, String>> commandResults;
  final VoidCallback onMinimize;
  final bool isAvaSpeaking;
  final VoidCallback? onViewData;
  final RemoteListenUiState? remoteListen;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color(0xFF0a0e17),
              Color(0xFF0d1321),
              Color(0xFF0a0e17),
            ],
          ),
        ),
        child: Stack(
          children: [
            _buildGrid(context),
            SafeArea(
              child: Column(
                children: [
                  _buildHeader(context),
                  const SizedBox(height: 24),
                  _buildOrb(context),
                  const SizedBox(height: 32),
                  _buildTranscript(context),
                  const SizedBox(height: 24),
                  Expanded(child: _buildResults(context)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGrid(BuildContext context) {
    return CustomPaint(
      painter: _GridPainter(),
      size: Size.infinite,
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: const Color(0xFF00d4ff),
                  borderRadius: BorderRadius.circular(4),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF00d4ff).withValues(alpha: 0.6),
                      blurRadius: 8,
                      spreadRadius: 1,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Text(
                'AVA',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.9),
                  fontSize: 14,
                  letterSpacing: 3,
                  fontWeight: FontWeight.w300,
                ),
              ),
            ],
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (onViewData != null)
                IconButton(
                  onPressed: onViewData,
                  icon: Icon(Icons.calendar_month, color: Colors.white.withValues(alpha: 0.8)),
                  tooltip: 'Ver meus dados',
                ),
              IconButton(
                onPressed: onMinimize,
                icon: Icon(Icons.keyboard_arrow_down, color: Colors.white.withValues(alpha: 0.7)),
                tooltip: 'Minimizar',
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildOrb(BuildContext context) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 300),
      child: isAvaSpeaking
          ? _SpeakingOrb(key: const ValueKey('speaking'))
          : _ListeningOrb(key: const ValueKey('listening')),
    );
  }

  Widget _buildTranscript(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        children: [
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 250),
            child: Text(
              isAvaSpeaking ? 'Ava está falando...' : 'Ouça...',
              key: ValueKey(isAvaSpeaking),
              style: TextStyle(
                color: isAvaSpeaking
                    ? const Color(0xFF00d4ff).withValues(alpha: 0.9)
                    : Colors.white.withValues(alpha: 0.5),
                fontSize: 12,
                letterSpacing: 2,
              ),
            ),
          ),
          if (remoteListen != null && !isAvaSpeaking)
            RemoteListenIndicator(state: remoteListen!),
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFF00d4ff).withValues(alpha: 0.3), width: 1),
            ),
            child: Text(
              lastTranscript.isEmpty ? '—' : lastTranscript,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.95),
                fontSize: 16,
                height: 1.4,
              ),
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ),
    );
  }

  static const String _commandsHintFull =
      'Comandos: "crie uma reunião", "tome notas", "ver minhas reuniões", "visualize o calendário", '
      '"marque um evento", "quais reuniões tenho hoje", "sair"';

  static const String _commandsHintContextual =
      'Sobre a lista acima: "leia as notas dessa reunião", "adicione uma nota nessa reunião bom dia", "cancela a primeira", "remarca a segunda para amanhã às 15h", "sair"';

  Widget _buildResults(BuildContext context) {
    const hintStyle = TextStyle(
      color: Colors.white54,
      fontSize: 12,
      height: 1.4,
    );
    if (commandResults.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(24),
        child: Text(
          _commandsHintFull,
          style: hintStyle,
          textAlign: TextAlign.center,
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
            itemCount: commandResults.length,
            itemBuilder: (context, i) {
              final r = commandResults[i];
              final label = r['label'] ?? '';
              final result = r['result'] ?? '';
              return Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: const Color(0xFF00d4ff).withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFF00d4ff).withValues(alpha: 0.2)),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 4,
                      height: 40,
                      decoration: BoxDecoration(
                        color: const Color(0xFF00d4ff),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            label,
                            style: TextStyle(
                              color: const Color(0xFF00d4ff),
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            result,
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.9),
                              fontSize: 14,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
          child: Text(
            _commandsHintContextual,
            style: hintStyle,
            textAlign: TextAlign.center,
          ),
        ),
      ],
    );
  }
}

/// Orb com pulso suave: estado "ouvindo".
class _ListeningOrb extends StatefulWidget {
  const _ListeningOrb({super.key});

  @override
  State<_ListeningOrb> createState() => _ListeningOrbState();
}

class _ListeningOrbState extends State<_ListeningOrb>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat(reverse: true);
    _scale = Tween<double>(begin: 0.92, end: 1.08).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _scale,
      builder: (context, child) {
        return Transform.scale(
          scale: _scale.value,
          child: child,
        );
      },
      child: Container(
        width: 120,
        height: 120,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(
            colors: [
              const Color(0xFF00d4ff).withValues(alpha: 0.4),
              const Color(0xFF00d4ff).withValues(alpha: 0.1),
              Colors.transparent,
            ],
          ),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF00d4ff).withValues(alpha: 0.3),
              blurRadius: 40,
              spreadRadius: 2,
            ),
          ],
        ),
        child: Center(
          child: Container(
            width: 24,
            height: 24,
            decoration: BoxDecoration(
              color: const Color(0xFF00d4ff).withValues(alpha: 0.8),
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF00d4ff).withValues(alpha: 0.8),
                  blurRadius: 12,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Orb com barras de "onda": estado "Ava falando".
class _SpeakingOrb extends StatefulWidget {
  const _SpeakingOrb({super.key});

  @override
  State<_SpeakingOrb> createState() => _SpeakingOrbState();
}

class _SpeakingOrbState extends State<_SpeakingOrb>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 120,
      height: 120,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Container(
            width: 100,
            height: 100,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                colors: [
                  const Color(0xFF00d4ff).withValues(alpha: 0.5),
                  const Color(0xFF00d4ff).withValues(alpha: 0.15),
                  Colors.transparent,
                ],
              ),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF00d4ff).withValues(alpha: 0.4),
                  blurRadius: 32,
                  spreadRadius: 2,
                ),
              ],
            ),
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: List.generate(5, (i) {
              final delay = i * 0.15;
              return AnimatedBuilder(
                animation: _controller,
                builder: (context, child) {
                  final t = (_controller.value + delay) % 1.0;
                  final h = 8.0 + 18.0 * (0.5 + 0.5 * (t < 0.5 ? t * 2 : 2 - t * 2));
                  return Container(
                    width: 5,
                    height: h,
                    margin: const EdgeInsets.symmetric(horizontal: 3),
                    decoration: BoxDecoration(
                      color: const Color(0xFF00d4ff).withValues(alpha: 0.9),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  );
                },
              );
            }),
          ),
        ],
      ),
    );
  }
}

class _GridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFF00d4ff).withValues(alpha: 0.06)
      ..strokeWidth = 1;
    const step = 40.0;
    for (double x = 0; x < size.width; x += step) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (double y = 0; y < size.height; y += step) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
