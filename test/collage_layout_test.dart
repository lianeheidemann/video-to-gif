import 'package:flutter/material.dart' show Size;
import 'package:flutter_test/flutter_test.dart';
import 'package:video_to_gif/models/collage_layout.dart';

void main() {
  test('linha de 3 fotos gera 3 células da mesma largura', () {
    final layout = CollageLayout.row(3);
    expect(layout.cellCount, 3);

    final rects = layout.cellRectsFor(const Size(300, 100), 0);
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
    final rects = layout.cellRectsFor(const Size(100, 200), 0);
    expect(rects.length, 2);
    expect(rects[0].top, closeTo(0, 0.001));
    expect(rects[1].top, closeTo(100, 0.001));
  });

  test('grade 2x2 tem 4 células', () {
    const layout = CollageLayout(kind: CollageLayoutKind.grid2x2);
    expect(layout.cellCount, 4);
    expect(layout.cellRectsFor(const Size(200, 200), 0).length, 4);
  });

  test('grade livre respeita colunas x linhas', () {
    final layout = CollageLayout.grid(3, 2);
    expect(layout.cellCount, 6);
  });

  test('margem reduz o tamanho das células e afasta da borda', () {
    final layout = CollageLayout.row(2);
    final rects = layout.cellRectsFor(const Size(300, 100), 0.1);
    // margem = shortestSide(100) * 0.1 = 10, aplicada nas bordas e entre células.
    expect(rects[0].left, closeTo(10, 0.001));
    expect(rects[0].width, closeTo((300 - 10 * 3) / 2, 0.001));
    expect(rects[1].left, closeTo(10 + rects[0].width + 10, 0.001));
  });

  test('células nunca se sobrepõem numa grade', () {
    const layout = CollageLayout(kind: CollageLayoutKind.grid3x3);
    final rects = layout.cellRectsFor(const Size(300, 300), 0.02);
    for (var i = 0; i < rects.length; i++) {
      for (var j = i + 1; j < rects.length; j++) {
        expect(rects[i].overlaps(rects[j]), isFalse);
      }
    }
  });
}
