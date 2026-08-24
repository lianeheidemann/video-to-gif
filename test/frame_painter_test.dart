import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:video_to_gif/models/frame_settings.dart';
import 'package:video_to_gif/ui/widgets/frame_painter.dart';

const _side = 64;
const _frameColor = ui.Color(0xFFC9A8FF);
const _backgroundColor = ui.Color(0xFF58C78C);

/// Rasteriza [settings] num quadrado de [_side] px e devolve os pixels já
/// convertidos para ARGB, na mesma ordem de [ui.Color.toARGB32].
Future<List<int>> _argbPixels(FrameSettings settings) async {
  final png = await FramePainter.rasterize(_side, _side, settings);
  final codec = await ui.instantiateImageCodec(png);
  final frame = await codec.getNextFrame();
  try {
    final data = await frame.image.toByteData(
      format: ui.ImageByteFormat.rawRgba,
    );
    return [
      for (var i = 0; i < _side * _side * 4; i += 4)
        (data!.getUint8(i + 3) << 24) |
            (data.getUint8(i) << 16) |
            (data.getUint8(i + 1) << 8) |
            data.getUint8(i + 2),
    ];
  } finally {
    frame.image.dispose();
    codec.dispose();
  }
}

int _at(List<int> pixels, int x, int y) => pixels[y * _side + x];

void main() {
  test('máscara arredondada mantém transparência e suaviza a borda', () async {
    const width = 64;
    const height = 64;
    final png = await rasterizeCornerMask(width, height, 24);
    final codec = await ui.instantiateImageCodec(png);
    final frame = await codec.getNextFrame();

    try {
      final data = await frame.image.toByteData(
        format: ui.ImageByteFormat.rawRgba,
      );
      int valueAt(int x, int y) => data!.getUint8((y * width + x) * 4);

      expect(valueAt(0, 0), lessThan(16));
      expect(valueAt(width ~/ 2, height ~/ 2), 255);

      final transition = <int>{
        for (var y = 0; y < 24; y++)
          for (var x = 0; x < 24; x++) valueAt(x, y),
      };
      expect(transition, contains(0));
      expect(transition, contains(255));
      expect(transition.any((value) => value > 0 && value < 255), isTrue);
    } finally {
      frame.image.dispose();
      codec.dispose();
    }
  });

  // A moldura é sempre a forma arredondada, na cor escolhida. O toggle
  // "Fundo transparente" decide só o que sobra nos 4 cantos fora dela.
  // No modo opaco, os cantos usam a cor de fundo escolhida sem cobrir a
  // moldura nem apagar o arredondamento.
  group('cantos fora da moldura', () {
    const rounded = FrameSettings(
      style: FrameStyle.thick,
      color: _frameColor,
      thicknessAtReference: 18,
      cornerRatio: FrameSettings.maxCornerRatio,
    );

    test('com fundo transparente, ficam sem nada', () async {
      final pixels = await _argbPixels(
        rounded.copyWith(transparentBackground: true),
      );

      expect(_at(pixels, 0, 0) >> 24, 0, reason: 'canto transparente');
      expect(_at(pixels, 32, 32), _frameColor.toARGB32());
    });

    test('sem fundo transparente, usam a cor de fundo escolhida', () async {
      final pixels = await _argbPixels(
        rounded.copyWith(
          transparentBackground: false,
          backgroundColor: _backgroundColor,
        ),
      );

      expect(
        _at(pixels, 0, 0),
        _backgroundColor.toARGB32(),
        reason: 'o canto deve usar a cor de fundo, não a cor da moldura',
      );
      expect(
        _at(pixels, 32, 32),
        _frameColor.toARGB32(),
        reason: 'dentro da forma arredondada continua a cor da moldura',
      );
    });
  });
}
