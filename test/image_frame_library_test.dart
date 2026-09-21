import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:video_to_gif/core/models/image_frame.dart';

void main() {
  group('molduras prontas', () {
    test('todo SVG registrado existe em assets/frame', () {
      for (final asset in ImageFrameLibrary.bundled) {
        expect(
          asset.source,
          ImageFrameSource.bundledSvg,
          reason: 'a biblioteca só deve conter arte empacotada',
        );
        expect(
          File(asset.svgAssetPath!).existsSync(),
          isTrue,
          // Renomear um SVG sem mexer aqui deixaria a moldura na lista e
          // quebraria só na hora de desenhar, no aparelho.
          reason: '${asset.label}: ${asset.svgAssetPath} não existe',
        );
      }
    });

    test('ids e rótulos não se repetem', () {
      final ids = ImageFrameLibrary.bundled.map((a) => a.id);
      final labels = ImageFrameLibrary.bundled.map((a) => a.label);

      expect(ids.toSet(), hasLength(ImageFrameLibrary.bundled.length));
      expect(labels.toSet(), hasLength(ImageFrameLibrary.bundled.length));
    });

    test('a janela de conteúdo cabe dentro da arte', () {
      for (final asset in ImageFrameLibrary.bundled) {
        final rect = asset.contentRect;
        final reason = asset.label;

        expect(rect.left, inInclusiveRange(0, 1), reason: reason);
        expect(rect.top, inInclusiveRange(0, 1), reason: reason);
        expect(rect.width, greaterThan(0), reason: reason);
        expect(rect.height, greaterThan(0), reason: reason);
        expect(rect.left + rect.width, lessThanOrEqualTo(1), reason: reason);
        expect(rect.top + rect.height, lessThanOrEqualTo(1), reason: reason);

        expect(asset.nativeAspectRatio, greaterThan(0), reason: reason);
        expect(asset.nativeReferenceWidth, greaterThan(0), reason: reason);
      }
    });

    test('a janela vertical e o navegador estão disponíveis', () {
      final byId = {for (final a in ImageFrameLibrary.bundled) a.id: a};

      expect(byId['bundled_janela']?.label, 'Janela');
      expect(
        byId['bundled_janela']?.svgAssetPath,
        'assets/frame/moldura_06_janela_vertival.svg',
      );

      final navegador = byId['bundled_navegador'];
      expect(navegador?.label, 'Navegador');
      expect(
        navegador?.svgAssetPath,
        'assets/frame/moldura_07_navegador_desktop.svg',
      );
      // Única deitada da biblioteca — as telas desenham pela proporção
      // nativa, então ela não pode entrar como se fosse em pé.
      expect(navegador!.nativeAspectRatio, greaterThan(1));
    });
  });
}
