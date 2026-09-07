import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../models/frame_settings.dart';
import '../models/image_frame.dart';
import '../models/photo_info.dart';
import '../ui/widgets/frame_painter.dart';

/// Compõe uma [PhotoInfo] com a [FrameSettings] escolhida (moldura
/// procedural ou moldura de imagem) num PNG final, com `dart:ui`/[Canvas]
/// puro — ao contrário do vídeo, uma foto não tem quadros nem tempo, então
/// não há necessidade do pipeline de FFmpeg usado por
/// `FfmpegService._framedGraph`/`_imageFramedGraph`; esta função replica a
/// mesma lógica de ajuste de conteúdo (cover/contain/expandir com zoom)
/// diretamente em cima da imagem decodificada.
Future<Uint8List> composeFramedPhoto({
  required PhotoInfo photo,
  required FrameSettings frame,
}) async {
  final image = await _decodeImageFile(photo.path);
  try {
    return await (frame.imageFrame != null
        ? _composeImageFramed(photo, image, frame)
        : _composeProcedural(photo, image, frame));
  } finally {
    image.dispose();
  }
}

/// Moldura procedural (ou nenhuma): canvas no tamanho nativo da foto. Sem
/// nenhum passo assíncrono no meio, pode usar [rasterizeCanvas] direto,
/// igual a [FramePainter.rasterize].
Future<Uint8List> _composeProcedural(
  PhotoInfo photo,
  ui.Image image,
  FrameSettings frame,
) {
  return rasterizeCanvas(photo.width, photo.height, (canvas, size) {
    // `paintFrame` já não desenha nada quando o estilo é `none`, e a
    // geometria correspondente cobre o canvas inteiro sem cantos
    // arredondados — então não precisa de um caso especial para "sem
    // moldura": o recorte abaixo já sai igual à foto original.
    paintFrame(canvas, size, frame);
    final geometry = FrameGeometry.of(size, frame);
    canvas.save();
    canvas.clipRRect(geometry.contentClip);
    final srcRect = _coverSrcRect(
      image.width.toDouble(),
      image.height.toDouble(),
      geometry.contentRect.width,
      geometry.contentRect.height,
    );
    canvas.drawImageRect(
      image,
      srcRect,
      geometry.contentRect,
      Paint()..filterQuality = FilterQuality.high,
    );
    canvas.restore();
  });
}

/// Moldura de imagem: canvas dimensionado por
/// [FrameSettings.frameResolutionMode], com a foto ajustada dentro da
/// janela de conteúdo da arte ([ImageFrameAsset.contentRect]) conforme
/// [ContentFitMode], e a arte desenhada por cima. Não usa [rasterizeCanvas]
/// porque desenhar a arte precisa de um passo assíncrono
/// (`vg.loadPicture`/decodificar um PNG importado) entre os outros
/// desenhos, que a assinatura síncrona de [rasterizeCanvas] não permite.
Future<Uint8List> _composeImageFramed(
  PhotoInfo photo,
  ui.Image image,
  FrameSettings frame,
) async {
  final asset = frame.imageFrame!;
  final (canvasWidth, canvasHeight) = _imageFrameCanvasDimensions(
    photo,
    asset,
    frame.frameResolutionMode,
  );
  final size = Size(canvasWidth.toDouble(), canvasHeight.toDouble());
  final areaRect = Rect.fromLTWH(
    size.width * asset.contentRect.left,
    size.height * asset.contentRect.top,
    size.width * asset.contentRect.width,
    size.height * asset.contentRect.height,
  );

  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);

  if (!frame.transparentBackground) {
    canvas.drawRect(Offset.zero & size, Paint()..color = frame.backgroundColor);
  }

  final fullImageRect = Rect.fromLTWH(
    0,
    0,
    image.width.toDouble(),
    image.height.toDouble(),
  );
  final paint = Paint()..filterQuality = FilterQuality.high;
  final fit = resolveContentFit(
    frame.contentFit,
    photo.aspectRatio,
    areaRect.width / areaRect.height,
  );

  if (fit == ContentFitMode.expand) {
    // Mesma composição de `FfmpegService._imageFramedGraph`: a foto cabe
    // inteira dentro da área (escala mínima dos dois eixos), o zoom amplia
    // ou reduz só ela sobre um fundo preto do tamanho da área, e o que
    // passar da área é recortado.
    canvas.save();
    canvas.clipRect(areaRect);
    canvas.drawRect(areaRect, Paint()..color = Colors.black);
    final fitScale = math.min(
      areaRect.width / image.width,
      areaRect.height / image.height,
    );
    final zoom = frame.effectiveContentZoom;
    final drawWidth = image.width * fitScale * zoom;
    final drawHeight = image.height * fitScale * zoom;
    canvas.drawImageRect(
      image,
      fullImageRect,
      Rect.fromLTWH(
        areaRect.left + (areaRect.width - drawWidth) / 2,
        areaRect.top + (areaRect.height - drawHeight) / 2,
        drawWidth,
        drawHeight,
      ),
      paint,
    );
    canvas.restore();
  } else if (fit == ContentFitMode.fill) {
    final srcRect = _coverSrcRect(
      image.width.toDouble(),
      image.height.toDouble(),
      areaRect.width,
      areaRect.height,
    );
    canvas.drawImageRect(image, srcRect, areaRect, paint);
  } else {
    // `auto` resolvido para `fit`: cabe inteira, barras pretas — a arte de
    // imagem não tem uma "cor de moldura" configurável para as barras,
    // então usa preto, igual a `_imageFramedGraph`.
    canvas.drawRect(areaRect, Paint()..color = Colors.black);
    canvas.drawImageRect(
      image,
      fullImageRect,
      _containDstRect(image.width.toDouble(), image.height.toDouble(), areaRect),
      paint,
    );
  }

  await _drawArtwork(canvas, size, asset);

  final picture = recorder.endRecording();
  try {
    final composed = await picture.toImage(canvasWidth, canvasHeight);
    try {
      final bytes = await composed.toByteData(format: ui.ImageByteFormat.png);
      return bytes!.buffer.asUint8List();
    } finally {
      composed.dispose();
    }
  } finally {
    picture.dispose();
  }
}

