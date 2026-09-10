import 'package:flutter_test/flutter_test.dart';
import 'package:video_to_gif/models/conversion_settings.dart';
import 'package:video_to_gif/models/frame_settings.dart';
import 'package:video_to_gif/models/image_frame.dart';
import 'package:video_to_gif/models/video_info.dart';
import 'package:video_to_gif/services/ffmpeg_service.dart';

// A entrada `-f lavfi -i "color=..."` para a máscara da área de conteúdo
// dependia do dispositivo de entrada `lavfi` do libavdevice, que builds de
// FFmpeg para celular costumam remover — a exportação falhava direto na
// abertura das entradas ("Unknown input format: 'lavfi'") sempre que "Fundo
// transparente" estava ligado (o padrão). Este arquivo garante que a
// máscara vira filtro dentro do próprio `-lavfi`, nunca uma entrada `-i`
// separada.

const _video = VideoInfo(
  path: '/tmp/exemplo.mp4',
  fileName: 'exemplo.mp4',
  rawWidth: 1080,
  rawHeight: 1920,
  durationSeconds: 5,
  frameRate: 30,
  bitrateBps: 6000000,
  fileSizeBytes: 3000000,
  codec: 'h264',
);

/// O `-lavfi` é sempre o argumento logo após a flag `-lavfi` na lista.
String _lavfiOf(List<String> args) => args[args.indexOf('-lavfi') + 1];

void main() {
  final ffmpeg = FfmpegService();
  final art = ImageFrameLibrary.bundled.first;

  test('transparente: máscara da área vira filtro no grafo, nunca uma entrada '
      '-f lavfi separada', () {
    final settings = ConversionSettings(
      startSeconds: 0,
      endSeconds: 5,
      frame: FrameSettings(imageFrame: art, transparentBackground: true),
    );

    final args = ffmpeg.imageFramedGifArgs(
      video: _video,
      settings: settings,
      artPath: '/tmp/arte.png',
      outputPath: '/tmp/saida.gif',
    );

    // Só as duas entradas de sempre (vídeo e arte) — nada de `-f lavfi`.
    expect(args, isNot(contains('lavfi')));
    expect(args.where((a) => a == '-i'), hasLength(2));

    final graph = _lavfiOf(args);
    expect(graph, contains('color=white:size='));
    expect(graph, contains('[area_src]'));
    expect(graph, contains('alphamerge'));
    expect(graph, contains('reserve_transparent'));
    expect(graph, contains('alpha_threshold'));
  });

  test('opaca: sem máscara de área nenhuma, nem filtro nem entrada', () {
    final settings = ConversionSettings(
      startSeconds: 0,
      endSeconds: 5,
      frame: FrameSettings(imageFrame: art, transparentBackground: false),
    );

    final args = ffmpeg.imageFramedGifArgs(
      video: _video,
      settings: settings,
      artPath: '/tmp/arte.png',
      outputPath: '/tmp/saida.gif',
    );

    expect(args, isNot(contains('lavfi')));
    expect(args.where((a) => a == '-i'), hasLength(2));

    final graph = _lavfiOf(args);
    expect(graph, isNot(contains('color=white:size=')));
    expect(graph, isNot(contains('alphamerge')));
    expect(graph, isNot(contains('reserve_transparent')));
  });
}
