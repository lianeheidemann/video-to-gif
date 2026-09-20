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
      // O resto da lista vem de `assets/fonts` no `main()`, então aqui só
      // vale a primeira entrada — quantas fontes existem é assunto de
      // `bundled_assets_test.dart`.
      expect(bundledCollageFonts.first.$1, isNull);
      expect(bundledCollageFonts.first.$2, 'Padrão');
    });
  });

  group('CollageTextListOps', () {
    const a = CollageTextItem(
      id: 'a',
      text: 'a',
      centerX: 0.5,
      centerY: 0.5,
      zIndex: 3,
    );
    const b = CollageTextItem(
      id: 'b',
      text: 'b',
      centerX: 0.5,
      centerY: 0.5,
      zIndex: 7,
    );

    test('nextTextZIndex é 0 numa lista vazia, e um a mais que o maior '
        'zIndex quando há itens', () {
      expect(<CollageTextItem>[].nextTextZIndex, 0);
      expect([a, b].nextTextZIndex, 8);
    });

    test('minTextZIndex é 0 numa lista vazia, e um a menos que o menor '
        'zIndex quando há itens', () {
      expect(<CollageTextItem>[].minTextZIndex, 0);
      expect([a, b].minTextZIndex, 2);
    });

    test('findText acha pelo id, ou devolve null se não existir', () {
      expect([a, b].findText('a'), a);
      expect([a, b].findText('z'), isNull);
    });

    test('replacingText troca só o item com aquele id, preservando ordem', () {
      final updated = [a, b].replacingText('a', a.copyWith(text: 'A!'));
      expect(updated.map((t) => t.text), ['A!', 'b']);
    });

    test('removingText tira só o item com aquele id', () {
      final updated = [a, b].removingText('a');
      expect(updated.map((t) => t.id), ['b']);
    });
  });
}
