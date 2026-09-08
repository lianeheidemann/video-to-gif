import 'package:flutter_test/flutter_test.dart';
import 'package:video_to_gif/models/collage_text.dart';

void main() {
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
