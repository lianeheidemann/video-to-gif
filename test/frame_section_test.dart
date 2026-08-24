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
    const frame = FrameSettings();
    expect(frame.transparentBackground, isTrue);
    expect(frame.backgroundColor, Colors.black);
  });

  testWidgets('cor do fundo aparece somente com transparência desligada', (
    tester,
  ) async {
    await _openFrameSection(tester);

    expect(
      find.text('Desligado, a área fora da moldura fica preta'),
      findsNothing,
    );
    expect(find.byKey(const ValueKey('backgroundColorRow')), findsNothing);

    await tester.tap(
      find.byKey(const ValueKey('transparentBackgroundSwitch')),
    );
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.byKey(const ValueKey('backgroundColorRow')), findsOneWidget);
    expect(find.text('Cor do fundo'), findsOneWidget);
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

  testWidgets('trocar a família de moldura mantém as opções no mesmo lugar', (
    tester,
  ) async {
    await _openFrameSection(tester);
    tester.view.physicalSize = const Size(1080, 2340);
    await tester.pump();

    final imageFrame = find.byKey(
      const ValueKey('imageFrameThumb_bundled_titanio'),
    );
    await tester.ensureVisible(imageFrame);
    await tester.pump();
    final imageY = tester.getTopLeft(imageFrame).dy;

    await tester.tap(imageFrame);
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump();

    expect(
      tester.getTopLeft(imageFrame).dy,
      closeTo(imageY, 1),
      reason: 'a fileira de imagens não deve pular quando a prévia muda',
    );

    final proceduralFrame = find.byKey(
      const ValueKey('frameStyleThumb_medium'),
    );
    await tester.ensureVisible(proceduralFrame);
    await tester.pump();

    await tester.tap(proceduralFrame);
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump();

    expect(
      tester.getTopLeft(proceduralFrame).dy,
      greaterThanOrEqualTo(0),
      reason: 'a fileira procedural deve continuar visível',
    );
    expect(
      tester.getBottomRight(proceduralFrame).dy,
      lessThanOrEqualTo(tester.view.physicalSize.height),
      reason: 'a fileira procedural não deve sair da tela',
    );
  });

  testWidgets(
    'painel de ajuste só aparece com moldura de imagem ativa',
    (tester) async {
      await _openFrameSection(tester);

      expect(find.text('Ajuste do conteúdo'), findsNothing);
      expect(find.text('Resolução da moldura'), findsNothing);

      await tester.tap(
        find.byKey(const ValueKey('imageFrameThumb_bundled_titanio')),
      );
      await tester.pump();

      expect(find.text('Ajuste do conteúdo'), findsOneWidget);
      expect(find.text('Resolução da moldura'), findsNothing);
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
      expect(find.text('Ajuste automático'), findsOneWidget);
      expect(find.text('Modo de encaixe'), findsNothing);
      expect(find.text('Resolução da moldura'), findsOneWidget);
      expect(find.text('Igual à escolhida em Ajustar'), findsNothing);
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

  testWidgets('resolução da moldura aparece como seletor geral do painel', (
    tester,
  ) async {
    await _openFrameSection(tester);
    await tester.tap(
      find.byKey(const ValueKey('imageFrameThumb_bundled_titanio')),
    );
    await tester.pump(const Duration(milliseconds: 300));

    await tester.tap(find.text('Ajuste do conteúdo'));
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Resolução da moldura'), findsOneWidget);
    expect(find.text('Igual à escolhida em Ajustar'), findsNothing);
    expect(
      find.byKey(const ValueKey('frameResolutionSegment_matchAjustar')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('frameResolutionSegment_nativeMax')),
      findsOneWidget,
    );

    final selector = find.byKey(
      const ValueKey('frameResolutionSegmentedButton'),
    );
    expect(
      tester
          .widget<SegmentedButton<ImageFrameResolutionMode>>(selector)
          .selected,
      {ImageFrameResolutionMode.matchAjustar},
    );

    final nativeResolution = find.byKey(
      const ValueKey('frameResolutionSegment_nativeMax'),
    );
    await tester.tap(nativeResolution);
    await tester.pump(const Duration(milliseconds: 300));

    expect(
      tester
          .widget<SegmentedButton<ImageFrameResolutionMode>>(selector)
          .selected,
      {ImageFrameResolutionMode.nativeMax},
    );
  });
}
