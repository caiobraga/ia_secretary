import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

/// Tela exibida quando a permissão "Exibir sobre outros apps" não está concedida (Android).
/// Segue o padrão visual futurista do app.
class OverlayPermissionScreen extends StatelessWidget {
  const OverlayPermissionScreen({
    super.key,
    required this.isChecking,
    required this.onOpenSettings,
    required this.onRetry,
  });

  final bool isChecking;
  final VoidCallback onOpenSettings;
  final VoidCallback onRetry;

  static const _accentColor = Color(0xFF00d4ff);
  static const _bgStart = Color(0xFF0a0e17);
  static const _bgMid = Color(0xFF0d1321);

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
            colors: [_bgStart, _bgMid, _bgStart],
          ),
        ),
        child: Stack(
          children: [
            CustomPaint(painter: _GridPainter(), size: Size.infinite),
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // Ícone com glow
                    Container(
                      width: 100,
                      height: 100,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: RadialGradient(
                          colors: [
                            _accentColor.withValues(alpha: 0.3),
                            _accentColor.withValues(alpha: 0.1),
                            Colors.transparent,
                          ],
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: _accentColor.withValues(alpha: 0.3),
                            blurRadius: 30,
                            spreadRadius: 2,
                          ),
                        ],
                      ),
                      child: Icon(
                        Icons.layers_outlined,
                        size: 48,
                        color: _accentColor.withValues(alpha: 0.9),
                      ),
                    ),
                    const SizedBox(height: 32),
                    // Título
                    Text(
                      'PERMISSÃO NECESSÁRIA',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.95),
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 2,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 20),
                    // Descrição principal
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.05),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: _accentColor.withValues(alpha: 0.2),
                        ),
                      ),
                      child: Text(
                        'Para a Ava abrir quando você disser "Ava" ou "Secretária", '
                        'é preciso permitir que o app seja exibido sobre outros apps.',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.85),
                          fontSize: 15,
                          height: 1.5,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                    const SizedBox(height: 16),
                    // Instruções
                    Text(
                      'Configurações → Apps → IA Secretary → Exibir sobre outros apps',
                      style: TextStyle(
                        color: _accentColor.withValues(alpha: 0.8),
                        fontSize: 13,
                        height: 1.4,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 32),
                    // Botões ou loading
                    if (isChecking)
                      SizedBox(
                        width: 48,
                        height: 48,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation(_accentColor),
                        ),
                      )
                    else ...[
                      // Botão principal
                      _FuturisticButton(
                        onPressed: () async {
                          await Permission.systemAlertWindow.request();
                          onOpenSettings();
                        },
                        icon: Icons.settings,
                        label: 'ABRIR CONFIGURAÇÕES',
                        isPrimary: true,
                      ),
                      const SizedBox(height: 16),
                      // Botão secundário
                      _FuturisticButton(
                        onPressed: onRetry,
                        icon: Icons.refresh,
                        label: 'JÁ PERMITI, VERIFICAR',
                        isPrimary: false,
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FuturisticButton extends StatelessWidget {
  const _FuturisticButton({
    required this.onPressed,
    required this.icon,
    required this.label,
    required this.isPrimary,
  });

  final VoidCallback onPressed;
  final IconData icon;
  final String label;
  final bool isPrimary;

  static const _accentColor = Color(0xFF00d4ff);

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onPressed,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 20),
        decoration: BoxDecoration(
          color: isPrimary 
              ? _accentColor.withValues(alpha: 0.15) 
              : Colors.white.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isPrimary 
                ? _accentColor.withValues(alpha: 0.5) 
                : Colors.white.withValues(alpha: 0.15),
            width: 1,
          ),
          boxShadow: isPrimary
              ? [
                  BoxShadow(
                    color: _accentColor.withValues(alpha: 0.2),
                    blurRadius: 12,
                    spreadRadius: 0,
                  ),
                ]
              : null,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 20,
              color: isPrimary 
                  ? _accentColor 
                  : Colors.white.withValues(alpha: 0.7),
            ),
            const SizedBox(width: 10),
            Text(
              label,
              style: TextStyle(
                color: isPrimary 
                    ? _accentColor 
                    : Colors.white.withValues(alpha: 0.7),
                fontSize: 13,
                fontWeight: FontWeight.w600,
                letterSpacing: 1,
              ),
            ),
          ],
        ),
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
