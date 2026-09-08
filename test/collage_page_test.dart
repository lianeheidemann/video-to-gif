import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:video_to_gif/models/photo_info.dart';
import 'package:video_to_gif/ui/collage_page.dart';

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
        find.text('Duplicar'),
        -200,
        scrollable: page,
      );
      expect(find.text('Duplicar'), findsOneWidget);

      await tester.tap(find.byTooltip('Desfazer'));
      await tester.pumpAndSettle();

      // O texto deixou de existir: a barra não pode continuar na tela
      // apontando para ele, com todos os botões sem efeito nenhum.
      expect(find.text('oi'), findsNothing);
      expect(find.text('Duplicar'), findsNothing);
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
    expect(find.text('Duplicar'), findsOneWidget);
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
}
