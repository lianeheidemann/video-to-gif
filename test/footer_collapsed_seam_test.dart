import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:video_to_gif/core/models/conversion_settings.dart';
import 'package:video_to_gif/core/models/photo_info.dart';
import 'package:video_to_gif/core/models/video_info.dart';
import 'package:video_to_gif/core/ui/editor_tabs_footer.dart';
import 'package:video_to_gif/features/collage/collage_page.dart';
import 'package:video_to_gif/features/video/editor_page.dart';

// Recolhido, o rodapé tem que ler como um bloco só: a tira da alça empresta a
// cor da barra de abas, e as duas dividem uma única linha de topo.
//
// Antes cada uma trazia cor e borda próprias. Recolhido, isso desenhava duas
// linhas paralelas a 17px uma da outra com uma faixa de outro tom entre elas —
// na tela não lia como parte do controle, e sim como falha de renderização em
// volta da alça.

const _video = VideoInfo(
  path: '/tmp/video-inexistente-para-teste.mp4',
  fileName: 'video.mp4',
  rawWidth: 1920,
  rawHeight: 1080,
  durationSeconds: 10,
  frameRate: 30,
  bitrateBps: 1000000,
  fileSizeBytes: 1000000,
  codec: 'h264',
);

/// A tira que contém a alça de recolher — o `Container` que embrulha o gesto.
BoxDecoration _tiraDaAlca(WidgetTester tester, Finder alca) =>
    tester
            .widgetList<Container>(
              find.ancestor(of: alca, matching: find.byType(Container)),
            )
            .first
            .decoration
        as BoxDecoration;

/// A barra das abas — o único `Container` do rodapé com altura fixa de 60.
BoxDecoration _barraDeAbas(WidgetTester tester) =>
    tester
            .widgetList<Container>(
              find.byWidgetPredicate(
                (w) =>
                    w is Container &&
                    w.constraints?.minHeight == 60 &&
                    w.constraints?.maxHeight == 60,
              ),
            )
            .first
            .decoration
        as BoxDecoration;

bool _temLinhaDeTopo(BoxDecoration d) {
  final topo = d.border?.top;
  return topo != null && topo.width > 0 && topo.style != BorderStyle.none;
}

void _conferir(WidgetTester tester, Finder alca, {required bool recolhido}) {
  final tema = ThemeData();
  final tira = _tiraDaAlca(tester, alca);
  final barra = _barraDeAbas(tester);

  // A linha que separa o rodapé da prévia é sempre a da tira.
  expect(_temLinhaDeTopo(tira), isTrue);

  if (recolhido) {
    // Uma linha só: a barra não desenha a dela, senão sobrariam duas a 17px
    // de distância com uma faixa de outro tom no meio.
    expect(_temLinhaDeTopo(barra), isFalse);
    // E a faixa some porque a tira passa a ter o fundo da própria barra.
    expect(tira.color, barra.color);
    expect(tira.color, tema.colorScheme.surface);
  } else {
    // Aberto, o painel é uma folha sobre a barra: cor própria e as duas
    // linhas separando prévia/painel e painel/barra.
    expect(_temLinhaDeTopo(barra), isTrue);
    expect(tira.color, tema.colorScheme.surfaceContainerLow);
    expect(tira.color, isNot(barra.color));
  }
}

Future<void> _writeSolidPng(String path, int size) async {
  final recorder = ui.PictureRecorder();
  Canvas(recorder).drawRect(
    Rect.fromLTWH(0, 0, size.toDouble(), size.toDouble()),
    Paint()..color = const Color(0xFFFF0000),
  );
  final picture = recorder.endRecording();
  final image = await picture.toImage(size, size);
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

  // As fotos nascem aqui, fora do `testWidgets`: o binding de teste roda numa
  // zona assíncrona falsa, e E/S de verdade lá dentro nunca completa.
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    tempDir = await Directory.systemTemp.createTemp('footer_seam_test');
    photos = [];
    for (var i = 0; i < 2; i++) {
      final path = '${tempDir.path}/foto_$i.png';
      await _writeSolidPng(path, 60);
      photos.add(PhotoInfo(path: path, width: 60, height: 60));
    }
  });

  tearDown(() async {
    if (await tempDir.exists()) await tempDir.delete(recursive: true);
  });

  testWidgets('Editar GIF: recolhido, alça e barra viram um bloco só', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: EditorPage(
          video: _video,
          initialSettings: ConversionSettings.recommendedFor(_video),
        ),
      ),
    );
    // O player nunca inicializa em teste (sem plugin real); dá tempo de ele
    // desistir antes de seguir.
    await tester.pump(const Duration(seconds: 1));

    final alca = find
        .descendant(
          of: find.byType(EditorTabsFooter),
          matching: find.byType(GestureDetector),
        )
        .first;

    _conferir(tester, alca, recolhido: false);

    await tester.tap(alca, warnIfMissed: false);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    _conferir(tester, alca, recolhido: true);

    // Reabrir devolve a folha, sem deixar resíduo do estado recolhido.
    await tester.tap(alca, warnIfMissed: false);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    _conferir(tester, alca, recolhido: false);
  });

  testWidgets('Montagem: recolhido, alça e barra viram um bloco só', (
    tester,
  ) async {
    // Tela alta o bastante para prévia, painel e barra caberem juntos — a
    // prévia da montagem já é quadrada e mais alta que a janela padrão do
    // flutter_test.
    tester.view.physicalSize = const Size(900, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(MaterialApp(home: CollagePage(photos: photos)));
    await tester.pumpAndSettle();

    final alca = find.byKey(const ValueKey('collagePanelHandle'));

    _conferir(tester, alca, recolhido: false);

    await tester.tap(alca, warnIfMissed: false);
    await tester.pumpAndSettle();
    _conferir(tester, alca, recolhido: true);

    await tester.tap(alca, warnIfMissed: false);
    await tester.pumpAndSettle();
    _conferir(tester, alca, recolhido: false);
  });
}
