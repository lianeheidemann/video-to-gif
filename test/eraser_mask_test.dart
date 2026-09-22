import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:video_to_gif/features/photo/models/eraser_mask.dart';

/// Rasteriza uma máscara como o serviço faz, para conferir que traço somando
/// e traço tirando produzem de fato os pixels certos — a prévia e o algoritmo
/// saem os dois de [paintEraserMask], então é este comportamento que os dois
/// herdam.
///
/// Fica num `test` comum, não num `testWidgets`: `Picture.toImage` só resolve
/// no tempo real, e no tempo falso do `testWidgets` o `await` ficaria
/// pendurado até o teste estourar. É a mesma razão pela qual
/// `photo_crop_page_test` rasteriza a foto de apoio no `setUp`.
Future<Uint8List> _rasterise(EraserMask mask, int size) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  final bounds = Rect.fromLTWH(0, 0, size.toDouble(), size.toDouble());
  canvas.saveLayer(bounds, Paint());
  paintEraserMask(
    canvas,
    mask,
    addColor: const Color(0xFFFFFFFF),
    subtractColor: const Color(0x00000000),
    subtractBlendMode: BlendMode.clear,
  );
  canvas.restore();
  final picture = recorder.endRecording();
  final image = await picture.toImage(size, size);
  try {
    final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    return data!.buffer.asUint8List();
  } finally {
    image.dispose();
    picture.dispose();
  }
}

int _alphaAt(Uint8List rgba, int size, int x, int y) =>
    rgba[(y * size + x) * 4 + 3];

