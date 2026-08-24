import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:video_to_gif/models/conversion_settings.dart';
import 'package:video_to_gif/models/frame_settings.dart';
import 'package:video_to_gif/models/video_info.dart';
import 'package:video_to_gif/ui/editor_page.dart';

// A aba "Frame" tem duas famílias de moldura em caixas separadas — as
// procedurais ("Moldura") e as artes prontas ("Molduras de imagem") — e só
// uma pode estar ativa por vez. Cada fileira tem a sua própria miniatura
// "Sem moldura" e mostra sempre exatamente uma opção marcada: é assim que se
// vê que escolher de um lado desativou o outro. Estes testes garantem que as
// duas fileiras sempre aparecem, sem exceção, e que essa exclusão mútua vale
// nos dois sentidos.
const _video = VideoInfo(
  path: '/tmp/video-inexistente-para-teste.mp4',
  fileName: 'video.mp4',
  rawWidth: 640,
  rawHeight: 360,
  durationSeconds: 10,
  frameRate: 30,
  bitrateBps: 1000000,
  fileSizeBytes: 1000000,
  codec: 'h264',
);

Finder _checkIn(String key) => find.descendant(
  of: find.byKey(ValueKey(key)),
  matching: find.byIcon(Icons.check_rounded),
);

Future<void> _openFrameSection(WidgetTester tester) async {
  // Viewport retrato: em paisagem o app esconde as abas "Ajustar"/"Frame"
  // para aproveitar o espaço vertical, e o tamanho padrão de teste
  // (800x600) é "paisagem".
  tester.view.physicalSize = const Size(1080, 5000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final settings = ConversionSettings.recommendedFor(_video);
  await tester.pumpWidget(
    MaterialApp(
      home: EditorPage(video: _video, initialSettings: settings),
    ),
  );
  // O player de vídeo nunca inicializa em teste (sem plugin real); dá
  // tempo dele desistir e marcar `_previewFailed` antes de seguir.
  await tester.pump(const Duration(seconds: 1));

  await tester.tap(find.text('Frame'));
  await tester.pump();
  // As duas famílias moram em seções recolhidas separadas; abrir as duas.
  await tester.tap(find.text('Moldura'));
  await tester.pump();
  await tester.tap(find.text('Molduras de imagem'));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}

void main() {
  test('o fundo transparente vem ligado por padrão', () {
    expect(const FrameSettings().transparentBackground, isTrue);
  });

  testWidgets('as duas fileiras de moldura aparecem juntas, sem erro', (
    tester,
  ) async {
    await _openFrameSection(tester);

    expect(tester.takeException(), isNull);
    for (final key in [
      'frameStyleThumb_none',
      'frameStyleThumb_thin',
      'frameStyleThumb_medium',
      'frameStyleThumb_thick',
      'imageFrameThumb_none',
      'imageFrameThumb_bundled_transparente',
      'imageFrameThumb_bundled_graphite',
      'imageFrameThumb_bundled_titanio',
      'imageFrameThumb_bundled_ceramica',
      'imageFrameThumb_bundled_neon',
      'imageFrameThumb_bundled_rose_gold',
    ]) {
      expect(
        find.byKey(ValueKey(key)),
        findsOneWidget,
        reason: '$key deveria estar na tela',
      );
    }
  });

  testWidgets('escolher numa fileira volta a outra para "Sem moldura"', (
    tester,
  ) async {
    await _openFrameSection(tester);

    expect(
      _checkIn('frameStyleThumb_none'),
      findsOneWidget,
      reason: 'sem nada escolhido, as duas fileiras começam em "Sem moldura"',
    );
    expect(_checkIn('imageFrameThumb_none'), findsOneWidget);

    await tester.tap(
      find.byKey(const ValueKey('imageFrameThumb_bundled_titanio')),
    );
    await tester.pump();

    expect(
      _checkIn('imageFrameThumb_bundled_titanio'),
      findsOneWidget,
      reason: 'a moldura de imagem escolhida fica marcada',
    );
    expect(
      _checkIn('imageFrameThumb_none'),
      findsNothing,
      reason: '"Sem moldura" da fileira de imagem sai de marcada',
    );
    expect(
      _checkIn('frameStyleThumb_none'),
      findsOneWidget,
      reason: 'a fileira de moldura volta para "Sem moldura"',
    );
    expect(
      find.text('Titânio'),
      findsWidgets,
      reason: 'o resumo da seção deve refletir a moldura de imagem ativa',
    );

    await tester.tap(find.byKey(const ValueKey('frameStyleThumb_medium')));
    await tester.pump();

    expect(
      _checkIn('frameStyleThumb_medium'),
      findsOneWidget,
      reason: 'a moldura procedural escolhida fica marcada',
    );
    expect(
      _checkIn('frameStyleThumb_none'),
      findsNothing,
      reason: '"Sem moldura" da fileira procedural sai de marcada',
    );
    expect(
      _checkIn('imageFrameThumb_bundled_titanio'),
      findsNothing,
      reason: 'a moldura de imagem é desativada',
    );
    expect(
      _checkIn('imageFrameThumb_none'),
      findsOneWidget,
      reason: 'a fileira de imagem volta para "Sem moldura"',
    );
  });

  testWidgets(
    'ajuste do conteúdo e resolução só aparecem com moldura de imagem ativa',
    (tester) async {
      await _openFrameSection(tester);

      expect(find.text('Ajuste do conteúdo'), findsNothing);
      expect(find.text('Resolução da moldura'), findsNothing);

      await tester.tap(
        find.byKey(const ValueKey('imageFrameThumb_bundled_titanio')),
      );
      await tester.pump();

      expect(find.text('Ajuste do conteúdo'), findsOneWidget);
      expect(find.text('Resolução da moldura'), findsOneWidget);
    },
  );

  testWidgets(
    'zoom aparece somente em Expandir sem cortar e vai de 10% a 300%',
    (tester) async {
      await _openFrameSection(tester);
      await tester.tap(
        find.byKey(const ValueKey('imageFrameThumb_bundled_titanio')),
      );
      await tester.pump(const Duration(milliseconds: 300));

      final contentHeader = find.text('Ajuste do conteúdo');
      await tester.tap(contentHeader);
      await tester.pump(const Duration(milliseconds: 300));

      expect(
        find.byKey(const ValueKey('frameContentZoomSlider')),
        findsNothing,
        reason: 'o modo automático não deve permitir zoom',
      );
      expect(find.byKey(const ValueKey('contentFitTile_auto')), findsOneWidget);
      expect(find.byKey(const ValueKey('contentFitTile_fill')), findsOneWidget);
      expect(
        find.byKey(const ValueKey('contentFitTile_expand')),
        findsOneWidget,
      );
      expect(
        find.text('Encaixar'),
        findsNothing,
        reason: 'Encaixar duplicava o comportamento do ajuste automático',
      );
      expect(find.text('Melhor enquadramento para o vídeo'), findsNothing);
      expect(find.text('Preenche toda a moldura (pode cortar)'), findsNothing);
      expect(find.text('Preenche com fundo estendido'), findsNothing);

      final expand = find.byKey(const ValueKey('contentFitTile_expand'));
      await tester.tap(expand);
      await tester.pump(const Duration(milliseconds: 300));

      final zoomFinder = find.byKey(const ValueKey('frameContentZoomSlider'));
      expect(zoomFinder, findsOneWidget);
      final slider = tester.widget<Slider>(zoomFinder);
      expect(slider.min, FrameSettings.minContentZoom);
      expect(slider.max, FrameSettings.maxContentZoom);

      final auto = find.byKey(const ValueKey('contentFitTile_auto'));
      await tester.tap(auto);
      await tester.pump(const Duration(milliseconds: 300));

      expect(
        find.byKey(const ValueKey('frameContentZoomSlider')),
        findsNothing,
        reason: 'sair de Expandir sem cortar deve ocultar o zoom',
      );
    },
  );

  testWidgets('tocar no cabeçalho de Resolução da moldura alterna o modo', (
    tester,
  ) async {
    await _openFrameSection(tester);
    await tester.tap(
      find.byKey(const ValueKey('imageFrameThumb_bundled_titanio')),
    );
    await tester.pump(const Duration(milliseconds: 300));

    final resolutionHeader = find.text('Resolução da moldura');
    await tester.tap(resolutionHeader);
    await tester.pump(const Duration(milliseconds: 300));

    // "Igual à escolhida em Ajustar" é o modo padrão: aparece duas vezes
    // (resumo da subseção + chip), por isso `findsWidgets` em vez de
    // `findsOneWidget`. "Resolução máxima da imagem" ainda não está
    // selecionada, então aparece só no chip.
    expect(find.text('Igual à escolhida em Ajustar'), findsWidgets);
    expect(find.text('Resolução máxima da imagem'), findsOneWidget);

    final nativeResolution = find.text('Resolução máxima da imagem');
    await tester.tap(nativeResolution);
    await tester.pump(const Duration(milliseconds: 300));

    // Recolhe para conferir o resumo, que só mostra o valor selecionado
    // quando a subseção está fechada.
    await tester.tap(resolutionHeader);
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Resolução máxima da imagem'), findsOneWidget);
    expect(find.text('Igual à escolhida em Ajustar'), findsNothing);
  });
}
