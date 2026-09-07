import 'dart:ui' as ui;

import 'package:flutter/material.dart'
    show Canvas, Color, ColorFilter, Offset, Paint, PictureRecorder, Rect, Size;
import 'package:flutter_test/flutter_test.dart';
import 'package:video_to_gif/models/collage_cell.dart';

/// Desenha um retângulo de cor conhecida com [filter] aplicado e devolve o
/// pixel resultante (R,G,B,A) — evita depender de `ColorFilter` ter
/// `operator==` por valor (não documentado com certeza), verificando o
/// efeito real do filtro igual a `frame_painter_test.dart` já faz para
/// `FramePainter.rasterize`.
Future<List<int>> _renderPixel(ColorFilter filter) async {
  const side = 2;
  final recorder = PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.drawRect(
    const Rect.fromLTWH(0, 0, 2, 2),
    Paint()
      ..color = const Color.fromARGB(255, 128, 64, 32)
      ..colorFilter = filter,
  );
  final picture = recorder.endRecording();
  final image = await picture.toImage(side, side);
  try {
    final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    return [data!.getUint8(0), data.getUint8(1), data.getUint8(2), data.getUint8(3)];
  } finally {
    image.dispose();
    picture.dispose();
  }
}

void main() {
  group('coverSrcRect', () {
    test('foto mais larga que a célula: recorta os lados, usa a altura toda', () {
      const cell = CollageCellSettings(photoWidth: 1000, photoHeight: 500);
      final rect = cell.coverSrcRect(const Size(200, 200));
      expect(rect.left, closeTo(250, 0.01));
      expect(rect.top, closeTo(0, 0.01));
      expect(rect.width, closeTo(500, 0.01));
      expect(rect.height, closeTo(500, 0.01));
    });

    test('zoom > 1 permite deslocar sem nunca sair dos limites da foto', () {
      const cell = CollageCellSettings(
        photoWidth: 1000,
        photoHeight: 500,
        zoom: 2,
        offsetX: 1,
        offsetY: 1,
      );
      final rect = cell.coverSrcRect(const Size(200, 200));
      expect(rect.left, greaterThanOrEqualTo(0));
      expect(rect.top, greaterThanOrEqualTo(0));
      expect(rect.right, lessThanOrEqualTo(1000.001));
      expect(rect.bottom, lessThanOrEqualTo(500.001));
    });

    test('nunca deixa buraco: recorte sempre cabe dentro da foto em qualquer offset/zoom', () {
      const cell = CollageCellSettings(photoWidth: 800, photoHeight: 600);
      for (final zoom in [1.0, 1.5, 2.0, 3.0, 4.0]) {
        for (final offset in [-1.0, -0.5, 0.0, 0.5, 1.0]) {
          final rect = cell
              .copyWith(zoom: zoom, offsetX: offset, offsetY: offset)
              .coverSrcRect(const Size(150, 100));
          expect(rect.left, greaterThanOrEqualTo(-0.01));
          expect(rect.top, greaterThanOrEqualTo(-0.01));
          expect(rect.right, lessThanOrEqualTo(800.01));
          expect(rect.bottom, lessThanOrEqualTo(600.01));
        }
      }
    });

    test('sem foto devolve Rect.zero', () {
      const cell = CollageCellSettings();
      expect(cell.coverSrcRect(const Size(100, 100)), Rect.zero);
    });
  });

  group('offsetDeltaForDrag', () {
    test('arrastar para a direita revela mais do lado esquerdo da foto (manipulação direta)', () {
      const cell = CollageCellSettings(photoWidth: 1000, photoHeight: 500, zoom: 2);
      final delta = cell.offsetDeltaForDrag(const Offset(50, 0), const Size(200, 200));
      // offsetX deveria DIMINUIR (a janela de recorte se move para a
      // esquerda), fazendo a foto parecer seguir o dedo para a direita.
      expect(delta.dx, lessThan(0));
    });

    test('sem folga no eixo (zoom mínimo, lado que já cobre a célula inteira) não desloca', () {
      const cell = CollageCellSettings(photoWidth: 1000, photoHeight: 500);
      final delta = cell.offsetDeltaForDrag(const Offset(0, 50), const Size(200, 200));
      expect(delta.dy, 0);
    });
  });

  group('rotação e espelhamento', () {
    test('girar 90° quatro vezes volta ao começo', () {
      var rotation = CellRotation.none;
      for (var i = 0; i < 4; i++) {
        rotation = rotation.next;
      }
      expect(rotation, CellRotation.none);
    });

    test('aspectRatio troca largura/altura só nos giros de 90°/270°', () {
      const cell = CollageCellSettings(photoWidth: 1000, photoHeight: 500);
      expect(cell.aspectRatio, closeTo(2.0, 0.001));
      expect(cell.copyWith(rotation: CellRotation.quarter).aspectRatio, closeTo(0.5, 0.001));
      expect(cell.copyWith(rotation: CellRotation.half).aspectRatio, closeTo(2.0, 0.001));
    });
  });

  group('ajustes de cor', () {
    test('brilho/contraste/saturação neutros não alteram a cor', () async {
      final filter = buildAdjustmentColorFilter(brightness: 0, contrast: 0, saturation: 0);
      final pixel = await _renderPixel(filter);
      expect(pixel, [128, 64, 32, 255]);
    });

    test('brilho positivo clareia a cor', () async {
      final filter = buildAdjustmentColorFilter(brightness: 0.5, contrast: 0, saturation: 0);
      final pixel = await _renderPixel(filter);
      expect(pixel[0], greaterThan(128));
      expect(pixel[1], greaterThan(64));
      expect(pixel[2], greaterThan(32));
    });

    test('saturação mínima (-1) produz cinza (R=G=B)', () async {
      final filter = buildAdjustmentColorFilter(brightness: 0, contrast: 0, saturation: -1);
      final pixel = await _renderPixel(filter);
      expect(pixel[0], pixel[1]);
      expect(pixel[1], pixel[2]);
    });
  });

  group('resetFraming', () {
    test('mantém foto e ajustes de cor, reseta enquadramento', () {
      const cell = CollageCellSettings(
        photoPath: '/tmp/foo.jpg',
        photoWidth: 100,
        photoHeight: 100,
        offsetX: 0.5,
        offsetY: -0.5,
        zoom: 2,
        rotation: CellRotation.quarter,
        flipHorizontal: true,
        brightness: 0.3,
      );
      final reset = cell.resetFraming();
      expect(reset.photoPath, cell.photoPath);
      expect(reset.brightness, cell.brightness);
      expect(reset.offsetX, 0);
      expect(reset.offsetY, 0);
      expect(reset.zoom, CollageCellSettings.minZoom);
      expect(reset.rotation, CellRotation.none);
      expect(reset.flipHorizontal, isFalse);
    });
  });
}
