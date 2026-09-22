import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:video_to_gif/services/inpaint_patchmatch.dart';

/// Imagem RGBA opaca gerada por uma função de cor — o jeito mais direto de
/// montar um caso com "gabarito": o original é conhecido, então dá para medir
/// o quanto o preenchimento errou.
Uint8List _image(
  int width,
  int height,
  List<int> Function(int x, int y) color,
) {
  final rgba = Uint8List(width * height * 4);
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      final i = (y * width + x) * 4;
      final c = color(x, y);
      rgba[i] = c[0];
      rgba[i + 1] = c[1];
      rgba[i + 2] = c[2];
      rgba[i + 3] = 255;
    }
  }
  return rgba;
}

Uint8List _rectMask(int width, int height, int x0, int y0, int w, int h) {
  final mask = Uint8List(width * height);
  for (var y = y0; y < y0 + h; y++) {
    for (var x = x0; x < x0 + w; x++) {
      mask[y * width + x] = 255;
    }
  }
  return mask;
}

/// Erro médio absoluto por canal dentro da máscara, entre o resultado e o
/// original. Escala 0-255.
double _maskedError(Uint8List result, Uint8List truth, Uint8List mask) {
  var sum = 0.0;
  var count = 0;
  for (var i = 0; i < mask.length; i++) {
    if (mask[i] == 0) continue;
    for (var c = 0; c < 3; c++) {
      sum += (result[i * 4 + c] - truth[i * 4 + c]).abs();
    }
    count += 3;
  }
  return count == 0 ? 0 : sum / count;
}

