import 'package:flutter/material.dart';

import '../../models/crop_rect.dart';

/// Qual alça de [CropOverlay] está sendo arrastada — as 4 de canto sempre
/// existem; as 4 de borda (meio de cada lado) só aparecem no modo livre
/// (`freeform: true`), para redimensionar um lado por vez.
enum CropHandle {
  topLeft,
  topRight,
  bottomLeft,
  bottomRight,
  top,
  bottom,
  left,
  right,
}

/// Arredonda para o número par mais próximo abaixo (mínimo 2) — exigência do
/// FFmpeg para recorte/escala de vídeo, inofensiva para fotos.
int _evenFloor(int value) {
  if (value <= 2) return 2;
  return value.isEven ? value : value - 1;
}

/// Redimensiona o recorte movendo só o canto/lado arrastado, sem travar a
/// proporção (usado no preset "Personalizado" do vídeo; não usado pelo
/// recorte de foto da montagem, que é sempre travado).
CropRect resizeFreeCrop(
  CropRect crop,
  CropHandle handle,
  double dx,
  double dy, {
  required int boundsWidth,
  required int boundsHeight,
}) {
  const minSize = 32;
  var left = crop.x.toDouble();
  var top = crop.y.toDouble();
  var right = (crop.x + crop.width).toDouble();
  var bottom = (crop.y + crop.height).toDouble();

  switch (handle) {
    case CropHandle.topLeft:
      left += dx;
      top += dy;
    case CropHandle.topRight:
      right += dx;
      top += dy;
    case CropHandle.bottomLeft:
      left += dx;
      bottom += dy;
    case CropHandle.bottomRight:
      right += dx;
      bottom += dy;
    case CropHandle.top:
      top += dy;
    case CropHandle.bottom:
      bottom += dy;
    case CropHandle.left:
      left += dx;
    case CropHandle.right:
      right += dx;
  }

  left = left.clamp(0.0, right - minSize);
  top = top.clamp(0.0, bottom - minSize);
  right = right.clamp(left + minSize, boundsWidth.toDouble());
  bottom = bottom.clamp(top + minSize, boundsHeight.toDouble());

  var width = _evenFloor((right - left).round());
  var height = _evenFloor((bottom - top).round());
  width = width.clamp(2, boundsWidth);
  height = height.clamp(2, boundsHeight);

  var x = left.round().clamp(0, boundsWidth - width);
  var y = top.round().clamp(0, boundsHeight - height);

  if (handle == CropHandle.topLeft ||
      handle == CropHandle.bottomLeft ||
      handle == CropHandle.left) {
    x = (right.round() - width).clamp(0, boundsWidth - width);
  }
  if (handle == CropHandle.topLeft ||
      handle == CropHandle.topRight ||
      handle == CropHandle.top) {
    y = (bottom.round() - height).clamp(0, boundsHeight - height);
  }

  return CropRect(x: x, y: y, width: width, height: height);
}

