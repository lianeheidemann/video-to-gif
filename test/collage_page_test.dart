import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:video_to_gif/models/collage_background.dart';
import 'package:video_to_gif/models/collage_cell.dart';
import 'package:video_to_gif/models/collage_color_adjustment.dart';
import 'package:video_to_gif/models/photo_info.dart';
import 'package:video_to_gif/ui/collage_page.dart';
import 'package:video_to_gif/ui/widgets/collage_cell_view.dart';
import 'package:video_to_gif/ui/widgets/color_adjust_controls.dart';

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
  late List<PhotoInfo> photos;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    tempDir = await Directory.systemTemp.createTemp('collage_page_test');
    photos = [];
    for (var i = 0; i < 2; i++) {
      final path = '${tempDir.path}/foto_$i.png';
      await _writeSolidPng(path, 60, 60);
      photos.add(PhotoInfo(path: path, width: 60, height: 60));
    }
  });

  tearDown(() async {
    if (await tempDir.exists()) await tempDir.delete(recursive: true);
  });

  testWidgets(
    'desfazer a criação de um texto também tira a barra de ações da tela',
    (tester) async {
      // Tela alta o bastante para a prévia, a barra de ações e as seções
      // caberem juntas — a prévia sozinha já é quadrada e mais alta que a
      // janela padrão do flutter_test.
      tester.view.physicalSize = const Size(900, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(MaterialApp(home: CollagePage(photos: photos)));
      await tester.pumpAndSettle();

      // Abre a seção "Texto" e cria um texto sobreposto.
      final page = find.byType(Scrollable).first;
      await tester.scrollUntilVisible(
        find.text('Texto'),
        200,
        scrollable: page,
      );
      await tester.tap(find.text('Texto'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Adicionar texto'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'oi');
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();

      // Com o texto recém-criado selecionado, a barra de ações da sobreposição
      // aparece logo abaixo da prévia.
      await tester.scrollUntilVisible(
        find.byTooltip('Duplicar'),
        -200,
        scrollable: page,
      );
      expect(find.byTooltip('Duplicar'), findsOneWidget);

      await tester.tap(find.byTooltip('Desfazer'));
      await tester.pumpAndSettle();

      // O texto deixou de existir: a barra não pode continuar na tela
      // apontando para ele, com todos os botões sem efeito nenhum.
      expect(find.text('oi'), findsNothing);
      expect(find.byTooltip('Duplicar'), findsNothing);
    },
  );

  testWidgets(
    'layout "Linha" tem contador de fotos, igual "Grade livre" já tinha',
    (tester) async {
      tester.view.physicalSize = const Size(900, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(MaterialApp(home: CollagePage(photos: photos)));
      await tester.pumpAndSettle();

      // A aba "Layout" já começa aberta; troca para "Linha".
      await tester.tap(find.text('Linha'));
      await tester.pumpAndSettle();

      expect(find.text('Fotos'), findsOneWidget);
      expect(find.text('2'), findsOneWidget);

      await tester.tap(find.byIcon(Icons.add_circle_outline));
      await tester.pumpAndSettle();

      expect(find.text('3'), findsOneWidget);
    },
  );

  testWidgets('sticker embutido pode ser adicionado à montagem', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(900, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(MaterialApp(home: CollagePage(photos: photos)));
    await tester.pumpAndSettle();

    final page = find.byType(Scrollable).first;
    await tester.scrollUntilVisible(
      find.text('Stickers'),
      200,
      scrollable: page,
    );
    await tester.tap(find.text('Stickers'));
    await tester.pumpAndSettle();

    // Os 5 stickers embutidos aparecem antes do tile "Importar".
    expect(find.byType(SvgPicture), findsWidgets);

    await tester.tap(find.byType(SvgPicture).first);
    await tester.pumpAndSettle();

    // Adicionar um sticker já o seleciona — a barra de ações aparece.
    expect(find.byTooltip('Duplicar'), findsOneWidget);
  });

  testWidgets('opções de fundo não quebram linha dentro do próprio botão', (
    tester,
  ) async {
    // Largura de tela estreita de propósito, pior caso para o antigo
    // SegmentedButton (rótulo "Transparente" quebrando ao meio).
    tester.view.physicalSize = const Size(400, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(MaterialApp(home: CollagePage(photos: photos)));
    await tester.pumpAndSettle();

    final page = find.byType(Scrollable).first;
    await tester.scrollUntilVisible(find.text('Fundo'), 200, scrollable: page);
    await tester.tap(find.text('Fundo'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('Transparente'), findsOneWidget);
    expect(find.text('Cor'), findsOneWidget);
    expect(find.text('Imagem'), findsOneWidget);
  });

  testWidgets('recorte aprovado entra em "encaixar", na horizontal', (
    tester,
  ) async {
    // Com o recorte livre, o resultado quase nunca tem a proporção da célula:
    // se continuasse em "preencher", a foto recortada apareceria esticada/
    // cortada de novo. Depois de "Usar recorte" ela tem que aparecer inteira,
    // centralizada e a 0°.
    tester.view.physicalSize = const Size(900, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(MaterialApp(home: CollagePage(photos: photos)));
    await tester.pumpAndSettle();

    // Toque com duração de verdade: o `GestureDetector` da célula tem
    // `onDoubleTap`, então o toque do "..." só é entregue depois que a arena
    // de gestos desiste do duplo toque.
    final gesture = await tester.startGesture(
      tester.getCenter(find.byIcon(Icons.more_horiz_rounded).first),
    );
    await tester.pump(const Duration(milliseconds: 60));
    await gesture.up();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Recortar'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Usar recorte'));
    await tester.pumpAndSettle();

    final cell = tester
        .widgetList<CollageCellView>(find.byType(CollageCellView))
        .first
        .cell;
    expect(cell.manualCrop, isNotNull);
    expect(cell.fitMode, CollageCellFitMode.contain);
    expect(cell.rotation, 0);
    expect(cell.zoom, CollageCellSettings.minZoom);
    expect(cell.offsetX, 0);
    expect(cell.offsetY, 0);
  });

  testWidgets('"Ajustar cor" abre com as bolinhas dos oito ajustes', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(900, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(MaterialApp(home: CollagePage(photos: photos)));
    await tester.pumpAndSettle();

    // Toque com duração de verdade: o "..." só é entregue depois que a arena
    // desiste do duplo toque da célula.
    final gesture = await tester.startGesture(
      tester.getCenter(find.byIcon(Icons.more_horiz_rounded).first),
    );
    await tester.pump(const Duration(milliseconds: 60));
    await gesture.up();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Ajustar cor'));
    await tester.pumpAndSettle();

    expect(find.byType(IntensityRuler), findsOneWidget);
    expect(
      find.byType(ColorAdjustButton),
      findsNWidgets(CollageColorAdjustment.values.length),
    );
    // Começa no brilho, com a régua no zero.
    expect(find.text('0'), findsOneWidget);
    expect(find.text('Brilho'), findsWidgets);
  });

  testWidgets('texto ganha fundo, cor e arredondamento pelo painel', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(900, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(MaterialApp(home: CollagePage(photos: photos)));
    await tester.pumpAndSettle();

    final page = find.byType(Scrollable).first;
    await tester.scrollUntilVisible(find.text('Texto'), 200, scrollable: page);
    await tester.tap(find.text('Texto'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Adicionar texto'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'oi');
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();

    // Com o texto recém-criado selecionado, o painel mostra os controles de
    // estilo dele.
    expect(find.text('Cor do texto'), findsOneWidget);
    expect(find.text('Fundo do texto'), findsOneWidget);
    expect(find.text('Arredondamento do fundo'), findsNothing);

    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();

    expect(find.text('Cor do fundo do texto'), findsOneWidget);
    expect(find.text('Arredondamento do fundo'), findsOneWidget);
  });

  testWidgets('sem foto animada, o download não pergunta formato nenhum', (
    tester,
  ) async {
    // Só com PNGs parados a montagem tem uma saída possível — a folha de
    // formato seria uma pergunta com uma resposta só.
    tester.view.physicalSize = const Size(900, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(MaterialApp(home: CollagePage(photos: photos)));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Salvar na galeria'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Exportar'), findsNothing);
    expect(find.text('GIF'), findsNothing);
  });

  testWidgets('fundo com alvo "Fotos" muda só as fotos, não a montagem', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(400, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(MaterialApp(home: CollagePage(photos: photos)));
    await tester.pumpAndSettle();

    final page = find.byType(Scrollable).first;
    await tester.scrollUntilVisible(find.text('Fundo'), 200, scrollable: page);
    await tester.tap(find.text('Fundo'));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(ChoiceChip, 'Fotos'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ChoiceChip, 'Cor'));
    await tester.pumpAndSettle();

    final cells = tester.widgetList<CollageCellView>(
      find.byType(CollageCellView),
    );
    expect(cells, isNotEmpty);
    for (final view in cells) {
      expect(view.cell.background.mode, CollageBackgroundMode.color);
    }

    // Voltando o alvo para "Montagem", o fundo da montagem continua
    // transparente: as duas escolhas são independentes.
    await tester.tap(find.widgetWithText(ChoiceChip, 'Montagem'));
    await tester.pumpAndSettle();
    final transparentChip = tester.widget<ChoiceChip>(
      find.widgetWithText(ChoiceChip, 'Transparente'),
    );
    expect(transparentChip.selected, isTrue);
  });
}
