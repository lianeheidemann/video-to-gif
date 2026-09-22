import 'package:flutter_test/flutter_test.dart';
import 'package:video_to_gif/models/conversion_settings.dart';
import 'package:video_to_gif/models/frame_settings.dart';
import 'package:video_to_gif/models/image_frame.dart';
import 'package:video_to_gif/models/video_info.dart';
import 'package:video_to_gif/services/ffmpeg_service.dart';

// Cobre as duas rotações novas nos argumentos de FFmpeg — funções puras
// (nenhuma delas toca o FFmpeg de verdade), no mesmo estilo de
// ffmpeg_service_webp_args_test.dart:
//
//  * rotação de CONTEÚDO (aba "Girar", `ConversionSettings.
//    rotationQuarterTurns`/`flipHorizontal`/`flipVertical`) — um único
//    ponto de injeção em `buildVideoFilter`, então basta confirmar que ele
//    produz o fragmento certo e que ele chega até os grafos que o usam;
//  * rotação do RESULTADO inteiro (aba "Moldura", `FrameSettings.
//    groupRotationQuarterTurns`) — um passe final separado
//    (`groupRotateArgs`), que nunca aparece dentro de `buildVideoFilter`.

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

  group('buildVideoFilter — rotação/espelhamento do conteúdo', () {
    test('sem rotação nem flip, nenhum fragmento aparece', () {
      final settings = ConversionSettings(startSeconds: 0, endSeconds: 5);
      final filter = ffmpeg.buildVideoFilter(settings, _video);
      expect(filter, isNot(contains('transpose')));
      expect(filter, isNot(contains('hflip')));
      expect(filter, isNot(contains('vflip')));
    });

    test('90° horário usa transpose=1 puro', () {
      final settings = ConversionSettings(
        startSeconds: 0,
        endSeconds: 5,
        rotationQuarterTurns: 1,
      );
      expect(
        ffmpeg.buildVideoFilter(settings, _video),
        contains('transpose=1'),
      );
    });

    test('180° usa duas rotações puras de 90° (transpose=1,transpose=1)', () {
      final settings = ConversionSettings(
        startSeconds: 0,
        endSeconds: 5,
        rotationQuarterTurns: 2,
      );
      expect(
        ffmpeg.buildVideoFilter(settings, _video),
        contains('transpose=1,transpose=1'),
      );
    });

    test('90° anti-horário usa transpose=2 puro', () {
      final settings = ConversionSettings(
        startSeconds: 0,
        endSeconds: 5,
        rotationQuarterTurns: 3,
      );
      expect(
        ffmpeg.buildVideoFilter(settings, _video),
        contains('transpose=2'),
      );
    });

    test('flip horizontal/vertical viram hflip/vflip', () {
      final settings = ConversionSettings(
        startSeconds: 0,
        endSeconds: 5,
        flipHorizontal: true,
        flipVertical: true,
      );
      final filter = ffmpeg.buildVideoFilter(settings, _video);
      expect(filter, contains('hflip'));
      expect(filter, contains('vflip'));
    });

    test('o fragmento vem depois do crop e antes do fps/setpts', () {
      final settings = ConversionSettings(
        startSeconds: 0,
        endSeconds: 5,
        speed: 2.0,
        crop: CropRect.centeredIn(_video.width, _video.height, 1),
        rotationQuarterTurns: 1,
      );
      final filter = ffmpeg.buildVideoFilter(settings, _video);
      final parts = filter.split(',');
      final cropIndex = parts.indexWhere((p) => p.startsWith('crop='));
      final transposeIndex = parts.indexOf('transpose=1');
      final setptsIndex = parts.indexWhere((p) => p.startsWith('setpts='));
      final fpsIndex = parts.indexWhere((p) => p.startsWith('fps='));

      expect(cropIndex, greaterThanOrEqualTo(0));
      expect(transposeIndex, greaterThan(cropIndex));
      expect(setptsIndex, greaterThan(transposeIndex));
      expect(fpsIndex, greaterThan(setptsIndex));
    });

    test('a rotação de conteúdo nunca usa transpose=0 nem transpose=3', () {
      // transpose=0/3 embutem um flip vertical extra — não servem para uma
      // rotação pura de 90°.
      for (final turns in [1, 2, 3]) {
        final settings = ConversionSettings(
          startSeconds: 0,
          endSeconds: 5,
          rotationQuarterTurns: turns,
        );
        final filter = ffmpeg.buildVideoFilter(settings, _video);
        expect(filter, isNot(contains('transpose=0')));
        expect(filter, isNot(contains('transpose=3')));
      }
    });
  });

  group('rotação de conteúdo chega aos caminhos "sem moldura"', () {
    test('webpArgs propaga o fragmento até o -lavfi', () {
      final settings = ConversionSettings(
        startSeconds: 0,
        endSeconds: 5,
        rotationQuarterTurns: 1,
      );
      final args = ffmpeg.webpArgs(
        video: _video,
        settings: settings,
        outputPath: '/tmp/saida.webp',
      );
      expect(_lavfiOf(args), contains('transpose=1'));
    });
  });

  group('rotação de conteúdo chega à moldura de imagem', () {
    final art = ImageFrameLibrary.bundled.first;

    test('imageFramedGifArgs propaga o fragmento até o -lavfi', () {
      final settings = ConversionSettings(
        startSeconds: 0,
        endSeconds: 5,
        rotationQuarterTurns: 1,
        frame: FrameSettings(imageFrame: art),
      );
      final args = ffmpeg.imageFramedGifArgs(
        video: _video,
        settings: settings,
        artPath: '/tmp/arte.png',
        outputPath: '/tmp/saida.gif',
      );
      expect(_lavfiOf(args), contains('transpose=1'));
    });

    test('webpImageFramedArgs propaga o fragmento até o -lavfi', () {
      final settings = ConversionSettings(
        startSeconds: 0,
        endSeconds: 5,
        flipHorizontal: true,
        frame: FrameSettings(imageFrame: art),
      );
      final args = ffmpeg.webpImageFramedArgs(
        video: _video,
        settings: settings,
        artPath: '/tmp/arte.png',
        outputPath: '/tmp/saida.webp',
      );
      expect(_lavfiOf(args), contains('hflip'));
    });
  });

  group('groupRotateArgs — girar o resultado inteiro já pronto', () {
    test('90° horário usa transpose=1 puro', () {
      final settings = ConversionSettings(
        startSeconds: 0,
        endSeconds: 5,
        frame: const FrameSettings(groupRotationQuarterTurns: 1),
      );
      final args = ffmpeg.groupRotateArgs(
        settings: settings,
        inputPath: '/tmp/entrada.gif',
        outputPath: '/tmp/saida.gif',
      );
      expect(_lavfiOf(args), contains('transpose=1'));
      expect(args.first, '-y');
      expect(args[args.indexOf('-i') + 1], '/tmp/entrada.gif');
      expect(args.last, '/tmp/saida.gif');
    });

    test('180° usa transpose=1,transpose=1; 270° usa transpose=2', () {
      final base = ConversionSettings(startSeconds: 0, endSeconds: 5);

      final at180 = ffmpeg.groupRotateArgs(
        settings: base.copyWith(
          frame: base.frame.copyWith(groupRotationQuarterTurns: 2),
        ),
        inputPath: '/tmp/a.gif',
        outputPath: '/tmp/b.gif',
      );
      expect(_lavfiOf(at180), contains('transpose=1,transpose=1'));

      final at270 = ffmpeg.groupRotateArgs(
        settings: base.copyWith(
          frame: base.frame.copyWith(groupRotationQuarterTurns: 3),
        ),
        inputPath: '/tmp/a.gif',
        outputPath: '/tmp/b.gif',
      );
      expect(_lavfiOf(at270), contains('transpose=2'));
    });

    test('branch GIF regera a paleta (palettegen/paletteuse)', () {
      final settings = ConversionSettings(
        startSeconds: 0,
        endSeconds: 5,
        frame: const FrameSettings(groupRotationQuarterTurns: 1),
      );
      final args = ffmpeg.groupRotateArgs(
        settings: settings,
        inputPath: '/tmp/entrada.gif',
        outputPath: '/tmp/saida.gif',
      );
      final graph = _lavfiOf(args);
      expect(graph, contains('palettegen'));
      expect(graph, contains('paletteuse'));
    });

    test('branch WebP usa libwebp direto, sem nenhuma paleta', () {
      final settings = ConversionSettings(
        startSeconds: 0,
        endSeconds: 5,
        format: OutputFormat.webp,
        frame: const FrameSettings(groupRotationQuarterTurns: 1),
      );
      final args = ffmpeg.groupRotateArgs(
        settings: settings,
        inputPath: '/tmp/entrada.webp',
        outputPath: '/tmp/saida.webp',
      );
      final graph = _lavfiOf(args);
      expect(graph, isNot(contains('palettegen')));
      expect(graph, isNot(contains('paletteuse')));
      expect(args, contains('libwebp'));
    });

    test('transparência ativa reserva/alfa; sem moldura, opaco', () {
      final withFrame = ConversionSettings(
        startSeconds: 0,
        endSeconds: 5,
        frame: const FrameSettings(
          style: FrameStyle.medium,
          thicknessAtReference: 10,
          transparentBackground: true,
          groupRotationQuarterTurns: 1,
        ),
      );
      final framedArgs = ffmpeg.groupRotateArgs(
        settings: withFrame,
        inputPath: '/tmp/a.gif',
        outputPath: '/tmp/b.gif',
      );
      final framedGraph = _lavfiOf(framedArgs);
      expect(framedGraph, contains('reserve_transparent=1'));
      expect(framedGraph, contains('alpha_threshold=128'));

      final withoutFrame = ConversionSettings(
        startSeconds: 0,
        endSeconds: 5,
        frame: const FrameSettings(groupRotationQuarterTurns: 1),
      );
      final noFrameArgs = ffmpeg.groupRotateArgs(
        settings: withoutFrame,
        inputPath: '/tmp/a.gif',
        outputPath: '/tmp/b.gif',
      );
      final noFrameGraph = _lavfiOf(noFrameArgs);
      expect(noFrameGraph, isNot(contains('reserve_transparent')));
      expect(noFrameGraph, isNot(contains('alpha_threshold')));
    });
  });
}
