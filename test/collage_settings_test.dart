import 'package:flutter/material.dart' show Color;
import 'package:flutter_test/flutter_test.dart';
import 'package:video_to_gif/models/collage_background.dart';
import 'package:video_to_gif/models/collage_cell.dart';
import 'package:video_to_gif/models/collage_layout.dart';
import 'package:video_to_gif/models/collage_settings.dart';
import 'package:video_to_gif/models/collage_sticker.dart';
import 'package:video_to_gif/models/photo_info.dart';

const _photoA = PhotoInfo(path: '/tmp/a.jpg', width: 100, height: 200);
const _photoB = PhotoInfo(path: '/tmp/b.jpg', width: 300, height: 300);
const _photoC = PhotoInfo(path: '/tmp/c.jpg', width: 400, height: 100);

void main() {
  group('CollageSettings.forLayout', () {
    test('cria uma célula por foto, na ordem escolhida', () {
      final settings = CollageSettings.forLayout(CollageLayout.row(3), const [
        _photoA,
        _photoB,
        _photoC,
      ]);
      expect(settings.cells.length, 3);
      expect(settings.cells[0].photoPath, _photoA.path);
      expect(settings.cells[1].photoPath, _photoB.path);
      expect(settings.cells[2].photoPath, _photoC.path);
    });

    test('menos fotos que células deixa o resto vazio', () {
      final settings = CollageSettings.forLayout(
        const CollageLayout(kind: CollageLayoutKind.grid2x2),
        const [_photoA],
      );
      expect(settings.cells.length, 4);
      expect(settings.cells[0].hasPhoto, isTrue);
      expect(settings.cells[1].hasPhoto, isFalse);
    });
  });

  group('replacingCell / swappingCells', () {
    late CollageSettings settings;

    setUp(() {
      settings = CollageSettings.forLayout(CollageLayout.row(2), const [
        _photoA,
        _photoB,
      ]);
    });

    test('replacingCell troca só a célula indicada', () {
      final replaced = settings.replacingCell(
        0,
        const CollageCellSettings(photoPath: '/tmp/novo.jpg'),
      );
      expect(replaced.cells[0].photoPath, '/tmp/novo.jpg');
      expect(replaced.cells[1].photoPath, _photoB.path);
    });

    test('swappingCells troca foto e ajustes, mantendo a posição', () {
      final adjusted = settings.replacingCell(
        0,
        settings.cells[0].copyWith(brightness: 0.4, zoom: 2),
      );
      final swapped = adjusted.swappingCells(0, 1);
      expect(swapped.cells[0].photoPath, _photoB.path);
      expect(swapped.cells[0].brightness, 0.0);
      expect(swapped.cells[1].photoPath, _photoA.path);
      expect(swapped.cells[1].brightness, 0.4);
      expect(swapped.cells[1].zoom, 2.0);
    });

    test('swappingCells com o mesmo índice não muda nada', () {
      final swapped = settings.swappingCells(0, 0);
      expect(swapped.cells[0].photoPath, settings.cells[0].photoPath);
    });
  });

  group('updatingAllCells', () {
    test('aplica a mudança em todas as células de uma vez', () {
      final settings = CollageSettings.forLayout(CollageLayout.row(2), const [
        _photoA,
        _photoB,
      ]);
      final updated = settings.updatingAllCells(
        (c) => c.copyWith(borderThicknessAtReference: 12),
      );
      expect(updated.cells[0].borderThicknessAtReference, 12);
      expect(updated.cells[1].borderThicknessAtReference, 12);
    });

    test('não perde diferenças de foto/enquadramento já existentes', () {
      final settings =
          CollageSettings.forLayout(CollageLayout.row(2), const [
            _photoA,
            _photoB,
          ]).replacingCell(
            0,
            const CollageCellSettings(photoPath: '/tmp/a.jpg', zoom: 2),
          );
      final updated = settings.updatingAllCells(
        (c) => c.copyWith(cornerRatio: 0.2),
      );
      expect(updated.cells[0].zoom, 2.0);
      expect(updated.cells[0].cornerRatio, 0.2);
      expect(updated.cells[1].cornerRatio, 0.2);
    });
  });

  group('stickers/textos e zIndex', () {
    test('nextZIndex sempre fica acima do maior já usado', () {
      final settings = CollageSettings(layout: CollageLayout.row(1));
      expect(settings.nextZIndex, 1);

      final withSticker = settings.addingSticker(
        const CollageSticker(
          id: 's1',
          source: CollageStickerSource.importedImage,
          imageFilePath: '/tmp/s.png',
          centerX: 0.5,
          centerY: 0.5,
          zIndex: 5,
        ),
      );
      expect(withSticker.nextZIndex, 6);
    });

    test('removingSticker tira só o sticker com aquele id', () {
      const sticker1 = CollageSticker(
        id: 's1',
        source: CollageStickerSource.importedImage,
        imageFilePath: '/tmp/s1.png',
        centerX: 0.5,
        centerY: 0.5,
        zIndex: 1,
      );
      const sticker2 = CollageSticker(
        id: 's2',
        source: CollageStickerSource.importedImage,
        imageFilePath: '/tmp/s2.png',
        centerX: 0.3,
        centerY: 0.3,
        zIndex: 2,
      );
      final settings = CollageSettings(
        layout: CollageLayout.row(1),
      ).addingSticker(sticker1).addingSticker(sticker2);
      final removed = settings.removingSticker('s1');
      expect(removed.stickers.length, 1);
      expect(removed.stickers.single.id, 's2');
    });
  });

  group('estilo compartilhado das fotos', () {
    test('withSharedCellStyle copia borda, canto e fundo da foto que já '
        'está na montagem', () {
      const estilo = CollageCellSettings(
        photoPath: '/tmp/a.jpg',
        photoWidth: 100,
        photoHeight: 100,
        cornerRatio: 0.3,
        borderThicknessAtReference: 14,
        borderColor: Color(0xFF00FF00),
        background: CollageBackground(
          mode: CollageBackgroundMode.color,
          color: Color(0xFF0000FF),
        ),
      );
      final settings = CollageSettings(
        layout: CollageLayout.grid(2, 1),
        cells: const [estilo, CollageCellSettings()],
      );

      // A célula vazia — que é o estado de quem vai receber uma foto depois —
      // entra com o mesmo visual das que já estavam lá.
      final nova = settings.withSharedCellStyle(const CollageCellSettings());
      expect(nova.cornerRatio, 0.3);
      expect(nova.borderThicknessAtReference, 14);
      expect(nova.borderColor, const Color(0xFF00FF00));
      expect(nova.background.mode, CollageBackgroundMode.color);
      expect(nova.background.color, const Color(0xFF0000FF));
    });

    test('não mexe no enquadramento nem na foto da célula recebida', () {
      const estilo = CollageCellSettings(
        photoPath: '/tmp/a.jpg',
        borderThicknessAtReference: 8,
      );
      final settings = CollageSettings(
        layout: CollageLayout.row(1),
        cells: const [estilo],
      );

      const recebida = CollageCellSettings(
        photoPath: '/tmp/nova.jpg',
        photoWidth: 50,
        photoHeight: 60,
        zoom: 2,
        fitMode: CollageCellFitMode.contain,
      );
      final resultado = settings.withSharedCellStyle(recebida);
      expect(resultado.photoPath, '/tmp/nova.jpg');
      expect(resultado.zoom, 2);
      expect(resultado.fitMode, CollageCellFitMode.contain);
      expect(resultado.borderThicknessAtReference, 8);
    });

    test('sem nenhuma foto ainda, o estilo é o padrão', () {
      final settings = CollageSettings(
        layout: CollageLayout.row(2),
        cells: const [CollageCellSettings(), CollageCellSettings()],
      );
      final nova = settings.withSharedCellStyle(const CollageCellSettings());
      expect(nova.borderThicknessAtReference, 0);
      expect(nova.background.mode, CollageBackgroundMode.transparent);
    });
  });
}