/// Redimensiona o recorte mantendo a proporção [ratio] fixa: o canto oposto
/// ao que foi arrastado fica ancorado, e a escala do arraste em ambos os
/// eixos é combinada para decidir o novo tamanho.
CropRect resizeLockedCrop(
  CropRect crop,
  CropHandle handle,
  double dx,
  double dy,
  double ratio, {
  required int boundsWidth,
  required int boundsHeight,
}) {
  const minSide = 32.0;
  // As alças de borda (top/bottom/left/right) só existem no modo livre
  // ("Personalizados"), que nunca chama esta função — os ramos delas abaixo
  // são inalcançáveis em tempo de execução e só existem para o switch
  // exaustivo sobre `CropHandle` compilar; foram agrupados com o canto/lado
  // correspondente para manter os valores plausíveis.
  final deltaW = switch (handle) {
    CropHandle.topLeft || CropHandle.bottomLeft || CropHandle.left => -dx,
    CropHandle.topRight || CropHandle.bottomRight || CropHandle.right => dx,
    CropHandle.top || CropHandle.bottom => 0.0,
  };
  final deltaH = switch (handle) {
    CropHandle.topLeft || CropHandle.topRight || CropHandle.top => -dy,
    CropHandle.bottomLeft || CropHandle.bottomRight || CropHandle.bottom => dy,
    CropHandle.left || CropHandle.right => 0.0,
  };

  final widthChange = deltaW / crop.width;
  final heightChange = deltaH / crop.height;
  final scaleChange = (widthChange + heightChange) / 2;

  var width = crop.width * (1 + scaleChange);
  var height = width / ratio;

  if (height < minSide) {
    height = minSide;
    width = height * ratio;
  }
  if (width < minSide) {
    width = minSide;
    height = width / ratio;
  }

  final anchorX = switch (handle) {
    CropHandle.topLeft ||
    CropHandle.bottomLeft ||
    CropHandle.left => (crop.x + crop.width).toDouble(),
    CropHandle.topRight ||
    CropHandle.bottomRight ||
    CropHandle.right ||
    CropHandle.top ||
    CropHandle.bottom => crop.x.toDouble(),
  };
  final anchorY = switch (handle) {
    CropHandle.topLeft ||
    CropHandle.topRight ||
    CropHandle.top => (crop.y + crop.height).toDouble(),
    CropHandle.bottomLeft ||
    CropHandle.bottomRight ||
    CropHandle.bottom ||
    CropHandle.left ||
    CropHandle.right => crop.y.toDouble(),
  };

  final maxWidthByX = switch (handle) {
    CropHandle.topLeft || CropHandle.bottomLeft || CropHandle.left => anchorX,
    CropHandle.topRight ||
    CropHandle.bottomRight ||
    CropHandle.right ||
    CropHandle.top ||
    CropHandle.bottom => boundsWidth - anchorX,
  };
  final maxHeightByY = switch (handle) {
    CropHandle.topLeft || CropHandle.topRight || CropHandle.top => anchorY,
    CropHandle.bottomLeft ||
    CropHandle.bottomRight ||
    CropHandle.bottom ||
    CropHandle.left ||
    CropHandle.right => boundsHeight - anchorY,
  };

  final maxWidth = maxWidthByX < maxHeightByY * ratio
      ? maxWidthByX
      : maxHeightByY * ratio;
  width = width.clamp(2.0, maxWidth);
  height = width / ratio;

  var evenWidth = _evenFloor(width.round());
  var evenHeight = _evenFloor((evenWidth / ratio).round());
  if (evenHeight > maxHeightByY) {
    evenHeight = _evenFloor(maxHeightByY.floor());
    evenWidth = _evenFloor((evenHeight * ratio).round());
  }

  evenWidth = evenWidth.clamp(2, boundsWidth);
  evenHeight = evenHeight.clamp(2, boundsHeight);

  final x = switch (handle) {
    CropHandle.topLeft || CropHandle.bottomLeft || CropHandle.left =>
      (anchorX.round() - evenWidth).clamp(0, boundsWidth - evenWidth),
    CropHandle.topRight ||
    CropHandle.bottomRight ||
    CropHandle.right ||
    CropHandle.top ||
    CropHandle.bottom => anchorX.round().clamp(0, boundsWidth - evenWidth),
  };
  final y = switch (handle) {
    CropHandle.topLeft || CropHandle.topRight || CropHandle.top =>
      (anchorY.round() - evenHeight).clamp(0, boundsHeight - evenHeight),
    CropHandle.bottomLeft ||
    CropHandle.bottomRight ||
    CropHandle.bottom ||
    CropHandle.left ||
    CropHandle.right => anchorY.round().clamp(0, boundsHeight - evenHeight),
  };

  return CropRect(x: x, y: y, width: evenWidth, height: evenHeight);
}

/// Moldura de recorte arrastável sobre uma prévia de [bounds] (pixels do
/// conteúdo original — vídeo ou foto): véu escuro fora da janela de recorte,
/// borda branca, alças nos 4 cantos (sempre) e nos 4 lados (só quando
/// [freeform]), mais um botão para mover a janela inteira. Puramente visual +
/// gestos; quem decide a nova geometria são [resizeFreeCrop]/
/// [resizeLockedCrop], chamados pelo dono deste widget via [onResize].
class CropOverlay extends StatelessWidget {
  const CropOverlay({
    super.key,
    required this.bounds,
    required this.crop,
    required this.onResize,
    required this.onMove,
    required this.freeform,
  });

  final Size bounds;
  final CropRect? crop;
  final void Function(CropHandle handle, Offset delta, Size previewSize)
  onResize;
  final void Function(Offset delta, Size previewSize) onMove;

  /// Se true (preset "Personalizados"), também mostra as quatro alças de
  /// borda (meio de cada lado) para redimensionar um lado por vez.
  final bool freeform;

  static const _handleBoxSize = 34.0;

