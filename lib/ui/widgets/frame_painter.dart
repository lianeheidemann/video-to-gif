import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
// Reexporta `vg` (a constante top-level VectorGraphicsUtilities) e
// PictureInfo do pacote vector_graphics, usados em [rasterizeSvgAsset].
import 'package:flutter_svg/flutter_svg.dart';

import '../../models/frame_settings.dart';

/// Geometria de uma moldura já calculada para um [Size] específico: raio de
/// canto externo/interno, espessura em pixels e o retângulo onde o
/// conteúdo (vídeo) deve ser desenhado. Tudo em proporção ao tamanho
/// recebido — nunca pixels fixos —, para a moldura ficar nítida e
/// proporcional em qualquer resolução, seja a prévia na tela ou o GIF
/// exportado.
class FrameGeometry {
  const FrameGeometry({
    required this.outerRadius,
    required this.innerRadius,
    required this.thickness,
    required this.contentRect,
  });

  final double outerRadius;
  final double innerRadius;
  final double thickness;
  final Rect contentRect;

  factory FrameGeometry.of(Size size, FrameSettings settings) {
    if (settings.style == FrameStyle.none) {
      return FrameGeometry(
        outerRadius: 0,
        innerRadius: 0,
        thickness: 0,
        contentRect: Offset.zero & size,
      );
    }

    final shorterSide = size.shortestSide;
    final thickness = settings.thicknessFor(size.width);
    final outerRadius = settings.cornerRadiusFor(shorterSide);
    final innerRadius = (outerRadius - thickness).clamp(0.0, outerRadius);
    final contentRect = Rect.fromLTWH(
      thickness,
      thickness,
      (size.width - thickness * 2).clamp(0.0, size.width),
      (size.height - thickness * 2).clamp(0.0, size.height),
    );

    return FrameGeometry(
      outerRadius: outerRadius,
      innerRadius: innerRadius,
      thickness: thickness,
      contentRect: contentRect,
    );
  }

  /// Recorte arredondado da área de conteúdo, pronto para clipar o vídeo.
  RRect get contentClip =>
      RRect.fromRectAndRadius(contentRect, Radius.circular(innerRadius));
}

/// Desenha o fundo/borda da moldura em [canvas] para um retângulo de
/// [size], a partir de [settings]. Não desenha o conteúdo (vídeo) — isso é
/// feito por cima, fora daqui, recortado por [FrameGeometry.contentClip].
///
/// A moldura em si é sempre a forma arredondada, na cor escolhida. O que o
/// "Fundo transparente" decide é só o que fica nos 4 cantos que sobram fora
/// dela: ligado, nada (transparente no PNG exportado, ou o que houver atrás,
/// na prévia); desligado, a cor de fundo escolhida. Pintar os cantos com a
/// própria cor da moldura — como era antes — apagava o arredondamento no modo
/// opaco.
void paintFrame(Canvas canvas, Size size, FrameSettings settings) {
  if (settings.style == FrameStyle.none) return;

  final rect = Offset.zero & size;
  final geometry = FrameGeometry.of(size, settings);

  if (!settings.transparentBackground) {
    canvas.drawRect(rect, Paint()..color = settings.backgroundColor);
  }
  canvas.drawRRect(
    RRect.fromRectAndRadius(rect, Radius.circular(geometry.outerRadius)),
    Paint()..color = settings.color,
  );
}

/// [CustomPainter] que desenha [paintFrame] por cima da prévia do vídeo no
/// editor, e também sabe se [rasterize]ar a mesma moldura em qualquer
/// resolução — a mesma lógica de desenho serve para a prévia (tamanho de
/// tela) e para a exportação (tamanho exato do GIF final), nunca duas
/// implementações divergentes.
class FramePainter extends CustomPainter {
  const FramePainter(this.settings);

  final FrameSettings settings;

  @override
  void paint(Canvas canvas, Size size) => paintFrame(canvas, size, settings);

  @override
  bool shouldRepaint(covariant FramePainter oldDelegate) =>
      oldDelegate.settings != settings;

