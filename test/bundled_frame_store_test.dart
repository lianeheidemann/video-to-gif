import 'package:flutter_test/flutter_test.dart';
import 'package:video_to_gif/core/models/image_frame.dart';
import 'package:video_to_gif/core/services/bundled_frame_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('molduras descobertas', () {
    test('acha todo SVG de assets/frame', () async {
      final frames = await loadBundledImageFrames();

      expect(
        frames.length,
        greaterThanOrEqualTo(ImageFrameLibrary.bundled.length),
      );
      expect(
        frames.map((f) => f.svgAssetPath).toSet(),
        containsAll(ImageFrameLibrary.bundled.map((f) => f.svgAssetPath)),
      );
    });

    test('moldura curada mantém nome e janela escritos à mão', () async {
      final frames = await loadBundledImageFrames();
      final porCaminho = {for (final f in frames) f.svgAssetPath: f};

      for (final curada in ImageFrameLibrary.bundled) {
        final achada = porCaminho[curada.svgAssetPath]!;
        // A detecção automática é boa, mas a janela tirada à mão da
        // geometria do SVG é exata — a curada tem que ganhar.
        expect(achada.label, curada.label);
        expect(achada.id, curada.id);
        expect(achada.contentRect.left, curada.contentRect.left);
        expect(achada.contentRect.top, curada.contentRect.top);
        expect(achada.contentRect.width, curada.contentRect.width);
        expect(achada.contentRect.height, curada.contentRect.height);
      }
    });

    test('as curadas vêm primeiro, na ordem da biblioteca', () async {
      final frames = await loadBundledImageFrames();
      final curadas = frames
          .take(ImageFrameLibrary.bundled.length)
          .map((f) => f.id)
          .toList();

      expect(curadas, ImageFrameLibrary.bundled.map((f) => f.id).toList());
    });

    test('ids não se repetem e são estáveis entre carregamentos', () async {
      final primeira = await loadBundledImageFrames();
      final segunda = await loadBundledImageFrames();

      final ids = primeira.map((f) => f.id).toList();
      expect(ids.toSet(), hasLength(ids.length));
      // Id derivado do caminho, não de contador: se mudasse a cada
      // abertura, a moldura escolhida se perderia.
      expect(segunda.map((f) => f.id).toList(), ids);
    });
  });
}
