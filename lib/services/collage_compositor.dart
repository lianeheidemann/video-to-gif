import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../models/collage_background.dart';
import '../models/collage_settings.dart';
import '../models/collage_sticker.dart';
import '../models/collage_text.dart';
import '../ui/widgets/collage_painter.dart';

/// Compõe uma [CollageSettings] completa (células, fundo, borda, stickers e
/// textos) num PNG final, com `dart:ui`/[Canvas] puro — mesmo espírito de
/// `photo_frame_compositor.dart`, generalizado para N fotos e sobreposições.
/// [outputWidth] decide a resolução final; a altura é derivada de
/// [CollageSettings.aspectRatio].
Future<Uint8List> composeCollage({
  required CollageSettings settings,
  required int outputWidth,
}) async {
  final cellImages = await Future.wait(
    settings.cells.map<Future<ui.Image?>>(
      (cell) => cell.photoPath == null
          ? Future<ui.Image?>.value(null)
          : _tryDecodeImageFile(cell.photoPath!),
    ),
  );
  final backgroundImage =
      settings.background.mode == CollageBackgroundMode.image &&
          settings.background.imagePath != null
      ? await _tryDecodeImageFile(settings.background.imagePath!)
      : null;
  final cellBackgroundImages = await _decodeCellBackgrounds(settings);

  try {
    return await composeCollageFrame(
      settings: settings,
      outputWidth: outputWidth,
      cellImages: cellImages,
      backgroundImage: backgroundImage,
      cellBackgroundImages: cellBackgroundImages,
    );
  } finally {
    for (final image in cellImages) {
      image?.dispose();
    }
    for (final image in cellBackgroundImages.values) {
      image?.dispose();
    }
    backgroundImage?.dispose();
  }
}

/// Desenha UM quadro da montagem a partir de imagens **já decodificadas** —
/// o miolo de [composeCollage], separado para a exportação animada
/// (`collage_animation.dart`) poder trocar só as fotos das células a cada
/// quadro sem decodificar tudo de novo (e sem duplicar o desenho, que
/// continua sendo o mesmo `paintCollageBorder`/`paintCollageBackground`/
/// `paintCollageCell` da prévia). Nenhuma imagem recebida é liberada aqui:
/// quem decodificou é quem libera.
Future<Uint8List> composeCollageFrame({
  required CollageSettings settings,
  required int outputWidth,
  required List<ui.Image?> cellImages,
  ui.Image? backgroundImage,
  Map<String, ui.Image?> cellBackgroundImages = const {},
}) async {
  final width = outputWidth < 2 ? 2 : outputWidth;
  final height = (width / settings.aspectRatio).round().clamp(2, 1 << 20);
  final size = Size(width.toDouble(), height.toDouble());

  final geometry = CollageGeometry.of(size, settings);
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);

  canvas.save();
  canvas.clipRRect(geometry.outerClip);
  paintCollageBorder(canvas, size, settings);

  canvas.save();
  canvas.clipRRect(geometry.innerClip);
  paintCollageBackground(
    canvas,
    geometry.innerClip.outerRect,
    settings.background,
    backgroundImage: backgroundImage,
  );
  for (
    var i = 0;
    i < settings.cells.length && i < geometry.cellRects.length;
    i++
  ) {
    final cell = settings.cells[i];
    paintCollageCell(
      canvas,
      geometry.cellRects[i],
      cell,
      i < cellImages.length ? cellImages[i] : null,
      cellBackgroundImage: cellBackgroundImages[cell.background.imagePath],
    );
  }
  canvas.restore();

  await _paintOverlays(canvas, size, settings);
  canvas.restore();

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

/// Imagens de fundo próprias das fotos (`CollageCellSettings.background` no
/// modo imagem), indexadas pelo caminho do arquivo. Deduplicar por caminho
/// importa porque a aba "Fundo" aplica a escolha a todas as fotos de uma vez:
/// sem isso, a mesma imagem seria decodificada uma vez por célula.
Future<Map<String, ui.Image?>> _decodeCellBackgrounds(
  CollageSettings settings,
) async {
  final paths = <String>{
    for (final cell in settings.cells)
      if (cell.background.mode == CollageBackgroundMode.image &&
          cell.background.imagePath != null)
        cell.background.imagePath!,
  };
  final images = await Future.wait(paths.map(_tryDecodeImageFile));
  return {for (final (index, path) in paths.indexed) path: images[index]};
}

/// Desenha stickers e textos juntos, ordenados por `zIndex` (menor primeiro,
/// para os de maior valor ficarem por cima).
Future<void> _paintOverlays(
  Canvas canvas,
  Size size,
  CollageSettings settings,
) async {
  final overlays = <_Overlay>[
    for (final sticker in settings.stickers) _StickerOverlay(sticker),
    for (final text in settings.texts) _TextOverlay(text),
  ]..sort((a, b) => a.zIndex.compareTo(b.zIndex));

  for (final overlay in overlays) {
    await overlay.paint(canvas, size);
  }
}

abstract class _Overlay {
  int get zIndex;
  Future<void> paint(Canvas canvas, Size canvasSize);
}