/// Tamanho do canvas de uma moldura de imagem: [ImageFrameResolutionMode.nativeMax]
/// usa a resolução original da arte; [ImageFrameResolutionMode.matchAjustar]
/// (rotulado como "Da foto" nesta tela, já que não há uma aba "Ajustar" de
/// resolução) usa o maior lado da própria foto escolhida como base,
/// mantendo a proporção nativa da arte.
(int, int) _imageFrameCanvasDimensions(
  PhotoInfo photo,
  ImageFrameAsset asset,
  ImageFrameResolutionMode mode,
) {
  if (mode == ImageFrameResolutionMode.nativeMax) {
    final width = asset.nativeReferenceWidth;
    final height = (width / asset.nativeAspectRatio).round();
    return (width, height);
  }

  final base = math.max(photo.width, photo.height).toDouble();
  if (asset.nativeAspectRatio >= 1) {
    return (base.round(), (base / asset.nativeAspectRatio).round());
  }
  return ((base * asset.nativeAspectRatio).round(), base.round());
}

/// Desenha a arte de uma moldura de imagem ocupando o canvas inteiro —
/// mesmos três formatos de [ImageFrameSource] que
/// `EditorPage._imageFrameArtwork` sabe exibir na prévia.
Future<void> _drawArtwork(Canvas canvas, Size size, ImageFrameAsset asset) async {
  switch (asset.source) {
    case ImageFrameSource.bundledSvg:
      final loader = SvgAssetLoader(asset.svgAssetPath!);
      await _drawPicture(canvas, size, vg.loadPicture(loader, null));
      break;
    case ImageFrameSource.importedSvg:
      final loader = SvgFileLoader(File(asset.imageFilePath!));
      await _drawPicture(canvas, size, vg.loadPicture(loader, null));
      break;
    case ImageFrameSource.importedImage:
      final artImage = await _decodeImageFile(asset.imageFilePath!);
      try {
        canvas.drawImageRect(
          artImage,
          Rect.fromLTWH(0, 0, artImage.width.toDouble(), artImage.height.toDouble()),
          Offset.zero & size,
          Paint()..filterQuality = FilterQuality.high,
        );
      } finally {
        artImage.dispose();
      }
      break;
  }
}

/// Espera o `Picture` vetorial carregar e desenha escalado para preencher
/// [size] — mesma técnica de `rasterizeSvgAsset`/`rasterizeSvgFile`
/// (`frame_painter.dart`), mas desenhando direto no canvas em composição em
/// vez de rasterizar para um PNG à parte. Recebe o `Future<PictureInfo>` já
/// iniciado (em vez do `BytesLoader`) para não precisar nomear esse tipo,
/// que o `flutter_svg` não reexporta.
Future<void> _drawPicture(
  Canvas canvas,
  Size size,
  Future<PictureInfo> pictureInfoFuture,
) async {
  final pictureInfo = await pictureInfoFuture;
  try {
    canvas.save();
    canvas.scale(
      size.width / pictureInfo.size.width,
      size.height / pictureInfo.size.height,
    );
    canvas.drawPicture(pictureInfo.picture);
    canvas.restore();
  } finally {
    pictureInfo.picture.dispose();
  }
}

Future<ui.Image> _decodeImageFile(String path) async {
  final bytes = await File(path).readAsBytes();
  final codec = await ui.instantiateImageCodec(bytes);
  final frame = await codec.getNextFrame();
  return frame.image;
}

/// Retângulo de origem que, desenhado no destino `dstW`×`dstH`, cobre todo
/// o destino recortando o excedente do maior eixo — o "cover" do
/// `BoxFit.cover`, feito manualmente porque [Canvas.drawImageRect] não tem
/// um modo de ajuste embutido.
Rect _coverSrcRect(double srcW, double srcH, double dstW, double dstH) {
  final srcAspect = srcW / srcH;
  final dstAspect = dstW / dstH;
  if (srcAspect > dstAspect) {
    final cropWidth = srcH * dstAspect;
    return Rect.fromLTWH((srcW - cropWidth) / 2, 0, cropWidth, srcH);
  }
  final cropHeight = srcW / dstAspect;
  return Rect.fromLTWH(0, (srcH - cropHeight) / 2, srcW, cropHeight);
}

/// Retângulo de destino, centralizado dentro de [dst], que mostra a imagem
/// inteira sem distorcer — o "contain" do `BoxFit.contain`.
Rect _containDstRect(double srcW, double srcH, Rect dst) {
  final srcAspect = srcW / srcH;
  final dstAspect = dst.width / dst.height;
  final double w, h;
  if (srcAspect > dstAspect) {
    w = dst.width;
    h = w / srcAspect;
  } else {
    h = dst.height;
    w = h * srcAspect;
  }
  return Rect.fromLTWH(
    dst.left + (dst.width - w) / 2,
    dst.top + (dst.height - h) / 2,
    w,
    h,
  );
}
