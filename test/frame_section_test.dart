import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:video_to_gif/models/conversion_settings.dart';
import 'package:video_to_gif/models/frame_settings.dart';
import 'package:video_to_gif/models/video_info.dart';
import 'package:video_to_gif/ui/editor_page.dart';

// As molduras moram em duas abas do rodapé — "Moldura" (as procedurais) e
// "Imagem" (as artes prontas) — e só uma família pode estar ativa por vez.
// Cada fileira tem a sua própria miniatura "Sem moldura" e mostra sempre
// exatamente uma opção marcada: é assim que se vê que escolher de um lado
// desativou o outro. Estes testes garantem que as duas fileiras existem nas
// suas abas e que essa exclusão mútua vale nos dois sentidos.
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

/// Monta a tela e abre a aba [tab] do rodapé (o rótulo curto da barra).
Future<void> _openTab(WidgetTester tester, String tab) async {
  tester.view.physicalSize = const Size(1080, 2340);
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

  await _switchTab(tester, tab);
}

/// Troca de aba numa tela já montada.
Future<void> _switchTab(WidgetTester tester, String tab) async {
  await tester.tap(find.text(tab).last);
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
    await _openTab(tester, 'Fundo');

    expect(
      find.text('Desligado, a área fora da moldura fica preta'),
      findsNothing,
    );
    expect(find.byKey(const ValueKey('backgroundColorRow')), findsNothing);

    await tester.tap(find.byKey(const ValueKey('transparentBackgroundSwitch')));
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.byKey(const ValueKey('backgroundColorRow')), findsOneWidget);
    expect(find.text('Cor do fundo'), findsOneWidget);
  });

  testWidgets('cada família de moldura aparece na sua aba, sem erro', (
    tester,
  ) async {
    await _openTab(tester, 'Moldura');
    expect(tester.takeException(), isNull);
    for (final key in [
      'frameStyleThumb_none',
      'frameStyleThumb_thin',
      'frameStyleThumb_medium',
      'frameStyleThumb_thick',
    ]) {
      expect(
        find.byKey(ValueKey(key)),
        findsOneWidget,
        reason: '$key deveria estar na aba "Moldura"',
      );
    }

    await _switchTab(tester, 'Imagem');
    expect(tester.takeException(), isNull);
    for (final key in [
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
        reason: '$key deveria estar na aba "Imagem"',
      );
    }
  });

  testWidgets('escolher numa aba volta a outra para "Sem moldura"', (
    tester,
  ) async {
    await _openTab(tester, 'Imagem');
    expect(
      _checkIn('imageFrameThumb_none'),
      findsOneWidget,
      reason: 'sem nada escolhido, a fileira começa em "Sem moldura"',
    );

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
      find.text('Titânio'),
      findsWidgets,
      reason: 'o cabeçalho do painel deve refletir a moldura ativa',
    );

    await _switchTab(tester, 'Moldura');
    expect(
      _checkIn('frameStyleThumb_none'),
      findsOneWidget,
      reason: 'a família procedural continua em "Sem moldura"',
    );

    await tester.tap(find.byKey(const ValueKey('frameStyleThumb_medium')));
    await tester.pump();
    expect(_checkIn('frameStyleThumb_medium'), findsOneWidget);

    await _switchTab(tester, 'Imagem');
    expect(
      _checkIn('imageFrameThumb_bundled_titanio'),
      findsNothing,
      reason: 'a moldura de imagem é desativada',
    );
    expect(_checkIn('imageFrameThumb_none'), findsOneWidget);
  });

  testWidgets('escolher uma moldura não fecha nem troca a aba aberta', (
    tester,
  ) async {
    // Antes as seções viviam numa lista rolável junto com a prévia, e mudar
    // de moldura mexia na rolagem (havia toda uma compensação para isso).
    // Com o painel fixo no rodapé, a fileira simplesmente continua no lugar.
    await _openTab(tester, 'Imagem');
    final imageFrame = find.byKey(
      const ValueKey('imageFrameThumb_bundled_titanio'),
    );

    await tester.tap(imageFrame);
    await tester.pump(const Duration(milliseconds: 300));

    // A aba continua a mesma e a fileira continua na tela — o painel só
    // cresce para baixo do próprio cabeçalho, com as opções novas da
    // moldura escolhida.
    expect(imageFrame, findsOneWidget);
    expect(_checkIn('imageFrameThumb_bundled_titanio'), findsOneWidget);
    expect(find.text('Moldura de imagem'), findsWidgets);
  });

  testWidgets('painel de ajuste só aparece com moldura de imagem ativa', (
    tester,
  ) async {
    await _openTab(tester, 'Imagem');

    expect(find.text('Ajuste do conteúdo'), findsNothing);
    expect(find.text('Resolução da moldura'), findsNothing);

    await tester.tap(
      find.byKey(const ValueKey('imageFrameThumb_bundled_titanio')),
    );
    await tester.pump();

    expect(find.text('Ajuste do conteúdo'), findsOneWidget);
    expect(
      find.text('Resolução da moldura'),
      findsOneWidget,
      reason:
          'resolução da moldura é um card independente, não deve depender '
          'de Ajuste do conteúdo estar expandido',
    );
  });

  testWidgets(
    'zoom aparece somente em Expandir sem cortar e vai de 10% a 300%',
    (tester) async {
      await _openTab(tester, 'Imagem');
      await tester.tap(
        find.byKey(const ValueKey('imageFrameThumb_bundled_titanio')),
      );
      await tester.pump(const Duration(milliseconds: 300));

      final contentHeader = find.text('Ajuste do conteúdo');
      await tester.ensureVisible(contentHeader);
      await tester.pump();
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
      await tester.ensureVisible(expand);
      await tester.pump();
      await tester.tap(expand);
      await tester.pump(const Duration(milliseconds: 300));

      final zoomFinder = find.byKey(const ValueKey('frameContentZoomSlider'));
      expect(zoomFinder, findsOneWidget);
      final slider = tester.widget<Slider>(zoomFinder);
      expect(slider.min, FrameSettings.minContentZoom);
      expect(slider.max, FrameSettings.maxContentZoom);

      final auto = find.byKey(const ValueKey('contentFitTile_auto'));
      await tester.ensureVisible(auto);
      await tester.pump();
      await tester.tap(auto);
      await tester.pump(const Duration(milliseconds: 300));

      expect(
        find.byKey(const ValueKey('frameContentZoomSlider')),
        findsNothing,
        reason: 'sair de Expandir sem cortar deve ocultar o zoom',
      );
    },
  );

  testWidgets('resolução da moldura aparece como card próprio do painel', (
    tester,
  ) async {
    await _openTab(tester, 'Imagem');
    await tester.tap(
      find.byKey(const ValueKey('imageFrameThumb_bundled_titanio')),
    );
    await tester.pump(const Duration(milliseconds: 300));

    expect(
      find.text('Resolução da moldura'),
      findsOneWidget,
      reason: 'não deve exigir Ajuste do conteúdo expandido para aparecer',
    );
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
    // O painel tem teto de altura e rola por dentro: o seletor pode estar
    // abaixo do corte.
    await tester.ensureVisible(nativeResolution);
    await tester.pump();
    await tester.tap(nativeResolution);
    await tester.pump(const Duration(milliseconds: 300));

    expect(
      tester
          .widget<SegmentedButton<ImageFrameResolutionMode>>(selector)
          .selected,
      {ImageFrameResolutionMode.nativeMax},
    );
  });

  testWidgets('desfazer e refazer voltam e refazem a escolha de moldura', (
    tester,
  ) async {
    await _openTab(tester, 'Moldura');

    // Sem nenhuma mudança ainda, os dois botões nascem desligados.
    // O `Tooltip` fica DENTRO do `IconButton` (é ele que o cria), então o
    // botão é o ancestral, não o descendente.
    IconButton buttonWith(String tooltip) => tester.widget<IconButton>(
      find
          .ancestor(
            of: find.byTooltip(tooltip),
            matching: find.byType(IconButton),
          )
          .first,
    );
    expect(buttonWith('Desfazer').onPressed, isNull);
    expect(buttonWith('Refazer').onPressed, isNull);

    await tester.tap(find.byKey(const ValueKey('frameStyleThumb_medium')));
    await tester.pump(const Duration(milliseconds: 300));
    expect(_checkIn('frameStyleThumb_medium'), findsOneWidget);

    await tester.tap(find.byTooltip('Desfazer'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(
      _checkIn('frameStyleThumb_none'),
      findsOneWidget,
      reason: 'desfazer volta para "Sem moldura"',
    );

    await tester.tap(find.byTooltip('Refazer'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(
      _checkIn('frameStyleThumb_medium'),
      findsOneWidget,
      reason: 'refazer traz a moldura de volta',
    );
  });
}
