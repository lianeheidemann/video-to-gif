import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:video_to_gif/models/collage_background.dart';
import 'package:video_to_gif/models/collage_cell.dart';
import 'package:video_to_gif/ui/widgets/collage_cell_view.dart';

/// Grava um PNG sólido de verdade em [path] — [CollageCellView] só liga os
/// gestos quando a célula tem foto, e a prévia usa `Image.file`.
Future<void> _writeSolidPng(String path, int width, int height) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.drawRect(
    Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
    Paint()..color = const Color(0xFFFF0000),
  );
  final picture = recorder.endRecording();
  final image = await picture.toImage(width, height);
  try {
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    await File(path).writeAsBytes(bytes!.buffer.asUint8List());
  } finally {
    image.dispose();
    picture.dispose();
  }
}

void main() {
  const cellSize = Size(200, 200);
  late Directory tempDir;
  late String photoPath;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('collage_cell_view_test');
    photoPath = '${tempDir.path}/foto.png';
    await _writeSolidPng(photoPath, 100, 100);
  });

  tearDown(() async {
    if (await tempDir.exists()) await tempDir.delete(recursive: true);
  });

  Future<(int gestureStarts, int changes)> dragCell(
    WidgetTester tester,
    CollageCellSettings cell,
  ) async {
    var gestureStarts = 0;
    var changes = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox.fromSize(
              size: cellSize,
              child: CollageCellView(
                cell: cell,
                cellSize: cellSize,
                onGestureStart: () => gestureStarts++,
                onChanged: (_) => changes++,
                onMenu: () {},
              ),
            ),
          ),
        ),
      ),
    );

    final center = tester.getCenter(find.byType(CollageCellView));
    final gesture = await tester.startGesture(center);
    await tester.pump(const Duration(milliseconds: 100));
    for (var i = 0; i < 4; i++) {
      await gesture.moveBy(const Offset(12, 0));
      await tester.pump(const Duration(milliseconds: 16));
    }
    await gesture.up();
    await tester.pumpAndSettle();
    return (gestureStarts, changes);
  }

  /// Monta a célula sozinha, sem a tela de montagem em volta.
  Future<void> pumpCell(
    WidgetTester tester,
    CollageCellSettings cell, {
    ValueChanged<CollageCellSettings>? onChanged,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox.fromSize(
              size: cellSize,
              child: CollageCellView(
                cell: cell,
                cellSize: cellSize,
                onChanged: onChanged ?? (_) {},
                onMenu: () {},
              ),
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('duplo toque alterna o modo e recentraliza na horizontal', (
    tester,
  ) async {
    final cell = CollageCellSettings(
      photoPath: photoPath,
      photoWidth: 100,
      photoHeight: 100,
      zoom: 2.5,
      rotation: math.pi / 5,
      offsetX: 0.6,
      offsetY: -0.4,
      flipHorizontal: true,
    );
    CollageCellSettings? changed;
    await pumpCell(tester, cell, onChanged: (updated) => changed = updated);

    await tester.tap(find.byType(CollageCellView));
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tap(find.byType(CollageCellView));
    await tester.pumpAndSettle();

    expect(changed, isNotNull);
    expect(changed!.fitMode, CollageCellFitMode.contain);
    expect(changed!.rotation, 0);
    expect(changed!.zoom, CollageCellSettings.minZoom);
    expect(changed!.offsetX, 0);
    expect(changed!.offsetY, 0);
    // A foto e o recorte manual continuam intactos: o duplo toque mexe só no
    // enquadramento.
    expect(changed!.photoPath, photoPath);
  });

  testWidgets('foto girada em "ajustar" não é cortada pelo quadro da célula', (
    tester,
  ) async {
    // Foto ampliada e girada: o widget da imagem tem que ser medido no
    // tamanho que `containDisplaySize` pede. Antes, a caixa do tamanho da
    // célula (que gira junto com a foto) recortava o excedente e o resultado
    // era a foto presa num retângulo girado.
    final cell = CollageCellSettings(
      photoPath: photoPath,
      photoWidth: 100,
      photoHeight: 100,
      fitMode: CollageCellFitMode.contain,
      rotation: math.pi / 6,
      zoom: 2,
    );
    await pumpCell(tester, cell);

    final display = cell.containDisplaySize(cellSize);
    expect(display.width, greaterThan(cellSize.width));
    // `_CroppedCover` (o mesmo widget do modo "preencher", desde que
    // "encaixar" passou a respeitar `manualCrop` de verdade) impõe o
    // tamanho final no `FittedBox` — a `Image` interna agora mede o
    // tamanho nativo da foto, não mais o tamanho exibido.
    expect(tester.getSize(find.byType(FittedBox)), display);
  });

  testWidgets(
    'foto girada em "preencher" é desenhada no tamanho do footprint',
    (tester) async {
      // Mesma matemática de `paintCollageCell` na exportação: a foto precisa
      // sobrar o suficiente para cobrir a célula depois de girada, então a
      // caixa do conteúdo é maior que a célula — se as restrições apertadas do
      // `Stack` a encolhessem, a prévia sairia espremida.
      final cell = CollageCellSettings(
        photoPath: photoPath,
        photoWidth: 100,
        photoHeight: 100,
        rotation: math.pi / 6,
      );
      await pumpCell(tester, cell);

      final (footprintW, footprintH) = rotatedFootprint(
        cellSize.width,
        cellSize.height,
        cell.rotation,
      );
      final size = tester.getSize(find.byType(FittedBox));
      expect(size.width, closeTo(footprintW, 0.01));
      expect(size.height, closeTo(footprintH, 0.01));
    },
  );

  testWidgets('o botão "..." abre o menu da célula', (tester) async {
    var menus = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox.fromSize(
              size: cellSize,
              child: CollageCellView(
                cell: CollageCellSettings(
                  photoPath: photoPath,
                  photoWidth: 100,
                  photoHeight: 100,
                ),
                cellSize: cellSize,
                onChanged: (_) {},
                onMenu: () => menus++,
              ),
            ),
          ),
        ),
      ),
    );

    // Toque com duração de verdade: o `GestureDetector` da célula tem
    // `onDoubleTap`, então o toque do botão só é entregue depois que a arena
    // desiste do duplo toque — um `tester.tap()` instantâneo não chega lá.
    final gesture = await tester.startGesture(
      tester.getCenter(find.byIcon(Icons.more_horiz_rounded)),
    );
    await tester.pump(const Duration(milliseconds: 60));
    await gesture.up();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    expect(menus, 1);
  });

  testWidgets('fundo próprio da foto aparece por baixo dela', (tester) async {
    await pumpCell(
      tester,
      CollageCellSettings(
        photoPath: photoPath,
        photoWidth: 100,
        photoHeight: 100,
        fitMode: CollageCellFitMode.contain,
        background: const CollageBackground(
          mode: CollageBackgroundMode.color,
          color: Color(0xFF0000FF),
        ),
      ),
    );

    expect(
      find.byWidgetPredicate(
        (w) => w is ColoredBox && w.color == const Color(0xFF0000FF),
      ),
      findsOneWidget,
    );
  });

  testWidgets(
    'arrastar uma foto sem folga nenhuma não gasta um passo de desfazer',
    (tester) async {
      // Foto quadrada numa célula quadrada, no zoom mínimo: o recorte "cover"
      // já é a foto inteira, não há para onde deslocar. O arrasto não pode
      // mudar nada — e portanto não pode empilhar um passo de desfazer que
      // depois "desfaz" para exatamente o mesmo estado.
      final (gestureStarts, changes) = await dragCell(
        tester,
        CollageCellSettings(
          photoPath: photoPath,
          photoWidth: 100,
          photoHeight: 100,
        ),
      );

      expect(changes, 0);
      expect(gestureStarts, 0);
    },
  );

  testWidgets('arrastar uma foto com folga empilha um passo só', (
    tester,
  ) async {
    // Com zoom, sobra recorte para os lados: o arrasto muda o enquadramento e
    // aí sim entra um único passo de desfazer, não um por quadro.
    final (gestureStarts, changes) = await dragCell(
      tester,
      CollageCellSettings(
        photoPath: photoPath,
        photoWidth: 100,
        photoHeight: 100,
        zoom: 2,
      ),
    );

    expect(changes, greaterThan(1));
    expect(gestureStarts, 1);
  });

  testWidgets(
    'com interactive: false, arrastar não move a foto nem abre o menu',
    (tester) async {
      // Mesmo cenário de "arrastar uma foto com folga empilha um passo só"
      // (que sem essa trava move a foto), agora com a aba "Stickers"/"Texto"
      // simulada como aberta: nem o arrasto nem o botão "..." devem
      // responder.
      var changes = 0;
      var menus = 0;
      final cell = CollageCellSettings(
        photoPath: photoPath,
        photoWidth: 100,
        photoHeight: 100,
        zoom: 2,
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox.fromSize(
                size: cellSize,
                child: CollageCellView(
                  cell: cell,
                  cellSize: cellSize,
                  interactive: false,
                  onChanged: (_) => changes++,
                  onMenu: () => menus++,
                ),
              ),
            ),
          ),
        ),
      );

      final center = tester.getCenter(find.byType(CollageCellView));
      final gesture = await tester.startGesture(center);
      for (var i = 0; i < 4; i++) {
        await gesture.moveBy(const Offset(12, 0));
        await tester.pump(const Duration(milliseconds: 16));
      }
      await gesture.up();
      await tester.pumpAndSettle();
      expect(changes, 0);

      await tester.tap(find.byIcon(Icons.more_horiz_rounded));
      await tester.pumpAndSettle();
      expect(menus, 0);
    },
  );
}
