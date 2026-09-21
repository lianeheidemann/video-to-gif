import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart' hide Image;

import '../models/collage_text.dart';
import '../../features/collage/painting/collage_painter.dart';

/// Rasteriza só os textos (`CollageTextItem`) num PNG transparente do
/// tamanho exato [width]x[height] — usado pela exportação de vídeo/GIF, que
/// não pode desenhar texto com `dart:ui` direto (o FFmpeg produz os quadros)
/// e por isso compõe esta camada por cima via o filtro `overlay`, mesma
/// técnica que [FfmpegService] já usa para a arte de uma moldura de imagem
/// (ver `_prepareImageFrameArt`/`_imageFramedGraph`). A foto (que compõe com
/// `dart:ui` puro em `photo_frame_compositor.dart`) desenha os textos direto
/// no canvas final com [paintCollageTextItem], sem precisar desta camada à
/// parte.
Future<Uint8List> renderTextOverlayLayer(
  List<CollageTextItem> texts,
  int width,
  int height,
) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  final size = Size(width.toDouble(), height.toDouble());
  final sorted = [...texts]..sort((a, b) => a.zIndex.compareTo(b.zIndex));
  for (final item in sorted) {
    paintCollageTextItem(canvas, size, item);
  }
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
