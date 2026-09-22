import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:video_to_gif/core/models/conversion_settings.dart';
import 'package:video_to_gif/core/models/photo_info.dart';
import 'package:video_to_gif/core/models/video_info.dart';
import 'package:video_to_gif/features/photo/photo_frame_page.dart';
import 'package:video_to_gif/features/video/editor_page.dart';

// A aba "Girar" nasceu na tela de SVG e passou a valer também em "Editar
// GIF" e "Editar imagem". Nestas duas ela é um passo de saída: gira o
// resultado, não o espaço de trabalho. O que estes testes fixam é o par
// que faz isso ser verdade na tela — o botão muda o estado, e a prévia
// mostra o resultado já girado — mais a exceção deliberada: com as alças de
// recorte à mostra a prévia fica na orientação original, senão arrastar uma
// alça moveria a janela no sentido "errado" para quem está olhando.

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

Future<void> _writeSolidPng(String path, int width, int height) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.drawRect(
    Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
    Paint()..color = const Color(0xFF3366FF),
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

/// Quartos de volta que a prévia está aplicando — `0` quando não há nenhum
/// `RotatedBox` montado, que é como a tela fica sem giro escolhido.
int _previewQuarterTurns(WidgetTester tester) {
  final boxes = tester.widgetList<RotatedBox>(find.byType(RotatedBox));
  if (boxes.isEmpty) return 0;
  expect(boxes.length, 1, reason: 'a prévia deveria girar num lugar só');
  return boxes.first.quarterTurns;
}

Future<void> _openTab(WidgetTester tester, String tab) async {
  await tester.tap(find.text(tab).last);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

void main() {
  late Directory tempDir;
  late PhotoInfo photo;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('rotate_flip_tab_test');
    final path = '${tempDir.path}/foto.png';
    await _writeSolidPng(path, 400, 200);
    photo = PhotoInfo(path: path, width: 400, height: 200);
  });

  tearDown(() async {
    if (await tempDir.exists()) await tempDir.delete(recursive: true);
  });

  Future<void> pumpVideo(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: EditorPage(
          video: _video,
          initialSettings: ConversionSettings.recommendedFor(_video),
        ),
      ),
    );
    // O player nunca inicializa em teste (sem plugin real); dá tempo dele
    // desistir antes de seguir — mesmo cuidado de frame_section_test.
    await tester.pump(const Duration(seconds: 1));
  }

  Future<void> pumpPhoto(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(home: PhotoFramePage(photo: photo)));
    await tester.pump(const Duration(milliseconds: 400));
  }

  testWidgets('Editar GIF ganhou a aba, e ela gira a prévia', (tester) async {
    await pumpVideo(tester);
    expect(find.text('Girar'), findsOneWidget);

    await _openTab(tester, 'Girar');
    expect(find.text('90° à direita'), findsOneWidget);
    expect(_previewQuarterTurns(tester), 0);

    await tester.tap(find.text('90° à direita'));
    await tester.pump(const Duration(milliseconds: 400));
    expect(_previewQuarterTurns(tester), 1);

    // Girar para a esquerda a partir daqui volta ao original.
    await tester.tap(find.text('90° à esquerda'));
    await tester.pump(const Duration(milliseconds: 400));
    expect(_previewQuarterTurns(tester), 0);
  });

  testWidgets('no vídeo, girar à esquerda a partir do zero dá 270°', (
    tester,
  ) async {
    await pumpVideo(tester);
    await _openTab(tester, 'Girar');

    await tester.tap(find.text('90° à esquerda'));
    await tester.pump(const Duration(milliseconds: 400));
    expect(_previewQuarterTurns(tester), 3);
  });

  testWidgets('desfazer volta o giro do vídeo', (tester) async {
    await pumpVideo(tester);
    await _openTab(tester, 'Girar');

    await tester.tap(find.text('90° à direita'));
    await tester.pump(const Duration(milliseconds: 400));
    expect(_previewQuarterTurns(tester), 1);

    await tester.tap(find.byIcon(Icons.undo_rounded));
    await tester.pump(const Duration(milliseconds: 400));
    expect(_previewQuarterTurns(tester), 0);
  });

  testWidgets('com as alças de recorte à mostra, a prévia não gira', (
    tester,
  ) async {
    await pumpVideo(tester);
    await _openTab(tester, 'Girar');
    await tester.tap(find.text('90° à direita'));
    await tester.pump(const Duration(milliseconds: 400));
    expect(_previewQuarterTurns(tester), 1);

    await _openTab(tester, 'Janela');
    expect(_previewQuarterTurns(tester), 0);

    // E ao sair da aba de recorte o giro reaparece — ele continua guardado.
    await _openTab(tester, 'Girar');
    expect(_previewQuarterTurns(tester), 1);
  });

  testWidgets('Editar imagem ganhou a aba, e ela gira a prévia', (
    tester,
  ) async {
    await pumpPhoto(tester);
    expect(find.text('Girar'), findsOneWidget);

    await _openTab(tester, 'Girar');
    expect(_previewQuarterTurns(tester), 0);

    await tester.tap(find.text('90° à direita'));
    await tester.pump(const Duration(milliseconds: 400));
    expect(_previewQuarterTurns(tester), 1);
  });

  testWidgets('na foto, as alças de recorte também ficam sem girar', (
    tester,
  ) async {
    await pumpPhoto(tester);
    await _openTab(tester, 'Girar');
    await tester.tap(find.text('90° à direita'));
    await tester.pump(const Duration(milliseconds: 400));
    expect(_previewQuarterTurns(tester), 1);

    await _openTab(tester, 'Recorte');
    expect(_previewQuarterTurns(tester), 0);
  });

  testWidgets('espelhar não é exclusivo com girar', (tester) async {
    await pumpPhoto(tester);
    await _openTab(tester, 'Girar');

    await tester.tap(find.text('90° à direita'));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.text('Horizontal'));
    await tester.pump(const Duration(milliseconds: 400));

    expect(_previewQuarterTurns(tester), 1);
    expect(find.text('90° · Espelho H'), findsWidgets);
  });
}
