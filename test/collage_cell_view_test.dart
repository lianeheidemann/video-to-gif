import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
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
}
