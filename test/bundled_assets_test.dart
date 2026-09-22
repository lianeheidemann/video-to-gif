import 'package:flutter_test/flutter_test.dart';
import 'package:video_to_gif/core/services/bundled_assets.dart';
import 'package:video_to_gif/core/services/bundled_font_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('nome a partir do arquivo', () {
    test('tira pasta, extensão e separadores', () {
      expect(labelFromFileName('assets/sticker/thumbs_up.svg'), 'Thumbs up');
      expect(
        labelFromFileName('assets/frame/moldura-teste.svg'),
        'Moldura teste',
      );
    });

    test('descarta o prefixo numérico de ordenação', () {
      expect(
        labelFromFileName('assets/sticker/github/01-robot-android.svg'),
        'Robot android',
      );
      expect(
        labelFromFileName('assets/sticker/github/23-octopus-silhueta.svg'),
        'Octopus silhueta',
      );
    });

    test('separa palavras grudadas em maiúscula', () {
      expect(labelFromFileName('PlayfairDisplay.ttf'), 'Playfair Display');
      expect(labelFromFileName('SpaceMono.ttf'), 'Space Mono');
    });

    test('não quebra sigla no meio da palavra', () {
      // "GitHub" tem uma maiúscula colada em minúscula, mas "Git Hub" seria
      // pior que deixar como está — a regra só corta depois de minúscula.
      expect(labelFromFileName('GitHub-octocat.svg'), 'Git Hub octocat');
    });

    test('nome vazio não vira rótulo vazio', () {
      expect(labelFromFileName('assets/sticker/.svg'), 'Sem nome');
    });
  });

  group('família de fonte', () {
    test('tira o sufixo de peso', () {
      expect(
        BundledFontStore.familyOf('assets/fonts/BebasNeue-Regular.ttf'),
        'Bebas Neue',
      );
      expect(
        BundledFontStore.familyOf('assets/fonts/PlayfairDisplay-Regular.ttf'),
        'Playfair Display',
      );
      expect(
        BundledFontStore.familyOf('assets/fonts/Pacifico-Regular.ttf'),
        'Pacifico',
      );
      expect(
        BundledFontStore.familyOf('assets/fonts/SpaceMono-Regular.ttf'),
        'Space Mono',
      );
    });

    test('fonte sem sufixo mantém o nome inteiro', () {
      expect(BundledFontStore.familyOf('assets/fonts/Lobster.ttf'), 'Lobster');
    });
  });

  group('lista do manifesto', () {
    test('acha as fontes empacotadas', () async {
      final paths = await BundledAssets.list(
        'assets/fonts/',
        extensions: {'ttf', 'otf'},
      );
      expect(paths, isNotEmpty);
      expect(paths.every((p) => p.endsWith('.ttf')), isTrue);
      expect(paths, contains('assets/fonts/Poppins-Regular.ttf'));
    });

    test('entra em subpasta e respeita a extensão', () async {
      final svgs = await BundledAssets.list(
        'assets/sticker/',
        extensions: {'svg'},
      );
      expect(
        svgs.any((p) => p.startsWith('assets/sticker/github/')),
        isTrue,
        reason: 'subpasta declarada no pubspec precisa aparecer',
      );

      final nenhum = await BundledAssets.list(
        'assets/sticker/',
        extensions: {'png'},
      );
      expect(nenhum, isEmpty);
    });

    test('as fontes empacotadas são registradas', () async {
      final fonts = await const BundledFontStore().loadAll();
      final families = fonts.map((f) => f.family).toList();

      expect(families, contains('Poppins'));
      expect(families, contains('Playfair Display'));
      expect(families, contains('Bebas Neue'));
      expect(families, contains('Space Mono'));
      expect(families, contains('Pacifico'));
    });
  });
}
