import 'package:flutter_test/flutter_test.dart';
import 'package:video_to_gif/core/models/crop_rect.dart';
import 'package:video_to_gif/core/ui/crop/crop_controller.dart';
import 'package:video_to_gif/core/ui/crop/crop_overlay.dart';

void main() {
  group('evenOnly', () {
    final video = CropController(
      sourceWidth: 1920,
      sourceHeight: 1080,
      evenOnly: true,
    );
    final foto = CropController(sourceWidth: 1920, sourceHeight: 1080);

    test('ligado, arredonda para baixo até o par mais próximo', () {
      expect(video.snap(101), 100);
      expect(video.snap(100), 100);
      expect(video.snap(1), 2);
    });

    test('desligado, não mexe no valor', () {
      expect(foto.snap(101), 101);
      expect(foto.snap(1), 1);
    });

    test('lado mínimo é 2 no vídeo e 1 nas outras telas', () {
      expect(video.minSide, 2);
      expect(foto.minSide, 1);
    });

    test('centeredOn devolve dimensões pares só com evenOnly', () {
      expect(video.centeredOn(101, 51).width, 100);
      expect(video.centeredOn(101, 51).height, 50);
      expect(foto.centeredOn(101, 51).width, 101);
      expect(foto.centeredOn(101, 51).height, 51);
    });
  });

  group('centeredOn', () {
    final c = CropController(sourceWidth: 1000, sourceHeight: 800);

    test('sem referência, centraliza na fonte', () {
      final crop = c.centeredOn(400, 200);
      expect(crop.x, 300);
      expect(crop.y, 300);
    });

    test('com referência, mantém o centro do recorte anterior', () {
      const anterior = CropRect(x: 0, y: 0, width: 100, height: 100);
      final crop = c.centeredOn(50, 50, around: anterior);
      expect(crop.x, 25);
      expect(crop.y, 25);
    });

    test('não deixa o recorte sair da fonte', () {
      const canto = CropRect(x: 950, y: 750, width: 50, height: 50);
      final crop = c.centeredOn(400, 400, around: canto);
      expect(crop.x + crop.width, lessThanOrEqualTo(1000));
      expect(crop.y + crop.height, lessThanOrEqualTo(800));
    });

    test('tamanho maior que a fonte é limitado à fonte', () {
      final crop = c.centeredOn(5000, 5000);
      expect(crop.width, 1000);
      expect(crop.height, 800);
    });
  });

  group('withWidth / withHeight', () {
    final c = CropController(sourceWidth: 1000, sourceHeight: 1000);
    const atual = CropRect(x: 100, y: 100, width: 200, height: 300);

    test('sem proporção travada, o outro lado não muda', () {
      expect(c.withWidth(400, crop: atual).height, 300);
      expect(c.withHeight(400, crop: atual).width, 200);
    });

    test('com proporção travada, o outro lado acompanha', () {
      final crop = c.withWidth(400, crop: atual, ratio: 2);
      expect(crop.width, 400);
      expect(crop.height, 200);
    });

    test('recorte cresce a partir do centro do anterior', () {
      final crop = c.withWidth(400, crop: atual);
      expect(crop.x + crop.width / 2, atual.x + atual.width / 2);
    });
  });

  group('defaultCustomCrop', () {
    test('é 80% da fonte, centralizado', () {
      final crop = CropController(
        sourceWidth: 1000,
        sourceHeight: 500,
      ).defaultCustomCrop();
      expect(crop.width, 800);
      expect(crop.height, 400);
      expect(crop.x, 100);
      expect(crop.y, 50);
    });
  });

  group('sobra fracionária do arrasto', () {
    const crop = CropRect(x: 100, y: 100, width: 200, height: 200);

    test('acumulando, deltas pequenos somam até virar um pixel inteiro', () {
      final c = CropController(sourceWidth: 1000, sourceHeight: 1000);
      // Dois passos de 0,4px para a direita: o primeiro sozinho arredonda
      // para o mesmo pixel, mas a sobra fica guardada e o segundo fecha.
      expect(c.moveBy(crop: crop, sourceDelta: const Offset(0.4, 0)), isNull);
      expect(c.moveBy(crop: crop, sourceDelta: const Offset(0.4, 0))?.x, 101);
    });

    test('as três telas acumulam igual — nenhuma descarta a sobra', () {
      // O vídeo arredonda para par e tem a fonte maior, mas a regra da sobra
      // é a mesma das outras duas: dois passos de 0,4px movem um pixel.
      final telas = [
        CropController(sourceWidth: 1920, sourceHeight: 1080, evenOnly: true),
        CropController(sourceWidth: 1000, sourceHeight: 1000),
        CropController(sourceWidth: 512, sourceHeight: 512, minHandleSize: 8),
      ];
      for (final c in telas) {
        expect(c.moveBy(crop: crop, sourceDelta: const Offset(0.4, 0)), isNull);
        expect(c.moveBy(crop: crop, sourceDelta: const Offset(0.4, 0))?.x, 101);
      }
    });

    test('resizeBy acumula a sobra do mesmo jeito', () {
      CropRect? arrastar(CropController c, double dx) => c.resizeBy(
        crop: crop,
        handle: CropHandle.right,
        sourceDelta: Offset(dx, 0),
      );

      // Acumulando, três passos de 0,55px chegam a 1,65 e alargam a janela
      // (resizeFreeCrop mantém as dimensões pares, daí o passo de 2).
      final acumula = CropController(sourceWidth: 1000, sourceHeight: 1000);
      expect(arrastar(acumula, 0.55), isNull);
      expect(arrastar(acumula, 0.55), isNull);
      expect(arrastar(acumula, 0.55)?.width, 202);

      // E um passo único do mesmo tamanho total não mexe: é a sobra
      // acumulada que fecha o pixel, não o delta de um frame só.
      final passoUnico = CropController(sourceWidth: 1000, sourceHeight: 1000);
      expect(arrastar(passoUnico, 0.55), isNull);
    });

    test('moveBy não deixa a janela sair da fonte', () {
      final c = CropController(sourceWidth: 1000, sourceHeight: 1000);
      final movido = c.moveBy(
        crop: crop,
        sourceDelta: const Offset(5000, 5000),
      );
      expect(movido?.x, 800);
      expect(movido?.y, 800);
    });
  });
}
