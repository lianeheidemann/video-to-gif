import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:video_to_gif/models/conversion_settings.dart';
import 'package:video_to_gif/models/video_info.dart';
import 'package:video_to_gif/ui/editor_page.dart';

// Cobre as duas rotações novas na UI: a aba "Girar" (rotação/espelhamento
// só do conteúdo) e o botão "Girar resultado" dentro da aba "Moldura"
// (rotação de moldura + conteúdo juntos). Mesmos helpers de abertura de aba
// de frame_section_test.dart.

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
  // O player de vídeo nunca inicializa em teste (sem plugin real); dá tempo
  // dele desistir e marcar `_previewFailed` antes de seguir.
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
  group('aba "Girar" (conteúdo)', () {
    testWidgets('abre sem erro, com o valor inicial "Nenhum"', (tester) async {
      await _openTab(tester, 'Girar');
      expect(tester.takeException(), isNull);
      expect(find.text('Nenhum'), findsOneWidget);
      expect(find.text('90° à esquerda'), findsOneWidget);
      expect(find.text('90° à direita'), findsOneWidget);
      expect(find.text('Horizontal'), findsOneWidget);
      expect(find.text('Vertical'), findsOneWidget);
    });

    testWidgets('girar à direita atualiza o valor para "90°"', (tester) async {
      await _openTab(tester, 'Girar');

      await tester.tap(find.text('90° à direita'));
      await tester.pump();

      expect(tester.takeException(), isNull);
      expect(find.text('90°'), findsOneWidget);
    });

    testWidgets('espelhar horizontal atualiza o valor', (tester) async {
      await _openTab(tester, 'Girar');

      await tester.tap(find.text('Horizontal'));
      await tester.pump();

      expect(tester.takeException(), isNull);
      expect(find.text('Espelho H'), findsOneWidget);
    });
  });

  group('aba "Moldura": botão "Girar resultado"', () {
    testWidgets('aparece e funciona com "Sem moldura" selecionada', (
      tester,
    ) async {
      await _openTab(tester, 'Moldura');

      final button = find.byKey(const ValueKey('groupRotateButton'));
      expect(button, findsOneWidget);
      expect(find.text('Girar 90°'), findsOneWidget);

      await tester.tap(button);
      await tester.pump();

      expect(tester.takeException(), isNull);
      expect(find.text('90°'), findsOneWidget);
    });

    testWidgets('continua visível e funcional com uma moldura de imagem '
        'ativa', (tester) async {
      await _openTab(tester, 'Imagem');
      await tester.tap(
        find.byKey(const ValueKey('imageFrameThumb_bundled_titanio')),
      );
      await tester.pump();

      await _switchTab(tester, 'Moldura');

      final button = find.byKey(const ValueKey('groupRotateButton'));
      expect(button, findsOneWidget);

      await tester.tap(button);
      await tester.pump();

      expect(tester.takeException(), isNull);
      expect(find.text('90°'), findsOneWidget);
    });
  });
}
