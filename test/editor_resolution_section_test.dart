import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:video_to_gif/models/conversion_settings.dart';
import 'package:video_to_gif/models/video_info.dart';
import 'package:video_to_gif/ui/editor_page.dart';
import 'package:video_to_gif/ui/widgets/editor_tabs_footer.dart';

// A aba "Resolução" virou um slider de porcentagem (ver
// conversion_settings_test.dart para a conta pixel↔porcentagem). Estes
// testes cobrem só a tela: o texto acima do slider e o balão que segue o
// dedo durante o arrasto mostram o tamanho em pixels resultante, sem
// precisar soltar o slider para ver o resultado.

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

Future<void> _openResolutionTab(WidgetTester tester) async {
  SharedPreferences.setMockInitialValues({});
  tester.view.physicalSize = const Size(1080, 2340);
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
  // O player de vídeo nunca inicializa em teste (sem plugin real); dá tempo
  // dele desistir antes de seguir.
  await tester.pump(const Duration(seconds: 1));

  final bar = find.descendant(
    of: find.byType(EditorTabsFooter),
    matching: find.byType(Scrollable),
  );
  await tester.scrollUntilVisible(
    find.text('Resolução'),
    120,
    scrollable: bar.last,
  );
  await tester.tap(find.text('Resolução').last);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}

void main() {
  testWidgets('abre em 100%, com o tamanho original do vídeo', (tester) async {
    await _openResolutionTab(tester);

    expect(find.textContaining('100% · 1920×1080'), findsOneWidget);
    expect(tester.widget<Slider>(find.byType(Slider)).value, 100.0);
  });

  testWidgets('arrastar o slider atualiza o texto e o balão de arrasto '
      'para o tamanho novo, sem precisar soltar', (tester) async {
    await _openResolutionTab(tester);

    await tester.drag(find.byType(Slider), const Offset(-400, 0));
    await tester.pump();

    expect(find.textContaining('100% · 1920×1080'), findsNothing);

    final slider = tester.widget<Slider>(find.byType(Slider));
    expect(slider.value, lessThan(100.0));
    // O texto acima do slider já reflete o novo tamanho...
    expect(find.textContaining('${slider.value.round()}% · '), findsOneWidget);
    // ...e o balão que segue o dedo mostra a mesma coisa, com os pixels.
    expect(slider.label, contains('×'));
    expect(slider.label, startsWith('${slider.value.round()}%'));
  });
}
