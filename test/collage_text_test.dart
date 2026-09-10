import 'package:flutter_test/flutter_test.dart';
import 'package:video_to_gif/models/collage_text.dart';
import 'package:video_to_gif/models/default_colors.dart';

void main() {
  group('CollageTextItem.color/backgroundColor padrão', () {
    test('texto novo nasce com defaultTextColor e sem fundo', () {
      const item = CollageTextItem(
        id: 't1',
        text: 'oi',
        centerX: 0.5,
        centerY: 0.5,
        zIndex: 1,
      );
      expect(item.color, defaultTextColor);
      expect(item.hasBackground, isFalse);
    });

    test('ligar o fundo (fora daqui, na tela) grava defaultBackgroundColor '
        'opaco — copyWith preserva isso e o slider de opacidade só troca '
        'o alfa, sem mudar o RGB', () {
      const item = CollageTextItem(
        id: 't1',
        text: 'oi',
        centerX: 0.5,
        centerY: 0.5,
        zIndex: 1,
        backgroundColor: defaultBackgroundColor,
      );
      expect(item.backgroundColor!.a, 1.0);

      final translucido = item.copyWith(
        backgroundColor: item.backgroundColor!.withValues(alpha: 0.4),
      );
      expect(translucido.backgroundColor!.a, closeTo(0.4, 0.001));
      expect(translucido.backgroundColor!.r, item.backgroundColor!.r);
      expect(translucido.backgroundColor!.g, item.backgroundColor!.g);
      expect(translucido.backgroundColor!.b, item.backgroundColor!.b);
    });
  });

  group('CollageTextItem.fontFamily', () {
    test('começa nulo (fonte padrão do tema) por padrão', () {
      const item = CollageTextItem(
        id: 't1',
        text: 'oi',
        centerX: 0.5,
        centerY: 0.5,
        zIndex: 1,
      );
      expect(item.fontFamily, isNull);
    });

    test('copyWith(fontFamily: ...) troca a fonte', () {
      const item = CollageTextItem(
        id: 't1',
        text: 'oi',
        centerX: 0.5,
        centerY: 0.5,
        zIndex: 1,
      );
      final updated = item.copyWith(fontFamily: 'Bebas Neue');
      expect(updated.fontFamily, 'Bebas Neue');
    });

    test('clearFontFamily volta para a fonte padrão (null)', () {
      const item = CollageTextItem(
        id: 't1',
        text: 'oi',
        centerX: 0.5,
        centerY: 0.5,
        zIndex: 1,
        fontFamily: 'Poppins',
      );
      final cleared = item.copyWith(clearFontFamily: true);
      expect(cleared.fontFamily, isNull);
    });

    test('bundledCollageFonts começa com "Padrão" (fontFamily null)', () {
      expect(bundledCollageFonts.first.$1, isNull);
      expect(bundledCollageFonts.first.$2, 'Padrão');
      expect(bundledCollageFonts.length, 6);
    });
  });
}
