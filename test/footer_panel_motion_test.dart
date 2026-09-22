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

// Abrir e fechar o painel de uma aba precisa ter movimento, não um salto.
//
// Antes o painel inteiro entrava e saía da árvore junto com a aba, então não
// havia nada para animar: ele aparecia e sumia num quadro só. O que prova a
// correção é medir a altura no MEIO da transição — sem ela o valor é sempre 0
// ou o final, nunca um intermediário.

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

/// Altura ocupada pelo painel da aba. O alvo é o invólucro da transição, não
/// o painel em si: dentro de um `SizeTransition` o filho mantém o tamanho
/// inteiro e quem encolhe é o recorte em volta.
double _alturaDoPainel(WidgetTester tester) =>
    tester.getSize(find.byKey(const ValueKey('painelDaAba'))).height;

/// Meio da transição: metade da duração declarada no rodapé.
Duration get _meio => editorPanelMotionDuration ~/ 2;

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

  // As fotos nascem fora do `testWidgets`: o binding de teste roda numa zona
  // assíncrona falsa, e E/S de verdade lá dentro nunca completa.
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    tempDir = await Directory.systemTemp.createTemp('footer_motion_test');
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

  testWidgets('Editar GIF: fechar e abrir a aba passam por alturas no meio', (
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

    final aberta = _alturaDoPainel(tester);
    expect(aberta, greaterThan(0));

    // A tela abre já com a primeira aba aberta; tocar nela fecha.
    final abaAberta = find.descendant(
      of: find.byType(EditorTabsFooter),
      matching: find.text('Formato'),
    );
    await tester.tap(abaAberta);
    await tester.pump();
    await tester.pump(_meio);

    final fechando = _alturaDoPainel(tester);
    expect(fechando, greaterThan(0), reason: 'fechar deu um salto para zero');
    expect(fechando, lessThan(aberta));

    // `pumpAndSettle` não serve aqui: o indicador de carregamento do player
    // nunca assenta em teste. Avançar a duração exata basta.
    await tester.pump(editorPanelMotionDuration);
    expect(_alturaDoPainel(tester), 0);

    // E abrir de novo também passa pelo meio.
    await tester.tap(abaAberta);
    await tester.pump();
    await tester.pump(_meio);

    final abrindo = _alturaDoPainel(tester);
    expect(abrindo, greaterThan(0), reason: 'abrir deu um salto para o final');
    expect(abrindo, lessThan(aberta));

    await tester.pump(editorPanelMotionDuration);
    expect(_alturaDoPainel(tester), aberta);
  });

  testWidgets('Montagem: fechar a aba passa por alturas no meio', (
    tester,
  ) async {
    // Tela alta o bastante para prévia, painel e barra caberem juntos.
    tester.view.physicalSize = const Size(900, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(MaterialApp(home: CollagePage(photos: photos)));
    await tester.pumpAndSettle();

    final aberta = _alturaDoPainel(tester);
    expect(aberta, greaterThan(0));

    await tester.tap(find.text('Layout'));
    await tester.pump();
    await tester.pump(_meio);

    final fechando = _alturaDoPainel(tester);
    expect(fechando, greaterThan(0), reason: 'fechar deu um salto para zero');
    expect(fechando, lessThan(aberta));

    await tester.pumpAndSettle();
    expect(_alturaDoPainel(tester), 0);
  });
}
