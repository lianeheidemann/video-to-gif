import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:video_to_gif/models/video_info.dart';
import 'package:video_to_gif/ui/widgets/source_file_card.dart';

VideoInfo _video({
  String fileName = 'ferias.mp4',
  int rawWidth = 1920,
  int rawHeight = 1080,
  double durationSeconds = 6,
  double frameRate = 30,
  int fileSizeBytes = 8 * 1024 * 1024,
  int rotationDegrees = 0,
}) {
  return VideoInfo(
    path: '/tmp/$fileName',
    fileName: fileName,
    rawWidth: rawWidth,
    rawHeight: rawHeight,
    durationSeconds: durationSeconds,
    frameRate: frameRate,
    bitrateBps: 4000000,
    fileSizeBytes: fileSizeBytes,
    codec: 'h264',
    rotationDegrees: rotationDegrees,
  );
}

Future<void> _pumpCard(
  WidgetTester tester, {
  required VideoInfo video,
  required String extension,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SourceFileCard(video: video, extension: extension),
      ),
    ),
  );
}

void main() {
  testWidgets('mostra nome, selo e as duas linhas de metadados', (
    tester,
  ) async {
    await _pumpCard(tester, video: _video(), extension: 'mp4');

    expect(find.text('ferias.mp4'), findsOneWidget);
    expect(find.text('MP4'), findsOneWidget);
    expect(find.text('1920 × 1080 px • 6.0s'), findsOneWidget);
    expect(find.text('30 FPS • 8.0 MB'), findsOneWidget);
  });

  testWidgets('duração acima de um minuto sai em minutos e segundos', (
    tester,
  ) async {
    await _pumpCard(
      tester,
      video: _video(durationSeconds: 65),
      extension: 'mp4',
    );

    expect(find.text('1920 × 1080 px • 1min 5s'), findsOneWidget);
  });

  testWidgets('vídeo girado mostra as dimensões de exibição', (tester) async {
    await _pumpCard(
      tester,
      video: _video(rotationDegrees: 90),
      extension: 'mp4',
    );

    expect(find.text('1080 × 1920 px • 6.0s'), findsOneWidget);
  });

  testWidgets('arquivo sem extensão não mostra selo', (tester) async {
    await _pumpCard(
      tester,
      video: _video(fileName: 'gravacao'),
      extension: '',
    );

    expect(find.text('gravacao'), findsOneWidget);
    expect(find.text('MP4'), findsNothing);
  });
}
