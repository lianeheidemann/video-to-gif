import 'package:flutter_test/flutter_test.dart';
import 'package:video_to_gif/models/crop_rect.dart';
import 'package:video_to_gif/ui/widgets/crop_overlay.dart';

/// `resizeFreeCrop`/`resizeLockedCrop` foram extraídos de `editor_page.dart`
/// (onde já rodavam sem testes dedicados, só exercitados manualmente pelo
/// recorte de vídeo) para serem reaproveitados pelo recorte de foto da
/// montagem — a extração em si não mudou nenhuma fórmula, só trocou
/// `VideoInfo` por `Size`/`boundsWidth`/`boundsHeight` explícitos. Estes
/// testes cobrem o comportamento básico que o recorte de foto passa a
/// depender diretamente.
void main() {
  group('resizeLockedCrop', () {
    test('mantém a proporção travada ao arrastar um canto', () {
      const crop = CropRect(x: 100, y: 100, width: 200, height: 200);
      final next = resizeLockedCrop(
        crop,
        CropHandle.bottomRight,
        40,
        40,
        1.0, // quadrado
        boundsWidth: 1000,
        boundsHeight: 1000,
      );
      expect(next.width, next.height);
    });

    test('nunca sai dos limites do conteúdo original', () {
      const crop = CropRect(x: 0, y: 0, width: 100, height: 100);
      final next = resizeLockedCrop(
        crop,
        CropHandle.bottomRight,
        5000,
        5000,
        1.0,
        boundsWidth: 300,
        boundsHeight: 300,
      );
      expect(next.x, greaterThanOrEqualTo(0));
      expect(next.y, greaterThanOrEqualTo(0));
      expect(next.x + next.width, lessThanOrEqualTo(300));
      expect(next.y + next.height, lessThanOrEqualTo(300));
    });

    test('arrastar o canto oposto ao ancorado não move o canto ancorado', () {
      const crop = CropRect(x: 100, y: 100, width: 200, height: 200);
      final next = resizeLockedCrop(
        crop,
        CropHandle.bottomRight,
        20,
        20,
        1.0,
        boundsWidth: 1000,
        boundsHeight: 1000,
      );
      // Arrastar o canto inferior-direito mantém o canto superior-esquerdo
      // (100,100) no lugar — só o tamanho cresce a partir dali.
      expect(next.x, 100);
      expect(next.y, 100);
    });
  });

  group('resizeFreeCrop', () {
    test('respeita o tamanho mínimo mesmo arrastando para dentro', () {
      // Delta plausível de um gesto real (`onPanUpdate.delta` é incremental,
      // poucos pixels por quadro) — bem maior que a folga até o mínimo, mas
      // sem inverter os limites do próprio cálculo.
      const crop = CropRect(x: 100, y: 100, width: 100, height: 100);
      final next = resizeFreeCrop(
        crop,
        CropHandle.bottomRight,
        -90,
        -90,
        boundsWidth: 1000,
        boundsHeight: 1000,
      );
      expect(next.width, greaterThanOrEqualTo(2));
      expect(next.height, greaterThanOrEqualTo(2));
    });

    test('nunca sai dos limites do conteúdo original', () {
      const crop = CropRect(x: 400, y: 400, width: 100, height: 100);
      final next = resizeFreeCrop(
        crop,
        CropHandle.topLeft,
        -5000,
        -5000,
        boundsWidth: 500,
        boundsHeight: 500,
      );
      expect(next.x, greaterThanOrEqualTo(0));
      expect(next.y, greaterThanOrEqualTo(0));
    });
  });
}
