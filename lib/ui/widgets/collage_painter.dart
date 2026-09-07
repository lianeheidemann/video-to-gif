import 'dart:ui' as ui;

import 'package:flutter/material.dart' hide Image;

import '../../models/collage_background.dart';
import '../../models/collage_cell.dart';
import '../../models/collage_settings.dart';

/// Geometria de uma montagem já calculada para um [Size] específico: raio de
/// canto externo, espessura da borda em pixels e o retângulo de cada célula
/// — tudo proporcional ao tamanho recebido (nunca pixels fixos), para a
/// prévia ao vivo (tamanho de tela) e a exportação (tamanho exato do PNG
/// final) nunca ficarem fora de sincronia. Mesmo princípio de
/// `FrameGeometry` em `frame_painter.dart`, generalizado para N células.
class CollageGeometry {
  const CollageGeometry({
    required this.canvasSize,
    required this.cellRects,
    required this.outerRadius,
    required this.borderThickness,
  });

  final Size canvasSize;
  final List<Rect> cellRects;
  final double outerRadius;
  final double borderThickness;

  factory CollageGeometry.of(Size size, CollageSettings settings) {
    final thickness = settings.borderThicknessFor(size.width);
    final outerRadius = settings.cornerRadiusFor(size.shortestSide);
    final contentRect = Rect.fromLTWH(
      thickness,
      thickness,
      (size.width - thickness * 2).clamp(0.0, size.width),
      (size.height - thickness * 2).clamp(0.0, size.height),
    );
    final rects = settings.layout
        .cellRectsFor(contentRect.size, settings.marginRatio)
        .map((r) => r.shift(contentRect.topLeft))
        .toList();
    return CollageGeometry(
      canvasSize: size,
      cellRects: rects,
      outerRadius: outerRadius,
      borderThickness: thickness,
    );
  }

  /// Raio de canto da área interna (dentro da borda) — a borda mantém a
  /// mesma "espessura visual" de um canto ao outro.
  double get innerRadius => (outerRadius - borderThickness).clamp(0.0, outerRadius);

  RRect get outerClip =>
      RRect.fromRectAndRadius(Offset.zero & canvasSize, Radius.circular(outerRadius));

  RRect get innerClip => RRect.fromRectAndRadius(
    Rect.fromLTWH(
      borderThickness,
      borderThickness,
      (canvasSize.width - borderThickness * 2).clamp(0.0, canvasSize.width),
      (canvasSize.height - borderThickness * 2).clamp(0.0, canvasSize.height),
    ),
    Radius.circular(innerRadius),
  );
}

/// Desenha a borda externa da montagem (cor sólida atrás de tudo, visível só
/// no anel entre o canto externo e a área interna) — mesmo princípio de
/// `paintFrame`.
void paintCollageBorder(Canvas canvas, Size size, CollageSettings settings) {
  if (settings.borderThicknessFor(size.width) <= 0) return;
  final geometry = CollageGeometry.of(size, settings);
  canvas.drawRRect(geometry.outerClip, Paint()..color = settings.borderColor);
}

/// Desenha o fundo da montagem (dentro da área interna, já recortada pelo
/// arredondamento) — nada quando transparente.
void paintCollageBackground(
  Canvas canvas,
  Size size,
  CollageBackground background, {
  ui.Image? backgroundImage,
}) {
  final rect = Offset.zero & size;
  switch (background.mode) {
    case CollageBackgroundMode.transparent:
      return;
    case CollageBackgroundMode.color:
      canvas.drawRect(rect, Paint()..color = background.color);
      return;
    case CollageBackgroundMode.image:
      if (backgroundImage == null) return;
      final src = coverSrcRectFor(
        backgroundImage.width.toDouble(),
        backgroundImage.height.toDouble(),
        size.width,
        size.height,
      );
      canvas.drawImageRect(
        backgroundImage,
        src,
        rect,
        Paint()..filterQuality = FilterQuality.high,
      );
      return;
  }
}

/// Desenha a foto de uma célula, recortada ao arredondamento próprio da
/// célula, com deslocamento/zoom/rotação/espelhamento/ajustes de cor — a
/// mesma ordem de transformações (girar, depois espelhar) usada pela prévia
/// ao vivo (`RotatedBox` por fora de `Transform` de espelhamento), para as
/// duas nunca divergirem visualmente.
void paintCollageCell(Canvas canvas, Rect cellRect, CollageCellSettings cell, ui.Image? photoImage) {
  if (photoImage == null) return;

  final outerRadius =
      cellRect.size.shortestSide * cell.cornerRatio.clamp(0.0, CollageCellSettings.maxCornerRatio);
  final src = cell.coverSrcRect(cellRect.size);
  if (src == Rect.zero) return;

  final destWidth = cell.rotation.swapsAxes ? cellRect.height : cellRect.width;
  final destHeight = cell.rotation.swapsAxes ? cellRect.width : cellRect.height;
  final dest = Rect.fromCenter(center: Offset.zero, width: destWidth, height: destHeight);

  canvas.save();
  canvas.clipRRect(RRect.fromRectAndRadius(cellRect, Radius.circular(outerRadius)));
  canvas.translate(cellRect.center.dx, cellRect.center.dy);
  canvas.rotate(cell.rotation.radians);
  if (cell.flipHorizontal || cell.flipVertical) {
    canvas.scale(cell.flipHorizontal ? -1 : 1, cell.flipVertical ? -1 : 1);
  }
  canvas.drawImageRect(
    photoImage,
    src,
    dest,
    Paint()
      ..filterQuality = FilterQuality.high
      ..colorFilter = cell.colorFilter,
  );
  canvas.restore();
}

/// Retângulo de origem que, desenhado no destino `dstW`×`dstH`, cobre todo o
/// destino recortando o excedente do maior eixo — o "cover" do
/// `BoxFit.cover`, mesma matemática de `photo_frame_compositor.dart`'s
/// `_coverSrcRect`, reexposta aqui para o fundo de imagem da montagem.
Rect coverSrcRectFor(double srcW, double srcH, double dstW, double dstH) {
  final srcAspect = srcW / srcH;
  final dstAspect = dstW / dstH;
  if (srcAspect > dstAspect) {
    final cropWidth = srcH * dstAspect;
    return Rect.fromLTWH((srcW - cropWidth) / 2, 0, cropWidth, srcH);
  }
  final cropHeight = srcW / dstAspect;
  return Rect.fromLTWH(0, (srcH - cropHeight) / 2, srcW, cropHeight);
}