  /// Rasteriza a moldura para um PNG de exatamente [width]x[height] pixels
  /// — usado antes de chamar o FFmpeg, para a moldura nunca ser um asset de
  /// resolução fixa sendo esticado, e sim gerada já no tamanho final exato
  /// da exportação.
  static Future<Uint8List> rasterize(
    int width,
    int height,
    FrameSettings settings,
  ) => rasterizeCanvas(
    width,
    height,
    (canvas, size) => paintFrame(canvas, size, settings),
  );
}

/// Rasteriza uma máscara em preto e branco para o contorno arredondado, no
/// tamanho final exato — sem suavização extra. O GIF só suporta
/// transparência binária (`alpha_threshold` corta em 0 ou 255, nunca um
/// meio-termo), então qualquer borda em degradê de cinza vira uma faixa de
/// pixels tratados de forma inconsistente entre um quadro e outro, visível
/// como uma linha colorida ao redor da moldura. Ver [rasterizeCanvas].
Future<Uint8List> rasterizeCornerMask(
  int width,
  int height,
  double outerRadius,
) => rasterizeCanvas(width, height, (canvas, size) {
  final rect = Offset.zero & size;
  canvas.drawRect(rect, Paint()..color = Colors.black);
  canvas.drawRRect(
    RRect.fromRectAndRadius(rect, Radius.circular(outerRadius)),
    Paint()
      ..color = Colors.white
      ..isAntiAlias = true,
  );
});

/// Rasteriza o SVG do asset [assetPath] para um PNG de exatamente
/// [width]x[height] pixels — a arte é vetorial, então isso nunca perde
/// nitidez em nenhuma resolução de saída, ao contrário de esticar um asset
/// bitmap de tamanho fixo. Usa [rasterizeCanvas] (mesma base do resto deste
/// arquivo) para nunca haver dois caminhos de rasterização divergentes.
Future<Uint8List> rasterizeSvgAsset(
  String assetPath,
  int width,
  int height,
) async {
  final loader = SvgAssetLoader(assetPath);
  final pictureInfo = await vg.loadPicture(loader, null);
  try {
    return await rasterizeCanvas(width, height, (canvas, size) {
      canvas.scale(
        size.width / pictureInfo.size.width,
        size.height / pictureInfo.size.height,
      );
      canvas.drawPicture(pictureInfo.picture);
    });
  } finally {
    pictureInfo.picture.dispose();
  }
}

/// Rasteriza a imagem importada em [filePath] para um PNG de exatamente
/// [width]x[height] pixels, com reamostragem de alta qualidade — mesma
/// necessidade de nitidez em qualquer resolução de saída que
/// [rasterizeSvgAsset], mas a partir de um arquivo bitmap já existente em
/// vez de um desenho vetorial.
Future<Uint8List> rasterizeImportedImage(
  String filePath,
  int width,
  int height,
) async {
  final bytes = await File(filePath).readAsBytes();
  final codec = await ui.instantiateImageCodec(bytes);
  final frame = await codec.getNextFrame();
  final image = frame.image;
  try {
    return await rasterizeCanvas(width, height, (canvas, size) {
      final paint = Paint()..filterQuality = FilterQuality.high;
      canvas.drawImageRect(
        image,
        Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
        Offset.zero & size,
        paint,
      );
    });
  } finally {
    image.dispose();
  }
}

/// Grava um desenho de [width]x[height] pixels (feito por [paint]) como PNG
/// — a base compartilhada por [FramePainter.rasterize] e
/// [rasterizeCornerMask].
Future<Uint8List> rasterizeCanvas(
  int width,
  int height,
  void Function(Canvas canvas, Size size) paint,
) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  final size = Size(width.toDouble(), height.toDouble());
  paint(canvas, size);
  final picture = recorder.endRecording();
  try {
    final image = await picture.toImage(width, height);
    try {
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      return bytes!.buffer.asUint8List();
    } finally {
      image.dispose();
    }
  } finally {
    picture.dispose();
  }
}

