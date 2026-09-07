import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart' show Canvas, Color, Paint, PictureRecorder, Rect;
import 'package:flutter_test/flutter_test.dart';
import 'package:video_to_gif/models/collage_background.dart';
import 'package:video_to_gif/models/collage_cell.dart';
import 'package:video_to_gif/models/collage_layout.dart';
import 'package:video_to_gif/models/collage_settings.dart';
import 'package:video_to_gif/services/collage_compositor.dart';

/// Grava um PNG sólido de [width]x[height] na cor [color] em [path] — usado
/// para ter fotos "de verdade" em disco para o compositor decodificar, sem
/// depender de nenhum asset do repositório.
Future<void> _writeSolidPng(String path, int width, int height, Color color) async {
  final recorder = PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.drawRect(
    Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
    Paint()..color = color,
  );
  final picture = recorder.endRecording();
  final image = await picture.toImage(width, height);
  try {
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    await File(path).writeAsBytes(bytes!.buffer.asUint8List());
  } finally {
    image.dispose();
    picture.dispose();
  }
}

/// Lê o pixel (R,G,B,A) em (x,y) de um PNG já em memória, decodificando com
/// `dart:ui` — mesma técnica de `frame_painter_test.dart`.
Future<List<int>> _decodePixel(Uint8List pngBytes, int width, int x, int y) async {
  final codec = await ui.instantiateImageCodec(pngBytes);
  final frame = await codec.getNextFrame();
  try {
    final data = await frame.image.toByteData(format: ui.ImageByteFormat.rawRgba);
    final offset = (y * width + x) * 4;
    return [
      data!.getUint8(offset),
      data.getUint8(offset + 1),
      data.getUint8(offset + 2),
      data.getUint8(offset + 3),
    ];
  } finally {
    frame.image.dispose();
    codec.dispose();
  }
}

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('collage_compositor_test');
  });

  tearDown(() async {
    if (await tempDir.exists()) await tempDir.delete(recursive: true);
  });

  test('PNG de saída tem exatamente a largura pedida e a altura pela proporção', () async {
    final photoPath = '${tempDir.path}/foto.png';
    await _writeSolidPng(photoPath, 100, 100, const Color(0xFFFF0000));

    final settings = CollageSettings(
      layout: CollageLayout.row(1),
      aspectRatio: 2.0,
      cells: [CollageCellSettings(photoPath: photoPath, photoWidth: 100, photoHeight: 100)],
    );

    final bytes = await composeCollage(settings: settings, outputWidth: 300);
    final codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    try {
      expect(frame.image.width, 300);
      expect(frame.image.height, 150);
    } finally {
      frame.image.dispose();
      codec.dispose();
    }
  });

  test('duas fotos lado a lado com fundo sólido: pixels batem com cada foto e o fundo', () async {
    final redPath = '${tempDir.path}/vermelho.png';
    final bluePath = '${tempDir.path}/azul.png';
    await _writeSolidPng(redPath, 50, 50, const Color(0xFFFF0000));
    await _writeSolidPng(bluePath, 50, 50, const Color(0xFF0000FF));

    final settings = CollageSettings(
      layout: CollageLayout.row(2),
      aspectRatio: 2.0,
      marginRatio: 0.1,
      background: const CollageBackground(
        mode: CollageBackgroundMode.color,
        color: Color(0xFF00FF00),
      ),
      cells: [
        CollageCellSettings(photoPath: redPath, photoWidth: 50, photoHeight: 50),
        CollageCellSettings(photoPath: bluePath, photoWidth: 50, photoHeight: 50),
      ],
    );

    const outputWidth = 200;
    final bytes = await composeCollage(settings: settings, outputWidth: outputWidth);

    // canvas 200x100 (aspectRatio 2.0), margem = shortestSide(100)*0.1 = 10.
    // célula 0: x em [10,95], y em [10,90] — amostra bem no meio dela.
    final leftPixel = await _decodePixel(bytes, outputWidth, 50, 50);
    expect(leftPixel[0], greaterThan(200)); // R alto
    expect(leftPixel[2], lessThan(50)); // B baixo

    // célula 1: x em [105,190], y em [10,90].
    final rightPixel = await _decodePixel(bytes, outputWidth, 150, 50);
    expect(rightPixel[2], greaterThan(200)); // B alto (foto azul)
    expect(rightPixel[0], lessThan(50)); // R baixo

    // Canto (2,2): fora das duas células, dentro da margem — mostra o fundo.
    final cornerPixel = await _decodePixel(bytes, outputWidth, 2, 2);
    expect(cornerPixel[1], greaterThan(200)); // G alto (fundo verde)
  });
}