void main() {
  group('inpaintPatchMatch', () {
    test('cor chapada volta a ser a mesma cor', () {
      const w = 96, h = 96;
      final truth = _image(w, h, (x, y) => const [40, 120, 200]);
      final mask = _rectMask(w, h, 36, 36, 24, 24);

      final result = inpaintPatchMatch(
        rgba: truth,
        mask: mask,
        width: w,
        height: h,
      );

      expect(_maskedError(result, truth, mask), lessThan(2));
    });

    test('textura listrada é reconstruída, não borrada', () {
      const w = 128, h = 128;
      // Listras verticais de 8px: um caso que a difusão pura resolveria com
      // um borrão cinza, e que só a síntese de textura acerta.
      final truth = _image(
        w,
        h,
        (x, y) => (x ~/ 8).isEven ? const [230, 230, 230] : const [30, 30, 30],
      );
      final mask = _rectMask(w, h, 48, 48, 32, 32);

      final result = inpaintPatchMatch(
        rgba: truth,
        mask: mask,
        width: w,
        height: h,
      );

      // O gabarito é exato aqui (a listra continua), então o erro tem que
      // ficar bem abaixo do que um borrão daria: a média entre 30 e 230 erra
      // ~100 por canal.
      expect(_maskedError(result, truth, mask), lessThan(25));
    });

    test('a divisa entre duas regiões não vaza de um lado para o outro', () {
      const w = 128, h = 128;
      // Metade de cima vermelha, metade de baixo azul. O buraco fica em cima
      // da divisa: cada pixel preenchido tem que sair da cor do seu lado.
      final truth = _image(
        w,
        h,
        (x, y) => y < 64 ? const [200, 40, 40] : const [40, 40, 200],
      );
      final mask = _rectMask(w, h, 40, 44, 40, 40);

      final result = inpaintPatchMatch(
        rgba: truth,
        mask: mask,
        width: w,
        height: h,
      );

      // Longe da divisa o resultado tem que ser inequívoco; a linha exata
      // pode oscilar um pixel ou dois, então a checagem pula uma faixa.
      for (var y = 44; y < 84; y++) {
        if ((y - 64).abs() <= 4) continue;
        for (var x = 40; x < 80; x++) {
          final i = (y * w + x) * 4;
          final red = result[i];
          final blue = result[i + 2];
          if (y < 64) {
            expect(red, greaterThan(blue), reason: 'vermelho em ($x, $y)');
          } else {
            expect(blue, greaterThan(red), reason: 'azul em ($x, $y)');
          }
        }
      }
    });

    test('a mesma semente dá o mesmo resultado; outra semente, outro', () {
      const w = 96, h = 96;
      final random = math.Random(7);
      final truth = _image(
        w,
        h,
        (x, y) => [random.nextInt(256), random.nextInt(256), 128],
      );
      final mask = _rectMask(w, h, 36, 36, 20, 20);

      Uint8List run(int seed) => inpaintPatchMatch(
        rgba: truth,
        mask: mask,
        width: w,
        height: h,
        seed: seed,
      );

      expect(run(1), equals(run(1)));
      // "Tentar de novo" só faz sentido se a semente realmente muda a saída.
      expect(run(1), isNot(equals(run(2))));
    });

    test('nada fora da máscara é tocado, alfa incluso', () {
      const w = 64, h = 64;
      final original = _image(w, h, (x, y) => [x * 4 % 256, y * 4 % 256, 90]);
      // Um alfa não-opaco para conferir que o canal passa intacto.
      for (var i = 3; i < original.length; i += 4) {
        original[i] = 200;
      }
      final mask = _rectMask(w, h, 24, 24, 16, 16);

      final result = inpaintPatchMatch(
        rgba: original,
        mask: mask,
        width: w,
        height: h,
      );

      for (var i = 0; i < w * h; i++) {
        expect(result[i * 4 + 3], 200, reason: 'alfa do pixel $i');
        if (mask[i] != 0) continue;
        for (var c = 0; c < 3; c++) {
          expect(result[i * 4 + c], original[i * 4 + c], reason: 'pixel $i');
        }
      }
    });

    test('máscara vazia devolve a imagem intacta', () {
      const w = 32, h = 32;
      final original = _image(w, h, (x, y) => [x * 8 % 256, 10, 10]);

      final result = inpaintPatchMatch(
        rgba: original,
        mask: Uint8List(w * h),
        width: w,
        height: h,
      );

      expect(result, equals(original));
    });

    test('um buraco encostado na borda não estoura índice', () {
      const w = 64, h = 64;
      final original = _image(w, h, (x, y) => [120, 120, 120]);
      final mask = _rectMask(w, h, 0, 0, 12, 12);

      final result = inpaintPatchMatch(
        rgba: original,
        mask: mask,
        width: w,
        height: h,
      );

      expect(_maskedError(result, original, mask), lessThan(2));
    });

    test('cancelar no meio devolve o que já havia', () {
      const w = 96, h = 96;
      final original = _image(w, h, (x, y) => [60, 160, 60]);
      final mask = _rectMask(w, h, 36, 36, 24, 24);

      var calls = 0;
      final result = inpaintPatchMatch(
        rgba: original,
        mask: mask,
        width: w,
        height: h,
        isCancelled: () => ++calls > 2,
      );

      expect(result.length, original.length);
    });

    test('o progresso vai de 0 a 1 sem voltar atrás', () {
      const w = 96, h = 96;
      final original = _image(w, h, (x, y) => [60, 60, 160]);
      final mask = _rectMask(w, h, 36, 36, 24, 24);

      final seen = <double>[];
      inpaintPatchMatch(
        rgba: original,
        mask: mask,
        width: w,
        height: h,
        onProgress: seen.add,
      );

      expect(seen, isNotEmpty);
      expect(seen.last, closeTo(1, 1e-9));
      for (var i = 1; i < seen.length; i++) {
        expect(seen[i], greaterThan(seen[i - 1]));
      }
    });

    test('entrada malformada é recusada em vez de corromper memória', () {
      expect(
        () => inpaintPatchMatch(
          rgba: Uint8List(10),
          mask: Uint8List(4),
          width: 2,
          height: 2,
        ),
        throwsArgumentError,
      );
      expect(
        () => inpaintPatchMatch(
          rgba: Uint8List(16),
          mask: Uint8List(3),
          width: 2,
          height: 2,
        ),
        throwsArgumentError,
      );
      expect(
        () => inpaintPatchMatch(
          rgba: Uint8List(16),
          mask: Uint8List(4),
          width: 2,
          height: 2,
          patchSize: 6,
        ),
        throwsArgumentError,
      );
    });
  });
}