class _StickerOverlay extends _Overlay {
  _StickerOverlay(this.sticker);

  final CollageSticker sticker;

  @override
  int get zIndex => sticker.zIndex;

  @override
  Future<void> paint(Canvas canvas, Size canvasSize) async {
    final refSize =
        canvasSize.shortestSide *
        CollageSticker.referenceSizeRatio *
        sticker.scale;
    final center = Offset(
      sticker.centerX * canvasSize.width,
      sticker.centerY * canvasSize.height,
    );

    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate(sticker.rotation);

    switch (sticker.source) {
      case CollageStickerSource.bundledSvg:
        await _paintVector(canvas, refSize, SvgAssetLoader(sticker.assetPath!));
      case CollageStickerSource.importedSvg:
        await _paintVector(
          canvas,
          refSize,
          SvgFileLoader(File(sticker.imageFilePath!)),
        );
      case CollageStickerSource.importedImage:
        await _paintRasterSticker(canvas, refSize, sticker.imageFilePath!);
    }
    canvas.restore();
  }

  Future<void> _paintVector(
    Canvas canvas,
    double refSize,
    BytesLoader loader,
  ) async {
    final PictureInfo pictureInfo;
    try {
      pictureInfo = await vg.loadPicture(loader, null);
    } catch (_) {
      // Arte apagada/ilegível: deixa esse sticker de fora em vez de derrubar a
      // exportação inteira (ver `_tryDecodeImageFile`).
      return;
    }
    try {
      final nativeSize = pictureInfo.size;
      if (nativeSize.width <= 0 || nativeSize.height <= 0) return;
      final aspect = nativeSize.width / nativeSize.height;
      final w = aspect >= 1 ? refSize : refSize * aspect;
      final h = aspect >= 1 ? refSize / aspect : refSize;
      canvas.save();
      canvas.translate(-w / 2, -h / 2);
      canvas.scale(w / nativeSize.width, h / nativeSize.height);
      canvas.drawPicture(pictureInfo.picture);
      canvas.restore();
    } finally {
      pictureInfo.picture.dispose();
    }
  }

  Future<void> _paintRasterSticker(
    Canvas canvas,
    double refSize,
    String path,
  ) async {
    final image = await _tryDecodeImageFile(path);
    if (image == null) return;
    try {
      final aspect = image.width / image.height;
      final w = aspect >= 1 ? refSize : refSize * aspect;
      final h = aspect >= 1 ? refSize / aspect : refSize;
      canvas.drawImageRect(
        image,
        Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
        Rect.fromCenter(center: Offset.zero, width: w, height: h),
        Paint()..filterQuality = FilterQuality.high,
      );
    } finally {
      image.dispose();
    }
  }
}

class _TextOverlay extends _Overlay {
  _TextOverlay(this.item);

  final CollageTextItem item;

  @override
  int get zIndex => item.zIndex;

  @override
  Future<void> paint(Canvas canvas, Size canvasSize) async {
    final fontSize = canvasSize.shortestSide * item.fontSizeRatio * item.scale;
    final center = Offset(
      item.centerX * canvasSize.width,
      item.centerY * canvasSize.height,
    );

    final painter = TextPainter(
      text: TextSpan(
        text: item.text,
        style: TextStyle(
          color: item.color,
          fontSize: fontSize,
          fontFamily: item.fontFamily,
          fontWeight: item.bold ? FontWeight.w700 : FontWeight.w400,
        ),
      ),
      textDirection: TextDirection.ltr,
      textAlign: TextAlign.center,
    )..layout();

    try {
      canvas.save();
      canvas.translate(center.dx, center.dy);
      canvas.rotate(item.rotation);

      // Caixa de fundo primeiro, texto por cima — o mesmo respiro e o mesmo
      // arredondamento que a prévia usa (ver `CollagePage._textArt`).
      final background = item.backgroundColor;
      if (background != null) {
        final (padH, padV) = CollageTextItem.backgroundPaddingFor(fontSize);
        paintCollageTextBackground(
          canvas,
          Rect.fromCenter(
            center: Offset.zero,
            width: painter.width + padH * 2,
            height: painter.height + padV * 2,
          ),
          background,
          item.backgroundCornerRatio,
        );
      }

      painter.paint(canvas, Offset(-painter.width / 2, -painter.height / 2));
      canvas.restore();
    } finally {
      painter.dispose();
    }
  }
}

/// Decodifica [path], devolvendo `null` (em vez de propagar) quando o arquivo
/// sumiu ou não é uma imagem legível. Uma foto/sticker/fundo que o usuário
/// apagou do aparelho depois de montar a colagem não pode derrubar a
/// exportação inteira: o resto da montagem ainda é exportável.
Future<ui.Image?> _tryDecodeImageFile(String path) async {
  try {
    return await _decodeImageFile(path);
  } catch (_) {
    return null;
  }
}

Future<ui.Image> _decodeImageFile(String path) async {
  final bytes = await File(path).readAsBytes();
  final codec = await ui.instantiateImageCodec(bytes);
  try {
    final frame = await codec.getNextFrame();
    return frame.image;
  } finally {
    codec.dispose();
  }
}
