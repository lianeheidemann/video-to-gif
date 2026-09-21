import 'package:flutter/material.dart';

import '../../app/preview_background_controller.dart';

/// Fundo quadriculado clássico de "transparência" (o mesmo indicador visual
/// de editores de imagem como Photoshop/GIMP) — cores neutras fixas,
/// independentes do tema claro/escuro, para representar sempre a mesma
/// coisa não importa o tema do app.
class CheckerboardBackground extends StatelessWidget {
  const CheckerboardBackground({super.key, this.cellSize = 12});

  final double cellSize;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _CheckerboardPainter(cellSize: cellSize),
      child: const SizedBox.expand(),
    );
  }
}

class _CheckerboardPainter extends CustomPainter {
  const _CheckerboardPainter({required this.cellSize});

  final double cellSize;

  static const _light = Color(0xFFE0E0E0);
  static const _dark = Color(0xFFB4B4B4);

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = _light);

    final darkPaint = Paint()..color = _dark;
    final cols = (size.width / cellSize).ceil();
    final rows = (size.height / cellSize).ceil();
    for (var row = 0; row < rows; row++) {
      for (var col = 0; col < cols; col++) {
        if ((row + col).isOdd) {
          canvas.drawRect(
            Rect.fromLTWH(col * cellSize, row * cellSize, cellSize, cellSize),
            darkPaint,
          );
        }
      }
    }
  }

  @override
  bool shouldRepaint(covariant _CheckerboardPainter oldDelegate) =>
      oldDelegate.cellSize != cellSize;
}

/// Envolve [child] com o fundo quadriculado por baixo, quando a preferência
/// global [previewCheckerboardNotifier] está ligada — usado atrás da prévia
/// nas três telas de edição (vídeo, foto e montagem), para a tela de prévia
/// inteira (não só as áreas que cada conteúdo marca como transparentes).
class PreviewAreaBackground extends StatelessWidget {
  const PreviewAreaBackground({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: previewCheckerboardNotifier,
      builder: (context, enabled, _) => Stack(
        fit: StackFit.expand,
        children: [if (enabled) const CheckerboardBackground(), child],
      ),
    );
  }
}
