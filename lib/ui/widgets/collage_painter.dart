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
  double get innerRadius =>
      (outerRadius - borderThickness).clamp(0.0, outerRadius);

  RRect get outerClip => RRect.fromRectAndRadius(
    Offset.zero & canvasSize,
    Radius.circular(outerRadius),
  );

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

/// Desenha a borda externa da montagem: só o anel entre o canto externo e a
/// área interna. Pintar o retângulo inteiro com a cor da borda (como era
/// antes) fazia a cor vazar por baixo de tudo — com "Fundo transparente" as
/// margens entre as fotos saíam pintadas da cor da borda em vez de
/// transparentes, e não havia como ter borda e fundo transparente juntos.
void paintCollageBorder(Canvas canvas, Size size, CollageSettings settings) {
  final geometry = CollageGeometry.of(size, settings);
  if (geometry.borderThickness <= 0) return;
  // O anel avança meio pixel para dentro da área interna: o fundo e as fotos
  // são desenhados por cima logo em seguida, então essa sobra some — e sem
  // ela ficaria uma linha clara de antialiasing entre os dois desenhos.
  final overlap = geometry.borderThickness < 1
      ? geometry.borderThickness / 2
      : 0.5;
  canvas.drawDRRect(
    geometry.outerClip,
    geometry.innerClip.deflate(overlap),
    Paint()..color = settings.borderColor,
  );
}

/// [CustomPainter] que desenha [paintCollageBorder] na prévia ao vivo, para a
/// prévia na tela e o PNG exportado usarem literalmente o mesmo desenho de
/// borda — mesmo papel de [FramePainter] para a moldura de vídeo.
class CollageBorderPainter extends CustomPainter {
  const CollageBorderPainter(this.settings);

  final CollageSettings settings;

  @override
  void paint(Canvas canvas, Size size) =>
      paintCollageBorder(canvas, size, settings);

  @override
  bool shouldRepaint(covariant CollageBorderPainter oldDelegate) => true;
}

/// Desenha o fundo da montagem dentro de [rect] — a área interna, já dentro
/// da borda. [rect] (e não o canvas inteiro) é o que decide o recorte "cover"
/// da imagem de fundo, exatamente como o `BoxFit.cover` da prévia, que também
/// só enxerga a área interna: calcular o "cover" contra o canvas inteiro
/// enquadrava a imagem de um jeito na prévia e de outro na exportação sempre
/// que havia borda. Nada é desenhado quando o fundo é transparente.
void paintCollageBackground(
  Canvas canvas,
  Rect rect,
  CollageBackground background, {
  ui.Image? backgroundImage,
}) {
  if (rect.isEmpty) return;
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
        rect.width,
        rect.height,
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

/// Desenha a foto de uma célula, recortada (modo [CollageCellFitMode.cover])
/// ou inteira (modo [CollageCellFitMode.contain]) ao arredondamento próprio
/// da célula, com deslocamento/zoom/rotação livre/espelhamento/ajustes de
/// cor e a borda própria da célula (se houver) — a mesma ordem de
/// transformações (girar, depois espelhar) usada pela prévia ao vivo
/// (`Transform.rotate` por fora de `Transform` de espelhamento), para as
/// duas nunca divergirem visualmente.
void paintCollageCell(
  Canvas canvas,
  Rect cellRect,
  CollageCellSettings cell,
  ui.Image? photoImage,
) {
  if (photoImage == null) return;

  final outerRadius =
      cellRect.size.shortestSide *
      cell.cornerRatio.clamp(0.0, CollageCellSettings.maxCornerRatio);

  // Borda própria da foto (distinta da borda da montagem inteira): um anel
  // desenhado no perímetro da célula, encolhendo a área de conteúdo pela
  // mesma espessura — mesmo princípio de `paintCollageBorder`/
  // `CollageGeometry`, só que por célula em vez de pela montagem toda.
  final borderThickness = cell.borderThicknessFor(cellRect.width);
  final innerRadius = (outerRadius - borderThickness).clamp(0.0, outerRadius);
  final contentRect = cellRect.deflate(borderThickness);
  if (contentRect.isEmpty) return;

  canvas.save();
  canvas.clipRRect(
    RRect.fromRectAndRadius(cellRect, Radius.circular(outerRadius)),
  );
  if (borderThickness > 0) {
    canvas.drawRect(cellRect, Paint()..color = cell.borderColor);
  }
  canvas.clipRRect(
    RRect.fromRectAndRadius(contentRect, Radius.circular(innerRadius)),
  );

  canvas.translate(contentRect.center.dx, contentRect.center.dy);
  canvas.rotate(cell.rotation);
  if (cell.flipHorizontal || cell.flipVertical) {
    canvas.scale(cell.flipHorizontal ? -1 : 1, cell.flipVertical ? -1 : 1);
  }

  final paint = Paint()
    ..filterQuality = FilterQuality.high
    ..colorFilter = cell.colorFilter;
  switch (cell.fitMode) {
    case CollageCellFitMode.cover:
      final src = cell.coverSrcRect(contentRect.size);
      if (src != Rect.zero) {
        final (destWidth, destHeight) = rotatedFootprint(
          contentRect.width,
          contentRect.height,
          cell.rotation,
        );
        canvas.drawImageRect(
          photoImage,
          src,
          Rect.fromCenter(
            center: Offset.zero,
            width: destWidth,
            height: destHeight,
          ),
          paint,
        );
      }
    case CollageCellFitMode.contain:
      // Foto inteira (sem recorte): o que sobrar dentro da célula mostra o
      // fundo geral da montagem, já pintado por baixo antes das células.
      final display = cell.containDisplaySize(contentRect.size);
      if (display != Size.zero) {
        final offset = cell.containDisplayOffset(contentRect.size);
        canvas.drawImageRect(
          photoImage,
          Rect.fromLTWH(
            0,
            0,
            photoImage.width.toDouble(),
            photoImage.height.toDouble(),
          ),
          Rect.fromCenter(
            center: offset,
            width: display.width,
            height: display.height,
          ),
          paint,
        );
      }
  }
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
