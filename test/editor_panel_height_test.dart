import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:video_to_gif/models/conversion_settings.dart';
import 'package:video_to_gif/models/video_info.dart';
import 'package:video_to_gif/ui/editor_page.dart';
import 'package:video_to_gif/ui/widgets/editor_tabs_footer.dart';

// O painel do rodapé cobre a prévia enquanto está aberto, então ele tem um
// teto de altura e rola por dentro. Estes testes fixam esse contrato: uma aba
// longa não pode crescer além do teto, e o que passa dele continua no painel,
// só fora da área visível.
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

Future<void> _openTab(WidgetTester tester, String tab) async {
  // Largura de celular: no padrão largo do flutter_test os chips caberiam
  // todos em duas linhas e não sobraria nada para rolar.
  tester.view.physicalSize = const Size(400, 900);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

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
  // A barra de abas rola na horizontal: numa largura de celular a aba pedida
  // pode estar fora da tela.
  final bar = find.descendant(
    of: find.byType(EditorTabsFooter),
    matching: find.byType(Scrollable),
  );
  await tester.scrollUntilVisible(find.text(tab), 120, scrollable: bar.last);
  await tester.tap(find.text(tab));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}

double _panelHeight(WidgetTester tester) => tester
    .getSize(
      find.descendant(
        of: find.byType(EditorTabsFooter),
        matching: find.byType(SingleChildScrollView),
      ),
    )
    .height;

void main() {
  testWidgets('"Resolução" mostra as primeiras linhas e rola o resto', (
    tester,
  ) async {
    await _openTab(tester, 'Resolução');

    expect(_panelHeight(tester), lessThanOrEqualTo(200));

    // Com um vídeo 1920 de largura todas as opções estão habilitadas, então
    // a lista é longa o bastante para sobrar gente fora da área visível.
    final panelBottom = tester
        .getRect(
          find.descendant(
            of: find.byType(EditorTabsFooter),
            matching: find.byType(SingleChildScrollView),
          ),
        )
        .bottom;

    // As duas primeiras linhas cabem: 160 px (primeira linha) e 480 px
    // (segunda) aparecem inteiros...
    for (final label in ['160 px', '480 px']) {
      expect(tester.getRect(find.text(label)).bottom, lessThan(panelBottom));
    }
    // ...e a última opção fica abaixo do corte, alcançável rolando.
    expect(tester.getRect(find.text('1920 px')).top, greaterThan(panelBottom));

    // Rolar o painel traz a opção escondida para dentro.
    await tester.drag(find.text('160 px'), const Offset(0, -400));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(tester.getRect(find.text('1920 px')).top, lessThan(panelBottom));
  });
}
