import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:video_to_gif/models/crop_rect.dart';
import 'package:video_to_gif/ui/photo_crop_page.dart';
import 'package:video_to_gif/ui/widgets/crop_overlay.dart';

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
  late Directory tempDir;
  late String photoPath;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('photo_crop_page_test');
    photoPath = '${tempDir.path}/foto.png';
    await _writeSolidPng(photoPath, 400, 200);
  });

  tearDown(() async {
    if (await tempDir.exists()) await tempDir.delete(recursive: true);
  });

  Future<void> pumpPage(
    WidgetTester tester, {
    CropRect? initialCrop,
    Size viewSize = const Size(500, 900),
    ThemeData? theme,
  }) async {
    tester.view.physicalSize = viewSize;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: theme,
        home: PhotoCropPage(
          photoPath: photoPath,
          photoWidth: 400,
          photoHeight: 200,
          cellAspectRatio: 1.0,
          initialCrop: initialCrop,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('abre no recorte livre, com a foto inteira selecionada', (
    tester,
  ) async {
    await pumpPage(tester);

    // "Livre" é o padrão: as alças de lado (que só existem no modo livre)
    // estão na tela e o recorte inicial cobre a foto inteira, em vez de já
    // vir travado na proporção da célula.
    final overlay = tester.widget<CropOverlay>(find.byType(CropOverlay));
    expect(overlay.freeform, isTrue);
    expect(overlay.crop?.width, 400);
    expect(overlay.crop?.height, 200);
  });

  testWidgets(
    'chips de proporção travam a aparência escura mesmo no tema claro',
    (tester) async {
      // A tela é sempre escura de propósito — sem isso, o Material 3
      // tingia o chip com o ColorScheme do tema ambiente (que no modo
      // claro é claro), apagando o contraste das cores fixas e deixando o
      // texto ilegível.
      await pumpPage(tester, theme: ThemeData.light());

      final chip = tester.widget<ChoiceChip>(
        find.widgetWithText(ChoiceChip, '1:1'),
      );
      expect(chip.surfaceTintColor, Colors.transparent);
      expect(chip.elevation, 0);
    },
  );

  testWidgets('escolher uma proporção trava o recorte nela', (tester) async {
    await pumpPage(tester);

    await tester.tap(find.widgetWithText(ChoiceChip, '1:1'));
    await tester.pumpAndSettle();

    final overlay = tester.widget<CropOverlay>(find.byType(CropOverlay));
    expect(overlay.freeform, isFalse);
    expect(overlay.crop!.width, overlay.crop!.height);
  });

  testWidgets('proporção personalizada digitada vira o recorte', (
    tester,
  ) async {
    // Tela larga de propósito: a fileira de proporções rola na horizontal e
    // "Personalizada…" é a última — numa largura de celular ela nasce fora da
    // viewport (e o que não está na viewport de uma lista não existe na
    // árvore para o teste tocar).
    await pumpPage(tester, viewSize: const Size(1400, 900));

    await tester.tap(find.widgetWithText(ChoiceChip, 'Personalizada…'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, '2');
    await tester.enterText(find.byType(TextField).last, '1');
    await tester.tap(find.text('Usar'));
    await tester.pumpAndSettle();

    final overlay = tester.widget<CropOverlay>(find.byType(CropOverlay));
    expect(overlay.freeform, isFalse);
    expect(overlay.crop!.aspectRatio, closeTo(2.0, 0.05));
    // O chip passa a mostrar a proporção escolhida.
    expect(find.widgetWithText(ChoiceChip, '2:1'), findsOneWidget);
  });

  testWidgets('"Usar recorte" devolve o recorte escolhido', (tester) async {
    CropRect? result;
    tester.view.physicalSize = const Size(500, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () async {
              result = await Navigator.of(context).push<CropRect>(
                MaterialPageRoute(
                  builder: (_) => PhotoCropPage(
                    photoPath: photoPath,
                    photoWidth: 400,
                    photoHeight: 200,
                    cellAspectRatio: 1.0,
                  ),
                ),
              );
            },
            child: const Text('abrir'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('abrir'));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(ChoiceChip, '1:1'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Usar recorte'));
    await tester.pumpAndSettle();

    expect(result, isNotNull);
    expect(result!.width, result!.height);
  });
}
