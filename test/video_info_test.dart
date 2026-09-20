import 'package:flutter_test/flutter_test.dart';
import 'package:video_to_gif/models/video_info.dart';

/// Vídeo gravado em pé no celular: o arquivo guarda 1280x720 deitado e conta
/// a rotação à parte. É o caso que aparecia achatado no editor.
VideoInfo _video({int rotationDegrees = 0}) => VideoInfo(
  path: '/tmp/20260919_084543.mp4',
  fileName: '20260919_084543.mp4',
  rawWidth: 1280,
  rawHeight: 720,
  durationSeconds: 6.9,
  frameRate: 30,
  bitrateBps: 10000000,
  fileSizeBytes: 8744946,
  codec: 'hevc',
  rotationDegrees: rotationDegrees,
);

void main() {
  group('dimensões de exibição', () {
    test('rotação de 90 ou 270 troca os lados', () {
      for (final graus in [90, 270, -90]) {
        final video = _video(rotationDegrees: graus);
        expect(video.width, 720, reason: '$graus°');
        expect(video.height, 1280, reason: '$graus°');
      }
    });

    test('rotação de 0 ou 180 mantém os lados', () {
      for (final graus in [0, 180]) {
        final video = _video(rotationDegrees: graus);
        expect(video.width, 1280, reason: '$graus°');
        expect(video.height, 720, reason: '$graus°');
      }
    });

    test('proporção e orientação acompanham a rotação', () {
      final deitado = _video();
      expect(deitado.isPortrait, isFalse);
      expect(deitado.aspectRatio, closeTo(16 / 9, 0.001));

      final emPe = _video(rotationDegrees: 90);
      expect(emPe.isPortrait, isTrue);
      expect(emPe.aspectRatio, closeTo(9 / 16, 0.001));
    });

    test('altura zero não gera divisão por zero', () {
      const vazio = VideoInfo(
        path: '/tmp/v.mp4',
        fileName: 'v.mp4',
        rawWidth: 0,
        rawHeight: 0,
        durationSeconds: 1,
        frameRate: 30,
        bitrateBps: 0,
        fileSizeBytes: 0,
        codec: 'hevc',
      );
      expect(vazio.aspectRatio, 1);
    });
  });

  group('bits por pixel da fonte', () {
    test('usa as dimensões de exibição', () {
      // Mesma contagem de pixels nos dois casos: girar não muda a área, e o
      // valor não pode depender de como o arquivo guardou os lados.
      expect(
        _video(rotationDegrees: 90).sourceBitsPerPixel,
        closeTo(_video().sourceBitsPerPixel, 1e-9),
      );
    });

    test('sem bitrate conhecido, devolve zero em vez de infinito', () {
      const semBitrate = VideoInfo(
        path: '/tmp/v.mp4',
        fileName: 'v.mp4',
        rawWidth: 1280,
        rawHeight: 720,
        durationSeconds: 6,
        frameRate: 30,
        bitrateBps: 0,
        fileSizeBytes: 100,
        codec: 'hevc',
      );
      expect(semBitrate.sourceBitsPerPixel, 0);
    });
  });
}
