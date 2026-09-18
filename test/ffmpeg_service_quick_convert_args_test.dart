import 'package:flutter_test/flutter_test.dart';
import 'package:video_to_gif/models/quick_convert_format.dart';
import 'package:video_to_gif/models/video_info.dart';
import 'package:video_to_gif/services/ffmpeg_service.dart';

// quickConvertVideoArgs monta a linha de comando do único formato de vídeo
// oferecido por "Converter formato" (MP4) — uma função pura, sem tocar o
// FFmpeg de verdade, então dá para conferir os argumentos direto.

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

  group('quickConvertVideoArgs — MP4', () {
    test('usa h264_mediacodec (encoder de hardware) + aac, mantendo áudio '
        'quando existir', () {
      final args = ffmpeg.quickConvertVideoArgs(
        video: _video,
        format: QuickConvertFormat.mp4,
        width: 720,
        bitrateKbps: 3000,
        outputPath: '/tmp/saida.mp4',
      );

      _expectFlagValue(args, '-c:v', 'h264_mediacodec');
      _expectFlagValue(args, '-b:v', '3000k');
      _expectFlagValue(args, '-c:a', 'aac');
      _expectFlagValue(args, '-f', 'mp4');
      _expectFlagValue(args, '-vf', 'scale=720:-2:flags=lanczos');
      expect(args, contains('-movflags'));
      expect(args, isNot(contains('-map')));
      expect(args, isNot(contains('-preset')));
      expect(args, isNot(contains('-crf')));
      expect(args.last, '/tmp/saida.mp4');
    });

    test('bitrate reflete o nível de qualidade escolhido', () {
      final args = ffmpeg.quickConvertVideoArgs(
        video: _video,
        format: QuickConvertFormat.mp4,
        width: 480,
        bitrateKbps: QuickConvertQuality.low.mp4BitrateKbps,
        outputPath: '/tmp/saida.mp4',
      );

      _expectFlagValue(args, '-b:v', '1500k');
    });
  });

  group('QuickConvertFormat.isAnimatedImage', () {
    test('só gif e webp são imagem animada', () {
      expect(QuickConvertFormat.gif.isAnimatedImage, isTrue);
      expect(QuickConvertFormat.webp.isAnimatedImage, isTrue);
      expect(QuickConvertFormat.mp4.isAnimatedImage, isFalse);
    });
  });
}
