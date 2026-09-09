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

  testWidgets(
    'aba "Margem" ajusta margem externa e entre fotos de forma independente',
    (tester) async {
      tester.view.physicalSize = const Size(900, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(MaterialApp(home: CollagePage(photos: photos)));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Margem').last);
      await tester.pumpAndSettle();

      expect(find.widgetWithText(ChoiceChip, 'Tudo'), findsOneWidget);
      expect(find.widgetWithText(ChoiceChip, 'Externa'), findsOneWidget);
      expect(find.widgetWithText(ChoiceChip, 'Entre fotos'), findsOneWidget);

      // As duas margens começam iguais, então "Externa" e "Entre fotos"
      // mostram o mesmo valor inicial que "Tudo".
      final initial = tester.widget<Slider>(find.byType(Slider)).value;

      // Mexe só na margem externa.
      await tester.tap(find.widgetWithText(ChoiceChip, 'Externa'));
      await tester.pumpAndSettle();
      await tester.drag(find.byType(Slider), const Offset(-120, 0));
      await tester.pumpAndSettle();
      final outerAfter = tester.widget<Slider>(find.byType(Slider)).value;
      expect(outerAfter, isNot(closeTo(initial, 0.001)));

      // "Entre fotos" continua no valor original — não foi mexida.
      await tester.tap(find.widgetWithText(ChoiceChip, 'Entre fotos'));
      await tester.pumpAndSettle();
      final innerStill = tester.widget<Slider>(find.byType(Slider)).value;
      expect(innerStill, closeTo(initial, 0.001));

      // Mexe só na margem entre fotos agora.
      await tester.drag(find.byType(Slider), const Offset(120, 0));
      await tester.pumpAndSettle();
      final innerAfter = tester.widget<Slider>(find.byType(Slider)).value;
      expect(innerAfter, isNot(closeTo(initial, 0.001)));

      // "Externa" continua no valor que ficou antes, intacta pela mexida
      // acima.
      await tester.tap(find.widgetWithText(ChoiceChip, 'Externa'));
      await tester.pumpAndSettle();
      final outerStill = tester.widget<Slider>(find.byType(Slider)).value;
      expect(outerStill, closeTo(outerAfter, 0.001));

      // "Tudo" iguala as duas ao valor arrastado.
      await tester.tap(find.widgetWithText(ChoiceChip, 'Tudo'));
      await tester.pumpAndSettle();
      await tester.drag(find.byType(Slider), const Offset(60, 0));
      await tester.pumpAndSettle();
      final bothValue = tester.widget<Slider>(find.byType(Slider)).value;

      await tester.tap(find.widgetWithText(ChoiceChip, 'Externa'));
      await tester.pumpAndSettle();
      expect(
        tester.widget<Slider>(find.byType(Slider)).value,
        closeTo(bothValue, 0.001),
      );

      await tester.tap(find.widgetWithText(ChoiceChip, 'Entre fotos'));
      await tester.pumpAndSettle();
      expect(
        tester.widget<Slider>(find.byType(Slider)).value,
        closeTo(bothValue, 0.001),
      );
    },
  );

  testWidgets(
    'a seleção de um texto só aparece com a aba "Texto" aberta',
    (tester) async {
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
    },
  );

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

    // O botão do fim da linha pede o nome e já abre a pasta nova.
    await tester.tap(find.widgetWithText(FolderTab, 'Nova pasta'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Xícaras');
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();

    expect(find.widgetWithText(FolderTab, 'Xícaras'), findsOneWidget);
    // Pasta criada começa vazia: só o tile de importar.
    expect(find.text('Importar'), findsOneWidget);

    // Segurar abre o menu com renomear/apagar — só as criadas têm esse gesto.
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
        tester.widget<TargetSubPanel>(find.byType(TargetSubPanel)).selectedIndex,
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
\n
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
}
