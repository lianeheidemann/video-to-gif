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
import 'package:video_to_gif/ui/widgets/collage_overlay_view.dart';
import 'package:video_to_gif/ui/widgets/color_adjust_controls.dart';
import 'package:video_to_gif/ui/widgets/folder_tab.dart';
import 'package:video_to_gif/ui/widgets/target_sub_panel.dart';

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

/// Repete `pump` até [finder] achar algo, em vez de um `pump`/`pumpAndSettle`
/// só — nenhum dos dois espera de verdade quando o trabalho pendente é E/S
/// pura (ler e decodificar arquivo) sem nenhum quadro agendado no meio.
Future<void> _pumpUntilFound(
  WidgetTester tester,
  Finder finder, {
  Duration timeout = const Duration(seconds: 30),
}) async {
  final stopwatch = Stopwatch()..start();
  while (finder.evaluate().isEmpty && stopwatch.elapsed < timeout) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pump(const Duration(milliseconds: 50));
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
      await tester.enterText(find.byType(TextField), 'oi');
      await tester.pump();
      await tester.tap(find.byTooltip('Adicionar texto'));
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

  testWidgets(
    'o nome da aba não se repete no topo do painel — a aba do rodapé já '
    'basta',
    (tester) async {
      tester.view.physicalSize = const Size(900, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(MaterialApp(home: CollagePage(photos: photos)));
      await tester.pumpAndSettle();

      // "Layout" já começa aberta: só a aba do rodapé mostra o nome, uma
      // vez só — não mais o painel repetindo por cima.
      expect(find.text('Layout'), findsOneWidget);

      await tester.tap(find.text('Margem'));
      await tester.pumpAndSettle();
      expect(find.text('Margem'), findsOneWidget);
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

    // A pasta "Reações" (aberta por padrão) já mostra seus stickers
    // embutidos.
    expect(find.byType(SvgPicture), findsWidgets);

    await tester.tap(find.byType(SvgPicture).first);
    await tester.pumpAndSettle();

    // Adicionar um sticker já o seleciona — a barra de ações aparece.
    expect(find.byTooltip('Duplicar'), findsOneWidget);
  });

  testWidgets(
    'stickers embutidos ficam em pastas temáticas, e "Importar" só na pasta '
    '"Importados"',
    (tester) async {
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

      // Sem a dica de texto antiga — as pastas substituem essa explicação.
      expect(
        find.text('Toque para adicionar um sticker à montagem.'),
        findsNothing,
      );

      // As 4 pastas existem, e "Importar" só aparece dentro de "Importados".
      for (final label in ['Reações', 'Símbolos', 'Efeitos', 'Importados']) {
        expect(find.widgetWithText(FolderTab, label), findsOneWidget);
      }
      expect(find.text('Importar'), findsNothing);

      // "Reações" (padrão) mostra 2 stickers (Joinha, Sorriso) — os
      // ícones não têm rótulo visível, então a checagem é pela contagem
      // de SVGs.
      expect(find.byType(SvgPicture), findsNWidgets(2));

      await tester.tap(find.widgetWithText(FolderTab, 'Símbolos'));
      await tester.pumpAndSettle();
      expect(find.byType(SvgPicture), findsNWidgets(2));

      await tester.tap(find.widgetWithText(FolderTab, 'Efeitos'));
      await tester.pumpAndSettle();
      expect(find.byType(SvgPicture), findsNWidgets(1));

      await tester.tap(find.widgetWithText(FolderTab, 'Importados'));
      await tester.pumpAndSettle();
      expect(find.text('Importar'), findsOneWidget);
      // Sem nada importado ainda, só o tile "Importar" aparece — nenhum SVG
      // embutido vaza para essa pasta.
      expect(find.byType(SvgPicture), findsNothing);
    },
  );

  testWidgets('pastas e miniaturas da aba Stickers são pequenas', (
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

    // Bem menores que o padrão de 62×46 usado pelo seletor de imagem de
    // fundo — é justamente o ponto do pedido ("bem menor, principalmente
    // as stickers").
    final folderSize = tester.getSize(
      find.widgetWithText(FolderTab, 'Reações'),
    );
    expect(folderSize.height, lessThan(50));

    final thumbSize = tester.getSize(
      find
          .ancestor(
            of: find.byType(SvgPicture).first,
            matching: find.byType(Container),
          )
          .first,
    );
    expect(thumbSize.width, lessThanOrEqualTo(44));
    expect(thumbSize.height, lessThanOrEqualTo(36));
  });

  testWidgets('alça do item selecionado continua funcionando mesmo coberta por '
      'outro sticker por cima', (tester) async {
    // Reproduz o bug relatado: dois stickers na mesma posição (o padrão
    // de todo sticker novo), o de cima (zIndex maior) tapando o canto do
    // selecionado, que está por baixo — antes disso bloqueava a alça,
    // porque ela morava dentro da pilha por zIndex.
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

    // Sticker A: primeiro da pasta "Reações".
    await tester.tap(find.byType(SvgPicture).first);
    await tester.pumpAndSettle();

    // Sticker B: o segundo — nasce na mesma posição de A (0.5, 0.5) e
    // fica selecionado, por cima (zIndex maior).
    await tester.tap(find.byType(SvgPicture).at(1));
    await tester.pumpAndSettle();

    // Manda B para trás: ele continua selecionado, mas agora A (que não
    // se move) fica por cima, cobrindo o canto de B por completo.
    await tester.scrollUntilVisible(
      find.byTooltip('Trás'),
      -200,
      scrollable: page,
    );
    await tester.tap(find.byTooltip('Trás'));
    await tester.pumpAndSettle();

    Widget selectedOverlay() => tester
        .widgetList<CollageOverlayView>(find.byType(CollageOverlayView))
        .firstWhere((w) => w.selected);

    final before = selectedOverlay() as CollageOverlayView;
    expect(before.scale, 1.0);
    expect(before.rotation, 0.0);

    final resizeHandle = find.byIcon(Icons.open_in_full_rounded);
    expect(resizeHandle, findsOneWidget);
    await tester.dragFrom(tester.getCenter(resizeHandle), const Offset(40, 40));
    await tester.pumpAndSettle();

    final afterResize = selectedOverlay() as CollageOverlayView;
    expect(afterResize.scale, greaterThan(before.scale));

    final rotateHandle = find.byIcon(Icons.rotate_right_rounded);
    expect(rotateHandle, findsOneWidget);
    await tester.dragFrom(tester.getCenter(rotateHandle), const Offset(0, 40));
    await tester.pumpAndSettle();

    final afterRotate = selectedOverlay() as CollageOverlayView;
    expect(afterRotate.rotation, greaterThan(0));
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
    // Pelo chip, e não pelo texto solto: "Cor" também é o rótulo de uma aba
    // do rodapé, e o que este teste checa são os três botões do painel.
    expect(find.widgetWithText(ChoiceChip, 'Transparente'), findsOneWidget);
    expect(find.widgetWithText(ChoiceChip, 'Cor'), findsOneWidget);
    expect(find.widgetWithText(ChoiceChip, 'Imagem'), findsOneWidget);
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

  testWidgets('duplo toque num ícone de "Ajustar cor" zera só aquele ajuste', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(900, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(MaterialApp(home: CollagePage(photos: photos)));
    await tester.pumpAndSettle();

    final gesture = await tester.startGesture(
      tester.getCenter(find.byIcon(Icons.more_horiz_rounded).first),
    );
    await tester.pump(const Duration(milliseconds: 60));
    await gesture.up();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Ajustar cor'));
    await tester.pumpAndSettle();

    ColorAdjustButton contrasteButton() => tester
        .widgetList<ColorAdjustButton>(find.byType(ColorAdjustButton))
        .firstWhere(
          (button) => button.adjustment == CollageColorAdjustment.contrast,
        );

    // Seleciona "Contraste" e arrasta a régua para um valor não-zero.
    contrasteButton().onTap();
    await tester.pumpAndSettle();
    await tester.drag(find.byType(IntensityRuler), const Offset(-80, 0));
    await tester.pumpAndSettle();

    final beforeReset = tester
        .widgetList<CollageCellView>(find.byType(CollageCellView))
        .first
        .cell;
    expect(beforeReset.contrast, isNot(0));

    // Duplo toque no ícone "Contraste" zera só esse ajuste.
    contrasteButton().onDoubleTap!.call();
    await tester.pumpAndSettle();

    final afterReset = tester
        .widgetList<CollageCellView>(find.byType(CollageCellView))
        .first
        .cell;
    expect(afterReset.contrast, 0);
    expect(find.text('0'), findsOneWidget);
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
    await tester.enterText(find.byType(TextField), 'oi');
    await tester.pump();
    await tester.tap(find.byTooltip('Adicionar texto'));
    await tester.pumpAndSettle();

    // Com o texto recém-criado selecionado, o painel mostra os controles de
    // estilo dele.
    expect(find.text('Cor do texto'), findsOneWidget);
    expect(find.text('Fundo do texto'), findsOneWidget);
    expect(find.text('Arredondamento'), findsNothing);

    // O painel tem teto de altura e rola por dentro: o interruptor pode
    // estar abaixo do corte.
    await tester.ensureVisible(find.byType(Switch));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();

    // Dentro da caixa agrupada os rótulos são curtos ("Cor", não "Cor do
    // fundo do texto") — "Cor" também é o nome da aba do rodapé, daí as duas
    // ocorrências.
    expect(find.text('Cor'), findsNWidgets(2));
    expect(find.text('Arredondamento'), findsOneWidget);
  });

  testWidgets('sem foto animada, o download só pergunta o tamanho', (
    tester,
  ) async {
    // Só com PNGs parados a montagem tem uma saída possível — a folha não
    // pergunta formato (seria uma pergunta com uma resposta só), mas ainda
    // abre para deixar escolher o tamanho da exportação.
    tester.view.physicalSize = const Size(900, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(MaterialApp(home: CollagePage(photos: photos)));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Salvar na galeria'));
    // A folha só abre depois de ler e decodificar cada foto (E/S de
    // verdade) — um `pumpAndSettle` sozinho pode devolver antes disso
    // terminar, porque nada agenda um novo quadro enquanto só se espera por
    // E/S. Repete `pump` até o título da folha aparecer, em vez de assumir
    // que um `pump`/`pumpAndSettle` já é tempo suficiente.
    await _pumpUntilFound(tester, find.text('Exportar'));

    expect(find.text('Exportar'), findsOneWidget);
    expect(find.text('Tamanho'), findsOneWidget);
    expect(find.text('Padrão'), findsOneWidget);
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

  testWidgets(
    'aba "Margem" mostra as três de uma vez e ajusta cada uma sozinha',
    (tester) async {
      tester.view.physicalSize = const Size(900, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(MaterialApp(home: CollagePage(photos: photos)));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Margem').last);
      await tester.pumpAndSettle();

      // Uma linha por margem, todas na tela ao mesmo tempo: "Tudo",
      // "Externa" e "Entre fotos", nessa ordem.
      final sliders = find.byType(Slider);
      expect(sliders, findsNWidgets(3));
      for (final label in ['Tudo', 'Externa', 'Entre fotos']) {
        expect(find.byTooltip(label), findsOneWidget);
      }

      double sliderValue(int index) =>
          tester.widget<Slider>(sliders.at(index)).value;

      final initialOuter = sliderValue(1);
      final initialAll = sliderValue(0);

      // Mexer na linha "Entre fotos" não move a externa, nem "Tudo" — antes
      // "Tudo" mostrava a média das outras duas a cada rebuild, então o
      // próprio slider se movia sozinho sem ninguém tocar nele.
      await tester.drag(sliders.at(2), const Offset(120, 0));
      await tester.pumpAndSettle();
      expect(sliderValue(2), isNot(closeTo(initialOuter, 0.001)));
      expect(sliderValue(1), closeTo(initialOuter, 0.001));
      expect(sliderValue(0), closeTo(initialAll, 0.001));

      // "Tudo" iguala as duas ao valor arrastado.
      await tester.drag(sliders.at(0), const Offset(60, 0));
      await tester.pumpAndSettle();
      expect(sliderValue(1), closeTo(sliderValue(0), 0.001));
      expect(sliderValue(2), closeTo(sliderValue(0), 0.001));

      // O botão da direita zera tudo de uma vez.
      await tester.tap(find.byTooltip('Zerar margens'));
      await tester.pumpAndSettle();
      expect(sliderValue(0), 0);
      expect(sliderValue(1), 0);
      expect(sliderValue(2), 0);
    },
  );

  testWidgets('a seleção de um texto só aparece com a aba "Texto" aberta', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(900, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(MaterialApp(home: CollagePage(photos: photos)));
    await tester.pumpAndSettle();

    // Cria um texto pela aba "Texto" — ele já nasce selecionado.
    await tester.tap(find.text('Texto'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'oi');
    await tester.pump();
    await tester.tap(find.byTooltip('Adicionar texto'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Duplicar'), findsOneWidget);

    // Com outra aba aberta, o texto continua na prévia mas sem nenhum
    // controle de seleção: nem a barra de ações, nem a moldura roxa da
    // CollageOverlayView (que fora da aba dona não responde a gesto).
    await tester.tap(find.text('Fundo'));
    await tester.pumpAndSettle();
    expect(find.text('oi'), findsOneWidget);
    expect(find.byTooltip('Duplicar'), findsNothing);
    expect(
      tester
          .widgetList<CollageOverlayView>(find.byType(CollageOverlayView))
          .every((overlay) => !overlay.selected),
      isTrue,
    );

    // Voltando para "Texto", a seleção guardada reaparece no mesmo texto —
    // trocar de aba esconde, não solta a seleção.
    await tester.tap(find.text('Texto'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Duplicar'), findsOneWidget);
    expect(
      tester
          .widgetList<CollageOverlayView>(find.byType(CollageOverlayView))
          .where((overlay) => overlay.selected),
      hasLength(1),
    );
  });

  testWidgets('pasta criada pelo usuário aparece na barra e pode ser apagada', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(900, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(MaterialApp(home: CollagePage(photos: photos)));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Stickers'));
    await tester.pumpAndSettle();

    // A barra de pastas rola: "Nova pasta" fica no fim dela.
    final folderBar = find.byType(Scrollable).first;
    await tester.scrollUntilVisible(
      find.widgetWithText(FolderTab, 'Nova pasta'),
      200,
      scrollable: folderBar,
    );
    await tester.ensureVisible(find.widgetWithText(FolderTab, 'Nova pasta'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FolderTab, 'Nova pasta'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Xícaras');
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();

    expect(find.widgetWithText(FolderTab, 'Xícaras'), findsOneWidget);
    // Pasta criada começa vazia: só o tile de importar.
    expect(find.text('Importar'), findsOneWidget);

    // Segurar abre o menu com renomear/apagar — só as criadas têm esse gesto.
    await tester.scrollUntilVisible(
      find.widgetWithText(FolderTab, 'Xícaras'),
      200,
      scrollable: folderBar,
    );
    await tester.longPress(find.widgetWithText(FolderTab, 'Xícaras'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Apagar'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Apagar'));
    await tester.pumpAndSettle();

    expect(find.widgetWithText(FolderTab, 'Xícaras'), findsNothing);
    // Sem a pasta aberta, a barra cai em "Importados" em vez de ficar sem
    // nenhuma pasta marcada.
    final imported = tester.widget<FolderTab>(
      find.widgetWithText(FolderTab, 'Importados'),
    );
    expect(imported.selected, isTrue);
  });

  testWidgets(
    'criar uma pasta rola a fileira até ela, sem precisar rolar na mão',
    (tester) async {
      tester.view.physicalSize = const Size(900, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(MaterialApp(home: CollagePage(photos: photos)));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Stickers'));
      await tester.pumpAndSettle();

      final page = find.byType(Scrollable).first;

      // Cria várias pastas: com só uma, a fileira inteira já cabe na tela e
      // o teste não provaria nada — a pasta nova precisa nascer longe do
      // que já está visível para a rolagem automática ter algo a fazer.
      for (var i = 0; i < 6; i++) {
        await tester.scrollUntilVisible(
          find.widgetWithText(FolderTab, 'Nova pasta'),
          200,
          scrollable: page,
        );
        await tester.tap(find.widgetWithText(FolderTab, 'Nova pasta'));
        await tester.pumpAndSettle();
        await tester.enterText(find.byType(TextField), 'Pasta $i');
        await tester.tap(find.text('OK'));
        await tester.pumpAndSettle();
      }

      // Sem rolar a fileira de pastas na mão: a última criada precisa já
      // estar visível, porque criar uma pasta rola até ela sozinho.
      expect(find.widgetWithText(FolderTab, 'Pasta 5'), findsOneWidget);
    },
  );

  testWidgets(
    'modos de fundo ficam dentro da caixa do alvo, com os dois alvos',
    (tester) async {
      tester.view.physicalSize = const Size(900, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(MaterialApp(home: CollagePage(photos: photos)));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Fundo'));
      await tester.pumpAndSettle();

      // "Transparente/Cor/Imagem" configuram o alvo escolhido em cima, então
      // precisam estar dentro da caixa dele — é isso que deixa claro que são
      // sub-opções, e não opções de mesmo nível.
      for (final label in ['Transparente', 'Cor', 'Imagem']) {
        expect(
          find.descendant(
            of: find.byType(TargetSubPanel),
            matching: find.widgetWithText(ChoiceChip, label),
          ),
          findsOneWidget,
        );
      }
      // "Montagem" começa como o alvo escolhido.
      final panel = tester.widget<TargetSubPanel>(find.byType(TargetSubPanel));
      expect(panel.selectedIndex, 0);

      await tester.tap(find.widgetWithText(ChoiceChip, 'Fotos'));
      await tester.pumpAndSettle();

      expect(
        tester
            .widget<TargetSubPanel>(find.byType(TargetSubPanel))
            .selectedIndex,
        1,
      );
      // Trocar de alvo mantém os três modos na caixa — muda o que eles
      // configuram, não onde moram.
      expect(
        find.descendant(
          of: find.byType(TargetSubPanel),
          matching: find.widgetWithText(ChoiceChip, 'Transparente'),
        ),
        findsOneWidget,
      );
    },
  );
  testWidgets('lápis edita o texto no próprio painel, sem abrir diálogo', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(900, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(MaterialApp(home: CollagePage(photos: photos)));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Texto'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'oi');
    await tester.pump();
    await tester.tap(find.byTooltip('Adicionar texto'));
    await tester.pumpAndSettle();
    expect(find.text('oi'), findsOneWidget);

    // O lápis traz a frase para o mesmo campo do painel — nenhuma janela
    // nova aparece.
    await tester.tap(find.byTooltip('Editar'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller?.text,
      'oi',
    );

    await tester.enterText(find.byType(TextField), 'tchau');
    await tester.pump();
    await tester.tap(find.byTooltip('Salvar texto'));
    await tester.pumpAndSettle();

    expect(find.text('tchau'), findsOneWidget);
    expect(find.text('oi'), findsNothing);
  });

  testWidgets('recolher o painel mantém o sticker selecionado e manipulável', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(900, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(MaterialApp(home: CollagePage(photos: photos)));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Stickers'));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(SvgPicture).first);
    await tester.pumpAndSettle();

    // Com a aba aberta, o sticker está selecionado e responde a gesto.
    CollageOverlayView overlay() =>
        tester.widget<CollageOverlayView>(find.byType(CollageOverlayView));
    expect(overlay().selected, isTrue);
    expect(overlay().interactive, isTrue);
    expect(find.widgetWithText(FolderTab, 'Reações'), findsOneWidget);

    // Puxar a alça para baixo encolhe o painel: os controles somem...
    await tester.drag(find.byType(SvgPicture).last, const Offset(0, 200));
    await tester.pumpAndSettle();
    await tester.fling(
      find.byKey(const ValueKey('collagePanelHandle')),
      const Offset(0, 60),
      800,
    );
    await tester.pumpAndSettle();
    expect(find.widgetWithText(FolderTab, 'Reações'), findsNothing);

    // ...mas a aba continua sendo a aba aberta, então o sticker segue
    // selecionado e movimentável — é o ponto do gesto.
    expect(overlay().selected, isTrue);
    expect(overlay().interactive, isTrue);

    // Puxar de volta para cima traz os controles.
    await tester.fling(
      find.byKey(const ValueKey('collagePanelHandle')),
      const Offset(0, -60),
      800,
    );
    await tester.pumpAndSettle();
    expect(find.widgetWithText(FolderTab, 'Reações'), findsOneWidget);
  });

  testWidgets('pastas "GitHub" e "Black" existem e recebem importados', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(900, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(MaterialApp(home: CollagePage(photos: photos)));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Stickers'));
    await tester.pumpAndSettle();

    for (final label in ['GitHub', 'Black']) {
      final folder = find.widgetWithText(FolderTab, label);
      expect(folder, findsOneWidget);
      await tester.scrollUntilVisible(
        folder,
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.ensureVisible(folder);
      await tester.pumpAndSettle();
      await tester.tap(folder);
      await tester.pumpAndSettle();
      if (label == 'GitHub') {
        // Já vem com a arte embutida na fileira (o tile "Importar" fica no
        // fim dela, fora da tela — a lista é preguiçosa).
        expect(find.byType(SvgPicture), findsWidgets);
      } else {
        // Ainda sem arte: só o tile de importar.
        expect(find.text('Importar'), findsOneWidget);
        expect(find.byType(SvgPicture), findsNothing);
      }
    }
  });
}
