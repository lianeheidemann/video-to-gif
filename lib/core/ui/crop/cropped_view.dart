import 'package:flutter/material.dart';

import '../../models/conversion_settings.dart';

/// Mostra apenas a janela de recorte de um conteúdo do tamanho da fonte —
/// usado na aba "Frame" do editor, onde o vídeo tem que aparecer já cortado,
/// exatamente como vai sair no GIF, sem as alças de recorte da aba
/// "Ajustar".
///
/// Toda a conta é feita em pixels da fonte (os mesmos de [CropRect], que o
/// FFmpeg usa no filtro `crop`) e só no fim o [FittedBox] escala o resultado
/// para o espaço disponível. Assim o enquadramento não depende do tamanho da
/// tela nem precisa repetir a aritmética de recorte em unidades de layout.
class CroppedView extends StatelessWidget {
  const CroppedView({
    super.key,
    required this.sourceWidth,
    required this.sourceHeight,
    required this.crop,
    required this.child,
  });

  /// Dimensões do conteúdo inteiro, em pixels (as de exibição do vídeo).
  final int sourceWidth;
  final int sourceHeight;

  /// A janela a mostrar. `null` mostra a fonte inteira.
  final CropRect? crop;

  /// Desenhado no tamanho da fonte inteira; este widget cuida de deslocar e
  /// recortar.
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final source = crop;
    if (source == null ||
        sourceWidth <= 0 ||
        sourceHeight <= 0 ||
        source.width <= 0 ||
        source.height <= 0) {
      return AspectRatio(
        aspectRatio: sourceHeight <= 0 ? 1 : sourceWidth / sourceHeight,
        child: child,
      );
    }

    return AspectRatio(
      aspectRatio: source.aspectRatio,
      child: FittedBox(
        fit: BoxFit.fill,
        child: SizedBox(
          width: source.width.toDouble(),
          height: source.height.toDouble(),
          child: ClipRect(
            child: OverflowBox(
              alignment: Alignment.topLeft,
              minWidth: 0,
              minHeight: 0,
              maxWidth: sourceWidth.toDouble(),
              maxHeight: sourceHeight.toDouble(),
              child: Transform.translate(
                offset: Offset(-source.x.toDouble(), -source.y.toDouble()),
                child: SizedBox(
                  width: sourceWidth.toDouble(),
                  height: sourceHeight.toDouble(),
                  child: child,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
