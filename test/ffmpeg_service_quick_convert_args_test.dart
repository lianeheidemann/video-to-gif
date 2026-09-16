import 'package:flutter_test/flutter_test.dart';
import 'package:video_to_gif/models/quick_convert_format.dart';
import 'package:video_to_gif/models/video_info.dart';
import 'package:video_to_gif/services/ffmpeg_service.dart';

// quickConvertVideoArgs monta a linha de comando dos três formatos de vídeo
// oferecidos por "Converter formato" (MP4/MOV/WebM) — uma função pura, sem
// tocar o FFmpeg de verdade, então dá para conferir os argumentos direto.

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

void _expectFlagValue(List<String> args, String flag, String value) {
  final index = args.indexOf(flag);
  expect(index, greaterThanOrEqualTo(0), reason: 'flag $flag não encontrada');
  expect(args[index + 1], value, reason: 'valor de $flag');
}

void main() {
  final ffmpeg = FfmpegService();

  group('quickConvertVideoArgs — MP4/MOV', () {
    for (final format in [QuickConvertFormat.mp4, QuickConvertFormat.mov]) {
      test(
        '${format.label} usa libx264 + aac, mantendo áudio quando existir',
        () {
          final args = ffmpeg.quickConvertVideoArgs(
            video: _video,
            format: format,
            width: 720,
            outputPath: '/tmp/saida.${format.extension}',
          );

          _expectFlagValue(args, '-c:v', 'libx264');
          _expectFlagValue(args, '-pix_fmt', 'yuv420p');
          _expectFlagValue(args, '-c:a', 'aac');
          _expectFlagValue(args, '-f', format.extension);
          _expectFlagValue(args, '-vf', 'scale=720:-2:flags=lanczos');
          expect(args, contains('-movflags'));
          expect(args, isNot(contains('-map')));
          expect(args.last, '/tmp/saida.${format.extension}');
        },
      );
    }
  });

  group('quickConvertVideoArgs — WebM', () {
    test('usa libvpx-vp9 + libopus, mantendo áudio quando existir', () {
      final args = ffmpeg.quickConvertVideoArgs(
        video: _video,
        format: QuickConvertFormat.webm,
        width: 480,
        outputPath: '/tmp/saida.webm',
      );

      _expectFlagValue(args, '-c:v', 'libvpx-vp9');
      _expectFlagValue(args, '-c:a', 'libopus');
      _expectFlagValue(args, '-f', 'webm');
      _expectFlagValue(args, '-vf', 'scale=480:-2:flags=lanczos');
      expect(args, isNot(contains('-movflags')));
      expect(args, isNot(contains('-map')));
    });
  });

  group('QuickConvertFormat.isAnimatedImage', () {
    test('só gif e webp são imagem animada', () {
      expect(QuickConvertFormat.gif.isAnimatedImage, isTrue);
      expect(QuickConvertFormat.webp.isAnimatedImage, isTrue);
      expect(QuickConvertFormat.mp4.isAnimatedImage, isFalse);
      expect(QuickConvertFormat.webm.isAnimatedImage, isFalse);
      expect(QuickConvertFormat.mov.isAnimatedImage, isFalse);
    });
  });
}
