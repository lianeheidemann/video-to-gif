import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:video_to_gif/features/collage/models/background_image.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('fundos prontos', () {
    test('todo fundo registrado chega pelo rootBundle', () async {
      for (final background in BackgroundImageLibrary.bundled) {
        // Pelo rootBundle e não pelo sistema de arquivos: existir na pasta
        // não basta, o asset também precisa estar declarado no pubspec, que
        // é como o app vai lê-lo de verdade.
        final data = await rootBundle.load(background.assetPath);
        expect(
          data.lengthInBytes,
          greaterThan(1000),
          reason: '${background.label}: ${background.assetPath} não carregou',
        );
      }
    });

    test('são quatro, com caminhos e rótulos distintos', () {
      final bundled = BackgroundImageLibrary.bundled;

      expect(bundled, hasLength(4));
      expect(bundled.map((b) => b.assetPath).toSet(), hasLength(4));
      expect(bundled.map((b) => b.label).toSet(), hasLength(4));
    });

    test('todo fundo pronto é reconhecido como asset', () {
      for (final background in BackgroundImageLibrary.bundled) {
        expect(isBundledBackgroundPath(background.assetPath), isTrue);
      }
    });

    test('arquivo importado não passa por fundo pronto', () {
      // O que o ImportedAssetStore grava é sempre caminho absoluto, e é isso
      // que separa as duas origens dentro de CollageBackground.imagePath.
      expect(
        isBundledBackgroundPath(
          '/data/user/0/app/files/imported_backgrounds/a.jpg',
        ),
        isFalse,
      );
      expect(isBundledBackgroundPath('/tmp/assets/background/x.jpg'), isFalse);
    });
  });
}