  @override
  Widget build(BuildContext context) {
    final rect = crop;
    if (rect == null) return const SizedBox.shrink();

    return LayoutBuilder(
      builder: (context, constraints) {
        final previewSize = Size(constraints.maxWidth, constraints.maxHeight);
        final scaleX = constraints.maxWidth / bounds.width;
        final scaleY = constraints.maxHeight / bounds.height;
        final left = rect.x * scaleX;
        final top = rect.y * scaleY;
        final width = rect.width * scaleX;
        final height = rect.height * scaleY;
        const veil = Color(0x8C000000);

        // Mantém a bolinha inteira dentro da prévia, mesmo quando o canto da
        // janela de recorte encosta na borda do conteúdo — senão ela é
        // cortada pelo clipe arredondado do preview e fica "escondida".
        double clampLeft(double raw) =>
            raw.clamp(0.0, previewSize.width - _handleBoxSize);
        double clampTop(double raw) =>
            raw.clamp(0.0, previewSize.height - _handleBoxSize);

        // Constrói uma alça arrastável na posição dada (já limitada para não
        // sair da área visível da prévia). As de canto são bolinhas; as de
        // borda (meio de cada lado) são retângulos pequenos, para
        // diferenciar visualmente que só movem um lado por vez.
        Widget handle(CropHandle handle, double rawLeft, double rawTop) {
          final isEdge =
              handle == CropHandle.top ||
              handle == CropHandle.bottom ||
              handle == CropHandle.left ||
              handle == CropHandle.right;
          final isVertical =
              handle == CropHandle.left || handle == CropHandle.right;
          final markWidth = isEdge ? (isVertical ? 8.0 : 22.0) : 15.0;
          final markHeight = isEdge ? (isVertical ? 22.0 : 8.0) : 15.0;

          return Positioned(
            left: clampLeft(rawLeft),
            top: clampTop(rawTop),
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onPanUpdate: (details) =>
                  onResize(handle, details.delta, previewSize),
              child: SizedBox(
                width: _handleBoxSize,
                height: _handleBoxSize,
                child: Center(
                  child: Container(
                    width: markWidth,
                    height: markHeight,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      shape: isEdge ? BoxShape.rectangle : BoxShape.circle,
                      borderRadius: isEdge ? BorderRadius.circular(3) : null,
                      border: Border.all(color: Colors.black54, width: 1.5),
                      boxShadow: const [
                        BoxShadow(
                          color: Colors.black45,
                          blurRadius: 4,
                          offset: Offset(0, 1),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          );
        }

        // Botão para mover a janela inteira, ao lado dela — também travado
        // dentro da área da prévia.
        final moveLeft = clampLeft(left + width + 10);
        final moveTop = clampTop(top + height / 2 - _handleBoxSize / 2);
        final moveButton = Positioned(
          left: moveLeft,
          top: moveTop,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onPanUpdate: (details) => onMove(details.delta, previewSize),
            child: Container(
              width: _handleBoxSize,
              height: _handleBoxSize,
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primary,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 1.5),
                boxShadow: const [
                  BoxShadow(
                    color: Colors.black45,
                    blurRadius: 4,
                    offset: Offset(0, 1),
                  ),
                ],
              ),
              child: const Icon(
                Icons.open_with_rounded,
                color: Colors.white,
                size: 18,
              ),
            ),
          ),
        );

        return Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned(
              left: 0,
              right: 0,
              top: 0,
              height: top,
              child: const IgnorePointer(child: ColoredBox(color: veil)),
            ),
            Positioned(
              left: 0,
              right: 0,
              top: top + height,
              bottom: 0,
              child: const IgnorePointer(child: ColoredBox(color: veil)),
            ),
            Positioned(
              left: 0,
              width: left,
              top: top,
              height: height,
              child: const IgnorePointer(child: ColoredBox(color: veil)),
            ),
            Positioned(
              left: left + width,
              right: 0,
              top: top,
              height: height,
              child: const IgnorePointer(child: ColoredBox(color: veil)),
            ),
            Positioned(
              left: left,
              top: top,
              width: width,
              height: height,
              child: IgnorePointer(
                child: Container(
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.white, width: 2),
                  ),
                ),
              ),
            ),
            handle(CropHandle.topLeft, left - 17, top - 17),
            handle(CropHandle.topRight, left + width - 17, top - 17),
            handle(CropHandle.bottomLeft, left - 17, top + height - 17),
            handle(
              CropHandle.bottomRight,
              left + width - 17,
              top + height - 17,
            ),
            if (freeform) ...[
              handle(CropHandle.top, left + width / 2 - 17, top - 17),
              handle(
                CropHandle.bottom,
                left + width / 2 - 17,
                top + height - 17,
              ),
              handle(CropHandle.left, left - 17, top + height / 2 - 17),
              handle(
                CropHandle.right,
                left + width - 17,
                top + height / 2 - 17,
              ),
            ],
            moveButton,
          ],
        );
      },
    );
  }
}
