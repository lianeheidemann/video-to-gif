import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart'
    show Canvas, Color, ColorFilter, Offset, Paint, Rect, Size;
import 'package:flutter_test/flutter_test.dart';
import 'package:video_to_gif/models/collage_background.dart';
import 'package:video_to_gif/models/collage_cell.dart';
import 'package:video_to_gif/models/crop_rect.dart';

/// Desenha um retângulo de cor conhecida com [filter] aplicado e devolve o
/// pixel resultante (R,G,B,A) — evita depender de `ColorFilter` ter
/// `operator==` por valor (não documentado com certeza), verificando o
/// efeito real do filtro igual a `frame_painter_test.dart` já faz para
/// `FramePainter.rasterize`.
Future<List<int>> _renderPixel(ColorFilter filter) async {
  const side = 2;
  final recorder = ui.PictureRecorder();
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
    return [
      data!.getUint8(0),
      data.getUint8(1),
      data.getUint8(2),
      data.getUint8(3),
    ];
  } finally {
    image.dispose();
    picture.dispose();
  }
}

void main() {
  group('coverSrcRect', () {
    test(
      'foto mais larga que a célula: recorta os lados, usa a altura toda',
      () {
        const cell = CollageCellSettings(photoWidth: 1000, photoHeight: 500);
        final rect = cell.coverSrcRect(const Size(200, 200));
        expect(rect.left, closeTo(250, 0.01));
        expect(rect.top, closeTo(0, 0.01));
        expect(rect.width, closeTo(500, 0.01));
        expect(rect.height, closeTo(500, 0.01));
      },
    );

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

    test(
      'nunca deixa buraco: recorte sempre cabe dentro da foto em qualquer offset/zoom',
      () {
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
      },
    );

    test(
      'nunca deixa buraco também em rotação livre (não só múltiplos de 90°)',
      () {
        // O ponto central da rotação livre: girar por um ângulo qualquer
        // continua exigindo que o recorte de origem caiba dentro da foto —
        // `rotatedFootprint` precisa inflar a folga corretamente em QUALQUER
        // ângulo, não só nos 4 que o antigo `CellRotation` cobria.
        const cell = CollageCellSettings(photoWidth: 800, photoHeight: 600);
        for (final degrees in [15, 30, 45, 60, 75, 120, 200, 333]) {
          final rect = cell
              .copyWith(rotation: degrees * math.pi / 180)
              .coverSrcRect(const Size(150, 100));
          expect(rect, isNot(Rect.zero));
          expect(rect.left, greaterThanOrEqualTo(-0.01));
          expect(rect.top, greaterThanOrEqualTo(-0.01));
          expect(rect.right, lessThanOrEqualTo(800.01));
          expect(rect.bottom, lessThanOrEqualTo(600.01));
        }
      },
    );

    test('sem foto devolve Rect.zero', () {
      const cell = CollageCellSettings();
      expect(cell.coverSrcRect(const Size(100, 100)), Rect.zero);
    });

    test('com manualCrop, trata a sub-região como a "foto" inteira', () {
      // Foto de 1000x1000 com um recorte manual de 400x300 a partir de
      // (100,100) — coverSrcRect deve operar só dentro dessa sub-região (sem
      // zoom/offset, o resultado é a própria sub-região) e continuar
      // expressando o retângulo final em pixels da foto ORIGINAL.
      const cell = CollageCellSettings(
        photoWidth: 1000,
        photoHeight: 1000,
        manualCrop: CropRect(x: 100, y: 100, width: 400, height: 300),
      );
      final rect = cell.coverSrcRect(const Size(400, 300));
      expect(rect.left, closeTo(100, 0.01));
      expect(rect.top, closeTo(100, 0.01));
      expect(rect.width, closeTo(400, 0.01));
      expect(rect.height, closeTo(300, 0.01));
    });
  });

  group('offsetDeltaForDrag', () {
    test(
      'arrastar para a direita revela mais do lado esquerdo da foto (manipulação direta)',
      () {
        const cell = CollageCellSettings(
          photoWidth: 1000,
          photoHeight: 500,
          zoom: 2,
        );
        final delta = cell.offsetDeltaForDrag(
          const Offset(50, 0),
          const Size(200, 200),
        );
        // offsetX deveria DIMINUIR (a janela de recorte se move para a
        // esquerda), fazendo a foto parecer seguir o dedo para a direita.
        expect(delta.dx, lessThan(0));
      },
    );

    test(
      'sem folga no eixo (zoom mínimo, lado que já cobre a célula inteira) não desloca',
      () {
        const cell = CollageCellSettings(photoWidth: 1000, photoHeight: 500);
        final delta = cell.offsetDeltaForDrag(
          const Offset(0, 50),
          const Size(200, 200),
        );
        expect(delta.dy, 0);
      },
    );
  });

  group('rotação e espelhamento', () {
    test('girar 90° quatro vezes volta ao começo', () {
      var rotation = 0.0;
      for (var i = 0; i < 4; i++) {
        rotation += math.pi / 2;
      }
      // 4 * pi/2 == 2*pi: mesmo ângulo que 0°, mas não necessariamente o
      // mesmo double exato — a rotação é contínua agora, então comparamos
      // pelo cosseno/seno (periódicos), não pelo valor bruto.
      expect(math.cos(rotation), closeTo(math.cos(0), 0.0001));
      expect(math.sin(rotation), closeTo(math.sin(0), 0.0001));
    });

    test('aspectRatio troca largura/altura só nos giros de 90°/270°', () {
      const cell = CollageCellSettings(photoWidth: 1000, photoHeight: 500);
      expect(cell.aspectRatio, closeTo(2.0, 0.001));
      expect(
        cell.copyWith(rotation: math.pi / 2).aspectRatio,
        closeTo(0.5, 0.001),
      );
      expect(cell.copyWith(rotation: math.pi).aspectRatio, closeTo(2.0, 0.001));
    });

    test('aspectRatio em ângulo livre fica entre os dois extremos', () {
      const cell = CollageCellSettings(photoWidth: 1000, photoHeight: 500);
      final at45 = cell.copyWith(rotation: math.pi / 4).aspectRatio;
      expect(at45, greaterThan(0.5));
      expect(at45, lessThan(2.0));
    });
  });

  group('ajustes de cor', () {
    test('brilho/contraste/saturação neutros não alteram a cor', () async {
      final filter = buildAdjustmentColorFilter(
        brightness: 0,
        contrast: 0,
        saturation: 0,
      );
      final pixel = await _renderPixel(filter);
      expect(pixel, [128, 64, 32, 255]);
    });

    test('brilho positivo clareia a cor', () async {
      final filter = buildAdjustmentColorFilter(
        brightness: 0.5,
        contrast: 0,
        saturation: 0,
      );
      final pixel = await _renderPixel(filter);
      expect(pixel[0], greaterThan(128));
      expect(pixel[1], greaterThan(64));
      expect(pixel[2], greaterThan(32));
    });

    test('saturação mínima (-1) produz cinza (R=G=B)', () async {
      final filter = buildAdjustmentColorFilter(
        brightness: 0,
        contrast: 0,
        saturation: -1,
      );
      final pixel = await _renderPixel(filter);
      expect(pixel[0], pixel[1]);
      expect(pixel[1], pixel[2]);
    });

    test('todos os oito ajustes no zero não alteram a cor', () async {
      final filter = buildAdjustmentColorFilter(
        brightness: 0,
        exposure: 0,
        contrast: 0,
        highlights: 0,
        shadows: 0,
        saturation: 0,
        hue: 0,
        temperature: 0,
      );
      final pixel = await _renderPixel(filter);
      expect(pixel, [128, 64, 32, 255]);
    });

    test('exposição multiplica a luz (o preto continua preto)', () async {
      // Diferente do brilho, que soma: dobrando a exposição, cada canal
      // aproximadamente dobra em vez de ganhar um valor fixo.
      final filter = buildAdjustmentColorFilter(
        brightness: 0,
        exposure: 1,
        contrast: 0,
        saturation: 0,
      );
      final pixel = await _renderPixel(filter);
      expect(pixel[1], closeTo(128, 6)); // 64 * 2
      expect(pixel[2], closeTo(64, 6)); // 32 * 2
    });

    test('realces mexem mais no claro do que no escuro', () async {
      final filter = buildAdjustmentColorFilter(
        brightness: 0,
        contrast: 0,
        highlights: 1,
        saturation: 0,
      );
      final pixel = await _renderPixel(filter);
      final deltaClaro = pixel[0] - 128; // canal mais claro (R = 128)
      final deltaEscuro = pixel[2] - 32; // canal mais escuro (B = 32)
      expect(deltaClaro, greaterThan(deltaEscuro));
    });

    test('sombras levantam o escuro sem estourar o claro', () async {
      final filter = buildAdjustmentColorFilter(
        brightness: 0,
        contrast: 0,
        shadows: 1,
        saturation: 0,
      );
      final pixel = await _renderPixel(filter);
      final deltaEscuro = pixel[2] - 32;
      final deltaClaro = pixel[0] - 128;
      expect(deltaEscuro, greaterThan(0));
      expect(deltaEscuro, greaterThan(deltaClaro));
    });

    test('temperatura positiva esquenta (mais vermelho, menos azul)', () async {
      final filter = buildAdjustmentColorFilter(
        brightness: 0,
        contrast: 0,
        saturation: 0,
        temperature: 1,
      );
      final pixel = await _renderPixel(filter);
      expect(pixel[0], greaterThan(128));
      expect(pixel[2], lessThan(32));
      expect(pixel[1], 64); // o verde não entra na conta
    });

    test('matiz gira a cor mantendo a luminosidade parecida', () async {
      final filter = buildAdjustmentColorFilter(
        brightness: 0,
        contrast: 0,
        saturation: 0,
        hue: 0.5,
      );
      final pixel = await _renderPixel(filter);
      // A cor muda de verdade...
      expect(pixel[0], isNot(128));
      // ...mas a luma (Rec. 709) fica na mesma vizinhança.
      double luma(List<int> p) => 0.2126 * p[0] + 0.7152 * p[1] + 0.0722 * p[2];
      expect(luma(pixel), closeTo(luma([128, 64, 32, 255]), 25));
    });
  });

  group('hasColorAdjustments / withoutColorAdjustments', () {
    test('célula recém-criada não tem ajuste nenhum', () {
      expect(const CollageCellSettings().hasColorAdjustments, isFalse);
    });

    test('qualquer ajuste fora do zero conta', () {
      expect(const CollageCellSettings(hue: 0.2).hasColorAdjustments, isTrue);
      expect(
        const CollageCellSettings(temperature: -0.1).hasColorAdjustments,
        isTrue,
      );
    });

    test('redefinir zera só os ajustes de cor', () {
      const cell = CollageCellSettings(
        photoPath: '/tmp/a.jpg',
        zoom: 2,
        brightness: 0.4,
        exposure: -0.3,
        highlights: 0.5,
        hue: 0.2,
      );
      final limpa = cell.withoutColorAdjustments();
      expect(limpa.hasColorAdjustments, isFalse);
      expect(limpa.zoom, 2);
      expect(limpa.photoPath, '/tmp/a.jpg');
    });
  });

  group('resetFraming', () {
    test('mantém foto, recorte manual, cor e borda; reseta enquadramento', () {
      const crop = CropRect(x: 10, y: 10, width: 50, height: 50);
      const cell = CollageCellSettings(
        photoPath: '/tmp/foo.jpg',
        photoWidth: 100,
        photoHeight: 100,
        manualCrop: crop,
        offsetX: 0.5,
        offsetY: -0.5,
        zoom: 2,
        rotation: math.pi / 2,
        flipHorizontal: true,
        brightness: 0.3,
        borderThicknessAtReference: 6,
      );
      final reset = cell.resetFraming();
      expect(reset.photoPath, cell.photoPath);
      expect(reset.manualCrop, crop);
      expect(reset.brightness, cell.brightness);
      expect(reset.borderThicknessAtReference, cell.borderThicknessAtReference);
      expect(reset.offsetX, 0);
      expect(reset.offsetY, 0);
      expect(reset.zoom, CollageCellSettings.minZoom);
      expect(reset.rotation, 0.0);
      expect(reset.flipHorizontal, isFalse);
    });

    test('mantém o fundo próprio da foto', () {
      const cell = CollageCellSettings(
        photoPath: '/tmp/foo.jpg',
        rotation: 1.2,
        background: CollageBackground(
          mode: CollageBackgroundMode.color,
          color: Color(0xFF0000FF),
        ),
      );
      final reset = cell.resetFraming();
      expect(reset.rotation, 0.0);
      expect(reset.background.mode, CollageBackgroundMode.color);
      expect(reset.background.color, const Color(0xFF0000FF));
    });
  });

  group('fundo próprio da foto', () {
    test('é transparente por padrão', () {
      const cell = CollageCellSettings();
      expect(cell.background.mode, CollageBackgroundMode.transparent);
    });

    test('copyWith troca só o fundo, sem mexer no resto', () {
      const cell = CollageCellSettings(
        photoPath: '/tmp/foo.jpg',
        zoom: 2,
        fitMode: CollageCellFitMode.contain,
      );
      final withBackground = cell.copyWith(
        background: const CollageBackground(
          mode: CollageBackgroundMode.image,
          imagePath: '/tmp/fundo.png',
        ),
      );
      expect(withBackground.background.imagePath, '/tmp/fundo.png');
      expect(withBackground.zoom, 2);
      expect(withBackground.fitMode, CollageCellFitMode.contain);
      expect(withBackground.photoPath, '/tmp/foo.jpg');
    });
  });

  group('modo ajustar (contain)', () {
    test('zoom 1 mostra a foto inteira, sem cortar', () {
      const cell = CollageCellSettings(
        photoWidth: 1000,
        photoHeight: 500,
        fitMode: CollageCellFitMode.contain,
      );
      // Foto bem mais larga (2:1) que a célula quadrada: o "ajustar" clássico
      // bate exatamente na largura da célula e sobra espaço na altura.
      final display = cell.containDisplaySize(const Size(200, 200));
      expect(display.width, closeTo(200, 0.01));
      expect(display.height, closeTo(100, 0.01));
    });

    test('zoom acima de 1 amplia a partir do "ajustar" puro', () {
      const base = CollageCellSettings(
        photoWidth: 1000,
        photoHeight: 500,
        fitMode: CollageCellFitMode.contain,
      );
      final at1 = base.containDisplaySize(const Size(200, 200));
      final at2 = base
          .copyWith(zoom: 2)
          .containDisplaySize(const Size(200, 200));
      expect(at2.width, closeTo(at1.width * 2, 0.01));
      expect(at2.height, closeTo(at1.height * 2, 0.01));
    });

    test('sem foto, containDisplaySize é zero', () {
      const cell = CollageCellSettings(fitMode: CollageCellFitMode.contain);
      expect(cell.containDisplaySize(const Size(100, 100)), Size.zero);
    });

    test('containDisplayOffset move a foto mesmo no zoom mínimo, baseado no '
        'tamanho da célula', () {
      const cell = CollageCellSettings(
        photoWidth: 1000,
        photoHeight: 500,
        fitMode: CollageCellFitMode.contain,
        offsetX: 1.0,
        offsetY: -1.0,
      );
      // zoom == minZoom (o padrão): antes desta mudança o alcance zerava
      // exatamente aqui, travando a foto centralizada até ampliar.
      expect(cell.zoom, CollageCellSettings.minZoom);
      final offset = cell.containDisplayOffset(const Size(200, 200));
      expect(offset.dx, closeTo(100, 0.01));
      expect(offset.dy, closeTo(-100, 0.01));
    });

    test('containOffsetDeltaForDrag converte arrasto em incremento mesmo no '
        'zoom mínimo', () {
      const cell = CollageCellSettings(
        photoWidth: 1000,
        photoHeight: 500,
        fitMode: CollageCellFitMode.contain,
      );
      final delta = cell.containOffsetDeltaForDrag(
        const Offset(20, 0),
        const Size(200, 200),
      );
      expect(delta.dx, closeTo(0.2, 0.001));
      expect(delta.dy, 0);
    });
  });

  group('borda por foto', () {
    test('espessura escala proporcionalmente à largura da célula', () {
      const cell = CollageCellSettings(borderThicknessAtReference: 12);
      expect(
        cell.borderThicknessFor(CollageCellSettings.referenceWidth),
        closeTo(12, 0.001),
      );
      expect(
        cell.borderThicknessFor(CollageCellSettings.referenceWidth * 2),
        closeTo(24, 0.001),
      );
    });

    test('espessura zero por padrão (sem borda própria)', () {
      const cell = CollageCellSettings();
      expect(cell.borderThicknessFor(480), 0);
    });
  });
}
