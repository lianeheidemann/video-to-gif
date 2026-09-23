import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:video_to_gif/features/photo/models/eraser_mask.dart';
import 'package:video_to_gif/core/models/photo_info.dart';
import 'package:video_to_gif/features/photo/photo_frame_page.dart';
import 'package:video_to_gif/features/photo/widgets/eraser_mask_overlay.dart';
import 'package:video_to_gif/features/photo/widgets/eraser_option_button.dart';

Future<void> _writeSolidPng(String path, int width, int height) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.drawRect(
    Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
    Paint()..color = const Color(0xFF3366AA),
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
  late PhotoInfo photo;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('eraser_tab_test');
    final path = '${tempDir.path}/foto.png';
    await _writeSolidPng(path, 400, 400);
    photo = PhotoInfo(path: path, width: 400, height: 400);
  });

  tearDown(() async {
    if (await tempDir.exists()) await tempDir.delete(recursive: true);
  });

  Future<void> pumpPage(WidgetTester tester) async {
    tester.view.physicalSize = const Size(500, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(home: PhotoFramePage(photo: photo)));
    await tester.pumpAndSettle();
  }

  /// Abre a aba da borracha tocando no rótulo curto do rodapé.
  Future<void> openEraserTab(WidgetTester tester) async {
    await tester.tap(find.text('Borracha'));
    await tester.pumpAndSettle();
  }

  EraserCanvas canvas(WidgetTester tester) =>
      tester.widget<EraserCanvas>(find.byType(EraserCanvas));

  /// Toca num controle do painel do rodapé. O painel é uma área rolável de
  /// 200px de altura ([EditorTabsFooter.maxPanelHeight]), então o que está
  /// mais abaixo precisa ser trazido para dentro da vista antes — sem isso o
  /// toque cai fora do widget e não faz nada.
  Future<void> tapInPanel(WidgetTester tester, Finder finder) async {
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  /// Arrasta na prévia, que é o gesto que pinta a seleção.
  Future<void> paintStroke(WidgetTester tester) async {
    final center = tester.getCenter(find.byType(EraserCanvas));
    final gesture = await tester.startGesture(center);
    await tester.pump();
    for (var i = 1; i <= 4; i++) {
      await gesture.moveTo(center + Offset(i * 12.0, 0));
      await tester.pump();
    }
    await gesture.up();
    await tester.pumpAndSettle();
  }

  testWidgets('a aba existe e abre sem erro', (tester) async {
    await pumpPage(tester);
    await openEraserTab(tester);

    // O estado da seleção fica no selo do cabeçalho do painel.
    expect(find.text('Nenhuma seleção'), findsOneWidget);
    expect(find.widgetWithText(EraserOptionButton, 'Pincel'), findsOneWidget);
    // "Apagar seleção" e a nota sobre a qualidade não estão no mockup, mas
    // continuam no painel.
    expect(
      find.widgetWithText(EraserOptionButton, 'Apagar seleção'),
      findsOneWidget,
    );
    expect(find.textContaining('Mais qualidade demora mais'), findsOneWidget);
    expect(find.byType(EraserCanvas), findsOneWidget);
    // Fora da aba a prévia é a normal; aqui a foto aparece crua, para a
    // seleção ficar em coordenadas da foto.
    expect(canvas(tester).photoWidth, 400);
    expect(canvas(tester).photoHeight, 400);
  });

  testWidgets('"Apagar" nasce desabilitado e liga com a primeira pincelada', (
    tester,
  ) async {
    await pumpPage(tester);
    await openEraserTab(tester);

    final erase = find.widgetWithText(FilledButton, 'Apagar');
    expect(tester.widget<FilledButton>(erase).onPressed, isNull);
    expect(canvas(tester).mask.isEmpty, isTrue);

    await paintStroke(tester);

    expect(canvas(tester).mask.strokes, hasLength(1));
    expect(tester.widget<FilledButton>(erase).onPressed, isNotNull);
    expect(find.text('Seleção pronta'), findsOneWidget);
    expect(find.text('Nenhuma seleção'), findsNothing);
  });

  testWidgets('"Limpar" esvazia a seleção inteira', (tester) async {
    await pumpPage(tester);
    await openEraserTab(tester);
    await paintStroke(tester);
    await paintStroke(tester);
    expect(canvas(tester).mask.strokes, hasLength(2));

    await tapInPanel(tester, find.widgetWithText(OutlinedButton, 'Limpar'));

    expect(canvas(tester).mask.isEmpty, isTrue);
  });

  testWidgets('"Desfazer traço" tira só a última pincelada', (tester) async {
    await pumpPage(tester);
    await openEraserTab(tester);
    await paintStroke(tester);
    await paintStroke(tester);

    await tapInPanel(tester, find.text('Desfazer traço'));

    expect(canvas(tester).mask.strokes, hasLength(1));
  });

  testWidgets('o slider de pincel some nas ferramentas de área', (
    tester,
  ) async {
    await pumpPage(tester);
    await openEraserTab(tester);

    // Pincel: o tamanho importa.
    expect(find.text('Tamanho do pincel'), findsOneWidget);

    await tapInPanel(
      tester,
      find.widgetWithText(EraserOptionButton, 'Retângulo'),
    );

    // Retângulo desenha área fechada — espessura não quer dizer nada.
    expect(find.text('Tamanho do pincel'), findsNothing);
    expect(canvas(tester).tool, EraserTool.rectangle);
  });

  testWidgets('o retângulo vira uma área fechada de quatro cantos', (
    tester,
  ) async {
    await pumpPage(tester);
    await openEraserTab(tester);
    await tapInPanel(
      tester,
      find.widgetWithText(EraserOptionButton, 'Retângulo'),
    );

    await paintStroke(tester);

    final stroke = canvas(tester).mask.strokes.single;
    expect(stroke.closed, isTrue);
    expect(stroke.points, hasLength(4));
  });

  testWidgets('"Apagar seleção" marca o traço como subtrativo', (tester) async {
    await pumpPage(tester);
    await openEraserTab(tester);
    await paintStroke(tester);

    await tapInPanel(
      tester,
      find.widgetWithText(EraserOptionButton, 'Apagar seleção'),
    );
    await paintStroke(tester);

    final strokes = canvas(tester).mask.strokes;
    expect(strokes, hasLength(2));
    expect(strokes.first.subtract, isFalse);
    expect(strokes.last.subtract, isTrue);
    // Ainda há o que apagar: o traço aditivo continua lá.
    expect(canvas(tester).mask.isEmpty, isFalse);
  });

  testWidgets('a qualidade escolhida fica marcada', (tester) async {
    await pumpPage(tester);
    await openEraserTab(tester);

    await tapInPanel(tester, find.widgetWithText(EraserOptionButton, 'Alta'));

    final chip = tester.widget<EraserOptionButton>(
      find.widgetWithText(EraserOptionButton, 'Alta'),
    );
    expect(chip.selected, isTrue);
  });

  testWidgets('"Tentar de novo" só aparece depois de uma apagada', (
    tester,
  ) async {
    await pumpPage(tester);
    await openEraserTab(tester);
    await paintStroke(tester);

    // Antes de apagar não faz sentido: não há resultado para trocar por
    // outro. (A apagada em si não entra neste teste — ela sobe um Isolate e
    // leva segundos.)
    expect(find.text('Tentar de novo'), findsNothing);
  });

  testWidgets('a seleção é guardada em pixels da foto, não da tela', (
    tester,
  ) async {
    await pumpPage(tester);
    await openEraserTab(tester);
    await paintStroke(tester);

    final box = tester.getSize(find.byType(EraserCanvas));
    final stroke = canvas(tester).mask.strokes.single;
    // A caixa da prévia é menor que a foto (400px numa tela de 500 com
    // margens), então um traço no meio tem que sair em coordenadas maiores
    // que as da tela — é o que garante que a máscara não encolhe junto com a
    // prévia.
    final scale = 400 / box.width;
    expect(stroke.points.first.dx, closeTo(box.width / 2 * scale, 2));
    expect(stroke.radius, closeTo(400 * 4 / 100, 0.01));
  });
}