void main() {
  // Rasterizar precisa da engine de pé, e é o binding de teste que a levanta.
  TestWidgetsFlutterBinding.ensureInitialized();

  group('EraserMask', () {
    test('nasce vazia e continua vazia só com traços que tiram', () {
      expect(EraserMask.empty.isEmpty, isTrue);

      final onlySubtract = EraserMask.empty.add(
        const EraserStroke(points: [Offset(10, 10)], radius: 5, subtract: true),
      );
      // Tirar de nada não marca nada — e o botão "Apagar" não pode habilitar.
      expect(onlySubtract.isEmpty, isTrue);

      expect(
        onlySubtract
            .add(const EraserStroke(points: [Offset(20, 20)], radius: 5))
            .isEmpty,
        isFalse,
      );
    });

    test('removeLast tira só o último traço', () {
      final mask = EraserMask.empty
          .add(const EraserStroke(points: [Offset(1, 1)], radius: 2))
          .add(const EraserStroke(points: [Offset(9, 9)], radius: 2));

      expect(mask.strokes, hasLength(2));
      expect(
        mask.removeLast().strokes.single.points.single,
        const Offset(1, 1),
      );
      expect(EraserMask.empty.removeLast().strokes, isEmpty);
    });

    test('a caixa do pincel cresce com a espessura', () {
      final mask = EraserMask.empty.add(
        const EraserStroke(points: [Offset(50, 50)], radius: 10),
      );

      expect(mask.boundsIn(200, 200), const Rect.fromLTRB(40, 40, 60, 60));
    });

    test('a caixa ignora o que tira e é cortada nos limites da foto', () {
      final mask = EraserMask.empty
          .add(const EraserStroke(points: [Offset(5, 5)], radius: 20))
          .add(
            // Bem longe e subtrativo: não pode aumentar a janela de contexto,
            // porque tirar nunca aumenta a área a preencher.
            const EraserStroke(
              points: [Offset(180, 180)],
              radius: 10,
              subtract: true,
            ),
          );

      // -15 vira 0: a caixa não passa da foto.
      expect(mask.boundsIn(100, 100), const Rect.fromLTRB(0, 0, 25, 25));
    });

    test('seleção inteiramente fora da foto não tem caixa', () {
      final mask = EraserMask.empty.add(
        const EraserStroke(points: [Offset(-100, -100)], radius: 5),
      );

      expect(mask.boundsIn(50, 50), isNull);
    });
  });

  group('janela de contexto', () {
    test('margem mínima de 64px em volta de um buraco pequeno', () {
      final window = eraserContextWindow(
        const Rect.fromLTWH(100, 100, 10, 10),
        500,
        500,
      );

      expect(window, const Rect.fromLTRB(36, 36, 174, 174));
    });

    test('margem proporcional quando o buraco é grande', () {
      // 60% do maior lado: 200 * 0.6 = 120, bem acima do mínimo.
      final window = eraserContextWindow(
        const Rect.fromLTWH(200, 200, 200, 100),
        1000,
        1000,
      );

      expect(window, const Rect.fromLTRB(80, 80, 520, 420));
    });

    test('a janela nunca sai da foto', () {
      final window = eraserContextWindow(
        const Rect.fromLTWH(0, 0, 40, 40),
        100,
        100,
      );

      expect(window, const Rect.fromLTRB(0, 0, 100, 100));
    });
  });

  group('escala de trabalho', () {
    test('janela menor que o teto passa sem redução nenhuma', () {
      // É o caso que mantém apagadas pequenas em resolução nativa.
      expect(
        eraserWorkingScale(
          const Rect.fromLTWH(0, 0, 300, 200),
          EraserQuality.normal,
        ),
        1.0,
      );
    });

    test('janela maior que o teto encolhe pelo maior lado', () {
      expect(
        eraserWorkingScale(
          const Rect.fromLTWH(0, 0, 2048, 1024),
          EraserQuality.fast,
        ),
        closeTo(512 / 2048, 1e-9),
      );
    });

    test('nunca amplia: ampliar custaria tempo sem inventar detalhe', () {
      for (final quality in EraserQuality.values) {
        expect(
          eraserWorkingScale(const Rect.fromLTWH(0, 0, 10, 10), quality),
          lessThanOrEqualTo(1.0),
        );
      }
    });

    test('mais qualidade, janela maior', () {
      const window = Rect.fromLTWH(0, 0, 4000, 3000);
      expect(
        eraserWorkingScale(window, EraserQuality.fast),
        lessThan(eraserWorkingScale(window, EraserQuality.normal)),
      );
      expect(
        eraserWorkingScale(window, EraserQuality.normal),
        lessThan(eraserWorkingScale(window, EraserQuality.high)),
      );
    });
  });

  group('rasterização', () {
    const size = 64;

    test('o pincel marca onde passou e nada além', () async {
      final mask = EraserMask.empty.add(
        const EraserStroke(points: [Offset(16, 32), Offset(48, 32)], radius: 6),
      );

      final rgba = await _rasterise(mask, size);

      expect(_alphaAt(rgba, size, 32, 32), 255);
      expect(_alphaAt(rgba, size, 16, 32), 255);
      expect(_alphaAt(rgba, size, 48, 32), 255);
      // Fora do raio continua limpo.
      expect(_alphaAt(rgba, size, 32, 10), 0);
      expect(_alphaAt(rgba, size, 4, 32), 0);
    });

    test('a área fechada preenche o miolo', () async {
      final mask = EraserMask.empty.add(
        const EraserStroke(
          points: [
            Offset(10, 10),
            Offset(50, 10),
            Offset(50, 50),
            Offset(10, 50),
          ],
          closed: true,
        ),
      );

      final rgba = await _rasterise(mask, size);

      expect(_alphaAt(rgba, size, 30, 30), 255);
      expect(_alphaAt(rgba, size, 5, 5), 0);
    });

    test('o traço que tira abre buraco no que já estava', () async {
      final mask = EraserMask.empty
          .add(
            const EraserStroke(
              points: [
                Offset(8, 8),
                Offset(56, 8),
                Offset(56, 56),
                Offset(8, 56),
              ],
              closed: true,
            ),
          )
          .add(
            const EraserStroke(
              points: [Offset(32, 32)],
              radius: 8,
              subtract: true,
            ),
          );

      final rgba = await _rasterise(mask, size);

      // O centro foi retirado; a borda da área continua marcada.
      expect(_alphaAt(rgba, size, 32, 32), 0);
      expect(_alphaAt(rgba, size, 12, 12), 255);
    });
  });
}
