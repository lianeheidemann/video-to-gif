import 'package:flutter/material.dart' show Rect, Size;
import 'package:flutter_test/flutter_test.dart';
import 'package:video_to_gif/models/collage_layout.dart';

/// [margin] vira as duas margens (externa/entre fotos) com o mesmo valor —
/// o comportamento equivalente ao antigo `marginRatio` único, para os testes
/// que não se importam com a diferença entre as duas.
List<Rect> _rectsFor(CollageLayout layout, Size size, double margin) =>
    layout.cellRectsFor(
      size,
      outerMarginRatio: margin,
      innerMarginRatio: margin,
    );

void main() {
  test('linha de 3 fotos gera 3 células da mesma largura', () {
    final layout = CollageLayout.row(3);
    expect(layout.cellCount, 3);

    final rects = _rectsFor(layout, const Size(300, 100), 0);
    expect(rects.length, 3);
    for (final rect in rects) {
      expect(rect.width, closeTo(100, 0.001));
      expect(rect.height, closeTo(100, 0.001));
    }
    expect(rects[0].left, closeTo(0, 0.001));
    expect(rects[1].left, closeTo(100, 0.001));
    expect(rects[2].left, closeTo(200, 0.001));
  });

  test('coluna de 2 fotos gera 2 células da mesma altura', () {
    final layout = CollageLayout.column(2);
    final rects = _rectsFor(layout, const Size(100, 200), 0);
    expect(rects.length, 2);
    expect(rects[0].top, closeTo(0, 0.001));
    expect(rects[1].top, closeTo(100, 0.001));
  });

  test('grade 2x2 tem 4 células', () {
    const layout = CollageLayout(kind: CollageLayoutKind.grid2x2);
    expect(layout.cellCount, 4);
    expect(_rectsFor(layout, const Size(200, 200), 0).length, 4);
  });

  test('grade livre respeita colunas x linhas', () {
    final layout = CollageLayout.grid(3, 2);
    expect(layout.cellCount, 6);
  });

  test('margem reduz o tamanho das células e afasta da borda', () {
    final layout = CollageLayout.row(2);
    final rects = _rectsFor(layout, const Size(300, 100), 0.1);
    // margem = shortestSide(100) * 0.1 = 10, aplicada nas bordas e entre células.
    expect(rects[0].left, closeTo(10, 0.001));
    expect(rects[0].width, closeTo((300 - 10 * 3) / 2, 0.001));
    expect(rects[1].left, closeTo(10 + rects[0].width + 10, 0.001));
  });

  test('células nunca se sobrepõem numa grade', () {
    const layout = CollageLayout(kind: CollageLayoutKind.grid3x3);
    final rects = _rectsFor(layout, const Size(300, 300), 0.02);
    for (var i = 0; i < rects.length; i++) {
      for (var j = i + 1; j < rects.length; j++) {
        expect(rects[i].overlaps(rects[j]), isFalse);
      }
    }
  });

  test(
    'margem externa e entre fotos são independentes uma da outra',
    () {
      final layout = CollageLayout.row(2);
      // Só margem externa: nada entre as duas células.
      final onlyOuter = layout.cellRectsFor(
        const Size(300, 100),
        outerMarginRatio: 0.1,
        innerMarginRatio: 0,
      );
      expect(onlyOuter[0].left, closeTo(10, 0.001));
      expect(onlyOuter[1].right, closeTo(290, 0.001));
      expect(onlyOuter[0].right, closeTo(onlyOuter[1].left, 0.001));

      // Só margem entre fotos: as células encostam nas bordas da montagem.
      final onlyInner = layout.cellRectsFor(
        const Size(300, 100),
        outerMarginRatio: 0,
        innerMarginRatio: 0.1,
      );
      expect(onlyInner[0].left, closeTo(0, 0.001));
      expect(onlyInner[1].right, closeTo(300, 0.001));
      expect(onlyInner[1].left, greaterThan(onlyInner[0].right));
    },
  );
}
