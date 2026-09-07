import 'package:flutter_test/flutter_test.dart';
import 'package:video_to_gif/models/conversion_settings.dart';
import 'package:video_to_gif/models/frame_settings.dart';
import 'package:video_to_gif/models/image_frame.dart';
import 'package:video_to_gif/models/video_info.dart';
import 'package:video_to_gif/services/ffmpeg_service.dart';

// Os builders de argumento do WebP são funções puras (nenhuma delas toca o
// FFmpeg de verdade) — dá para testar a lista de argumentos e o grafo do
// `-lavfi` sem rodar uma conversão real. Este arquivo garante especificamente
// que o caminho do WebP nunca reintroduz as muletas específicas do GIF
// (paleta em dois passes, `reserve_transparent`, `alpha_threshold`,
// `-gifflags -transdiff`) — o ponto central do design (ver ffmpeg_service.dart).

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

/// Confirma que [flag] existe na lista e que o valor logo depois dele é
/// exatamente [value] — mais preciso que `containsAllInOrder`, que só
/// garante a ordem relativa e deixaria passar um valor de outra flag.
void _expectFlagValue(List<String> args, String flag, String value) {
  final index = args.indexOf(flag);
  expect(index, greaterThanOrEqualTo(0), reason: 'flag $flag não encontrada');
  expect(args[index + 1], value, reason: 'valor de $flag');
}

void main() {
  final ffmpeg = FfmpegService();

  group('webpArgs — sem moldura', () {
    final settings = ConversionSettings(
      startSeconds: 0,
      endSeconds: 5,
      webpQuality: 80,
    );

    test('usa libwebp num único passe, sem paleta nenhuma', () {
      final args = ffmpeg.webpArgs(
        video: _video,
        settings: settings,
        outputPath: '/tmp/saida.webp',
      );

      _expectFlagValue(args, '-c:v', 'libwebp');
      _expectFlagValue(args, '-quality', '80');
      _expectFlagValue(args, '-pix_fmt', 'yuv420p');
      _expectFlagValue(args, '-f', 'webp');
      expect(args.last, '/tmp/saida.webp');

      final graph = _lavfiOf(args);
      expect(graph, isNot(contains('palettegen')));
      expect(graph, isNot(contains('paletteuse')));
      expect(args, isNot(contains('-gifflags')));
      expect(graph, isNot(contains('reserve_transparent')));
      expect(graph, isNot(contains('alpha_threshold')));
    });

    test('loop ligado vira -loop 0, desligado vira -loop 1', () {
      final looping = ffmpeg.webpArgs(
        video: _video,
        settings: settings.copyWith(loop: true),
        outputPath: '/tmp/a.webp',
      );
      final once = ffmpeg.webpArgs(
        video: _video,
        settings: settings.copyWith(loop: false),
        outputPath: '/tmp/b.webp',
      );

      _expectFlagValue(looping, '-loop', '0');
      _expectFlagValue(once, '-loop', '1');
    });
  });

  group('webpArgs — moldura procedural', () {
    const opaqueFrame = FrameSettings(
      style: FrameStyle.medium,
      thicknessAtReference: 10,
      cornerRatio: 0.12,
      transparentBackground: false,
    );
    const transparentFrame = FrameSettings(
      style: FrameStyle.medium,
      thicknessAtReference: 10,
      cornerRatio: 0.12,
      transparentBackground: true,
    );

    test('opaca não precisa de alfa nem de máscara', () {
      final settings = ConversionSettings(
        startSeconds: 0,
        endSeconds: 5,
        frame: opaqueFrame,
      );

      final args = ffmpeg.webpArgs(
        video: _video,
        settings: settings,
        outputPath: '/tmp/saida.webp',
      );

      _expectFlagValue(args, '-pix_fmt', 'yuv420p');
      expect(_lavfiOf(args), isNot(contains('alphamerge')));
    });

    test('transparente usa alfa real via alphamerge, sem hacks do GIF', () {
      final settings = ConversionSettings(
        startSeconds: 0,
        endSeconds: 5,
        frame: transparentFrame,
      );

      final args = ffmpeg.webpArgs(
        video: _video,
        settings: settings,
        outputPath: '/tmp/saida.webp',
        maskPath: '/tmp/mascara.png',
      );

      _expectFlagValue(args, '-pix_fmt', 'yuva420p');
      final graph = _lavfiOf(args);
      expect(graph, contains('alphamerge'));
      expect(graph, isNot(contains('reserve_transparent')));
      expect(graph, isNot(contains('alpha_threshold')));
      expect(args, isNot(contains('-gifflags')));
    });
  });

  group('webpImageFramedArgs — moldura de imagem', () {
    final art = ImageFrameLibrary.bundled.first;

    test('opaca usa yuv420p e não referencia máscara de área', () {
      final settings = ConversionSettings(
        startSeconds: 0,
        endSeconds: 5,
        frame: FrameSettings(imageFrame: art, transparentBackground: false),
      );

      final args = ffmpeg.webpImageFramedArgs(
        video: _video,
        settings: settings,
        artPath: '/tmp/arte.png',
        outputPath: '/tmp/saida.webp',
      );

      _expectFlagValue(args, '-pix_fmt', 'yuv420p');
      expect(args, contains('-shortest'));
      expect(_lavfiOf(args), isNot(contains('alphamerge')));
    });

    test('transparente usa yuva420p e o alphamerge da área de conteúdo', () {
      final settings = ConversionSettings(
        startSeconds: 0,
        endSeconds: 5,
        frame: FrameSettings(imageFrame: art, transparentBackground: true),
      );

      final args = ffmpeg.webpImageFramedArgs(
        video: _video,
        settings: settings,
        artPath: '/tmp/arte.png',
        outputPath: '/tmp/saida.webp',
      );

      _expectFlagValue(args, '-pix_fmt', 'yuva420p');
      expect(_lavfiOf(args), contains('alphamerge'));
    });
  });
}
